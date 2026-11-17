import EventKit
import Observation

// 설정값을 저장할 때 쓰는 이름표
enum SettingsKey {
    static let eventCalendarID = "eventCalendarID"   // 일정을 넣을 캘린더
    static let reminderListID = "reminderListID"     // 미리알림을 넣을 목록
    static let alarmMinutes = "alarmMinutes"         // 몇 분 전에 알릴지
    static let didSetup = "didSetup"                 // 첫 실행 설정을 마쳤는지
}

enum CalendarError: LocalizedError {
    case noEventAccess, noReminderAccess, noCalendar, noReminderList

    var errorDescription: String? {
        switch self {
        case .noEventAccess: return "캘린더 접근 권한이 없어요. 시스템 설정에서 허용해 주세요."
        case .noReminderAccess: return "미리알림 접근 권한이 없어요. 시스템 설정에서 허용해 주세요."
        case .noCalendar: return "일정을 넣을 캘린더가 없어요. 설정에서 골라 주세요."
        case .noReminderList: return "미리알림 목록이 없어요. 설정에서 골라 주세요."
        }
    }
}

// 캘린더와 미리알림에 실제로 읽고 쓰는 부분.
// 애플의 EventKit이 두 가지를 모두 담당한다.
@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    @ObservationIgnored private let store = EKEventStore()
    private(set) var hasEventAccess = false
    private(set) var hasReminderAccess = false
    // 캘린더 목록이 바뀔 때마다 1씩 올려서, 목록을 보여주는 화면이 새로 그려지게 한다
    private var revision = 0

    init() {
        refreshAccess()
        // 캘린더 목록이 바뀌면 (예: 구글 계정 추가) 설정 창을 새로 고친다
        Task { [weak self] in
            guard let store = self?.store else { return }
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged, object: store) {
                self?.refreshAccess()
                self?.revision += 1
            }
        }
    }

    private func refreshAccess() {
        hasEventAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        hasReminderAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    // 처음 실행할 때 권한 요청 창을 띄운다
    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        _ = try? await store.requestFullAccessToReminders()
        refreshAccess()
    }

    // 쓸 수 있는 캘린더 / 미리알림 목록 (읽기 전용은 제외)
    var eventCalendars: [EKCalendar] {
        _ = revision
        guard hasEventAccess else { return [] }
        return store.calendars(for: .event).filter(\.allowsContentModifications).sorted(by: Self.order)
    }

    var reminderLists: [EKCalendar] {
        _ = revision
        guard hasReminderAccess else { return [] }
        return store.calendars(for: .reminder).filter(\.allowsContentModifications).sorted(by: Self.order)
    }

    private static func order(_ a: EKCalendar, _ b: EKCalendar) -> Bool {
        (a.source.title, a.title) < (b.source.title, b.title)
    }

    // 설정에서 고른 캘린더. 고르지 않았으면 시스템 기본 캘린더
    var selectedEventCalendar: EKCalendar? {
        let id = UserDefaults.standard.string(forKey: SettingsKey.eventCalendarID) ?? ""
        return eventCalendars.first { $0.calendarIdentifier == id } ?? store.defaultCalendarForNewEvents
    }

    var selectedReminderList: EKCalendar? {
        let id = UserDefaults.standard.string(forKey: SettingsKey.reminderListID) ?? ""
        return reminderLists.first { $0.calendarIdentifier == id } ?? store.defaultCalendarForNewReminders()
    }

    var alarmMinutes: Int {
        UserDefaults.standard.object(forKey: SettingsKey.alarmMinutes) as? Int ?? 10
    }

    // 해석된 입력을 캘린더 / 미리알림에 저장한다
    func add(_ input: ParsedInput, kind: EntryKind) throws {
        let title = input.title.isEmpty ? "제목 없음" : input.title

        // 저장하기 전에 필요한 것을 모두 확인한다 (한쪽만 만들어지는 일을 줄이기 위해)
        var eventCalendar: EKCalendar?
        var reminderList: EKCalendar?
        if kind != .reminderOnly {
            guard hasEventAccess else { throw CalendarError.noEventAccess }
            guard let c = selectedEventCalendar else { throw CalendarError.noCalendar }
            eventCalendar = c
        }
        if kind != .eventOnly {
            guard hasReminderAccess else { throw CalendarError.noReminderAccess }
            guard let l = selectedReminderList else { throw CalendarError.noReminderList }
            reminderList = l
        }

        do {
            try saveItems(input, title: title, eventCalendar: eventCalendar, reminderList: reminderList)
        } catch {
            store.reset()
            throw error
        }
    }

    private func saveItems(_ input: ParsedInput, title: String, eventCalendar: EKCalendar?, reminderList: EKCalendar?) throws {
        let calendar = Calendar.current

        if let eventCalendar {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.calendar = eventCalendar
            if let start = input.start {
                event.startDate = start
                event.endDate = input.end ?? start.addingTimeInterval(3600)   // 끝 시간이 없으면 1시간
            } else {
                // 시간이 없으면 하루 종일 일정 (날짜도 없으면 오늘)
                let day = input.day ?? calendar.startOfDay(for: .now)
                event.isAllDay = true
                event.startDate = day
                event.endDate = day
            }
            try store.save(event, span: .thisEvent, commit: false)
        }

        if let reminderList {
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = reminderList
            if let start = input.start {
                reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
                // 일정 시각의 N분 전에 알림
                reminder.addAlarm(EKAlarm(absoluteDate: start.addingTimeInterval(TimeInterval(-alarmMinutes * 60))))
            } else if let day = input.day {
                reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day], from: day)
            }
            try store.save(reminder, commit: false)
        }

        // 일정과 미리알림을 한꺼번에 확정한다 (실패하면 add()에서 둘 다 취소한다)
        try store.commit()
    }
}
