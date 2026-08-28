import Foundation

/// User-facing settings, shared between the SwiftUI views and the App Intents
/// (which run in the same process, so plain `UserDefaults` is enough).
enum AppSettings {
    enum Key {
        static let fileName = "logFileName"
        static let format = "logFormat"
        static let defaultCurrency = "defaultCurrency"
        static let minimumConfidence = "minimumConfidence"
        static let keepRejected = "keepRejected"
        static let dedupeWindow = "dedupeWindowSeconds"
    }

    static let defaults: [String: Any] = [
        Key.fileName: "expenses.txt",
        Key.format: LogFormat.tsv.rawValue,
        Key.defaultCurrency: "EUR",
        Key.minimumConfidence: 0.5,
        Key.keepRejected: true,
        Key.dedupeWindow: 120.0,
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaults)
    }

    /// Name of the log file inside Documents.
    static var fileName: String {
        let raw = UserDefaults.standard.string(forKey: Key.fileName) ?? "expenses.txt"
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "expenses.txt" : cleaned
    }

    static var format: LogFormat {
        LogFormat(rawValue: UserDefaults.standard.string(forKey: Key.format) ?? "") ?? .tsv
    }

    /// Used when a notification names an amount but no currency.
    static var defaultCurrency: String {
        UserDefaults.standard.string(forKey: Key.defaultCurrency) ?? "EUR"
    }

    /// Parses below this confidence go to the review file instead of the log.
    static var minimumConfidence: Double {
        UserDefaults.standard.double(forKey: Key.minimumConfidence)
    }

    /// Whether ignored / unparsed / low-confidence notifications are written to
    /// `<name>.review.txt` so nothing is silently lost.
    static var keepRejected: Bool {
        UserDefaults.standard.bool(forKey: Key.keepRejected)
    }

    /// Identical notifications arriving within this many seconds are dropped.
    static var dedupeWindow: TimeInterval {
        let value = UserDefaults.standard.double(forKey: Key.dedupeWindow)
        return value > 0 ? value : 120
    }
}
