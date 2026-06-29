# EEND 화자분리 학습 가이드

이 문서는 Minto2의 라이브 화자분리를 이해하기 위한 학습용 문서다. 목표는 `EEND`, `EEND-EDA`, `BW-EDA-EEND`, `LS-EEND`, `.ami` 같은 이름이 각각 무엇을 뜻하는지 분리해서 이해하는 것이다.

## 1. 가장 큰 그림

화자분리 diarization은 전사 STT와 다른 문제다.

- STT: "무슨 말을 했나?"
- 화자분리: "누가 언제 말했나?"

화자분리 모델은 최종적으로 이런 시간표를 만들려고 한다.

| 시간 | 화자 1 | 화자 2 | 화자 3 |
|------|--------|--------|--------|
| 0.0초 | 말함 | 안 말함 | 안 말함 |
| 0.1초 | 말함 | 안 말함 | 안 말함 |
| 0.2초 | 말함 | 말함 | 안 말함 |
| 0.3초 | 안 말함 | 말함 | 안 말함 |

여기서 중요한 점은 한 시간에 여러 화자가 동시에 켜질 수 있다는 것이다. 회의에서는 말이 겹칠 수 있기 때문이다.

## 2. 전통적 방식과 EEND 방식

전통적인 화자분리는 보통 다음처럼 동작한다.

> 음성 자르기 → 각 조각의 목소리 특징 추출 → 비슷한 목소리끼리 묶기 → 화자 라벨 부여

이 방식은 "묶기"가 핵심이라서 클러스터링 기반이라고 부른다. Minto2의 종료 후 최종 보정 경로에서 쓰는 VBx도 이 계열에 있다.

EEND는 문제를 다르게 본다.

> 음성 입력 → 신경망 → 시간별 화자 활동표

즉, EEND는 "목소리 조각을 나중에 묶는 문제"가 아니라 "매 순간 어떤 화자들이 말하는지 맞히는 문제"로 바꾼다.

## 3. EEND

EEND는 End-to-End Neural Diarization의 줄임말이다.

핵심 아이디어:

- 화자분리를 여러 단계로 쪼개지 않고 신경망이 직접 출력한다.
- 출력은 시간별 화자 활동표다.
- 겹쳐 말하는 구간을 표현할 수 있다.

초기 EEND의 한계:

- 화자 수가 고정된 환경에 가깝다.
- 긴 회의 전체를 실시간으로 처리하는 데는 맞지 않는다.
- 전체 입력을 보고 판단하는 offline 성격이 강하다.

쉽게 말하면:

> EEND는 "화자분리를 클러스터링이 아니라 신경망의 시간표 예측 문제로 바꾼 첫 큰 방향 전환"이다.

## 4. EEND-EDA

EEND-EDA는 EEND에 attractor를 붙인 방식이다. EDA는 Encoder-Decoder Attractor를 뜻한다.

attractor는 쉽게 말해 "이 사람 같은 소리는 이 자리로 모으자"라는 화자 자리다.

흐름:

> 음성 → 프레임 embedding → attractor 생성 → embedding과 attractor 비교 → 화자별 활동 판단

EEND-EDA가 해결하려는 문제:

- 기본 EEND는 화자 수가 고정되기 쉽다.
- 실제 회의는 2명일 수도 있고 5명일 수도 있다.
- EEND-EDA는 오디오를 보고 필요한 만큼 화자 자리를 만든다.

예를 들면 모델이 이렇게 판단한다.

- attractor 1: 첫 번째 사람 자리
- attractor 2: 두 번째 사람 자리
- attractor 3: 세 번째 사람 자리
- stop: 더 이상 새 화자 없음

장점:

- 화자 수가 더 유연하다.
- 겹침 발화도 처리할 수 있다.
- EEND보다 실제 대화 상황에 가까워진다.

한계:

- 기본적으로 전체 입력을 보고 판단하는 offline 성격이 강하다.
- 긴 회의를 실시간으로 계속 처리하는 문제는 아직 남아 있다.

쉽게 말하면:

> EEND-EDA는 "EEND에 화자 자리 생성기를 붙여서, 몇 명인지 더 유연하게 맞히는 방식"이다.

## 5. BW-EDA-EEND

BW-EDA-EEND는 EEND-EDA를 streaming에 더 가깝게 만든 방식이다. BW는 Block-wise를 뜻한다.

핵심 아이디어:

- 전체 오디오를 한 번에 넣지 않는다.
- 오디오를 블록 단위로 나눠 처리한다.
- 이전 블록의 정보를 다음 블록으로 넘긴다.

흐름:

> 10초 블록 처리 → 이전 블록 상태 저장 → 다음 블록 처리 → 화자 연결 유지

왜 필요한가:

- 긴 회의 전체를 한 번에 모델에 넣으면 계산량이 너무 커진다.
- 라이브에 가까운 처리를 하려면 오디오가 들어오는 순서대로 처리해야 한다.

장점:

- EEND-EDA보다 online 처리에 가깝다.
- 긴 오디오를 더 현실적으로 다룰 수 있다.
- 블록 사이 상태를 이용해 화자 연결을 유지하려고 한다.

한계:

- 블록 경계에서 같은 화자를 다른 사람처럼 볼 수 있다.
- latency를 줄일수록 앞뒤 맥락이 줄어 정확도가 떨어질 수 있다.
- 완전한 long-form streaming 모델이라기보다는 중간 단계에 가깝다.

쉽게 말하면:

> BW-EDA-EEND는 "EEND-EDA를 긴 녹음에 쓰려고 오디오를 블록 단위로 읽는 방식"이다.

## 6. LS-EEND

LS-EEND는 Long-form Streaming End-to-End Neural Diarization의 줄임말이다.

목표:

> 긴 회의를 실시간으로 들으면서 누가 언제 말하는지 계속 출력한다.

LS-EEND의 핵심 요소:

- causal embedding encoder
  - 미래 오디오를 보지 않고 지금까지 들어온 정보로 판단한다.
- online attractor decoder
  - 새 화자가 나오면 새 화자 자리를 만든다.
  - 기존 화자가 다시 나오면 기존 자리를 업데이트한다.
- frame-in-frame-out
  - 오디오 프레임이 들어오면 결과 프레임을 계속 내보낸다.
- long-form 처리
  - 긴 회의에서도 계산량이 폭발하지 않도록 상태를 유지한다.

Minto2에서 LS-EEND가 필요한 이유:

- 녹음 중 화면에 화자 라벨을 바로 보여줘야 한다.
- 종료 후까지 기다릴 수 없다.
- 최종 정확도보다 낮은 지연 시간이 중요하다.

쉽게 말하면:

> LS-EEND는 "회의가 진행되는 동안 바로바로 듣고, 새 사람이 나오면 새 칸을 만들고, 기존 사람이 다시 말하면 그 칸을 업데이트하는 방식"이다.

## 7. EEND 계열 발전 흐름

| 계열 | 핵심 질문 | 답 |
|------|-----------|----|
| EEND | 클러스터링 없이 직접 맞힐 수 있나? | 시간별 화자 활동표를 신경망이 직접 출력한다. |
| EEND-EDA | 몇 명인지 모를 때도 되나? | attractor로 필요한 화자 자리를 만든다. |
| BW-EDA-EEND | 긴 오디오를 순차 처리할 수 있나? | 블록 단위로 처리하고 이전 상태를 넘긴다. |
| LS-EEND | 긴 회의를 진짜 streaming으로 처리할 수 있나? | online attractor와 frame-in-frame-out 구조를 쓴다. |

## 8. `.ami`는 무엇인가

`.ami`는 EEND 계열 이름이 아니다. Minto2가 쓰는 FluidAudio LS-EEND 안에서 고르는 model variant다.

관계는 이렇게 보면 된다.

- `LS-EEND` = 모델 구조와 실행 방식
- `.ami` = 그 구조에 끼우는 학습된 모델 가중치
- `.dihard3` = 같은 구조에 끼우는 다른 학습된 모델 가중치

비유:

- LS-EEND = 게임기 본체
- `.ami` = 회의실 대화에 맞춘 게임팩
- `.dihard3` = 더 어렵고 다양한 녹음 환경에 맞춘 게임팩

FluidAudio에서 현재 노출하는 LS-EEND variant는 네 가지다.

| variant | 모델 이름 | 이해하기 쉬운 성격 |
|---------|-----------|-------------------|
| `.ami` | `ls_eend_ami` | 회의실 대화 계열 |
| `.callhome` | `ls_eend_ch` | 전화 대화 계열 |
| `.dihard2` | `ls_eend_dih2` | DIHARD II 난환경 계열 |
| `.dihard3` | `ls_eend_dih3` | DIHARD III 난환경 계열 |

각 variant는 step size와도 조합된다.

- `100ms`
- `200ms`
- `300ms`
- `400ms`
- `500ms`

따라서 실제 모델 번들은 개념적으로 다음처럼 늘어난다.

- `ls_eend_ami_100ms`
- `ls_eend_ami_500ms`
- `ls_eend_dih3_100ms`
- `ls_eend_ch_300ms`

Minto2의 현재 라이브 기본값은:

> LS-EEND + `.ami` + `100ms`

이다.

## 9. `.ami`와 `.dihard3` 차이

두 값은 알고리즘 자체를 바꾸는 것이 아니다.

둘 다:

- LS-EEND 구조를 쓴다.
- streaming 방식으로 동작한다.
- 오디오 프레임을 받아 시간별 화자 활동을 예측한다.

다른 점은:

- 어떤 데이터 성격에 맞춰 학습된 가중치를 쓰는가
- 어떤 상황에서 화자를 더 잘 나누는가

Minto2의 실제 회의 `선관위 부실 관리 원인과 선거 신뢰 회복 과제`에서는 다음처럼 나왔다.

| 경로 | 검출 화자 수 |
|------|--------------|
| LS-EEND `.dihard3` streaming | 2명 |
| LS-EEND `.ami` streaming | 4명 |
| 종료 후 VBx | 5명 |

해석:

- `.ami`는 이 회의의 라이브 화면에서는 `.dihard3`보다 낫다.
- 그래도 종료 후 VBx의 5명에는 못 미친다.
- 따라서 `.ami`는 라이브 기본값으로 적합하지만, 최종 회의록 보정까지 대체할 정도는 아니다.

## 10. LS-EEND와 VBx 차이

LS-EEND와 VBx는 같은 문제를 풀지만 접근이 다르다.

| 항목 | LS-EEND streaming | VBx |
|------|-------------------|-----|
| 실행 시점 | 녹음 중 | 녹음 종료 후 |
| 처리 방식 | 신경망이 시간별 화자 활동을 직접 예측 | 목소리 특징을 뽑고 비슷한 것끼리 묶음 |
| 강점 | 빠른 반응, 라이브 UI 가능, 겹침 표현에 유리 | 전체 맥락 사용, 최종 품질 안정적 |
| 약점 | 뒤쪽 오디오를 못 보고 판단, 결과가 흔들릴 수 있음 | 실시간 표시에는 부적합 |
| Minto2 역할 | 라이브 화면 화자 라벨 | 최종 회의록 화자 보정 |

정리하면:

> LS-EEND는 "지금 보이는 화면"을 위한 빠른 판단자고, VBx는 "회의가 끝난 뒤 회의록"을 위한 최종 정리자다.

## 11. 화자분리 결과를 전사 문장에 붙이는 단계

화자분리 모델이 만든 것은 "누가 언제 말했나"라는 시간표다. 하지만 회의록에서 사용자가 보는 것은 "이 문장은 누가 말했나"다. 둘 사이에는 한 번 더 정렬 단계가 필요하다.

Minto2에는 세 종류의 시간 정보가 있다.

- `Segment.timestamp`와 `duration`
  - 전사 청크 전체의 시작/길이.
- `Segment.words`
  - WhisperKit이 만든 단어별 시작/끝 시간.
  - 각 단어 시간은 청크 안에서의 상대 초다.
- `DiarizedSpeakerSegment`
  - VBx나 LS-EEND가 만든 화자별 시작/끝 시간.
  - 오디오 전체 기준의 절대 초다.

예전 방식은 `TranscriptSpeakerMatcher`가 전사 청크 전체와 화자 구간을 겹쳐 봤다.

> 전사 청크 1개 → 가장 많이 겹친 화자 1명

이 방식은 빠르고 단순하지만, 한 청크 안에 여러 화자가 섞이면 짧게 끼어든 화자가 사라질 수 있다.

현재 저장/파일 임포트 경로는 `SentenceSpeakerSplitter`가 한 단계를 더 수행한다.

> 전사 청크 → 단어별 시간 확인 → 각 단어를 화자 시간표에 배정 → 화자 전환/문장 경계/침묵 gap에서 분할 → 문장 단위 화자 세그먼트 저장

예를 들면:

| 단어 | 단어 시간 | 화자분리 시간표와 겹침 | 배정 |
|------|-----------|------------------------|------|
| 이번 | 0.2~0.7초 | 화자 A 구간 | 화자 A |
| 안건은 | 0.8~1.2초 | 화자 A 구간 | 화자 A |
| 제가 | 3.2~3.5초 | 화자 B 구간 | 화자 B |
| 볼게요 | 3.6~4.1초 | 화자 B 구간 | 화자 B |

그러면 저장 회의록은 다음처럼 나뉠 수 있다.

> `화자 A` 이번 안건은
>
> `화자 B` 제가 볼게요

중요한 점:

- 라이브 화면은 여전히 미리보기라 청크 단위 라벨을 유지한다.
- 최종 저장/파일 임포트 결과만 문장 단위로 정밀화한다.
- 이유는 라이브 중 세그먼트를 계속 쪼개면 화면 깜빡임과 교정 배치 id 충돌이 생길 수 있기 때문이다.
- `words`가 없거나 화자분리 결과가 없으면 기존 청크 단위 결과를 그대로 둔다.

쉽게 말하면:

> 화자분리는 "시간표"를 만들고, `SentenceSpeakerSplitter`는 그 시간표를 전사 단어에 붙여서 사용자가 읽는 문장 단위 회의록으로 바꾼다.

## 12. 공부할 때 헷갈리지 않는 규칙

규칙 1:

> `EEND`, `EEND-EDA`, `BW-EDA-EEND`, `LS-EEND`는 모델 구조 또는 연구 계열 이름이다.

규칙 2:

> `.ami`, `.dihard3`, `.callhome`, `.dihard2`는 Minto2가 쓰는 FluidAudio LS-EEND의 학습된 variant 이름이다.

규칙 3:

> `.ami`는 LS-EEND와 경쟁하는 기술이 아니라 LS-EEND 안에서 고르는 모델 가중치다.

규칙 4:

> 라이브 품질과 최종 회의록 품질은 분리해서 판단해야 한다.

규칙 5:

> 검출 화자 수가 많다고 항상 좋은 것은 아니다. 화자 수 count와 실제 구간 배정 품질 DER은 별개다.

## 13. Minto2에서 이어서 볼 파일

- `Sources/Minto/Services/Diarization/StreamingSpeakerDiarizationProvider.swift`
  - LS-EEND streaming provider와 `.ami` 기본값.
- `Sources/Minto/Services/LiveSpeakerAssignmentUseCase.swift`
  - provider snapshot을 앱 상태로 반영하는 use case.
- `Sources/Minto/ViewModels/TranscriptionViewModel.swift`
  - 전사 segment와 live diarization segment를 시간으로 맞춰 UI 라벨을 갱신하는 곳.
- `Sources/Minto/Services/Diarization/SentenceSpeakerSplitter.swift`
  - 저장/파일 임포트 결과를 word timestamp 기반 문장 단위 화자 세그먼트로 다시 나누는 곳.
- `docs/work/2026-06-29-sentence-level-speaker-attribution-research.md`
  - 문장 단위 화자 귀속 설계, critic 리뷰 반영, AB/e2e 측정 결과.
- `docs/work/lseend-streaming-api-notes.md`
  - FluidAudio `LSEENDDiarizer` API를 Minto2 관점에서 정리한 노트.
- `docs/benchmark/2026-06-22-lseend-vs-vbx-count.md`
  - LS-EEND와 VBx의 화자 수 및 품질 해석.
- `docs/work/2026-06-25-live-diarization-ami-experiment.md`
  - `.ami`를 라이브 기본값 후보로 선택한 실제 실험 기록.

## 14. 추천 학습 순서

1. 먼저 화자분리 출력표를 이해한다.
   - 시간별로 어떤 화자가 말하는지 표시하는 문제다.
2. 전통적 클러스터링과 EEND의 차이를 이해한다.
   - "나중에 묶기"와 "바로 예측하기"의 차이다.
3. EEND에서 EEND-EDA로 넘어간 이유를 본다.
   - 화자 수를 유연하게 만들기 위해 attractor가 등장한다.
4. BW-EDA-EEND에서 streaming 문제가 왜 어려운지 본다.
   - 블록 경계와 latency가 핵심이다.
5. LS-EEND가 long-form streaming을 어떻게 목표로 삼는지 본다.
   - online attractor와 frame-in-frame-out이 핵심이다.
6. `.ami`와 `.dihard3`를 본다.
   - 이들은 구조 이름이 아니라 LS-EEND의 학습된 모델 선택지다.
7. 마지막으로 `SentenceSpeakerSplitter`를 본다.
   - 화자분리 시간표를 전사 단어와 문장에 붙이는 제품 단계다.

## 15. 참고 자료

논문:

- End-to-End Neural Speaker Diarization with Self-attention: https://arxiv.org/abs/1909.06247
- End-to-End Speaker Diarization for an Unknown Number of Speakers with Encoder-Decoder Based Attractors: https://arxiv.org/abs/2005.09921
- Encoder-Decoder Based Attractors for End-to-End Neural Diarization: https://arxiv.org/abs/2106.10654
- BW-EDA-EEND: Streaming End-to-End Neural Speaker Diarization for a Variable Number of Speakers: https://arxiv.org/abs/2011.02678
- LS-EEND: Long-Form Streaming End-to-End Neural Diarization with Online Attractor Extraction: https://arxiv.org/abs/2410.06670

로컬 구현:

- FluidAudio `ModelNames.LSEEND.Variant`: `.build/checkouts/FluidAudio/Sources/FluidAudio/ModelNames.swift`
- FluidAudio `LSEENDDiarizer`: `.build/checkouts/FluidAudio/Sources/FluidAudio/Diarizer/LS-EEND/LSEENDDiarizer.swift`
- Minto2 live provider: `Sources/Minto/Services/Diarization/StreamingSpeakerDiarizationProvider.swift`
