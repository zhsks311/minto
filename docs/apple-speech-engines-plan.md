# Apple Speech Engines Implementation Plan

## Goal

Add Apple speech recognition engines to the existing WhisperKit model choices without weakening the current default path.

## Scope

- Keep WhisperKit as the default engine.
- Add `SpeechAnalyzer` as a selectable engine only when the current macOS version supports it.
- Add `SFSpeechRecognizer` as an on-device-only selectable engine.
- Disable unavailable engine rows and show the concrete reason in Settings.
- Add the required speech-recognition permission description.
- Keep existing model cache recovery for WhisperKit only.

## Verification Criteria

1. Pencil design: export a visible V2.2 Settings mockup with engine availability states.
2. Compile: `swift build` passes.
3. Tests: focused unit tests for engine metadata and SFSpeech on-device policy pass.
4. UI QA: launch the app and confirm Settings shows engine names, availability, disabled rows, and on-device copy.
5. Commit: commit only the worktree changes for this branch.
