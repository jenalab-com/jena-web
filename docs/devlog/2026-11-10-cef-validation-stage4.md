# CEF 검증 4차: iframe 실행 전 쿠키 정책과 반복 안정성

## 목적·변경

3차에서 최상위 target에만 쿠키 차단을 적용하면 OOPIF의 JavaScript 읽기가 남았다. 이번에는 iframe 실행 전에 정책을 적용해 초기 접근 구간을 확인하고, 읽기뿐 아니라 쓰기·서버 응답·영속 저장 여부를 검증했다.

[4차 검증기](../../validation/cef-spike/privacy-stage4.py)를 별도로 추가했다. 기존 3차 검증기는 보존했다. CEF 앱 바이너리는 3차와 동일하며 제품 코드·개인 프로필·시스템 설정은 변경하지 않았다.

- Target.setAutoAttach에 waitForDebuggerOnStart와 flatten을 설정해 새 iframe을 자동 연결한다.
- attachedToTarget 이벤트를 받으면 Network.enable → Network.setCookieControls → 자식 target 자동 연결 설정 → Runtime.runIfWaitingForDebugger 순서로 처리한다.
- 각 iframe이 waitingForDebugger=true로 연결되고 정책 적용 응답을 받은 뒤 재개됐는지 기록한다.
- 최상위 페이지에는 iframe 생성 전부터 동일한 정책을 적용해 초기 네트워크 요청도 확인한다.
- HTTPS handshake는 accept 루프가 아닌 요청별 스레드에서 처리한다. 한 연결의 대기가 다른 연결을 막지 않도록 했으며 연결 오류를 따로 기록한다.

## 시험 구성

macOS arm64, Swift 진입점·CEF 156.0.27 / Chromium 156.0.8078.88, sandbox helper를 유지했다. 매 실행 새 프로필, loopback HTTPS 서버, 테스트 앱 전용 DNS·SPKI 설정을 사용한다.

한 실행에서 허용 → 차단 → 허용 → 차단의 4개 사례를 수행한다. 매 사례 B를 직접 방문해 쿠키를 초기화하고 first-party 쿠키 fixture 하나를 심은 뒤 A에 B iframe을 생성한다.

각 사례의 7개 확인 항목:

1. B 직접 방문에서 기준 쿠키 생성 확인
2. iframe 최초 요청에 서버가 받은 쿠키
3. iframe 최초 스크립트의 읽기와 응답 Set-Cookie 반영 여부
4. JavaScript 쿠키 쓰기 후 읽기
5. 같은 iframe의 후속 fetch에서 서버가 받은 쿠키
6. 새 iframe의 실행 일시정지·정책 적용·재개 순서
7. B를 다시 직접 방문해 쓰기·응답 쿠키가 실제 저장됐는지 확인

문자열 순서가 아니라 쿠키 이름 집합을 비교했다. 테스트용 쿠키만 사용한다. 부모 메시지는 B origin에서 온 것만 수신한다.

## 결과

| 실행 | 확인 항목 | 네트워크 서비스 재시작 | fixture 연결 오류 | 앱 종료 |
|---|---:|---:|---:|---:|
| [1회](../../validation/cef-spike/evidence/privacy-stage4-20261110-234348/results.json) | 28/28 통과 | 0 | 0 | 0 |
| [2회](../../validation/cef-spike/evidence/privacy-stage4-20261110-234428/results.json) | 28/28 통과 | 0 | 0 | 0 |
| [3회](../../validation/cef-spike/evidence/privacy-stage4-20261110-234459/results.json) | 28/28 통과 | 0 | 0 | 0 |

[집계 원본](../../validation/cef-spike/evidence/stage4-summary.json). 총 84개 확인은 같은 28개 시나리오를 3회 반복한 결과이며, 서로 다른 84개 기능 검증이 아니다.

**차단 상태:** 최초 요청·후속 fetch에 쿠키 없음, 최초 JS 읽기와 JS 쓰기 후 읽기 모두 비어 있음. B 직접 재방문에서는 기존 fixture만 남아 JS 쓰기와 응답 Set-Cookie가 저장되지 않았음을 확인했다.

**허용 상태:** 최초 요청에 fixture가 있고, 응답 쿠키와 JS 쓰기 쿠키가 읽기·후속 요청·직접 재방문에서 확인됐다. 차단 후 허용으로 돌아온 사례도 동일하게 동작했다.

검증기·테스트 앱 모두 종료 코드 0이며, 종료 callback과 CefShutdown 완료 로그를 보존했다. 앱·서버는 자신의 검증 생명주기로 종료했으며 강제 프로세스 종료나 프로필 삭제는 수행하지 않았다.

## 네트워크 재시작 조사

3차 해당 프로필 cef.log에서 재시작 직전에 다음 메시지를 확인했다.

```text
Terminating current process after 15 seconds with no connection.
Network service crashed or was terminated, restarting service.
```

이는 자식 프로세스 초기 연결 지연을 조사할 근거지만 원인 확정은 아니다. 해당 프로필 경로에서 dmp·ips 파일은 찾지 못했고, 사용자 DiagnosticReports에서도 Jena 이름의 보고서는 확인되지 않았다. 다른 경로나 수집되지 않은 진단 자료의 존재 가능성까지 부정하지 않는다.

4차의 3회에서는 재현되지 않았다. TLS 처리를 바꾼 것과 이 현상 사이의 인과관계는 확인하지 않았으므로 “서버 수정으로 해결”이라고 기록하지 않는다. 실제 배포 번들의 helper 시작 시간·서명·초기 연결을 추가 관찰할 필요가 있다.

## 판정과 한계

- **G05 부분 통과 확대:** 단일 탭·두 site·새 OOPIF·비분할 SameSite=None Secure 쿠키에 대해 실행 전 정책과 읽기·쓰기·송수신·저장 차단을 확인했다.
- 기존 iframe에 정책을 바꾸는 경우, 여러 탭, 중첩 iframe, worker, CHIPS, HttpOnly, 사이트 예외, 재실행 후 설정 복원은 이번 시험에 포함하지 않았다.
- 재귀 자동 연결 코드는 있으나 중첩 iframe fixture는 실행하지 않았다. 새 iframe 동작을 모든 target의 동작으로 일반화하지 않는다.
- pause→정책→resume이 사용자 체감 성능에 미치는 비용은 측정하지 않았다.
- Network.setCookieControls는 여전히 실험적 API다. CDP WebSocket으로 확인했으며 제품용 CEF native adapter 통합은 미검증이다.
- 3회 무재현은 장시간 안정성이나 이전 오류의 해결을 보장하지 않는다.

**다음 검증:** 제품에 원격 디버깅 포트를 열지 않고 CefBrowserHost::ExecuteDevToolsMethod와 observer로 동일 정책을 처리하는 경로, 기존 target·다중 탭·재실행의 일관성. CEF 최종 채택과 전체 G05 완료 판정은 보류한다.

## 재현

CEF 검증 앱 빌드와 privacy-requirements 설치 후:

```sh
validation/cef-spike/.venv/bin/python validation/cef-spike/privacy-stage4.py
```

기능 실패·예외·앱 종료 실패·네트워크 서비스 재시작 발생 시 exit 1이다. results.json의 status는 기능 결과이며 안정성은 networkServiceRestarts와 appExitCode를 함께 확인한다. 실행별 소스 스냅샷·인증서·로그·프로필을 보존했다.
