import SwiftUI

struct ItemsView: View {
    @Environment(Store.self) private var store
    @State private var showAdd = false
    @State private var showHistory = false
    @State private var editingList: Watchlist?

    private var singles: [TrackedItem] { store.items.filter { $0.watchlistId == nil } }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink { CheckLogView() } label: { CheckStatusBar() }
                if let message = store.errorMessage {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.red)
                }
                if store.items.isEmpty && store.watchlists.isEmpty {
                    ContentUnavailableView(
                        "Henüz ürün yok",
                        systemImage: "bag.badge.plus",
                        description: Text("Sol üstteki + ile bir ürün ya da favori listesi linki ekleyin.")
                    )
                    .listRowBackground(Color.clear)
                }
                if !singles.isEmpty {
                    Section("Ürünler") {
                        ForEach(singles) { item in
                            NavigationLink(value: item) { ItemRow(item: item) }
                                .swipeActions {
                                    Button("Sil", role: .destructive) { Task { try? await store.delete(item: item) } }
                                }
                        }
                    }
                }
                ForEach(store.watchlists) { list in
                    let items = store.items.filter { $0.watchlistId == list.id }
                    Section {
                        if items.isEmpty {
                            Text(list.lastError ?? "Liste okunuyor…")
                                .font(.caption).foregroundStyle(list.lastError == nil ? Color.secondary : Color.orange)
                        }
                        ForEach(items) { item in
                            NavigationLink(value: item) { CompactItemRow(item: item) }
                        }
                    } header: {
                        WatchlistHeader(list: list, count: items.count) { editingList = list }
                    }
                }
            }
            .navigationTitle("Stok Takip")
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
}

struct BellIcon: View {
    let count: Int

    var body: some View {
        Image(systemName: count > 0 ? "bell.badge" : "bell")
            .symbolRenderingMode(count > 0 ? .multicolor : .monochrome)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .offset(x: 10, y: -8)
                }
            }
    }
}

struct WatchlistHeader: View {
    @Environment(Store.self) private var store
    let list: Watchlist
    let count: Int
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "heart.fill").foregroundStyle(.pink)
            Text(list.name ?? "\(list.brand.brandDisplayName) listesi")
            Text("\(count)").foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Bedenleri düzenle", systemImage: "ruler", action: onEdit)
                Button("Listeyi sil", systemImage: "trash", role: .destructive) {
                    Task { try? await store.delete(watchlist: list) }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.body)
            }
        }
    }
}

/// Full-size row for products added one by one.
struct ItemRow: View {
    let item: TrackedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductImage(url: item.imageUrl)
                .frame(width: 60, height: 90)
                .overlay(alignment: .topLeading) { StockDot(item: item).padding(4) }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name ?? "Yükleniyor…").font(.subheadline.weight(.semibold)).lineLimit(2)
                Text([item.brand.brandDisplayName, item.colorName, formatPrice(item.price, item.currency)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                SizeChips(item: item)
                ItemStatus(item: item)
            }
            Spacer(minLength: 4)
            CheckedAgo(date: item.lastCheckedAt, failed: item.lastError != nil)
        }
        .padding(.vertical, 2)
    }
}

/// Narrow row for products that come from a favourites list.
struct CompactItemRow: View {
    let item: TrackedItem

    var body: some View {
        HStack(spacing: 10) {
            ProductImage(url: item.imageUrl).frame(width: 32, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    StockDot(item: item)
                    Text(item.name ?? "Yükleniyor…").font(.footnote.weight(.medium)).lineLimit(1)
                }
                SizeChips(item: item, compact: true)
            }
            Spacer(minLength: 4)
            CheckedAgo(date: item.lastCheckedAt, failed: item.lastError != nil)
        }
    }
}

/// Small live "12 sn" label showing when the server last checked an item.
struct CheckedAgo: View {
    let date: Date?
    var failed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(date.map { agoText($0, now: context.date).replacingOccurrences(of: " önce", with: "") } ?? "—")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(failed ? Color.orange : Color.secondary)
        }
    }
}

/// Green when a wanted size is in stock right now.
struct StockDot: View {
    let item: TrackedItem

    var body: some View {
        if !item.availableWanted.isEmpty {
            Circle().fill(.green).frame(width: 8, height: 8)
                .overlay(Circle().stroke(.background, lineWidth: 1.5))
        }
    }
}

struct ItemStatus: View {
    let item: TrackedItem

    var body: some View {
        if item.lastError != nil {
            Label("Kontrol edilemedi", systemImage: "exclamationmark.triangle")
                .font(.caption2).foregroundStyle(.orange)
        } else if !item.active {
            Label("Duraklatıldı", systemImage: "pause.circle").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct SizeChips: View {
    let item: TrackedItem
    var compact = false

    var body: some View {
        let shown = item.wantedSizes.isEmpty ? item.sizes : item.sizes.filter { item.isWanted($0.name) }
        if shown.isEmpty {
            Text(item.lastCheckedAt == nil ? "İlk kontrol bekleniyor" : "Beden bilgisi yok")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 3) {
                ForEach(shown, id: \.name) { size in
                    let available = size.availability.isAvailable
                    Text(TrackedItem.shortSize(size.name))
                        .font(.system(size: compact ? 10 : 11, weight: .medium))
                        .strikethrough(!available && size.availability != .comingSoon)
                        .padding(.horizontal, compact ? 4 : 6).padding(.vertical, compact ? 1 : 2)
                        .background(available ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(available ? Color.green : size.availability == .comingSoon ? Color.orange : Color.secondary)
                }
            }
        }
    }
}

struct ProductImage: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.secondary.opacity(0.1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Simple wrapping layout for size chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, point) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}
