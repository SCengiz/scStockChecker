import SwiftUI

/// "Profil" tab: account, notifications (ntfy) and check intervals.
struct ProfileView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var topic = ""
    @State private var message: String?
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    static let intervals = [10, 15, 20, 30, 45, 60, 120, 300, 600]
    static let hotIntervals = [10, 15, 20, 30, 60]

    private var name: String { store.profile?.displayName ?? "Kullanıcı" }
    private var savedTopic: String? { store.profile?.ntfyTopic.flatMap { $0.isEmpty ? nil : $0 } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.title2.weight(.semibold)).foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Color.accentColor.gradient, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name.capitalized).font(.headline)
                            Text("\(store.items.count) ürün · \(store.watchlists.count) liste takipte")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                notifications

                Section("Görünüm") {
                    Picker(selection: $theme) {
                        ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label("Tema", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Picker(selection: Binding(
                        get: { store.checkInterval },
                        set: { value in Task { try? await store.setCheckInterval(value) } }
                    )) {
                        ForEach(Self.intervals, id: \.self) { Text(intervalText($0)).tag($0) }
                    } label: {
                        Label("Normal sıklık", systemImage: "clock")
                    }
                    Picker(selection: Binding(
                        get: { store.hotInterval },
                        set: { value in Task { try? await store.setHotInterval(value) } }
                    )) {
                        ForEach(Self.hotIntervals, id: \.self) { Text(intervalText($0)).tag($0) }
                    } label: {
                        Label("Öncelikli sıklık", systemImage: "bolt")
                    }
                } header: {
                    Text("Kontrol")
                } footer: {
                    Text("Öncelikli ürünler: istenen bedeni \"yakında\" olanlar, son 1 saatte tükenenler ve daha önce stoğa girdiği saat dilimindekiler. Kontrol sunucuda yapılır; telefon kapalıyken de devam eder. Çok sık kontrol, markanın bot korumasına takılma riskini artırır.")
                }

                Section {
                    LabeledContent("Sürüm", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                    Button("Çıkış yap", role: .destructive) { Task { await store.signOut() } }
                }
            }
            .navigationTitle("Profil")
            .onAppear { topic = savedTopic ?? "" }
            .onChange(of: store.profile?.ntfyTopic) { _, new in topic = new ?? "" }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {}
        }
    }

    private var notifications: some View {
        Section {
            HStack {
                Label("Durum", systemImage: "bell.badge")
                Spacer()
                Pill(text: savedTopic == nil ? "Kurulmadı" : "Bağlı",
                     systemImage: savedTopic == nil ? "xmark" : "checkmark",
                     color: savedTopic == nil ? Palette.warning : Palette.inStock)
            }
            HStack {
                TextField("Kanal adı", text: $topic)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout.monospaced())
                Button("Yeni") { topic = Self.randomTopic() }.buttonStyle(.bordered).controlSize(.small)
            }
            if topic != (savedTopic ?? "") && !topic.isEmpty {
                Button("Kanalı kaydet") {
                    Task {
                        try? await store.saveNtfyTopic(topic.trimmingCharacters(in: .whitespaces))
                        message = "Kaydedildi. Şimdi ntfy'da abone olun."
                    }
                }
            }
            if let current = savedTopic {
                Button {
                    if let url = URL(string: "ntfy://ntfy.sh/\(current)") { openURL(url) }
                } label: { Label("ntfy uygulamasında abone ol", systemImage: "arrow.up.forward.app") }
                Button {
                    Task { await sendTest(topic: current) }
                } label: { Label("Test bildirimi gönder", systemImage: "paperplane") }
            }
        } header: {
            Text("Bildirimler")
        } footer: {
            Text("App Store'dan ücretsiz \"ntfy\" uygulamasını kurun, \"Yeni\" ile kanal oluşturup kaydedin, sonra abone olun. Kanal adını bilen herkes bildirimleri görebilir; paylaşmayın.")
        }
    }

    private func sendTest(topic: String) async {
        var request = URLRequest(url: URL(string: "https://ntfy.sh")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let example = store.items.first
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "topic": topic,
            "title": "🟢 Test: \(example?.name ?? "Stok Takip")",
            "message": "Bildirimler çalışıyor. Dokununca ürün açılır.",
            "click": example?.productURL?.absoluteString ?? "https://www.zara.com/tr/",
            "priority": 5,
            "tags": ["shopping_bags"],
        ])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            message = (response as? HTTPURLResponse)?.statusCode == 200 ? "Test bildirimi gönderildi." : "Gönderilemedi."
        } catch {
            message = "Gönderilemedi: \(error.localizedDescription)"
        }
    }

    static func randomTopic() -> String {
        let chars = Array("abcdefghijkmnopqrstuvwxyz23456789")
        return "stok-" + String((0..<16).map { _ in chars.randomElement()! })
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appTheme"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Sistem"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
