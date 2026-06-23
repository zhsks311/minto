# 재조정 알고리즘 명세 (Task 0b)

저장 시 라이브 임시 라벨을 VBx 최종 라벨로 교체하는 규칙. ADR 0005 Decision 7~8.

## 입력
- **L** = 라이브 결과: transcript segment마다 임시 화자라벨(LS-EEND 기반) + 사용자 편집 여부 flag.
- **V** = VBx 최종 결과: 아카이브 믹스에 offline VBx 재실행 → `[DiarizedSpeakerSegment]`(authoritative, "화자 N" raw id + 시간).
- **A** = 앵커: 라이브에서 확정된 "나" 구간(채널 prior), 보이스프린트 매칭 결과.

## 출력
- 각 transcript segment의 **최종 화자 라벨**(VBx 기준, 가능하면 실명).

## 알고리즘
1. **VBx에 앵커 제약 전달**(최종 정확도용): "나" 구간을 known-speaker로, 등록 보이스프린트를 numSpeakers/known으로 VBx 호출에 반영(정확 파라미터는 Phase 4서 provider API에 맞춤). 아카이브가 믹스라 채널정보가 파일에 없으므로 **이 전달이 유일한 앵커→최종 경로**.
2. **transcript ↔ VBx 시간 바인딩**: 기존 `TranscriptSpeakerMatcher`(50% 겹침)로 각 transcript segment에 VBx 화자 배정 → 최종 라벨의 1차 소스.
3. **라이브 라벨 ID ↔ VBx 라벨 ID 매핑**(연속성·UI 전환용): 라이브 화자 L_i와 VBx 화자 V_j의 **시간 겹침 IOU** 행렬 계산 → **그리디 최대 매칭**(IOU 큰 쌍부터, 1:1). 동점은 더 이른 등장 우선. 매칭 안 된 라이브 라벨은 버림(VBx가 정답). 이 매핑은 "화면에 보이던 화자 2가 곧 김부장"의 연속성 표시에만 쓰고, **최종 배정은 2번(VBx)**.
4. **보이스프린트 실명**: VBx 화자 centroid에 `VoiceprintMatching.identifySpeakers`(θ=0.65) → 등록자면 실명 치환(`SpeakerLabelEditing.replacingSpeaker`).
5. **사용자 편집 보존**: transcript segment의 편집 flag=true면 **그 segment의 라벨은 고정**(2~4 적용 제외). 미편집 segment만 VBx 결과로 치환.

## 엣지
- VBx 실패 → 재조정 생략, 라이브 임시 라벨 그대로 저장(fail-soft, `Log.diarization.error`).
- VBx 화자수 ≠ 라이브 화자수 → 정상(VBx 우선). 매칭 안 된 화자는 신규 "화자 N".
- 빈 transcript/무발화 → no-op.

## 검증
- 단위: IOU 매핑(1:1·동점·미매칭), 편집 보존(편집 segment 불변), 보이스프린트 실명.
- 통합/QA: 저장 JSON에서 화자수·라벨이 VBx 기준인지, 편집 라벨 유지되는지.
