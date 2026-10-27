import Foundation
/// Why a charge limit helps: general research only, no lifespan numbers.
public enum ChargeLimitExplainer {
    public static var paragraphs: [String] { [
        tr("Lithium-ion batteries wear faster the longer they sit at a high charge, and faster still when they are warm. This is general battery research, not something measured on your battery.", "리튬이온 배터리는 높은 잔량으로 오래 있을수록, 그리고 따뜻할수록 더 빨리 마모됩니다. 이는 일반적인 배터리 연구 내용이며 이 배터리에서 측정한 값이 아닙니다."),
        tr("A charge limit stops charging at the level you choose, so the battery spends less time at high charge. Apple says Optimized Battery Charging and charge limits reduce the time the battery spends fully charged. Heat hold pauses charging while the battery is warm.", "충전 상한은 정한 잔량에서 충전을 멈춰 높은 잔량에 머무는 시간을 줄입니다. Apple은 최적화된 배터리 충전과 충전 한도가 배터리가 완충 상태로 있는 시간을 줄여 준다고 설명합니다. 과열 보류는 배터리가 따뜻한 동안 충전을 멈춥니다."),
        tr("The numbers above are the hours this app measured on your Mac, so you can see whether your habits are changing.", "위 수치는 이 앱이 이 Mac에서 직접 측정한 시간이라, 충전 습관이 바뀌고 있는지 확인할 수 있습니다."),
    ] }
    public static var sources: [(title: String, url: URL)] { [
        (title: tr("About Optimized Battery Charging and Charge Limit on Mac", "Mac의 최적화된 배터리 충전 및 충전 한도에 관하여"), url: URL(string: "https://support.apple.com/102338")!),
        (title: "Battery University BU-808", url: URL(string: "https://batteryuniversity.com/article/bu-808-how-to-prolong-lithium-based-batteries")!),
    ] }
}
