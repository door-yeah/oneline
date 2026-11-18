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
    var endDay: Date? = nil            // 여러 날 일정의 마지막 날 ("20일~22일", "2박 3일")
    var recurrence: Recurrence? = nil  // 반복 규칙 ("매주 월수금")

    var hasTime: Bool { start != nil }
    var isPeriod: Bool { endDay != nil }

    // 자동 판단 규칙: 시간이 있으면 둘 다, 여러 날 기간이면 일정만, 나머지는 미리알림만
    var suggestedKind: EntryKind {
        if hasTime { return .both }
        if isPeriod { return .eventOnly }
        return .reminderOnly
    }
}

// "내일 3시 치과" 같은 한국어 문장에서 날짜와 시간을 읽어내는 파서.
// 현재 시각(now)을 밖에서 받아서, 테스트할 때 날짜를 고정할 수 있다.
enum KoreanDateParser {

    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> ParsedInput {
        var rest = text
        let today = calendar.startOfDay(for: now)

        // 1) 반복 읽기 ("매주 월수금", "매달", "12월까지", "10번")
        var recurrence = parseRecurrence(&rest, today: today, calendar: calendar)

        // 2) 시간 읽기 — 범위("10시~12시")를 먼저, 없으면 단일 시간("3시")
        var startTime: ClockTime?
        var endTime: ClockTime?
        if let m = find(timePattern + #"\s*(?:~|-|–|부터)\s*"# + timePattern + #"(?:까지)?에?"#, in: rest),
           let s = clockTime(m.groups, at: 1), var e = clockTime(m.groups, at: 6) {
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

        // 3) 여러 날 기간 읽기 ("11월 20일~22일", "12/24~12/26", "금~일")
        var day: Date?
        var endDay: Date?
        if let period = parsePeriod(&rest, today: today, calendar: calendar) {
            day = period.first
            endDay = period.last
        }

        // 4) 기간 길이 읽기 ("2박 3일", "5일간") — 날짜는 아래에서 따로 읽는다
        var periodLength: Int?
        if endDay == nil {
            if let m = find(#"(?<!\d)(\d{1,2})\s*박\s*(\d{1,2})\s*일"#, in: rest), let n = Int(m.groups[2] ?? "") {
                periodLength = n
                cut(&rest, m.range)
            } else if let m = find(#"(?<!\d)(\d{1,3})\s*일\s*(?:간|동안)"#, in: rest), let n = Int(m.groups[1] ?? "") {
                periodLength = n
                cut(&rest, m.range)
            }
        }

        // 5) 날짜 읽기
        var dayIsBareWeekday = false
        let particle = Self.particle
        let weekdays = "(월|화|수|목|금|토|일)"

        if day != nil {
            // 기간에서 이미 날짜를 읽었다
        } else if let m = find(#"(?<!\d)(\d{1,2})월\s*(\d{1,2})일"# + particle, in: rest)
            ?? find(#"(?<![\d/])(\d{1,2})/(\d{1,2})(?![\d/])"# + particle, in: rest),
           let month = Int(m.groups[1] ?? ""), let d = Int(m.groups[2] ?? ""),
           let date = monthDay(month, d, today: today, calendar: calendar) {
            // "11월 20일", "11/20"
            day = date
            cut(&rest, m.range)
        } else if let m = find(#"(이번\s*주|다음\s*주|담주|다다음\s*주)\s*"# + weekdays + #"(?:(?:요일|욜)|(?=\s|$))"# + particle, in: rest),
                  let target = weekdayNumber(m.groups[2]) {
            // "다음주 월", "이번주 금요일" — 월요일을 한 주의 시작으로 본다
            day = weekdayInWeek(target, prefix: m.groups[1], today: today, calendar: calendar)
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
        } else if let m = find(#"(?<!\d)(\d{1,2})일(?=\s|$|에|까지|부터)"# + particle, in: rest),
                  let d = Int(m.groups[1] ?? ""),
                  let date = dayOfMonth(d, today: today, calendar: calendar) {
            // "25일" — 이번 달, 이미 지났으면 다음 달
            day = date
            cut(&rest, m.range)
        }

        // 6) 매주 반복할 요일이 있고 날짜를 안 썼으면, 가장 가까운 그 요일부터 시작한다
        if day == nil, let r = recurrence, r.frequency == .weekly, !r.weekdays.isEmpty {
            for offset in 0..<14 {
                guard let d = calendar.date(byAdding: .day, value: offset, to: today),
                      r.weekdays.contains(calendar.component(.weekday, from: d)) else { continue }
                // 오늘이 그 요일이어도 시간이 이미 지났으면 다음 번으로
                if offset == 0, let s = startTime,
                   let t = calendar.date(byAdding: .minute, value: s.minutes, to: d), t <= now { continue }
                day = d
                break
            }
        }

        // 7) 날짜와 시간을 합치기
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

        // 8) 반복이나 기간인데 날짜가 없으면 오늘부터
        if day == nil, recurrence != nil || periodLength != nil {
            day = today
        }
        if let n = periodLength, n > 1, let first = day {
            endDay = calendar.date(byAdding: .day, value: n - 1, to: first)
        }

        // 9) 반복 + 기간이면, 기간의 끝을 반복이 끝나는 날로 본다
        //    ("12월 1일~31일 매일 운동" → 12월 1일부터 31일까지 매일)
        if var r = recurrence, let last = endDay {
            if r.until == nil { r.until = endOfDay(last, calendar: calendar) }
            recurrence = r
            endDay = nil
        }
        if let first = day, let last = endDay, last <= first {
            endDay = nil
        }

        var words = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let leftovers: Set = ["까지", "까지만", "까지는", "부터", "에", "에는", "에서"]
        while let first = words.first, leftovers.contains(first) { words.removeFirst() }
        while let last = words.last, leftovers.contains(last) { words.removeLast() }
        let title = words.joined(separator: " ")
        return ParsedInput(title: title, day: day, start: start, end: end, endDay: endDay, recurrence: recurrence)
    }

    // 날짜 뒤에 붙는 말: "까지", "까지만", "부터", "에", "에는" (띄어 써도 된다)
    // 바로 뒤에 다른 글자가 붙으면 조사가 아니다 ("내일 에어컨 청소"의 "에"는 그대로 둔다)
    private static let particle = #"(?:\s*(?:까지(?:만|는)?|부터|에(?:는|서)?)(?=\s|$))?"#
    private static let untilWord = #"\s*까지(?:만|는)?(?=\s|$)"#

    // MARK: - 반복 해석

    // 요일 묶음: "월", "월요일", "월수금", "월, 수, 금", "화·목"
    // 뒤에 다른 글자가 바로 붙으면 요일이 아니다 ("일정"의 "일"은 일요일이 아님)
    private static let dayBlock =
        #"((?:[월화수목금토일]{1,7}(?:요일|욜)?(?=[\s,·/]|$|에|마다)[\s,·/]*)+)"#

    private static func parseRecurrence(_ rest: inout String, today: Date, calendar: Calendar) -> Recurrence? {
        var recurrence: Recurrence?

        if let m = find(#"매\s*평일|평일\s*마다"#, in: rest) {
            recurrence = Recurrence(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])
            cut(&rest, m.range)
        } else if let m = find(#"매\s*주말|주말\s*마다"#, in: rest) {
            recurrence = Recurrence(frequency: .weekly, weekdays: [7, 1])
            cut(&rest, m.range)
        } else if let m = find(#"(매\s*주|격\s*주|(\d{1,2})\s*주\s*마다)\s*"# + dayBlock + #"?(?:마다)?"#, in: rest) {
            // "매주 월수금", "격주 화요일", "2주마다 토"
            let prefix = m.groups[1] ?? ""
            let interval = prefix.hasPrefix("격") ? 2 : Int(m.groups[2] ?? "") ?? 1
            recurrence = Recurrence(frequency: .weekly, interval: interval, weekdays: weekdayList(m.groups[3]))
            cut(&rest, m.range)
        } else if let m = find(#"(?<!\d)(\d{1,3})\s*일\s*마다"#, in: rest) {
            // "3일마다" (요일보다 먼저 봐야 "일요일마다"로 잘못 읽지 않는다)
            recurrence = Recurrence(frequency: .daily, interval: max(1, Int(m.groups[1] ?? "") ?? 1))
            cut(&rest, m.range)
        } else if let m = find(#"(?<![\d가-힣])([월화수목금토일]{1,7})(?:요일|욜)?\s*마다"#, in: rest) {
            // "월요일마다", "화목마다"
            recurrence = Recurrence(frequency: .weekly, weekdays: weekdayList(m.groups[1]))
            cut(&rest, m.range)
        } else if let m = find(#"매일|날마다"#, in: rest) {
            recurrence = Recurrence(frequency: .daily)
            cut(&rest, m.range)
        } else if let m = find(#"(?<!\d)(\d{1,2})\s*(?:개월|달)\s*마다"#, in: rest) {
            recurrence = Recurrence(frequency: .monthly, interval: max(1, Int(m.groups[1] ?? "") ?? 1))
            cut(&rest, m.range)
        } else if let m = find(#"매\s*달|매\s*월(?![화수목금토일요])|다달이|격\s*월"#, in: rest) {
            let interval = m.groups[0]?.hasPrefix("격") == true ? 2 : 1
            recurrence = Recurrence(frequency: .monthly, interval: interval)
            cut(&rest, m.range)
        } else if let m = find(#"매\s*년|매\s*해|해마다"#, in: rest) {
            recurrence = Recurrence(frequency: .yearly)
            cut(&rest, m.range)
        }

        guard var r = recurrence else { return nil }

        // 언제까지 반복할지
        if let m = find(#"(?<!\d)(\d{1,2})월\s*(\d{1,2})일"# + untilWord, in: rest)
            ?? find(#"(?<![\d/])(\d{1,2})/(\d{1,2})"# + untilWord, in: rest),
           let month = Int(m.groups[1] ?? ""), let d = Int(m.groups[2] ?? ""),
           let date = monthDay(month, d, today: today, calendar: calendar) {
            r.until = endOfDay(date, calendar: calendar)
            cut(&rest, m.range)
        } else if let m = find(#"(?<!\d)(\d{1,2})월\s*(?:말\s*)?"# + untilWord, in: rest),
                  let month = Int(m.groups[1] ?? ""),
                  let first = monthDay(month, 1, today: calendar.date(byAdding: .month, value: -1, to: today) ?? today, calendar: calendar),
                  let last = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first) {
            // "12월까지" → 12월 마지막 날
            r.until = endOfDay(last, calendar: calendar)
            cut(&rest, m.range)
        } else if let m = find(#"(?:올해|연말|올\s*연말)"# + untilWord, in: rest),
                  let last = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 12, day: 31)) {
            r.until = endOfDay(last, calendar: calendar)
            cut(&rest, m.range)
        }

        // 몇 번 반복할지 ("10번", "5회")
        if r.until == nil, let m = find(#"(?<!\d)(\d{1,3})\s*(?:번|회)(?:\s*만)?(?=\s|$)"#, in: rest),
           let n = Int(m.groups[1] ?? ""), n > 0 {
            r.count = n
            cut(&rest, m.range)
        }
        return r
    }

    // "월수금" → [2, 4, 6] (월요일부터 정렬)
    private static func weekdayList(_ text: String?) -> [Int] {
        guard let text else { return [] }
        let cleaned = text.replacing("요일", with: "").replacing("욜", with: "")
        var result: [Int] = []
        for ch in cleaned {
            if let n = weekdayNumber(String(ch)), !result.contains(n) { result.append(n) }
        }
        return result.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
    }

    // MARK: - 기간 해석

    private static func parsePeriod(_ rest: inout String, today: Date, calendar: Calendar) -> (first: Date, last: Date)? {
        let to = #"\s*(?:~|-|–|부터)\s*"#
        let notLength = #"(?!\s*(?:간|동안|뒤|후|마다))"#

        // "11월 20일~22일", "20일~22일", "11월 30일부터 12월 2일까지"
        if let m = find(#"(?<!\d)(?:(\d{1,2})월\s*)?(\d{1,2})일"# + to + #"(?:(\d{1,2})월\s*)?(\d{1,2})일"# + notLength + #"(?:\s*까지(?:만|는)?)?"#, in: rest),
           let d1 = Int(m.groups[2] ?? ""), let d2 = Int(m.groups[4] ?? "") {
            let first: Date? = if let mo = Int(m.groups[1] ?? "") {
                monthDay(mo, d1, today: today, calendar: calendar)
            } else {
                dayOfMonth(d1, today: today, calendar: calendar)
            }
            if let first, let last = periodEnd(first: first, month: Int(m.groups[3] ?? ""), day: d2, calendar: calendar) {
                cut(&rest, m.range)
                return (first, last)
            }
        }

        // "12/24~12/26", "12/24~26"
        if let m = find(#"(?<![\d/])(\d{1,2})/(\d{1,2})\s*(?:~|-|–)\s*(?:(\d{1,2})/)?(\d{1,2})(?![\d/])(?:\s*까지(?:만|는)?)?"#, in: rest),
           let mo = Int(m.groups[1] ?? ""), let d1 = Int(m.groups[2] ?? ""), let d2 = Int(m.groups[4] ?? ""),
           let first = monthDay(mo, d1, today: today, calendar: calendar),
           let last = periodEnd(first: first, month: Int(m.groups[3] ?? ""), day: d2, calendar: calendar) {
            cut(&rest, m.range)
            return (first, last)
        }

        // "금~일", "다음주 월~수"
        if let m = find(#"(?:(이번\s*주|다음\s*주|담주|다다음\s*주)\s*)?(?<![가-힣])([월화수목금토일])(?:요일|욜)?"# + to + #"([월화수목금토일])(?:요일|욜)?(?:\s*까지(?:만|는)?)?(?=\s|$)"#, in: rest),
           let w1 = weekdayNumber(m.groups[2]), let w2 = weekdayNumber(m.groups[3]) {
            let first: Date?
            if m.groups[1] != nil {
                first = weekdayInWeek(w1, prefix: m.groups[1], today: today, calendar: calendar)
            } else {
                first = calendar.date(byAdding: .day, value: (w1 - calendar.component(.weekday, from: today) + 7) % 7, to: today)
            }
            let length = (w2 - w1 + 7) % 7
            if let first, length > 0, let last = calendar.date(byAdding: .day, value: length, to: first) {
                cut(&rest, m.range)
                return (first, last)
            }
        }
        return nil
    }

    // 기간의 끝 날짜. 달을 안 썼으면 시작과 같은 달 (끝이 더 이르면 다음 달)
    private static func periodEnd(first: Date, month: Int?, day: Int, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: first)
        if let month { comps.month = month }
        comps.day = day
        guard var last = calendar.date(from: comps), calendar.component(.day, from: last) == day else { return nil }
        while last < first {
            guard let next = calendar.date(byAdding: month == nil ? .month : .year, value: 1, to: last) else { return nil }
            last = next
        }
        return last
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

    // "다음주 월" — 월요일을 한 주의 시작으로 본다
    private static func weekdayInWeek(_ target: Int, prefix: String?, today: Date, calendar: Calendar) -> Date? {
        let p = (prefix ?? "").replacing(" ", with: "")
        let weeks = p.hasPrefix("다다음") ? 2 : (p.hasPrefix("이번") ? 0 : 1)
        let todayOffset = (calendar.component(.weekday, from: today) + 5) % 7
        let targetOffset = (target + 5) % 7
        return calendar.date(byAdding: .day, value: targetOffset - todayOffset + weeks * 7, to: today)
    }

    // "25일" → 이번 달 25일. 이미 지났으면 다음 달
    private static func dayOfMonth(_ day: Int, today: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: today)
        comps.day = day
        guard let date = calendar.date(from: comps), calendar.component(.day, from: date) == day else { return nil }
        return date < today ? calendar.date(byAdding: .month, value: 1, to: date) : date
    }

    // 그날의 마지막 순간 (반복이 끝나는 날을 포함하기 위해)
    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
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
