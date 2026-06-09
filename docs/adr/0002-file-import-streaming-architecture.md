# ADR 0002: File Import Streaming Architecture

상태: Accepted
작성일: 2026-06-09

## Context

Minto2는 녹음이 끝난 뒤 음성 또는 영상 파일을 넣어 회의록을 만들 수 있어야 한다. 이 기능의 정상 사용 범위에는 1-2시간 회의 파일이 포함된다.

초기 구현은 파일 전체를 16kHz mono `[Float]` 배열로 만든 뒤 use-case에서 다시 chunk 배열로 나누는 방식이었다. 코드리뷰에서 이 방식은 원본 mono buffer, resampled buffer, chunk copy가 동시에 생겨 긴 파일에서 앱 정지나 OOM으로 이어질 수 있다는 BLOCKER로 판정됐다.

## Decision

파일 import는 streaming chunk pipeline으로 처리한다.

- UI는 `MeetingFileImportUseCase`만 호출하고 `FileAudioExtractor`나 `MeetingStore`를 직접 다루지 않는다.
- `FileAudioExtractor`는 AVFoundation `AVAssetReader`로 파일을 읽고, 16kHz mono PCM chunk를 callback으로 순차 전달한다.
- chunk callback은 source order로 호출하며, 각 callback이 끝날 때까지 다음 chunk를 읽지 않는다.
- `MeetingFileImportUseCase`는 callback으로 들어온 chunk를 즉시 전사/교정하고, segment만 누적한다.
- 저장 commit point는 최종 요약과 `MeetingRecord` 생성이 끝난 뒤 `MeetingStore.save` 한 번으로 제한한다.
- 취소가 발생하면 부모 import task cancellation을 detached reader task에 전달하고, reader를 `cancelReading()`하며, use-case는 `cancelled` 상태로 끝내고 partial meeting을 저장하지 않는다.
- 파일 import 교정과 요약은 live `MeetingContext`를 읽지 않고 명시적 `LLMCorrectionContext`, `SummaryGenerationContext`를 사용한다.

## Alternatives

- 전체 PCM 배열 반환
  - 장점: 구현이 단순하다.
  - 단점: 긴 파일에서 메모리 사용량이 파일 길이에 선형으로 커지고, chunk copy까지 중첩된다.
  - 기각 이유: 사후 회의 파일은 장시간 파일이 정상 입력이라 merge blocker다.
- live `TranscriptionViewModel` 재사용
  - 장점: 기존 전사 흐름을 재활용한다.
  - 단점: live recording 상태, overlay 상태, file import 상태가 섞인다.
  - 기각 이유: 파일 import는 offline pipeline이어야 하며 live audio session을 건드리면 안 된다.
- 파일 import용 별도 저장 schema 추가
  - 장점: 출처별 metadata를 풍부하게 담을 수 있다.
  - 단점: 검색 index, export, UI가 모두 schema 분기를 가져야 한다.
  - 기각 이유: 현재 요구는 회의록 생성이며 기존 `MeetingRecord` 최소 필드로 충분하다.

## Consequences

### Positive

- 긴 파일에서도 메모리 사용량이 chunk 크기 중심으로 제한된다.
- UI와 AVFoundation adapter 사이에 use-case 경계가 유지된다.
- 취소와 저장 commit point가 한 곳에 모인다.
- live 회의 context가 파일 import 교정/요약에 섞이지 않는다.

### Negative

- extractor callback이 MainActor use-case를 기다리므로 처리량은 STT 속도에 의해 backpressure를 받는다.
- 현재 resampling은 선형 보간이다. 품질 이슈가 확인되면 `AVAudioConverter` 기반 변환으로 교체해야 한다.
- segment는 최종 저장 전까지 메모리에 누적된다. transcript text는 회의록 생성을 위해 필요한 최소 상태다.

## Migration

- 저장 schema는 기존 `MeetingRecord`를 유지한다.
- 기존 live recording 경로는 변경하지 않는다.
- `SummaryService.generateFinal(transcript:)` 기존 API는 유지하고, 파일 import만 explicit context overload를 사용한다.
- `LLMCorrectionService.correct(text:context:)` 기존 API는 유지하고, 파일 import만 explicit `LLMCorrectionContext` overload를 사용한다.

## Rollback

- `파일 가져오기` UI action과 `MeetingFileImportUseCase` wiring을 제거하면 기존 live recording 기능은 유지된다.
- `FileAudioExtractor`와 파일 import 테스트는 독립 파일이므로 feature 단위 revert가 가능하다.

## Verification

- `swift test --disable-sandbox --scratch-path /tmp/minto2-file-import-test --filter MeetingFileImport`
- 실제 작은 wav fixture를 생성해 AVFoundation extractor가 chunk를 방출하는지 확인
- unsupported extension은 파일 읽기 전에 거부
- 추출 전 취소와 chunk 처리 중 취소 모두 partial meeting 저장 없음
- 실제 `FileAudioExtractor`가 부모 task 취소를 detached reader task에 전파하는지 확인
- `git diff --check`
- 후속 전체 gate: `swift build --disable-sandbox --scratch-path /tmp/minto2-file-import-build`
