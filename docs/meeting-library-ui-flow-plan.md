# Meeting library UI flow plan

## Goal

- Make the meeting library the primary place to read, copy, and revisit meeting notes.
- Remove the end-of-meeting v1 popup flow.
- Keep the transcription overlay available on demand instead of showing it automatically.

## Changes

1. Render meeting detail with summary and transcript tabs.
   - Summary tab shows the lead summary first.
   - Full structured meeting notes are shown below the lead summary.
   - Transcript tab shows the full transcript.
   - Detail text is selectable, and copy actions are available.
2. Show the active meeting inside the meeting list.
   - The live row shows the title/topic, current status, running summary or latest transcript, and an overlay button.
   - The live detail can copy the running summary or transcript.
3. Change start/stop flow.
   - Start keeps the main meeting window visible.
   - Overlay no longer opens automatically.
   - Stop saves into the meeting list instead of opening the old result popup.
4. Make the app switchable via the normal macOS app switcher.
   - The app uses regular activation policy so the main window can be reached with Command-Tab.

## Verification

- `swift build --build-tests --disable-sandbox`
- `swift test --disable-sandbox`
- Manual UI smoke:
  - start recording and confirm the live row appears in the library
  - open overlay from the live row
  - stop recording and confirm the saved meeting appears in the list
  - verify summary markdown emphasis renders without literal `**`
  - switch away and return to Minto with Command-Tab
