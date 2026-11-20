import Foundation

enum Availability: String, Codable {
    case inStock = "in_stock"
    case lowOnStock = "low_on_stock"
    case outOfStock = "out_of_stock"
    case comingSoon = "coming_soon"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Availability(rawValue: raw) ?? .unknown
    }

    var isAvailable: Bool { self == .inStock || self == .lowOnStock }

    var label: String {
        switch self {
        case .inStock: "Stokta"
        case .lowOnStock: "Az kaldı"
        case .outOfStock: "Tükendi"
        case .comingSoon: "Yakında"
        case .unknown: "?"
        }
    }
}

struct StoredSize: Codable, Hashable {
    let name: String
    let availability: Availability
}

struct TrackedItem: Codable, Identifiable, Hashable {
    let id: UUID
    let watchlistId: UUID?
    let brand: String
    let url: String
    let name: String?
    let colorId: String?
    let colorName: String?
    let imageUrl: String?
    let price: Double?
    let currency: String?
    var wantedSizes: [String]
    let sizes: [StoredSize]
    var active: Bool
    let lastCheckedAt: Date?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, brand, url, name, price, currency, sizes, active
        case watchlistId = "watchlist_id"
        case colorId = "color_id"
        case colorName = "color_name"
        case imageUrl = "image_url"
        case wantedSizes = "wanted_sizes"
        case lastCheckedAt = "last_checked_at"
        case lastError = "last_error"
    }

    func isWanted(_ size: String) -> Bool {
        wantedSizes.isEmpty || wantedSizes.contains { Self.sizeKey($0) == Self.sizeKey(size) || $0.lowercased() == size.lowercased() }
    }

    /// "M (US M)" -> "m", so a typed "M" matches Zara's longer size labels (same rule as the server).
    static func sizeKey(_ s: String) -> String {
        shortSize(s).lowercased()
    }

    /// "M (US M)" -> "M" for compact display.
    static func shortSize(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Wanted sizes that are in stock right now.
    var availableWanted: [StoredSize] { sizes.filter { isWanted($0.name) && $0.availability.isAvailable } }

    var productURL: URL? {
        guard var c = URLComponents(string: url) else { return nil }
        if let colorId { c.queryItems = [URLQueryItem(name: "v1", value: colorId)] }
        return c.url
    }
}

struct Watchlist: Codable, Identifiable, Hashable {
    let id: UUID
    let brand: String
    let url: String
    let name: String?
    var wantedSizes: [String]
    let lastSyncedAt: Date?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, brand, url, name
        case wantedSizes = "wanted_sizes"
        case lastSyncedAt = "last_synced_at"
        case lastError = "last_error"
    }
}

struct Profile: Codable {
    let userId: UUID
    var displayName: String?
    var ntfyTopic: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case ntfyTopic = "ntfy_topic"
    }
}

/// One server-side check of all tracked items.
struct CheckRun: Codable, Identifiable, Hashable {
    let id: Int
    let startedAt: Date
    let durationMs: Int
    let listsSynced: Int
    let itemsChecked: Int
    let itemsFailed: Int
    let cameIn: Int
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, error
        case startedAt = "started_at"
        case durationMs = "duration_ms"
        case listsSynced = "lists_synced"
        case itemsChecked = "items_checked"
        case itemsFailed = "items_failed"
        case cameIn = "came_in"
    }

    var isHealthy: Bool { error == nil && itemsFailed == 0 }
}

/// "12 sn önce" style text, updated by the caller (e.g. inside a TimelineView).
func agoText(_ date: Date?, now: Date = .now) -> String {
    guard let date else { return "henüz yok" }
    let s = max(0, Int(now.timeIntervalSince(date)))
    switch s {
    case ..<60: return "\(s) sn önce"
    case ..<3600: return "\(s / 60) dk önce"
    case ..<86400: return "\(s / 3600) sa önce"
    default: return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A wanted size that came into stock; `endedAt` is set once it sold out again.
struct StockEvent: Codable, Identifiable, Hashable {
    let id: Int
    let itemId: UUID?
    let brand: String
    let productName: String
    let colorName: String?
    let sizeName: String
    let imageUrl: String?
    let url: String?
    let startedAt: Date
    let endedAt: Date?
    let notified: Bool

    enum CodingKeys: String, CodingKey {
        case id, brand, url, notified
        case itemId = "item_id"
        case productName = "product_name"
        case colorName = "color_name"
        case sizeName = "size_name"
        case imageUrl = "image_url"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

// MARK: - resolve-link function response

struct ResolvedSize: Codable, Hashable {
    let id: String
    let name: String
    let availability: Availability
}

struct ResolvedColor: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let imageUrl: String?
    let price: Double?
    let sizes: [ResolvedSize]
}

struct ResolvedProduct: Codable, Hashable {
    let brand: String
    let externalId: String
    let name: String
    let url: String
    let currency: String?
    let colors: [ResolvedColor]
}

struct ResolvedWishlist: Codable, Hashable {
    struct Item: Codable, Hashable {
        let url: String
        let colorId: String?
    }
    let brand: String
    let name: String?
    let items: [Item]
}

struct ResolvedLink: Codable {
    let kind: String
    let product: ResolvedProduct?
    let wishlist: ResolvedWishlist?
}

extension String {
    var brandDisplayName: String {
        switch self {
        case "zara": "Zara"
        case "bershka": "Bershka"
        case "pullandbear": "Pull&Bear"
        case "stradivarius": "Stradivarius"
        case "massimodutti": "Massimo Dutti"
        default: capitalized
        }
    }
}

func formatPrice(_ price: Double?, _ currency: String?) -> String? {
    guard let price else { return nil }
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency ?? "TRY"
    f.locale = Locale(identifier: "tr_TR")
    return f.string(from: NSNumber(value: price))
}
