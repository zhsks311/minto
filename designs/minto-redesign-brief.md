# Minto UI/UX redesign brief

## Product context
- macOS menu bar app for meeting recording and Korean STT.
- Core flow: start meeting with topic/glossary/document context -> floating live transcription overlay -> stop recording -> structured summary/report -> saved meeting library.
- Current UI surfaces:
  - Meeting setup sheet: topic, glossary, optional meeting document/agenda.
  - Floating transcription overlay: recording timer, live/pending transcript lines, audio level meter, copy/clear, related-info toggle.
  - Related info panel: on-demand Notion and Confluence search using recent transcript query and detected keywords.
  - Meeting library: sidebar list of saved meetings and detail view.
  - Meeting summary/detail: summary and transcript tabs, markdown export, copy.
  - Settings: Whisper model, LLM correction provider/model, Notion OAuth, Confluence token, current model state.

## Redesign goal
- Design a user-friendly expert-level macOS UI that makes meeting capture, review, search, and export feel obvious.
- Prioritize repeated work: quickly start a meeting, monitor transcription without distraction, find previous meetings, inspect summary/transcript, and export to Markdown for Notion/Confluence.
- The next implementation will strengthen search, so search must be a first-class interaction.

## Search requirements to consider
- Global search across saved meetings, summary text, transcript text, topic, glossary, keywords, related documents, and dates.
- Filter facets: date range, source/context, has document, provider/model, Notion/Confluence related results, export status.
- Search result preview should show matched snippets with timestamps and source badges.
- Detail view should support in-meeting transcript search, jump to timestamp, and highlight matches in summary/transcript.
- Live overlay should keep manual related-info lookup, but make the detected query and source status easier to understand.

## Design deliverable
- Create a multi-screen design system concept for the app:
  - Main meeting library with prominent global search and filter controls.
  - Meeting detail with summary/transcript/search-within tabs or panels.
  - New meeting setup with topic, glossary, document/agenda input, and clear start action.
  - Live transcription overlay with related-info/search panel.
  - Settings/integrations surface focused on provider/model and Notion/Confluence readiness.
- Use a practical desktop productivity aesthetic, not a marketing page.
- Use readable Korean UI copy.
