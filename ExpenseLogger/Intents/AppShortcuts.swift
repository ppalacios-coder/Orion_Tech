import AppIntents

/// Surfaces a couple of intents as ready-made Siri phrases. Every intent in the
/// app is available in the Shortcuts app regardless of what is listed here.
struct ExpenseLoggerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SpendSummaryIntent(),
            phrases: [
                "How much have I spent in \(.applicationName)",
                "Show my spending in \(.applicationName)",
            ],
            shortTitle: "Spend total",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: ExpenseLogFileIntent(),
            phrases: [
                "Get my \(.applicationName) file",
                "Export my \(.applicationName) log",
            ],
            shortTitle: "Export log",
            systemImageName: "square.and.arrow.up"
        )
    }
}
