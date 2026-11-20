import Foundation
import Observation
import Supabase

enum AppConfig {
    static let supabaseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        return URL(string: raw) ?? URL(string: "https://invalid.supabase.co")!
    }()

    static let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""

    static var isConfigured: Bool { !supabaseURL.absoluteString.contains("YOUR-PROJECT") && !supabaseKey.contains("YOUR-") }

    /// Optional test account from Local.xcconfig (AUTO_LOGIN_USER / AUTO_LOGIN_PASSWORD):
    /// when set, the app signs in by itself instead of showing the login screen.
    static var autoLogin: (user: String, password: String)? {
        let user = (Bundle.main.object(forInfoDictionaryKey: "AutoLoginUser") as? String ?? "").trimmingCharacters(in: .whitespaces)
        let password = Bundle.main.object(forInfoDictionaryKey: "AutoLoginPassword") as? String ?? ""
        return user.isEmpty || password.isEmpty ? nil : (user, password)
    }
}

let supabase = SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)

/// App-wide state: the signed-in session and the user's data.
@MainActor
@Observable
final class Store {
    var userId: UUID?
    var isRestoring = true
    var items: [TrackedItem] = []
    var watchlists: [Watchlist] = []
    var profile: Profile?
    var events: [StockEvent] = []
    var runs: [CheckRun] = []
    /// Seconds between server-side checks (app_settings, shared by all users).
    var checkInterval = 30
    var errorMessage: String?

    /// Events newer than this were not seen in the history screen yet (bell badge).
    var eventsSeenAt: Date = (UserDefaults.standard.object(forKey: "eventsSeenAt") as? Date) ?? .distantPast {
        didSet { UserDefaults.standard.set(eventsSeenAt, forKey: "eventsSeenAt") }
    }
    var unseenEventCount: Int { events.filter { $0.startedAt > eventsSeenAt }.count }

    func item(id: UUID?) -> TrackedItem? { id.flatMap { id in items.first { $0.id == id } } }

    /// The session is stored in the keychain by the Supabase SDK, so the user stays
    /// signed in across launches until they sign out.
    func start() async {
        for await (event, session) in supabase.auth.authStateChanges {
            if event == .initialSession, session == nil, let login = AppConfig.autoLogin,
               (try? await signIn(username: login.user, password: login.password)) != nil {
                continue // the .signedIn event that follows carries the session
            }
            userId = session?.user.id
            isRestoring = false
            if userId != nil { await reload() } else { clear() }
        }
    }

    /// Users sign in with a short user name (e.g. "admin"); Supabase needs an email,
    /// so a bare name is mapped to <name>@stoktakip.app. Supabase also requires
    /// passwords of 6+ characters, so the typed password is wrapped the same way
    /// every time and accounts are created with the wrapped form.
    func signIn(username: String, password: String) async throws {
        let name = username.trimmingCharacters(in: .whitespaces).lowercased()
        let email = name.contains("@") ? name : "\(name)@stoktakip.app"
        try await supabase.auth.signIn(email: email, password: "sc-\(password)-stoktakip")
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    private func clear() {
        items = []; watchlists = []; profile = nil; events = []; runs = []
    }

    func reload() async {
        do {
            async let items: [TrackedItem] = supabase.from("tracked_items")
                .select().order("created_at", ascending: false).execute().value
            async let lists: [Watchlist] = supabase.from("watchlists")
                .select().order("created_at", ascending: false).execute().value
            async let profiles: [Profile] = supabase.from("profiles").select().execute().value
            async let events: [StockEvent] = supabase.from("stock_events")
                .select().order("started_at", ascending: false).limit(200).execute().value
            async let runs: [CheckRun] = supabase.from("check_runs")
                .select().order("started_at", ascending: false).limit(100).execute().value
            async let settings: [AppSettings] = supabase.from("app_settings").select().execute().value
            (self.items, self.watchlists, self.events, self.runs) = try await (items, lists, events, runs)
            if let interval = try await settings.first?.checkIntervalSeconds { checkInterval = interval }
            self.profile = try await profiles.first
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resolve(_ url: String) async throws -> ResolvedLink {
        try await supabase.functions.invoke("resolve-link", options: .init(body: ["url": url]))
    }

    func addItem(product: ResolvedProduct, color: ResolvedColor, wantedSizes: [String]) async throws {
        struct NewItem: Encodable {
            let brand, url, name: String
            let external_id, color_id, color_name: String
            let image_url: String?
            let price: Double?
            let currency: String?
            let wanted_sizes: [String]
        }
        try await supabase.from("tracked_items").insert(NewItem(
            brand: product.brand, url: product.url, name: product.name,
            external_id: product.externalId, color_id: color.id, color_name: color.name,
            image_url: color.imageUrl, price: color.price, currency: product.currency,
            wanted_sizes: wantedSizes
        )).execute()
        await reload()
    }

    func addWatchlist(url: String, brand: String, name: String?, wantedSizes: [String]) async throws {
        struct NewList: Encodable {
            let brand, url: String
            let name: String?
            let wanted_sizes: [String]
        }
        try await supabase.from("watchlists")
            .insert(NewList(brand: brand, url: url, name: name, wanted_sizes: wantedSizes)).execute()
        await reload()
    }

    func updateWantedSizes(item: TrackedItem, sizes: [String]) async throws {
        try await supabase.from("tracked_items").update(["wanted_sizes": sizes]).eq("id", value: item.id).execute()
        await reload()
    }

    func setActive(item: TrackedItem, _ active: Bool) async throws {
        try await supabase.from("tracked_items").update(["active": active]).eq("id", value: item.id).execute()
        await reload()
    }

    func delete(item: TrackedItem) async throws {
        try await supabase.from("tracked_items").delete().eq("id", value: item.id).execute()
        items.removeAll { $0.id == item.id }
    }

    func updateWatchlistSizes(_ list: Watchlist, sizes: [String]) async throws {
        try await supabase.from("watchlists").update(["wanted_sizes": sizes]).eq("id", value: list.id).execute()
        try await supabase.from("tracked_items").update(["wanted_sizes": sizes]).eq("watchlist_id", value: list.id).execute()
        await reload()
    }

    func delete(watchlist: Watchlist) async throws {
        try await supabase.from("watchlists").delete().eq("id", value: watchlist.id).execute()
        await reload()
    }

    func setCheckInterval(_ seconds: Int) async throws {
        checkInterval = seconds
        try await supabase.from("app_settings").update(["check_interval_seconds": seconds]).eq("id", value: 1).execute()
    }

    func saveNtfyTopic(_ topic: String) async throws {
        guard let userId else { return }
        try await supabase.from("profiles").update(["ntfy_topic": topic]).eq("user_id", value: userId).execute()
        await reload()
    }
}
