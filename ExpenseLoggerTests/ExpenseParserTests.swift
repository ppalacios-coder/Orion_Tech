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
                let expectNoMerchant: Bool?
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
            if expected.expectNoMerchant == true {
                XCTAssertNil(parsed.merchant, sample.id)
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

    // MARK: - Guatemala / Banco Industrial

    func testQuetzalSymbolIsRecognised() {
        let parsed = ExpenseParser.parse("Compra por Q1,234.56 en SUPER 24")
        XCTAssertEqual(parsed.currency, "GTQ")
        XCTAssertEqual(parsed.amount, Decimal(string: "1234.56"), "GTQ groups with a comma")
        XCTAssertEqual(parsed.merchant, "SUPER 24")
    }

    func testQuetzalWrittenWithAFullStop() {
        let parsed = ExpenseParser.parse("BI: Consumo Q. 45.00 en POLLO CAMPERO ZONA 10")
        XCTAssertEqual(parsed.currency, "GTQ")
        XCTAssertEqual(parsed.amount, Decimal(string: "45.00"))
    }

    func testALetterSymbolNeedsAWordBoundary() {
        // "Q" inside a word must not be read as a currency.
        let parsed = ExpenseParser.parse("REQ12345 no es una transaccion de dinero")
        XCTAssertNil(parsed.amount)
    }

    func testDollarAlertsFromAQuetzalBankStayInDollars() {
        let parsed = ExpenseParser.parse("Banco Industrial: Compra por US$25.00 en AMAZON MKTP")
        XCTAssertEqual(parsed.currency, "USD")
        XCTAssertEqual(parsed.amount, Decimal(25))
    }

    func testCardDigitsArePreferredOverAccountDigits() {
        let parsed = ExpenseParser.parse("Compra Q80.00 en LA TORRE, cuenta *4567, tarjeta terminación 1234")
        XCTAssertEqual(parsed.card, "1234", "the account number must not be taken for the card")
        XCTAssertEqual(parsed.merchant, "LA TORRE")
    }

    func testSecurityTokenIsNeverLogged() {
        XCTAssertEqual(ExpenseParser.parse("Su token de seguridad es 483920").kind, .ignored)
        XCTAssertEqual(ExpenseParser.parse("Ingreso exitoso a Bi en Línea desde un nuevo dispositivo").kind, .ignored)
    }

    func testAcreditamientoIsRecordedAsMoneyIn() {
        let parsed = ExpenseParser.parse("Acreditamiento por Q1,000.00 de DEVOLUCION COMERCIO")
        XCTAssertEqual(parsed.kind, .credit)
        XCTAssertEqual(parsed.signedAmount, Decimal(1000))
    }

    // MARK: - Wallet-style card alerts (issuer / merchant / amount)

    func testSubtitleIsUsedAsTheMerchant() {
        let parsed = ExpenseParser.parse(title: "Banco Industrial", subtitle: "Circus Coffee", body: "GTQ 26.00")
        XCTAssertEqual(parsed.kind, .expense)
        XCTAssertEqual(parsed.amount, Decimal(26))
        XCTAssertEqual(parsed.currency, "GTQ")
        XCTAssertEqual(parsed.merchant, "Circus Coffee")
    }

    func testLayoutGivesTheMerchantWhenThereIsNoWordingToKeyOff() {
        let parsed = ExpenseParser.parse("Banco Industrial\nParqueo Cayala\nGTQ 15.00")
        XCTAssertEqual(parsed.merchant, "Parqueo Cayala")
        XCTAssertEqual(parsed.amount, Decimal(15))
    }

    func testAmountIsNeverMistakenForTheMerchant() {
        let parsed = ExpenseParser.parse("Banco Industrial\nSocial Tickets\nGTQ 310.00")
        XCTAssertEqual(parsed.merchant, "Social Tickets")
        XCTAssertNotEqual(parsed.merchant, "GTQ 310.00")
    }

    func testMixedCaseMerchantSurvives() {
        // The all-caps fallback used to reduce "Cafe UFM" to "UFM".
        XCTAssertEqual(ExpenseParser.parse("Banco Industrial\nCafe UFM\nGTQ 44.00").merchant, "Cafe UFM")
    }

    func testIssuerNameIsNotUsedAsAMerchant() {
        let parsed = ExpenseParser.parse("Banco Industrial\nGTQ 15.00")
        XCTAssertEqual(parsed.amount, Decimal(15))
        XCTAssertNil(parsed.merchant, "with no subtitle there is no merchant")
    }

    func testATimestampLineIsSkipped() {
        let parsed = ExpenseParser.parse("Banco Industrial\n31m ago\nCircus Coffee\nGTQ 26.00")
        XCTAssertEqual(parsed.merchant, "Circus Coffee")
    }

    func testASubtitleThatIsOnlyAnAmountIsNotAMerchant() {
        let parsed = ExpenseParser.parse(title: "Banco Industrial", subtitle: "GTQ 26.00", body: nil)
        XCTAssertNotEqual(parsed.merchant, "GTQ 26.00")
    }

    func testSentenceStyleAlertsStillUseTheirWording() {
        let parsed = ExpenseParser.parse("Compra de 45,20 EUR en MERCADONA con tarjeta *1234")
        XCTAssertEqual(parsed.merchant, "MERCADONA")
    }

    func testDedupeKeyIsStableForIdenticalTextAndDiffersOtherwise() {
        let first = ExpenseParser.parse("You spent $8.00 at LIDL", receivedAt: Self.receivedAt)
        let second = ExpenseParser.parse("You spent $8.00 at LIDL", receivedAt: Self.receivedAt.addingTimeInterval(30))
        let other = ExpenseParser.parse("You spent $9.00 at LIDL", receivedAt: Self.receivedAt)
        XCTAssertEqual(first.dedupeKey, second.dedupeKey)
        XCTAssertNotEqual(first.dedupeKey, other.dedupeKey)
    }
}
