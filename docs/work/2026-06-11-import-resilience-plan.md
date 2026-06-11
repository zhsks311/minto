# 2026-06-11 파일 가져오기 복원력 계획

## 목표

- 파일 가져오기 중 앱 종료로 진행 상태가 조용히 사라지는 문제를 막는다.
- 저장된 회의는 항상 미리보기 헤더에서 다시 요약할 수 있게 한다.
- 사용자에게 보이는 일부 안내/에러 문구의 종결 톤을 해요체로 맞춘다.

## 커밋 1: 파일 임포트 중단 보호

- `MeetingFileImportUseCase`
  - `pendingImportFileName` 마커 키와 UserDefaults 주입 지점을 추가한다.
  - running 상태 진입 시 파일명 마커를 저장하고, completed/failed/cancelled/idle 전이에서 제거한다.
  - 상태 전이마다 `isAnyImportRunning`을 갱신한다.
- `AppDelegate`
  - 종료 요청 시 진행 중인 파일 가져오기가 있으면 `NSAlert`로 종료 취소/강제 종료를 선택하게 한다.
- `MeetingLibraryView`
  - 시작 시 남은 마커를 감지해 좌측 가져오기 카드 영역에 안내 카드를 표시하고, 닫기 버튼으로 마커를 제거한다.
- 테스트
  - 시작→성공/실패/취소 마커 전이를 검증한다.
  - 시작 시 남은 마커 감지를 검증한다.
- 검증
  - `./scripts/dev.sh build`
  - `./scripts/dev.sh test`

## 커밋 2: 임포트 완료 알림과 다시 요약 버튼

- 파일 가져오기 성공 카드 문구를 완료 상태로 명확히 남긴다.
- 회의 미리보기 헤더에 `다시 요약` 보조 버튼을 추가한다.
- 기존 폴백 배너의 재요약 흐름을 공용 helper로 모아 중복 실행을 막는다.
- 검증
  - `./scripts/dev.sh build`
  - `./scripts/dev.sh test`

## 커밋 3: 사용자 노출 문구 톤 통일

- `rg '"[^"]*합니다\."' Sources/Minto --type swift` 결과 중 사용자 노출 에러/안내 문구만 해요체로 변경한다.
- 문구 검증 테스트가 있으면 함께 갱신한다.
- 검증
  - `./scripts/dev.sh build`
  - `./scripts/dev.sh test`

## 진행 상태

- 커밋 1: 완료
- 커밋 2: 완료
- 커밋 3: 진행 전
