import XCTest
@testable import ExpenseLogger

/// Runs the shared corpus (fixtures/samples.json) through the Swift parser.
/// The Python reference implementation runs the same file in
/// bridge/test_parser.py — if you change a rule, both suites must stay green.
final class ExpenseParserTests: XCTestCase {

    private struct Corpus: Decodable {
        struct Sample: Decodable {
            struct Expectation: Decodable {
                let kind: String
                let amount: String?
                let currency: String?
                let merchant: String?
                let card: String?
            }
            let id: String
            let text: String
            let expect: Expectation
        }
        let samples: [Sample]
    }

    private static let receivedAt = Date(timeIntervalSince1970: 1_787_923_391)

    private func loadCorpus() throws -> Corpus {
        let bundleURL = Bundle(for: Self.self).url(forResource: "samples", withExtension: "json")
        // Fall back to the source tree so the suite still runs if the resource
        // has not been copied into the test bundle.
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/samples.json")

        guard let url = bundleURL ?? (FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : nil) else {
            throw XCTSkip("fixtures/samples.json not found")
        }
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    func testCorpus() throws {
        let corpus = try loadCorpus()
        XCTAssertFalse(corpus.samples.isEmpty, "corpus should not be empty")

        for sample in corpus.samples {
            let parsed = ExpenseParser.parse(sample.text, source: "test", receivedAt: Self.receivedAt)
            let expected = sample.expect

            XCTAssertEqual(parsed.kind.rawValue, expected.kind,
                           "\(sample.id): reason=\(parsed.reason ?? "-")")
            if let amount = expected.amount {
                XCTAssertEqual(parsed.amount,
                               Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")),
                               sample.id)
            }
            if let currency = expected.currency {
                XCTAssertEqual(parsed.currency, currency, sample.id)
            }
            if let merchant = expected.merchant {
                XCTAssertEqual(parsed.merchant, merchant, sample.id)
            }
            if let card = expected.card {
                XCTAssertEqual(parsed.card, card, sample.id)
            }
        }
    }

    // MARK: - Amount normalisation

    func testEuropeanGroupingAndDecimals() {
        XCTAssertEqual(ExpenseParser.normalizeAmount("1.234,56", currency: "EUR"), Decimal(string: "1234.56"))
        XCTAssertEqual(ExpenseParser.normalizeAmount("1.500", currency: "EUR"), Decimal(1500))
        XCTAssertEqual(ExpenseParser.normalizeAmount("24,50", currency: "EUR"), Decimal(string: "24.50"))
    }

    func testUnitedStatesGroupingAndDecimals() {
        XCTAssertEqual(ExpenseParser.normalizeAmount("1,234.56", currency: "USD"), Decimal(string: "1234.56"))
        XCTAssertEqual(ExpenseParser.normalizeAmount("1,500", currency: "USD"), Decimal(1500))
        XCTAssertEqual(ExpenseParser.normalizeAmount("24.50", currency: "USD"), Decimal(string: "24.50"))
    }

    func testMillionsWithRepeatedGroupSeparators() {
        XCTAssertEqual(ExpenseParser.normalizeAmount("1.234.567", currency: "EUR"), Decimal(1_234_567))
        XCTAssertEqual(ExpenseParser.normalizeAmount("1,234,567", currency: "USD"), Decimal(1_234_567))
    }

    // MARK: - Behaviour

    func testBalanceAmountIsNotPreferredOverTheSpend() {
        let parsed = ExpenseParser.parse("You spent $12.00 at CVS. Available balance: $1,203.11")
        XCTAssertEqual(parsed.amount, Decimal(string: "12.00"))
    }

    func testRefundIsRecordedAsPositive() {
        let parsed = ExpenseParser.parse("Refund of $30.00 from ZARA has been credited")
        XCTAssertEqual(parsed.kind, .credit)
        XCTAssertEqual(parsed.signedAmount, Decimal(30))
    }

    func testExpenseIsRecordedAsNegative() {
        let parsed = ExpenseParser.parse("You spent $30.00 at ZARA")
        XCTAssertEqual(parsed.kind, .expense)
        XCTAssertEqual(parsed.signedAmount, Decimal(-30))
    }

    func testOneTimeCodeIsNeverLogged() {
        let parsed = ExpenseParser.parse("Tu código de verificación es 483920")
        XCTAssertEqual(parsed.kind, .ignored)
        XCTAssertFalse(parsed.isLoggable)
    }

    func testUnknownCurrencyFallsBackToTheDefault() {
        let parsed = ExpenseParser.parse("Compra de 12,00 en LIDL", defaultCurrency: "EUR")
        XCTAssertEqual(parsed.currency, "EUR")
        XCTAssertLessThan(parsed.confidence, 1.0)
    }

    func testEmptyTextIsNotLoggable() {
        let parsed = ExpenseParser.parse("   ")
        XCTAssertEqual(parsed.kind, .unparsed)
        XCTAssertEqual(parsed.reason, "empty")
    }

    func testDedupeKeyIsStableForIdenticalTextAndDiffersOtherwise() {
        let first = ExpenseParser.parse("You spent $8.00 at LIDL", receivedAt: Self.receivedAt)
        let second = ExpenseParser.parse("You spent $8.00 at LIDL", receivedAt: Self.receivedAt.addingTimeInterval(30))
        let other = ExpenseParser.parse("You spent $9.00 at LIDL", receivedAt: Self.receivedAt)
        XCTAssertEqual(first.dedupeKey, second.dedupeKey)
        XCTAssertNotEqual(first.dedupeKey, other.dedupeKey)
    }
}
