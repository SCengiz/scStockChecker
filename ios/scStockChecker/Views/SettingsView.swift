import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var topic = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Kullanıcı", value: store.profile?.displayName ?? "-")
                }

                Section {
                    HStack {
                        TextField("Kanal adı", text: $topic)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                        Button("Yeni") { topic = Self.randomTopic() }
                    }
                    Button("Kaydet") {
                        Task {
                            try? await store.saveNtfyTopic(topic.trimmingCharacters(in: .whitespaces))
                            saved = true
                        }
                    }
                    .disabled(topic.isEmpty || topic == store.profile?.ntfyTopic)
                    if let current = store.profile?.ntfyTopic, !current.isEmpty,
                       let url = URL(string: "ntfy://ntfy.sh/\(current)") {
                        Button("ntfy uygulamasında abone ol") { openURL(url) }
                    }
                } header: {
                    Text("Bildirimler (ntfy)")
                } footer: {
                    Text("App Store'dan ücretsiz \"ntfy\" uygulamasını kurun, \"Yeni\" ile tahmin edilemez bir kanal adı oluşturup kaydedin, sonra \"ntfy uygulamasında abone ol\"a dokunun. Kanal adını bilen herkes bildirimleri görebilir; paylaşmayın.")
                }

                Section {
                    LabeledContent("Takip edilen", value: "\(store.items.count) ürün")
                    Picker("Kontrol sıklığı", selection: Binding(
                        get: { store.checkInterval },
                        set: { value in Task { try? await store.setCheckInterval(value) } }
                    )) {
                        ForEach(Self.intervals, id: \.self) { Text(intervalText($0)).tag($0) }
                    }
                } footer: {
                    Text("Kontrol sunucuda yapılır; telefon kapalıyken de devam eder. Çok sık kontrol, markanın bot korumasına takılma riskini artırır.")
                }

                Section {
                    Button("Çıkış yap", role: .destructive) { Task { await store.signOut() } }
                }
            }
            .navigationTitle("Ayarlar")
            .onAppear { topic = store.profile?.ntfyTopic ?? "" }
            .onChange(of: store.profile?.ntfyTopic) { _, new in topic = new ?? "" }
            .alert("Kaydedildi", isPresented: $saved) {}
        }
    }

    static let intervals = [10, 15, 20, 30, 45, 60, 120, 300, 600]

    static func randomTopic() -> String {
        let chars = Array("abcdefghijkmnopqrstuvwxyz23456789")
        return "stok-" + String((0..<16).map { _ in chars.randomElement()! })
    }
}
