import SwiftUI

struct SettingsView: View {
    @Bindable var store: LogStore

    @AppStorage(AppSettings.Key.fileName) private var fileName = "expenses.txt"
    @AppStorage(AppSettings.Key.format) private var format = LogFormat.tsv.rawValue
    @AppStorage(AppSettings.Key.defaultCurrency) private var defaultCurrency = "EUR"
    @AppStorage(AppSettings.Key.minimumConfidence) private var minimumConfidence = 0.5
    @AppStorage(AppSettings.Key.keepRejected) private var keepRejected = true
    @AppStorage(AppSettings.Key.dedupeWindow) private var dedupeWindow = 120.0

    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("File name", text: $fileName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Picker("Format", selection: $format) {
                        ForEach(LogFormat.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                } header: {
                    Text("Log file")
                } footer: {
                    Text("Saved in Files ▸ On My iPhone ▸ Expense Logger. Changing the format only affects new lines — start a new file if you switch.")
                }

                Section {
                    TextField("Default currency", text: $defaultCurrency)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Minimum confidence")
                            Spacer()
                            Text(String(format: "%.2f", minimumConfidence)).monospacedDigit()
                        }
                        Slider(value: $minimumConfidence, in: 0...1, step: 0.05)
                    }
                    Toggle("Keep rejected notifications", isOn: $keepRejected)
                } header: {
                    Text("Parsing")
                } footer: {
                    Text("Used when a notification names an amount but no currency. Anything below the confidence threshold goes to the review file instead of the log.")
                }

                Section {
                    Stepper(value: $dedupeWindow, in: 0...600, step: 30) {
                        Text("Ignore repeats within \(Int(dedupeWindow))s")
                    }
                } header: {
                    Text("Duplicates")
                } footer: {
                    Text("Automations sometimes fire twice for the same notification. Identical text inside this window is logged only once.")
                }

                Section("File") {
                    LabeledContent("Entries", value: "\(store.entries.count)")
                    LabeledContent("Size", value: "\(store.fileSize) bytes")
                    if FileManager.default.fileExists(atPath: ExpenseLog.shared.fileURL.path) {
                        ShareLink(item: ExpenseLog.shared.fileURL) {
                            Label("Export log file", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) { confirmingClear = true } label: {
                        Label("Delete log file", systemImage: "trash")
                    }
                } footer: {
                    if let error = store.lastError { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete the log file and start over?",
                                isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await store.clear() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. Export the file first if you want to keep it.")
            }
        }
    }
}
