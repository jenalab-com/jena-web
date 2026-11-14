# OS 권한 결합·복구 검증 — 진행 중

사용자 요청: “OS 권한 결합, 복구 검증 진행해줘.” 기존 검증 자료를 보존하고 G06CombinedProbe, CombinedLaunchState, CombinedPermissionCommands, CombinedFixture 및 controller/preflight runner를 추가했다. [설계 판단](../architecture-log/2026-11-12-g06-combined-recovery.md)을 참조한다.

## 자동 사전 검사

- 첫 실행: `validation/cef-spike/evidence/g06-combined-20261112-184407`. 사이트 거절 경로 6개는 통과했으나 종료 대기에서 실패했다. 최초 구현의 applicationShouldTerminate/NSTerminateLater가 CEF 종료를 막았다. 실패 소스를 initial-source에 보존했다.
- 수정 실행: [preflight 결과](../../validation/cef-spike/evidence/g06-combined-20261112-184923/preflight-results.json), **15/15 통과**. NSApplication.terminate:에서 CEF 브라우저 닫기를 시작하는 공식 예제 방식으로 수정했다.
- 확인: HTTPS-origin 로컬 fixture의 secure context, 카메라·마이크 사이트 deny 시 실제 웹 NotAllowedError와 query denied, OS 창 미요청, 앱·helper 정상 종료, CefShutdown, 환경변수 없는 재실행, 같은 프로필·쿠키·LocalStorage·사이트 선택 유지, 새 mailbox 및 과거 명령 재실행 방지.
- 멈춘 첫 실행의 PID 12633, 13298, 13299, 13303, 13437, 13438, 13439, 15814, 16137은 사용자에게 해당 9개만 종료를 승인받았다. 경로·부모 PID 확인 후 SIGTERM을 보냈고 모두 사라진 것을 확인했다. 별도 수정 번들은 종료하지 않았다. 기록은 첫 실행의 approved-termination.json에 있다.

## 수동 결합 검증

현재 실행 폴더: `validation/cef-spike/evidence/g06-combined-20261112-184923`. 같은 프로필을 유지하며 재실행마다 active-session.json의 bootID와 mailbox가 바뀐다. 원시 명령·응답은 steps.jsonl에 기록한다.

1. 테스트 사이트 camera 선택을 allow로 설정하고 사용자가 웹 버튼을 눌렀다. 사용자는 OS 창에서 거절했다고 답했으나 웹 결과는 opened-and-stopped(트랙 1개, 모두 중지), native camera 상태는 notDetermined였다. 이 불일치를 성공으로 처리하지 않았다. 원인·권한 귀속·시점은 확정하지 않았다.
2. 앱 자체 카메라 권한 요청을 별도로 수행했다. 사용자는 동작하지 않으니 모두 닫고 다시 띄워 달라고 요청했다. 검증 앱을 정상 종료했고 관련 프로세스가 모두 사라진 것을 확인한 뒤, 환경변수 없는 재실행으로 같은 프로필을 복원했다. user-restart.json에 기록했다.
3. 기존 자동검증용 probe가 두 창을 생성해 하나가 비어 있다는 점을 설명했다. 이 수동 실행에서는 빈 slot 1을 정상 닫고 테스트 slot 0만 유지했다. 시작 코드 자체가 두 browser인 사실은 바뀌지 않았으므로 다음 자동 재실행 때는 다시 정리해야 한다.
4. 재실행 후 native camera=2(denied)를 확인했다. 사이트 camera 설정은 ALLOW(1)로 남아 있었다. 실제 웹 media('video')는 NotAllowedError로 실패했다. 웹 permissions.query는 전후 granted였다. 즉 웹 query는 사이트 선택, native OS API는 시스템 상태이며 두 층을 혼동하면 안 된다. native media callback이 OS 거부를 확인해 취소했고 사이트 선택을 덮어쓰지 않았다.
5. 카메라 OS 설정을 켠 후 사용자는 앱이 종료됐지만 다시 열리지 않았다고 보고했다. 관련 앱·helper가 없는 것을 확인하고 같은 실행 폴더로 명시적으로 재실행했다. 새 bootID와 mailbox, 기존 프로필·LocalStorage·쿠키·사이트 camera ALLOW(1)를 확인했다. native camera=3(authorized), 실제 웹 요청은 opened-and-stopped(트랙 1개, 모두 중지)였다. 자동 재실행은 실패, 명시적 재실행 후 카메라 복구는 통과로 구분한다. 원시 결과: camera-os-recovery.json.

6. 마이크 OS 설정을 끈 뒤에도 사용자는 종료 후 자동으로 다시 열리지 않았다고 보고했다. 기존 앱·helper가 없음을 확인하고 동일 프로필로 명시적으로 재실행했다. 초기 Jena.status 시간 초과, policy-not-ready, helper의 15초 연결 실패 및 network service 재시작 로그가 있었으며, 추가 재실행 없이 나중에 ready=true가 됐다. 빈 slot 1은 닫았다. native microphone=2(denied), 사이트 microphone=ALLOW(1)에서 실제 웹 요청은 NotAllowedError였고 사이트 선택은 전후 유지됐다. query는 전후 granted였다. camera도 이번 조회에서는 denied로 관측됐으나 변경 원인은 확정하지 않았다. 원시 결과: microphone-os-denial.json. 마이크 OS 허용 후 복구는 다음 단계다.

7. 마이크 OS 설정을 다시 켠 후 사용자는 자동 재실행됐지만 빈 창 두 개가 나타났다고 보고했다. 새 bootID 846218FE-56F6-4DA9-A2DB-FA385B70A87C, restoredConfiguration=true, 동일 프로필을 확인했다. 시작 코드가 about:blank와 두 browser를 고정 생성하므로 화면 복원은 미구현이다. 빈 slot 1을 닫고 slot 0을 fixture로 탐색시켰다. native microphone=3, 사이트 ALLOW(1)에서 실제 웹 요청은 opened-and-stopped(트랙 1개, 모두 중지), 사이트 선택은 유지됐다. LocalStorage marker도 유지됐다. 1시간 만료 쿠키는 이번 조회에서 없었으며 최초 설정 후 1시간 이상 지난 시점이므로 이 결과를 쿠키 복구 실패로 판정하지 않는다. 이번 자동 재실행 성공은 앞선 실패 기록과 구분한다. 원시 결과: microphone-os-recovery.json.

8. 사용자가 위치 OS 요청에서 거부한 뒤 native location=2(denied)를 확인했다. 사이트 geolocation을 ALLOW(1)로 설정한 상태에서 실제 웹 getCurrentPosition은 code=1(PERMISSION_DENIED)로 실패했다. 사이트 설정은 ALLOW(1)로 유지됐으나 permissions.query는 전후 denied였다. 카메라·마이크와 query 동작이 다르므로 모든 권한의 query가 사이트 선택만 반영한다고 일반화하지 않는다. 원시 결과: location-os-denial.json. OS 재허용 후 복구는 다음 단계다.

## 범위

카메라 OS deny + 사이트 allow의 요청 차단은 확인했다. OS 허용 후 명시적 재실행에서 실제 웹 카메라 성공·복구도 확인했다. 설정 변경에 의한 자동 재실행은 앞선 카메라·마이크 거부 단계에서 실패했고, 마이크 재허용 단계에서는 성공했다. 마이크의 사이트 allow + OS deny 차단 및 OS 재허용 후 실제 웹 복구도 확인했다. 위치·알림의 결합 검증은 아직 완료가 아니다. native OS request 결과만으로 웹 기능 성공을 대신하지 않는다. 카메라·마이크 성공 시 트랙을 즉시 중지하며 영상·음성을 저장하지 않는다. 위치 fixture는 좌표 필드를 읽지 않고 성공 여부만 기록한다. 알림 발송은 별도 버튼을 누를 때만 한다.

웹 query와 OS 상태를 결합한 제품 UI 안내, 미결정 OS 권한의 CEF 위임 경로, 다중 인스턴스·여러 종류 동시 요청·탐색 중 권한 응답은 추가 검증이 필요하다. G06 전체·CEF 전체 채택을 확정하지 않는다.
