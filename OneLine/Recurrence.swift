import Foundation

// 반복 규칙. 예: "매주 월수금", "격주 화", "매달 25일", "12월까지", "10번"
struct Recurrence: Equatable {
    enum Frequency { case daily, weekly, monthly, yearly }

    var frequency: Frequency
    var interval = 1           // 2면 격주, 격월처럼 한 번씩 건너뛴다
    var weekdays: [Int] = []   // 매주 반복할 요일. 1=일, 2=월 … 7=토 (월요일부터 정렬)
    var until: Date?           // 이 날까지 반복
    var count: Int?            // 이 횟수만큼 반복

    // 미리보기에 보여줄 짧은 설명. 예: "매주 월·수·금", "매달 25일"
    func summary(firstDay: Date?, calendar: Calendar = .current) -> String {
        switch frequency {
        case .daily:
            return interval == 1 ? "매일" : "\(interval)일마다"
        case .weekly:
            let prefix = interval == 1 ? "매주" : (interval == 2 ? "격주" : "\(interval)주마다")
            let set = Set(weekdays)
            if set == [2, 3, 4, 5, 6] { return "\(prefix) 평일" }
            if set == [1, 7] { return "\(prefix) 주말" }
            let names = ["일", "월", "화", "수", "목", "금", "토"]
            let days = (weekdays.isEmpty ? firstDay.map { [calendar.component(.weekday, from: $0)] } ?? [] : weekdays)
                .map { names[$0 - 1] }
                .joined(separator: "·")
            return days.isEmpty ? prefix : "\(prefix) \(days)"
        case .monthly:
            let prefix = interval == 1 ? "매달" : "\(interval)개월마다"
            guard let firstDay else { return prefix }
            return "\(prefix) \(calendar.component(.day, from: firstDay))일"
        case .yearly:
            let prefix = interval == 1 ? "매년" : "\(interval)년마다"
            guard let firstDay else { return prefix }
            return "\(prefix) \(calendar.component(.month, from: firstDay))월 \(calendar.component(.day, from: firstDay))일"
        }
    }
}
