# SpeechAnalyzer PoC result

## Goal

Evaluate whether Apple's on-device `SpeechAnalyzer`/`SpeechTranscriber` can be a free local streaming STT candidate for Korean meeting transcription.

## Local SDK/API probe

Environment:

- Xcode: `26.5` (`17F42`)
- Swift: `6.3.2`
- SDK: `MacOSX26.5.sdk`

Observed probes:

```sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/minto2-speechanalyzer-clang-cache \
  swift -e 'import Speech; _ = SpeechAnalyzer.self; print("SpeechAnalyzer symbol ok")'
```

Result:

- `SpeechAnalyzer` symbol is present.
- `SpeechTranscriber(locale:preset:)` compiles with `.progressiveTranscription`.
- `SpeechAnalyzer(modules:)` can be constructed.

## Korean locale probe

```sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/minto2-speechanalyzer-clang-cache \
  swift -e 'import Foundation; import Speech; if #available(macOS 26.0, *) { print("isAvailable=\(SpeechTranscriber.isAvailable)"); let ko = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ko-KR")); print("koSupported=\(String(describing: ko))"); let installed = await SpeechTranscriber.installedLocales; print("installedCount=\(installed.count)") }'
```

Result:

- `SpeechTranscriber.isAvailable`: `true`
- `supportedLocale(equivalentTo: ko-KR)`: `nil`
- `supportedLocales.count`: `0`
- `installedLocales.count`: `0`

## Interpretation

- SpeechAnalyzer is architecturally attractive for this app because it is free, on-device, async/streaming-first, and supports volatile/final result separation.
- It is not currently a primary Korean STT candidate in this local environment because `ko-KR` does not resolve to a supported locale.
- Keep it as a future fast-path if Apple exposes Korean support on the target OS/device. The app would still need a runtime engine picker because current deployment is macOS 14 while SpeechAnalyzer requires macOS 26 APIs.

## Verification

```sh
env RUN_SPEECH_ANALYZER_POC=1 \
  CLANG_MODULE_CACHE_PATH=/private/tmp/minto2-speechanalyzer-clang-cache \
  SWIFTPM_HOME=/private/tmp/minto2-speechanalyzer-swiftpm-cache \
  swift test --disable-sandbox \
  --scratch-path /private/tmp/minto2-speechanalyzer-build \
  --filter SpeechAnalyzerAvailabilityTests
```
