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
| 6 | 2026-06-09 | [LLM/Search/Export 확장 구현 시작](work-log/2026-06-09-06-llm-search-export-expansion-start.md) | provider/search/export/glossary/file/system audio/mixed audio/local LLM/benchmark/keychain reconnect/SecretStore 병렬 통합 |
| 7 | 2026-06-09 | [Local LLM Ollama 설치 모델 조회](work-log/2026-06-09-07-local-llm-ollama-model-discovery.md) | Ollama `/api/tags` 설치 모델 picker, 모델 확인 상태, 실패 fallback 테스트 |
| 8 | 2026-06-10 | [Settings AI/Glossary UX 정리](work-log/2026-06-10-08-settings-ai-glossary-ux.md) | 검색 답변 연결 위치 정리, 로컬/API 안내, 용어집 입력 폼 개선 |
| 9 | 2026-06-10 | [Settings AI 통합과 용어집 예산 표시](work-log/2026-06-10-09-settings-ai-unified-glossary-budget.md) | 검색 답변 AI를 기본 AI 연결과 통합, 로컬 LLM 프리셋, 용어집 묶음/1,200자 예산, 새 회의 버튼 유지 |
| 10 | 2026-06-10 | [Settings 모델 선택 안내 정리](work-log/2026-06-10-10-settings-model-selection-clarity.md) | 로컬 LLM 모델 입력 중복 제거, 고급 설정 클릭 영역 확대, API 모델 선택 안내 개선 |
| 11 | 2026-06-10 | [Provider 모델 카탈로그 갱신](work-log/2026-06-10-11-provider-model-catalog-refresh.md) | API key provider 기본 모델과 직접 입력 예시를 현재 공식 모델 ID로 갱신 |
| 12 | 2026-06-10 | [계정 provider 모델 카탈로그 갱신](work-log/2026-06-10-12-account-provider-model-refresh.md) | GPT/Gemini/Copilot 계정 로그인 모델 목록 갱신, 최신 모델 실패 시 안정 모델 폴백 |
| 13 | 2026-06-11 | [용어집 별칭 자동 수집](work-log/2026-06-11-13-alias-auto-collect.md) | 교정 diff 기반 alias 제안, 저장소 pendingAliases, 설정 UI 승인/무시, 후보 LLM 프리필 |
| 14 | 2026-06-12 | [별칭 자동 수집 리뷰 반영](work-log/2026-06-12-14-alias-auto-collect-review-fixes.md) | dismissed alias 영속 차단, 혼재 alias 거부, 프리필 예산/파싱/덮어쓰기 방어 |
| 15 | 2026-06-12 | [Confluence 연결 설정 UX 개선](work-log/2026-06-12-15-confluence-connection-validation-ux.md) | 연결 확인 성공 후 연동 저장, 검색 실패 사유 분리, 입력창 클릭 영역 확대 |
| 16 | 2026-06-12 | [회의 시작 용어집 묶음 선택](work-log/2026-06-12-16-glossary-set-selection.md) | 회의 시작/파일 임포트 용어집을 분류 선택 + 직접 입력 방식으로 개편 |
| 17 | 2026-06-12 | [용어집 묶음 선택 리뷰 반영](work-log/2026-06-12-17-glossary-set-selection-review-fixes.md) | 선택 UI disabled-only 분류 제외, defaults 주입, 선택 영속 helper 공유 |
| 18 | 2026-06-12 | [진단 로그 정비](work-log/2026-06-12-18-diagnostic-log-cleanup.md) | OAuth 실패 body prefix, 모델/provider 변경, 검색 답변 생성 결과를 민감 원문 없이 기록 |
| 19 | 2026-06-12 | [파일 임포트 교정 병렬 파이프라인](work-log/2026-06-12-19-file-import-correction-pipeline.md) | LLM 교정을 STT 뒤에 숨기는 동시 상한 파이프라인으로 임포트 wall-clock을 STT 시간으로 수렴 |
| 20 | 2026-06-12 | [Silero VAD 승격](work-log/2026-06-12-20-silero-vad-promotion.md) | 검증 조합(Silero+빈 구간 복구)을 설정 기반 기본값으로, 모델 자동 다운로드·Energy fail-soft |
| 21 | 2026-06-12 | [녹음 오디오 보존](work-log/2026-06-12-21-recording-audio-retention.md) | 화자분리 1단계 — 녹음 WAV 로컬 보존, 보관 기간 정리, 회의 삭제 연동, 스키마 하위 호환 |
| 22 | 2026-06-13 | [임포트 교정 배치화](work-log/2026-06-13-22-import-correction-batching.md) | 청크 3개를 한 LLM 호출로 — 호출 수 1/3, 번호 파싱 fail-soft, 배치 경계 문맥 |

## 남은 과제

- [x] OAuth 3종 검증: **Codex ✅ / Gemini ✅ / Copilot ⚠️ 코드 정상이나 계정에 Copilot 구독 없어 404** (구독 시 재시도하면 동작, `noSubscription` 에러로 안내)
- [x] `VADProcessorTests` 기존 실패 수정 (`maxChunkDuration` 5s↔15s 불일치, 이번 작업과 무관한 선재 실패)
- [ ] 교정 품질 튜닝 — 과교정 방지 효과를 실제 회의 음원에서 재측정
- [ ] 회의 시작 시트 UI 흐름 직접 확인 (헤드리스 불가, `[Meeting]` 로그로 입력 캡처는 검증 가능)
