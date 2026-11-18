import Foundation

// 앱이 캘린더에서 읽어 둔 일정 목록. 위젯은 이 파일만 읽어서 달력을 그린다.
struct CalendarSnapshot: Codable {
    struct Item: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var colorHex: String
    }

    var savedAt: Date
    var items: [Item]

    static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("calendar.json")
    }

    static func load() -> CalendarSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CalendarSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = Self.fileURL else { return }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    // 그날에 걸쳐 있는 일정들. 하루 종일 일정이 먼저, 나머지는 시작 시간 순서
    func items(on day: Date, calendar: Calendar) -> [Item] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return items
            .filter { item in
                if item.start == item.end { return item.start >= dayStart && item.start < dayEnd }
                return item.start < dayEnd && item.end > dayStart
            }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.start < b.start
            }
    }
}
