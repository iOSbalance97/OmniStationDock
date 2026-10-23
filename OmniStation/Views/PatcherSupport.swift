import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - Parcheador (Rom Patcher JS de Marc Robledo, MIT)

/// Rom Patcher JS dentro de OmniStation, sin conexión: sus archivos van en la app
/// (Resources/RomPatcher) y se sirven con un esquema propio («omnipatcher://»), así sus web
/// workers funcionan. La ROM parcheada se guarda en Archivos → OmniStation Dock → Parcheados.
struct PatcherSheet: View {
    let lang: String
    var onPatched: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PatcherWebView { url in onPatched(url) }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(L10n.tr("Parcheador", lang))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.tr("Listo", lang)) { dismiss() }
                            .font(AppFont.text(14, .bold))
                            .foregroundStyle(Color.cyan)
                    }
                }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}

/// Carpeta donde se guarda lo parcheado.
enum PatcherFolders {
    static var output: URL {
        let documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url: URL = documents.appendingPathComponent("Parcheados", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var bundle: URL? {
        Bundle.main.url(forResource: "RomPatcher", withExtension: nil)
    }
}

struct PatcherWebView: UIViewRepresentable {
    var onPatched: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPatched: onPatched) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: Coordinator.scheme)
        // La web libera el archivo justo después de pedir la descarga: se espera un poco para que dé tiempo.
        let keepBlobs = """
        (function(){ var revoke = URL.revokeObjectURL; URL.revokeObjectURL = function(u){ setTimeout(function(){ revoke.call(URL, u); }, 120000); }; })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: keepBlobs, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // Fondo oscuro como el resto de la app.
        let dark = """
        var s = document.createElement('style'); s.textContent = 'html,body{background:#050b1a !important;color-scheme:dark;}'; document.head.appendChild(s);
        """
        configuration.userContentController.addUserScript(WKUserScript(source: dark, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        if let url = URL(string: Coordinator.scheme + "://app/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate, WKDownloadDelegate {
        static let scheme = "omnipatcher"
        let onPatched: (URL) -> Void
        private var destinations: [ObjectIdentifier: URL] = [:]

        init(onPatched: @escaping (URL) -> Void) {
            self.onPatched = onPatched
        }

        // MARK: Archivos de la web

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url, let root = PatcherFolders.bundle else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            var path: String = url.path
            if path.isEmpty || path == "/" { path = "/index.html" }
            let file: URL = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
            guard file.path.hasPrefix(root.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let type: String = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let mime: String = file.pathExtension.lowercased() == "js" ? "text/javascript" : type
            let headers: [String: String] = ["Content-Type": mime, "Content-Length": "\(data.count)", "Cache-Control": "no-cache"]
            if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) {
                urlSchemeTask.didReceive(response)
            }
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

        // MARK: Enlaces y descargas

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }
            // Los enlaces de fuera (GitHub, la web del autor) van a Safari.
            if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let name: String = suggestedFilename.isEmpty ? "parcheado.bin" : suggestedFilename
            let target: URL = PatcherFolders.output.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: target)
            destinations[ObjectIdentifier(download)] = target
            completionHandler(target)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let target = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            DispatchQueue.main.async { self.onPatched(target) }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            destinations.removeValue(forKey: ObjectIdentifier(download))
        }
    }
}
