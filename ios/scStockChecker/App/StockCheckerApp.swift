import SwiftUI

@main
struct StockCheckerApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.start() }
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store

    var body: some View {
        if !AppConfig.isConfigured {
            ContentUnavailableView(
                "Sunucu ayarı eksik",
                systemImage: "gearshape.2",
                description: Text("ios/Config/App.xcconfig içindeki SUPABASE_URL ve SUPABASE_ANON_KEY değerlerini doldurun.")
            )
        } else if store.isRestoring {
            ProgressView()
        } else if store.userId == nil {
            LoginView()
        } else {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ItemsView()
                .tabItem { Label("Takip", systemImage: "bag") }
            WatchlistsView()
                .tabItem { Label("Listeler", systemImage: "heart.text.square") }
            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "gearshape") }
        }
    }
}
