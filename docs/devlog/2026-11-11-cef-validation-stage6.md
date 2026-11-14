# CEF 검증 6차: Swift 정책 서비스와 복원·실패 처리

## 범위와 결과

5차에서 Python이 담당하던 쿠키 정책 저장·로드·적용 순서와 iframe 자동 연결 처리를 Swift 서비스로 옮겼다. 기존 단계의 소스·프로필은 보존하고 별도 검증 앱을 추가했다. macOS arm64, Swift 6 모드, 기존 CEF 156.0.27 배포본과 sandbox helper를 사용했다.

| 실행 | 내용 | 확인 항목 | 앱 종료 코드 | 네트워크 서비스 재시작 |
|---|---|---:|---:|---:|
| [새 프로필](../../validation/cef-spike/evidence/privacy-stage6-20261111-000254/results.json) | 두 인스턴스 허용·차단 반복, 기존 iframe, 제거·재생성, 실패·복구 | 69/69 | 0 | 0 |
| [동일 프로필 재실행](../../validation/cef-spike/evidence/privacy-stage6-20261111-000511/results.json) | Swift 저장 정책 복원, 영속 쿠키, 제거·재생성, 실패·복구 | 27/27 | 0 | 0 |

[집계](../../validation/cef-spike/evidence/stage6-summary.json). 96개는 fixture 확인 항목 수이며 제품 요구 완료 개수가 아니다. 초기 실패 1회는 통과 집계에서 제외했다. 성공 실행 모두 원격 디버깅 포트 설정 없이 네이티브 경로를 사용했고 DevTools listening 로그는 없었다.

## 변경한 검증 코드

- [SwiftPolicyService.swift](../../validation/cef-spike/SwiftPolicyService.swift): MainActor에서 정책 JSON 저장·복원, root 및 iframe 정책 적용, 자동 연결, 상태·오류·재시도를 담당한다.
- [SwiftPolicyProbe.mm](../../validation/cef-spike/SwiftPolicyProbe.mm): CEF 명령 ID를 일원화하고 observer 응답을 원래 호출자 ID로 변환한다. Swift의 후속 명령은 CEF UI 작업 큐로 보낸다.
- [SwiftPolicyBridge.h](../../validation/cef-spike/SwiftPolicyBridge.h), [SwiftPolicyMain.swift](../../validation/cef-spike/SwiftPolicyMain.swift): Swift와 Objective-C++의 호출 경계와 진입점이다.
- [privacy-stage6.py](../../validation/cef-spike/privacy-stage6.py): 테스트용 mailbox로 정책 변경을 요청하고 브라우저 관측값을 검사한다. 쿠키 정책 API·자동 연결을 직접 조작하거나 정책 파일을 저장하지 않는다.

파일 mailbox와 범용 명령 인터페이스는 검증 전용이다. 제품 UI나 웹 콘텐츠에 제공하는 API가 아니다. 두 CEF browser를 별도 AppKit 창으로 실행했으며 실제 탭 UI를 구현한 것은 아니다.

## 확인한 동작

1. 초기 root 정책 적용과 자동 연결 설정이 완료된 뒤 검증기의 페이지 이동을 허용했다. 재실행 시 두 인스턴스 모두 첫 이동 전에 restricted=true, ready=true였다. Swift가 swift-policy.json을 직접 읽었다.
2. 허용·차단을 반복하며 iframe의 JS 쿠키 읽기·쓰기, 요청 Cookie, 응답 Set-Cookie와 first-party 재방문 결과를 확인했다. 기존 iframe은 정책 변경 직후 이전 쿠키를 읽었고 새로고침 후 차단됐다. 제품에서도 설정 저장과 현재 문서 반영을 구분해야 한다.
3. iframe 제거 후 Swift의 세션 수가 0이 됐고, 새 iframe에서는 차단이 유지됐다. 적용 완료 이후 제거한 시험이며 진행 중인 명령 취소 시험은 아니다.
4. 존재하지 않는 정책 명령으로 실패를 주입했다. policy-apply-failed가 노출되고 ready=false가 됐으며 검증용 Page.navigate가 policy-not-ready로 거절됐다. 정상 정책 재요청 후 두 인스턴스가 ready=true로 복구됐다. 모든 웹 탐색 경로의 차단을 증명하지는 않는다.
5. 동일 프로필의 영속 fixture 쿠키가 재실행 후 남아 있었다. 첫 인스턴스에서 새 쿠키 생성 전에 확인했다. 실제 사이트의 로그인 유효성·만료·서버 취소나 LocalStorage 기반 인증은 별도 검증 대상이다.

## 초기 실패와 수정

[초기 실행](../../validation/cef-spike/evidence/privacy-stage6-20261111-000048/results.json)은 확인 항목 실행 전에 실패했다. 해당 폴더에 수정 전 소스와 runtime 로그를 보존했다.

- Swift 서비스와 테스트 드라이버가 서로 다른 명령 ID 범위를 사용하면서 CEF의 증가하는 ID 요구와 충돌했다. 네이티브 adapter에서 wire ID를 발급하고 응답을 논리 ID로 복원하도록 변경했다.
- observer 콜백 안에서 바로 후속 명령을 보내 재진입 검사 오류가 발생했다. 후속 호출을 CefPostTask로 예약한 후 성공 실행에서 같은 오류가 재현되지 않았다.
- Swift 6 컴파일에서 C 포인터를 actor closure로 전달하는 오류가 발생했다. 콜백 진입 시 Swift String으로 복사한 뒤 MainActor 경계에 전달하도록 수정했다.

실패 실행의 종료 코드 0을 기능 통과로 집계하지 않았다. 이번 단계는 제목 변경을 통한 검증 앱의 정상 종료 경로를 사용했으며 강제 프로세스 종료나 테스트 프로필 삭제는 수행하지 않았다.

## 판정과 남은 위험

G05·G09의 부분 검증 범위를 확대했다. CEF 채택은 계속 잠정이며 제품 PolicyService 완성으로 판단하지 않는다.

- 적용 도중 target 소멸, 빠른 연속 정책 변경, browser 종료와 callback의 경합은 미검증이다. 현재 취소 코드는 pending 항목을 제거하지만 전체 적용 완료 집계를 끝내지 못할 가능성이 있다. 성공 실행의 cancelled 값도 0이다.
- 명령 응답 timeout, 저장 실패·손상 파일 복구, iframe 연결 단계별 실패는 추가 검증이 필요하다. 이번 실패 주입은 root 정책 명령에 한정했다.
- ready 상태의 이동 차단은 검증기의 Page.navigate 경로만 대상으로 한다. 실제 링크·리디렉션·새 창 및 일시 정지된 target의 실패 복구는 제품 탐색 계층에서 검증해야 한다.
- reloadRequired는 현재 revision 기반의 검증용 표시다. 문서별 실제 반영 여부를 추적하는 제품 상태 모델이 아니다.
- 중첩 iframe·worker·CHIPS·HttpOnly·사이트별 예외, 로그인·OAuth, 권한, IME·접근성·프레임 시간은 아직 남아 있다.
- 두 성공 실행에서 네트워크 서비스 재시작이 없었지만 이전 단계의 재시작 원인이 해결됐다는 근거는 아니다. CDP 정책 API의 실험적 성격도 남아 있다.

## 재현

기존 CEF wrapper와 테스트 환경이 준비된 프로젝트 루트에서 실행한다.

```sh
python3 validation/cef-spike/build-swift-policy-probe.py
validation/cef-spike/.venv/bin/python validation/cef-spike/privacy-stage6.py
```

동일 프로필 재실행은 첫 results.json의 profile 경로를 JENA_STAGE6_PROFILE에 지정한다. 이 검증기가 생성한 프로필만 사용한다. 성공 실행 폴더에 최종 소스 스냅샷과 결과·runtime·mailbox 로그를 보존했다. 설계 검증 문서 수정 전 원본은 docs/backups/before-stage6-status-*에 보존했다.
