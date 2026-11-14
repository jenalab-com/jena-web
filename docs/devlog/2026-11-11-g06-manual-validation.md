# G06 macOS 수동 검증 — OS 상태 전환 확인

사용자가 시스템 권한 창·설정의 직접 조작에 참여하겠다고 확인했다. 기존 G06 결과와 소스를 보존하고 전용 G06ManualProbe.mm, build-g06-manual-probe.py, g06-manual-session.py를 추가했다. code 스킬의 작업 기록 기준을 적용했다.

## 실행 준비와 현재 근거

- 앱: `validation/cef-spike/build/g06-manual-probe/JenaProbe.app`
- bundle ID: `local.jena.g06manual`
- 실행·네이티브 응답: [실행 폴더](../../validation/cef-spike/evidence/g06-manual-20261111-165019/), [단계 기록](../../validation/cef-spike/evidence/g06-manual-20261111-165019/manual-steps.jsonl)
- Launch Services 실행 성공(return code 0), CEF sandbox 및 native mailbox 활성화. 이전 runner와 달리 launchd의 외장 볼륨 stdout/stderr 리디렉션을 제거하고 앱에서 로그를 열도록 했다. 실행 환경도 최소화했다. 두 조건을 함께 바꿨으므로 이전 실패의 단일 원인으로 단정하지 않는다.
- 최초 OS 상태: camera=0, microphone=0, location=0, notifications=1. 직접 binary 실행 때와 달리 미디어 권한은 아직 결정되지 않은 상태였다.
- `Permission.requestOS`를 추가했다. 네이티브 mailbox에서만 요청 가능하며 실제 OS 권한 API를 호출한다. 이 단계는 촬영·녹음·위치 수집을 시작하지 않는다. 참조: [Apple AVCaptureDevice](https://developer.apple.com/documentation/avfoundation/avcapturedevice/).

## 수동 진행

1. 카메라 요청에서 거부 선택을 안내했으나 사용자는 허용을 선택했다고 답했다. 순서를 허용 → 설정에서 거부 → 재허용으로 조정했다.
2. 앱 상태 조회에서 camera=3(authorized)을 확인했다. 실제 callback 결과도 mailbox에 보존한다.
3. 시스템 설정의 카메라 화면에서 끔으로 바꾸자 앱 종료·재실행 안내가 나타났다고 사용자가 답했다. “종료 및 다시 열기”를 선택했으나 앱이 다시 열리지 않았다는 답변을 받았다.
4. 동일한 번들을 Launch Services로 새 검증 세션(`g06-manual-20261111-165348`)에서 다시 실행했다. camera=2(denied)와 재요청 callback granted=false를 확인했다. 거부 설정은 재실행 뒤 유지됐다. 자동 재실행 실패 원인은 아직 확정하지 않았다.

5. 카메라를 다시 켠 뒤 사용자에게 자동 재실행 실패를 다시 보고받았다. 동일 번들을 새 세션(`g06-manual-20261111-165557`)으로 실행했고 camera=3(authorized) 복구를 확인했다. 카메라 재요청 결과는 mailbox에 보존한다.
6. 마이크 최초 요청에서 사용자가 거절했다. microphone=2, callback granted=false를 확인했다.
7. 마이크 설정을 켜고 종료·재실행을 선택한 뒤 앱이 다시 열리지 않았다는 답변을 받았다. 새 세션(`g06-manual-20261111-165736`)에서 microphone=3(authorized)으로 복구된 것을 확인했다.
8. 위치 요청에서 사용자가 거절했다. location=2(denied)를 확인했고, 앱 위치 설정을 켜도록 안내했다. 사용자가 재실행 안내가 있었다는 답변을 정정했고 실제로는 앱이 그대로 실행 중이라고 확인했다. 재시작 없이 location=3(authorizedAlways)으로 바뀐 것을 읽었다.

9. 알림은 최초부터 denied(1)였고 요청 창이 나타나지 않았다는 사용자 답변과 callback granted=false를 확인했다. 시스템 설정에서 알림 허용을 켠 후 notifications=2(authorized), 재요청 callback granted=true를 확인했다.

## 결과

| 권한 | 실제 관측 | 복구 |
|---|---|---|
| 카메라 | notDetermined → authorized → denied → authorized; 요청 결과 true → false → true | 설정 변경 후 별도 앱 실행으로 확인 |
| 마이크 | notDetermined → denied → authorized; 요청 결과 false → true | 설정 변경 후 별도 앱 실행으로 확인 |
| 위치 | notDetermined → denied → authorizedAlways | 앱 재시작 없이 확인; 좌표 수집 없음 |
| 알림 | 기존 denied → authorized; 재요청 false → true | 앱 재시작 없이 확인; 알림 발송 없음 |

네 권한의 **OS 거부 상태와 설정 변경 후 복구**를 실제 사용자 조작 및 네이티브 응답으로 확인했다. 알림은 최초 거절 팝업부터 수행한 것이 아니라 기존 거부 상태에서 시작했다. 카메라·마이크 설정 변경 후 자동 재실행 실패를 총 3회 사용자에게 보고받았으며, 명시적 재실행은 성공했다. 이를 자동 복구 UX 통과로 기록하지 않는다.

[수동 검증 요약](../../validation/cef-spike/evidence/g06-manual-summary.json)에 실행 폴더와 결과를 기록했다. 마지막 실행 폴더에 소스 snapshot을 보존했다.

## 범위

OS API의 거부·복구 상태 전환 검증은 완료했다. 실제 웹 getUserMedia/위치/알림 요청이 OS 거부와 허용을 올바르게 반영하는 결합 검증, 실제 장치·알림 사용, 제품 내 복구 안내는 아직 검증하지 않았다. 기존 G06 iframe 6개 실패를 해결하거나 채택 보류를 해제하지 않는다. 앱과 프로필은 유지 중이며 사용자 선택을 대신하거나 TCC를 reset하지 않는다.
