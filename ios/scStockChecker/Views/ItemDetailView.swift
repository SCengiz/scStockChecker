import SwiftUI

struct ItemDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let itemId: UUID

    private var item: TrackedItem? { store.items.first { $0.id == itemId } }

    var body: some View {
        if let item {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        ProductImage(url: item.imageUrl).frame(width: 90, height: 135)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name ?? "").font(.headline)
                            Text(item.brand.brandDisplayName).foregroundStyle(.secondary)
                            if let color = item.colorName { Text(color).font(.subheadline) }
                            if let price = formatPrice(item.price, item.currency) { Text(price).font(.subheadline.weight(.semibold)) }
                        }
                    }
                    if let url = item.productURL {
                        Button("Ürün sayfasını aç") { openURL(url) }
                    }
                }

                Section {
                    if item.sizes.isEmpty {
                        Text("İlk kontrol bekleniyor (birkaç dakika sürebilir).").foregroundStyle(.secondary)
                    }
                    ForEach(item.sizes, id: \.name) { size in
                        Button {
                            Task { await toggle(size.name, in: item) }
                        } label: {
                            HStack {
                                let selected = !item.wantedSizes.isEmpty && item.isWanted(size.name)
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.accentColor)
                                Text(size.name).foregroundStyle(.primary)
                                Spacer()
                                Text(size.availability.label)
                                    .foregroundStyle(size.availability.isAvailable ? .green : .secondary)
                            }
                        }
                    }
                } header: {
                    Text("Bedenler")
                } footer: {
                    Text(item.wantedSizes.isEmpty
                         ? "Hiç beden seçilmedi: herhangi bir beden gelince bildirim gelir."
                         : "Seçili bedenlerden biri stoğa girince bildirim gelir.")
                }

                Section {
                    Toggle("Takip et", isOn: Binding(
                        get: { item.active },
                        set: { value in Task { try? await store.setActive(item: item, value) } }
                    ))
                    if let checked = item.lastCheckedAt {
                        LabeledContent("Son kontrol", value: checked.formatted(.relative(presentation: .named)))
                    }
                    if let error = item.lastError {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                }

                if item.watchlistId == nil {
                    Section {
                        Button("Takipten çıkar", role: .destructive) {
                            Task {
                                try? await store.delete(item: item)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(item.name ?? "Ürün")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.reload() }
        } else {
            ContentUnavailableView("Ürün bulunamadı", systemImage: "questionmark")
        }
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
