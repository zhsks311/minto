import Foundation

enum GlossarySetSelectionPersistence {
    static let defaultsKey = "meetingGlossarySelectedCategories"

    static func load(
        from defaults: UserDefaults = .standard,
        availableCategories: Set<String>
    ) -> Set<String> {
        let saved = defaults.stringArray(forKey: defaultsKey) ?? []
        let normalized = Set(saved.map(GlossaryStore.displayCategoryName(for:)))
        let available = Set(availableCategories.map(GlossaryStore.displayCategoryName(for:)))
        return normalized.intersection(available)
    }

    static func save(
        _ categories: Set<String>,
        to defaults: UserDefaults = .standard
    ) {
        let values = Set(categories.map(GlossaryStore.displayCategoryName(for:)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        defaults.set(values, forKey: defaultsKey)
    }
}
