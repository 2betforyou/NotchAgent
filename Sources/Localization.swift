import Foundation

/// UI language. Every user-facing string is written as `L("한국어", "English")` right where it
/// is used, so both languages stay side by side and switch instantly without a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, korean, english
    var id: String { rawValue }

    /// The language strings are rendered in; set from `AppModel.language`.
    nonisolated(unsafe) static var current: AppLanguage = .system

    /// Korean when chosen, or when "system" and macOS prefers Korean; English otherwise.
    var resolvesToKorean: Bool {
        switch self {
        case .korean: true
        case .english: false
        case .system: Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        }
    }
    /// Shown in the picker in each language's own name.
    var name: String {
        switch self {
        case .system: L("시스템 설정 따르기", "Match System")
        case .korean: "한국어" // native name, same in every language
        case .english: "English"
        }
    }
}

/// Picks the Korean or English text for the current UI language.
func L(_ korean: String, _ english: String) -> String {
    AppLanguage.current.resolvesToKorean ? korean : english
}
