# Health Insights and Lifetime Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record a year of daily battery usage, estimate health trends from measured data only, compare charging habits with a relative stress model, and show the results in the app and `vbctl health`.

**Architecture:** Pure models in `BatteryCore` (snapshot fields, stress model, daily ledger, segments, Theil–Sen trend, sleep events, advisor, report, text). File storage in `BatteryPlatform` (`JSONFile`, `HealthStore`, `HealthRecorder`, `SleepStore`). The app feeds samples every refresh and sleep/wake events; the CLI only reads.

**Tech Stack:** Swift 6 toolchain in Swift 5 mode, SwiftPM, Swift Testing, SwiftUI/AppKit, CryptoKit.

**Spec:** `docs/superpowers/specs/2026-10-20-health-insights-design.md`

## Global Constraints

- Local build/test: `SW=/Users/youngmin/Documents/Codex/2026-10-18/a/work/swift-local; $SW test --disable-xctest` (CI uses `swift test --disable-xctest`).
- Never change the real charge limit; never quit or relaunch the user's running VibeBattery or other apps.
- No personal device values (serials, capacities, cycles, health) in Git; tests use synthetic values.
- Data files live in `AppPaths.directory`, mode 0600, directory 0700.
- Collection is disabled when `preferences.backgroundHistory` is false.
- User-facing text is Korean; commits are English conventional style with the session trailer.
- Code style: match the compact style of the surrounding files.

## Review Focus

- A sample whose timestamp is earlier than the previous one (clock change) must not corrupt totals and later samples must keep recording — Task 3 test `clockGoingBackwardsDropsInterval` + Task 6 test `recorderKeepsRecordingAfterClockChange`.
- A huge Theil–Sen extrapolation (almost-flat decline) must not crash on `Int` conversion — Task 4 test `nearlyFlatDeclineIsBeyondHorizon`.
- A machine without a battery (CI runner) must make `vbctl health` print and exit 0 — Task 7 CI step and test `reportWithoutBatteryHasNoHealth`.
- A corrupt `health.json` must not stop the app; it is moved aside and recording restarts — Task 6 test `corruptFileIsMovedAside`.
- Integer SoC makes short sleeps look like heavy drain — Task 5 test `shortSleepHasNoDrain`.

---

### Task 1: Snapshot health fields

**Files:**
- Modify: `Sources/BatteryCore/BatterySnapshot.swift`
- Test: `Tests/BatteryCoreTests/HealthLedgerTests.swift` (new)

**Interfaces:**
- Produces: `BatterySnapshot.healthPrecise: Double?`, `designCapacity: Int?`, `designCycles: Int?`, `batteryID: String?` (16 hex chars).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import BatteryCore
struct SnapshotHealthTests {
    @Test func decodesPreciseHealthDesignAndHashedSerial() {
        let s=BatterySnapshot.decode(["CycleCount":12,"DesignCycleCount9C":1000,"Serial":"TESTSERIAL","BatteryData":["DesignCapacity":5000,"NominalChargeCapacity":4512]])
        #expect(s.healthPrecise==90.2);#expect(s.health==90)
        #expect(s.designCapacity==5000);#expect(s.designCycles==1000)
        #expect(s.batteryID?.count==16);#expect(s.batteryID != nil && !s.batteryID!.contains("TEST"))
        #expect(BatterySnapshot.decode(["Serial":"TESTSERIAL"]).batteryID==s.batteryID)
    }
    @Test func legacyHistorySampleStillDecodes() throws {
        let old=#"{"timestamp":0,"percent":50,"health":88,"cycles":10,"onAC":true,"charging":false}"#
        let s=try JSONDecoder().decode(BatterySnapshot.self,from:Data(old.utf8))
        #expect(s.percent==50);#expect(s.healthPrecise==nil);#expect(s.batteryID==nil)
    }
}
```

- [ ] **Step 2: Run** `$SW test --disable-xctest --filter SnapshotHealthTests` — Expected: compile failure, `healthPrecise` missing.

- [ ] **Step 3: Implement** — add to `BatterySnapshot` after `temperatureSource`:

```swift
    public var healthPrecise: Double?
    public var designCapacity: Int?
    public var designCycles: Int?
    public var batteryID: String?
```

In `decode`, replace the health line and add identity fields:

```swift
        if let design, let full, design > 0, full > 0 {
            result.health = min(100, Int(full / design * 100))
            let precise = full / design * 100
            if precise < 150 { result.healthPrecise = (precise * 10).rounded() / 10 }
        }
        if let design, design > 0 { result.designCapacity = Int(design) }
        result.designCycles = (values["DesignCycleCount9C"] as? NSNumber)?.intValue
        if let serial = values["Serial"] as? String, !serial.isEmpty { result.batteryID = BatteryIdentity.hash(serial) }
```

and at file end (with `import CryptoKit` at top):

```swift
/// Stable local identifier for battery replacement detection; the serial itself is never stored.
enum BatteryIdentity {
    static func hash(_ serial: String) -> String { SHA256.hash(data: Data(serial.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined() }
}
```

- [ ] **Step 4: Run** the filter again — Expected: PASS; full suite green.
- [ ] **Step 5: Commit** `feat: record precise health and battery identity in snapshots`

### Task 2: Stress model

**Files:**
- Create: `Sources/BatteryCore/StressModel.swift`
- Test: `Tests/BatteryCoreTests/StressModelTests.swift`

**Interfaces:**
- Produces: `StressModel.rate(soc: Double, temperature: Double) -> Double` (25°C·40% = 1.0).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import BatteryCore
struct StressModelTests {
    @Test func reproducesBU808Table() {
        #expect(abs(StressModel.rate(soc:40,temperature:25)-1)<1e-9)
        #expect(abs(StressModel.rate(soc:100,temperature:25)-5)<1e-9)
        #expect(abs(StressModel.rate(soc:100,temperature:40)-8.75)<1e-9)
        #expect(abs(StressModel.rate(soc:40,temperature:0)-0.5)<1e-9)
        #expect(abs(StressModel.rate(soc:80,temperature:25)-11.0/3.0)<1e-9)
    }
    @Test func increasesWithChargeAndTemperature() {
        var previous=0.0
        for soc in stride(from:40.0,through:100,by:5) { let r=StressModel.rate(soc:soc,temperature:30);#expect(r>previous);previous=r }
        previous=0
        for t in stride(from:0.0,through:60,by:5) { let r=StressModel.rate(soc:80,temperature:t);#expect(r>previous);previous=r }
    }
    @Test func clampsOutsideTheTable() {
        #expect(StressModel.rate(soc:10,temperature:25)==StressModel.rate(soc:40,temperature:25))
        #expect(StressModel.rate(soc:80,temperature:-10)==StressModel.rate(soc:80,temperature:0))
        #expect(StressModel.rate(soc:80,temperature:90)==StressModel.rate(soc:80,temperature:60))
    }
}
```

(The 80% line is 11/3 = (4 + 16·40/60)/4.)

- [ ] **Step 2: Run** `--filter StressModelTests` — Expected: compile failure, `StressModel` missing.
- [ ] **Step 3: Implement**

```swift
import Foundation
/// Relative calendar-aging stress from BU-808 Table 3 (capacity lost after one year of storage).
/// General Li-ion research, not validated for any specific cell; used only for comparisons.
public enum StressModel {
    static let table: [(t: Double, low: Double, high: Double)] = [(0, 2, 6), (25, 4, 20), (40, 15, 35)]
    static let reference = 4.0
    public static func rate(soc: Double, temperature: Double) -> Double {
        let s = min(max(soc, 40), 100), t = min(max(temperature, 0), 60)
        func loss(_ row: (t: Double, low: Double, high: Double)) -> Double { row.low + (row.high - row.low) * (s - 40) / 60 }
        let (a, b) = t <= 25 ? (table[0], table[1]) : (table[1], table[2])
        let f = (t - a.t) / (b.t - a.t)
        return exp(log(loss(a)) + (log(loss(b)) - log(loss(a))) * f) / reference
    }
}
```

- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat: add relative battery stress model`

### Task 3: Daily ledger and battery segments

**Files:**
- Create: `Sources/BatteryCore/HealthLedger.swift`
- Test: `Tests/BatteryCoreTests/HealthLedgerTests.swift` (append suite)

**Interfaces:**
- Consumes: `StressModel.rate`, snapshot fields from Task 1.
- Produces: `DailyUsage` (Codable, Equatable; fields below), `HealthLedger.record(_:after:into:calendar:) -> [DailyUsage]`, `HealthLedger.maxGap = 300`, `HealthLedger.retentionDays = 400`, `BatterySegment.current(_:) -> [DailyUsage]`.

- [ ] **Step 1: Write the failing tests**

```swift
func seoul() -> Calendar { var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"Asia/Seoul")!;return c }
func sample(_ t:Date,percent:Int?=96,temp:Double?=36,ac:Bool=true,health:Double?=90,cycles:Int?=10,design:Int?=5000,id:String?="a") -> BatterySnapshot {
    var s=BatterySnapshot();s.timestamp=t;s.percent=percent;s.temperature=temp;s.onAC=ac;s.healthPrecise=health;s.cycles=cycles;s.designCapacity=design;s.batteryID=id;return s
}
func at(_ y:Int,_ m:Int,_ d:Int,_ h:Int=12,_ min:Int=0,_ sec:Int=0) -> Date { seoul().date(from:DateComponents(year:y,month:m,day:d,hour:h,minute:min,second:sec))! }
struct HealthLedgerTests {
    @Test func accumulatesIntervalWithPreviousState() {
        let c=seoul(),a=sample(at(2026,10,20)),b=sample(at(2026,10,20,12,0,30),percent:50,temp:20,ac:false,health:89.9)
        let days=HealthLedger.record(b,after:a,into:[],calendar:c)
        #expect(days.count==1);let d=days[0]
        #expect(d.day==c.startOfDay(for:a.timestamp))
        #expect(d.observed==30);#expect(d.onAC==30);#expect(d.soc90==30);#expect(d.soc95==30);#expect(d.hot35==30);#expect(d.hot40==0)
        #expect(d.averageSoC==96);#expect(d.maxTemperature==36);#expect(d.stressSeconds==30)
        #expect(abs(d.stress-StressModel.rate(soc:96,temperature:36)*30)<1e-9)
        #expect(abs(d.stressAt80-StressModel.rate(soc:80,temperature:36)*30)<1e-9)
        #expect(d.health==89.9);#expect(d.cycles==10);#expect(d.designCapacity==5000);#expect(d.batteryID=="a")
    }
    @Test func longGapIsUnknownButDayValuesUpdate() {
        let days=HealthLedger.record(sample(at(2026,10,20,12,10)),after:sample(at(2026,10,20)),into:[],calendar:seoul())
        #expect(days.count==1);#expect(days[0].observed==0);#expect(days[0].health==90)
    }
    @Test func splitsAtLocalMidnight() {
        let days=HealthLedger.record(sample(at(2026,10,21,0,0,20)),after:sample(at(2026,10,20,23,59,50)),into:[],calendar:seoul())
        #expect(days.count==2);#expect(days[0].observed==10);#expect(days[1].observed==20)
    }
    @Test func clockGoingBackwardsDropsInterval() {
        let first=HealthLedger.record(sample(at(2026,10,20,12,0,30)),after:sample(at(2026,10,20)),into:[],calendar:seoul())
        let after=HealthLedger.record(sample(at(2026,10,20,11),health:50),after:sample(at(2026,10,20,12,0,30)),into:first,calendar:seoul())
        #expect(after==first)
    }
    @Test func missingSensorsSkipTheirTotals() {
        let d=HealthLedger.record(sample(at(2026,10,20,12,0,30)),after:sample(at(2026,10,20),temp:nil),into:[],calendar:seoul())[0]
        #expect(d.observed==30);#expect(d.soc95==30);#expect(d.hot35==0);#expect(d.stressSeconds==0);#expect(d.maxTemperature==nil)
        let e=HealthLedger.record(sample(at(2026,10,20,12,0,30)),after:sample(at(2026,10,20),percent:nil),into:[],calendar:seoul())[0]
        #expect(e.socSeconds==0);#expect(e.hot35==30);#expect(e.stressSeconds==0)
    }
    @Test func missingValuesKeepEarlierDayValues() {
        let first=HealthLedger.record(sample(at(2026,10,20)),after:nil,into:[],calendar:seoul())
        let d=HealthLedger.record(sample(at(2026,10,20,13),health:nil,cycles:nil,id:nil),after:nil,into:first,calendar:seoul())[0]
        #expect(d.health==90);#expect(d.cycles==10);#expect(d.batteryID=="a")
    }
    @Test func keepsFourHundredDays() {
        let c=seoul();var days:[DailyUsage]=[]
        for i in 0..<401 { days.append(DailyUsage(day:c.date(byAdding:.day,value:-i-1,to:c.startOfDay(for:at(2026,10,20)))!)) }
        days.sort { $0.day<$1.day }
        let out=HealthLedger.record(sample(at(2026,10,20)),after:nil,into:days,calendar:c)
        #expect(out.count==401);#expect(out.first!.day==c.date(byAdding:.day,value:-400,to:c.startOfDay(for:at(2026,10,20)))!)
    }
    @Test func segmentStartsAtBatteryReplacement() {
        func day(_ n:Int,id:String?,design:Int?,cycles:Int?) -> DailyUsage { var d=DailyUsage(day:Date(timeIntervalSince1970:Double(n)*86400));d.batteryID=id;d.designCapacity=design;d.cycles=cycles;return d }
        let swapped=[day(0,id:"a",design:5000,cycles:300),day(1,id:"b",design:5000,cycles:1),day(2,id:nil,design:nil,cycles:2)]
        #expect(BatterySegment.current(swapped).map(\.cycles)==[1,2])
        let resized=[day(0,id:nil,design:5000,cycles:3),day(1,id:nil,design:6000,cycles:4)]
        #expect(BatterySegment.current(resized).count==1)
        let reset=[day(0,id:nil,design:nil,cycles:300),day(1,id:nil,design:nil,cycles:2)]
        #expect(BatterySegment.current(reset).count==1)
        let same=[day(0,id:"a",design:5000,cycles:3),day(1,id:nil,design:nil,cycles:nil),day(2,id:"a",design:5000,cycles:4)]
        #expect(BatterySegment.current(same).count==3)
        #expect(BatterySegment.current([]).isEmpty)
    }
}
```

- [ ] **Step 2: Run** `--filter HealthLedgerTests` — Expected: compile failure, `HealthLedger` missing.
- [ ] **Step 3: Implement**

```swift
import Foundation
/// One local calendar day of time-weighted battery usage. Durations are seconds.
public struct DailyUsage: Codable, Equatable, Sendable {
    public var day: Date
    public var observed = 0.0, onAC = 0.0
    public var soc90 = 0.0, soc95 = 0.0, socSeconds = 0.0, socSum = 0.0
    public var hot35 = 0.0, hot40 = 0.0
    public var maxTemperature: Double?
    public var stressSeconds = 0.0, stress = 0.0, stressAt80 = 0.0
    public var health: Double?
    public var cycles: Int?
    public var designCapacity: Int?
    public var batteryID: String?
    public init(day: Date) { self.day = day }
    public var averageSoC: Double? { socSeconds > 0 ? socSum / socSeconds : nil }
}
public enum HealthLedger {
    public static let maxGap: TimeInterval = 300
    public static let retentionDays = 400
    /// Adds the interval since `previous` (state of the earlier sample), split at local midnight.
    /// Gaps over five minutes stay unknown; a sample older than `previous` is ignored.
    public static func record(_ sample: BatterySnapshot, after previous: BatterySnapshot?, into days: [DailyUsage], calendar: Calendar) -> [DailyUsage] {
        var days = days
        if let p = previous {
            if sample.timestamp < p.timestamp { return days }
            var start = p.timestamp
            if sample.timestamp.timeIntervalSince(start) <= maxGap {
                while start < sample.timestamp {
                    let dayStart = calendar.startOfDay(for: start)
                    let stop = min(sample.timestamp, calendar.date(byAdding: .day, value: 1, to: dayStart)!)
                    let i = slot(dayStart, &days)
                    accumulate(p, seconds: stop.timeIntervalSince(start), into: &days[i])
                    start = stop
                }
            }
        }
        let i = slot(calendar.startOfDay(for: sample.timestamp), &days)
        if let v = sample.healthPrecise { days[i].health = v }
        if let v = sample.cycles { days[i].cycles = v }
        if let v = sample.designCapacity { days[i].designCapacity = v }
        if let v = sample.batteryID { days[i].batteryID = v }
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: sample.timestamp))!
        days.removeAll { $0.day < cutoff }
        return days
    }
    static func slot(_ day: Date, _ days: inout [DailyUsage]) -> Int {
        if let i = days.lastIndex(where: { $0.day == day }) { return i }
        days.append(DailyUsage(day: day)); days.sort { $0.day < $1.day }
        return days.firstIndex { $0.day == day }!
    }
    static func accumulate(_ s: BatterySnapshot, seconds dt: Double, into d: inout DailyUsage) {
        d.observed += dt
        if s.onAC { d.onAC += dt }
        let soc = s.percent.map(Double.init)
        if let p = soc {
            d.socSeconds += dt; d.socSum += p * dt
            if p >= 90 { d.soc90 += dt }
            if p >= 95 { d.soc95 += dt }
        }
        if let t = s.temperature {
            if t >= 35 { d.hot35 += dt }
            if t >= 40 { d.hot40 += dt }
            d.maxTemperature = max(d.maxTemperature ?? t, t)
            if let p = soc {
                d.stressSeconds += dt
                d.stress += StressModel.rate(soc: p, temperature: t) * dt
                d.stressAt80 += StressModel.rate(soc: min(p, 80), temperature: t) * dt
            }
        }
    }
}
public enum BatterySegment {
    /// Days since the most recent battery replacement: a different identifier or design capacity, or a falling cycle count.
    public static func current(_ days: [DailyUsage]) -> [DailyUsage] {
        guard var start = days.indices.last else { return [] }
        var id = days[start].batteryID, design = days[start].designCapacity, cycles = days[start].cycles
        while start > 0 {
            let d = days[start - 1]
            if let a = d.batteryID, let b = id, a != b { break }
            if let a = d.designCapacity, let b = design, a != b { break }
            if let a = d.cycles, let b = cycles, a > b { break }
            id = d.batteryID ?? id; design = d.designCapacity ?? design; cycles = d.cycles ?? cycles
            start -= 1
        }
        return Array(days[start...])
    }
}
```

- [ ] **Step 4: Run** — Expected: PASS; full suite green.
- [ ] **Step 5: Commit** `feat: accumulate daily battery usage and detect battery replacement`

### Task 4: Health trend (Theil–Sen)

**Files:**
- Create: `Sources/BatteryCore/HealthTrend.swift`
- Test: `Tests/BatteryCoreTests/HealthTrendTests.swift`

**Interfaces:**
- Consumes: `DailyUsage`.
- Produces: `TrendStatus` (`collecting(days:points:)`, `alreadyBelow`, `notDeclining`, `beyondHorizon`, `projected(earliest:latest:)`), `CycleProjection { low: Int; high: Int? }`, `HealthTrend { status; cycles: CycleProjection? }`, `HealthTrend.make(_:now:calendar:)`, `HealthTrend.minDays = 30`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import BatteryCore
struct HealthTrendTests {
    let c:Calendar={ var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"UTC")!;return c }()
    let start=Date(timeIntervalSince1970:1_790_000_000)
    func days(_ values:[(Int,Double)],cycles:((Int)->Int?)={ _ in nil }) -> [DailyUsage] {
        values.map { (n,h) in var d=DailyUsage(day:c.date(byAdding:.day,value:n,to:c.startOfDay(for:start))!);d.health=h;d.cycles=cycles(n);return d }
    }
    var now:Date { c.date(byAdding:.day,value:60,to:start)! }
    @Test func collectsUntilThirtyDaysFivePointsAndOnePoint() {
        #expect(HealthTrend.make(days([(0,95),(10,94),(20,93),(25,92.5),(29,92)]),now:now,calendar:c).status == .collecting(days:29,points:5))
        #expect(HealthTrend.make(days([(0,95),(40,94)]),now:now,calendar:c).status == .collecting(days:40,points:2))
        #expect(HealthTrend.make(days([(0,95),(10,94.8),(20,94.9),(30,94.5),(40,94.6)]),now:now,calendar:c).status == .collecting(days:40,points:5))
        #expect(HealthTrend.make([],now:now,calendar:c).status == .collecting(days:0,points:0))
    }
    @Test func linearDeclineProjectsExactDate() {
        let t=HealthTrend.make(days(stride(from:0,through:60,by:5).map { ($0,95-0.02*Double($0)) }),now:now,calendar:c)
        let expected=c.date(byAdding:.day,value:750,to:c.startOfDay(for:start))!
        #expect(t.status == .projected(earliest:expected,latest:expected))
    }
    @Test func outlierBarelyMovesProjection() {
        var v=stride(from:0,through:60,by:5).map { ($0,95-0.02*Double($0)) };v[6].1=60
        guard case .projected(let e,let l)=HealthTrend.make(days(v),now:now,calendar:c).status, let l else { Issue.record("no projection");return }
        let expected=c.date(byAdding:.day,value:750,to:c.startOfDay(for:start))!
        #expect(abs(e.timeIntervalSince(expected))<120*86400);#expect(abs(l.timeIntervalSince(expected))<120*86400);#expect(e<=l)
    }
    @Test func risingOrFlatIsNotDeclining() {
        #expect(HealthTrend.make(days([(0,90),(10,91),(20,90.5),(30,91.5),(40,92)]),now:now,calendar:c).status == .notDeclining)
    }
    @Test func belowThresholdIsReportedFirst() {
        #expect(HealthTrend.make(days([(0,79.5)]),now:now,calendar:c).status == .alreadyBelow)
    }
    @Test func nearlyFlatDeclineIsBeyondHorizon() {
        let t=HealthTrend.make(days(stride(from:0,through:400,by:20).map { ($0,95-Double($0)/400) }),now:now,calendar:c)
        #expect(t.status == .beyondHorizon)
        _=HealthTrend.make(days([(0,95),(10,95-1e-12),(20,94),(30,95),(40,95-2e-12),(50,95)]),now:now,calendar:c)
    }
    @Test func cycleProjectionNeedsSpreadAndOrders() {
        let v=stride(from:0,through:60,by:5).map { ($0,95-0.02*Double($0)) }
        let t=HealthTrend.make(days(v,cycles:{ 100+$0/2 }),now:now,calendar:c)
        #expect(t.cycles != nil);if let p=t.cycles { #expect(p.low<=(p.high ?? Int.max));#expect(p.low>=130) }
        #expect(HealthTrend.make(days(v,cycles:{ 100+$0/20 }),now:now,calendar:c).cycles==nil)
    }
}
```

(The second call only asserts no crash on an extreme extrapolation.)

- [ ] **Step 2: Run** `--filter HealthTrendTests` — Expected: compile failure, `HealthTrend` missing.
- [ ] **Step 3: Implement**

```swift
import Foundation
public enum TrendStatus: Codable, Equatable, Sendable {
    case collecting(days: Int, points: Int)
    case alreadyBelow
    case notDeclining
    case beyondHorizon
    case projected(earliest: Date, latest: Date?)
}
public struct CycleProjection: Codable, Equatable, Sendable { public var low: Int; public var high: Int? }
/// Measured-only health trend. Robust Theil–Sen fit; the range comes from the 25th and 75th percentile pair slopes.
public struct HealthTrend: Codable, Equatable, Sendable {
    public var status: TrendStatus
    public var cycles: CycleProjection?
    public static let threshold = 80.0, minDays = 30, minPoints = 5, minChange = 1.0, horizonDays = 15 * 365
    public static func make(_ days: [DailyUsage], now: Date, calendar: Calendar) -> HealthTrend {
        let points = days.compactMap { d in d.health.map { (day: d.day, health: $0) } }
        guard let first = points.first, let last = points.last else { return HealthTrend(status: .collecting(days: 0, points: 0)) }
        if last.health <= threshold { return HealthTrend(status: .alreadyBelow) }
        let span = calendar.dateComponents([.day], from: first.day, to: last.day).day ?? 0
        let ys = points.map(\.health)
        guard span >= minDays, points.count >= minPoints, ys.max()! - ys.min()! >= minChange else {
            return HealthTrend(status: .collecting(days: span, points: points.count))
        }
        let xy = points.map { (x: Double(calendar.dateComponents([.day], from: first.day, to: $0.day).day ?? 0), y: $0.health) }
        guard let mid = TheilSen.fit(xy, quantile: 0.5), mid.slope < 0 else { return HealthTrend(status: .notDeclining) }
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now)!
        func reach(_ q: Double) -> Date? {
            guard let f = TheilSen.fit(xy, quantile: q), f.slope < 0 else { return nil }
            let x = min((threshold - f.intercept) / f.slope, Double(horizonDays * 4))
            return max(calendar.date(byAdding: .day, value: Int(x.rounded()), to: first.day)!, now)
        }
        guard let early = reach(0.25), early <= horizon else { return HealthTrend(status: .beyondHorizon, cycles: cycleProjection(days)) }
        let late = reach(0.75).flatMap { $0 <= horizon ? $0 : nil }
        return HealthTrend(status: .projected(earliest: early, latest: late), cycles: cycleProjection(days))
    }
    static func cycleProjection(_ days: [DailyUsage]) -> CycleProjection? {
        let xy = days.compactMap { d -> (x: Double, y: Double)? in guard let c = d.cycles, let h = d.health else { return nil }; return (Double(c), h) }
        let cycles = Set(xy.map(\.x))
        guard cycles.count >= minPoints, let lo = cycles.min(), let hi = cycles.max(), hi - lo >= 10 else { return nil }
        func reach(_ q: Double) -> Int? {
            guard let f = TheilSen.fit(xy, quantile: q), f.slope < 0 else { return nil }
            let x = (threshold - f.intercept) / f.slope
            return x <= 10000 ? max(Int(x.rounded()), Int(hi)) : nil
        }
        guard let low = reach(0.25) else { return nil }
        return CycleProjection(low: low, high: reach(0.75))
    }
}
enum TheilSen {
    struct Fit { var slope: Double; var intercept: Double }
    static func fit(_ p: [(x: Double, y: Double)], quantile q: Double) -> Fit? {
        var slopes: [Double] = []
        for i in p.indices { for j in p.indices where j > i && p[j].x != p[i].x { slopes.append((p[j].y - p[i].y) / (p[j].x - p[i].x)) } }
        guard !slopes.isEmpty else { return nil }
        let m = percentile(slopes.sorted(), q)
        return Fit(slope: m, intercept: percentile(p.map { $0.y - m * $0.x }.sorted(), 0.5))
    }
    static func percentile(_ s: [Double], _ q: Double) -> Double {
        let pos = q * Double(s.count - 1), lo = Int(pos.rounded(.down)), hi = min(lo + 1, s.count - 1)
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }
}
```

`HealthTrend` needs a memberwise init with a default for `cycles`: declare `public init(status: TrendStatus, cycles: CycleProjection? = nil) { self.status = status; self.cycles = cycles }`.

- [ ] **Step 4: Run** — Expected: PASS; full suite green.
- [ ] **Step 5: Commit** `feat: project health trend from measured history`

### Task 5: Sleep events, usage summary, advisor, report and text

**Files:**
- Create: `Sources/BatteryCore/HealthReport.swift`
- Test: `Tests/BatteryCoreTests/HealthReportTests.swift`

**Interfaces:**
- Consumes: `DailyUsage`, `BatterySegment`, `HealthTrend`.
- Produces: `SleepEvent(before:after:)`, `.drainPerHour`, `.isHigh`; `UsageSummary.make(_:)`; `AdvisorContext(limit:heatEnabled:)`; `SuggestionKind {chargeLimit, heatHold, sleepDrain}`; `Suggestion {kind; message}`; `HealthAdvisor.suggestions(week:sleeps:context:)`; `HealthReport.make(snapshot:days:sleeps:context:now:calendar:)` with `health, cycles, designCycles, marginTo80, trend, week, month, sleeps (newest first), suggestions`; `HealthText.trend(_:calendar:)`, `HealthText.stress(_:)`, `HealthText.lines(_:calendar:) -> [String]`, `HealthText.caveat`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import BatteryCore
struct HealthReportTests {
    let c:Calendar={ var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"UTC")!;return c }()
    let now=Date(timeIntervalSince1970:1_790_000_000)
    func snap(_ t:Date,_ p:Int,ac:Bool=false) -> BatterySnapshot { var s=BatterySnapshot();s.timestamp=t;s.percent=p;s.onAC=ac;return s }
    func event(hours:Double,from a:Int,to b:Int,ac:Bool=false) -> SleepEvent { SleepEvent(before:snap(now,a,ac:ac),after:snap(now.addingTimeInterval(hours*3600),b)) }
    func day(_ ago:Int,soc95:Double=0,hot35:Double=0,stress:Double=0,at80:Double=0) -> DailyUsage {
        var d=DailyUsage(day:c.date(byAdding:.day,value:-ago,to:c.startOfDay(for:now))!);d.observed=3600;d.soc95=soc95;d.hot35=hot35;d.stress=stress;d.stressAt80=at80;d.stressSeconds=stress>0 ? 100:0;return d
    }
    @Test func sleepDrainPerHour() {
        #expect(event(hours:8,from:80,to:76).drainPerHour==0.5)
        #expect(event(hours:2,from:80,to:77).isHigh)
        #expect(!event(hours:8,from:80,to:76).isHigh)
    }
    @Test func shortSleepHasNoDrain() { #expect(event(hours:0.9,from:80,to:79).drainPerHour==nil) }
    @Test func sleepOnAdapterOrGainHasNoDrain() {
        #expect(event(hours:8,from:80,to:70,ac:true).drainPerHour==nil)
        #expect(event(hours:8,from:70,to:80).drainPerHour==nil)
    }
    @Test func summaryAddsDaysAndComparesCap() {
        let s=UsageSummary.make([day(0,soc95:3600,stress:500,at80:350),day(1,soc95:1800,stress:500,at80:350)])
        #expect(s.days==2);#expect(s.observed==7200);#expect(s.soc95==5400);#expect(s.averageStress==5)
        #expect(abs((s.reductionAt80 ?? 0)-0.3)<1e-9)
        #expect(UsageSummary.make([day(0)]).reductionAt80==nil)
    }
    @Test func advisorThresholdsAndOrder() {
        let week=UsageSummary.make([day(0,soc95:6*3600,hot35:2*3600)])
        let all=HealthAdvisor.suggestions(week:week,sleeps:[event(hours:2,from:80,to:77)],context:AdvisorContext(limit:nil,heatEnabled:false))
        #expect(all.map(\.kind)==[.chargeLimit,.heatHold,.sleepDrain])
        let under=UsageSummary.make([day(0,soc95:6*3600-60,hot35:2*3600-60)])
        #expect(HealthAdvisor.suggestions(week:under,sleeps:[],context:AdvisorContext(limit:nil,heatEnabled:false)).isEmpty)
        #expect(HealthAdvisor.suggestions(week:week,sleeps:[],context:AdvisorContext(limit:80,heatEnabled:true)).isEmpty)
        #expect(HealthAdvisor.suggestions(week:week,sleeps:[],context:AdvisorContext(limit:85,heatEnabled:true)).map(\.kind)==[.chargeLimit])
    }
    @Test func advisorOnlyLooksAtFiveRecentSleeps() {
        let old=[event(hours:2,from:80,to:77)]+Array(repeating:event(hours:8,from:80,to:79),count:5)
        #expect(HealthAdvisor.suggestions(week:UsageSummary.make([]),sleeps:old,context:AdvisorContext(limit:80,heatEnabled:true)).isEmpty)
    }
    @Test func reportUsesWindowsAndCurrentBattery() {
        var b=BatterySnapshot();b.healthPrecise=88.5;b.cycles=300;b.designCycles=1000
        var replaced=day(10);replaced.batteryID="old";replaced.health=70
        var current=day(0,soc95:60);current.batteryID="new";current.health=88.5
        let r=HealthReport.make(snapshot:b,days:[replaced,day(8,soc95:999),current],sleeps:[event(hours:8,from:80,to:76),event(hours:9,from:80,to:70)],context:AdvisorContext(limit:80,heatEnabled:true),now:now,calendar:c)
        #expect(r.health==88.5);#expect(r.marginTo80==8.5);#expect(r.cycles==300);#expect(r.designCycles==1000)
        #expect(r.week.days==1);#expect(r.week.soc95==60);#expect(r.month.days==3)
        #expect(r.trend.status == .collecting(days:0,points:1))
        #expect(r.sleeps.first?.endPercent==70)
    }
    @Test func reportWithoutBatteryHasNoHealth() {
        let r=HealthReport.make(snapshot:BatterySnapshot(),days:[],sleeps:[],context:AdvisorContext(limit:nil,heatEnabled:false),now:now,calendar:c)
        #expect(r.health==nil);#expect(r.marginTo80==nil);#expect(HealthText.lines(r,calendar:c).first=="배터리 정보 없음")
    }
    @Test func textDescribesStatus() {
        #expect(HealthText.trend(HealthTrend(status:.collecting(days:12,points:9)),calendar:c)=="데이터 수집 중 (12/30일)")
        #expect(HealthText.trend(HealthTrend(status:.beyondHorizon),calendar:c)=="80% 도달 예상: 15년 이상")
        let e=c.date(from:DateComponents(year:2028,month:3,day:2))!
        #expect(HealthText.trend(HealthTrend(status:.projected(earliest:e,latest:nil)),calendar:c)=="80% 도달 예상: 2028년 3월 ~ 알 수 없음")
        #expect(HealthText.stress(UsageSummary.make([day(0,stress:500,at80:365)]))=="상한 80%였다면 스트레스 −27%")
        #expect(HealthText.stress(UsageSummary.make([day(0,stress:500,at80:499)]))=="이미 80% 이하로 유지 중")
        #expect(HealthText.stress(UsageSummary.make([]))=="측정 중")
    }
}
```

The `replaced` day has a different `batteryID`, so the trend sees only the current day: `.collecting(days:0, points:1)` (without segmenting it would be `.collecting(days:10, points:2)`).

- [ ] **Step 2: Run** `--filter HealthReportTests` — Expected: compile failure, `SleepEvent` missing.
- [ ] **Step 3: Implement**

```swift
import Foundation
public struct SleepEvent: Codable, Equatable, Sendable {
    public var start: Date, end: Date
    public var startPercent: Int?, endPercent: Int?
    public var onAC: Bool
    public static let minimumDuration: TimeInterval = 3600, highDrain = 1.0
    public init(before: BatterySnapshot, after: BatterySnapshot) {
        start = before.timestamp; end = after.timestamp; startPercent = before.percent; endPercent = after.percent; onAC = before.onAC || after.onAC
    }
    /// Percent per hour on battery; nil on adapter, for sleeps under an hour (integer percent exaggerates them) or when charge rose.
    public var drainPerHour: Double? {
        let seconds = end.timeIntervalSince(start)
        guard !onAC, seconds >= Self.minimumDuration, let a = startPercent, let b = endPercent, b <= a else { return nil }
        return Double(a - b) / (seconds / 3600)
    }
    public var isHigh: Bool { (drainPerHour ?? 0) > Self.highDrain }
}
public struct UsageSummary: Codable, Equatable, Sendable {
    public var days = 0
    public var observed = 0.0, onAC = 0.0, soc90 = 0.0, soc95 = 0.0, hot35 = 0.0, hot40 = 0.0
    public var maxTemperature: Double?, averageSoC: Double?, averageStress: Double?
    /// Fraction of stress removed if charge never exceeded 80%.
    public var reductionAt80: Double?
    public static func make(_ days: [DailyUsage]) -> UsageSummary {
        var s = UsageSummary(); s.days = days.count
        var socSeconds = 0.0, socSum = 0.0, stressSeconds = 0.0, stress = 0.0, at80 = 0.0
        for d in days {
            s.observed += d.observed; s.onAC += d.onAC; s.soc90 += d.soc90; s.soc95 += d.soc95; s.hot35 += d.hot35; s.hot40 += d.hot40
            if let t = d.maxTemperature { s.maxTemperature = max(s.maxTemperature ?? t, t) }
            socSeconds += d.socSeconds; socSum += d.socSum; stressSeconds += d.stressSeconds; stress += d.stress; at80 += d.stressAt80
        }
        if socSeconds > 0 { s.averageSoC = socSum / socSeconds }
        if stressSeconds > 0 { s.averageStress = stress / stressSeconds }
        if stress > 0 { s.reductionAt80 = 1 - at80 / stress }
        return s
    }
}
public struct AdvisorContext: Sendable {
    /// Active charge limit, or nil when no limit is enabled.
    public var limit: Int?
    public var heatEnabled: Bool
    public init(limit: Int?, heatEnabled: Bool) { self.limit = limit; self.heatEnabled = heatEnabled }
}
public enum SuggestionKind: String, Codable, Sendable { case chargeLimit, heatHold, sleepDrain }
public struct Suggestion: Codable, Equatable, Sendable { public var kind: SuggestionKind; public var message: String }
public enum HealthAdvisor {
    public static func suggestions(week: UsageSummary, sleeps: [SleepEvent], context: AdvisorContext) -> [Suggestion] {
        var out: [Suggestion] = []
        func hours(_ s: Double) -> String { String(format: "%.1f", s / 3600) }
        if week.soc95 >= 6 * 3600, (context.limit ?? 100) > 80 {
            out.append(Suggestion(kind: .chargeLimit, message: "최근 7일 중 \(hours(week.soc95))시간을 잔량 95% 이상에서 보냈습니다. 충전 상한 80%를 권장합니다."))
        }
        if week.hot35 >= 2 * 3600, !context.heatEnabled {
            out.append(Suggestion(kind: .heatHold, message: "최근 7일 중 \(hours(week.hot35))시간 동안 배터리가 35°C 이상이었습니다. 과열 보류를 켜는 것을 권장합니다."))
        }
        if let worst = sleeps.suffix(5).compactMap(\.drainPerHour).max(), worst > SleepEvent.highDrain {
            out.append(Suggestion(kind: .sleepDrain, message: String(format: "최근 잠자기 중 시간당 %.1f%% 소모가 있었습니다. 잠자기를 막는 앱이 있는지 확인하세요.", worst)))
        }
        return Array(out.prefix(3))
    }
}
public struct HealthReport: Codable, Sendable {
    public var generated: Date
    public var health: Double?, marginTo80: Double?
    public var cycles: Int?, designCycles: Int?
    public var trend: HealthTrend
    public var week: UsageSummary, month: UsageSummary
    public var sleeps: [SleepEvent]
    public var suggestions: [Suggestion]
    public static func make(snapshot: BatterySnapshot, days: [DailyUsage], sleeps: [SleepEvent], context: AdvisorContext, now: Date, calendar: Calendar) -> HealthReport {
        func window(_ n: Int) -> [DailyUsage] {
            let from = calendar.date(byAdding: .day, value: -(n - 1), to: calendar.startOfDay(for: now))!
            return days.filter { $0.day >= from }
        }
        let health = snapshot.healthPrecise ?? snapshot.health.map(Double.init)
        let week = UsageSummary.make(window(7))
        return HealthReport(generated: now, health: health, marginTo80: health.map { $0 - 80 }, cycles: snapshot.cycles, designCycles: snapshot.designCycles,
                            trend: HealthTrend.make(BatterySegment.current(days), now: now, calendar: calendar), week: week, month: UsageSummary.make(window(30)),
                            sleeps: Array(sleeps.reversed()), suggestions: HealthAdvisor.suggestions(week: week, sleeps: sleeps, context: context))
    }
}
public enum HealthText {
    public static let caveat = "스트레스는 일반 리튬이온 연구(Battery University BU-808) 기반 상대값이며 이 배터리에서 검증된 값이 아닙니다."
    static func month(_ d: Date, _ calendar: Calendar) -> String { let c = calendar.dateComponents([.year, .month], from: d); return "\(c.year!)년 \(c.month!)월" }
    public static func trend(_ t: HealthTrend, calendar: Calendar) -> String {
        switch t.status {
        case .collecting(let days, _): return "데이터 수집 중 (\(min(days, HealthTrend.minDays))/\(HealthTrend.minDays)일)"
        case .alreadyBelow: return "건강도가 이미 80% 이하입니다"
        case .notDeclining: return "아직 하락 추세가 보이지 않습니다"
        case .beyondHorizon: return "80% 도달 예상: 15년 이상"
        case .projected(let e, let l): return "80% 도달 예상: \(month(e, calendar)) ~ \(l.map { month($0, calendar) } ?? "알 수 없음")"
        }
    }
    public static func stress(_ s: UsageSummary) -> String {
        guard let r = s.reductionAt80 else { return "측정 중" }
        if r < 0.005 { return "이미 80% 이하로 유지 중" }
        return "상한 80%였다면 스트레스 −\(Int((r * 100).rounded()))%"
    }
    static func hours(_ s: Double) -> String { String(format: "%.1f시간", s / 3600) }
    public static func lines(_ r: HealthReport, calendar: Calendar) -> [String] {
        var out: [String] = []
        if let h = r.health {
            var line = String(format: "건강도(추정) %.1f%%", h)
            if let c = r.cycles { line += " · 사이클 \(c)\(r.designCycles.map { "/\($0)" } ?? "")" }
            if let m = r.marginTo80 { line += m > 0 ? String(format: " · 80%%까지 %.1f%%p", m) : " · 80% 이하" }
            out.append(line)
        } else { out.append("배터리 정보 없음") }
        out.append("수명 추세: \(trend(r.trend, calendar: calendar))")
        if let p = r.trend.cycles { out.append("80% 도달 예상 사이클: \(p.low) ~ \(p.high.map(String.init) ?? "알 수 없음")") }
        let w = r.week
        out.append("최근 7일: 측정 \(hours(w.observed)) · 95% 이상 \(hours(w.soc95)) · 35°C 이상 \(hours(w.hot35))" + (w.observed > 0 ? " · 어댑터 \(Int((w.onAC / w.observed * 100).rounded()))%" : ""))
        out.append("스트레스: " + (w.averageStress.map { String(format: "평균 %.1f (25°C·잔량 40%% = 1) · ", $0) } ?? "") + stress(w))
        let measured = r.sleeps.filter { $0.drainPerHour != nil }
        if !measured.isEmpty { out.append("잠자기: 최근 \(measured.count)회 측정 · 높은 소모 \(measured.filter(\.isHigh).count)회") }
        out += r.suggestions.map { "제안: \($0.message)" }
        out.append("참고: \(caveat)")
        return out
    }
}
```

- [ ] **Step 4: Run** — Expected: PASS; full suite green.
- [ ] **Step 5: Commit** `feat: build health report with stress comparison and suggestions`

### Task 6: Local stores and recorder

**Files:**
- Create: `Sources/BatteryPlatform/HealthStore.swift`
- Modify: `Sources/BatteryPlatform/SessionStore.swift` (`AppPaths.health`, `AppPaths.sleep`)
- Test: `Tests/BatteryCoreTests/HealthStoreTests.swift`

**Interfaces:**
- Consumes: `HealthLedger.record`, `SleepEvent`.
- Produces: `JSONFile<T>(url:)` with `load() -> T?`, `save(_:) throws`, `delete() throws`; `HealthFile { version; last; days }`; `HealthStore(url:)` with `read() -> HealthFile`, `save(_:) throws`, `delete() throws`; `HealthRecorder(store:)` with `file`, `record(_:calendar:) throws`, `flush() throws`, `reset() throws`, `saveInterval = 300`; `SleepStore(url:)` with `read() -> [SleepEvent]`, `append(_:) throws`, `delete() throws`, `limit = 30`; `AppPaths.health`, `AppPaths.sleep`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import BatteryCore
@testable import BatteryPlatform
struct HealthStoreTests {
    func dir() -> URL { let u=FileManager.default.temporaryDirectory.appendingPathComponent("vb-health-\(UUID().uuidString)");return u }
    func snap(_ t:Double,_ p:Int=50) -> BatterySnapshot { var s=BatterySnapshot();s.timestamp=Date(timeIntervalSince1970:1_790_000_000+t);s.percent=p;s.healthPrecise=90;return s }
    @Test func corruptFileIsMovedAside() throws {
        let d=dir();try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true)
        let url=d.appendingPathComponent("health.json");try Data("{oops".utf8).write(to:url)
        #expect(HealthStore(url:url).read().days.isEmpty)
        #expect(FileManager.default.fileExists(atPath:url.appendingPathExtension("corrupt").path))
        #expect(!FileManager.default.fileExists(atPath:url.path))
    }
    @Test func savedFilesArePrivate() throws {
        let url=dir().appendingPathComponent("health.json");let r=HealthRecorder(store:HealthStore(url:url))
        try r.record(snap(0),calendar:.current)
        let mode=try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? Int
        #expect(mode==0o600)
    }
    @Test func recorderSavesAtMostEveryFiveMinutes() throws {
        let url=dir().appendingPathComponent("health.json");let store=HealthStore(url:url);let r=HealthRecorder(store:store)
        try r.record(snap(0),calendar:.current);try r.record(snap(30),calendar:.current)
        #expect(store.read().days.reduce(0) { $0+$1.observed }==0);#expect(r.file.days.reduce(0) { $0+$1.observed }==30)
        try r.flush();#expect(store.read().days.reduce(0) { $0+$1.observed }==30)
        try r.record(snap(330),calendar:.current);#expect(store.read().last?.timestamp==snap(330).timestamp)
    }
    @Test func recorderResumesFromSavedFile() throws {
        let url=dir().appendingPathComponent("health.json")
        let a=HealthRecorder(store:HealthStore(url:url));try a.record(snap(0),calendar:.current)
        let b=HealthRecorder(store:HealthStore(url:url));try b.record(snap(30),calendar:.current)
        #expect(b.file.days.reduce(0) { $0+$1.observed }==30)
    }
    @Test func recorderKeepsRecordingAfterClockChange() throws {
        let r=HealthRecorder(store:HealthStore(url:dir().appendingPathComponent("health.json")))
        try r.record(snap(1000),calendar:.current);try r.record(snap(0),calendar:.current);try r.record(snap(30),calendar:.current)
        #expect(r.file.days.reduce(0) { $0+$1.observed }==30)
    }
    @Test func resetDeletesFileAndMemory() throws {
        let url=dir().appendingPathComponent("health.json");let r=HealthRecorder(store:HealthStore(url:url))
        try r.record(snap(0),calendar:.current);try r.reset()
        #expect(r.file.days.isEmpty);#expect(r.file.last==nil);#expect(!FileManager.default.fileExists(atPath:url.path))
    }
    @Test func sleepStoreKeepsThirty() throws {
        let s=SleepStore(url:dir().appendingPathComponent("sleep.json"))
        for i in 0..<35 { try s.append(SleepEvent(before:snap(Double(i)*10000,80),after:snap(Double(i)*10000+7200,79))) }
        let all=s.read();#expect(all.count==30);#expect(all.first?.start==snap(50000).timestamp)
        try s.delete();#expect(s.read().isEmpty)
    }
}
```

`HealthFile.last` compares timestamps only; `BatterySnapshot` is not `Equatable`.

- [ ] **Step 2: Run** `--filter HealthStoreTests` — Expected: compile failure, `HealthStore` missing.
- [ ] **Step 3: Implement**

`Sources/BatteryPlatform/HealthStore.swift`:

```swift
import Foundation
import BatteryCore
/// A private JSON file. A file that cannot be decoded is moved to `<name>.corrupt` and treated as empty.
public struct JSONFile<T: Codable> {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) { return value }
        let aside = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: aside); try? FileManager.default.moveItem(at: url, to: aside)
        return nil
    }
    public func save(_ value: T) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func delete() throws { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
}
public struct HealthFile: Codable, Sendable {
    public var version = 1
    public var last: BatterySnapshot?
    public var days: [DailyUsage] = []
    public init() {}
}
public struct HealthStore {
    let file: JSONFile<HealthFile>
    public init(url: URL) { file = JSONFile(url: url) }
    public func read() -> HealthFile { file.load() ?? HealthFile() }
    public func save(_ value: HealthFile) throws { try file.save(value) }
    public func delete() throws { try file.delete() }
}
/// Keeps the daily ledger in memory and writes it at most every five minutes, plus on `flush()`.
public final class HealthRecorder {
    public static let saveInterval: TimeInterval = 300
    public private(set) var file: HealthFile
    let store: HealthStore
    var savedAt: Date?
    public init(store: HealthStore) { self.store = store; file = store.read() }
    public func record(_ sample: BatterySnapshot, calendar: Calendar = .current) throws {
        file.days = HealthLedger.record(sample, after: file.last, into: file.days, calendar: calendar)
        file.last = sample
        if let s = savedAt, abs(sample.timestamp.timeIntervalSince(s)) < Self.saveInterval { return }
        try store.save(file); savedAt = sample.timestamp
    }
    public func flush() throws { try store.save(file); savedAt = file.last?.timestamp }
    public func reset() throws { try store.delete(); file = HealthFile(); savedAt = nil }
}
public struct SleepStore {
    public static let limit = 30
    let file: JSONFile<[SleepEvent]>
    public init(url: URL) { file = JSONFile(url: url) }
    public func read() -> [SleepEvent] { file.load() ?? [] }
    public func append(_ event: SleepEvent) throws { try file.save(Array((read() + [event]).suffix(Self.limit))) }
    public func delete() throws { try file.delete() }
}
```

`AppPaths` additions:

```swift
    public static var health:URL { directory.appendingPathComponent("health.json") }
    public static var sleep:URL { directory.appendingPathComponent("sleep.json") }
```

Note the clock-change test: after `snap(1000)` then `snap(0)`, `last` becomes `snap(0)` (ledger ignored the interval) so `snap(30)` counts 30 s.

- [ ] **Step 4: Run** — Expected: PASS; full suite green.
- [ ] **Step 5: Commit** `feat: store daily health records and sleep events locally`

### Task 7: `vbctl health`

**Files:**
- Modify: `Sources/VibeCLI/Main.swift`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `HealthReport.make`, `HealthText.lines`, `HealthStore`, `SleepStore`, `AppPaths.health/sleep`, `PowerUIChargeBackend().read()`, `UserPreferences`.

- [ ] **Step 1: Add the command** before `default:` in `Main.swift`:

```swift
            case "health":
                let b=BatteryReader.read(),s=PowerUIChargeBackend().read()
                let prefs=(try? Data(contentsOf:AppPaths.directory.appendingPathComponent("preferences.json"))).flatMap { try? JSONDecoder().decode(UserPreferences.self,from:$0) } ?? UserPreferences()
                let r=HealthReport.make(snapshot:b,days:HealthStore(url:AppPaths.health).read().days,sleeps:SleepStore(url:AppPaths.sleep).read(),
                                        context:AdvisorContext(limit:s.enabled==true ? s.limit:nil,heatEnabled:prefs.heat.enabled),now:Date(),calendar:.current)
                if args.contains("--json") {
                    let e=JSONEncoder();e.dateEncodingStrategy = .iso8601;e.outputFormatting=[.prettyPrinted,.sortedKeys]
                    print(String(data:try e.encode(r),encoding:.utf8)!)
                } else { HealthText.lines(r,calendar:.current).forEach { print($0) } }
```

and the usage line `  vbctl health [--json]` after `vbctl charge status [--json]`.

- [ ] **Step 2: Run** `VIBEBATTERY_DATA_DIR=<scratch> .build/debug/vbctl health` and `... --json` — Expected: exit 0; text starts with the health line (or `배터리 정보 없음`); JSON contains `"trend"`. Using a scratch data dir keeps the user's files untouched.
- [ ] **Step 3: CI** — add after the charge status step:

```yaml
      - name: Read health report (read-only, runner may have no battery)
        run: dist/VibeBattery.app/Contents/MacOS/vbctl health && dist/VibeBattery.app/Contents/MacOS/vbctl health --json
```

- [ ] **Step 4: Run** full suite — Expected: green.
- [ ] **Step 5: Commit** `feat: add vbctl health report`

### Task 8: App collection, health screen and docs

**Files:**
- Create: `Sources/VibeBattery/HealthView.swift`
- Modify: `Sources/VibeBattery/AppModel.swift`, `App.swift`, `DashboardView.swift`, `SettingsView.swift`, `README.md`, `docs/COMPATIBILITY.md`, `docs/VALIDATION.md`, this plan's progress line.

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: AppModel** — add:

```swift
    @Published var healthReport:HealthReport?
    @Published var sleeps:[SleepEvent]=[]
    private lazy var healthRecorder=HealthRecorder(store:HealthStore(url:AppPaths.health))
    private let sleepStore=SleepStore(url:AppPaths.sleep)
    private var sleepStart:BatterySnapshot?
    func updateHealthReport() {
        healthReport=HealthReport.make(snapshot:battery,days:healthRecorder.file.days,sleeps:sleeps,context:AdvisorContext(limit:charge.enabled==true ? charge.limit:nil,heatEnabled:preferences.heat.enabled),now:Date(),calendar:.current)
    }
    func clearHealth() {
        do { try healthRecorder.reset();try sleepStore.delete();sleeps=[];updateHealthReport() } catch { message=error.localizedDescription }
    }
```

In `init` after loading preferences: `sleeps=sleepStore.read()`; observe sleep and wake:

```swift
        let ws=NSWorkspace.shared.notificationCenter
        ws.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.willSleep() } }
        ws.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.didWake() } }
```

with

```swift
    func willSleep() {
        guard preferences.backgroundHistory else { return }
        sleepStart=BatteryReader.read();try? healthRecorder.flush()
    }
    func didWake() {
        if let s=sleepStart, preferences.backgroundHistory {
            do { try sleepStore.append(SleepEvent(before:s,after:BatteryReader.read()));sleeps=sleepStore.read() } catch { message=error.localizedDescription }
        }
        sleepStart=nil;refresh()
    }
```

In the `willTerminate` observer also call `try? self?.healthRecorder.flush()`. In `refresh()`: inside the `backgroundHistory` branch also `try healthRecorder.record(battery)`; after `refreshCharge()` call `updateHealthReport()`.

- [ ] **Step 2: HealthView** — cards: current state, trend (+cycle range), habits (7/30 days, stress, caveat with BU-808 link), sleep list (last 10, high drain in orange), suggestions with a button to `dashboard`/`settings`/`processes`, delete button. Sidebar item `("health","건강 분석","heart.text.square")` after dashboard and `case "health":HealthView()`. Dashboard card: `건강 분석` + `HealthText.trend` + "자세히" button. Settings toggle label `배터리 이력 기록 (잔량 7일 · 건강 분석 1년)`.

- [ ] **Step 3: Build** `scripts/build-app.sh` (with `SWIFT=$SW` if the script needs the local toolchain) — Expected: build succeeds. Do not launch over the user's running instance; run `dist/.../vbctl health` with a scratch `VIBEBATTERY_DATA_DIR`.
- [ ] **Step 4: Docs** — README feature bullet; COMPATIBILITY rows for health history, trend, stress comparison, sleep drain (implemented; trend needs 30+ days); VALIDATION section with the new test count; plan progress line.
- [ ] **Step 5: Run** full suite — Expected: green. **Commit** `feat: add health insights screen and collection`.

Progress: Tasks 1–8 complete; trend projection awaits 30+ days of real records.
