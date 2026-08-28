import SwiftUI

/// In-app version of docs/TRIGGERS.md. iOS has no API for reading another
/// app's notifications, so this screen is where the app explains what it
/// actually needs to be fed by.
struct SetupView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("iOS will not let any app read your bank app's notifications",
                              systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text("There is no public API for it — that is an Apple platform restriction, not a missing feature here. Instead, pick a trigger below that hands the text to this app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                TriggerSection(
                    title: "1. Bank text messages",
                    subtitle: "Best option — fully on-device, no Mac needed",
                    reliability: "Reliable",
                    steps: [
                        "Turn on SMS alerts in your bank's app. For Banco Industrial, that is the alert settings in Bi en Línea.",
                        "Shortcuts ▸ Automation ▸ + ▸ Message.",
                        "Set Sender to your bank, or Message Contains a word its alerts always use (Compra, Consumo).",
                        "Choose Run Immediately and turn off Notify When Run.",
                        "Add action: Log Expense from Text, and set Notification Text to the Shortcut Input variable.",
                    ]
                )

                TriggerSection(
                    title: "2. Bank email alerts",
                    subtitle: "Same idea, using the Email automation trigger",
                    reliability: "Reliable",
                    steps: [
                        "Turn on per-transaction email alerts at your bank.",
                        "Shortcuts ▸ Automation ▸ + ▸ Email, filtered by sender.",
                        "Run Immediately, then add Log Expense from Text.",
                        "Pass the email body as the Notification Text.",
                    ]
                )

                TriggerSection(
                    title: "3. Real push notifications, via a Mac",
                    subtitle: "The only route that reads actual push alerts",
                    reliability: "Best-effort",
                    steps: [
                        "Requires a Mac running iPhone Mirroring with notifications forwarded.",
                        "Run bridge/notification_bridge.py from this repo on the Mac.",
                        "Grant the terminal Full Disk Access so it can read Notification Center.",
                        "It appends to the same text file, which you can keep in iCloud Drive.",
                        "Only works while the Mac is awake and mirroring — see docs/TRIGGERS.md.",
                    ]
                )

                TriggerSection(
                    title: "4. Manual capture",
                    subtitle: "Fallback for one-offs",
                    reliability: "Always works",
                    steps: [
                        "Copy the notification text.",
                        "Open the Test tab, tap Paste from clipboard, then Log this now.",
                    ]
                )

                Section {
                    Text("Whichever route you use, test it in the Test tab first with a real notification so you know the amount and merchant come out right.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Setup")
        }
    }
}

private struct TriggerSection: View {
    let title: String
    let subtitle: String
    let reliability: String
    let steps: [String]

    var body: some View {
        Section {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(step).font(.callout)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(subtitle) · \(reliability)")
                    .font(.caption2)
                    .textCase(nil)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
