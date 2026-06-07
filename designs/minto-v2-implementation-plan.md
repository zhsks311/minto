# Minto v2 design implementation plan

## Goal
- Apply the v2 Pencil design direction to the actual SwiftUI app.
- Keep the change scoped to UI/UX surfaces.
- Do not change STT, persistence, summary generation, or external integration behavior.

## Scope
- `MeetingLibraryView`
  - Make global search the primary control.
  - Split default and active-search states.
  - Show recent meetings and a selected preview by default.
  - Search across title, topic, summary markdown, and transcript text.
- `MeetingSetupView`
  - Keep topic prominent.
  - Move glossary and document inputs behind optional expandable rows.
  - Keep start available even when all fields are empty.
- `TranscriptionOverlayView`
  - Keep transcript as the dominant live surface.
  - Keep the whole overlay collapsible.
  - Show related documents as a compact suggestion row unless the user expands it.
- `SettingsView`
  - Move search readiness and source connection status above model/provider settings.
  - Keep low-level model/provider controls available but visually secondary.

## Verification
- Build: `swift build --build-tests --disable-sandbox`
- Tests: `swift test --disable-sandbox`
- Manual review target:
  - Main screen default state does not expose permanent filters.
  - Typing in search visibly changes the screen.
  - Meeting start sheet can start with topic only or empty context.
  - Expanded overlay gives more room to transcript than related documents.
  - Collapsed overlay hides transcript text.
  - Settings first tells the user whether search sources are ready.

## Post-implementation QA
- Do not commit immediately after code changes. Run QA first.
- QA order: build/tests → launch app → manual core-flow check → visual/UX check → fix issues → re-run relevant checks → commit.
- Core-flow checks:
  - Meeting start remains simple and can start with empty context.
  - Active meeting appears in the library and exposes stop/overlay actions.
  - Past meetings remain selectable while recording is active.
  - Overlay quiet/collapsed states do not expose related-document search.
  - Related-document search lives in the meeting library detail.
  - Settings uses disclosure rows for Notion/Confluence and an on/off correction toggle.
- Record each QA item as pass, needs fix, or deferred.
- Run at most three fix/verify loops for the same issue before reporting the remaining risk.
