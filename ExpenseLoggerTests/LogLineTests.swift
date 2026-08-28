import XCTest
@testable import ExpenseLogger

final class LogLineTests: XCTestCase {

    private let sample = ExpenseParser.parse(
        "Chase: You spent $24.50 at STARBUCKS with card ending in 1234",
        source: "Chase",
        receivedAt: Date(timeIntervalSince1970: 1_787_923_391)
    )

    func testTabSeparatedLineHasEightColumns() {
        let fields = LogLine.render(sample, format: .tsv).components(separatedBy: "\t")
        XCTAssertEqual(fields.count, 8)
        XCTAssertEqual(fields[1], "-24.50")
        XCTAssertEqual(fields[2], "USD")
        XCTAssertEqual(fields[3], "STARBUCKS")
        XCTAssertEqual(fields[4], "1234")
    }

    func testNewlinesInRawTextNeverSplitALine() {
        let multiline = ExpenseParser.parse("Revolut\nYou spent $8.00 at LIDL\nBalance: $2.00")
        XCTAssertFalse(LogLine.render(multiline, format: .tsv).contains("\n"))
    }

    func testCommasAndQuotesAreEscapedForCSV() {
        let tricky = ExpenseParser.parse("You spent $5.00 at \"BAR, GRILL\"")
        let line = LogLine.render(tricky, format: .csv)
        XCTAssertFalse(line.contains("\n"))
        let fields = LogLine.parseCSVRow(line)
        XCTAssertEqual(fields.count, 8, "escaping must not change the column count")
    }

    func testTabSeparatedLineReadsBackIntoAnEntry() throws {
        let line = LogLine.render(sample, format: .tsv)
        let entry = try XCTUnwrap(LogLine.parse(line, format: .tsv))
        XCTAssertEqual(entry.amount, Decimal(string: "-24.50"))
        XCTAssertEqual(entry.merchant, "STARBUCKS")
        XCTAssertEqual(entry.card, "1234")
        XCTAssertEqual(entry.source, "Chase")
    }

    func testCSVLineReadsBackIntoAnEntry() throws {
        let line = LogLine.render(sample, format: .csv)
        let entry = try XCTUnwrap(LogLine.parse(line, format: .csv))
        XCTAssertEqual(entry.amount, Decimal(string: "-24.50"))
        XCTAssertEqual(entry.merchant, "STARBUCKS")
    }

    func testJSONLineReadsBackIntoAnEntry() throws {
        let line = LogLine.render(sample, format: .jsonl)
        let entry = try XCTUnwrap(LogLine.parse(line, format: .jsonl))
        XCTAssertEqual(entry.merchant, "STARBUCKS")
        XCTAssertEqual(entry.currency, "USD")
    }

    func testHeaderRowIsNotReadBackAsAnEntry() {
        XCTAssertNil(LogLine.parse(LogFormat.tsv.header ?? "", format: .tsv))
        XCTAssertNil(LogLine.parse("", format: .tsv))
    }

    func testUnparsedEntryStillRendersWithoutCrashing() {
        let unparsed = ExpenseParser.parse("Movimiento registrado en tu cuenta")
        XCTAssertFalse(LogLine.render(unparsed, format: .jsonl).isEmpty)
        XCTAssertFalse(LogLine.render(unparsed, format: .tsv).isEmpty)
    }
}
