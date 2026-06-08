# STT Engine Refactor Plan

## Goal

- Keep the current `STTService` public API stable.
- Move WhisperKit, SpeechAnalyzer, and SFSpeech implementation details behind engine implementations.
- Preserve the current WhisperKit default path before adding new engines such as Nemotron, sherpa, FluidAudio, or true streaming engines.

## Scope

- `STTService` remains the facade used by `TranscriptionViewModel` and tests.
- New engine implementations handle their own load and transcribe behavior.
- `STT_ENGINE` benchmark work remains compatible with the refactor.
- No default engine change in this step.

## Steps

1. Add `SpeechTranscriptionEngine`.
   - Verify: existing call sites still compile through `STTService`.

2. Extract shared audio helpers.
   - Verify: WhisperKit, SpeechAnalyzer, and SFSpeech produce the same `TranscriptionResult` shape.

3. Extract engine implementations.
   - `WhisperKitSTTEngine`
   - `SpeechAnalyzerSTTEngine`
   - `SFSpeechOnDeviceSTTEngine`
   - Verify: `STTService.transcribe` delegates to the loaded engine.

4. Keep `STTService` as facade.
   - Preserve `loadEngine`, `loadModel`, `recoverModelCacheAndReload`, `modelState`, `modelVariant`, `speechEngineID`, and `supportsPreviewTranscription`.
   - Verify: existing app/view model code is unchanged.

5. Validate.
   - Run `swift test --disable-sandbox`.
   - Run a 1-window `whisper_accurate` smoke with `WHISPER_MODEL_FOLDER`.
   - Compare the smoke path against the previously recorded baseline command.

6. Add true streaming scaffold after batch engine separation is stable.
   - `StreamingTranscriptionEngine`
   - `StreamingTranscriptionSession`
   - `StreamingTranscriptionEvent`
   - Verify: current engines keep `supportsTrueStreaming == false`, including WhisperKit rolling preview.

7. Add coordinator route planning without changing runtime behavior.
   - `TranscriptionCoordinatorPlan`
   - one-shot engines route to VAD chunk final plus optional rolling preview.
   - true streaming candidates route to continuous audio sessions.
   - Verify: current Apple final-only engines still route to one-shot without preview.

8. Add hidden streaming session runner without connecting product runtime.
   - `TranscriptionCoordinator`
   - reject streaming start for one-shot plans.
   - drive `StreamingTranscriptionSession.accept` / `finish`.
   - record first partial latency, final latency, partial/final event count, accepted sample count, latest revision.
   - Verify: stub streaming engine emits partial/final through coordinator and updates metrics.

9. Add hidden SpeechAnalyzer streaming PoC engine.
   - `SpeechAnalyzerStreamingEngine`
   - Convert 16kHz mono Float32 chunks into `AnalyzerInput`.
   - Use `SpeechTranscriber` progressive results as partial/final streaming events.
   - Keep `SpeechEngineID.speechAnalyzer.supportsTrueStreaming == false` until product assembly policy is ready.
   - Verify: compile/default tests pass; manual smoke reports local Korean availability before running.

## Non-goals

- Do not add Nemotron or sherpa runtime integration in this step.
- Do not change VAD behavior.
- Do not change the default engine.
- Do not connect true streaming abstractions to app runtime until a streaming engine PoC is selected.
