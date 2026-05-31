# 세션 2 — g2 데이터셋 기반 CER 측정 + noSpeechThreshold 튜닝

_2026-05-30 ~ 05-31 · 커밋 `c4a15f3`, `f3e644c`_

## 프롬프트
> "테스트 음원과 스크립트를 준비해왔어. codex와 함께 이걸 어떻게 활용해서 전사를 개선할 수 있을 지 판단해줘."
> "CER이 뭐고, 어떻게 체크했는지 알려줘"
> "ㄱㄱ" (noSpeechThreshold 실험 진행)

## 작업 내용
- AI Hub 한국어 구어 말뭉치(g2) 3,900쌍 평가 harness 구현 (`STTG2Tests.swift`)
  - AI Hub 전사 규약 파서: `n/`, `b/`, `(표준형)/(발음형)` 처리
  - CER(Character Error Rate) = `editDistance(ref, hyp) / ref.count`
- 베이스라인 CER: **5.9%** (`noSpeechThreshold=0.90`)
- A/B 테스트 결과: **`noSpeechThreshold=0.80` → CER 5.7%** 최적 → `STTService.swift` 반영
