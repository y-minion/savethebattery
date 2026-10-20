import Foundation
/// Which notifications the user wants and their thresholds. Missing keys keep defaults so older files load.
public struct NotificationSettings: Codable, Equatable, Sendable {
    public var limitReached=false, topUpDone=true, lowBattery=false, limitChanged=true, controlUnavailable=true
    public var highTemperature=true, conflict=true, heatProblem=true, heatActivity=false
    public var sessionEnded=true, sessionCancelled=false, protectionReleased=true
    public var sleepDrain=true, suggestions=false, weeklySummary=false
    public var lowAt=20
    public var hotAt=40.0
    public static let lowRange=10...50, hotRange=36.0...45.0
    public init() {}
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self),d=NotificationSettings()
        func flag(_ k:CodingKeys,_ v:Bool) throws -> Bool { try c.decodeIfPresent(Bool.self,forKey:k) ?? v }
        limitReached=try flag(.limitReached,d.limitReached);topUpDone=try flag(.topUpDone,d.topUpDone)
        lowBattery=try flag(.lowBattery,d.lowBattery);limitChanged=try flag(.limitChanged,d.limitChanged)
        controlUnavailable=try flag(.controlUnavailable,d.controlUnavailable);highTemperature=try flag(.highTemperature,d.highTemperature)
        conflict=try flag(.conflict,d.conflict);heatProblem=try flag(.heatProblem,d.heatProblem);heatActivity=try flag(.heatActivity,d.heatActivity)
        sessionEnded=try flag(.sessionEnded,d.sessionEnded);sessionCancelled=try flag(.sessionCancelled,d.sessionCancelled)
        protectionReleased=try flag(.protectionReleased,d.protectionReleased);sleepDrain=try flag(.sleepDrain,d.sleepDrain)
        suggestions=try flag(.suggestions,d.suggestions);weeklySummary=try flag(.weeklySummary,d.weeklySummary)
        lowAt=try c.decodeIfPresent(Int.self,forKey:.lowAt) ?? d.lowAt
        hotAt=try c.decodeIfPresent(Double.self,forKey:.hotAt) ?? d.hotAt
    }
    public mutating func validate() {
        if !Self.lowRange.contains(lowAt) || lowAt%5 != 0 { lowAt=20 }
        if !hotAt.isFinite || !Self.hotRange.contains(hotAt) { hotAt=40 }
    }
}
/// What one heat-hold step did, announced once.
public enum HeatEvent: Equatable, Sendable {
    case held(Int), restored, yielded, holdFailed
    /// A failed restore is not an event: it leaves a stuck limit, which is reported as state.
    public static func from(action:HeatAction,failed:Bool) -> HeatEvent? {
        switch action {
        case .hold(let p):return failed ? .holdFailed:.held(p)
        case .restore:return failed ? nil:.restored
        case .yielded:return .yielded
        default:return nil
        }
    }
}
public struct SessionSummary: Equatable, Sendable {
    public var id:UUID;public var command:String;public var outcome:SessionOutcome
    public var started:Date;public var ended:Date?;public var exitCode:Int32?
    /// The user asked VibeBattery to release this session's protection.
    public var released:Bool
    public init(id:UUID,command:String,outcome:SessionOutcome,started:Date,ended:Date?=nil,exitCode:Int32?=nil,released:Bool=false) {
        self.id=id;self.command=command;self.outcome=outcome;self.started=started;self.ended=ended;self.exitCode=exitCode;self.released=released
    }
}
/// Everything one evaluation looks at. One-shot fields (`heatEvent`, `wake`) are set only for the refresh that produced them.
public struct NotificationInput: Sendable {
    public var now:Date
    public var battery:BatterySnapshot
    public var limit=ChargeLimitState()
    public var lastWritten:Int?
    /// Bumped on every charge write VibeBattery attempts, including its own heat-hold restores.
    public var chargeWrites=0
    public var topUpRequested:Date?
    public var heatEnabled=false, heatHolding=false
    /// The lowered limit left behind by a failed restore.
    public var heatStuckLimit:Int?
    public var heatSensorMissing=false
    public var heatEvent:HeatEvent?
    public var conflicts:[String]=[]
    public var sessions:[SessionSummary]=[]
    public var wake:SleepEvent?
    public var suggestions:[Suggestion]=[]
    public var week:UsageSummary?
    public var calendar=Calendar.current
    public init(now:Date,battery:BatterySnapshot) { self.now=now;self.battery=battery }
}
public struct AlertEvent: Equatable, Sendable {
    public static let sections:Set<String>=["dashboard","settings","sessions","health"]
    /// The screen a clicked notification may open; anything unexpected opens the dashboard.
    public static func route(_ value:Any?) -> String { (value as? String).flatMap { sections.contains($0) ? $0:nil } ?? "dashboard" }
    /// Same id replaces the earlier notification of that kind.
    public var id:String, title:String, body:String, section:String, thread:String
    /// The app also shows this in its own alert; skipped while the app is in front.
    public var duplicatesAppMessage:Bool
    public init(id:String,title:String,body:String,section:String,thread:String,duplicatesAppMessage:Bool=false) {
        self.id=id;self.title=title;self.body=body;self.section=section;self.thread=thread;self.duplicatesAppMessage=duplicatesAppMessage
    }
}
public struct SessionMark: Codable, Equatable, Sendable {
    public var ended=false, released=false
    public init(ended:Bool=false,released:Bool=false) { self.ended=ended;self.released=released }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        ended=try c.decodeIfPresent(Bool.self,forKey:.ended) ?? false;released=try c.decodeIfPresent(Bool.self,forKey:.released) ?? false
    }
}
/// What has been announced and what may be announced again. Disabled events update it too, so enabling one later causes no backlog.
public struct NotificationMemory: Codable, Equatable, Sendable {
    /// In-process only: after a restart change-based checks start from a fresh baseline.
    public var evaluated:Date?
    public var wasCharging:Bool?
    public var limitNotified:Int?
    public var offACSince:Date?, onACSince:Date?
    public var topUpNotified:Date?
    public var lowArmed=true
    public var hotArmed=true
    public var hotSent:Date?
    public var conflicts:[String]=[]
    public var origin:LimitOrigin?
    public var lastWritten:Int?
    public var chargeWrites:Int?
    public var supportedSeen=false, unavailableNotified=false
    public var stuckSent:Date?
    public var sensorMissingSince:Date?
    public var sensorNotified=false
    public var sessions:[String:SessionMark]=[:]
    public var suggestionSent:[String:Date]=[:]
    public var weekKey:String?
    enum CodingKeys:String,CodingKey { case limitNotified,offACSince,onACSince,topUpNotified,lowArmed,hotArmed,hotSent,conflicts,origin,lastWritten,chargeWrites,supportedSeen,unavailableNotified,stuckSent,sensorMissingSince,sensorNotified,sessions,suggestionSent,weekKey }
    public init() {}
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        limitNotified=try c.decodeIfPresent(Int.self,forKey:.limitNotified)
        offACSince=try c.decodeIfPresent(Date.self,forKey:.offACSince);onACSince=try c.decodeIfPresent(Date.self,forKey:.onACSince)
        topUpNotified=try c.decodeIfPresent(Date.self,forKey:.topUpNotified)
        lowArmed=try c.decodeIfPresent(Bool.self,forKey:.lowArmed) ?? true;hotArmed=try c.decodeIfPresent(Bool.self,forKey:.hotArmed) ?? true
        hotSent=try c.decodeIfPresent(Date.self,forKey:.hotSent)
        conflicts=try c.decodeIfPresent([String].self,forKey:.conflicts) ?? []
        origin=(try? c.decodeIfPresent(LimitOrigin.self,forKey:.origin)) ?? nil
        lastWritten=try c.decodeIfPresent(Int.self,forKey:.lastWritten)
        chargeWrites=try c.decodeIfPresent(Int.self,forKey:.chargeWrites)
        supportedSeen=try c.decodeIfPresent(Bool.self,forKey:.supportedSeen) ?? false
        unavailableNotified=try c.decodeIfPresent(Bool.self,forKey:.unavailableNotified) ?? false
        stuckSent=try c.decodeIfPresent(Date.self,forKey:.stuckSent)
        sensorMissingSince=try c.decodeIfPresent(Date.self,forKey:.sensorMissingSince)
        sensorNotified=try c.decodeIfPresent(Bool.self,forKey:.sensorNotified) ?? false
        sessions=try c.decodeIfPresent([String:SessionMark].self,forKey:.sessions) ?? [:]
        suggestionSent=try c.decodeIfPresent([String:Date].self,forKey:.suggestionSent) ?? [:]
        weekKey=try c.decodeIfPresent(String.self,forKey:.weekKey)
    }
    /// A wall clock moved back leaves times in the future: sent times expire, durations restart now.
    mutating func clamp(_ now:Date) {
        func since(_ d:Date?) -> Date? { d.map { $0>now ? now:$0 } }
        func sent(_ d:Date?) -> Date? { d.flatMap { $0>now ? nil:$0 } }
        evaluated=sent(evaluated);offACSince=since(offACSince);onACSince=since(onACSince);sensorMissingSince=since(sensorMissingSince)
        hotSent=sent(hotSent);stuckSent=sent(stuckSent);suggestionSent=suggestionSent.filter { $0.value<=now }
    }
}
public struct NotificationOutcome: Equatable, Sendable {
    public var events:[AlertEvent]=[]
    /// Delivered notifications whose condition has ended.
    public var removals:[String]=[]
    public var memory:NotificationMemory
    public init(memory:NotificationMemory) { self.memory=memory }
    mutating func send(_ on:Bool,_ e:AlertEvent) { if on { events.append(e) } }
    mutating func remove(_ id:String) { removals.append(id) }
}
