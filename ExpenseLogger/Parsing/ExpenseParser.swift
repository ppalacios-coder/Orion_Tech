import Foundation

/// Turns the text of a bank notification into a `ParsedExpense`.
///
/// Swift port of `bridge/expense_parser.py`. Both implementations are verified
/// against the same corpus (`fixtures/samples.json`) — when you change a rule
/// here, change it there too and rerun both test suites.
enum ExpenseParser {

    // MARK: - Currency

    static let symbols: [String: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "₱": "PHP",
        "Q": "GTQ",     // Guatemalan quetzal, written Q1,234.56 or Q. 45.00
    ]

    /// Symbols that are letters need a word-boundary check so "REQ12345" is not
    /// read as a currency, and may be followed by a full stop ("Q. 45.00").
    /// GTQ groups with "," and so is deliberately absent from `commaDecimal`.
    static let letterSymbols: Set<String> = ["Q"]

    static let isoCodes = [
        "EUR", "USD", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD", "SEK", "NOK", "DKK",
        "PLN", "CZK", "HUF", "RON", "TRY", "MXN", "COP", "CLP", "ARS", "PEN", "BRL",
        "UYU", "DOP", "GTQ", "CRC", "INR", "PHP", "CNY", "HKD", "SGD", "ZAR",
    ]

    /// Currencies conventionally written `1.234,56`.
    static let commaDecimal: Set<String> = [
        "EUR", "ARS", "BRL", "CLP", "COP", "CZK", "DKK", "HUF", "IDR", "ISK",
        "NOK", "PLN", "RON", "SEK", "TRY", "UYU", "VND", "CRC",
    ]

    /// Grouping and decimal separators a currency is normally written with.
    static func convention(for currency: String?) -> (group: Character, decimal: Character) {
        if let currency, commaDecimal.contains(currency) { return (".", ",") }
        return (",", ".")
    }

    // MARK: - Vocabularies

    static let spendKeywords = [
        "spent", "purchase", "purchased", "paid", "payment", "charged", "charge",
        "was used", "transaction", "debit", "withdrawal", "compra", "cargo",
        "pago", "adeudo", "recibo", "domiciliado", "retirada", "gasto",
        "has realizado", "operacion", "operación",
        // Guatemala / Banco Industrial wording
        "consumo", "transaccion", "transacción", "retiro", "transferencia",
        "debito", "débito", "rebajo", "cobro",
    ]

    static let creditKeywords = [
        "refund", "refunded", "credited", "credit of", "reversal", "reversed",
        "abono", "abonado", "devolucion", "devolución", "ingreso", "reembolso",
        "acreditamiento", "acreditado", "deposito", "depósito", "nota de credito",
    ]

    static let balanceKeywords = [
        "balance", "saldo", "disponible", "available", "limit", "límite", "limite",
        "restante", "remaining",
    ]

    /// Merchant-introducing words, most specific first.
    static let merchantKeywords = [
        "at", "en", "to", "from", "a favor de", "para", "comercio", "merchant",
        "de", "in", "a",
    ]

    static let merchantBlocklist: Set<String> = [
        "your account", "the account", "tu cuenta", "su cuenta", "account", "cuenta",
        "your card", "tu tarjeta", "la tarjeta", "card", "tarjeta", "us", "you",
        "your", "tu", "su", "mi", "la", "el", "los", "las", "the", "a", "an",
        "efectivo", "cash", "compra", "pago",
    ]

    // MARK: - Patterns

    static let merchantTerminators = Rx(
        #"\s+(?:was|were|on|with|using|from|por|by|con|mediante|via|el\s+d[ií]a|"# +
        #"tarjeta|card|ha\s+sido|han\s+sido|has\s+been|have\s+been|"# +
        #"en\s+(?:tu|su|la|el|nuestra)|balance|saldo|available|disponible)\b"# +
        #"|\.(?=\s|$)|[;,\n]|\s+-\s+|\s*\|\s*"#
    )

    static let ignoreRules: [(reason: String, rule: Rx)] = [
        ("otp", Rx(#"\b(?:c[oó]digo|code|otp|clave|token)\b[^\n]{0,40}?\b\d{4,8}\b"#)),
        ("otp", Rx(#"\b(?:verification|verificaci[oó]n|autenticaci[oó]n|one[- ]time|un solo uso)\b"#)),
        ("signin", Rx(#"\b(?:sign[- ]?in|signed in|inicio de sesi[oó]n|log[- ]?in|logged in|"# +
                      #"acceso a tu cuenta|ingreso exitoso|nuevo dispositivo)\b"#)),
        ("statement", Rx(#"\b(?:statement|extracto)\b[^\n]{0,30}\b(?:ready|available|disponible)\b"#)),
        ("promo", Rx(#"\d+\s*%[^\n]{0,30}\b(?:descuento|off|cashback|dto)\b"#)),
        ("promo", Rx(#"\b(?:oferta especial|promoci[oó]n|promotional)\b"#)),
        ("security", Rx(#"\b(?:password|contrase[nñ]a|pin)\b[^\n]{0,30}\b(?:changed|updated|cambiad|actualizad)"#)),
    ]

    /// Digits introduced by the word "card"/"tarjeta", so an account number in
    /// the same alert ("cuenta *4567, tarjeta terminación 1234") is not taken.
    static let cardContextRegex = Rx(
        #"(?:tarjeta|card)[^\n]{0,25}?"# +
        #"(?:terminaci[oó]n(?:\s+en)?|terminada\s+en|termina\s+en|acabada\s+en|final|"# +
        #"ending(?:\s+in|\s+with)?|\*+|x{2,}|•{2,})\s*(\d{4})\b"#
    )

    static let cardRegex = Rx(
        #"(?:ending(?:\s+in|\s+with)?|terminaci[oó]n(?:\s+en)?|terminada\s+en|termina\s+en|"# +
        #"acabada\s+en|final|\*+|x{2,}|•{2,})\s*(\d{4})\b"#
    )

    static let amountRegex: Rx = {
        let symbolClass = symbols.keys
            .filter { !letterSymbols.contains($0) }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined()
        let letterAlt = letterSymbols.sorted()
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let isoAlt = isoCodes.joined(separator: "|")
        let number = #"\d[\d.,  ]*\d|\d"#
        // A currency marker before the amount ("Q. 45.00", "$24.50") or after
        // it ("45,20 EUR").
        let before = "(?:(?<cur1>[\(symbolClass)])"
            + "|(?<!\\p{L})(?<lsym1>\(letterAlt))\\.?"
            + "|(?<!\\p{L})(?<iso1>\(isoAlt))(?!\\p{L}))"
        let after = "(?:(?<cur2>[\(symbolClass)])"
            + "|(?<!\\p{L})(?<lsym2>\(letterAlt))"
            + "|(?<!\\p{L})(?<iso2>\(isoAlt))(?!\\p{L}))"
        return Rx("\(before)\\s*(?<amt1>\(number))|(?<amt2>\(number))\\s*\(after)")
    }()

    // MARK: - Amount normalisation

    /// Reads `1.234,56`, `1,234.56`, `1.500`, `24,50` etc. into a `Decimal`.
    static func normalizeAmount(_ raw: String, currency: String?) -> Decimal? {
        var s = raw.replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        let groupSep = convention(for: currency).group
        let hasDot = s.contains("."), hasComma = s.contains(",")

        if hasDot && hasComma {
            // Whichever separator comes last is the decimal one.
            let decimalSep: Character = s.lastIndex(of: ".")! > s.lastIndex(of: ",")! ? "." : ","
            let groupingSep: Character = decimalSep == "." ? "," : "."
            s = s.replacingOccurrences(of: String(groupingSep), with: "")
            s = s.replacingOccurrences(of: String(decimalSep), with: ".")
        } else if hasDot || hasComma {
            let sep: Character = hasDot ? "." : ","
            let parts = s.split(separator: sep, omittingEmptySubsequences: false)
            if parts.count > 2 {
                s = s.replacingOccurrences(of: String(sep), with: "")   // 1.234.567
            } else {
                switch parts[1].count {
                case 3:
                    // Ambiguous (1,234 / 1.234): grouping when it matches the
                    // currency's own convention, otherwise a decimal separator.
                    s = sep == groupSep
                        ? s.replacingOccurrences(of: String(sep), with: "")
                        : s.replacingOccurrences(of: String(sep), with: ".")
                case 1, 2:
                    s = s.replacingOccurrences(of: String(sep), with: ".")
                default:
                    s = s.replacingOccurrences(of: String(sep), with: "")
                }
            }
        }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Amount candidates

    private struct AmountCandidate {
        var value: Decimal
        var currency: String
        var explicitCurrency: Bool
        var start: Int
        var end: Int
        var score: Double
    }

    private static func findAmounts(in text: NSString, defaultCurrency: String) -> [AmountCandidate] {
        return amountRegex.matches(in: text).compactMap { match in
            let symbol = match.group("cur1") ?? match.group("cur2")
                ?? match.group("lsym1") ?? match.group("lsym2")
            let iso = match.group("iso1") ?? match.group("iso2")
            guard let raw = match.group("amt1") ?? match.group("amt2") else { return nil }

            let currency = symbol.flatMap { symbols[$0.uppercased()] } ?? iso?.uppercased()
            guard let value = normalizeAmount(raw, currency: currency) else { return nil }

            // Prefer amounts introduced by spending language; demote balances.
            let windowStart = max(0, match.start - 45)
            // Lowercase the window itself: lowercasing the whole string first
            // can shift UTF-16 offsets away from the match ranges.
            let window = text.substring(with: NSRange(location: windowStart,
                                                      length: match.start - windowStart)).lowercased()
            var score = 0.0
            if balanceKeywords.contains(where: window.contains) { score -= 2.0 }
            if spendKeywords.contains(where: window.contains) { score += 1.0 }
            if creditKeywords.contains(where: window.contains) { score += 1.0 }
            score -= Double(match.start) / 10_000.0     // tie-break toward the earliest

            return AmountCandidate(
                value: value,
                currency: currency ?? defaultCurrency,
                explicitCurrency: currency != nil,
                start: match.start,
                end: match.end,
                score: score
            )
        }
    }

    // MARK: - Merchant

    static func cleanMerchant(_ raw: String) -> String {
        var text = raw
        if let cut = merchantTerminators.firstMatch(in: text as NSString) {
            text = (text as NSString).substring(to: cut.start)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t,;:·-—–"))
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(text.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    /// Looks for the merchant after the amount first, then anywhere in the text.
    private static func findMerchant(in text: NSString, after: Int) -> (name: String?, viaKeyword: Bool) {
        for regionStart in [after, 0] where regionStart <= text.length {
            let region = text.substring(from: regionStart) as NSString

            for keyword in merchantKeywords {
                let escaped = NSRegularExpression.escapedPattern(for: keyword)
                for match in Rx("(?<!\\p{L})\(escaped)\\s+").matches(in: region) {
                    let candidate = cleanMerchant(region.substring(from: match.end))
                    if candidate.isEmpty { continue }
                    if merchantBlocklist.contains(candidate.lowercased()) { continue }
                    if candidate.range(of: #"^[\d.,\s]+$"#, options: .regularExpression) != nil { continue }
                    return (candidate, true)
                }
            }

            // Fallback: a run of upper-case tokens, typical of card-network text.
            let caps = Rx(#"\b[A-Z0-9][A-Z0-9&.'*/-]{2,}(?:\s+[A-Z0-9][A-Z0-9&.'*/-]*){0,3}"#, options: [])
            for match in caps.matches(in: region) {
                guard let raw = match.group(0) else { continue }
                if merchantBlocklist.contains(raw.lowercased()) { continue }
                if isoCodes.contains(raw.uppercased()) { continue }
                return (cleanMerchant(raw), false)
            }
        }
        return (nil, false)
    }

    // MARK: - Entry point

    static func parse(
        _ text: String,
        source: String? = nil,
        receivedAt: Date = Date(),
        defaultCurrency: String = "GTQ"
    ) -> ParsedExpense {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ParsedExpense(kind: .unparsed, raw: raw, receivedAt: receivedAt, source: source)
        guard !raw.isEmpty else {
            result.reason = "empty"
            return result
        }

        let ns = raw as NSString
        let lowered = raw.lowercased()

        for (reason, rule) in ignoreRules where rule.containsMatch(in: ns) {
            result.kind = .ignored
            result.reason = reason
            return result
        }

        let hasSpend = spendKeywords.contains(where: lowered.contains)
        let hasCredit = creditKeywords.contains(where: lowered.contains)
        if !hasSpend, !hasCredit, balanceKeywords.contains(where: lowered.contains) {
            result.kind = .ignored
            result.reason = "balance"
            return result
        }

        let candidates = findAmounts(in: ns, defaultCurrency: defaultCurrency)
        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            result.reason = "no-amount"
            return result
        }
        guard best.explicitCurrency || hasSpend || hasCredit else {
            result.reason = "no-currency"
            return result
        }

        let merchant = findMerchant(in: ns, after: best.end)

        result.kind = hasCredit ? .credit : .expense
        result.amount = best.value
        result.currency = best.currency
        result.merchant = merchant.name
        result.card = (cardContextRegex.firstMatch(in: ns) ?? cardRegex.firstMatch(in: ns))?.group(1)

        var confidence = 0.5
        if best.explicitCurrency { confidence += 0.2 }
        if merchant.name != nil { confidence += merchant.viaKeyword ? 0.2 : 0.1 }
        if result.card != nil { confidence += 0.1 }
        if hasSpend || hasCredit { confidence += 0.1 }
        result.confidence = min(1.0, (confidence * 100).rounded() / 100)

        return result
    }
}
