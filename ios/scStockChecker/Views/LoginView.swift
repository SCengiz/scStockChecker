import SwiftUI

struct LoginView: View {
    @Environment(Store.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kullanıcı adı", text: $email)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Şifre", text: $password)
                        .textContentType(.password)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text("Giriş yap")
                            if isLoading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                }
            }
            .navigationTitle("Stok Takip")
        }
    }

    private func signIn() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await store.signIn(username: email, password: password)
            error = nil
        } catch {
            self.error = "Giriş yapılamadı: \(error.localizedDescription)"
        }
    }
}
