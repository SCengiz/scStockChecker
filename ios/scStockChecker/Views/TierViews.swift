import SwiftUI

/// How hard the current settings hit the brand, against the server's request budget.
struct LoadGauge: View {
    @Environment(Store.self) private var store
    /// Preview of a group's new interval while editing it.
    var override: (tierId: UUID, seconds: Int)?

    var body: some View {
        let load = store.estimatedLoad(override: override)
        let ratio = load / Store.requestBudget
        let level = LoadLevel(ratio: ratio)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Tahmini yük", systemImage: "gauge.with.dots.needle.33percent")
                Spacer()
                Text("\(Int(load.rounded())) / \(Int(Store.requestBudget)) istek/dk")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(level.color)
            }
            ProgressView(value: min(ratio, 1))
                .tint(level.color)
            Text(level.message)
                .font(.caption).foregroundStyle(level == .safe ? Color.secondary : level.color)
            if let until = store.settings?.backoffUntil, until > .now {
                Label("Zara engelleme sinyali verdi; kontroller \(until.formatted(date: .omitted, time: .shortened))'e kadar durduruldu.",
                      systemImage: "hand.raised.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.soldOut)
            } else if let stretch = store.settings?.loadStretch, stretch > 1.05, override == nil {
                Label(String(format: "Sunucu normal ürünlerin aralığını %.1f kat uzatıyor.", stretch), systemImage: "tortoise.fill")
                    .font(.caption).foregroundStyle(Palette.warning)
            }
        }
        .padding(.vertical, 4)
    }
}

enum LoadLevel {
    case safe, busy, over

    init(ratio: Double) {
        self = ratio <= 0.6 ? .safe : ratio <= 1 ? .busy : .over
    }

    var color: Color {
        switch self {
        case .safe: Palette.inStock
        case .busy: Palette.warning
        case .over: Palette.soldOut
        }
    }

    var message: String {
        switch self {
        case .safe:
            "Güvenli. Bu yükte Zara'nın sizi engellemesi beklenmez."
        case .busy:
            "Yoğun. Sınıra yaklaşıyorsunuz; daha fazla ürünü kısa aralığa almayın."
        case .over:
            "Sınır aşılıyor. Sunucu engellenmemek için aralıkları kendiliğinden uzatacak; öncelikli ürünleri azaltın veya süreleri artırın."
        }
    }
}

struct TierRow: View {
    let tier: CheckTier
    let count: Int

    var body: some View {
        HStack {
            Label(tier.name, systemImage: tier.icon)
            Spacer()
            Text("\(intervalText(tier.intervalSeconds)) · \(count) ürün")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

/// Create or edit a frequency group: name and interval, with a live load preview.
struct TierEditView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tier: CheckTier?

    @State private var name = ""
    @State private var seconds = 60
    @State private var error: String?

    private static let presets = [10, 15, 20, 30, 45, 60, 90, 120, 300, 600, 1800, 3600]

    var body: some View {
        Form {
            Section("Ad") {
                TextField("Örn. Çok istediklerim", text: $name)
            }
            Section {
                Stepper(value: $seconds, in: 10...86400, step: seconds < 60 ? 5 : seconds < 600 ? 30 : 300) {
                    HStack {
                        Text("Aralık")
                        Spacer()
                        Text(intervalText(seconds)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.presets, id: \.self) { value in
                            Button(intervalText(value)) { seconds = value }
                                .buttonStyle(.bordered)
                                .tint(value == seconds ? .accentColor : .secondary)
                                .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Kontrol aralığı")
            } footer: {
                Text(seconds < 20
                     ? "En kısa aralık 10 sn. Kısa aralıklar sadece gerçekten kaçırmak istemediğiniz birkaç ürün için kullanılmalı."
                     : "Bu gruptaki her ürün bu aralıkla kontrol edilir.")
            }
            if let tier {
                Section { LoadGauge(override: (tier.id, seconds)) }
            }
            if let error {
                Text(error).foregroundStyle(Palette.soldOut)
            }
            if let tier, !tier.isBuiltIn {
                Section {
                    Button("Grubu sil", role: .destructive) {
                        Task {
                            try? await store.deleteTier(tier)
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle(tier == nil ? "Yeni grup" : tier!.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = tier?.name ?? ""
            seconds = tier?.intervalSeconds ?? 60
        }
        .toolbar {
            Button("Kaydet") {
                Task {
                    do {
                        try await store.saveTier(id: tier?.id, name: name, seconds: seconds)
                        dismiss()
                    } catch {
                        self.error = "Kaydedilemedi: \(error.localizedDescription)"
                    }
                }
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

/// Menu for moving items to a group and toggling automatic priority.
struct TierMenuItems: View {
    @Environment(Store.self) private var store
    let itemIds: [UUID]

    var body: some View {
        Section("Sıklık grubu") {
            ForEach(store.tiers) { tier in
                Button("\(tier.name) (\(intervalText(tier.intervalSeconds)))", systemImage: tier.icon) {
                    Task { try? await store.setTier(tier.id, for: itemIds) }
                }
            }
        }
        Section("Otomatik öncelik") {
            Button("Aç", systemImage: "bolt.badge.automatic") { Task { try? await store.setAutoPriority(true, for: itemIds) } }
            Button("Kapat", systemImage: "bolt.slash") { Task { try? await store.setAutoPriority(false, for: itemIds) } }
        }
    }
}
