import AppKit

/// 번들에 포함된 앱 이미지 리소스 접근점.
/// 리소스는 MintoCore 타겟(`Sources/Minto/Resources`)에 있어 `Bundle.module`로 로드한다 —
/// 메뉴바(MintoApp 타겟)와 Dock(AppDelegate, MintoCore 타겟) 양쪽에서 같은 경로로 쓰기 위함이다.
public enum AppAssets {
    /// 메뉴바용 단색 템플릿 아이콘. `isTemplate`이라 OS가 라이트/다크 메뉴바에 맞춰 흑/백으로 틴트한다.
    /// 로드 실패 시 nil → 호출부에서 SF Symbol로 fail-soft 한다.
    public static let menuBarIcon: NSImage? = {
        guard let image = bundleImage(named: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    /// Dock·Finder용 컬러 앱 아이콘(풀컬러, 라운딩 포함).
    public static let appIcon: NSImage? = bundleImage(named: "AppIcon")

    private static func bundleImage(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
