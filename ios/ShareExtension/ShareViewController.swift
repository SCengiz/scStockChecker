import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share sheet entry ("Paylaş → Stok Takip"): takes the shared Zara link and
/// shows the same add screen as the app, signed in with the app's session.
final class ShareViewController: UIViewController {
    private let store = Store()

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let link = await sharedLink()
            let root = ShareRoot(link: link) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
            .environment(store)
            let host = UIHostingController(rootView: root)
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
        Task { await store.start() }
    }

    /// The shared URL, or a link found in shared text (Zara shares "NAME https://…").
    private func sharedLink() async -> String? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return url.absoluteString
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return AddLinkView.extractURL(text)
            }
        }
        return nil
    }
}

private struct ShareRoot: View {
    @Environment(Store.self) private var store
    let link: String?
    let finish: () -> Void

    var body: some View {
        if store.isRestoring {
            ProgressView()
        } else if store.userId == nil {
            NavigationStack {
                ContentUnavailableView(
                    "Giriş gerekli",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Önce Stok Takip uygulamasını açıp giriş yapın.")
                )
                .toolbar { Button("Kapat", action: finish) }
            }
        } else {
            AddLinkView(initialLink: link, onFinish: finish)
        }
    }
}
