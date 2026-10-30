import Foundation

/// Whether this Mac has the macOS Charge Limit feature (macOS 26.4+ on Apple silicon).
public enum ChargeSupport {
    public static func platformAllows(os: OperatingSystemVersion, arm64: Bool) -> Bool {
        arm64 && (os.majorVersion > 26 || (os.majorVersion == 26 && os.minorVersion >= 4))
    }

    /// A Rosetta-translated x86 process on Apple silicon counts as arm64.
    public static var runsOnArm64: Bool {
        #if arch(arm64)
        return true
        #else
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        #endif
    }

    public static var current: Bool { platformAllows(os: ProcessInfo.processInfo.operatingSystemVersion, arm64: runsOnArm64) }

    /// Apple silicon on an older macOS can update to get it; Intel Macs are not supported.
    public static func requirementText(arm64: Bool = runsOnArm64) -> String {
        arm64
            ? tr("Charge limiting needs macOS 26.4 or later. Update macOS in System Settings › General › Software Update to use it.","충전 상한은 macOS 26.4 이상에서 쓸 수 있습니다. 시스템 설정 › 일반 › 소프트웨어 업데이트에서 macOS를 업데이트하세요.")
            : tr("Charge limiting doesn't support Intel Macs yet.","충전 상한은 아직 Intel 맥을 지원하지 않습니다.")
    }

    /// Why the limit is unsupported: the platform gate, or macOS reporting no charge limit on a Mac that passes it.
    public static func unsupportedText(platformAllows: Bool = current) -> String {
        platformAllows ? tr("Charge limiting isn't available on this Mac.","이 맥에서는 충전 상한을 쓸 수 없습니다.") : requirementText()
    }
}
