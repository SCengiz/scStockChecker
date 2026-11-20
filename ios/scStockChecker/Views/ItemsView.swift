import SwiftUI

/// "Takip" tab: summary, single products as cards, favourites lists as compact groups.
/// Search filters by name, colour or frequency group.
struct ItemsView: View {
    @Environment(Store.self) private var store
    @State private var showAdd = false
    @State private var showHistory = false
    @State private var editingList: Watchlist?
    @State private var query = ""

    private func matches(_ item: TrackedItem) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [item.name, item.colorName, store.tier(of: item)?.name].contains { $0?.localizedCaseInsensitiveContains(q) == true }
    }

    private var visible: [TrackedItem] { store.items.filter(matches) }
    private var singles: [TrackedItem] { visible.filter { $0.watchlistId == nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let message = store.errorMessage {
                        Label(message, systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(Palette.soldOut)
                    }
                    if query.isEmpty { summary }
                    if store.items.isEmpty && store.watchlists.isEmpty {
                        emptyState
                    } else if visible.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    if !singles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle("Ürünler") { Text("\(singles.count)").font(.caption).foregroundStyle(.secondary) }
                            ForEach(singles) { item in
                                NavigationLink(value: item) { ItemCard(item: item) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if let url = item.productURL { Link("Mağazada aç", destination: url) }
                                        TierMenuItems(itemIds: [item.id])
                                        Button("Takipten çıkar", systemImage: "trash", role: .destructive) {
                                            Task { try? await store.delete(item: item) }
                                        }
                                    }
                            }
                        }
                    }
                    ForEach(store.watchlists) { list in
                        let items = visible.filter { $0.watchlistId == list.id }
                        if query.isEmpty || !items.isEmpty {
                            WatchlistGroup(list: list, items: items) {
                                editingList = list
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Palette.page)
            .navigationTitle("Takip")
            .searchable(text: $query, prompt: "Ürün, renk veya grup ara")
            .refreshable { await store.reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Link ekle")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: { BellIcon(count: store.unseenEventCount) }
                        .accessibilityLabel("Stok geçmişi")
                }
            }
            .sheet(isPresented: $showAdd) { AddLinkView() }
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(item: $editingList) { WatchlistSizesView(list: $0) }
            .navigationDestination(for: TrackedItem.self) { ItemDetailView(itemId: $0.id) }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            StatTile(value: "\(store.items.count)", label: "Takipte")
            StatTile(value: "\(store.items.filter { !$0.availableWanted.isEmpty }.count)", label: "Stokta", color: Palette.inStock)
            StatTile(value: "\(store.items.filter { $0.active && store.interval(of: $0) <= store.hotInterval }.count)",
                     label: "Öncelikli", color: Palette.priority)
        }
    }

    private var emptyState: some View {
        Card {
            VStack(spacing: 10) {
                Image(systemName: "bag.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                Text("Henüz ürün yok").font(.headline)
                Text("Sol üstteki + ile bir ürün ya da favori listesi linki ekleyin; Zara'da Paylaş menüsünden de ekleyebilirsiniz.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Link ekle") { showAdd = true }.buttonStyle(.borderedProminent).padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

/// Full card for a product added one by one.
struct ItemCard: View {
    let item: TrackedItem

    var body: some View {
        Card(padding: 12) {
            HStack(alignment: .top, spacing: 14) {
                ProductImage(url: item.imageUrl)
                    .frame(width: 78, height: 117)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.brand.brandDisplayName.uppercased())
                        .font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                    Text(item.name ?? "Yükleniyor…")
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text([item.colorName, formatPrice(item.price, item.currency)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    SizeChips(item: item)
                    HStack(spacing: 6) {
                        ItemBadges(item: item)
                        Spacer(minLength: 0)
                        CheckedAgo(date: item.lastCheckedAt, failed: item.lastError != nil)
                    }
                }
            }
        }
        .stockFrame(item.stockState)
    }
}

struct ItemBadges: View {
    @Environment(Store.self) private var store
    let item: TrackedItem

    var body: some View {
        if item.stockState != .unknown {
            Pill(text: item.stockState.label, color: item.stockState.color)
        }
        if let tier = store.tier(of: item), tier.key != "normal" {
            Pill(text: tier.name, systemImage: tier.icon, color: Palette.priority)
        } else if item.hotReason != nil && item.autoPriority {
            Pill(text: "Öncelikli", systemImage: "bolt.fill", color: Palette.priority)
        }
        if !item.active {
            Pill(text: "Duraklatıldı", systemImage: "pause.fill")
        }
    }
}

/// A favourites list: header plus one compact row per product, in a single card.
struct WatchlistGroup: View {
    @Environment(Store.self) private var store
    let list: Watchlist
    let items: [TrackedItem]
    let onEdit: () -> Void

    /// The list's frame shows its best item state, so a list with something in stock stands out.
    private var groupState: TrackedItem.StockState {
        let states = items.map(\.stockState)
        for state in [TrackedItem.StockState.wantedInStock, .wantedComingSoon, .otherSizesInStock, .soldOut]
        where states.contains(where: { $0 == state }) { return state }
        return .unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(list.name ?? "\(list.brand.brandDisplayName) listesi") {
                HStack(spacing: 10) {
                    Text("\(items.count) ürün").font(.caption).foregroundStyle(.secondary)
                    Menu {
                        Button("Bedenleri düzenle", systemImage: "ruler", action: onEdit)
                        TierMenuItems(itemIds: items.map(\.id))
                        if let url = URL(string: list.url) { Link("Listeyi Zara'da aç", destination: url) }
                        Button("Listeyi sil", systemImage: "trash", role: .destructive) {
                            Task { try? await store.delete(watchlist: list) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.subheadline)
                    }
                }
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    if items.isEmpty {
                        Text(list.lastError ?? "Liste okunuyor…")
                            .font(.caption)
                            .foregroundStyle(list.lastError == nil ? Color.secondary : Palette.warning)
                            .padding(14)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) { CompactItemRow(item: item) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let url = item.productURL { Link("Mağazada aç", destination: url) }
                                TierMenuItems(itemIds: [item.id])
                            }
                        if index < items.count - 1 { Divider().padding(.leading, 60) }
                    }
                }
            }
            .stockFrame(groupState)
        }
    }
}

/// Narrow row for products that come from a favourites list.
struct CompactItemRow: View {
    let item: TrackedItem

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(item.stockState.color).frame(width: 4, height: 54)
            ProductImage(url: item.imageUrl, cornerRadius: 6).frame(width: 36, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if item.hotReason != nil && item.autoPriority { Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(Palette.priority) }
                    Text(item.name ?? "Yükleniyor…")
                        .font(.footnote.weight(.medium)).lineLimit(1)
                }
                SizeChips(item: item, compact: true)
            }
            Spacer(minLength: 6)
            CheckedAgo(date: item.lastCheckedAt, failed: item.lastError != nil)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
