import AppKit
import AVFoundation
import Carbon
import ServiceManagement
import Sparkle
import UserNotifications
import WebKit

// MARK: - Ayarlar (UserDefaults persistence)

struct Settings {
    static let suite = UserDefaults.standard

    private enum Key {
        static let workMinutes = "workMinutes"
        static let shortMinutes = "shortMinutes"
        static let longMinutes = "longMinutes"
        static let soundEnabled = "soundEnabled"
        static let voiceEnabled = "voiceEnabled"
        static let notificationEnabled = "notificationEnabled"
    }

    static var workMinutes: Int {
        get { suite.object(forKey: Key.workMinutes) as? Int ?? 25 }
        set { suite.set(newValue, forKey: Key.workMinutes) }
    }
    static var shortMinutes: Int {
        get { suite.object(forKey: Key.shortMinutes) as? Int ?? 5 }
        set { suite.set(newValue, forKey: Key.shortMinutes) }
    }
    static var longMinutes: Int {
        get { suite.object(forKey: Key.longMinutes) as? Int ?? 15 }
        set { suite.set(newValue, forKey: Key.longMinutes) }
    }
    static var soundEnabled: Bool {
        get { suite.object(forKey: Key.soundEnabled) as? Bool ?? true }
        set { suite.set(newValue, forKey: Key.soundEnabled) }
    }
    static var voiceEnabled: Bool {
        get { suite.object(forKey: Key.voiceEnabled) as? Bool ?? true }
        set { suite.set(newValue, forKey: Key.voiceEnabled) }
    }
    static var notificationEnabled: Bool {
        get { suite.object(forKey: Key.notificationEnabled) as? Bool ?? true }
        set { suite.set(newValue, forKey: Key.notificationEnabled) }
    }
}

// MARK: - WebKit ↔ Swift köprüsü

final class TickBridge: NSObject, WKScriptMessageHandler {
    var onTick: ((String, String, String) -> Void)?
    var onComplete: ((String, Int) -> Void)?

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        switch message.name {
        case "tick":
            let time = body["time"] as? String ?? "--:--"
            let mode = body["mode"] as? String ?? ""
            let count = body["count"] as? String ?? "0"
            onTick?(time, mode, count)
        case "complete":
            let from = body["from"] as? String ?? "work"
            let count = body["count"] as? Int ?? 0
            onComplete?(from, count)
        default:
            break
        }
    }
}

// MARK: - WebView controller (popover içeriği + dinamik boyutlandırma)

final class WebViewController: NSViewController, WKNavigationDelegate {
    let bridge = TickBridge()
    private(set) var webView: WKWebView!
    var onContentSize: ((NSSize) -> Void)?

    private static let defaultSize = NSSize(width: 380, height: 600)

    override func loadView() {
        preferredContentSize = Self.defaultSize

        let userController = WKUserContentController()
        userController.add(bridge, name: "tick")
        userController.add(bridge, name: "complete")

        let observerScript = """
        (function() {
          const ids = ['time', 'modeLabel', 'counterNum'];
          function emit() {
            const get = (id) => document.getElementById(id)?.textContent?.trim() ?? '';
            window.webkit.messageHandlers.tick.postMessage({
              time: get('time'),
              mode: get('modeLabel'),
              count: get('counterNum'),
            });
          }
          function arm() {
            const targets = ids
              .map((id) => document.getElementById(id))
              .filter(Boolean);
            if (targets.length === 0) {
              setTimeout(arm, 50);
              return;
            }
            const obs = new MutationObserver(emit);
            targets.forEach((node) => {
              obs.observe(node, { childList: true, characterData: true, subtree: true });
            });
            emit();
          }
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', arm);
          } else {
            arm();
          }
        })();
        """
        userController.addUserScript(WKUserScript(
            source: observerScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let config = WKWebViewConfiguration()
        config.userContentController = userController

        webView = WKWebView(
            frame: NSRect(origin: .zero, size: Self.defaultSize),
            configuration: config
        )
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        view = webView

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyDurations()
        // İçerik gerçek yüksekliği için bir frame bekle, sonra ölç
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.measureAndReportSize()
        }
    }

    func applyDurations() {
        let js = "if (window.__setDurations) __setDurations(\(Settings.workMinutes), \(Settings.shortMinutes), \(Settings.longMinutes));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func measureAndReportSize() {
        let js = "Math.max(document.documentElement.scrollHeight, document.body.scrollHeight)"
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            guard let raw = result as? CGFloat else { return }
            let height = max(560, min(raw + 8, 720)) // 560–720 arasına sıkıştır
            let size = NSSize(width: 380, height: height)
            DispatchQueue.main.async {
                self?.preferredContentSize = size
                self?.onContentSize?(size)
            }
        }
    }
}

// MARK: - Tamamlanma motoru (ses + konuşma + bildirim)

final class CompletionEngine {
    private let synthesizer = AVSpeechSynthesizer()

    func handle(finishedMode: String) {
        let nextHint: String
        let soundName: String
        switch finishedMode {
        case "work":
            nextHint = "Pomodoro tamam. Şimdi biraz soluklan."
            soundName = "Hero"
        case "short":
            nextHint = "Kısa mola bitti. Yeniden odaklanma zamanı."
            soundName = "Glass"
        case "long":
            nextHint = "Uzun mola bitti. Yeni pomodoro başlasın."
            soundName = "Glass"
        default:
            nextHint = "Pomodoro turu tamamlandı."
            soundName = "Glass"
        }

        if Settings.soundEnabled {
            NSSound(named: NSSound.Name(soundName))?.play()
        }
        if Settings.voiceEnabled {
            speak(nextHint)
        }
        if Settings.notificationEnabled {
            sendNotification(title: "🍅 Pomodoro tamam", body: nextHint)
        }
    }

    private func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

// MARK: - Login Items (Mac başlangıcında otomatik başlatma)

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Login Item toggle hatası: \(error)")
        }
    }

    static var statusLabel: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "etkin"
        case .notRegistered: return "kapalı"
        case .requiresApproval: return "onay gerekli (Sistem Ayarları)"
        case .notFound: return "bulunamadı"
        @unknown default: return "bilinmiyor"
        }
    }
}

// MARK: - Global hotkey (Carbon RegisterEventHotKey)

final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                if let userData = userData {
                    let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async { me.onPress?() }
                }
                return noErr
            },
            1,
            &spec,
            opaque,
            &handler
        )
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        var hotKeyRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: fourCharCode("PmHK"), id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            ref = hotKeyRef
        }
    }

    func unregister() {
        if let ref = ref {
            UnregisterEventHotKey(ref)
        }
        ref = nil
    }

    deinit {
        unregister()
        if let handler = handler {
            RemoveEventHandler(handler)
        }
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) + OSType(char)
    }
    return result
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let webController = WebViewController()
    private let completion = CompletionEngine()
    private let hotKey = GlobalHotKey()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🍅 \(formatMinutes(Settings.workMinutes))"
            button.target = self
            button.action = #selector(handleStatusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.contentSize = NSSize(width: 380, height: 600)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = webController

        webController.bridge.onTick = { [weak self] time, mode, _ in
            DispatchQueue.main.async { self?.updateStatusBar(time: time, mode: mode) }
        }
        webController.bridge.onComplete = { [weak self] from, _ in
            DispatchQueue.main.async { self?.completion.handle(finishedMode: from) }
        }
        webController.onContentSize = { [weak self] size in
            self?.popover.contentSize = size
        }
        // view'i zorla yükle (loadView tetiklenir, HTML yüklenmesi başlar)
        _ = webController.view

        // Bildirim izni iste (yalnızca .app bundle içinden çalışır)
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }

        // Global hotkey: ⌘⇧P → popover toggle
        hotKey.onPress = { [weak self] in
            self?.togglePopover()
        }
        hotKey.register(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | shiftKey)
        )
    }

    // MARK: - Status bar etkileşimi

    @objc private func handleStatusClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showSettingsMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusBar(time: String, mode: String) {
        let icon: String
        switch mode {
        case "Çalışma": icon = "🍅"
        case "Kısa Mola", "Uzun Mola": icon = "☕"
        default: icon = "⏱"
        }
        statusItem.button?.title = "\(icon) \(time)"
    }

    private func formatMinutes(_ minutes: Int) -> String {
        return String(format: "%02d:00", minutes)
    }

    // MARK: - Sağ tık ayarlar menüsü

    private func showSettingsMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem.sectionHeader(title: "Süreler"))
        menu.addItem(durationSubmenu(
            title: "Çalışma",
            options: [15, 20, 25, 30, 45, 60, 90],
            current: Settings.workMinutes,
            apply: { Settings.workMinutes = $0 }
        ))
        menu.addItem(durationSubmenu(
            title: "Kısa Mola",
            options: [3, 5, 7, 10, 15],
            current: Settings.shortMinutes,
            apply: { Settings.shortMinutes = $0 }
        ))
        menu.addItem(durationSubmenu(
            title: "Uzun Mola",
            options: [10, 15, 20, 25, 30],
            current: Settings.longMinutes,
            apply: { Settings.longMinutes = $0 }
        ))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Bildirimler"))
        menu.addItem(toggleItem(
            title: "Sistem sesi (Glass)",
            isOn: Settings.soundEnabled,
            action: #selector(toggleSound)
        ))
        menu.addItem(toggleItem(
            title: "Sesli okuma (Türkçe TTS)",
            isOn: Settings.voiceEnabled,
            action: #selector(toggleVoice)
        ))
        menu.addItem(toggleItem(
            title: "Mac bildirimi",
            isOn: Settings.notificationEnabled,
            action: #selector(toggleNotification)
        ))

        let testItem = NSMenuItem(
            title: "Bildirimi test et",
            action: #selector(testNotification),
            keyEquivalent: ""
        )
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Sistem"))

        let loginItem = NSMenuItem(
            title: "Mac açılışında otomatik başlat (\(LoginItem.statusLabel))",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.state = LoginItem.isEnabled ? .on : .off
        loginItem.target = self
        menu.addItem(loginItem)

        let hotkeyHint = NSMenuItem(
            title: "Kısayol: ⌘⇧P (popover aç/kapat)",
            action: nil,
            keyEquivalent: ""
        )
        hotkeyHint.isEnabled = false
        menu.addItem(hotkeyHint)

        let checkUpdate = NSMenuItem(
            title: "Güncellemeleri kontrol et…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdate.target = self
        menu.addItem(checkUpdate)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(
            title: "Pomodoro'dan Çık",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func durationSubmenu(
        title: String,
        options: [Int],
        current: Int,
        apply: @escaping (Int) -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title): \(current) dk", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in options {
            let sub = NSMenuItem(
                title: "\(value) dakika",
                action: #selector(durationSelected(_:)),
                keyEquivalent: ""
            )
            sub.target = self
            sub.state = (value == current) ? .on : .off
            sub.representedObject = DurationChange(value: value, apply: apply)
            submenu.addItem(sub)
        }
        item.submenu = submenu
        return item
    }

    private func toggleItem(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = isOn ? .on : .off
        item.target = self
        return item
    }

    @objc private func durationSelected(_ sender: NSMenuItem) {
        guard let change = sender.representedObject as? DurationChange else { return }
        change.apply(change.value)
        webController.applyDurations()
    }

    @objc private func toggleSound() { Settings.soundEnabled.toggle() }
    @objc private func toggleVoice() { Settings.voiceEnabled.toggle() }
    @objc private func toggleNotification() { Settings.notificationEnabled.toggle() }
    @objc private func toggleLoginItem() { LoginItem.toggle() }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func testNotification() {
        completion.handle(finishedMode: "work")
    }
}

private struct DurationChange {
    let value: Int
    let apply: (Int) -> Void
}

private extension NSMenuItem {
    static func sectionHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        item.isEnabled = false
        return item
    }
}

// MARK: - Lifecycle

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
