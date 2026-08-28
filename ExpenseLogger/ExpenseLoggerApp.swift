import SwiftUI

@main
struct ExpenseLoggerApp: App {
    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
