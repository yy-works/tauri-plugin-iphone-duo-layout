import UIKit
import WebKit
import Tauri
import LayoutMetricsNative

final class LayoutMetricsPlugin: Plugin {
    private weak var host: WKWebView?
    private var reader: LayoutSnapshotReader?
    private var subscribers = 0

    @objc override func load(webview: WKWebView) {
        host = webview
        DispatchQueue.main.async { [weak self, weak webview] in
            guard let self, let webview else { return }
            self.ensureReaderAttached(for: webview)
        }
    }

    private func ensureReaderAttached(for webview: WKWebView) {
        if reader == nil {
            let r = LayoutSnapshotReader()
            self.reader = r
            r.onChange = { [weak self, weak webview] snapshot in
                guard let self else { return }
                // 1. Tauri plugin event notification
                do { try self.trigger("change", data: snapshot) }
                catch { NSLog("iphone-duo-layout: snapshot encoding failed: %@", String(describing: error)) }

                // 2. Direct DOM injection into WebView (__duoMetrics & duo-metrics CustomEvent)
                if let webview {
                    self.injectDuoMetrics(into: webview, snapshot: snapshot)
                }
            }
            // Keep WebView background transparent & clear so app background renders cleanly
            webview.isOpaque = false
            webview.backgroundColor = .clear
            webview.scrollView.backgroundColor = .clear
            r.attach(to: webview)
        }
    }

    private func injectDuoMetrics(into webview: WKWebView, snapshot: NativeLayoutSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              var value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let adjusted = webview.scrollView.adjustedContentInset
        value["adjustedInsets"] = [
            "top": adjusted.top,
            "right": adjusted.right,
            "bottom": adjusted.bottom,
            "left": adjusted.left
        ]
        value["viewportWidth"] = max(0, webview.bounds.width - adjusted.left - adjusted.right)
        value["viewportHeight"] = max(0, webview.bounds.height - adjusted.top - adjusted.bottom)

        if let radius = snapshot.cornerRadius, radius > 0 {
            webview.layer.cornerRadius = radius
            webview.layer.masksToBounds = true
            webview.window?.backgroundColor = .black
        }

        guard let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let json = String(data: encoded, encoding: .utf8) else { return }
        let script = """
        (() => {
          const next = \(json);
          if (JSON.stringify(window.__duoMetrics) !== JSON.stringify(next)) {
            window.__duoMetrics = next;
            window.dispatchEvent(new CustomEvent('duo-metrics', { detail: next }));
          }
        })()
        """
        webview.evaluateJavaScript(script, completionHandler: nil)
    }

    @objc func start(_ invoke: Invoke) {
        DispatchQueue.main.async { [self] in
            guard let host else { invoke.reject("WebView is unavailable"); return }
            subscribers += 1
            ensureReaderAttached(for: host)
            reader?.sample()
            invoke.resolve()
        }
    }

    @objc func getSnapshot(_ invoke: Invoke) {
        DispatchQueue.main.async { [self] in
            reader?.sample()
            invoke.resolve(reader?.snapshot)
        }
    }

    @objc func stop(_ invoke: Invoke) {
        DispatchQueue.main.async { [self] in
            subscribers = max(0, subscribers - 1)
            invoke.resolve()
        }
    }
}

@_cdecl("init_plugin_iphone_duo_layout")
func initPlugin() -> Plugin { LayoutMetricsPlugin() }
