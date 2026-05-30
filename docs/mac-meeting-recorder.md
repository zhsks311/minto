# 구현 계획: Mac 전용 회의 녹음 & 실시간 전사 서비스 (Minto)

> **스펙 출처:** `.omc/specs/deep-interview-mac-meeting-recorder.md`
> **버전:** v4 FINAL (Planner → Architect × 3 → Critic × 3 합의 완료)
> **합의 라운드:** 3 / 최대 5
> **작성일:** 2026-05-26

---

## RALPLAN-DR Summary

### Principles
1. **완전 로컬 우선** — 음성 데이터는 어떤 이유로도 외부 서버로 전송되지 않는다
2. **MVP 단순성** — Phase 1: STT + Overlay + Markdown만. AI 기능은 Phase 2로 명확히 분리
3. **Swift Concurrency 안전** — `@ModelActor` + `withCheckedContinuation + DispatchQueue` + `AsyncStream` 직렬화로 data race 없음
4. **점진적 확장** — `AudioSourceProtocol` 추상화로 Phase 3 ScreenCaptureKit 교체 비용 최소화
5. **사용자 통제권** — Overlay 위치/불투명도/마이크 장치 사용자 조절 가능

### Decision Drivers (Top 3)
1. **STT 지연 ≤ 3초 (p95, 연속 발화)** — Metal GPU + DispatchQueue 오프로드로 달성
2. **배포 채널 결정 (Phase 1-A Day 1 게이트)** — App Store vs 직접 배포가 entitlements/모델 로딩 전략 전체 결정
3. **한국어 WER ≤ 20%** — whisper-medium (16GB RAM) 기본, small (8GB) 경량 옵션

### Viable Options

#### Option A: Swift Native + whisper.cpp (권장)
| 항목 | 내용 |
|------|------|
| STT 백엔드 | whisper.cpp + Metal 가속 |
| 블로킹 오프로드 | `withCheckedContinuation` + `DispatchQueue.global(.userInitiated)` + `nonisolated static func` |
| 동시성 | `@ModelActor`(상태 직렬화) + `AsyncStream`(청크 순서 보장) |
| **장점** | Metal GPU 활용, 단일 런타임 배포, Phase 2 Core ML LLM 연결 자연스러움 |
| **단점** | Swift ↔ whisper.cpp Obj-C++ 브리지. POC 실패 시 Option B 전환 |

> **POC 합격 기준 (Phase 1-A Day 1):** Xcode 16+ Metal 가속 빌드 성공 + whisper-small 5초 오디오 추론 ≤ 3초

#### Option B: Python faster-whisper + Swift UI 하이브리드 (POC 실패 시)
| 항목 | 내용 |
|------|------|
| STT | faster-whisper + CTranslate2 3.x (Core ML 백엔드) |
| IPC | Unix Domain Socket (JSON 세그먼트 스트리밍) |
| 전환 트리거 | Metal 추론 ≤ 3초 미달성 또는 브리지 빌드 실패 |
| 전환 시 추가 일정 | +3-5일 (IPC 레이어 + Python 런타임 패키징) |

---

## Requirements Summary

### 기능 요구사항
| ID | 요구사항 | 우선순위 |
|----|----------|---------|
| F-01 | `AudioSourceProtocol` + `AVAudioEngineConfigurationChange` 핫스왑 + 권한 거부 처리 | P0 |
| F-02 | `ModelActor` + `DispatchQueue` 오프로드 + `AsyncStream` 직렬화 기반 실시간 한국어 STT | P0 |
| F-03 | Cluely 스타일 floating overlay (committed/tentative 분리) | P0 |
| F-04 | 회의 시작/종료 메뉴바 제어 | P0 |
| F-05 | 회의 종료 시 로컬 Markdown 자동 생성 (디스크 flush 포함) | P0 |
| F-06 | Overlay 불투명도/위치/마이크 장치 설정 | P1 |

### 비기능 요구사항
| ID | 요구사항 | 기준 |
|----|----------|------|
| N-01 | STT 지연 | ≤ 3초 p95 (M2, 연속 5초 청크, whisper-medium) |
| N-02 | 한국어 WER | ≤ 20% (AI Hub 원본 .wav 직접 전달 + jiwer) |
| N-03 | 메모리 | small ~500MB / medium ~1.5GB / large-v3 ~3GB. 기본: medium (권장 RAM 16GB) |
| N-04 | 외부 네트워크 | 0건 (완전 오프라인) |
| N-05 | 최소 시스템 | macOS 13+, M1+, 8GB(small) / 16GB(medium) |

---

## Acceptance Criteria

- [ ] AC-01: 최초 실행 시 마이크 권한 다이얼로그 표시. **거부 시:** Overlay에 "마이크 권한 필요" 메시지 + 시스템 환경설정 안내
- [ ] AC-02: 권한 허용 후 "녹음 시작" 클릭 시 오디오 캡처 시작
- [ ] AC-03: 평균 5-15초 발화 50회, STT 지연 p95 ≤ 3초 — Instruments Time Profiler 측정 (M2 whisper-medium 기준)
- [ ] AC-04: Overlay 창이 Finder/Chrome 전환 시에도 항상 최상위 유지
- [ ] AC-05: Overlay 창 드래그 이동 가능
- [ ] AC-06: 불투명도 슬라이더 20%-100% 동작
- [ ] AC-07: "녹음 종료" 시 `~/Documents/Minto/{YYYY-MM-DD HH-mm}.md` 파일 생성
- [ ] AC-08: Markdown에 `[HH:mm:ss]` 타임스탬프 + 전사 텍스트 포함
- [ ] AC-09: Wi-Fi 비활성화 전체 플로우 완료 (Network Monitor 0건)
- [ ] AC-10: AI Hub 한국어 음성 원본 .wav 20개 → whisper 직접 전달 → `jiwer` WER ≤ 20%
- [ ] AC-11: 마이크 장치 목록 표시 및 전환 가능. **핫스왑 중 크래시 없음 + 재시작 실패 시 메뉴바 알림**

---

## 핵심 아키텍처 설계 (Final)

### 1. STTService + TranscriptionViewModel 분리

```swift
// Sources/Minto/Services/STTService.swift
// @ModelActor: whisperContext 동시 접근 직렬화. ObservableObject 없음.
@ModelActor
class STTService {
    private var whisperContext: OpaquePointer?

    func loadModel(at path: URL) throws {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw STTError.modelNotFound(path)  // 모델 부재 즉시 throw
        }
        whisperContext = whisper_init_from_file(path.path)
        guard whisperContext != nil else { throw STTError.loadFailed }
    }

    // Sendable-safe 오프로드:
    // 1. @ModelActor 컨텍스트에서 포인터를 지역 변수로 복사 (actor 격리 내)
    // 2. nonisolated static 함수에 전달 — self 참조 없음, Swift 6 컴파일 안전
    func transcribe(pcmSamples: [Float], contextPrompt: String) async throws -> TranscriptionResult {
        guard let ctx = self.whisperContext else { throw STTError.modelNotLoaded }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                STTService.runWhisperStatic(ctx: ctx, samples: pcmSamples,
                                            prompt: contextPrompt, continuation: continuation)
            }
        }
    }

    // nonisolated static: actor isolation 없음, OpaquePointer만 수신
    private static func runWhisperStatic(
        ctx: OpaquePointer,
        samples: [Float],
        prompt: String,
        continuation: CheckedContinuation<TranscriptionResult, Error>
    ) {
        // whisper_full_params 설정 + initial_prompt UTF-8 주입
        // whisper_full() C++ 동기 블로킹 실행
        // 결과를 continuation.resume(returning:) 으로 반환
    }
}

// Sources/Minto/ViewModels/TranscriptionViewModel.swift
// @MainActor: UI 상태 소유. ObservableObject.
@MainActor
class TranscriptionViewModel: ObservableObject {
    @Published var committedSegments: [Segment] = []
    @Published var pendingSegment: Segment?

    private let sttService = STTService()
    private var transcriptionTask: Task<Void, Never>?
    // AsyncStream으로 청크 직렬화 — 병렬 Task 생성 없음, 순서 역전 없음
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?

    func startProcessing() {
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        chunkContinuation = continuation
        transcriptionTask = Task {
            for await chunk in stream {   // 단일 소비 루프 — 자연 직렬화
                guard !Task.isCancelled else { break }
                do {
                    let prompt = state.recentCommittedText
                    let result = try await sttService.transcribe(
                        pcmSamples: chunk.samples, contextPrompt: prompt)
                    state.advanceWindow(newResult: result)
                    committedSegments = state.committedSegments
                    pendingSegment = state.pendingSegment
                } catch { /* 세그먼트 오류 로깅, 계속 진행 */ }
            }
        }
    }

    // AudioSource onBuffer 콜백에서 호출 (DispatchQueue hop 후 MainActor로)
    func enqueueChunk(_ chunk: AudioChunk) {
        chunkContinuation?.yield(chunk)
    }
}
```

### 2. TranscriptionState 슬라이딩 윈도우

```swift
// Sources/Minto/Models/TranscriptionState.swift
struct TranscriptionState {
    var committedSegments: [Segment] = []
    var pendingSegment: Segment?

    // n+1번째 청크 도착 시 n번째 청크 확정 (SimulWhisper 슬라이딩 윈도우)
    mutating func advanceWindow(newResult: TranscriptionResult) {
        if let previous = pendingSegment {
            committedSegments.append(previous)
        }
        pendingSegment = newResult.segment
        // 메모리 관리: 100 세그먼트 초과 시 flush 트리거
        if committedSegments.count > 100 {
            NotificationCenter.default.post(name: .transcriptionNeedsFlush, object: committedSegments)
            committedSegments.removeAll()
        }
    }

    // initial_prompt 주입용 — recentCommittedText를 STTService.transcribe에 전달
    var recentCommittedText: String {
        committedSegments.suffix(3).map(\.text).joined(separator: " ")
    }
}
```

### 3. AudioSourceProtocol + 핫스왑 + 권한 처리

```swift
// Sources/Minto/Services/AudioSourceProtocol.swift
protocol AudioSourceProtocol: AnyObject {
    /// onBuffer는 AVAudioEngine 내부 오디오 스레드에서 호출됨.
    /// 구현 시 반드시 DispatchQueue.main 또는 적절한 큐로 hop 후 소비할 것.
    var onBuffer: (([Float]) -> Void)? { get set }
    var onError: ((AudioSourceError) -> Void)? { get set }  // 에러 전파 채널
    var availableDevices: [AudioDevice] { get }
    func start() throws
    func stop()
    func selectDevice(_ device: AudioDevice) throws
}

// Sources/Minto/Services/MicrophoneSource.swift
class MicrophoneSource: AudioSourceProtocol {
    var onError: ((AudioSourceError) -> Void)?

    // 마이크 권한 거부 시 즉시 onError 호출 → ViewModel이 Overlay에 안내 표시
    func start() throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .denied, .restricted:
            onError?(.permissionDenied)  // caller가 사용자 안내 처리
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted { try? self?.startEngine() }
                else { self?.onError?(.permissionDenied) }
            }
        case .authorized: try startEngine()
        }
    }

    // AVAudioEngine 핫스왑: 디바이스 변경/연결 해제 시 재시작
    @objc private func handleConfigChange(_ notification: Notification) {
        do {
            try restart()  // AVAudioConverter 재생성 포함
        } catch {
            // 침묵 실패 금지 — onError로 전파 → 메뉴바 "오디오 재시작 실패" 표시
            onError?(.configChangeFailed(error))
        }
    }

    // onBuffer 콜백: AVAudioEngine 내부 스레드에서 호출
    // DispatchQueue.main.async로 hop 후 ViewModel.enqueueChunk 호출
    private func installTap() {
        inputNode.installTap(onBus: 0, ...) { [weak self] buffer, _ in
            let samples = self?.convert(buffer)  // 16kHz PCM 변환
            DispatchQueue.main.async {
                self?.onBuffer?(samples ?? [])
            }
        }
    }
}
```

---

## Implementation Steps (Final)

### Phase 1-A: 프로젝트 셋업 + 배포 게이트 (2-3일)

**[Day 1 필수 결정 — 이후 단계 진행 조건]**

1. **배포 채널 결정**
   - App Store: App Sandbox + `audio-input` entitlement + **모델 첫 실행 다운로드 강제** (ggml-medium.bin ~1.5GB 번들 포함 불가 → 다운로드 UI + 실패 처리 Phase 1-C에 추가)
   - 직접 배포(.dmg): Hardened Runtime + Notarization. **ggml-medium.bin 번들 포함 가능** (DMG ~1.5GB 크기 수용 필요)

2. **swift-whisper POC**
   - 합격: Xcode 16+ Metal 빌드 + whisper-small 5초 오디오 ≤ 3초
   - 실패: Option B 전환 (IPC 스켈레톤 설계, +3-5일 추가)

3. Xcode 프로젝트 생성 (macOS 13.0, SwiftUI), entitlements 구성

### Phase 1-B: 오디오 캡처 + VAD (3-4일)

4. `AudioSourceProtocol` + `MicrophoneSource` 구현
   - `AVAudioEngine` + `AVAudioConverter` (→ 16kHz mono PCM)
   - `AVAudioEngineConfigurationChange` 핫스왑: `try restart()` + 실패 시 `onError` 전파
   - 마이크 권한 거부: `onError(.permissionDenied)` → ViewModel이 Overlay 안내 표시
   - `onBuffer` 콜백: `DispatchQueue.main.async` hop 후 `ViewModel.enqueueChunk()` 호출

5. `VADProcessor` 구현
   - 에너지 임계값: `-50dBFS`, 침묵 지속: `300ms`, 최대 청크: `5초`
   - `AudioChunk`: `{ samples: [Float], durationSeconds: Double, trailingSilence: TimeInterval }`
   - `whisper.cpp` VAD 파라미터: `params.vad_thold` (음성 확률), `params.freq_thold` (주파수)
     - `params.no_speech_thold`는 VAD 아님 — "무음 토큰 확률 임계값" (혼동 주의)

### Phase 1-C: STT 레이어 (3-4일)

6. `ModelActor` 글로벌 액터 정의

7. `STTService` 구현 (`@ModelActor`)
   - `nonisolated static func runWhisperStatic(ctx:samples:prompt:continuation:)` 분리 (Swift 6 Sendable-safe)
   - `initial_prompt`: `recentCommittedText` 한국어 UTF-8 → C `const char*` Bridge 처리
   - 모델 로딩 실패 처리: 파일 부재(`modelNotFound`) / 손상(`loadFailed`) → ViewModel에서 안내
     - App Store 경로: 모델 다운로드 UI + 진행률 표시 + 실패 재시도 UI 필요

8. `TranscriptionViewModel` 구현 (`@MainActor`)
   - `AsyncStream<AudioChunk>` 단일 소비 루프 (청크 순서 역전 방지)
   - `TranscriptionState.advanceWindow()` 슬라이딩 윈도우
   - `onError` → 메뉴바 알림 경로

**[Phase 1-B→C 연결 Smoke Test]**
- `MicrophoneSource.onBuffer` → `VADProcessor` → `STTService.transcribe` → 콘솔 출력
- Overlay 연결 전에 STT 파이프라인 독립 동작 확인 (xcode 실행 + 로그 확인)

### Phase 1-D: Overlay UI (2-3일)

9. `FloatingWindowManager`
   - `NSWindow(level: .floating)`, `.clear` 배경, `.nonactivatingPanel`
   - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`

10. `TranscriptionOverlayView` (SwiftUI)
    - committed: 회색 고정 텍스트 / pending: 흰색 in-place 교체
    - `.ultraThinMaterial` 배경, 최신 10 committed + 1 pending 표시
    - `@ObservedObject var viewModel: TranscriptionViewModel`
    - 권한 거부 / 모델 로딩 실패 안내 상태 표시

### Phase 1-E: 리포트 + 통합 테스트 (2일)

11. `ReportService`
    - 저장: `~/Documents/Minto/{YYYY-MM-DD HH-mm}.md`
    - 디스크 flush: `transcriptionNeedsFlush` 알림 수신 시 파일 핸들 append 방식 스트리밍 저장
    - **디스크 풀 처리:** 쓰기 실패 시 메뉴바 "저장 실패" 알림 + 임시 인메모리 유지

12. WER 측정 + 통합 검증
    - AI Hub 한국어 원본 .wav 20개 → whisper 직접 전달 → `jiwer` WER ≤ 20%
    - 실제 마이크 경로 품질: 팀원 5명 수동 체크리스트 (파일 주입 측정과 별도)
    - Instruments Time Profiler: 발화 50회 p95 ≤ 3초
    - macOS Network Monitor: 외부 호출 0건
    - AirPods 연결/해제 중 전사 연속성 확인 (AC-11)

---

## 디렉토리 구조

```
Minto.xcodeproj
Sources/
├── Minto/
│   ├── App/
│   │   ├── MintoApp.swift
│   │   └── AppDelegate.swift
│   ├── Models/
│   │   ├── Meeting.swift            # Meeting, Segment, AudioChunk
│   │   ├── TranscriptionState.swift # advanceWindow 슬라이딩 윈도우
│   │   └── Report.swift
│   ├── Services/
│   │   ├── AudioSourceProtocol.swift
│   │   ├── MicrophoneSource.swift   # 핫스왑 + 권한 처리
│   │   ├── VADProcessor.swift
│   │   ├── ModelActor.swift
│   │   ├── STTService.swift         # @ModelActor + static 오프로드
│   │   └── ReportService.swift
│   ├── ViewModels/
│   │   └── TranscriptionViewModel.swift  # @MainActor + AsyncStream
│   ├── UI/
│   │   ├── FloatingWindowManager.swift
│   │   ├── TranscriptionOverlayView.swift
│   │   ├── SettingsView.swift
│   │   └── MenuBarView.swift
│   └── Bridge/
│       ├── WhisperBridge.h
│       └── WhisperBridge.mm         # initial_prompt UTF-8 → const char* 처리
Tests/
├── MintoTests/
│   ├── VADProcessorTests.swift           # CI 포함
│   ├── TranscriptionStateTests.swift     # advanceWindow 순서 역전 케이스 포함, CI 포함
│   ├── ReportServiceTests.swift          # Markdown 포맷 + flush 케이스, CI 포함
│   └── STTIntegrationTests.swift         # whisper-small 5초 샘플 지연 + WER, CI 제외
Resources/
└── models/                               # .gitignore
    └── ggml-medium.bin
```

---

## Risks & Mitigations

| 리스크 | 가능성 | 영향 | 완화 방안 |
|--------|--------|------|----------|
| swift-whisper SPM 브리지 실패 | 중 | 고 | POC 게이트; 실패 시 Option B (+3-5일) |
| whisper-medium WER > 20% (한국어) | 저 | 고 | large-v3 폴백 옵션 (메모리 ~3GB) |
| AVAudioEngine 핫스왑 재시작 실패 | 중 | 중 | `onError` 전파 → 메뉴바 알림 |
| App Sandbox + Metal shader 충돌 | 중 | 고 | Phase 1-A POC 샌드박스 검증 필수 |
| M1 8GB + medium 모델 지연 초과 | 중 | 중 | whisper-small 자동 전환 정책 설정 |
| 장시간 메모리 누수 | 중 | 중 | 100 세그먼트 flush + Instruments 2시간 검증 |
| 디스크 풀 시 데이터 유실 | 저 | 고 | 쓰기 실패 즉시 메뉴바 알림 + 인메모리 유지 |

---

## Verification Steps

1. `xcodebuild test -scheme MintoTests` → VADProcessor, TranscriptionState(순서 역전 케이스), ReportService 통과
2. **Phase 1-B→C Smoke Test:** 파이프라인 독립 동작 확인 (콘솔 전사 출력)
3. Instruments Time Profiler: 발화 50회 (5-15초) p95 ≤ 3초 (M2 whisper-medium)
4. Instruments Allocations: 2시간 연속 메모리 누수 없음
5. macOS Network Monitor: 외부 호출 0건
6. AI Hub .wav 20개 `jiwer` WER ≤ 20%
7. Wi-Fi 비활성화 전체 플로우
8. AirPods 연결/해제 핫스왑 + 재시작 실패 알림 확인 (AC-11)
9. macOS 13 / 14 / 15 크래시 없음

---

## ADR

**결정:** Swift Native + whisper.cpp (Option A) — Phase 1-A POC 전제

**Drivers:**
1. Metal GPU로 STT 지연 ≤ 3초(p95) 달성 가능
2. `nonisolated static + withCheckedContinuation + DispatchQueue` 패턴으로 Swift 6 Sendable-safe C++ 블로킹 오프로드
3. `@ModelActor`(상태 직렬화) + `AsyncStream`(청크 순서 보장) 조합으로 data race 없는 파이프라인

**대안:** faster-whisper + CTranslate2 3.x (Core ML 지원). Lightning-SimulWhisper 직접 재활용 가능. POC 실패 시 전환 경로 명확 (+3-5일).

**배포 채널별 모델 전략:**
- App Store: 첫 실행 다운로드 강제 (ggml-medium.bin ~1.5GB 번들 불가) → 다운로드 UI 필수
- 직접 배포: 번들 포함 가능 (DMG ~1.5GB 수용) 또는 다운로드 선택

**후속 결정 (Phase 1-A Day 1):**
- [ ] App Store vs 직접 배포 → entitlements + 모델 전략
- [ ] swift-whisper SPM vs submodule → POC 결과
- [ ] 기본 모델 small(8GB) vs medium(16GB) → 사용자 RAM 기준

---

## Improvements Applied (Critic APPROVE-WITH-IMPROVEMENTS 반영)
1. `runWhisperStatic` nonisolated static 패턴 + Swift 6 Sendable-safe isolation escape 수정
2. `AsyncStream` 단일 소비 루프로 청크 순서 보장 (병렬 Task 생성 제거)
3. `handleConfigChange` `try?` → `onError` 전파 + 메뉴바 알림 경로
4. `onBuffer` 스레드 계약 프로토콜 doc comment + DispatchQueue hop 명시
5. 마이크 권한 거부 fallback flow 추가
6. 모델 파일 부재/손상 처리 + App Store 다운로드 UI 요구사항
7. Phase 1-B→C Smoke Test 스텝 추가
8. 배포 채널별 모델 번들 전략 명확화 (DMG ~1.5GB 크기 언급)
