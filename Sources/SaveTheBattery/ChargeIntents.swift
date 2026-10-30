import AppIntents
import BatteryCore
import BatteryPlatform
/// Shown by Shortcuts when an action fails, with the same text the app would show.
struct ShortcutFailure: Error, CustomLocalizedStringResourceConvertible {
    let message:String
    var localizedStringResource:LocalizedStringResource { "\(message)" }
}
@MainActor private func run(_ c:ChargeCommand) throws -> some IntentResult & ProvidesDialog {
    let r=AppModel.shared.perform(c,source:.shortcut)
    guard r.ok else { throw ShortcutFailure(message:r.message) }
    return .result(dialog:"\(r.message)")
}
struct SetChargeLimitIntent: AppIntent {
    static let title:LocalizedStringResource="Set Charge Limit"
    static let description=IntentDescription("Changes the charge limit between 50% and 100% in steps of 5%. Limits below 80% need the charge helper.")
    static let openAppWhenRun=false
    @Parameter(title:"Limit",default:80,inclusiveRange:(50,100)) var percent:Int
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ChargeCommand.setLimit(percent).isValid else { throw ShortcutFailure(message:ChargeError.invalid.localizedDescription) }
        return try run(.setLimit(percent))
    }
}
struct StartTopUpIntent: AppIntent {
    static let title:LocalizedStringResource="Start One-Time Full Charge"
    static let description=IntentDescription("Charges to 100% this one time. The limit returns when it ends.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog { try run(.startTopUp) }
}
struct EndTopUpIntent: AppIntent {
    static let title:LocalizedStringResource="End Full Charge"
    static let description=IntentDescription("Ends the one-time full charge and returns to the usual limit.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog { try run(.endTopUp) }
}
struct ClearChargeLimitIntent: AppIntent {
    static let title:LocalizedStringResource="Turn Off Charge Limit"
    static let description=IntentDescription("Turns off the charge limit and charges to 100%.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog { try run(.clearLimit) }
}
struct SetLowPowerModeIntent: AppIntent {
    static let title:LocalizedStringResource="Set Low Power Mode"
    static let description=IntentDescription("Turns Low Power Mode on or off. This overrides any per-power-source setting. Needs the charge helper.")
    static let openAppWhenRun=false
    @Parameter(title:"Turn On",default:true) var on:Bool
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        if let e=await AppModel.shared.setLowPower(on) { throw ShortcutFailure(message:e) }
        return .result(dialog:"\(LowPowerText.done(on))")
    }
}
struct BatteryStatusEntity: TransientAppEntity {
    static let typeDisplayRepresentation:TypeDisplayRepresentation="Battery Status"
    @Property(title:"Charge") var percent:Int?
    @Property(title:"Charging") var charging:Bool?
    @Property(title:"Adapter Connected") var onAC:Bool?
    @Property(title:"Limit") var limit:Int?
    @Property(title:"Health (estimated)") var health:Int?
    @Property(title:"Temperature") var temperature:Double?
    var summary=""
    var displayRepresentation:DisplayRepresentation { DisplayRepresentation(title:"\(summary)") }
    init() {}
    init(_ s:ShortcutStatus) {
        percent=s.percent;charging=s.charging;onAC=s.onAC;limit=s.limit;health=s.health;temperature=s.temperature;summary=s.summary
    }
}
struct GetBatteryStatusIntent: AppIntent {
    static let title:LocalizedStringResource="Get Battery Status"
    static let description=IntentDescription("Gets the charge, charging state, charge limit, estimated health and temperature.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<BatteryStatusEntity> & ProvidesDialog {
        let s=AppModel.shared.shortcutStatus()
        return .result(value:BatteryStatusEntity(s),dialog:"\(s.summary)")
    }
}
struct SaveTheBatteryShortcuts: AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] {
        AppShortcut(intent:SetChargeLimitIntent(),phrases:["\(.applicationName) limit 80%"],shortTitle:"Set Charge Limit",systemImageName:"battery.75percent")
        AppShortcut(intent:StartTopUpIntent(),phrases:["\(.applicationName) one-time full charge"],shortTitle:"One-Time Full Charge",systemImageName:"battery.100percent.bolt")
        AppShortcut(intent:GetBatteryStatusIntent(),phrases:["\(.applicationName) battery status"],shortTitle:"Battery Status",systemImageName:"info.circle")
    }
}
