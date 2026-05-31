# Minto2 작업 로그 (인덱스)

세션별 상세 기록은 `work-log/` 아래 **`YYYY-MM-DD-NN-slug.md`** 파일에 있습니다.
이 인덱스는 전체 흐름 파악용이며, 필요한 세션만 열어 보세요.

> 새 세션 추가 규칙: `work-log/`에 `YYYY-MM-DD-<순번>-<slug>.md` 파일을 만들고, 아래 표에 한 줄 추가.

## 세션 목록

| # | 날짜 | 제목 | 한 줄 요약 |
|---|------|------|-----------|
| 1 | 2026-05-30 | [WhisperKit 실시간 전사 초기 구현](work-log/2026-05-30-01-whisperkit-realtime-init.md) | VAD·preview Task 분리, 할루시네이션 필터, 직접 커밋 방식 |
| 2 | 2026-05-30 | [g2 CER 측정 + noSpeechThreshold 튜닝](work-log/2026-05-30-02-g2-cer-nospeech-tuning.md) | g2 3,900쌍 harness, baseline 5.9% → 0.80에서 5.7% |
| 3 | 2026-05-31 | [LLM 후처리 교정 + OAuth 3종 연동](work-log/2026-05-31-03-llm-correction-oauth.md) | Gemini/Copilot/Codex OAuth + 비동기 교정 (추가만, 미검증) |
| 4 | 2026-05-31 | [OAuth 실제 동작화 + 교정 품질 측정](work-log/2026-05-31-04-oauth-functional-quality.md) | 설정 진입점, Codex 9개 수정, Gemini loopback, sample CER |
| 5 | 2026-06-01 | [회의 맥락 기반 후교정](work-log/2026-06-01-05-meeting-context-correction.md) | MeetingContext·CorrectionPrompt 중앙화+보수적 규칙, 회의 시작 시트 |

## 남은 과제

- [x] OAuth 3종 검증: **Codex ✅ / Gemini ✅ / Copilot ⚠️ 코드 정상이나 계정에 Copilot 구독 없어 404** (구독 시 재시도하면 동작, `noSubscription` 에러로 안내)
- [ ] `VADProcessorTests` 기존 실패 수정 (`maxChunkDuration` 5s↔15s 불일치, 이번 작업과 무관한 선재 실패)
- [ ] 교정 품질 튜닝 — 과교정 방지 효과를 실제 회의 음원에서 재측정
- [ ] 회의 시작 시트 UI 흐름 직접 확인 (헤드리스 불가, `[Meeting]` 로그로 입력 캡처는 검증 가능)
