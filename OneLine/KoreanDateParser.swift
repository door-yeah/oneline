import Foundation

// 무엇을 만들지: 둘 다 / 캘린더 일정만 / 미리알림만
enum EntryKind: CaseIterable {
    case both, eventOnly, reminderOnly

    var label: String {
        switch self {
        case .both: return "둘 다"
        case .eventOnly: return "일정만"
        case .reminderOnly: return "미리알림만"
        }
    }

    // Tab을 누르면 다음 종류로 넘어간다
    var next: EntryKind {
        switch self {
        case .both: return .eventOnly
        case .eventOnly: return .reminderOnly
        case .reminderOnly: return .both
        }
    }
}

// 한 줄 입력을 해석한 결과
struct ParsedInput {
    var title: String   // 날짜·시간 표현을 뺀 나머지 (예: "치과")
    var day: Date?      // 날짜 (그날 0시). 날짜가 없으면 nil
    var start: Date?    // 시작 시각. 시간이 없으면 nil
    var end: Date?      // 끝 시각. "10시~12시"처럼 범위를 썼을 때만

    var hasTime: Bool { start != nil }

    // 자동 판단 규칙: 시간이 있으면 둘 다, 없으면 미리알림만
    var suggestedKind: EntryKind { hasTime ? .both : .reminderOnly }
}

// "내일 3시 치과" 같은 한국어 문장에서 날짜와 시간을 읽어내는 파서.
// 현재 시각(now)을 밖에서 받아서, 테스트할 때 날짜를 고정할 수 있다.
enum KoreanDateParser {

    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> ParsedInput {
        var rest = text
        let today = calendar.startOfDay(for: now)

        // 1) 시간 읽기 — 범위("10시~12시")를 먼저, 없으면 단일 시간("3시")
        var startTime: ClockTime?
        var endTime: ClockTime?
        if let m = find(timePattern + #"\s*(?:~|-|–|부터)\s*"# + timePattern + #"(?:까지)?에?"#, in: rest),
           let s = clockTime(m.groups, at: 1), var e = clockTime(m.groups, at: 6) {
            // "2시~4시"의 끝 시간이 시작보다 이르면 오후로 본다
            // 끝 시간에 오전/오후를 안 썼으면, 시작 뒤에 오는 가장 가까운 시각으로 본다
            // ("2시~4시" → 14~16시, "밤 11시~1시" → 23시~다음 날 1시)
            if !e.explicit { e.minutes = e.rawMinutes }
            while e.minutes <= s.minutes { e.minutes += e.explicit ? 24 * 60 : 12 * 60 }
            startTime = s
            endTime = e
            cut(&rest, m.range)
        } else if let m = find(timePattern + "에?", in: rest), let s = clockTime(m.groups, at: 1) {
            startTime = s
            cut(&rest, m.range)
        }

        // 2) 날짜 읽기
        var day: Date?
        var dayIsBareWeekday = false
        let particle = #"(?:에|까지)?"#
        let weekdays = "(월|화|수|목|금|토|일)"

        if let m = find(#"(?<!\d)(\d{1,2})월\s*(\d{1,2})일"# + particle, in: rest)
            ?? find(#"(?<![\d/])(\d{1,2})/(\d{1,2})(?![\d/])"# + particle, in: rest),
           let month = Int(m.groups[1] ?? ""), let d = Int(m.groups[2] ?? ""),
           let date = monthDay(month, d, today: today, calendar: calendar) {
            // "11월 20일", "11/20"
            day = date
            cut(&rest, m.range)
        } else if let m = find(#"(이번\s*주|다음\s*주|담주|다다음\s*주)\s*"# + weekdays + #"(?:(?:요일|욜)|(?=\s|$))"# + particle, in: rest),
                  let target = weekdayNumber(m.groups[2]) {
            // "다음주 월", "이번주 금요일" — 월요일을 한 주의 시작으로 본다
            let prefix = (m.groups[1] ?? "").replacing(" ", with: "")
            let weeks = prefix.hasPrefix("다다음") ? 2 : (prefix.hasPrefix("이번") ? 0 : 1)
            let todayOffset = (calendar.component(.weekday, from: today) + 5) % 7
            let targetOffset = (target + 5) % 7
            day = calendar.date(byAdding: .day, value: targetOffset - todayOffset + weeks * 7, to: today)
            cut(&rest, m.range)
        } else if let m = find(weekdays + "(?:요일|욜)" + particle, in: rest),
                  let target = weekdayNumber(m.groups[1]) {
            // "금요일" — 가장 가까운 그 요일 (오늘 포함)
            let delta = (target - calendar.component(.weekday, from: today) + 7) % 7
            day = calendar.date(byAdding: .day, value: delta, to: today)
            dayIsBareWeekday = true
            cut(&rest, m.range)
        } else if let m = find("(오늘|내일|낼|모레|글피)" + particle, in: rest) {
            let offsets = ["오늘": 0, "내일": 1, "낼": 1, "모레": 2, "글피": 3]
            day = calendar.date(byAdding: .day, value: offsets[m.groups[1] ?? ""] ?? 0, to: today)
            cut(&rest, m.range)
        } else if let m = find(#"(?<!\d)(\d{1,3})일\s*(?:뒤|후)"# + particle, in: rest),
                  let n = Int(m.groups[1] ?? "") {
            // "3일 뒤"
            day = calendar.date(byAdding: .day, value: n, to: today)
            cut(&rest, m.range)
        } else if let m = find(#"(?<!\d)(\d{1,2})일(?=\s|$|에|까지)"# + particle, in: rest),
                  let d = Int(m.groups[1] ?? "") {
            // "25일" — 이번 달, 이미 지났으면 다음 달
            var comps = calendar.dateComponents([.year, .month], from: today)
            comps.day = d
            if let date = calendar.date(from: comps), calendar.component(.day, from: date) == d {
                day = date < today ? calendar.date(byAdding: .month, value: 1, to: date) : date
                cut(&rest, m.range)
            }
        }

        // 3) 날짜와 시간을 합치기
        var start: Date?
        var end: Date?
        if let s = startTime {
            var base = day ?? today
            var candidate = calendar.date(byAdding: .minute, value: s.minutes, to: base)
            if let c = candidate, c <= now {
                // 날짜 없이 시간만 썼는데 이미 지난 시각이면 내일로,
                // "금요일 3시"인데 오늘이 금요일이고 3시가 지났으면 다음 주로
                if day == nil {
                    base = calendar.date(byAdding: .day, value: 1, to: base) ?? base
                } else if dayIsBareWeekday {
                    base = calendar.date(byAdding: .day, value: 7, to: base) ?? base
                }
                candidate = calendar.date(byAdding: .minute, value: s.minutes, to: base)
            }
            day = candidate.map { calendar.startOfDay(for: $0) } ?? base
            start = candidate
            if let e = endTime {
                end = calendar.date(byAdding: .minute, value: e.minutes, to: base)
            }
        }

        let title = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return ParsedInput(title: title, day: day, start: start, end: end)
    }

    // MARK: - 시간 해석

    // 자정부터 몇 분이 지났는지로 시각을 표현한다
    private struct ClockTime {
        var minutes: Int
        var rawMinutes: Int  // 오전/오후 보정을 하기 전, 쓴 숫자 그대로의 시각
        var explicit: Bool   // "오후"처럼 오전/오후를 직접 밝혔는지
    }

    // "오후 3시 30분", "3시 반", "15:30" — 캡처 그룹 5개 (오전오후, 시, 분, 반, :분)
    // "3시간"은 시각이 아니므로 제외한다
    private static let timePattern =
        #"(?<!\d)(오전|오후|아침|저녁|밤|낮|새벽)?\s*(\d{1,2})(?:시(?!간)\s*(?:(\d{1,2})분|(반))?|:(\d{2}))"#

    private static func clockTime(_ g: [String?], at i: Int) -> ClockTime? {
        guard g.count > i + 4, let hourText = g[i + 1], var hour = Int(hourText), hour <= 24 else { return nil }
        let minute = g[i + 3] != nil ? 30 : Int(g[i + 2] ?? g[i + 4] ?? "0") ?? 0
        guard minute < 60 else { return nil }

        let meridiem = g[i]
        let explicit = meridiem != nil || hour >= 13
        let rawMinutes = hour * 60 + minute
        switch meridiem {
        case "오후", "저녁":
            if hour < 12 { hour += 12 }
        case "밤":
            if hour == 12 { hour = 24 } else if hour >= 6 && hour < 12 { hour += 12 }
        case "오전", "아침", "새벽":
            if hour == 12 { hour = 0 }
        case "낮":
            if hour <= 6 { hour += 12 }
        default:
            // 오전/오후를 안 썼을 때: 1~7시는 보통 오후를 뜻한다 ("3시 치과" → 15시)
            if hour >= 1 && hour <= 7 { hour += 12 }
        }
        return ClockTime(minutes: hour * 60 + minute, rawMinutes: rawMinutes, explicit: explicit)
    }

    // MARK: - 날짜 해석

    // 일=1, 월=2 … 토=7 (Calendar의 weekday 번호와 같다)
    private static func weekdayNumber(_ s: String?) -> Int? {
        guard let s, let index = ["일", "월", "화", "수", "목", "금", "토"].firstIndex(of: s) else { return nil }
        return index + 1
    }

    // "11월 20일" → 올해 날짜. 이미 지났으면 내년
    private static func monthDay(_ month: Int, _ day: Int, today: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year], from: today)
        comps.month = month
        comps.day = day
        guard let date = calendar.date(from: comps),
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
    }

    // MARK: - 정규식 도우미

    private struct Match {
        let range: NSRange
        let groups: [String?]
    }

    private static func find(_ pattern: String, in s: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let groups: [String?] = (0..<m.numberOfRanges).map {
            let r = m.range(at: $0)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        return Match(range: m.range, groups: groups)
    }

    // 읽어낸 부분을 문장에서 지운다 (제목만 남기기 위해)
    private static func cut(_ s: inout String, _ range: NSRange) {
        s = (s as NSString).replacingCharacters(in: range, with: " ")
    }
}
