import SwiftUI
import WidgetKit

// 주 단위 달력. 한 달(큰 위젯) 또는 이번 주부터 2주(중간 위젯)를 그린다.
struct WeeksView: View {
    enum Mode { case month, twoWeeks }

    let today: Date
    let snapshot: CalendarSnapshot
    let mode: Mode

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, mode == .month ? 6 : 4)
            weekdayRow
                .padding(.bottom, 3)
            ForEach(weeks, id: \.self) { week in
                Divider().opacity(0.5)
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        DayCell(
                            day: day,
                            isToday: calendar.isDate(day, inSameDayAs: today),
                            isOtherMonth: mode == .month && !calendar.isDate(day, equalTo: today, toGranularity: .month),
                            items: snapshot.items(on: day, calendar: calendar)
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(today, format: .dateTime.month(.wide))
                .font(.system(size: 17, weight: .bold))
            if mode == .twoWeeks {
                Text("이번 주 · 다음 주")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Link(destination: URL(string: "oneline://new")!) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("새 일정 입력")
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // 달력 설정의 '한 주의 시작 요일'을 따른다
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weeks: [[Date]] {
        let start: Date
        let weekCount: Int
        switch mode {
        case .month:
            let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
            start = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
            let monthEnd = calendar.dateInterval(of: .month, for: today)?.end ?? today
            let days = calendar.dateComponents([.day], from: start, to: monthEnd).day ?? 35
            weekCount = Int((Double(days) / 7).rounded(.up))
        case .twoWeeks:
            start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            weekCount = 2
        }
        return (0..<weekCount).map { week in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: week * 7 + $0, to: start) }
        }
    }
}
