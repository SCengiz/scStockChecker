import SwiftUI

struct AddLinkView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Link handed over by the share extension; resolved right away.
    var initialLink: String?
    /// Called instead of dismiss() when hosted outside a sheet (share extension).
    var onFinish: (() -> Void)?

    @State private var link = ""
    @State private var resolved: ResolvedLink?
    @State private var selectedColorId: String?
    @State private var wanted: Set<String> = []
    @State private var listSizesText = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://www.zara.com/…", text: $link, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first { link = first; Task { await resolve() } }
                        }
                        .labelStyle(.titleAndIcon)
                        Spacer()
                        Button("Getir") { Task { await resolve() } }
                            .disabled(link.isEmpty || isLoading)
                    }
                } header: {
                    Text("Ürün veya favori listesi linki")
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }

                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }

                if let product = resolved?.product {
                    productSections(product)
                } else if let wishlist = resolved?.wishlist {
                    wishlistSections(wishlist)
                }
            }
            .navigationTitle("Link ekle")
            .task {
                if let initialLink, link.isEmpty {
                    link = initialLink
                    await resolve()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { close() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { Task { await save() } }.disabled(resolved == nil || isLoading)
                }
            }
        }
    }

    @ViewBuilder
    private func productSections(_ product: ResolvedProduct) -> some View {
        let color = product.colors.first { $0.id == selectedColorId } ?? product.colors.first
        Section {
            HStack(alignment: .top, spacing: 12) {
                ProductImage(url: color?.imageUrl).frame(width: 70, height: 105)
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name).font(.headline)
                    Text(product.brand.brandDisplayName).foregroundStyle(.secondary)
                    if let price = formatPrice(color?.price, product.currency) { Text(price) }
                }
            }
            if product.colors.count > 1 {
                Picker("Renk", selection: Binding(
                    get: { color?.id ?? "" },
                    set: { selectedColorId = $0; wanted = [] }
                )) {
                    ForEach(product.colors) { Text($0.name).tag($0.id) }
                }
            }
        }
        if let color {
            Section {
                ForEach(color.sizes, id: \.id) { size in
                    Button {
                        if wanted.contains(size.name) { wanted.remove(size.name) } else { wanted.insert(size.name) }
                    } label: {
                        HStack {
                            Image(systemName: wanted.contains(size.name) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color.accentColor)
                            Text(size.name).foregroundStyle(.primary)
                            Spacer()
                            Text(size.availability.label)
                                .foregroundStyle(size.availability.isAvailable ? .green : .secondary)
                        }
                    }
                }
            } header: {
                Text("Hangi bedenler?")
            } footer: {
                Text("Seçmezseniz herhangi bir beden gelince bildirim gelir.")
            }
        }
    }

    @ViewBuilder
    private func wishlistSections(_ wishlist: ResolvedWishlist) -> some View {
        Section {
            LabeledContent("Liste", value: wishlist.name ?? wishlist.brand.brandDisplayName)
            LabeledContent("Ürün sayısı", value: "\(wishlist.items.count)")
        }
        Section {
            TextField("Örn. M, L, 38", text: $listSizesText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("Takip edilecek bedenler")
        } footer: {
            Text("Virgülle ayırın. Listedeki her ürün için bu bedenler takip edilir. Boş bırakırsanız herhangi bir beden.")
        }
    }

    private func close() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    /// The first web link in a pasted or shared text ("ÜRÜN ADI https://…" → "https://…").
    static func extractURL(_ text: String) -> String {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url?.absoluteString
            ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolve() async {
        link = Self.extractURL(link)
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        error = nil
        resolved = nil
        defer { isLoading = false }
        do {
            let result = try await store.resolve(trimmed)
            resolved = result
            selectedColorId = result.product?.colors.first?.id
            wanted = []
        } catch {
            self.error = "Link okunamadı: \(error.localizedDescription)"
        }
    }

    private func save() async {
        guard let resolved else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let product = resolved.product,
               let color = product.colors.first(where: { $0.id == selectedColorId }) ?? product.colors.first {
                let order = color.sizes.map(\.name)
                try await store.addItem(product: product, color: color,
                                        wantedSizes: order.filter { wanted.contains($0) })
            } else if let wishlist = resolved.wishlist {
                let sizes = listSizesText.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                try await store.addWatchlist(url: link.trimmingCharacters(in: .whitespacesAndNewlines),
                                             brand: wishlist.brand, name: wishlist.name, wantedSizes: sizes)
            }
            close()
        } catch {
            self.error = "Kaydedilemedi: \(error.localizedDescription)"
        }
    }
}
