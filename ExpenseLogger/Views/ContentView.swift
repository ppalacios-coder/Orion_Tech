import SwiftUI

@MainActor
struct ContentView: View {
    @State private var store = LogStore()

    var body: some View {
        TabView {
            LogView(store: store)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            TestParserView(store: store)
                .tabItem { Label("Test", systemImage: "text.magnifyingglass") }
            SetupView()
                .tabItem { Label("Setup", systemImage: "bolt.horizontal") }
            SettingsView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { await store.refresh() }
    }
}

#Preview {
    ContentView()
}
