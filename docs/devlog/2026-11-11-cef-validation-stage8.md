# CEF 검증 8차: 실제 응답 보류와 browser 종료

## 범위와 결과

7차의 Swift 응답 순서 시험을 실제 CEF 앱으로 확장했다. CEF가 반환한 정책 응답을 native observer에서 보관해 Swift는 적용 대기 상태로 유지하고, CloseBrowser(false)와 OnBeforeClose를 거친 뒤 보관한 응답을 전달했다.

[실행 결과](../../validation/cef-spike/evidence/privacy-stage8-20261111-103957/results.json): **9/9 항목 통과**, 앱 종료 코드 0, CefShutdown 반환, 네트워크 서비스 재시작 0회. 원격 디버깅 포트는 설정하지 않았고 listening 로그도 없었다. [집계](../../validation/cef-spike/evidence/stage8-summary.json)에 종료·로그 순서 확인 결과를 함께 기록했다.

## 구현과 관측

- [Stage8Probe.mm](../../validation/cef-spike/Stage8Probe.mm): 검증 전용 Probe.hold/status/close 명령을 추가했다. Swift 정책 응답만 보관하며 일반 관측 명령은 계속 처리한다.
- 종료 시 observer 등록·browser 참조를 해제하고 native 명령 ID 매핑을 비운다. Swift 서비스는 7차 수정본을 그대로 사용한다.
- OnBeforeClose 이후 100ms 지연 작업에서 실제 보관 응답을 Swift에 전달한다. CefRefPtr로 검증 client를 유지하여 이미 해제된 메모리에 접근하는 시험이 되지 않도록 했다. 이어 같은 client의 Send를 호출해 browser 참조가 없으면 CEF를 호출하지 않고 반환하는지 확인한다.
- [privacy-stage8.py](../../validation/cef-spike/privacy-stage8.py)는 정책 응답이 실제 보관됐고 ready=false인 것을 확인한 뒤 첫 browser를 닫는다. 다른 browser가 계속 ready 상태이고, fixture 탐색과 JavaScript 실행 및 정책 변경을 수행하는지 검사한다.

runtime 로그에서 `POLICY_REPLY_HELD → BROWSER_BEFORE_CLOSE → LATE_REPLIES_DELIVERED slot=0 → QUEUED_SEND_DROPPED slot=0` 순서를 확인했다. 종료된 Swift 서비스는 늦은 응답 이후에도 ready=false였다. 마지막 browser는 기존 제목 callback을 통한 정상 종료 경로로 닫혔다.

## 해석과 한계

**실제 CEF 명령과 종료 callback을 사용했지만, 늦은 응답 시점은 검증 코드가 의도적으로 만든 것이다.** CEF 자체가 해제된 observer에 callback을 호출했다고 주장하지 않는다. 정책 명령은 엔진에서 이미 실행됐고 Swift가 응답을 아직 받지 못한 상황을 검증했다.

종료 후 Send 시험도 OnBeforeClose에서 예약한 검증용 작업이다. 모든 종류의 종료 전 큐 작업·renderer crash·메모리 해제 경합을 포괄하지 않는다. client를 보유한 상태의 방어 경로를 검증했으며 use-after-free 검출 도구나 장시간 반복 부하는 실행하지 않았다. slot 재사용 후 이전 browser 이벤트의 세대 구분, beforeunload 거부·종료 취소는 남아 있다.

새 기능 결함은 이번 실행에서 발견되지 않았다. 명령 매핑 정리와 시험 후킹은 별도 adapter에만 추가했다. G09의 부분 근거를 보강했으며 전체 게이트 또는 제품 탭 종료의 완전한 통과로 판정하지 않는다.

## 재현과 보존

기존 CEF wrapper가 준비된 프로젝트 루트에서:

```sh
python3 validation/cef-spike/build-stage8-probe.py
validation/cef-spike/.venv/bin/python validation/cef-spike/privacy-stage8.py
```

macOS arm64, Swift 6 모드, 기존 CEF 156.0.27 배포본과 sandbox helper를 사용했다. 별도 앱·프로필·로그를 생성했고 기존 단계 자료는 보존했다. 성공 실행 폴더에 최종 소스 스냅샷을 남겼다. 강제 프로세스 종료나 프로필 삭제는 수행하지 않았다.

## 검증을 언제 끝낼 것인가

차수마다 세부 문제 하나씩 추가하는 방식은 남은 규모를 파악하기 어렵다. [설계 검증 문서](../design-validation.md)의 4절에 9~12차 목표를 개인정보·로그인, 탐색·검색, 권한·보안, UI·안정성으로 묶고 G01~G09와 연결했다.

12차는 채택 판단을 정리하는 목표이며 무조건 통과시키는 기한이 아니다. 미해결 항목은 채택 보류 사유와 추가 작업으로 명시한다. 현재 결과만으로 실제 로그인·OAuth·권한·네이티브 UI가 가능하다고 확정하지 않는다. PRD나 기술 설계의 요구 범위를 축소하지 않았다.
