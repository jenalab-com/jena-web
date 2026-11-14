# CEF 검증 3차: 사이트 데이터 삭제와 서드 파티 쿠키

## 환경과 변경

기존 CEF 156.0.27 / Chromium 156.0.8078.88 / macOS arm64의 격리 검증 앱을 사용했다. 제품 코드·개인 프로필·시스템 hosts·인증서 저장소는 변경하지 않았다.

[HTTPS 검증기](../../validation/cef-spike/privacy-probe.py)와 [재현 안내](../../validation/cef-spike/PRIVACY-PROBE.md)를 추가했다. a.test와 b.test는 테스트 앱의 resolver 인자로만 127.0.0.1에 연결한다. 해당 실행에서 생성한 테스트 인증서의 SPKI만 허용하며 디버깅 endpoint는 loopback에서 사용했다. 고유 테스트 프로필·로그·인증서는 보존했다.

CEF 앱에는 테스트 환경변수로 시작 URL과 DevTools 포트를 지정하는 기능만 추가했다. 기존 2차 기본 실행은 유지한다. 프로필과 원본 소스는 삭제하지 않았다. 인증서 개인키는 0600으로 저장하며 검증용 자료를 제품 배포에 포함하지 않는다.

## 실제 결과

### G04 부분 통과: 원점별 선택 삭제

A와 B 각각에 다음 데이터를 만든 후 페이지에서 존재를 확인했다.

- Secure / SameSite=None 영속 쿠키
- LocalStorage 값
- IndexedDB 데이터베이스
- Cache Storage 항목
- service worker 등록

Storage.clearDataForOrigin으로 A의 위 데이터 종류를 삭제했다. 이후 실제 페이지 재방문에서 **A의 다섯 항목은 없어지고 B의 다섯 항목은 유지**됐다. 세 번의 실행에서 동일한 결과를 확인했다.

이는 지정한 두 origin과 데이터 종류에 대한 결과다. 기간 선택, 하위 도메인 공유 쿠키, CHIPS·partition key, HttpOnly, 동시 재생성, HTTP 캐시 전체까지 통과한 것은 아니다. IndexedDB는 DB 존재를 확인했으며 저장한 레코드 내용까지 검사한 시험은 아니다.

### G05 부분 검증: target별 정책 필요

| 설정과 관찰 | 서버가 받은 B 쿠키 | B iframe의 document.cookie | 판정 |
|---|---|---|---|
| 최상위 target에서 제한 해제 | 있음 | 있음 | 허용 기준 통과 |
| 최상위 target에서 제한 활성화 | 없음 | 있음 | 기대 차단 기준 실패 |
| 분리된 iframe target에도 제한 활성화 후 iframe 새로고침 | 별도 추가 측정 안 함 | 없음 | JS 읽기 차단 확인 |
| 최상위 target에서 해제 후 새 iframe 구성 | 있음 | 있음 | 허용 복귀 확인 |
| 이후 B를 first-party로 방문 | JS 읽기로 확인 | 있음 | B의 원래 쿠키는 보존 |

사용한 Network.setCookieControls는 실험적 CDP API다. 최상위 target 하나에만 적용하면 PRD의 일관된 쿠키 정책을 충족하지 못했다. OOPIF target을 별도로 attach해 같은 정책을 적용하고 새로고침하면 JS 읽기는 차단됐다.

이는 해결 경로에 대한 증거이며 최종 구현 완료가 아니다. 새 target에 코드 실행 전부터 정책을 적용하는 자동 연결, target 교체·정책 해제·여러 탭·worker·재실행·사이트 예외, JS 쓰기와 응답 Set-Cookie를 추가 검증해야 한다. 특히 쿠키를 읽을 수 있는 초기 구간이 없는지 확인해야 한다.

## 실행별 증거

1. [첫 실행](../../validation/cef-spike/evidence/privacy-20261110-232616/results.json): 선택 삭제 통과, 최상위 정책의 JS 읽기 차단 실패, 허용 복귀·first-party 보존 확인. 앱 정상 종료 0.
2. [두 번째 실행](../../validation/cef-spike/evidence/privacy-20261110-232740/results.json): 같은 실패 재현. iframe에서 Page.reload 호출은 top-level 전용이라는 오류로 추가 시험 중단. 앱 정상 종료 0. 오류를 성공 처리하지 않았다.
3. [세 번째 실행](../../validation/cef-spike/evidence/privacy-20261110-232833/results.json): iframe 자체 location.reload로 수정 후 JS 읽기 차단 확인. 최상위-only의 실패 사례가 포함되어 전체 status는 의도적으로 failed다. 앱 정상 종료 0.

각 실행의 소스 스냅샷 또는 현재 검증 코드와 runtime.log를 함께 보존했다. 검증 스크립트는 최종 수정에서 실패·예외·앱 종료 실패 시 exit 1을 반환하도록 했다. 초기 두 실행은 JSON status로 판정하며 프로세스 exit 0을 테스트 성공으로 해석하지 않는다.

## 발견한 문제와 한계

- 세 번째 실행의 [runtime.log](../../validation/cef-spike/evidence/privacy-20261110-232833/runtime.log)에 Network service crashed or was terminated, restarting service가 1회 기록됐다. 이후 검증은 진행되고 앱도 정상 종료했지만 안정성 원인은 미확인이다. 정상 상황으로 무시하지 않는다.
- 같은 실행에서 로컬 HTTPS 서버의 peer connection reset이 기록됐다. 네트워크 서비스 재시작과의 인과관계는 아직 확인하지 않았다.
- 원격 디버깅 WebSocket으로 Chromium 동작을 검증했다. 제품용 CefBrowserHost::ExecuteDevToolsMethod adapter로 통합한 시험은 아니다.
- sandbox helper 초기화는 유지했으나 보안 침투 시험이나 정식 서명·공증은 수행하지 않았다.

## 결정과 다음 검증

G04·G05 전체 통과나 CEF 최종 채택을 선언하지 않는다. 다음은 **OOPIF 생성 시점의 정책 적용과 JS 읽기·쓰기 / 서버 수신·응답 쿠키의 일관성**, **네트워크 서비스 재시작 원인과 재현성**이다. 이 경로를 제품 API adapter로 옮길 수 있는지도 확인한다. 실패를 이유로 Electron 전환, WebKit 변경, PRD 기능 축소는 수행하지 않는다.
