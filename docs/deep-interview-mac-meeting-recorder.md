# Deep Interview Spec: Mac 전용 회의 녹음 & 실시간 전사 서비스

## Metadata
- Interview ID: minto2-recording-001
- Rounds: 6
- Final Ambiguity Score: 14.5%
- Type: greenfield
- Generated: 2026-05-26
- Threshold: 20%
- Status: PASSED

## Clarity Breakdown
| 차원 | 점수 | 가중치 | 가중 점수 |
|------|------|--------|----------|
| Goal Clarity | 0.90 | 40% | 0.36 |
| Constraint Clarity | 0.85 | 30% | 0.255 |
| Success Criteria | 0.80 | 30% | 0.24 |
| **Total Clarity** | | | **0.855** |
| **Ambiguity** | | | **14.5%** |

---

## Goal

회의 중 마이크 음성을 실시간으로 캡처하여 한국어 STT(Whisper 로컬 모델)로 전사하고,
Cluely 스타일의 반투명 floating overlay 창에 실시간 텍스트를 표시하는 Mac 전용 앱.
회의 종료 시 전체 전사본을 로컬 Markdown/PDF 파일로 자동 저장한다.

**한 줄 요약:** "Mac 위에 조용히 떠 있으면서 회의를 받아쓰고 파일로 남겨주는 로컬 전용 앱"

---

## 범위 (MVP vs 향후)

### MVP (Phase 1)
- 마이크 오디오 캡처
- 로컬 Whisper 모델로 실시간 한국어 STT
- Cluely 스타일 floating overlay UI (항상 최상위, 반투명)
- 회의 종료 후 로컬 Markdown 파일 자동 저장

### Phase 2 (추후)
- AI 요약 / 액션 아이템 자동 추출 (로컬 LLM)
- 스피커 라벨링 (Speaker A, B 구분)
- PDF 내보내기

### Phase 3 (추후)
- 시스템 오디오 캡처 (Zoom, Teams 등 상대방 음성 포함)

---

## Constraints

- **플랫폼:** macOS 전용 (Windows/Linux 미지원)
- **처리 방식:** 완전 로컬 — 음성 데이터 외부 전송 없음
- **언어:** 한국어 회의 최적화 (기본 언어: ko)
- **인터넷:** 불필요 (STT 및 AI 모두 로컬)
- **저장 위치:** 로컬 파일시스템 (Markdown/PDF)
- **외부 통합 없음:** Notion, Slack 연동은 MVP 범위 밖

---

## Non-Goals

- 영어 또는 다국어 실시간 번역 (MVP에서 제외)
- 클라우드 API 사용 (OpenAI Whisper API, GPT-4 등)
- 외부 서비스 연동 (Notion, Slack, Jira 등)
- 모바일 앱 (iOS, Android)
- 윈도우/리눅스 지원
- 실시간 AI 제안 (Phase 2로 연기)

---

## Acceptance Criteria

### MVP 완료 기준
- [ ] 앱 실행 시 마이크 권한 요청 후 녹음 시작
- [ ] 발화 내용이 3초 이내 지연으로 overlay에 텍스트로 나타남
- [ ] Overlay 창이 화면 위에 항상 떠 있고 다른 앱 사용 시에도 가려지지 않음
- [ ] Overlay 창의 불투명도 및 위치를 사용자가 조절 가능
- [ ] "회의 종료" 버튼 클릭 시 타임스탬프 포함된 Markdown 파일 자동 생성
- [ ] Markdown 파일에 전체 전사 텍스트 포함
- [ ] 로컬 Whisper 모델 사용 (인터넷 연결 없이 동작)
- [ ] 한국어 인식 정확도 WER 20% 이하 (M2 이상 Mac 기준)

---

## Assumptions Exposed & Resolved

| 가정 | 검증 | 결론 |
|------|------|------|
| 실시간 표시가 집중력을 방해할 수 있다 | Contrarian Mode에서 질문 | 둘 다 필요 — overlay는 선택적 사용 |
| 클라우드 API가 더 정확할 수 있다 | 직접 질문 | 개인정보 보호로 완전 로컬 선택 |
| 다양한 회의 유형 지원 필요 | 사용 시나리오 확인 | 내부 팀 한국어 회의에 집중 |
| 리포트 외부 연동이 필요할 수 있다 | 출력 형식 질문 | 로컬 파일로 충분 |

---

## Technical Context

### 참고 레퍼런스
| 서비스 | 역할 | 차용할 점 |
|--------|------|----------|
| [Lightning-SimulWhisper](https://github.com/altalt-org/Lightning-SimulWhisper) | 실시간 로컬 Whisper STT | 오디오 청크 스트리밍 → Whisper 파이프라인 |
| [SimulStreaming](https://github.com/ufal/SimulStreaming) | 스트리밍 음성인식 아키텍처 | 버퍼링 전략, 지연 최소화 기법 |
| Tiro | 한국어 회의 전사 서비스 | 전사 결과물 포맷, 타임스탬프 구조 |
| Cluely | Mac overlay UI 패턴 | Floating window, 반투명 UI, 항상 최상위 |

### 권장 기술 스택 (결정 필요)
**Option A: Swift Native (권장)**
- `AVAudioEngine` / `AVCaptureSession` — 마이크 입력
- `whisper.cpp` with Metal 가속 — 로컬 STT
- `SwiftUI` + `NSWindow` (level: .floating) — Overlay UI
- Apple Silicon Neural Engine 활용 가능
- 장점: 최고 성능, macOS 네이티브 UX
- 단점: Swift 개발 필요

**Option B: Python + Electron (빠른 프로토타이핑)**
- `pyaudio` / `sounddevice` — 마이크 입력
- `faster-whisper` + CTranslate2 — 최적화된 로컬 Whisper
- `Electron` + `BrowserWindow` (alwaysOnTop) — Overlay UI
- 장점: Lightning-SimulWhisper 코드 재활용 가능
- 단점: 메모리/성능 오버헤드

### 최소 시스템 요구사항
- macOS 13 (Ventura) 이상
- Apple M1 이상 (Neural Engine 활용)
- 8GB RAM 이상 (whisper-medium 모델 기준)

---

## Ontology (Key Entities)

| 엔티티 | 타입 | 주요 속성 | 관계 |
|--------|------|----------|------|
| Meeting | core domain | id, startedAt, endedAt, language | has many Segments |
| Transcription | core feature | segments[], language, model | belongs to Meeting |
| Segment | core domain | text, startTime, endTime, speaker? | belongs to Transcription |
| OverlayUI | supporting | opacity, position, isVisible, alwaysOnTop | displays Transcription |
| LocalModel | supporting | modelName, language, backend | used by Transcription |
| PostMeetingReport | core feature | markdownPath, pdfPath?, createdAt | generated from Meeting |
| ActionItem | future feature | text, assignee?, dueDate? | extracted from Meeting |
| TeamMember | supporting | name, speakerLabel? | participates in Meeting |

## Ontology Convergence

| 라운드 | 엔티티 수 | 신규 | 변경 | 안정 | 안정성 |
|--------|----------|------|------|------|--------|
| 1 | 4 | 4 | - | - | N/A |
| 2 | 6 | 2 | 0 | 4 | 67% |
| 3 | 7 | 1 | 0 | 6 | 86% |
| 4 | 8 | 1 | 0 | 7 | 87.5% |
| 5 | 8 | 0 | 0 | 8 | 100% |
| 6 | 8 | 0 | 0 | 8 | 100% |

온톨로지 5라운드부터 완전 수렴 (100%). 도메인 모델 안정.

---

## Interview Transcript

<details>
<summary>전체 Q&A (6 라운드)</summary>

### Round 1
**Q:** 회의 중 화면에 보여주는 핵심 콘텐츠는 무엇인가요?
**A:** 실시간 전사 + AI 요약/제안
**Ambiguity:** 69% (Goal: 0.55, Constraints: 0.20, Criteria: 0.10)

### Round 2
**Q:** 이 앱을 가장 자주 쓰게 될 회의 유형은 무엇인가요?
**A:** 내부 팀 회의 (한국어)
**Ambiguity:** 56% (Goal: 0.65, Constraints: 0.30, Criteria: 0.30)

### Round 3
**Q:** 음성 인식(STT)과 AI 요약 처리를 어디서 실행하는 게 중요한가요?
**A:** 완전 로컬 (Mac 전용)
**Ambiguity:** 42% (Goal: 0.70, Constraints: 0.65, Criteria: 0.35)

### Round 4 [Contrarian Mode]
**Q:** 만약 Cluely식 overlay가 실제 회의에서 집중력을 방해한다면? 가장 중요하게 남게될 것은?
**A:** 둘 다 해야함 (실시간 + 사후 모두)
**Ambiguity:** 30.5% (Goal: 0.80, Constraints: 0.70, Criteria: 0.55)

### Round 5
**Q:** 회의 종료 후 생성되는 리포트는 어디에 저장/전달되나요?
**A:** 로컬 파일로 저장 (Markdown/PDF)
**Ambiguity:** 22.5% (Goal: 0.85, Constraints: 0.80, Criteria: 0.65)

### Round 6 [Simplifier Mode]
**Q:** 한 화면에 동시에 보여줘도 괜찮은 overlay 아이템은 미니멀로 무엇인가요?
**A:** 실시간 전사 텍스트만. 차후에 AI 요약, 스피커 라벨링 추가 예정
**Ambiguity:** 14.5% ✅ (Goal: 0.90, Constraints: 0.85, Criteria: 0.80)

</details>
