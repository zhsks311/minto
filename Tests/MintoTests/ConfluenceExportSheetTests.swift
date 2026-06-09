import Testing
@testable import MintoCore

@Suite("Confluence export sheet")
struct ConfluenceExportSheetTests {
    @Test("재연결 필요 상태에서 Settings handoff를 표시한다")
    func reconnectStateShowsSettingsHandoff() {
        #expect(ConfluenceExportSheetPresentation.showsSettingsHandoff(for: .needsReconnect))
        #expect(!ConfluenceExportSheetPresentation.showsSettingsHandoff(for: .connected))
        #expect(!ConfluenceExportSheetPresentation.showsSettingsHandoff(for: .disconnected))
        #expect(ConfluenceExportSheetPresentation.settingsHandoffButtonTitle == "Confluence 설정 열기")
    }
}
