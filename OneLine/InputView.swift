import SwiftUI

// 입력창 화면: 입력칸 + 미리보기 + 단축키 안내
struct InputView: View {
    @Bindable var model: InputModel
    let shortcutLabel: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @Namespace private var chipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // '동작 줄이기'를 켠 사용자에게는 움직이는 애니메이션을 끈다
    private var chipAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.18) }

    var body: some View {
        VStack(spacing: 0) {
            // 1) 입력칸
            HStack(spacing: 12) {
                Image(systemName: model.isDone ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(model.isDone ? Color.green : Color.accentColor)
                    .frame(width: 26)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)

                CommandTextField(
                    text: $model.text,
                    placeholder: "내일 3시 치과",
                    focusTick: model.focusTick,
                    onSubmit: onSubmit,
                    onTab: {
                        withAnimation(chipAnimation) { model.manualKind = model.kind.next }
                    },
                    onCancel: onCancel
                )
            }
            .padding(.horizontal, 20)
            .frame(height: 60)

            Divider().opacity(0.6)

            // 2) 미리보기: 어떻게 해석했는지 + 무엇을 만들지
            HStack(spacing: 10) {
                Text(previewText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(previewIsError ? Color.red : (model.text.isEmpty ? .secondary : .primary))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.12), value: previewText)

                Spacer(minLength: 8)

                HStack(spacing: 2) {
                    ForEach(EntryKind.allCases, id: \.self) { kind in
                        chip(kind)
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 20)
            .frame(height: 44)

            // 3) 단축키 안내
            HStack(spacing: 14) {
                hint("⏎", "추가")
                hint("⇥", "종류 바꾸기")
                hint("esc", "닫기")
                Spacer()
                if !shortcutLabel.isEmpty {
                    hint(shortcutLabel, "열기")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 28)
            .background(Color.primary.opacity(0.03))
        }
        .frame(width: 640, height: 132)
    }

    // MARK: - 작은 조각들

    private func chip(_ kind: EntryKind) -> some View {
        let selected = model.kind == kind
        return Button {
            withAnimation(chipAnimation) { model.manualKind = kind }
        } label: {
            Text(kind.label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background {
                    if selected {
                        Capsule().fill(Color.accentColor).matchedGeometryEffect(id: "chip", in: chipNamespace)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 16)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(label).font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }

    private var icon: String {
        switch model.kind {
        case .both: "calendar.badge.plus"
        case .eventOnly: "calendar"
        case .reminderOnly: "checklist"
        }
    }

    private var previewIsError: Bool { model.message != nil }

    private var previewText: String {
        if let message = model.message { return message }
        if model.isDone { return "추가됨" }
        if model.text.trimmingCharacters(in: .whitespaces).isEmpty { return "날짜와 시간을 함께 쓰면 자동으로 읽어요" }

        let parsed = model.parsed
        if let start = parsed.start {
            var text = Self.dateTimeFormatter.string(from: start)
            if model.kind != .reminderOnly {
                let end = parsed.end ?? start.addingTimeInterval(3600)
                text += " – " + Self.timeFormatter.string(from: end)
            }
            return text
        }
        if let day = parsed.day {
            return Self.dateFormatter.string(from: day) + (model.kind == .reminderOnly ? " 마감" : " 하루 종일")
        }
        return model.kind == .reminderOnly ? "날짜 없음" : "오늘 하루 종일"
    }

    // 날짜 표시 형식. 순서와 글자는 한국어 규칙(locale)이 정한다
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let dateTimeFormatter = formatter("MMMdEEEhmm")
    private static let dateFormatter = formatter("MMMdEEE")
    private static let timeFormatter = formatter("hmm")
}

// 엔터 / Tab / esc 키를 직접 받아야 해서, SwiftUI 기본 입력칸 대신 AppKit 입력칸을 감싸서 쓴다.
// (한글은 글자를 조합하는 중에 키가 눌리기 때문에, 조합 중인 글자까지 포함해서 읽는다)
struct CommandTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusTick: Int
    let onSubmit: (String) -> Void
    let onTab: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22, weight: .regular)
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // 한글 조합 중에는 글자를 건드리지 않는다 (조합이 깨진다)
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if !composing, field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            Task { @MainActor in field.window?.makeFirstResponder(field) }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandTextField
        var lastFocusTick = -1

        init(_ parent: CommandTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(textView.string)
                return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                parent.onTab()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
