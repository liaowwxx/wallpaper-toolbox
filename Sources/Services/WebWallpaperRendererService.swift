import AppKit
import Combine
import Foundation
import ImageIO
import WebKit

@MainActor
final class WebWallpaperRendererService {
    private struct WebSurface {
        let window: NSWindow
        let webView: WKWebView
        let navigationDelegate: WebWallpaperNavigationDelegate
        let screenID: String
    }

    private var surfaces: [String: WebSurface] = [:]
    private var activeContentURL: URL?
    private var activeAllScreens = false
    private var mouseEventMonitors: [Any] = []
    private var lastMouseMoveTime: TimeInterval = 0
    private let mouseMoveThrottle: TimeInterval = 1.0 / 30.0
    private var audioCancellable: AnyCancellable?

    func setWebWallpaper(contentURL: URL, allScreens: Bool) throws {
        let entryURL = try Self.resolveWebEntryURL(from: contentURL)
        let contentRoot = Self.contentRoot(for: contentURL, entryURL: entryURL)
        let screens = allScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        guard !screens.isEmpty else {
            throw WebWallpaperRendererError.noScreenAvailable
        }

        stop()

        for screen in screens {
            let webSurface = Self.makeWebView(contentRoot: contentRoot)
            let webView = webSurface.webView
            let window = Self.makeWallpaperWindow(for: screen, webView: webView)
            let screenID = Self.screenIdentifier(for: screen)
            surfaces[screenID] = WebSurface(
                window: window,
                webView: webView,
                navigationDelegate: webSurface.navigationDelegate,
                screenID: screenID
            )
            Self.load(entryURL: entryURL, contentRoot: contentRoot, in: webView)
            window.orderFrontRegardless()
        }

        activeContentURL = contentURL
        activeAllScreens = allScreens
        startMouseEventBridge()
        startAudioBridge()
    }

    func isRendering(contentURL: URL) -> Bool {
        activeContentURL?.standardizedFileURL == contentURL.standardizedFileURL
    }

    func stop() {
        stopMouseEventBridge()
        stopAudioBridge()
        for (_, surface) in surfaces {
            surface.webView.stopLoading()
            surface.webView.navigationDelegate = nil
            surface.webView.configuration.userContentController.removeAllUserScripts()
            surface.webView.loadHTMLString("", baseURL: nil)
            surface.window.orderOut(nil)
            surface.window.close()
        }
        surfaces.removeAll()
        activeContentURL = nil
        activeAllScreens = false
    }

    func captureFirstFrame() async -> URL? {
        guard let surface = surfaces.values.first else { return nil }
        try? await Task.sleep(for: .milliseconds(800))
        return await withCheckedContinuation { continuation in
            let config = WKSnapshotConfiguration()
            config.rect = surface.webView.bounds
            surface.webView.takeSnapshot(with: config) { image, _ in
                guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.writeCapturedFrame(cgImage))
            }
        }
    }

    private static func makeWallpaperWindow(for screen: NSScreen, webView: WKWebView) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = webView
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        return window
    }

    private static func makeWebView(contentRoot: URL) -> (webView: WKWebView, navigationDelegate: WebWallpaperNavigationDelegate) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.websiteDataStore = .nonPersistent()

        let contentController = WKUserContentController()
        contentController.addUserScript(wallpaperEngineWebAPIShim)
        contentController.addUserScript(localFileCompatScript)
        contentController.addUserScript(mouseEventBridgeScript)
        config.userContentController = contentController
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        let navigationDelegate = WebWallpaperNavigationDelegate(contentRoot: contentRoot)
        webView.navigationDelegate = navigationDelegate
        return (webView, navigationDelegate)
    }

    private static func load(entryURL: URL, contentRoot: URL, in webView: WKWebView) {
        if entryURL.isFileURL {
            webView.loadFileURL(entryURL, allowingReadAccessTo: contentRoot)
        } else {
            webView.load(URLRequest(url: entryURL))
        }
    }

    private static func contentRoot(for contentURL: URL, entryURL: URL) -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: contentURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return contentURL
        }
        return entryURL.deletingLastPathComponent()
    }

    static func resolveWebEntryURL(from url: URL) throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false

        if ["html", "htm"].contains(url.pathExtension.lowercased()) {
            return url
        }

        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WebWallpaperRendererError.entryNotFound
        }

        let indexHTML = url.appendingPathComponent("index.html")
        if fm.fileExists(atPath: indexHTML.path) {
            return indexHTML
        }

        let projectJSON = url.appendingPathComponent("project.json")
        if let data = try? Data(contentsOf: projectJSON),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let file = json["file"] as? String {
            let fileURL = url.appendingPathComponent(file)
            if fm.fileExists(atPath: fileURL.path),
               ["html", "htm"].contains(fileURL.pathExtension.lowercased()) {
                return fileURL
            }
        }

        if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
           let firstHTML = contents.first(where: { ["html", "htm"].contains($0.pathExtension.lowercased()) }) {
            return firstHTML
        }

        throw WebWallpaperRendererError.entryNotFound
    }

    private static func screenIdentifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return screen.localizedName
    }

    private static func writeCapturedFrame(_ image: CGImage) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("repkg-web-frame-\(Int(Date().timeIntervalSince1970)).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: AppConstants.frameCaptureJPEGQuality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    private static let wallpaperEngineWebAPIShim = WKUserScript(
        source: """
        (function() {
          try {
            window.wallpaperMediaIntegration = {
              playback: { PLAYING: 1, PAUSED: 2, STOPPED: 0 }
            };
            var audioCallbacks = [];
            var audioBuffer = new Float32Array(128);
            var audioEnabled = false;
            window.wallpaperRegisterAudioListener = function(callback) {
              if (typeof callback === 'function') audioCallbacks.push(callback);
            };
            window.__wtUpdateAudioBuf = function(values) {
              if (values && values.length) {
                audioEnabled = true;
                for (var i = 0; i < audioBuffer.length && i < values.length; i++) {
                  audioBuffer[i] = values[i];
                }
                for (var j = 0; j < audioCallbacks.length; j++) {
                  try { audioCallbacks[j](audioBuffer); } catch (e) {}
                }
              }
            };
            setInterval(function() {
              if (!audioEnabled) {
                for (var k = 0; k < audioBuffer.length; k++) audioBuffer[k] = 0;
              }
              for (var i = 0; i < audioCallbacks.length; i++) {
                try { audioCallbacks[i](audioBuffer); } catch (e) {}
              }
            }, 33);
            window.wallpaperRegisterMediaStatusListener = function(callback) {
              if (typeof callback === 'function') {
                try { callback({ enabled: false }); } catch (e) {}
              }
            };
            window.wallpaperRegisterMediaPropertiesListener = function(callback) {};
            window.wallpaperRegisterMediaThumbnailListener = function(callback) {};
            window.wallpaperRegisterMediaPlaybackListener = function(callback) {
              if (typeof callback === 'function') {
                try { callback({ state: window.wallpaperMediaIntegration.playback.STOPPED }); } catch (e) {}
              }
            };
            window.wallpaperRegisterMediaTimelineListener = function(callback) {};
          } catch (e) {}
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    private static let mouseEventBridgeScript = WKUserScript(
        source: """
        (function() {
          if (window.__wtMouseBridge) return;
          window.__wtMouseBridge = {
            lastDownTarget: null,
            dispatch: function(type, x, y, button, deltaX, deltaY) {
              var target = document.elementFromPoint(x, y) || document.documentElement;
              if (type === 'wheel') {
                target.dispatchEvent(new WheelEvent('wheel', {
                  clientX: x, clientY: y,
                  deltaX: deltaX || 0, deltaY: deltaY || 0,
                  bubbles: true, cancelable: true, view: window
                }));
                return;
              }
              var event = new MouseEvent(type, {
                clientX: x, clientY: y,
                screenX: x, screenY: y,
                bubbles: true, cancelable: true,
                button: button || 0,
                buttons: type === 'mouseup' ? 0 : 1,
                view: window
              });
              target.dispatchEvent(event);
              if (type === 'mousedown') this.lastDownTarget = target;
              if (type === 'mouseup' && this.lastDownTarget) {
                this.lastDownTarget.dispatchEvent(new MouseEvent('click', {
                  clientX: x, clientY: y,
                  bubbles: true, cancelable: true,
                  button: button || 0,
                  view: window
                }));
                this.lastDownTarget = null;
              }
            }
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    private static let localFileCompatScript = WKUserScript(
        source: """
        (function() {
          try {
            if (location.protocol !== "file:") return;
            var proto = HTMLImageElement.prototype;
            var srcDesc = Object.getOwnPropertyDescriptor(proto, "src");
            if (srcDesc && srcDesc.set) {
              Object.defineProperty(proto, "src", {
                set: function(value) {
                  try {
                    var source = String(value || "");
                    if (source.indexOf("http:") !== 0 && source.indexOf("https:") !== 0 && source.indexOf("data:") !== 0 && source.indexOf("blob:") !== 0) {
                      this.removeAttribute("crossorigin");
                    }
                  } catch (e) {}
                  srcDesc.set.call(this, value);
                },
                get: srcDesc.get,
                configurable: true
              });
            }
            var originalFetch = window.fetch;
            if (typeof originalFetch === "function") {
              window.fetch = function(input, init) {
                var url = typeof input === "string" ? input : (input && input.url) ? input.url : "";
                if (url && url.indexOf("http:") !== 0 && url.indexOf("https:") !== 0 && url.indexOf("data:") !== 0 && url.indexOf("blob:") !== 0) {
                  return new Promise(function(resolve, reject) {
                    var xhr = new XMLHttpRequest();
                    xhr.open("GET", url, true);
                    xhr.onload = function() {
                      if (xhr.status === 200 || xhr.status === 0) {
                        resolve(new Response(xhr.responseText, { status: 200, statusText: "OK" }));
                      } else {
                        reject(new Error("HTTP " + xhr.status));
                      }
                    };
                    xhr.onerror = function() { reject(new Error("network error")); };
                    xhr.send();
                  });
                }
                return originalFetch.call(this, input, init);
              };
            }
          } catch (e) {}
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    private func startAudioBridge() {
        let audioService = SystemAudioCaptureService.shared
        audioService.start()
        audioCancellable = audioService.spectrum64Publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spectrum in
                self?.pushAudioSpectrum(spectrum)
            }
    }

    private func stopAudioBridge() {
        audioCancellable?.cancel()
        audioCancellable = nil
        SystemAudioCaptureService.shared.stop()
    }

    private func pushAudioSpectrum(_ spectrum: [Float]) {
        guard !surfaces.isEmpty else { return }
        let doubled = spectrum.flatMap { value in [value, value] }
        let values = doubled.prefix(128).map { String(format: "%.4f", $0) }.joined(separator: ",")
        let source = "if(window.__wtUpdateAudioBuf){window.__wtUpdateAudioBuf([\(values)]);}"
        for (_, surface) in surfaces {
            surface.webView.evaluateJavaScript(source) { _, _ in }
        }
    }

    private func startMouseEventBridge() {
        stopMouseEventBridge()
        guard !surfaces.isEmpty else { return }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            self?.handleGlobalMouseEvent(event, type: "mousedown")
        }) {
            mouseEventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            self?.handleGlobalMouseEvent(event, type: "mouseup")
        }) {
            mouseEventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastMouseMoveTime >= self.mouseMoveThrottle else { return }
            self.lastMouseMoveTime = now
            self.handleGlobalMouseEvent(event, type: "mousemove")
        }) {
            mouseEventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.handleGlobalMouseEvent(event, type: "wheel")
        }) {
            mouseEventMonitors.append(monitor)
        }
    }

    private func stopMouseEventBridge() {
        for monitor in mouseEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseEventMonitors.removeAll()
        lastMouseMoveTime = 0
    }

    private func handleGlobalMouseEvent(_ event: NSEvent, type: String) {
        let location = NSEvent.mouseLocation
        guard let surface = surfaces.values.first(where: { $0.window.frame.contains(location) }) else { return }

        let relX = location.x - surface.window.frame.origin.x
        let relY = location.y - surface.window.frame.origin.y
        let webX = relX
        let webY = surface.window.frame.height - relY
        guard webX >= 0, webX <= surface.webView.bounds.width,
              webY >= 0, webY <= surface.webView.bounds.height else { return }

        var source = "if(window.__wtMouseBridge){window.__wtMouseBridge.dispatch('\(type)',\(webX),\(webY),0"
        if type == "wheel" {
            source += ",\(event.scrollingDeltaX),\(event.scrollingDeltaY)"
        } else {
            source += ",0,0"
        }
        source += ");}"
        surface.webView.evaluateJavaScript(source) { _, _ in }
    }
}

private final class WebWallpaperNavigationDelegate: NSObject, WKNavigationDelegate {
    let contentRoot: URL

    init(contentRoot: URL) {
        self.contentRoot = contentRoot
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        runBootstrap(in: webView)
    }

    private func runBootstrap(in webView: WKWebView) {
        let script = """
        (function(){
          try {
            document.documentElement.style.cssText = 'width:100%;height:100%;margin:0;padding:0;background:transparent;overflow:hidden;';
            document.body.style.setProperty('width', '100%');
            document.body.style.setProperty('height', '100%');
            document.body.style.setProperty('margin', '0');
            document.body.style.setProperty('overflow', 'hidden');
            var playerContainer = document.getElementById('player-container');
            if (playerContainer) {
              playerContainer.style.width = '100%';
              playerContainer.style.height = '100%';
            }
            window.dispatchEvent(new Event('resize'));
          } catch(e) {}
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { _, _ in }
    }
}

enum WebWallpaperRendererError: LocalizedError {
    case entryNotFound
    case noScreenAvailable

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            return "Web wallpaper entry HTML was not found."
        case .noScreenAvailable:
            return "No display is available to render the web wallpaper on."
        }
    }
}
