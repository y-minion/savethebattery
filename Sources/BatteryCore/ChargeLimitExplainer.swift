import Foundation
/// Why a charge limit helps: general research only, no lifespan numbers.
public enum ChargeLimitExplainer {
    public static var paragraphs: [String] { [
        tr("Lithium-ion batteries wear faster the longer they sit at a high charge, and faster still when they are warm. This is general battery research, not something measured on your battery.", "리튬이온 배터리는 높은 잔량으로 오래 있을수록, 그리고 따뜻할수록 더 빨리 마모됩니다. 이는 일반적인 배터리 연구 내용이며 이 배터리에서 측정한 값이 아닙니다."),
        tr("A charge limit stops charging at the level you choose, so the battery spends less time at high charge. Heat hold does the same when the battery is warm.", "충전 상한은 정한 잔량에서 충전을 멈춰 높은 잔량에 머무는 시간을 줄입니다. 과열 보류는 배터리가 따뜻할 때 같은 일을 합니다."),
        tr("The numbers above are the hours this app measured on your Mac, so you can see whether your habits are changing.", "위 수치는 이 앱이 이 Mac에서 직접 측정한 시간이라, 충전 습관이 바뀌고 있는지 확인할 수 있습니다."),
    ] }
    public static let sources: [(title: String, url: URL)] = [
        (title: "Apple: Maximize battery lifespan", url: URL(string: "https://support.apple.com/102338")!),
        (title: "Battery University BU-808", url: URL(string: "https://batteryuniversity.com/article/bu-808-how-to-prolong-lithium-based-batteries")!),
    ]
}
