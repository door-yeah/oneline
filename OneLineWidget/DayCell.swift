import SwiftUI
import WidgetKit

// 달력 한 칸: 날짜 숫자와 그날 일정 이름들. 자리가 모자라면 '+2'처럼 줄여 쓴다.
struct DayCell: View {
    let day: Date
    let isToday: Bool
    let isOtherMonth: Bool
    let items: [CalendarSnapshot.Item]

    private let lineHeight: CGFloat = 13
    private let numberHeight: CGFloat = 17

    var body: some View {
        GeometryReader { proxy in
            let room = max(0, Int((proxy.size.height - numberHeight - 3) / lineHeight))
            // 다 못 넣으면 마지막 줄은 '+n'에 쓴다
            let shown = items.count > room ? max(0, room - 1) : items.count

            VStack(spacing: 1) {
                number
                ForEach(items.prefix(shown)) { item in
                    EventLabel(item: item)
                }
                if items.count > shown {
                    Text("+\(items.count - shown)")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 3)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .opacity(isOtherMonth ? 0.4 : 1)
        .accessibilityElement(children: .combine)
    }

    private var number: some View {
        // '18일'이 아니라 숫자만 쓴다
        Text(String(Calendar.current.component(.day, from: day)))
            .font(.system(size: 11, weight: isToday ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(isToday ? Color.white : Color.primary)
            .frame(width: numberHeight, height: numberHeight)
            .background {
                if isToday {
                    Circle().fill(Color.accentColor).widgetAccentable()
                }
            }
    }
}

// 일정 하나. 하루 종일 일정은 색을 칠한 띠, 시간 일정은 왼쪽 색 막대만
struct EventLabel: View {
    let item: CalendarSnapshot.Item

    var body: some View {
        let color = Color(hex: item.colorHex)
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 2)
                .widgetAccentable()
            Text(item.title)
                .font(.system(size: 8.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: 11)
        .padding(.horizontal, 1)
        .background {
            if item.isAllDay {
                RoundedRectangle(cornerRadius: 2.5).fill(color.opacity(0.22))
            }
        }
    }
}

extension Color {
    // "RRGGBB" 글자를 색으로 바꾼다
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0x8E8E93
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
