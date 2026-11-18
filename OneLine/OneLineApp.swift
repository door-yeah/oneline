import Carbon.HIToolbox
import ServiceManagement
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

        // 처음 한 번은 로그인할 때 자동으로 켜지게 등록한다. 끄고 싶으면 설정에서 끈다
        if !UserDefaults.standard.bool(forKey: SettingsKey.didSetupLaunchAtLogin) {
            UserDefaults.standard.set(true, forKey: SettingsKey.didSetupLaunchAtLogin)
            try? SMAppService.mainApp.register()
        }

        Task {
            await CalendarService.shared.requestAccess()
            // 권한을 받은 뒤부터 위젯에 보낼 일정을 써 둔다
            WidgetSync.shared.start()
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

    // 위젯을 누르면 oneline:// 주소로 이 앱이 열린다
    // oneline://new → 입력창, 그 밖에는 캘린더 앱을 연다
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.scheme == "oneline" else { return }
        if url.host == "new" {
            panelController.show()
        } else if let calendarApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: calendarApp, configuration: .init())
        }
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
