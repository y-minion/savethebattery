import Foundation
public enum MenuBarStatus: Equatable, Sendable {
    /// `pluggedDischarging`: plugged in while the battery runs the Mac, as above the charge limit.
    case charging, paused, onBattery, heatHold, pluggedDischarging
    /// Heat hold wins over charging, which wins over the plugged-in states (paused, or the battery in use), then battery.
    /// Under half a watt out of the battery counts as holding, the same line the power flow draws.
    public static func make(onAC:Bool,charging:Bool,heatHolding:Bool,batteryWatts:Double?=nil) -> MenuBarStatus {
        if heatHolding { return .heatHold }
        if charging { return .charging }
        guard onAC else { return .onBattery }
        return (batteryWatts ?? 0) <= -0.5 ? .pluggedDischarging : .paused
    }
    /// The SF Symbol shown in the menu bar: what is powering the Mac, or why charging is held.
    public func symbolName(percent:Int?) -> String {
        switch self {
        case .charging: "bolt.fill"
        case .paused: "powerplug.fill"
        case .heatHold: "thermometer.medium"
        case .onBattery, .pluggedDischarging: BatterySymbol.name(percent:percent)
        }
    }
    public var title: String {
        switch self {
        case .charging: tr("Charging","충전 중")
        case .paused: tr("Holding","유지")
        case .onBattery, .pluggedDischarging: tr("On battery","사용 중")
        case .heatHold: tr("Heat hold","과열 보류")
        }
    }
    /// Character shown before the percent when only text is displayed without the status word.
    public var glyph: String {
        switch self { case .charging: "⚡︎"; case .paused: "⏸︎"; case .onBattery, .pluggedDischarging: ""; case .heatHold: "🌡︎" }
    }
}
public enum BatterySymbol {
    /// The SF Symbol battery nearest to `percent`; half full when unknown.
    public static func name(percent:Int?) -> String {
        let p=percent ?? 50
        return p>=88 ? "battery.100percent" : p>=63 ? "battery.75percent" : p>=38 ? "battery.50percent" : p>=13 ? "battery.25percent" : "battery.0percent"
    }
}
public enum MenuBarText {
    /// The words beside the menu bar image, nil when the image stands alone.
    public static func make(style:MenuIconStyle,showsStatus:Bool,percent:Int?,status:MenuBarStatus) -> String? {
        let p="\(percent.map(String.init) ?? "—")%"
        switch style {
        case .iconOnly: return showsStatus ? status.title : nil
        case .iconAndPercent: return showsStatus ? p+" "+status.title : p
        case .percentOnly: return showsStatus ? p+" "+status.title : status.glyph+p
        }
    }
}
public enum MenuIconStyle: String, Codable, CaseIterable, Sendable {
    case iconAndPercent, iconOnly, percentOnly
    public var title: String {
        switch self { case .iconAndPercent: tr("Icon + percent","아이콘 + 잔량"); case .iconOnly: tr("Icon only","아이콘만"); case .percentOnly: tr("Percent only","잔량만") }
    }
}
public enum MenuSection: String, Codable, CaseIterable, Sendable {
    case status, power, limit, topUp, lowPower, battery, sessions
    public var title: String {
        switch self {
        case .status: tr("Charge and status","잔량과 상태")
        case .power: tr("Power flow","전력 흐름")
        case .limit: tr("Quick charge limit","충전 상한 바로 바꾸기")
        case .topUp: tr("Top up once and next schedule","한 번 완충과 다음 일정")
        case .lowPower: tr("Low Power Mode","저전력 모드")
        case .battery: tr("Battery info","배터리 정보")
        case .sessions: tr("Vibe coding tasks","바이브 코딩 작업")
        }
    }
    public var defaultVisible: Bool { self != .topUp }
}
public struct MenuSectionSetting: Codable, Equatable, Sendable {
    public var section: MenuSection
    public var visible: Bool
    public init(section: MenuSection, visible: Bool) { self.section=section;self.visible=visible }
}
public enum MenuQuick { public static let limits = [60,70,80,90,100] }
public struct MenuBarSettings: Codable, Equatable, Sendable {
    public var icon: MenuIconStyle = .iconAndPercent
    /// The status word (Charging, Holding, On battery) beside the percent.
    public var showsStatus = true
    public var sections: [MenuSectionSetting] = MenuSection.allCases.map { MenuSectionSetting(section:$0,visible:$0.defaultVisible) }
    public static let `default` = MenuBarSettings()
    public init() {}
    // Unknown icon or section names are dropped, repeats keep the first, and missing sections come back at the end.
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        icon=(try? c.decodeIfPresent(MenuIconStyle.self,forKey:.icon)) ?? .iconAndPercent
        showsStatus=(try? c.decodeIfPresent(Bool.self,forKey:.showsStatus)) ?? true
        let decoded=(try? c.decodeIfPresent([LossyElement<MenuSectionSetting>].self,forKey:.sections))?.compactMap(\.value) ?? []
        var seen=Set<MenuSection>(),list:[MenuSectionSetting]=[]
        for s in decoded where seen.insert(s.section).inserted { list.append(s) }
        for s in MenuSection.allCases where !seen.contains(s) { list.append(.init(section:s,visible:s.defaultVisible)) }
        sections=list
    }
    public mutating func move(_ s: MenuSection, by offset: Int) {
        guard let i=sections.firstIndex(where:{$0.section==s}) else { return }
        let j=min(max(i+offset,0),sections.count-1)
        guard j != i else { return }
        sections.insert(sections.remove(at:i),at:j)
    }
}
