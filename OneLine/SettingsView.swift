import EventKit
import SwiftUI

// 설정 창: 어느 캘린더 / 목록에 넣을지, 몇 분 전에 알릴지
struct SettingsView: View {
    let service: CalendarService
    let shortcutLabel: String

    @AppStorage(SettingsKey.eventCalendarID) private var eventCalendarID = ""
    @AppStorage(SettingsKey.reminderListID) private var reminderListID = ""
    @AppStorage(SettingsKey.alarmMinutes) private var alarmMinutes = 10

    var body: some View {
        Form {
            Section("일정을 넣을 캘린더") {
                if !service.hasEventAccess {
                    accessWarning("캘린더")
                } else {
                    Picker("캘린더", selection: $eventCalendarID) {
                        Text("시스템 기본 캘린더").tag("")
                        ForEach(service.eventCalendars, id: \.calendarIdentifier) { calendar in
                            Text("\(calendar.title) — \(calendar.source.title)").tag(calendar.calendarIdentifier)
                        }
                    }
                    Text("구글 캘린더가 안 보이면 시스템 설정 → 인터넷 계정에서 Google 계정을 추가하고 캘린더를 켜 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("미리알림을 넣을 목록") {
                if !service.hasReminderAccess {
                    accessWarning("미리알림")
                } else {
                    Picker("목록", selection: $reminderListID) {
                        Text("시스템 기본 목록").tag("")
                        ForEach(service.reminderLists, id: \.calendarIdentifier) { list in
                            Text("\(list.title) — \(list.source.title)").tag(list.calendarIdentifier)
                        }
                    }
                    Picker("알림 시점", selection: $alarmMinutes) {
                        Text("정각").tag(0)
                        Text("10분 전").tag(10)
                        Text("30분 전").tag(30)
                        Text("1시간 전").tag(60)
                    }
                }
            }

            Section("단축키") {
                LabeledContent("입력창 열기", value: shortcutLabel.isEmpty ? "등록 실패 — 메뉴 막대 아이콘을 눌러 주세요" : shortcutLabel)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func accessWarning(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(name) 접근 권한이 필요해요", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            HStack {
                Button("권한 요청") { Task { await service.requestAccess() } }
                Button("시스템 설정 열기") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
