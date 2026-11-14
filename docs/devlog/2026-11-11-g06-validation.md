# G06 추가 검증

사용자 요청: “G06도 검증해줘.” 권한 요청·조회 일치, 사이트 경계, OS 거부·복구를 대상으로 기존 검증을 확장했다. 기존 소스와 실행 자료는 보존했고, G02·삭제 구현은 변경하지 않았다.

## 판정과 근거

**G06 미통과. 최종 자동 검사 25개 중 19개 통과·6개 실패.** 네이티브 앱은 정상 종료했다(종료 코드 0, CEF shutdown 1회, network service 재시작 0). 테스트 runner의 종료 코드 1은 수용 조건 실패를 의미한다.

- [최종 결과](../../validation/cef-spike/evidence/g06-signed-20261111-163741/results.json)
- [합산·소스 해시](../../validation/cef-spike/evidence/g06-summary.json)
- [초기 탐색 결과](../../validation/cef-spike/evidence/g06-20261111-163130/results.json)
- [독립 사례 재검증](../../validation/cef-spike/evidence/g06-signed-20261111-163601/results.json)
- [일반 앱 실행 실패](../../validation/cef-spike/evidence/g06-signed-20261111-163520/results.json), [해당 앱의 OS 오류 로그](../../validation/cef-spike/evidence/g06-launch-services-error.log)

반복 실행을 합산해 검사 수를 부풀리지 않았다. 이전 79개 통과와 이번 6개 실패는 모순이 아니다. 이전 검사에는 같은 origin의 명시적 거절, iframe의 요청 거절 등이 있었지만 iframe query와 단독 페이지 설정으로의 영향은 없었다.

## 소스와 시험 준비

- [G06Probe.mm](../../validation/cef-spike/G06Probe.mm): 이전 PermissionPrivacyProbe를 기반으로 별도 생성. `Probe.focus`와 `Permission.osStatus`를 추가했다. AVFoundation·CoreLocation·UserNotifications의 상태 조회만 수행하며 OS 권한 요청이나 촬영·녹음·위치 수집은 하지 않는다.
- [build-g06-probe.py](../../validation/cef-spike/build-g06-probe.py): 전용 bundle ID `local.jena.g06probe`, 카메라·마이크·위치 사용 설명을 추가했다. CEF sandbox 설정은 유지했다.
- [build-g06-signed-probe.py](../../validation/cef-spike/build-g06-signed-probe.py): 별도 출력 경로에 로컬 ad-hoc 서명과 deep/strict 검사를 추가했다. 배포용 서명·공증이 아니다.
- [g06-signed.py](../../validation/cef-spike/g06-signed.py): 실제 HTTPS a.test/b.test fixture, 독립 프로필, 두 browser, 위임 금지/허용 iframe 검사. 각 사례 전에 설정을 초기화해 이전 iframe의 설정 변경이 다음 독립성 검사를 오염시키지 않도록 했다. native 설정과 실제 웹 query를 모두 확인한다.
- [PermissionPrivacyCommands.inc](../../validation/cef-spike/PermissionPrivacyCommands.inc)는 이전 구현을 그대로 사용했다. 실패가 드러난 미디어 저장 경로를 이번 검사에서 임의로 다른 제품 정책으로 대체하지 않았다.

권한 설명 키는 [Apple의 macOS 미디어 권한 문서](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos?language=objc)를 참고했다. CEF 요청·거절 callback 계약은 고정 배포본 `include/cef_permission_handler.h`를 확인했다.

## 통과한 범위

- 전경 페이지에서 사전 차단 설정 없이 위치 query가 prompt인 것을 확인한 뒤 요청했다. `OnShowPermissionPrompt`에 mask 256으로 도달했고, 자동 거절 callback 후 웹 오류 코드 1, query denied가 일치했다.
- 같은 origin의 별도 browser는 저장된 카메라 거절을 공유했고 다른 origin은 prompt로 유지됐다. 이 검사는 iframe이 설정을 쓰기 전에 독립적으로 실행했다.
- Permissions Policy에서 camera/microphone/geolocation을 금지한 iframe의 초기 query는 denied였고 미디어 요청은 NotAllowedError였다.
- 위임한 iframe도 미디어 요청은 거절됐고 상위 DOM 접근은 SecurityError였다. iframe 요청 이후 상위 A 페이지 자체의 카메라·마이크 query는 prompt로 유지됐다.
- 최종 실행 안에서 읽은 OS 권한 상태는 실행 전후 같았다. 이것은 OS 거부·복구 시나리오 통과를 의미하지 않는다.

위치의 추가 창 활성화 실험에서는 포커스가 없는 시점에 이미 오류 코드 1이 반환돼 있었다. 따라서 “활성화가 pending 요청을 풀었다”는 증거가 아니다. 최종 테스트 이름도 이 관측에 맞춰 고쳤다. 이번 번들은 메타데이터·bundle ID·활성화 조건이 이전 Stage11과 달라, 과거 무응답의 원인을 포커스 하나로 확정하지 않는다. 위치 승인 UI·실제 좌표 취득도 검증하지 않았다.

## 실패한 수용 조건

각 현상은 카메라와 마이크에서 모두 재현돼 총 6개 실패다.

| 상황 | 기대 | 실제 |
|---|---|---|
| A 안의 B iframe에 Permissions Policy로 미디어 접근 금지 | 정책 때문에 거절된 요청이 B 단독 사이트의 사용자 선택을 바꾸지 않음 | native callback이 호출되고 B 단독 설정에 BLOCK(2)이 저장됨; 기대 ASK(3) |
| A가 B iframe에 미디어 권한을 위임하고 native에서 요청 거절 | iframe의 요청 거절과 query denied가 일치 | 요청은 NotAllowedError, iframe query는 prompt |
| 위임된 B iframe의 요청 거절 후 B를 단독으로 방문 | 요청 origin/최상위 origin 문맥을 분리 | B 단독 페이지 query도 denied로 변경됨 |

현재 callback은 `SetContentSetting(requesting_origin, top_level_url, mediaType, BLOCK)`을 호출한다. 두 URL을 넘겼다는 사실만으로 임의의 origin 쌍에 대한 독립적인 정책 저장·조회가 성립하지 않는다. 이번 런타임에서는 B의 단독 설정에 거절이 남고, 위임된 iframe query에는 반영되지 않았다. 상위 A의 설정이 변경됐다고 해석하면 안 된다.

따라서 사이트별 BLOCK 저장은 최상위 요청의 이전 불일치를 해결했지만 임베디드 요청에는 그대로 적용할 수 없다. 후속 수정은 Permissions Policy 차단과 사용자의 권한 결정을 구분하고, 요청 origin/최상위 origin/권한 종류/OS 상태를 함께 다뤄야 한다. JS query 덮어쓰기나 실패 조건 제거로 통과시키지 않았다.

## OS 권한 검증의 차단 사유

일반 실행과 직접 실행을 구분했다. `open -W -n`으로 Launch Services를 통한 실행을 시도했지만 unsigned 후보와 ad-hoc 서명 검사 통과 후보 모두 -10810으로 실패했다. 해당 앱의 OS 로그는 `NSPOSIXErrorDomain Code=1 Operation not permitted`, `Launchd job spawn failed`를 기록했다. 서명 불일치는 최초 번들에서 별도로 확인한 문제이며, 서명을 보완해도 실행 실패가 남았으므로 이를 유일 원인으로 단정하지 않는다. 시스템 보안 설정을 바꾸거나 우회하지 않았다.

직접 실행은 가능했으나 최종 상태는 camera=3, microphone=3, location=0, notifications=1이었다. 카메라·마이크의 3은 authorized, 위치의 0은 notDetermined, 알림의 1은 denied다. 실행 전후 값은 동일했다. 직접 실행에는 호출 앱의 권한 귀속이 관여할 수 있으므로 이 결과를 독립 배포 앱의 OS 허용·거부 증거로 사용하지 않는다. 초기 다른 실행의 notification 값은 0이었다; 실행 간 차이의 원인은 이번 검사에서 확정하지 않았다.

사용자에게 실제 시스템 창·설정 조작에 참여 가능한지 질문했다. 이 작업 종료 시점에는 수동 확인 답변·실행 근거가 없다. OS 권한 요청, 실제 장치 접근, 거부 후 설정 변경·복구, 사용자용 복구 안내는 미검증이다. 개인 TCC 데이터베이스를 읽거나 수정하지 않았고 OS 권한 reset도 실행하지 않았다.

## 재현

```sh
python3 validation/cef-spike/build-g06-signed-probe.py
python3 validation/cef-spike/g06-signed.py
```

현재 재현 결과는 수용 조건 6개 실패로 runner exit 1이 정상이다. OS 실행 경로 점검은 다음과 같다.

```sh
G06_LAUNCH_SERVICES=1 python3 validation/cef-spike/g06-signed.py
```

실행마다 evidence/profile을 새로 생성하며 원본을 삭제하지 않는다. 실패한 실행 폴더와 소스 snapshot도 보존한다. G02 확정은 유지하지만 **G06 및 CEF 전체 채택은 확정하지 않는다.**
