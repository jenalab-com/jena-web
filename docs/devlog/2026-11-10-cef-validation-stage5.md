# CEF 검증 5차: 네이티브 명령 경로·기존 iframe·다중 인스턴스·재실행

## 목적과 구현 범위

4차의 쿠키 제어를 원격 디버깅 WebSocket 없이 실행할 수 있는지 확인했다. Swift 진입점과 Objective-C++ CEF adapter를 사용하는 별도 검증 앱을 추가했다. 기존 단계의 소스·번들·프로필은 보존했다.

- [NativePolicyProbe.mm](../../validation/cef-spike/NativePolicyProbe.mm): 최상위 명령은 CefBrowserHost::ExecuteDevToolsMethod, sessionId가 있는 iframe 명령은 SendDevToolsMessage로 전달한다. AddDevToolsMessageObserver에서 결과·이벤트를 받는다.
- [privacy-stage5.py](../../validation/cef-spike/privacy-stage5.py): 동일한 쿠키 fixture를 사용하며 테스트 전용 파일 mailbox로 네이티브 adapter를 호출한다.
- [빌드](../../validation/cef-spike/build-native-policy-probe.py): 별도 native-policy-probe-v3 앱을 만든다. sandbox helper를 유지하고 remote_debugging_port=0으로 고정한다.

파일 mailbox는 검증용 전달 수단이다. 제품 UI에 범용 명령 실행 권한을 제공하는 설계가 아니다. 정책 순서와 재적용 로직은 아직 Python 시험 드라이버가 수행한다. **Swift 제품 PolicyService·설정 UI 구현 완료로 해석하지 않는다.**

## 결과 요약

| 실행 | 내용 | 검증 | 앱 종료 | 네트워크 재시작 |
|---|---|---:|---:|---:|
| [새 프로필](../../validation/cef-spike/evidence/privacy-stage5-20261110-235246/results.json) | 두 인스턴스 허용·차단 반복, 기존 iframe 변경 | 58/58 | 0 | 0 |
| [같은 프로필 재실행](../../validation/cef-spike/evidence/privacy-stage5-20261110-235338/results.json) | 저장 쿠키 확인, 저장 정책 재적용 | 16/16 | 0 | 0 |

[집계](../../validation/cef-spike/evidence/stage5-summary.json). 두 성공 실행 모두 CefShutdown 반환을 확인했고 DevTools listening 로그는 없었다. 설정과 코드에서도 원격 디버깅 포트를 사용하지 않는다. 시스템 전체의 모든 포트가 닫혀 있다는 의미는 아니다.

74개는 본 fixture의 확인 항목 수다. 제품 요구 74개가 완료됐다는 뜻은 아니다. 초기 진단 실패 2회는 이 통과 집계에서 제외하고 아래에 기록했다.

## 1. 네이티브 경로

최상위 Runtime·Page·Network·Target·Storage 명령과 iframe 세션 메시지가 CEF adapter를 통과했다. observer로 받은 자동 연결 이벤트를 사용해 iframe을 pause → 정책 적용 → resume했다. 4차에서 확인한 읽기·쓰기·요청 Cookie·응답 Set-Cookie·직접 재방문 저장 여부가 같은 방식으로 동작했다.

시험 코드의 명령 로그에는 fixture 주소와 스크립트가 포함된다. 제품 로그에 검색어·방문 URL·인증 정보를 남기도록 허용하는 변경이 아니다. 테스트용 파일 채널과 상세 명령 로그를 제품에 그대로 옮기지 않는다.

## 2. 기존 iframe 정책 변경

두 인스턴스 각각에서 허용 상태로 로드한 iframe을 유지한 채, 최상위와 iframe target에 차단 정책을 적용했다.

- **새로고침 전:** 기존 쿠키 fixture·response_0·js_0가 JS에서 계속 읽혔다.
- **같은 iframe 새로고침 후:** 최초 JS 읽기·쓰기 후 읽기·초기 서버 요청·후속 요청의 쿠키가 모두 비어 있었다.
- first-party 직접 재방문에서는 원래 허용 상태에서 저장된 쿠키가 보존됐다. 차단 정책 변경은 기존 쿠키 삭제와 다르다.

제품 설계에 주는 제약: 현재 API 경로에서는 정책 저장과 이미 열린 페이지의 적용 완료를 구분해야 한다. 새로고침 필요 여부를 표시해야 하며, 사용자 입력이 있는 페이지를 임의로 새로고침하는 정책은 이번 검증으로 승인하지 않는다. 새 target에는 실행 전 정책을 적용한다.

## 3. 여러 탭을 위한 기초 검증

탭을 대신하는 두 CEF browser 인스턴스를 별도 AppKit 창에 띄우고 같은 프로필을 공유했다. 각 인스턴스에서 허용→차단→허용→차단을 검사했다. 둘 다 동일한 결과를 보였고 마지막 browser가 닫힌 후 CEF를 종료했다.

이는 **다중 browser 객체의 명령 라우팅·상태 분리 검증**이다. 실제 탭 바·전환 UI·드래그·포커스 품질은 구현하거나 검증하지 않았다. 두 인스턴스를 동시에 실행하되 시험 명령은 순차 적용했으므로 원자적인 전체 탭 정책 변경이나 경합을 검증한 것도 아니다.

## 4. 재실행과 정책 재적용

첫 성공 실행이 test-policy.json에 남긴 restricted=true를 다음 실행에서 읽고 동일 프로필을 재사용했다. 첫 인스턴스가 B를 방문했을 때 이전 fixture 쿠키가 남아 있음을 새 쿠키 생성 전에 확인했다. 두 번째 인스턴스는 같은 공유 프로필의 쿠키를 확인한다.

테스트 드라이버가 저장값을 읽어 native API로 정책을 다시 적용한 후 두 인스턴스의 차단이 동작했다. Chromium이 이 DevTools 정책을 자동으로 영구 저장했다고 주장하지 않는다. 제품의 Swift 설정 저장·로드·적용 완료 대기·실패 처리 경로는 별도로 구현·검증해야 한다.

테스트 서버 포트는 실행마다 달라지지만 쿠키는 host 범위여서 보존 여부를 검사할 수 있었다. 사이트 로그인 서버, LocalStorage 기반 인증, 세션 쿠키 종료·만료는 이번 재실행 시험 범위가 아니다.

## 초기 진단 실패와 수정

처음 두 실행은 browser 생성 이후 첫 명령 결과를 받지 못했다. 진단 로그에서 CEF API 호출 전 파일 입력이 갱신되지 않는 현상을 확인했다. 입력 스트림을 유지하고 EOF만 지우는 방식 대신, 파일을 다시 열고 처리한 byte offset부터 읽도록 바꾼 뒤 명령 전달이 정상화됐다. CEF API 미지원으로 판단할 근거는 아니었다.

- [첫 실패](../../validation/cef-spike/evidence/privacy-stage5-20261110-234940/results.json), [진단 실행](../../validation/cef-spike/evidence/privacy-stage5-20261110-235135/results.json)을 보존했다.
- 응답 채널로 종료하지 못해 LLDB에서 해당 검증 browser들에 CloseBrowser(false)를 요청했다. 성공 시험의 종료 경로와 구분한다.
- 남아 있던 진단 v2 프로세스는 성공한 대체 실행과 재실행 확인 후 해당 PID·실행 경로를 대조해 SIGTERM으로 종료했다. 개인 앱이나 다른 서비스를 종료하지 않았으며 테스트 프로필을 삭제하지 않았다.
- 초기 진단의 프로세스 종료 코드만으로 정상 생명주기 통과를 인정하지 않는다. 통과 근거는 수정 후의 callback·CefShutdown 로그다.

## 남은 항목과 판정

G05·G09의 부분 통과 범위를 확대했다. CEF 채택은 계속 잠정이다.

- 정책 오케스트레이션을 Swift 제품 서비스로 옮기는 작업과 UI의 적용 대기 상태
- 기존 iframe의 차단 해제, 전체 탭 동시 정책 변경, target 소멸·교체 중 명령 취소
- 중첩 iframe·worker·CHIPS·HttpOnly·사이트별 예외
- 프로필 데이터 삭제의 경합·기간·하위 도메인 경계
- 실제 로그인 사이트와 OAuth, 권한, IME·드래그·접근성·프레임 시간
- 이전 단계 네트워크 서비스 재시작의 원인 및 장시간 안정성

이번 두 성공 실행에서 재시작이 없었다는 사실만으로 이전 재시작 문제가 해결됐다고 단정하지 않는다.

## 재현

CEF wrapper 빌드와 기존 테스트 환경이 준비된 프로젝트 루트에서:

```sh
python3 validation/cef-spike/build-native-policy-probe.py
validation/cef-spike/.venv/bin/python validation/cef-spike/privacy-stage5.py
```

같은 프로필 재실행은 첫 results.json의 profile 경로를 JENA_STAGE5_PROFILE 환경변수로 지정한다. 이는 이 검증기가 생성한 프로필에만 사용한다. 각 결과 폴더에 최종 소스 스냅샷, fixture 자료와 mailbox·runtime 로그를 보존했다.
