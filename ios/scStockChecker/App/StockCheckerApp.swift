import SwiftUI

@main
struct StockCheckerApp: App {
    @State private var store = Store()
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(theme.colorScheme)
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
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ItemsView()
                .tabItem { Label("Takip", systemImage: "bag") }
            LogView()
                .tabItem { Label("Log", systemImage: "waveform.path.ecg") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
        // The server checks every 10-30 s; refresh while the app is open so new results show up quickly.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.reload()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}
