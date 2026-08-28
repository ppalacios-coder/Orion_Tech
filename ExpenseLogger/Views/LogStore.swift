import Foundation
import SwiftUI

/// View-side cache of what is in the log file.
@MainActor
@Observable
final class LogStore {
    var entries: [LoggedEntry] = []
    var reviewLines: [String] = []
    var fileSize = 0
    var lastError: String?

    func refresh() async {
        entries = await ExpenseLog.shared.entries()
        fileSize = await ExpenseLog.shared.fileSize()
        let review = await ExpenseLog.shared.reviewContents()
        reviewLines = review
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .reversed()
            .map { $0 }
    }

    func total(since start: Date?) -> Decimal {
        let relevant = entries.filter { start.map { limit in $0.date >= limit } ?? true }
        return -relevant.reduce(Decimal(0)) { $0 + $1.amount }
    }

    var currency: String { entries.first?.currency ?? AppSettings.defaultCurrency }

    func clear() async {
        do {
            try await ExpenseLog.shared.clear()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
