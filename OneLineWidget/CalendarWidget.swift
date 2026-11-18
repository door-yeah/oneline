import SwiftUI
import WidgetKit

// 바탕화면에 올리는 달력 위젯. 큰 크기는 한 달, 중간 크기는 2주를 보여준다.
struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OneLineCalendar", provider: CalendarProvider()) { entry in
            CalendarWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "oneline://calendar"))
        }
        .configurationDisplayName("한줄 달력")
        .description("맥 캘린더의 일정을 보여줘요. ＋를 누르면 입력창이 열려요.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemMedium:
                WeeksView(today: entry.date, snapshot: snapshot, mode: .twoWeeks)
            default:
                WeeksView(today: entry.date, snapshot: snapshot, mode: .month)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("한줄 입력 앱을 켜면\n일정이 여기에 보여요")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
