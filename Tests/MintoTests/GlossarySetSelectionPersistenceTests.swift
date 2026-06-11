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

        let saved = defaults.stringArray(forKey: GlossarySetSelectionPersistence.defaultsKey) ?? []
        #expect(Set(saved) == Set(["개발", "기타"]))
        #expect(saved.count == 2)
    }

    @Test("선택 저장은 현재 가능한 분류만 영속한다")
    func saveSelectionFiltersUnavailableCategories() {
        let defaults = InMemoryUserDefaults()

        GlossarySetSelectionPersistence.saveSelection(
            ["개발", "없는 분류", "  "],
            availableCategoryNames: ["개발", "기타"],
            to: defaults
        )

        let saved = defaults.stringArray(forKey: GlossarySetSelectionPersistence.defaultsKey) ?? []
        #expect(Set(saved) == Set(["개발", "기타"]))
        #expect(saved.count == 2)
    }

    @Test("배지는 유효 선택과 직접 입력 상태를 공유 규칙으로 계산한다")
    func badgeTextUsesValidSelectionAndManualGlossary() {
        #expect(GlossarySetSelectionPersistence.badgeText(
            selectedCategories: ["없는 분류"],
            manualGlossary: "",
            availableCategoryNames: ["개발"]
        ) == "선택")
        #expect(GlossarySetSelectionPersistence.badgeText(
            selectedCategories: [],
            manualGlossary: "\n  Liquibase",
            availableCategoryNames: ["개발"]
        ) == "직접 입력")
        #expect(GlossarySetSelectionPersistence.badgeText(
            selectedCategories: ["개발", "없는 분류"],
            manualGlossary: "Liquibase",
            availableCategoryNames: ["개발"]
        ) == "분류 1개 선택")
    }
}
