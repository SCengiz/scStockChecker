import SwiftUI

/// Every time a wanted size came into stock, and whether it is still there.
struct HistoryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var seenAt = Date.distantPast

    private var groups: [(day: Date, events: [StockEvent])] {
        Dictionary(grouping: store.events) { Calendar.current.startOfDay(for: $0.startedAt) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.events.isEmpty {
                    ContentUnavailableView(
                        "Henüz stok hareketi yok",
                        systemImage: "bell.slash",
                        description: Text("Takip ettiğiniz bir beden stoğa girdiğinde burada görünür; kaçırdıklarınız da burada kalır.")
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
            .navigationTitle("Stok geçmişi")
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
        guard event.endedAt == nil else { return false }
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
            ProductImage(url: event.imageUrl).frame(width: 44, height: 66)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isNew { Circle().fill(.blue).frame(width: 7, height: 7) }
                    Text(event.productName).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .foregroundStyle(.primary)
                }
                Text([event.brand.brandDisplayName, event.colorName, "Beden \(TrackedItem.shortSize(event.sizeName))"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(event.startedAt.formatted(date: .omitted, time: .shortened)) stoğa girdi")
                    .font(.caption).foregroundStyle(.primary)
                status
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var status: some View {
        if inStockNow {
            Label("Hâlâ stokta", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.green)
        } else if let ended = event.endedAt {
            Label("Tükendi · \(duration(from: event.startedAt, to: ended)) stokta kaldı", systemImage: "xmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.red)
        } else {
            Label("Şu an stokta değil", systemImage: "xmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.red)
        }
    }

    private func duration(from start: Date, to end: Date) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .short
        f.maximumUnitCount = 2
        f.calendar?.locale = Locale(identifier: "tr_TR")
        return end.timeIntervalSince(start) < 60 ? "1 dk'dan az" : (f.string(from: start, to: end) ?? "")
    }
}
