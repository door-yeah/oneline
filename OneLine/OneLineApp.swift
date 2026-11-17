import Carbon.HIToolbox
import SwiftUI

// 앱의 시작점. 메뉴 막대에 아이콘만 띄운다 (Dock에는 안 보인다).
@main
struct OneLineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("한줄 입력", systemImage: "text.badge.plus") {
            Button(delegate.shortcutLabel.isEmpty ? "입력창 열기" : "입력창 열기  \(delegate.shortcutLabel)") {
                delegate.togglePanel()
            }
            Button("설정…") { delegate.showSettings() }
            Divider()
            Button("종료") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var shortcutLabel = ""

    @ObservationIgnored private let panelController = InputPanelController()
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotKey()

        Task {
            await CalendarService.shared.requestAccess()
            // 처음 실행했을 때만 설정 창을 띄워서 캘린더를 고르게 한다
            if !UserDefaults.standard.bool(forKey: SettingsKey.didSetup) {
                UserDefaults.standard.set(true, forKey: SettingsKey.didSetup)
                showSettings()
            }
        }
    }

    // ⌥Space를 먼저 시도하고, 다른 앱이 쓰고 있으면 ⌃⌥Space로 등록한다
    private func registerHotKey() {
        let candidates: [(label: String, modifiers: Int)] = [
            ("⌥Space", optionKey),
            ("⌃⌥Space", controlKey | optionKey),
        ]
        for candidate in candidates {
            if let key = HotKey(keyCode: kVK_Space, modifiers: candidate.modifiers, action: { [weak self] in
                self?.togglePanel()
            }) {
                hotKey = key
                shortcutLabel = candidate.label
                break
            }
        }
        panelController.shortcutLabel = shortcutLabel
    }

    func togglePanel() {
        panelController.toggle()
    }

    func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(service: .shared, shortcutLabel: shortcutLabel)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "한줄 입력 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
