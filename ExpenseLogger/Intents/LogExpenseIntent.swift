import AppIntents
import Foundation
import UniformTypeIdentifiers

/// The main entry point for automations: hand it the text of a bank
/// notification (or SMS/email body) and it parses and appends it to the log.
///
/// `openAppWhenRun` is false so a Shortcuts personal automation set to "Run
/// Immediately" logs in the background without taking over the screen.
struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Expense from Text"
    static var description = IntentDescription(
        "Reads an amount, merchant and card from bank notification text and appends it to your expense log file.",
        categoryName: "Logging",
        searchKeywords: ["expense", "bank", "notification", "spend", "log"]
    )
    static var openAppWhenRun = false

    @Parameter(title: "Notification Text")
    var text: String

    @Parameter(title: "Source", description: "Where it came from, e.g. your bank's name.")
    var source: String?

    @Parameter(title: "Received At", description: "Defaults to now.")
    var receivedAt: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log expense from \(\.$text)") {
            \.$source
            \.$receivedAt
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let parsed = ExpenseParser.parse(
            text,
            source: source,
            receivedAt: receivedAt ?? Date(),
            defaultCurrency: AppSettings.defaultCurrency
        )
        let outcome = try await ExpenseLog.shared.append(parsed)

        let dialog: IntentDialog
        switch outcome {
        case .logged:
            let amount = parsed.amount.map(LogLine.amountString) ?? "?"
            let currency = parsed.currency ?? ""
            let merchant = parsed.merchant ?? "unknown merchant"
            dialog = IntentDialog("Logged \(amount) \(currency) at \(merchant)")
        default:
            dialog = IntentDialog(stringLiteral: outcome.summary)
        }

        return .result(value: outcome.summary, dialog: dialog)
    }
}

/// Escape hatch: append text verbatim, no parsing. Useful while you are still
/// working out what your bank's notifications look like.
struct LogRawTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Append Raw Text to Expense Log"
    static var description = IntentDescription(
        "Appends text to the log file exactly as given, with a timestamp and no parsing.",
        categoryName: "Logging"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var raw = ParsedExpense(kind: .unparsed, raw: text, receivedAt: Date())
        raw.reason = "raw-capture"
        _ = try await ExpenseLog.shared.append(raw)
        return .result(value: text)
    }
}

/// Returns the log file itself, so a shortcut can mail it, drop it in iCloud
/// Drive, or hand it to another app.
struct ExpenseLogFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Expense Log File"
    static var description = IntentDescription(
        "Returns the expense log file so you can save, share or back it up.",
        categoryName: "Export"
    )
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let url = ExpenseLog.shared.fileURL   // nonisolated
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ExpenseLogIntentError.emptyLog
        }
        let file = try IntentFile(fileURL: url, filename: url.lastPathComponent, type: .plainText)
        return .result(value: file)
    }
}

enum ExpenseLogIntentError: LocalizedError {
    case emptyLog
    var errorDescription: String? {
        switch self {
        case .emptyLog: "Nothing has been logged yet."
        }
    }
}
