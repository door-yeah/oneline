import WidgetKit

struct CalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarSnapshot?
}

// 위젯이 언제 무엇을 그릴지 정한다.
// 일정이 바뀌면 앱이 위젯을 새로 그리게 하고, 여기서는 자정마다 '오늘'만 옮긴다.
struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        CalendarEntry(date: .now, snapshot: CalendarSnapshot(savedAt: .now, items: []))
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        completion(CalendarEntry(date: .now, snapshot: CalendarSnapshot.load() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let snapshot = CalendarSnapshot.load()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [CalendarEntry(date: .now, snapshot: snapshot)]
        // 앞으로 7일 동안 자정마다 하나씩 (앱이 꺼져 있어도 날짜는 넘어가게)
        for offset in 1...7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(CalendarEntry(date: day, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
