import Foundation
public enum MenuBarStatus: Equatable, Sendable {
    case charging, paused, onBattery, heatHold
    /// Heat hold wins over charging, which wins over paused (on AC, not charging), then battery.
    public static func make(onAC:Bool,charging:Bool,heatHolding:Bool) -> MenuBarStatus {
        if heatHolding { return .heatHold }
        if charging { return .charging }
        return onAC ? .paused : .onBattery
    }
}
public enum MenuIconStyle: String, Codable, CaseIterable, Sendable {
    case iconAndPercent, iconOnly, percentOnly
    public var title: String {
        switch self { case .iconAndPercent: "아이콘 + 잔량"; case .iconOnly: "아이콘만"; case .percentOnly: "잔량만" }
    }
}
public enum MenuSection: String, Codable, CaseIterable, Sendable {
    case status, power, limit, topUp, lowPower, battery, sessions
    public var title: String {
        switch self {
        case .status: "잔량과 상태"
        case .power: "전력 흐름"
        case .limit: "충전 상한 바로 바꾸기"
        case .topUp: "한 번 완충과 다음 일정"
        case .lowPower: "저전력 모드"
        case .battery: "배터리 정보"
        case .sessions: "바이브 코딩 작업"
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
    public var sections: [MenuSectionSetting] = MenuSection.allCases.map { MenuSectionSetting(section:$0,visible:$0.defaultVisible) }
    public static let `default` = MenuBarSettings()
    public init() {}
    // Unknown icon or section names are dropped, repeats keep the first, and missing sections come back at the end.
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        icon=(try? c.decodeIfPresent(MenuIconStyle.self,forKey:.icon)) ?? .iconAndPercent
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
