import SwiftUI
import UIKit

/// Paste a real notification here to see exactly how it will be parsed and what
/// line would be written. The fastest way to tune rules for your own bank.
struct TestParserView: View {
    @Bindable var store: LogStore
    @State private var text = ""
    @State private var statusMessage: String?

    private var parsed: ParsedExpense? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ExpenseParser.parse(trimmed, source: "Test", defaultCurrency: AppSettings.defaultCurrency)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Notification text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 110)
                        .font(.body)
                    Button {
                        if let clipboard = UIPasteboard.general.string { text = clipboard }
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }
                }

                if let parsed {
                    Section("Result") {
                        LabeledContent("Type", value: parsed.kind.rawValue)
                        if let amount = parsed.amount {
                            LabeledContent("Amount", value: "\(LogLine.amountString(amount)) \(parsed.currency ?? "")")
                        }
                        LabeledContent("Merchant", value: parsed.merchant ?? "—")
                        LabeledContent("Card", value: parsed.card.map { "•\($0)" } ?? "—")
                        LabeledContent("Confidence", value: String(format: "%.2f", parsed.confidence))
                        if let reason = parsed.reason {
                            LabeledContent("Reason", value: reason)
                        }
                    }

                    Section("Line that would be written") {
                        Text(LogLine.render(parsed, format: AppSettings.format))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }

                    Section {
                        Button {
                            Task { await log(parsed) }
                        } label: {
                            Label("Log this now", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!parsed.isLoggable)
                    } footer: {
                        if let statusMessage { Text(statusMessage) }
                    }
                }

                Section("Examples") {
                    ForEach(Self.examples, id: \.self) { example in
                        Button(example) { text = example }
                            .font(.caption)
                            .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Test parser")
        }
    }

    private func log(_ parsed: ParsedExpense) async {
        do {
            let outcome = try await ExpenseLog.shared.append(parsed)
            statusMessage = outcome.summary
            await store.refresh()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private static let examples = [
        "Chase: You spent $24.50 at STARBUCKS #4821 with card ending in 1234",
        "BBVA: Compra de 45,20 EUR en MERCADONA con tarjeta *1234",
        "Payment of £9.99 to NETFLIX.COM was made from your account",
        "Refund of $30.00 from ZARA has been credited to your card ending 1234",
    ]
}
