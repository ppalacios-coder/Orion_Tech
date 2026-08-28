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

    // The first two are the shape Banco Industrial card alerts arrive in:
    // issuer, then merchant, then amount, each on its own line.
    private static let examples = [
        "Banco Industrial\nCircus Coffee\nGTQ 26.00",
        "Banco Industrial\nParqueo Cayala\nGTQ 15.00",
        "Banco Industrial: Compra por Q1,234.56 en SUPER 24 con tarjeta terminación 1234",
        "Transacción realizada por GTQ 350.00 en FARMACIA GALENO",
        "Banco Industrial: Compra por US$25.00 en AMAZON MKTP",
        "Acreditamiento por Q1,000.00 de DEVOLUCION COMERCIO",
    ]
}
