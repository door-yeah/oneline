import Foundation

// 앱과 위젯이 함께 쓰는 폴더(앱 그룹). 이름은 Info.plist에 빌드할 때 들어간다.
enum AppGroup {
    static var id: String {
        Bundle.main.object(forInfoDictionaryKey: "OneLineAppGroup") as? String ?? ""
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}
