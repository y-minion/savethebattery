import Foundation
public enum ChargeCommand: Equatable, Sendable {
    case setLimit(Int), clearLimit, startTopUp, endTopUp
    public static let range=50...100
    /// macOS lets user processes set 80–100; lower limits need the root helper.
    public static let userFloor=80
    public var isValid:Bool { if case .setLimit(let p)=self { return Self.range.contains(p) };return true }
    public var requiresHelper:Bool { if case .setLimit(let p)=self { return p<Self.userFloor };return false }
}
public enum LimitOrigin: String, Codable, Sendable { case vibeBattery, external, none, unknown }
public struct ChargeLimitState: Codable, Equatable, Sendable {
    public var supported:Bool?;public var enabled:Bool?;public var limit:Int?
    public init(supported:Bool?=nil,enabled:Bool?=nil,limit:Int?=nil) { self.supported=supported;self.enabled=enabled;self.limit=limit }
    public func origin(lastWritten:Int?) -> LimitOrigin {
        guard supported==true,let enabled else { return .unknown }
        if !enabled { return .none }
        guard let limit else { return .unknown }
        return lastWritten==limit ? .vibeBattery:.external
    }
    /// Whether a read-back state confirms a command. nil: macOS gives no observable confirmation.
    public func matches(_ c:ChargeCommand) -> Bool? {
        switch c {
        case .setLimit(let p):return enabled==true && limit==p
        case .clearLimit:return enabled==false
        case .endTopUp:return enabled==true
        case .startTopUp:return nil
        }
    }
}
public struct HeatSettings: Codable, Equatable, Sendable {
    public var enabled=false;public var holdAt=35.0;public var resumeAt=32.0
    public init() {}
    public mutating func validate() {
        if !(30...45).contains(holdAt) { holdAt=35 }
        if !resumeAt.isFinite || resumeAt<25 || resumeAt>=holdAt { resumeAt=min(32,holdAt-1) }
    }
}
public struct HeatState: Codable, Equatable, Sendable {
    public var holdLimit:Int?;public var userLimit:Int?;public var coolSince:Date?
    public init() {}
}
public enum HeatAction: Equatable, Sendable { case none, hold(Int), restore(ChargeCommand), cannotHold, sensorUnavailable }
public enum HeatHoldPolicy {
    public static let stableResume:TimeInterval=300, staleAfter:TimeInterval=120, minimumHold=50
    public static func step(snapshot b:BatterySnapshot,limit:ChargeLimitState,settings:HeatSettings,state:inout HeatState,helperAvailable:Bool,now:Date=Date()) -> HeatAction {
        if let hold=state.holdLimit {
            // Someone changed the limit during the hold: their value wins.
            guard limit.enabled==true,limit.limit==hold else { state=HeatState();return .none }
            if !settings.enabled { return finish(&state) }
            guard let t=fresh(b,now) else { state.coolSince=nil;return .sensorUnavailable }
            guard t<=settings.resumeAt else { state.coolSince=nil;return .none }
            guard let since=state.coolSince else { state.coolSince=now;return .none }
            return now.timeIntervalSince(since)>=stableResume ? finish(&state):.none
        }
        guard settings.enabled else { return .none }
        guard let t=fresh(b,now) else { return .sensorUnavailable }
        guard t>=settings.holdAt,b.onAC,b.charging,let p=b.percent else { return .none }
        guard limit.supported==true,let enabled=limit.enabled,
              p>=minimumHold,p>=ChargeCommand.userFloor || helperAvailable else { return .cannotHold }
        state.holdLimit=p;state.userLimit=enabled ? limit.limit:nil;state.coolSince=nil
        return .hold(p)
    }
    private static func fresh(_ b:BatterySnapshot,_ now:Date) -> Double? {
        let age=now.timeIntervalSince(b.timestamp)
        return age >= -5 && age<=staleAfter ? b.temperature:nil
    }
    private static func finish(_ s:inout HeatState) -> HeatAction {
        let user=s.userLimit;s=HeatState()
        return .restore(user.map { .setLimit($0) } ?? .clearLimit)
    }
}
