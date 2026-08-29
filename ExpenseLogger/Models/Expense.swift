import Foundation

/// What a notification turned out to be.
enum ExpenseKind: String, Codable, Sendable {
    case expense    // money out
    case credit     // refund / money in
    case ignored    // deliberately not logged (OTP, balance alert, promo…)
    case unparsed   // looked like a transaction but no amount could be read
}

/// The result of running a notification through `ExpenseParser`.
struct ParsedExpense: Sendable, Equatable {
    var kind: ExpenseKind
    var raw: String
    var receivedAt: Date
    var source: String?
    var amount: Decimal?
    var currency: String?
    var merchant: String?
    var card: String?
    var confidence: Double = 0
    /// Why it was ignored or left unparsed. Nil for logged transactions.
    var reason: String?

    /// Negative for money out, positive for money in.
    var signedAmount: Decimal? {
        guard let amount else { return nil }
        return kind == .credit ? amount : -amount
    }

    var isLoggable: Bool { kind == .expense || kind == .credit }

    /// Stable fingerprint used to drop duplicates when an automation fires twice.
    var dedupeKey: String {
        let basis = [
            amount.map { "\($0)" } ?? "",
            currency ?? "",
            merchant ?? "",
            raw.trimmingCharacters(in: .whitespacesAndNewlines),
        ].joined(separator: "|")
        return String(basis.simpleDigest.prefix(16))
    }
}

/// How each line is written to the log file.
enum LogFormat: String, CaseIterable, Identifiable, Sendable {
    case tsv, csv, jsonl, plain
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tsv: return "Tab-separated (recommended)"
        case .csv: return "CSV (spreadsheet)"
        case .jsonl: return "JSON Lines"
        case .plain: return "Plain readable text"
        }
    }

    /// Header line written when the file is first created, if the format has one.
    var header: String? {
        switch self {
        case .tsv: return "timestamp\tamount\tcurrency\tmerchant\tcard\tsource\tconfidence\traw"
        case .csv: return "timestamp,amount,currency,merchant,card,source,confidence,raw"
        case .jsonl, .plain: return nil
        }
    }
}

/// A line read back out of the log file, for display.
struct LoggedEntry: Identifiable, Sendable {
    let id = UUID()
    var date: Date
    var amount: Decimal
    var currency: String
    var merchant: String
    var card: String?
    var source: String?
    var raw: String
}

private extension String {
    /// FNV-1a. Sufficient for dedupe fingerprints; not a security hash.
    var simpleDigest: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in self.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
