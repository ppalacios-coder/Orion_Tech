import AppIntents
import Foundation

enum SummaryPeriod: String, AppEnum {
    case today, week, month, all

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static var caseDisplayRepresentations: [SummaryPeriod: DisplayRepresentation] = [
        .today: "Today",
        .week: "This week",
        .month: "This month",
        .all: "All time",
    ]

    /// Plain-text name, for building dialog strings. `DisplayRepresentation`
    /// titles are `LocalizedStringResource` and do not interpolate cleanly.
    var label: String {
        switch self {
        case .today: "Today"
        case .week: "This week"
        case .month: "This month"
        case .all: "All time"
        }
    }

    /// Start of the period, or nil for all time.
    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .today: calendar.startOfDay(for: now)
        case .week: calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .month: calendar.dateInterval(of: .month, for: now)?.start
        case .all: nil
        }
    }
}

/// "Hey Siri, how much have I spent today" — reads the log back and totals it.
struct SpendSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Spend Total"
    static var description = IntentDescription(
        "Totals the expenses in your log for a period.",
        categoryName: "Reporting"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Period", default: .today)
    var period: SummaryPeriod

    static var parameterSummary: some ParameterSummary {
        Summary("Total spend for \(\.$period)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let entries = await ExpenseLog.shared.entries(limit: 5000)
        let start = period.startDate()
        let relevant = entries.filter { entry in
            guard let start else { return true }
            return entry.date >= start
        }

        // Log amounts are signed: spending is negative, refunds positive.
        let net = relevant.reduce(Decimal(0)) { $0 + $1.amount }
        let spend = -net
        let currency = relevant.first?.currency ?? AppSettings.defaultCurrency
        let value = NSDecimalNumber(decimal: spend).doubleValue

        let label = period.label
        let dialog = relevant.isEmpty
            ? IntentDialog("Nothing logged for that period yet.")
            : IntentDialog("\(label): \(LogLine.amountString(spend)) \(currency) across \(relevant.count) transactions.")

        return .result(value: value, dialog: dialog)
    }
}
