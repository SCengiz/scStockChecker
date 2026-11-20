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
    var notifications: [SentNotification] = []
    var errorMessage: String?

    func start() async {
        for await (_, session) in supabase.auth.authStateChanges {
            userId = session?.user.id
            isRestoring = false
            if userId != nil { await reload() } else { clear() }
        }
    }

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    private func clear() {
        items = []; watchlists = []; profile = nil; notifications = []
    }

    func reload() async {
        do {
            async let items: [TrackedItem] = supabase.from("tracked_items")
                .select().order("created_at", ascending: false).execute().value
            async let lists: [Watchlist] = supabase.from("watchlists")
                .select().order("created_at", ascending: false).execute().value
            async let profiles: [Profile] = supabase.from("profiles").select().execute().value
            async let notes: [SentNotification] = supabase.from("notifications")
                .select().order("sent_at", ascending: false).limit(50).execute().value
            (self.items, self.watchlists, self.notifications) = try await (items, lists, notes)
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

    func saveNtfyTopic(_ topic: String) async throws {
        guard let userId else { return }
        try await supabase.from("profiles").update(["ntfy_topic": topic]).eq("user_id", value: userId).execute()
        await reload()
    }
}
