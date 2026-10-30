import Testing
import Foundation
@testable import BatteryCore
@testable import BatteryPlatform

struct LocalizationTests {
    @Test func resolvesLanguage() {
        #expect(AppLanguage.resolve(env: nil, preferred: ["ko-KR","en-US"]) == .ko)
        #expect(AppLanguage.resolve(env: nil, preferred: ["en-KR","ko-KR"]) == .en)
        #expect(AppLanguage.resolve(env: nil, preferred: ["zh-Hans"]) == .en)
        #expect(AppLanguage.resolve(env: nil, preferred: []) == .en)
        #expect(AppLanguage.resolve(env: "ko", preferred: ["en-US"]) == .ko)
        #expect(AppLanguage.resolve(env: "fr", preferred: ["ko"]) == .ko)
    }
    @Test func trFollowsForcedLanguage() {
        AppLanguage.$forced.withValue(.ko) { #expect(tr("Off","끄기") == "끄기") }
        AppLanguage.$forced.withValue(.en) { #expect(tr("Off","끄기") == "Off") }
    }

    /// Hangul in Sources/ must sit inside tr(...) (or a """ literal opened on a tr( line).
    /// Files not converted yet (none left).
    static let pending: Set<String> = []
    /// Files whose Hangul sits outside tr() on purpose: the v2 helper's wire sentence, which is not UI text.
    static let allowedLegacy: Set<String> = ["Sources/BatteryCore/MagSafeLEDPolicy.swift"]
    static let legacyNames = ["legacyUnsupportedV2"]
    /// True when the line calls `tr(` that is not the tail of another identifier (`str(`, `attr(`).
    static func hasTr(_ line: String) -> Bool {
        let u = Array(line.unicodeScalars)
        var i = 0
        while i + 2 < u.count {
            if u[i] == "t", u[i+1] == "r", u[i+2] == "(" {
                let p = i > 0 ? u[i-1] : " "
                if !(p == "_" || CharacterSet.alphanumerics.contains(p)) { return true }
            }
            i += 1
        }
        return false
    }
    @Test func hangulOnlyInsideTr() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let src = root.appendingPathComponent("Sources")
        var bad: [String] = []
        let en = FileManager.default.enumerator(at: src, includingPropertiesForKeys: nil)!
        for case let url as URL in en where url.pathExtension == "swift" {
            let rel = String(url.path.dropFirst(root.path.count + 1))
            if Self.pending.contains(rel) { continue }
            var inMulti = false, multiAllowed = false
            for (i, line) in try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n").enumerated() {
                let triples = line.components(separatedBy: "\"\"\"").count - 1
                let hasHangul = line.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
                let ok = Self.hasTr(line) || (inMulti && multiAllowed) || (Self.allowedLegacy.contains(rel) && Self.legacyNames.contains { line.contains($0) })
                if hasHangul && !ok { bad.append("\(rel):\(i + 1)") }
                if triples % 2 == 1 {
                    if !inMulti { multiAllowed = Self.hasTr(line) }
                    inMulti.toggle()
                }
            }
        }
        #expect(bad.isEmpty, "Hangul outside tr(): \(bad.joined(separator: ", "))")
    }

    /// Every compile-time App Intents key is English and has a Korean entry in ko.lproj.
    @Test func koreanStringsCoverIntents() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: root.appendingPathComponent("Sources/SaveTheBattery/ChargeIntents.swift"), encoding: .utf8)
        func table(_ name: String) throws -> [String: String] {
            let data = try Data(contentsOf: root.appendingPathComponent("Resources/ko.lproj/\(name).strings"))
            return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        func matches(_ pattern: String, in text: String) throws -> [String] {
            let re = try NSRegularExpression(pattern: pattern)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range(at: 1), in: text)!]) }
        }
        let quoted = #""((?:[^"\\]|\\.)*)""#
        // Keys with interpolation are runtime strings, not catalog keys.
        let keys = try matches(#"(?:LocalizedStringResource\s*=|\btitle\s*:|shortTitle\s*:|IntentDescription\(|TypeDisplayRepresentation\s*=)\s*"# + quoted, in: src).filter { !$0.contains("\\(") }
        var phrases: [String] = []
        for list in try matches(#"phrases\s*:\s*\[([^\]]*)\]"#, in: src) {
            phrases += try matches(quoted, in: list).map { $0.replacingOccurrences(of: "\\(.applicationName)", with: "${applicationName}") }
        }
        #expect(keys.count >= 20 && phrases.count >= 3)
        let ko = try table("Localizable"), shortcuts = try table("AppShortcuts")
        for k in keys {
            #expect(ko[k] != nil, "Localizable.strings lacks \(k)")
            #expect(!k.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }, "Hangul key \(k)")
        }
        for k in phrases {
            #expect(shortcuts[k] != nil, "AppShortcuts.strings lacks \(k)")
            #expect(shortcuts[k]?.contains("${applicationName}") == true, "Korean phrase lacks ${applicationName}: \(k)")
            #expect(!k.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }, "Hangul key \(k)")
        }
    }

    /// Every scripts/*.sh line with Hangul must go through `msg `; Python scripts carry none.
    @Test func scriptsSayBothLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("scripts")
        var bad: [String] = []
        for url in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where ["sh", "py"].contains(url.pathExtension) {
            for (i, line) in try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n").enumerated() {
                guard line.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) else { continue }
                if url.pathExtension == "py" || !line.contains("msg ") { bad.append("\(url.lastPathComponent):\(i + 1)") }
            }
        }
        #expect(bad.isEmpty, "Hangul outside msg: \(bad.joined(separator: ", "))")
    }

    // One English assertion per text enum, plus the Korean counterpart.
    @Test func englishText() {
        let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Seoul")!; return c }()
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 23, minute: 0))!
        func at(_ day: Int, _ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h))! }
        AppLanguage.$forced.withValue(.en) {
            #expect(ScheduleText.days(Set(2...6)) == "Weekdays")
            #expect(ScheduleText.action(.setLimit(70)) == "Limit 70%")
            #expect(ScheduleText.when(at(22, 22), now: now, calendar: cal) == "Today 22:00")
            #expect(ScheduleText.when(at(23, 7), now: now, calendar: cal) == "Tomorrow 07:00")
            #expect(ScheduleText.when(at(26, 0), now: now, calendar: cal) == "Oct 26 00:00")
            #expect(ChargeText.logLine(ChargeWrite(date: at(21, 22), command: "setLimit(70)", source: .schedule, ok: true, detail: "Night"), now: now, calendar: cal) == "Yesterday 22:00 · Schedule 'Night' · Limit 70%")
            #expect(ChargeText.logLine(ChargeWrite(date: at(3, 22), command: "clearLimit", source: .user, ok: false, detail: nil), now: now, calendar: cal) == "Oct 3 22:00 · Manual · Limit off · failed")
            #expect(NotificationText.duration(95 * 60) == "1 h 35 min")
            #expect(NotificationText.limitReached(80).0 == "Charge limit 80% reached")
            #expect(HealthText.hours(7200) == "2.0 h")
            #expect(HealthText.month(now, cal) == "Oct 2026")
            #expect(MenuSection.power.title == "Power flow")
            #expect(LEDMode.perState.title == "Set per state")
            #expect(LowPowerText.done(true) == "Low Power Mode turned on.")
            #expect(PowerSegment.adapterToMac(61).label == "Mac 61 W")
            #expect(ChargeError.noTopUp.errorDescription == "No top-up is in progress.")
            #expect(ChargeCLI.usage.hasPrefix("Usage:"))
            #expect(ShortcutStatus(percent: 82, charging: true, onAC: true, limit: 70, health: 88, temperature: 31.5).summary == "Battery 82% · Charging · Limit 70% · Health 88% · 31.5°C")
        }
        AppLanguage.$forced.withValue(.ko) {
            #expect(HealthText.month(now, cal) == "2026년 10월")
            #expect(ChargeCLI.usage.hasPrefix("사용법:"))
        }
    }
    @Test func autoNamesFollowTemplatesInEitherLanguage() {
        let r = AppLanguage.$forced.withValue(.en) { ChargeScheduleRule.templates(now: Date())[0] }
        #expect(r.name == "70% at night")
        AppLanguage.$forced.withValue(.ko) { #expect(ScheduleText.isAutoName("70% at night", for: r)) }
    }
}
