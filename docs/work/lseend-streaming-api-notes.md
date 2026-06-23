# LS-EEND 스트리밍 API 노트 (Task 0a)

FluidAudio 0.15.2 `LSEENDDiarizer`(`Sources/FluidAudio/Diarizer/LS-EEND/LSEENDDiarizer.swift`) + `Diarizer` 프로토콜(`DiarizerProtocol.swift`) 실측.

## 타입 성격 (동시성 설계 근거)
- `LSEENDDiarizer`는 `Diarizer: AnyObject` = **class, non-Sendable**, 내부 가변 상태(session/timeline/framesFed). → 우리 **전용 actor가 인스턴스를 소유**하고 모든 호출을 직렬화한다. `process()`는 동기 `throws`라 actor 안에서 호출.
- 반환 `DiarizerTimelineUpdate`는 **Sendable** → actor 경계 넘어 `@MainActor` UI로 안전 전달.

## 프로토콜 표면 (Diarizer)
- 상태: `isAvailable`, `numFramesProcessed`, `targetSampleRate: Int?`, `modelFrameHz: Double?`, `numSpeakers: Int?`, `timeline: DiarizerTimeline`.
- 초기화: `initialize(... computeUnits: MLComputeUnits = .cpuOnly ...)` (CPU 기본 — STT ANE 비경합).

## 스트리밍 호출
```
func addAudio<C: Collection>(_ samples: C, sourceSampleRate: Double?) throws where C.Element == Float
func process() throws -> DiarizerTimelineUpdate?            // 버퍼된 오디오 처리, 새 출력 반환(없으면 nil)
func process<C: Collection>(samples: C, sourceSampleRate: Double?) throws -> DiarizerTimelineUpdate?  // addAudio+process 한 번에
func finalizeSession() throws -> DiarizerTimelineUpdate?    // 세션 종료 시 1회, timeline.finalize()
```
- `DiarizerTimelineUpdate { finalizedSegments: [DiarizerSegment]; tentativeSegments: [DiarizerSegment]; chunkResult }` — **finalized**=확정, **tentative**=잠정(약 900ms 미리보기). 라이브 UI는 둘 다 표시하되 tentative는 "곧 확정" 취급.
- 입력은 mono. `sourceSampleRate`에 우리 캡처 SR 주면 내부 리샘플(타깃 16k).

## 앵커 (pre-enrollment)
```
func enrollSpeaker<C: Collection>(withAudio samples: C, sourceSampleRate: Double? = nil, named name: String? = nil, ...)
```
- ⚠️ 세션 중 호출 시 timeline 리셋 → **첫 addAudio 전에만**. "나" 채널/등록 보이스프린트 오디오를 여기서 주입.

## timeline (DiarizerTimeline)
- 스레드 안전(내부 lock). `.speakers`, `.finalizedSegments`, `.tentativeSegments`, `.hasSegments`, `finalizedSegmentCount`.

## 우리 어댑터 매핑(Phase 1)
- actor가 `LSEENDDiarizer` 1개 보유 → `start(preEnrolled:)`(initialize + enrollSpeaker) / `process(samples:)`(→ DiarizerTimelineUpdate → 우리 `DiarizedSpeakerSegment`로 변환) / `finish()`(finalizeSession).
- 라이브 청크: STT와 같은 `onBuffer` 샘플을 actor에 넘김(직접 process 호출 금지).
