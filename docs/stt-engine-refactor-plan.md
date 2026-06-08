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

10. Add Nemotron sidecar HTTP client contract outside product runtime.
   - `NemotronSidecarClient`
   - health check endpoint: `/health`.
   - final-chunk transcription endpoint: `/transcribe`.
   - request audio format: 16kHz mono Float32 little-endian encoded as base64.
   - response fields: text, model id, audio seconds, elapsed seconds, RTF, peak memory.
   - Verify: request contract, response parsing, and HTTP failure handling are unit-tested without starting a worker.
11. Add a Nemotron sidecar mock worker before running the real MLX model.
   - `scripts/nemotron_sidecar_mock.py`
   - Keep it dependency-free so contract, timeout, warming, and metric handling can be tested without loading a large model.
   - The mock is not an ASR benchmark and must not be used as CER evidence.
   - Verify: run `/health` and `/transcribe` over localhost, then stop the worker in the same smoke command.
12. Add a real Nemotron MLX worker scaffold on the same HTTP contract.
   - `scripts/nemotron_mlx_sidecar.py`
   - Use `mlx_audio.stt.load(modelID)` and `model.generate(wavPath)` for final chunk one-shot transcription.
   - Convert the Swift f32le payload to a temporary 16kHz mono WAV before calling MLX Audio.
   - Keep model loading lazy by default; use `--preload` for explicit cold-start measurement.
   - Verify without model loading via `--help`, `--check-dependencies`, and Python compile checks; real CER validation requires a prepared MLX environment.
13. Add a sidecar benchmark runner for `sample/meeting`.
   - `scripts/nemotron_sidecar_bench.py`
   - Read 16kHz meeting WAV windows without loading entire long files into memory.
   - Send the same f32le base64 payload as the Swift client.
   - Record per-window CER, global CER, client latency, sidecar RTF, peak memory, and health before/after.
   - Verify with the mock worker only as a contract smoke; real CER evidence requires the MLX worker.

## Non-goals

- Do not connect Nemotron or sherpa runtime integration to product paths in this step.
- Do not change VAD behavior.
- Do not change the default engine.
- Do not connect true streaming abstractions to app runtime until a streaming engine PoC is selected.
