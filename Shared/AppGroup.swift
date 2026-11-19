import Foundation

// 앱과 위젯이 함께 쓰는 폴더(앱 그룹). 이름은 Info.plist에 빌드할 때 들어간다.
enum AppGroup {
    static var id: String {
        Bundle.main.object(forInfoDictionaryKey: "OneLineAppGroup") as? String ?? ""
    }

    // 애플 계정 팀 없이 빌드한 앱(다운로드판)은 이름 앞에 팀 ID가 없다.
    // 이때는 위젯이 앱의 일정 파일을 읽을 수 없다.
    static var isAvailable: Bool {
        !id.isEmpty && !id.hasPrefix("local.")
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}
