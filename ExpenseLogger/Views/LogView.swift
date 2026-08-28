import SwiftUI

struct LogView: View {
    @Bindable var store: LogStore
    @State private var showingRaw = false

    private var fileURL: URL { ExpenseLog.shared.fileURL }

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            totalsRow
                        }
                        Section("Transactions") {
                            ForEach(store.entries) { entry in
                                EntryRow(entry: entry)
                            }
                        }
                        if !store.reviewLines.isEmpty {
                            Section {
                                NavigationLink {
                                    ReviewListView(lines: store.reviewLines)
                                } label: {
                                    Label("\(store.reviewLines.count) needing review",
                                          systemImage: "questionmark.circle")
                                }
                            } footer: {
                                Text("Notifications that were ignored or could not be parsed. Nothing is thrown away.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Expense Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingRaw = true } label: { Image(systemName: "doc.plaintext") }
                        .disabled(store.entries.isEmpty && store.fileSize == 0)
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showingRaw) { RawFileView() }
        }
    }

    private var totalsRow: some View {
        HStack {
            TotalTile(title: "Today", amount: store.total(since: Calendar.current.startOfDay(for: Date())),
                      currency: store.currency)
            Divider()
            TotalTile(title: "This month",
                      amount: store.total(since: Calendar.current.dateInterval(of: .month, for: Date())?.start),
                      currency: store.currency)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No expenses logged yet", systemImage: "tray")
        } description: {
            Text("Set up a trigger in the Setup tab, or paste a notification into the Test tab to try the parser.")
        }
    }
}

private struct TotalTile: View {
    let title: String
    let amount: Decimal
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(LogLine.amountString(amount)) \(currency)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EntryRow: View {
    let entry: LoggedEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.merchant).font(.body)
                HStack(spacing: 6) {
                    Text(entry.date, format: .dateTime.day().month().hour().minute())
                    if let card = entry.card { Text("•\(card)") }
                    if let source = entry.source { Text(source) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(LogLine.amountString(entry.amount)) \(entry.currency)")
                .monospacedDigit()
                .foregroundStyle(entry.amount < 0 ? .primary : Color.green)
        }
    }
}

private struct ReviewListView: View {
    let lines: [String]

    var body: some View {
        List(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(line).font(.footnote.monospaced())
        }
        .navigationTitle("Needs review")
    }
}

private struct RawFileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var contents = ""

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(contents.isEmpty ? "(empty)" : contents)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle(AppSettings.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { contents = await ExpenseLog.shared.rawContents() }
        }
    }
}
