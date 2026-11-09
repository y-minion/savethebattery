import AppKit
import BatteryCore
enum MenuBarIcon {
    /// The state's SF Symbol at menu bar size. Template so it follows the menu bar's colors, except heat hold, which is orange.
    static func image(percent:Int?,status:MenuBarStatus) -> NSImage {
        let heat=status == .heatHold
        var config=NSImage.SymbolConfiguration(pointSize:14,weight:.medium)
        if heat { config=config.applying(.init(paletteColors:[.systemOrange])) }
        let image=NSImage(systemSymbolName:status.symbolName(percent:percent),accessibilityDescription:status.title)?.withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = !heat
        return image
    }
}
