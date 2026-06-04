# Minto UI/UX redesign v2 plan

## Objective
- Move the first Pencil concept from "good starting point" to a more usable product design.
- Reduce visible complexity for new users.
- Make search state transitions explicit.
- Keep live meeting UX quiet and transcription-first.
- Preserve fast post-meeting search, review, and export.

## Reference principles
- Toss product principles, adapted for Minto:
  - Simplicity: users should not need to learn how the app works before using it.
  - Value First: show the value before asking for setup work.
  - Clear Action: one obvious next action on each screen.
  - Context Based: each flow should match the user's current mode: before, during, or after a meeting.
  - Easy to Answer: split hard setup choices into small, recommended decisions.
  - One Thing: each page should have a single core message.
  - Minimum Features: hide advanced filters and source details until the user needs them.
- UX writing:
  - Use plain Korean labels.
  - Prefer active, positive, short sentences.
  - Avoid technical nouns where user-facing words are enough.

## Core UX decisions

### 1. Main library default state
- Primary question: "What should I review or find next?"
- Primary action: search or start a meeting.
- Visible by default:
  - Global search input.
  - Recent meetings.
  - One selected meeting preview.
  - A small search-readiness indicator.
- Hidden until needed:
  - Advanced filters.
  - Source-specific filters.
  - Full match taxonomy.

### 2. Main library search state
- Triggered when the user types a query.
- Primary question: "Which result answers my query?"
- Primary action: open the best match.
- Show:
  - Query summary.
  - Top result group.
  - Match snippets with timestamp/source badges.
  - Compact filter button and 2-3 recommended chips.
- Do not show:
  - Permanent large filter sidebar.
  - All source states at once.

### 3. Meeting detail state
- Primary question: "What happened in this meeting?"
- Primary action: review summary, then jump to exact transcript evidence.
- Structure:
  - Summary first.
  - Transcript search inside detail.
  - Match tab only when a search is active.
  - Export/copy actions fixed but visually secondary after content.

### 4. Meeting start
- Primary question: "What context helps this meeting?"
- Primary action: start recording.
- Reduce perceived work:
  - Topic stays prominent.
  - Glossary/document become optional expandable blocks.
  - Recommended examples stay short.
  - "Start recording" remains available even if everything is empty.

### 5. Live overlay
- Primary question: "Is recording working, and what is being said?"
- Primary action: monitor transcription.
- Keep default state quiet:
  - Timer, model state, transcript, audio meter only.
  - Related documents collapsed into a small suggestion bar.
  - Expand related documents only when the user chooses it.
- Avoid:
  - Large panel consuming transcript space by default.
  - Requiring the user to understand Notion/Confluence during a meeting.

### 6. Settings/search readiness
- Primary question: "What do I need to connect for search to work?"
- Primary action: fix the next missing setup item.
- Structure:
  - Search readiness card first.
  - Source rows with clear status and action.
  - Model/provider sections below.
  - Hide low-level model details unless expanded.

## V2 deliverables
- Pencil-exported PNGs:
  - Main library default state.
  - Main library search state.
  - Meeting start sheet.
  - Live overlay default + related suggestion.
  - Settings/search readiness.
- Self-review report:
  - One-thing check.
  - New-user complexity check.
  - Search-state clarity check.
  - Meeting-focus check.
  - Implementation fit check against current SwiftUI surfaces.

## Acceptance criteria
- Each screen has one clearly dominant purpose and one primary action.
- Default main screen exposes fewer concepts than v1.
- Search state is visibly different from default state.
- Live overlay gives more space to transcription than related documents.
- Settings tells the user the next setup action without reading every row.
- Korean UI copy is shorter and more conversational than v1.
