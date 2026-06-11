import Foundation
import Testing
@testable import MintoCore

@Suite("GlossarySetSelectionPersistence")
struct GlossarySetSelectionPersistenceTests {

    @Test("복원 시 존재하지 않는 분류는 걸러낸다")
    func loadFiltersUnavailableCategories() {
        let defaults = InMemoryUserDefaults()
        defaults.set(
            ["개발", "없는 분류", "기타"],
            forKey: GlossarySetSelectionPersistence.defaultsKey
        )

        let restored = GlossarySetSelectionPersistence.load(
            from: defaults,
            availableCategories: ["개발", "기타"]
        )

        #expect(restored == ["개발", "기타"])
    }

    @Test("저장 시 빈 분류명은 기타로 정규화한다")
    func saveNormalizesEmptyCategory() {
        let defaults = InMemoryUserDefaults()

        GlossarySetSelectionPersistence.save(["개발", "  "], to: defaults)

        #expect(defaults.stringArray(forKey: GlossarySetSelectionPersistence.defaultsKey) == ["개발", "기타"])
    }
}
