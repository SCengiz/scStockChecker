import SwiftUI

struct ItemsView: View {
    @Environment(Store.self) private var store
    @State private var showAdd = false

    private var singles: [TrackedItem] { store.items.filter { $0.watchlistId == nil } }
    private var fromLists: [TrackedItem] { store.items.filter { $0.watchlistId != nil } }

    var body: some View {
        NavigationStack {
            List {
                if let message = store.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                if store.items.isEmpty {
                    ContentUnavailableView(
                        "Henüz ürün yok",
                        systemImage: "bag.badge.plus",
                        description: Text("Sağ üstteki + ile bir ürün ya da favori listesi linki ekleyin.")
                    )
                }
                if !singles.isEmpty {
                    Section("Ürünler") { rows(singles) }
                }
                if !fromLists.isEmpty {
                    Section("Listelerden") { rows(fromLists) }
                }
            }
            .navigationTitle("Takip")
            .refreshable { await store.reload() }
            .toolbar {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showAdd) { AddLinkView() }
            .navigationDestination(for: TrackedItem.self) { ItemDetailView(itemId: $0.id) }
        }
    }

    @ViewBuilder
    private func rows(_ items: [TrackedItem]) -> some View {
        ForEach(items) { item in
            NavigationLink(value: item) { ItemRow(item: item) }
                .swipeActions {
                    if item.watchlistId == nil {
                        Button("Sil", role: .destructive) {
                            Task { try? await store.delete(item: item) }
                        }
                    }
                }
        }
    }
}

struct ItemRow: View {
    let item: TrackedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductImage(url: item.imageUrl)
                .frame(width: 56, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name ?? "Yükleniyor…").font(.subheadline.weight(.semibold)).lineLimit(2)
                Text([item.brand.brandDisplayName, item.colorName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                SizeChips(item: item)
                if item.lastError != nil {
                    Label("Kontrol edilemedi", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                } else if !item.active {
                    Text("Duraklatıldı").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct SizeChips: View {
    let item: TrackedItem

    var body: some View {
        let shown = item.wantedSizes.isEmpty
            ? item.sizes
            : item.sizes.filter { item.isWanted($0.name) }
        if shown.isEmpty {
            Text(item.lastCheckedAt == nil ? "İlk kontrol bekleniyor" : "Beden bilgisi yok")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 4) {
                ForEach(shown, id: \.name) { size in
                    Text(size.name)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(size.availability.isAvailable ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
                        .foregroundStyle(size.availability.isAvailable ? Color.green : Color.secondary)
                        .clipShape(Capsule())
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
