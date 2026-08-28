import Foundation

/// Renders a `ParsedExpense` as one line of the log file, and reads lines back.
enum LogLine {

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func amountString(_ value: Decimal) -> String {
        amountFormatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func timestamp(_ date: Date) -> String { timestampFormatter.string(from: date) }

    // MARK: - Writing

    static func render(_ expense: ParsedExpense, format: LogFormat) -> String {
        let fields = [
            timestamp(expense.receivedAt),
            expense.signedAmount.map(amountString) ?? "",
            expense.currency ?? "",
            expense.merchant ?? "",
            expense.card ?? "",
            expense.source ?? "",
            String(format: "%.2f", expense.confidence),
            expense.raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression),
        ]

        switch format {
        case .tsv:
            return fields.map { $0.replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t")
        case .csv:
            return fields.map(csvEscape).joined(separator: ",")
        case .jsonl:
            var payload: [String: Any] = [
                "timestamp": fields[0],
                "kind": expense.kind.rawValue,
                "confidence": expense.confidence,
                "raw": expense.raw,
            ]
            // Built key by key: `nil as Any` survives `compactMapValues` and
            // would make JSONSerialization reject the whole object.
            if let amount = expense.signedAmount {
                payload["amount"] = NSDecimalNumber(decimal: amount).doubleValue
            }
            if let currency = expense.currency { payload["currency"] = currency }
            if let merchant = expense.merchant { payload["merchant"] = merchant }
            if let card = expense.card { payload["card"] = card }
            if let source = expense.source { payload["source"] = source }
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? fields[7]
        case .plain:
            let symbol = ExpenseParser.symbols.first { $0.value == expense.currency }?.key
            let money = expense.amount.map { amount -> String in
                symbol.map { "\($0)\(amountString(amount))" }
                    ?? "\(amountString(amount)) \(expense.currency ?? "")"
            } ?? "?"
            var line = "\(shortDate(expense.receivedAt)) — \(money) \(expense.merchant ?? "?")"
            if let card = expense.card { line += " (*\(card))" }
            return line
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Reading back

    /// Parses a previously written line. Returns nil for headers, blanks and
    /// formats that are not machine-readable (`.plain`).
    static func parse(_ line: String, format: LogFormat) -> LoggedEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        switch format {
        case .tsv, .csv:
            let fields = format == .tsv
                ? trimmed.components(separatedBy: "\t")
                : parseCSVRow(trimmed)
            guard fields.count >= 8, fields[0] != "timestamp" else { return nil }
            guard let date = timestampFormatter.date(from: fields[0]),
                  let amount = Decimal(string: fields[1], locale: Locale(identifier: "en_US_POSIX"))
            else { return nil }
            return LoggedEntry(
                date: date,
                amount: amount,
                currency: fields[2],
                merchant: fields[3].isEmpty ? "Unknown" : fields[3],
                card: fields[4].isEmpty ? nil : fields[4],
                source: fields[5].isEmpty ? nil : fields[5],
                raw: fields[7]
            )
        case .jsonl:
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stamp = object["timestamp"] as? String,
                  let date = timestampFormatter.date(from: stamp),
                  let amount = object["amount"] as? Double
            else { return nil }
            return LoggedEntry(
                date: date,
                amount: Decimal(amount),
                currency: object["currency"] as? String ?? "",
                merchant: object["merchant"] as? String ?? "Unknown",
                card: object["card"] as? String,
                source: object["source"] as? String,
                raw: object["raw"] as? String ?? ""
            )
        case .plain:
            return nil
        }
    }

    /// Minimal RFC 4180 row reader — enough for the rows this app writes.
    static func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = row.makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { current.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }
}
