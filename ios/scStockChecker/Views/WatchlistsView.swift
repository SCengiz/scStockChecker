import SwiftUI

struct WatchlistsView: View {
    @Environment(Store.self) private var store
    @State private var showAdd = false
    @State private var editing: Watchlist?

    var body: some View {
        NavigationStack {
            List {
                if store.watchlists.isEmpty {
                    ContentUnavailableView(
                        "Liste yok",
                        systemImage: "heart.text.square",
                        description: Text("Zara'daki bir favori listesinin paylaşım linkini + ile ekleyin; içindeki tüm ürünler takip edilir.")
                    )
                }
                ForEach(store.watchlists) { list in
                    Button { editing = list } label: { row(list) }
                        .swipeActions {
                            Button("Sil", role: .destructive) {
                                Task { try? await store.delete(watchlist: list) }
                            }
                        }
                }
            }
            .navigationTitle("Listeler")
            .refreshable { await store.reload() }
            .toolbar {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showAdd) { AddLinkView() }
            .sheet(item: $editing) { WatchlistSizesView(list: $0) }
        }
    }

    private func row(_ list: Watchlist) -> some View {
        let count = store.items.filter { $0.watchlistId == list.id }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(list.name ?? "\(list.brand.brandDisplayName) listesi").font(.headline).foregroundStyle(.primary)
            Text("\(count) ürün · Bedenler: \(list.wantedSizes.isEmpty ? "hepsi" : list.wantedSizes.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            if let error = list.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            } else if list.lastSyncedAt == nil {
                Text("İlk senkronizasyon bekleniyor").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct WatchlistSizesView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let list: Watchlist
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Örn. M, L, 38", text: $text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Takip edilecek bedenler")
                } footer: {
                    Text("Virgülle ayırın. Boş bırakırsanız herhangi bir beden.")
                }
                Section {
                    Text(list.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .navigationTitle(list.name ?? "Liste")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { text = list.wantedSizes.joined(separator: ", ") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        let sizes = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        Task {
                            try? await store.updateWatchlistSizes(list, sizes: sizes)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
