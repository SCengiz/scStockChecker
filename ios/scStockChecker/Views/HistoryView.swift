import SwiftUI

/// Bell screen: everything that happened to tracked items, including stock you missed.
struct HistoryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var seenAt = Date.distantPast
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tümü", inStock = "Stok", comingSoon = "Yakında", priceDrop = "Fiyat"
        var id: String { rawValue }

        func matches(_ kind: StockEvent.Kind) -> Bool {
            switch self {
            case .all: true
            case .inStock: kind == .inStock
            case .comingSoon: kind == .comingSoon
            case .priceDrop: kind == .priceDrop
            }
        }
    }

    private var groups: [(day: Date, events: [StockEvent])] {
        Dictionary(grouping: store.events.filter { filter.matches($0.kind) }) { Calendar.current.startOfDay(for: $0.startedAt) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filtre", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if groups.isEmpty {
                    ContentUnavailableView(
                        "Henüz hareket yok",
                        systemImage: "bell.slash",
                        description: Text("Takip ettiğiniz bir beden stoğa girdiğinde, \"yakında\" olduğunda ya da fiyat düştüğünde burada görünür; kaçırdıklarınız da burada kalır.")
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(groups, id: \.day) { group in
                    Section(group.day.formatted(.dateTime.day().month(.wide).weekday(.wide))) {
                        ForEach(group.events) { event in
                            Button {
                                if let url = event.url.flatMap(URL.init(string:)) { openURL(url) }
                            } label: {
                                EventRow(event: event, isNew: event.startedAt > seenAt, inStockNow: isInStockNow(event))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bildirimler")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.reload() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
            }
            .onAppear {
                seenAt = store.eventsSeenAt
                store.eventsSeenAt = .now
            }
        }
    }

    /// An open event can be stale for up to one check; confirm with the item's latest sizes.
    private func isInStockNow(_ event: StockEvent) -> Bool {
        guard event.kind == .inStock, event.endedAt == nil else { return false }
        guard let item = store.item(id: event.itemId) else { return true }
        return item.sizes.first { $0.name == event.sizeName }?.availability.isAvailable ?? false
    }
}

private struct EventRow: View {
    let event: StockEvent
    let isNew: Bool
    let inStockNow: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductImage(url: event.imageUrl, cornerRadius: 8).frame(width: 44, height: 66)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isNew { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                }
                Text(event.productName)
                    .font(.footnote).foregroundStyle(.primary).lineLimit(1)
                Text([event.brand.brandDisplayName, event.colorName, event.startedAt.formatted(date: .omitted, time: .shortened)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                status
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var size: String { TrackedItem.shortSize(event.sizeName) }

    private var title: String {
        switch event.kind {
        case .inStock: "\(size) stoğa girdi"
        case .comingSoon: "\(size) yakında geliyor"
        case .priceDrop: "Fiyat düştü"
        }
    }

    private var color: Color {
        switch event.kind {
        case .inStock: Palette.inStock
        case .comingSoon: Palette.soon
        case .priceDrop: Palette.priority
        }
    }

    @ViewBuilder
    private var status: some View {
        switch event.kind {
        case .inStock:
            if inStockNow {
                Label("Hâlâ stokta", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.inStock)
            } else if let ended = event.endedAt {
                Label("Tükendi · \(duration(from: event.startedAt, to: ended)) stokta kaldı", systemImage: "xmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.soldOut)
            } else {
                Label("Şu an stokta değil", systemImage: "xmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.soldOut)
            }
        case .comingSoon:
            Text("Öncelikli kontrole alındı").font(.caption).foregroundStyle(.secondary)
        case .priceDrop:
            if let old = formatPrice(event.oldPrice, "TRY"), let new = formatPrice(event.price, "TRY") {
                Text("\(old) → \(new)").font(.caption.weight(.medium))
            }
        }
    }

    private func duration(from start: Date, to end: Date) -> String {
        let m = Int(end.timeIntervalSince(start) / 60)
        return m < 1 ? "1 dk'dan az" : m < 60 ? "\(m) dk" : "\(m / 60) sa \(m % 60) dk"
    }
}
