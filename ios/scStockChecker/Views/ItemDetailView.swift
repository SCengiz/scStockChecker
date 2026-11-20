import SwiftUI

struct ItemDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let itemId: UUID

    private var item: TrackedItem? { store.items.first { $0.id == itemId } }
    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(item)
                    sizes(item)
                    history(item)
                    settings(item)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Palette.page)
            .navigationTitle(item.brand.brandDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.reload() }
        } else {
            ContentUnavailableView("Ürün bulunamadı", systemImage: "questionmark")
        }
    }

    private func header(_ item: TrackedItem) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ProductImage(url: item.imageUrl).frame(width: 110, height: 165)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name ?? "")
                            .font(.title3.weight(.semibold))
                        if let color = item.colorName { Text(color).foregroundStyle(.secondary) }
                        if let price = formatPrice(item.price, item.currency) {
                            Text(price).font(.headline)
                        }
                        Spacer(minLength: 0)
                        ItemBadges(item: item)
                        CheckedAgo(date: item.lastCheckedAt, failed: item.lastError != nil)
                    }
                }
                if let url = item.productURL {
                    Button { openURL(url) } label: {
                        Label("\(item.brand.brandDisplayName)'da aç", systemImage: "bag.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(item.stockState == .wantedInStock ? Palette.inStock : .accentColor)
                }
            }
        }
        .stockFrame(item.stockState)
    }

    private func sizes(_ item: TrackedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Takip edilen bedenler") {
                if !item.wantedSizes.isEmpty {
                    Button("Temizle") { Task { try? await store.updateWantedSizes(item: item, sizes: []) } }
                        .font(.caption)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    if item.sizes.isEmpty {
                        Text("İlk kontrol bekleniyor…").font(.footnote).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(item.sizes, id: \.name) { size in
                            SizeToggle(size: size, selected: !item.wantedSizes.isEmpty && item.isWanted(size.name)) {
                                Task { await toggle(size.name, in: item) }
                            }
                        }
                    }
                    Text(item.wantedSizes.isEmpty
                         ? "Beden seçilmedi: herhangi bir beden stoğa girince bildirim gelir."
                         : "Seçili bedenlerden biri stoğa girince veya \"yakında\" olunca bildirim gelir.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func history(_ item: TrackedItem) -> some View {
        let restocks = store.restocks(of: item)
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Stok geçmişi")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    if let reason = item.hotReasonText {
                        Label("Öncelikli kontrol (\(intervalText(store.hotInterval))): \(reason)", systemImage: "bolt.fill")
                            .font(.footnote.weight(.medium)).foregroundStyle(Palette.priority)
                    }
                    if restocks.isEmpty {
                        Text("Bu ürün takibe alındığından beri seçili bedenlerde stoğa girmedi.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        if let pattern = hourPattern(restocks) {
                            Label(pattern, systemImage: "clock").font(.footnote.weight(.medium))
                        }
                        ForEach(restocks.prefix(8)) { event in
                            HStack {
                                Text("Beden \(TrackedItem.shortSize(event.sizeName))").font(.footnote.weight(.medium))
                                Spacer()
                                Text(event.startedAt.formatted(.dateTime.day().month().hour().minute()))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                if let end = event.endedAt {
                                    Text("· \(minutes(event.startedAt, end))").font(.caption).foregroundStyle(Palette.soldOut)
                                } else {
                                    Text("· stokta").font(.caption).foregroundStyle(Palette.inStock)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func settings(_ item: TrackedItem) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Takip et", isOn: Binding(
                    get: { item.active },
                    set: { value in Task { try? await store.setActive(item: item, value) } }
                ))
                if let error = item.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Palette.warning)
                }
                if item.watchlistId == nil {
                    Divider()
                    Button("Takipten çıkar", role: .destructive) {
                        Task {
                            try? await store.delete(item: item)
                            dismiss()
                        }
                    }
                } else {
                    Text("Bu ürün bir favori listesinden geliyor; listeden çıkarınca takipten de çıkar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Genelde 09:00–10:00 arası geliyor" when restocks cluster in one hour.
    private func hourPattern(_ events: [StockEvent]) -> String? {
        guard events.count >= 2 else { return nil }
        let hours = events.map { Calendar.current.component(.hour, from: $0.startedAt) }
        let counts = Dictionary(grouping: hours, by: { $0 }).mapValues(\.count)
        guard let (hour, count) = counts.max(by: { $0.value < $1.value }), count >= 2 else { return nil }
        return String(format: "%d kez stoğa girdi, genelde %02d:00–%02d:00 arası", events.count, hour, (hour + 1) % 24)
    }

    private func minutes(_ start: Date, _ end: Date) -> String {
        let m = Int(end.timeIntervalSince(start) / 60)
        return m < 1 ? "<1 dk kaldı" : m < 60 ? "\(m) dk kaldı" : "\(m / 60) sa kaldı"
    }

    private func toggle(_ size: String, in item: TrackedItem) async {
        // Match the way sizes are compared ("M" selects "M (US M)"), and keep the product's size order.
        let key = TrackedItem.sizeKey(size)
        var sizes = item.wantedSizes
        if sizes.contains(where: { TrackedItem.sizeKey($0) == key }) {
            sizes.removeAll { TrackedItem.sizeKey($0) == key }
        } else {
            sizes.append(size)
        }
        let order = item.sizes.map(\.name)
        sizes.sort { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        try? await store.updateWantedSizes(item: item, sizes: sizes)
    }
}

/// A size tile: name, availability, and whether it is tracked.
struct SizeToggle: View {
    let size: StoredSize
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(TrackedItem.shortSize(size.name)).font(.subheadline.weight(.semibold)).lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(size.availability.label).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(availabilityColor(size.availability))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.caption).padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
