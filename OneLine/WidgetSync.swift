import AppKit
import EventKit
import WidgetKit

// 캘린더가 바뀔 때마다 일정을 파일로 써 두고 위젯을 새로 그리게 한다.
// 위젯은 캘린더를 직접 읽지 않고, 이 파일을 읽는다.
@MainActor
final class WidgetSync {
    static let shared = WidgetSync()

    private let store = EKEventStore()
    private var pending: Task<Void, Never>?

    func start() {
        Task { [weak self] in
            guard let store = self?.store else { return }
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged, object: store) {
                self?.scheduleWrite()
            }
        }
        // 날짜가 바뀌면 '오늘' 표시를 옮긴다
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                self?.scheduleWrite()
            }
        }
        writeNow()
    }

    // 동기화 중에는 알림이 여러 번 연달아 오기 때문에 잠깐 기다렸다가 한 번만 쓴다
    func scheduleWrite() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    func writeNow() {
        guard AppGroup.isAvailable,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        guard let from = calendar.date(byAdding: .month, value: -1, to: thisMonth),
              let to = calendar.date(byAdding: .month, value: 3, to: thisMonth) else { return }

        // 반복 일정도 하나하나 펼쳐서 가져온다 (모든 캘린더)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        let items = store.events(matching: predicate).map { event in
            CalendarSnapshot.Item(
                id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                colorHex: Self.hex(event.calendar.color)
            )
        }
        do {
            try CalendarSnapshot(savedAt: .now, items: items).save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            NSLog("위젯용 일정 저장 실패: \(error)")
        }
    }

    private static func hex(_ color: NSColor?) -> String {
        guard let c = color?.usingColorSpace(.sRGB) else { return "8E8E93" }
        return String(format: "%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
