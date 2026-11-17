import AppKit
import SwiftUI

// 입력창의 상태 (입력한 글자, 해석 결과, 고른 종류)
@MainActor
@Observable
final class InputModel {
    var text = "" {
        didSet {
            parsed = KoreanDateParser.parse(text)
            if text != oldValue { message = nil }
        }
    }
    private(set) var parsed = KoreanDateParser.parse("")
    var manualKind: EntryKind? {   // Tab으로 직접 고른 종류 (없으면 자동 판단)
        didSet { message = nil }
    }
    var message: String?           // 오류 안내
    var isDone = false             // "추가됨" 표시 중
    var focusTick = 0              // 값이 바뀌면 입력칸에 커서를 둔다

    var kind: EntryKind { manualKind ?? parsed.suggestedKind }

    func reset() {
        text = ""
        manualKind = nil
        message = nil
        isDone = false
        focusTick += 1
    }
}

// 테두리 없는 창은 기본적으로 글자를 입력받지 못해서, 입력받을 수 있게 바꾼 패널
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// Spotlight처럼 화면 위에 떠 있는 입력창을 띄우고 닫는다
@MainActor
final class InputPanelController: NSObject, NSWindowDelegate {
    private let model = InputModel()
    private var panel: NSPanel?
    var shortcutLabel = ""

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reset()

        // 마우스가 있는 화면의 위쪽 1/3 지점에 띄운다
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                         y: frame.minY + frame.height * 0.68 - size.height / 2))
        }

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // 다른 곳을 클릭하면 닫는다
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func submit(_ text: String) {
        guard !model.isDone else { return }
        model.text = text
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            try CalendarService.shared.add(model.parsed, kind: model.kind)
            withAnimation(.easeOut(duration: 0.15)) { model.isDone = true }
            // 잠깐 "추가됨"을 보여주고 닫는다
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard self?.model.isDone == true else { return }
                self?.hide()
            }
        } catch {
            model.message = error.localizedDescription
        }
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 640, height: 132)
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        // 반투명 유리 느낌의 배경
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true

        let view = InputView(
            model: model,
            shortcutLabel: shortcutLabel,
            onSubmit: { [weak self] text in self?.submit(text) },
            onCancel: { [weak self] in self?.hide() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)

        panel.contentView = background
        return panel
    }
}
