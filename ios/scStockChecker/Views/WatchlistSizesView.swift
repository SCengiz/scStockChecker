import SwiftUI

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
