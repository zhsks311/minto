import Foundation

enum GlossarySetSelectionPersistence {
    static let defaultsKey = "meetingGlossarySelectedCategories"

    static func availableCategories(from categoryNames: [String]) -> Set<String> {
        Set(categoryNames.map(GlossaryStore.displayCategoryName(for:)))
    }

    static func validSelectedCategories(
        _ selectedCategories: Set<String>,
        availableCategoryNames: [String]
    ) -> Set<String> {
        let selected = Set(selectedCategories.map(GlossaryStore.displayCategoryName(for:)))
        return selected.intersection(availableCategories(from: availableCategoryNames))
    }

    static func hasManualGlossary(_ manualGlossary: String) -> Bool {
        manualGlossary
            .split(whereSeparator: { $0.isNewline })
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func badgeText(
        selectedCategories: Set<String>,
        manualGlossary: String,
        availableCategoryNames: [String]
    ) -> String {
        let selectedCount = validSelectedCategories(
            selectedCategories,
            availableCategoryNames: availableCategoryNames
        ).count
        if selectedCount > 0 { return "분류 \(selectedCount)개 선택" }
        if hasManualGlossary(manualGlossary) { return "직접 입력" }
        return "선택"
    }

    static func load(
        from defaults: UserDefaults = .standard,
        availableCategories: Set<String>
    ) -> Set<String> {
        let saved = defaults.stringArray(forKey: defaultsKey) ?? []
        let normalized = Set(saved.map(GlossaryStore.displayCategoryName(for:)))
        let available = Set(availableCategories.map(GlossaryStore.displayCategoryName(for:)))
        return normalized.intersection(available)
    }

    static func restore(
        from defaults: UserDefaults = .standard,
        availableCategoryNames: [String]
    ) -> Set<String> {
        load(
            from: defaults,
            availableCategories: availableCategories(from: availableCategoryNames)
        )
    }

    static func save(
        _ categories: Set<String>,
        to defaults: UserDefaults = .standard
    ) {
        let values = Set(categories.map(GlossaryStore.displayCategoryName(for:)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        defaults.set(values, forKey: defaultsKey)
    }

    static func saveSelection(
        _ selectedCategories: Set<String>,
        availableCategoryNames: [String],
        to defaults: UserDefaults = .standard
    ) {
        save(
            validSelectedCategories(
                selectedCategories,
                availableCategoryNames: availableCategoryNames
            ),
            to: defaults
        )
    }

    static func prunedSelection(
        _ selectedCategories: Set<String>,
        availableCategoryNames: [String],
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        let valid = validSelectedCategories(
            selectedCategories,
            availableCategoryNames: availableCategoryNames
        )
        guard valid != selectedCategories else { return selectedCategories }
        save(valid, to: defaults)
        return valid
    }
}
