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

                Section("Son bildirimler") {
                    if store.notifications.isEmpty {
                        Text("Henüz bildirim yok").foregroundStyle(.secondary)
                    }
                    ForEach(store.notifications) { note in
                        Button {
                            if let url = note.url.flatMap(URL.init(string:)) { openURL(url) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).font(.subheadline).foregroundStyle(.primary)
                                Text(note.body).font(.caption).foregroundStyle(.secondary)
                                Text(note.sentAt.formatted(.relative(presentation: .named)))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
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

    static func randomTopic() -> String {
        let chars = Array("abcdefghijkmnopqrstuvwxyz23456789")
        return "stok-" + String((0..<16).map { _ in chars.randomElement()! })
    }
}
