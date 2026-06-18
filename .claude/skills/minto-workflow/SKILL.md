---
name: minto-workflow
description: Use when implementing, planning, reviewing, or QA-ing in minto2 (macOS Swift meeting-recorder) — minto-specific build/run/sign commands, plan location, AGENTS.md=CLAUDE.md symlink rule, and the macOS/SwiftUI GUI+QA automation playbook. Pairs with the global dev-workflow skill (multi-agent methodology). Skip for trivial edits and pure Q&A.
---

# Minto2 고유 작업 메모

**범용 방법론(구현=Codex 위임 / 리뷰=크로스모델 / 측정=main / Codex 호출 함정 / 리뷰 스케일 / teams 게이트 / where-it-lives)은 전역 `dev-workflow` 스킬을 따른다.** 여기엔 minto2 고유분만 둔다. **제약**(fail-soft·로깅 금지값·surgical·검증 게이트·아키텍처 경계·ADR 조건·워크트리 함정)은 `CLAUDE.md`(=`AGENTS.md` 심링크)에 있다.

## 빌드·실행·검증 (minto2)

- 컴파일/테스트 확인: `swift build --disable-sandbox --scratch-path /tmp/minto2-build` / `swift test --disable-sandbox --scratch-path /tmp/minto2-test [--filter <Suite>]`
- **앱 실행은 `./scripts/dev.sh run`** (빌드+서명+실행). **`swift run` 금지** — SPM이 adhoc 서명을 덮어써 Keychain ACL이 깨진다. "Minto2 Dev" 자가서명 인증서 필요.
- Codex는 SwiftPM을 샌드박스에서 못 돌리니 "구현만, 빌드 금지" 지시 → 검증은 워크트리에서 main이 직접.

## 거버넌스 단일 소스

- **`AGENTS.md`는 `CLAUDE.md` 심링크**다. Codex가 AGENTS.md를 자동 로드하므로 CLAUDE.md 원문을 결정적으로 받는다. **거버넌스 규칙 수정은 CLAUDE.md만 편집**(AGENTS.md는 자동 반영).
- 계획 산출물은 **`docs/work/` 단일 소스**(`.omc/plans/` 지양). 세션 로그 `docs/work-log/`, benchmark `docs/benchmark/`, ADR `docs/adr/`.

## macOS/SwiftUI GUI + QA 자동화 플레이북

**하이브리드(사용자 GUI 조작 + main이 저장 JSON 검증)가 신뢰도 최고.** 순수 자동화 함정:

- **⚠️ 워크트리 cwd 함정(1순위)**: `cd X && (./scripts/dev.sh run &)`의 `cd`가 백그라운드 서브셸에 안 먹혀 **엉뚱한 워크트리 바이너리**가 뜬다. 회의 데이터(`~/Library/Application Support/Minto/meetings`)는 **모든 워크트리 공유**라 화면엔 시드가 보여 정상 착각 → 기능만 없음. **"데이터 보인다 ≠ 올바른 빌드"**. `lsof -a -p <pid> -d cwd -Fn`로 확인, 절대경로 바이너리 직접 exec. (CLAUDE.md에도 명시)
- **프로세스명**은 `Minto`가 아니라 `.build/debug/minto2` — `pgrep -f '\.build/debug/minto2$'`. 이전 인스턴스 남으면 새 인스턴스가 조용히 종료.
- **가려진 창 캡처**: CGWindowList에서 owner=="minto2" 최대면적 윈도우 ID → `screencapture -x -o -l <WID>`(포커스 불필요). 윈도우 ID는 재렌더마다 바뀌니 캡처 전 재조회.
- **SwiftUI 버튼은 AX name 없음** → 이름 클릭 불가. 좌표는 `.help()` 속성으로(`buttons of group 1 of window 1`의 help). 코드에 `.help()`를 달면 자동화가 쉬워짐.
- **CGEvent 클릭/스크롤은 frontmost 선행 필수**: `-l` 캡처는 가려져도 찍히므로 "보인다=클릭 간다"는 착시. frontmost 없이 보낸 클릭은 앞 창(사용자 에디터)으로 간다. 매 클릭 직전 `set frontmost to true` + delay.
- **retina 2x 매핑**: `screencapture -l`은 2x 픽셀. 클릭 화면좌표 = 윈도우origin + (이미지픽셀/2).
- **저장 검증**: `MeetingStore.save`는 `<record.id>.json`(시드 파일명 무관). 시드→확인→테스트 파일+`<id>.json` 삭제로 원복.
- 2~3회 실패하면 중단하고 사용자에게 알린다(맹목 재시도·Cmd+W 금지 — 메인창 닫힘).
- **Pencil `batch_design`**: 함수/변수가 배치 호출 간 유지 안 됨 → 헬퍼는 매 배치마다 재정의.

## 관련

- 전역: `dev-workflow` 스킬(범용 방법론)
- 메모리: `codex-for-code-changes`(why), `diarization-feature-state` 등(기능 상태)
