# Minto UI/UX redesign v2 self-review

## Review basis
- Plan: `designs/minto-redesign-v2-plan.md`
- Exports:
  - `designs/minto-redesign-v2-export/DvoBR.png`
  - `designs/minto-redesign-v2-export/Eld39.png`
  - `designs/minto-redesign-v2-export/Dkbi5.png`
  - `designs/minto-redesign-v2-export/FfpXZ.png`
  - `designs/minto-redesign-v2-export/d1x2w.png`
- Pencil layout check: `No layout problems.`
- External references:
  - Toss Product Principles: https://toss.im/tossfeed/article/tossproductprinciples
  - Toss UX writing guide: https://developers-apps-in-toss.toss.im/design/ux-writing.html
  - Toss Design System overview: https://developers-apps-in-toss.toss.im/design/components.html

## Principle audit

### One Thing
- Pass.
- Default library screen now focuses on recent meetings and one selected preview.
- Search results screen is separate and focuses on answering the active query.
- Live overlay focuses on transcription, with related documents collapsed.

### Minimum Features
- Pass with one caveat.
- The permanent filter sidebar from v1 is removed.
- Search filters are reduced to one filter button and three suggested chips.
- Meeting start hides glossary/document inputs behind optional rows.
- Caveat: settings still has several sections on one screen, but the search readiness card makes the next action clear.

### Clear Action
- Pass.
- Default library: `새 회의`, `요약 보기`, `전사 검색`.
- Search state: `이 회의 열기`.
- Meeting start: `녹음 시작`.
- Live overlay: `보기` for related documents.
- Settings: `Confluence 연결하기`.

### Context Based
- Pass.
- Before meeting: minimal setup.
- During meeting: large transcript, small status controls.
- After meeting: search/review/export.
- Troubleshooting: settings starts from search readiness.

### Easy to Answer
- Improved.
- User no longer needs to decide every search source or filter up front.
- Meeting start asks for topic first and treats other inputs as optional.
- Search result detail explains why the result is first.

### UX writing
- Improved.
- Copy is shorter and more conversational than v1.
- Most labels use active/positive Korean.
- One term to revisit during implementation: `provider` remains in settings copy elsewhere in the app; v2 avoids it in primary UI.

## Screen audit

### Main library default
- Stronger than v1.
- The left column is scannable and less crowded.
- Search readiness is visible but small.
- Detail panel gives enough value without forcing the user into tabs.

### Search state
- Stronger than v1.
- Query state is visually distinct from default.
- Results and evidence are separated clearly.
- The "why this result" explanation supports trust.

### Meeting start
- Stronger than v1.
- The user can start with one field.
- Optional inputs are discoverable without dominating the screen.
- The screen has more whitespace than strictly necessary, but that supports the low-pressure setup goal.

### Live overlay
- Stronger than v1.
- Related documents no longer compete with transcription.
- Transcript takes the dominant space.
- The collapsed related-document row keeps the feature discoverable.

### Settings
- Stronger than v1.
- The next setup action is obvious.
- Search sources are easier to understand than provider/model details.
- Model/provider settings are still available but visually lower priority.

## Implementation fit
- `MeetingLibraryView` should split default and search states instead of always showing filters.
- `MeetingSetupView` should make glossary/document expandable.
- `TranscriptionOverlayView` should default related info to collapsed suggestion, not a full panel.
- `SettingsView` should move search source readiness above detailed model/provider controls.
- Current SwiftUI components can support this without changing STT or persistence logic.

## Remaining risks
- Real search ranking is not designed here; the UI assumes a "best match" explanation can be produced.
- Keyboard navigation and VoiceOver states need implementation review.
- The existing `.pen` CLI save behavior produced a 0-byte file in this environment; PNG exports are the reliable design artifacts for now.
