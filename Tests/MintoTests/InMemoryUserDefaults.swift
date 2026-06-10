import Foundation

/// 디스크에 쓰지 않는 테스트 전용 UserDefaults.
///
/// suiteName 기반 UserDefaults는 값을 쓰는 순간 ~/Library/Preferences/<suite>.plist를
/// 만들고, removePersistentDomain을 호출해도 cfprefsd가 빈 파일을 남긴다.
/// 테스트마다 UUID suite를 쓰면 이 파일이 무한히 쌓이므로, 저장을 메모리 딕셔너리로
/// 가로채 파일 생성 자체를 막는다. (별도 정리 코드 불필요)
final class InMemoryUserDefaults: UserDefaults {
    private var storage: [String: Any] = [:]

    init() {
        super.init(suiteName: "minto-inmemory-\(UUID().uuidString)")!
    }

    override func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        if let value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    override func set(_ value: Bool, forKey defaultName: String) {
        storage[defaultName] = value
    }

    override func set(_ value: Int, forKey defaultName: String) {
        storage[defaultName] = value
    }

    override func set(_ value: Double, forKey defaultName: String) {
        storage[defaultName] = value
    }

    override func set(_ value: Float, forKey defaultName: String) {
        storage[defaultName] = value
    }

    override func set(_ url: URL?, forKey defaultName: String) {
        if let url {
            storage[defaultName] = url
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    override func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }

    override func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    override func bool(forKey defaultName: String) -> Bool {
        storage[defaultName] as? Bool ?? false
    }

    override func integer(forKey defaultName: String) -> Int {
        storage[defaultName] as? Int ?? 0
    }

    override func double(forKey defaultName: String) -> Double {
        storage[defaultName] as? Double ?? 0
    }

    override func float(forKey defaultName: String) -> Float {
        storage[defaultName] as? Float ?? 0
    }

    override func data(forKey defaultName: String) -> Data? {
        storage[defaultName] as? Data
    }

    override func array(forKey defaultName: String) -> [Any]? {
        storage[defaultName] as? [Any]
    }

    override func stringArray(forKey defaultName: String) -> [String]? {
        storage[defaultName] as? [String]
    }

    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        storage[defaultName] as? [String: Any]
    }

    override func url(forKey defaultName: String) -> URL? {
        storage[defaultName] as? URL
    }

    override func dictionaryRepresentation() -> [String: Any] {
        storage
    }
}
