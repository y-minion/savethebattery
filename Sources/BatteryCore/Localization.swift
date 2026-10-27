import Foundation

/// UI language. English is the base; Korean is the translation.
public enum AppLanguage: String, Sendable, CaseIterable {
    case en, ko

    /// `VB_LANG` of `ko`/`en` wins; else the first preferred language starting with `ko`; else English.
    public static func resolve(env: String?, preferred: [String]) -> AppLanguage {
        if let env, let l = AppLanguage(rawValue: env) { return l }
        if let first = preferred.first, first.hasPrefix("ko") { return .ko }
        return .en
    }

    @TaskLocal public static var forced: AppLanguage?
    public static let system: AppLanguage = resolve(env: ProcessInfo.processInfo.environment["VB_LANG"], preferred: Locale.preferredLanguages)
    public static var current: AppLanguage { forced ?? system }

    public var locale: Locale { Locale(identifier: self == .ko ? "ko_KR" : "en_US") }
}

/// English / Korean text chosen by the current language.
public func tr(_ en: String, _ ko: String) -> String { AppLanguage.current == .ko ? ko : en }
