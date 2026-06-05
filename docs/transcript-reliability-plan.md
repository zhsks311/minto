# Transcript reliability improvement plan

## Goal

- Prevent saved meeting transcripts from reading like arbitrary audio chunks.
- Preserve short utterances that are currently invisible or briefly shown and then removed.
- Keep the STT hallucination guards that were added from measured failures.
- Make changes in small, reversible steps with tests before tuning thresholds.

## Current findings

- Saved meetings persist `MeetingRecord.transcript` as JSON. The store does not split text during save.
- Live STT creates `Segment` values from final VAD chunks, then correction batches merge them when accumulated duration reaches 30 seconds.
- The merged segment keeps the first segment timestamp and total duration, so the saved line is a processing batch, not a sentence or paragraph.
- `pendingSegment` can be shown from preview STT and then cleared when final STT starts handling the chunk. If the final result is empty, nothing is committed.
- VAD drops buffers shorter than `minSpeechDuration` and has no public stop-time drain path for the current buffer.
- STT has intentional skip guards for low-energy short phantom text, low `avgLogprob`, and high `compressionRatio`.

## Design principles

- Do not trade missing text for fabricated text. False transcript content is worse than an omitted uncertain fragment.
- Separate processing units from reading units. VAD/STT chunks are useful internally; saved transcript lines should be readable.
- Preserve raw evidence where practical. Any formatted transcript should be reproducible from raw segments.
- Treat threshold tuning as measurement work, not a default fix.
- Keep existing saved meetings readable; do not rewrite old JSON without a separate migration decision.

## Options considered

### Option A: Lower VAD/STT thresholds

- Pros:
  - Can recover some short replies immediately.
  - Small code change if only constants change.
- Cons:
  - Increases noise and phantom transcript risk.
  - Conflicts with prior measurement that justified low-energy short phantom suppression.
  - Does not fix 30-second readable-line splitting.
- Verdict:
  - Not recommended as the first fix. Keep as a measured follow-up only.

### Option B: Normalize transcript only at save/export/display time

- Pros:
  - Directly addresses chunk-looking meeting records.
  - Low risk to realtime STT and correction timing.
  - Can be implemented with deterministic tests.
- Cons:
  - Timestamps become paragraph-start timestamps, less granular than raw chunks.
  - Heuristics may still be imperfect around Korean sentence endings.
- Verdict:
  - Recommended for the transcript readability problem.

### Option C: Add stop-time VAD flush and final transcription drain

- Pros:
  - Directly addresses tail loss and short final utterances.
  - Keeps STT filters intact.
  - Provides deterministic tests around stop behavior.
- Cons:
  - Requires changing stop flow from "cancel now" to "finish and await".
  - Can slightly delay summary window completion when a final chunk is being transcribed.
- Verdict:
  - Recommended as the first correctness fix.

### Option D: Commit preview text if final STT returns empty

- Pros:
  - Directly addresses "appeared then disappeared".
  - Good UX for very short replies.
- Cons:
  - Preview output is explicitly provisional and can be wrong.
  - If committed unconditionally, it weakens final STT quality gates.
- Verdict:
  - Do not commit preview blindly. Add a guarded fallback only after instrumentation shows it is needed.

### Option E: Full transcript data model split

- Pros:
  - Cleanest long-term model: raw chunks, normalized transcript blocks, and UI state can evolve independently.
  - Best foundation for search, export, and future audio timestamp features.
- Cons:
  - Larger persistence/schema change.
  - Needs compatibility handling for existing JSON meetings.
- Verdict:
  - Good long-term direction, but do after Phase 1/2 unless search/export quality requires it immediately.

## Recommended plan

### Phase 1: Stop-time correctness and disappearing-pending fix

#### Step 1. Add a VAD drain API

- Add a public async flush method to `VADProcessor`, for example `flushPending() async -> AudioChunk?`.
- It should run on the existing VAD queue and return a chunk only when the buffered speech satisfies `minSpeechDuration`.
- It must not dispatch through `onChunk` when the caller asks for a returned value; this avoids races during stop.

Verification:

- Add VAD tests:
  - `0.8s speech -> flushPending returns one chunk`.
  - `<0.5s speech -> flushPending returns nil`.
  - `flushPending` clears the buffer and does not double-emit through `onChunk`.

#### Step 2. Replace cancel-on-stop with finish-and-drain

- Add an async stop path in `TranscriptionViewModel`, for example `stopRecordingAndDrain() async`.
- Stop flow should be:
  - stop audio input
  - ask VAD for pending chunk
  - yield that chunk to the final transcription stream
  - finish the stream
  - await the transcription task
  - flush the remaining correction batch
  - cancel only preview work
- Update `AppDelegate.handleStopRecording()` to await this path before final summary/save.

Verification:

- Add tests with a fake audio source or injected VAD/STT seam if available; otherwise add a small test seam first.
- Verify stop does not clear `recordingDuration` before `makeRecord` receives it, or continue relying on segment timestamps with an explicit test.

#### Step 3. Prevent preview from vanishing silently

- Change final chunk handling so `pendingSegment` is cleared only after a non-empty final segment is committed, or after the UI has an explicit "not confirmed" transition.
- Do not automatically save preview text as final transcript in this step.
- Add debug logging or a lightweight state marker for "preview existed but final was empty".

Verification:

- Unit-test state transition:
  - preview text exists
  - final result empty
  - UI state does not jump straight to empty without an observable reason
- Manual check:
  - short reply appears during recording and does not disappear with no feedback.

### Phase 2: Readable saved transcript blocks

#### Step 4. Add a deterministic transcript normalizer

- Add a pure `TranscriptNormalizer` that takes `[Segment]` and returns `[Segment]`.
- Start conservative:
  - merge adjacent segments when the previous text has no terminal punctuation and the combined text is under a paragraph length cap
  - keep separate blocks when there is a large time gap or the current block is already long
  - preserve the first timestamp and sum durations
- Keep the raw text unchanged except whitespace around the join.

Verification:

- Unit tests for known patterns:
  - `"이렇게 XML을"` + `"파일을 추가"` merges.
  - `"변경될 때마다"` + `"직접 수행하지 않고"` merges.
  - already complete sentences remain separate when the paragraph is long enough.
  - large silence gaps can force a new block.

#### Step 5. Use normalized blocks for saved meeting results

- Apply normalization in `AppDelegate.makeRecord` before constructing `MeetingRecord`.
- Use normalized transcript for `MeetingSummaryView`, `MeetingLibraryView`, copy, and export.
- Keep summary generation under review:
  - If normalized transcript is materially more readable, feed final summary from normalized blocks.
  - If summary quality regresses, keep summary generation on raw committed segments and save normalized transcript only for display/export.

Verification:

- Add `AppDelegate.makeRecord` tests:
  - saved transcript count decreases for chunk-fragment input
  - text no longer ends at obvious incomplete fragments
  - timestamps remain monotonic
- Add `MeetingExporter` tests that normalized transcript exports as readable blocks.

### Phase 3: Raw evidence preservation and search quality

#### Step 6. Decide whether to store raw and normalized transcripts separately

- If Phase 2 degrades search precision, extend `MeetingRecord` with optional raw transcript storage.
- Add compatibility-safe decoding for older JSON files.
- Recommended shape:
  - `transcript`: normalized user-facing transcript
  - `rawTranscript`: optional raw STT/correction segments for diagnostics and precise search
  - `schemaVersion`: optional version marker only if custom migration becomes necessary

Verification:

- Existing JSON meeting files still decode.
- New JSON encodes optional raw evidence.
- Search can find text from user-facing transcript and, if present, raw transcript.

### Phase 4: Measured sensitivity tuning

#### Step 7. Build a short-utterance probe set

- Collect or synthesize clips covering:
  - 0.3s / 0.5s / 0.8s Korean replies
  - quiet real speech
  - keyboard noise, breath, chair noise, and background murmur
  - common short replies such as "네", "맞아요", "좋습니다", "잠깐만요"
- Measure both omission and hallucination.

#### Step 8. Tune only if numbers justify it

- Candidate knobs:
  - `minSpeechDuration`
  - low-energy short phantom threshold
  - preview fallback policy
- Acceptance threshold:
  - short true speech recall improves
  - phantom insertions do not increase on non-speech probes
  - meeting corpus CER does not regress meaningfully

## Acceptance criteria

- A saved meeting no longer shows most transcript lines as arbitrary 30-second chunks.
- Obvious incomplete endings like "XML을" or "변경될 때마다" are joined with the following text unless there is a strong boundary reason.
- A short final utterance before stop is not dropped merely because recording ended before VAD naturally flushed.
- A previewed short utterance does not disappear silently when final STT returns empty.
- Existing meetings continue to load.
- No production change commits a preview result as final text without a guard.
- Full standard verification passes:
  - `swift build --build-tests --disable-sandbox`
  - `swift test --disable-sandbox`
- Manual live check covers:
  - short utterance during ongoing recording
  - short utterance immediately before stop
  - long continuous speech
  - quiet room / non-speech noise

## Risks and mitigations

- Risk: stop now waits for final STT and feels slower.
  - Mitigation: show the existing summary loading window immediately, then drain in the background before saving.
- Risk: transcript normalization hides precise chunk boundaries.
  - Mitigation: preserve raw segments later if search or diagnostics need precision.
- Risk: Korean sentence heuristics are imperfect.
  - Mitigation: start with conservative merging and known regression fixtures from the saved DB meeting.
- Risk: lowering thresholds increases false transcripts.
  - Mitigation: defer threshold changes until Phase 4 measurement.
- Risk: persistence schema changes break old JSON.
  - Mitigation: keep Phase 2 schema-neutral; only add optional fields with custom decode if Phase 3 is approved.

## Initial implementation order

1. Implement `VADProcessor.flushPending()` and tests.
2. Convert stop flow to async drain, then save.
3. Stabilize pending/final-empty UI behavior.
4. Add `TranscriptNormalizer` pure tests.
5. Apply normalizer to saved/exported meeting transcript.
6. Run build and full tests.
7. Perform manual live recording checks.
8. Decide whether Phase 3 raw transcript persistence is needed.
