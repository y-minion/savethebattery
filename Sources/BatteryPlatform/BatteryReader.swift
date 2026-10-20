import Foundation
import IOKit
import IOKit.ps
import BatteryCore
public enum BatteryReader {
    private static func properties(_ service: io_service_t) -> [String:Any] {
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var value: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service,&value,kCFAllocatorDefault,0)==KERN_SUCCESS else { return [:] }
        return value?.takeRetainedValue() as? [String:Any] ?? [:]
    }
    public static func read() -> BatterySnapshot {
        var raw=properties(IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSmartBattery")))
        if raw["Temperature"] == nil {
            let pack=properties(IOServiceGetMatchingService(kIOMainPortDefault,IOServiceNameMatching("AppleSmartBatteryPack")))
            raw["Temperature"]=(pack["BatteryData"] as? [String:Any])?["Temperature"]
        }
        return BatterySnapshot.decode(raw)
    }
}
