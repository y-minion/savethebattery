import Foundation

/// Whether this Mac has the macOS Charge Limit feature (macOS 26.4+ on Apple silicon).
public enum ChargeSupport {
    public static func platformAllows(os: OperatingSystemVersion, arm64: Bool) -> Bool {
        arm64 && (os.majorVersion > 26 || (os.majorVersion == 26 && os.minorVersion >= 4))
    }

    /// A Rosetta-translated x86 process on Apple silicon counts as arm64.
    static var runsOnArm64: Bool {
        #if arch(arm64)
        return true
        #else
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        #endif
    }

    public static var current: Bool { platformAllows(os: ProcessInfo.processInfo.operatingSystemVersion, arm64: runsOnArm64) }

    public static var requirementText: String {
        tr("Charge limiting needs macOS 26.4 or later on Apple silicon (support for more Macs is planned).","충전 상한은 macOS 26.4 이상의 Apple Silicon 맥에서 쓸 수 있습니다(지원 기기 확대 예정).")
    }
}
