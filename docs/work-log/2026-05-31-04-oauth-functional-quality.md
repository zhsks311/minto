# 세션 4 — OAuth 실제 동작화 + 교정 품질 측정

_2026-05-31 · 커밋 `460ec52`, `5850cd1`_

## 프롬프트 → 작업 내용

### "서비스 실행해줘" / "oauth 는 어디에서 할 수 있어?"

앱을 실행(`swift run minto2`)했으나, 메뉴바 전용 앱(`LSUIElement`)이라 **설정 창을 여는 진입점이 없어** OAuth UI에 도달 불가였음.

- `MenuBarView`에 `SettingsLink` 추가 → 설정 창 진입 가능
- `.accessory` 앱은 활성화가 안 돼 설정 창이 안 떠서, `simultaneousGesture`로 `NSApp.activate(ignoringOtherApps:)` 호출해 창을 앞으로 끌어옴
- 커밋: `460ec52`

### Codex 로그인·교정이 안 됨 (단계별 디버깅)

로그를 심어 단계마다 실제 응답을 확인하며 **9개 연쇄 버그**를 수정.

- 로그인: `interval` 타입 불일치(String "5" → Int), Keychain을 렌더링마다 읽어 권한창 폭주 → 메모리 캐싱(실행당 1회), 로그인 성공 후 UI 미갱신 → `objectWillChange.send()`
- 교정 API: 엔드포인트 `/v1/responses`→`/responses`, Cloudflare 회피 헤더(`originator`/`User-Agent`/JWT의 `ChatGPT-Account-ID`), 모델 `o4-mini`→`gpt-5.4-mini`, 필수 필드 `instructions`/`store:false`/`stream:true`, SSE(`response.output_text.delta`) 파싱
- 진단 교훈: 각 400 에러가 다음 요구사항을 정확히 알려줌. 로깅을 미리 심은 게 결정적
- 토큰이 담긴 200 응답 본문은 로그에서 제외(자격증명 누출 방지)

### "gemini 시도하니 ... doesn't comply with Google's OAuth 2.0 policy"

Gemini는 `redirect_uri`가 커스텀 스킴(`minto://`)이라 Google이 거부.

- gemini-cli 공개 클라이언트는 "데스크톱 앱" 타입 → **loopback 리디렉트만 허용**. `ASWebAuthenticationSession`(커스텀 스킴 전용)을 버리고 **로컬 BSD 소켓 서버**(`127.0.0.1:<포트>/oauth2callback`)로 교체, 시스템 브라우저로 인증
- 교정 500 원인: 응답 키 casing 버그(`cloudaiCompanionProject` → `cloudaicompanionProject`), 빈 projectId 자동 backfill, thinking 모델 출력 잘림 → `thinkingConfig.thinkingBudget=0` + `maxOutputTokens` 상향
- 커밋: `5850cd1`

### "sample 로 먼저 테스트" / "품질 정량 비교 해보자"

- `STTFileTests` 경로를 `sample/you/{audio,script}/`로 수정 + 전사→교정 통합 테스트 추가
- sample 오디오로 Codex·Gemini 교정 end-to-end 검증(둘 다 동작)
- 정량 비교 결과: **내용 CER은 교정 후 개선 없음/미세 악화(과교정), 포맷 CER만 소폭 개선**. CER은 띄어쓰기·문장부호(교정의 주 효과)를 제거하고 측정하므로 한계가 있음을 확인
