# CEF 검증 9차: 인증 유지·만료·삭제 경계

## 범위

7차의 Swift 정책 서비스와 native CEF 앱을 그대로 사용하고 인증·삭제 fixture를 추가했다. 제품 코드나 기존 검증 자료를 바꾸지 않았다. macOS arm64, Swift 6 모드, CEF 156.0.27 환경이다.

로컬 HTTPS 서버가 인증 토큰을 발급하고 유효 상태를 관리한다. 앱 종료·재실행 사이에도 서버와 포트는 유지한다. 테스트 토큰은 fixture 전용 문자열이며 실제 계정·비밀번호를 사용하지 않았다. 인증 상태를 앱이 따로 true/false로 저장하지 않고 서버 응답으로 판정한다.

## 로컬 인증 결과

[인증·삭제 실행](../../validation/cef-spike/evidence/privacy-stage9-20261111-104405/results.json): **26/26 항목 통과**. 같은 프로필로 앱을 두 번 실행했고 두 번 모두 정상 종료했다.

- 영속 HttpOnly 쿠키로 로그인한 상태는 앱 재실행 후에도 서버가 인증했다. 쿠키 값은 document.cookie에 노출되지 않았다.
- LocalStorage에 저장한 bearer 토큰도 같은 origin에서 재실행 후 유지됐고 서버가 인증했다.
- 서버가 토큰을 취소한 뒤에는 쿠키·LocalStorage가 남아 있어도 둘 다 인증되지 않았다. 저장 데이터의 존재를 유효 로그인으로 간주하면 안 된다.
- Max-Age 없는 세션 쿠키는 이번 앱의 정상 종료·재실행 후 요청에서 사라졌다. 모든 사이트의 세션 복원 정책을 뜻하지 않는다.
- Max-Age=2 쿠키는 발급 직후 인증됐고 3초 후 요청에서 사라져 인증되지 않았다. 로그아웃도 쿠키 제거·인증 실패로 반영됐다.
- 같은 프로필의 두 browser가 동일한 사이트 로그인을 공유했다.
- 타 사이트 iframe에서 HttpOnly 인증 쿠키가 허용 상태에서는 전송됐고 차단 상태에서는 인증되지 않았다. first-party 직접 방문의 로그인은 유지됐다.
- A의 cookies·local_storage 선택 삭제 후 A의 인증 쿠키와 LocalStorage가 없어졌다. B의 인증과 LocalStorage는 유지됐다.
- 삭제 후 열린 A 페이지가 다시 로그인 요청을 보내 데이터를 재생성할 수 있었다. 삭제 완료와 열린 페이지의 향후 쓰기 차단은 별도 동작이다.

## 분할 쿠키와 하위 도메인

[경계 실행](../../validation/cef-spike/evidence/privacy-stage9-boundaries-20261111-104512/results.json): **7/7 항목 통과**, 관측 결과는 별도로 저장했다.

서드 파티 쿠키 제한이 켜져 있어도 `Partitioned; Secure; SameSite=None` 쿠키는 A 안의 B iframe에서 저장·조회됐다. 최상위 사이트를 C로 바꾸면 같은 B iframe에서 그 쿠키가 보이지 않았고 A로 돌아오면 다시 보였다. 현재 정책은 **모든 서드 파티 쿠키를 제거하는 기능이 아니며 분할 쿠키는 허용한다.** 제품의 R12 표현과 설정 설명에 이 동작이 맞는지 확정해야 한다. 이번 결과만으로 CHIPS 삭제·인증 전체가 검증됐다고 판단하지 않는다.

A에 host-only 인증 쿠키와 `Domain=a.test` 공유 쿠키를 만들고 sub.a.test에도 host-only 인증 쿠키와 LocalStorage를 만들었다. A origin에 cookies·local_storage 삭제를 요청한 후:

| 관측 대상 | 결과 |
|---|---|
| A의 host-only 인증 쿠키 | 제거됨 |
| sub.a.test의 host-only 인증 쿠키 | 유지, 서버 인증 성공 |
| sub.a.test에서 보이는 Domain=a.test 공유 쿠키 | 유지 |
| sub.a.test LocalStorage | 유지 |

따라서 이 API 호출을 “a.test와 하위 도메인의 모든 데이터 삭제”로 표시하면 안 된다. origin·host·Domain 쿠키·사이트 단위의 삭제 범위가 서로 다르다. 제품에서 선택 삭제 범위를 정하고 공유 쿠키를 별도로 식별·처리하는 추가 검증이 필요하다. B의 first-party 인증이 보존된 것도 확인했다.

## 실제 제공처와 남은 게이트

사용자가 실제 로그인 호환성 우선 대상으로 **Google·네이버**를 지정했다. [공개 페이지 실행](../../validation/cef-spike/evidence/privacy-stage9-providers-20261111-104607/results.json)에서 두 호스트 접근과 초기 입력 폼 4/4 항목이 통과했다. 세 실행의 확인 항목 합계는 37개이며 앱은 총 4회 정상 종료했다. 네트워크 서비스 재시작은 없었다. 공개 로그인 페이지 초기 접근 시험과 실제 계정 인증은 구분한다. 비밀번호·OTP를 요청하거나 자동 제출하지 않는다.

G03·G04·G05의 부분 근거를 확대했다. G07 및 전체 CEF 채택은 아직 통과가 아니다. 다음 항목은 남아 있다.

- Google·네이버의 실제 사용자 인증, 추가 인증, 재실행 후 유지, OAuth 팝업·복귀
- 사이트별 서드 파티 예외 설정의 제품 정책·적용 경로
- 분할 저장소·분할 쿠키의 선택 삭제, 기간 삭제와 진행 중 쓰기 경합
- 삭제 시 하위 도메인·Domain 공유 쿠키의 정확한 포함 범위
- IndexedDB·service worker 기반 인증과 재생성: 이전 저장소 삭제 시험을 인증 통과로 확대하지 않음

로컬 인증 26개와 경계 7개의 통과는 이 항목들을 대신하지 않는다. 10차 탐색·검색·새 탭 묶음에서 인증 팝업 경로를 이어서 다루며, 실제 인증 완료는 사용자의 직접 입력이 필요한 별도 확인 항목이다.

## 재현과 보존

```sh
validation/cef-spike/.venv/bin/python validation/cef-spike/privacy-stage9.py
validation/cef-spike/.venv/bin/python validation/cef-spike/privacy-stage9-boundaries.py
validation/cef-spike/.venv/bin/python validation/cef-spike/privacy-stage9-providers.py
```

각 스크립트는 고유 증거 폴더와 프로필을 생성한다. 인증 시험은 동일 프로필로 재실행하며 mailbox만 별도 디렉터리로 분리한다. 테스트 종료를 기존 프로필 삭제나 다른 프로세스 종료 승인으로 해석하지 않았다. [집계](../../validation/cef-spike/evidence/stage9-summary.json)에 실행별 결과를 기록한다.
