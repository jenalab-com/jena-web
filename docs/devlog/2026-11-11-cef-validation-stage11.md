# CEF 검증 11차: 권한 거부와 웹·네이티브 경계

## 판정

**G06은 보류다.** 보완 실행의 assertion 23개 중 21개가 통과했다. 위치 요청은 관측 시간 내 결과가 없었고 권한 조회도 prompt에 머물렀다. 카메라·마이크 요청은 거부됐지만 조회는 prompt로 남는 추가 불일치가 관측됐다. 권한 요청 거부를 저장 정책·권한 조회·OS 상태가 일치하는 제품 구현으로 확대하지 않는다.

G01은 제한된 공격 입력에 대한 부분 근거를 확보했다. 10차 G02 탐색 분류 문제는 계속 보류다.

## 구현과 시험 범위

- [Stage11Probe.mm](../../validation/cef-spike/Stage11Probe.mm): 7차 adapter에서 분리했다. OnRequestMediaAccessPermission은 Cancel, OnShowPermissionPrompt는 DENY로 처리한다. 요청 origin·frame 여부·권한 비트는 fixture 진단 로그에 남긴다.
- OnBeforeBrowse는 검증용 HTTP(S)·about:blank만 허용하고 file 및 외부 스킴 이동은 취소한다. 제품의 전체 URL·다운로드·하위 리소스 정책 구현은 아니다.
- [security-stage11.py](../../validation/cef-spike/security-stage11.py): 별도 HTTPS A/B origin, 공유 프로필의 두 browser, 로컬 시험용 sentinel 파일을 사용한다.
- 실제 장치 접근을 허용하지 않고 macOS 권한 설정을 변경하지 않는다. OS 허용 후 장치 사용·OS 거부·복구 안내는 이번 시험에 포함하지 않는다.
- Swift 정책 서비스는 기존 7차 파일을 사용한다. 사이트별 권한 선택·영구 저장·허용 UI는 구현하지 않았다.

## 초기 실패와 보완

[초기 실행](../../validation/cef-spike/evidence/security-stage11-20261111-131804/results.json)은 7개 assertion 통과 후 getCurrentPosition 응답을 기다리다 전송 계층의 시간 제한으로 중단됐다. 위치 요청에 지정한 timeout만으로는 권한 결정 대기를 끝내지 못했다. 원인은 확정하지 않았다. 앱은 정상 종료했고 실패 소스·로그를 보존했다.

다음 실행은 watchPosition과 별도 JavaScript 타이머를 사용해 관측을 끝내고 clearWatch를 호출했다. 8초 타이머가 반환한 값은 `no-callback-within-8s`였다. 이는 측정 코드의 값이며 OS·CEF 내부의 정확한 원인이나 벽시계 시간의 상한을 뜻하지 않는다.

코드 점검에서 이전 probe의 페이지 제목 `JENA_RENDERER_OK`가 네이티브 종료를 유발하는 시험 장치를 발견했다. 보안용 adapter에서는 OnTitleChange 종료 로직을 제거하고 파일 mailbox의 Probe.close로 종료한다. 웹 콘텐츠가 이 mailbox에 접근할 수 있는 브리지를 추가하지 않았다. 초기 실행 번들을 덮어쓰지 않고 stage11-hardened-probe를 별도로 만들었다.

## 보완 실행 결과

[실행 결과](../../validation/cef-spike/evidence/security-stage11-20261111-131941/results.json): **21/23 assertion 통과**, 전체 상태는 failed다. 앱 종료 코드 0, CefShutdown 반환, 네트워크 서비스 재시작 0회, 원격 디버깅 listening 로그 없음.

| 항목 | 관측 | 판정 범위 |
|---|---|---|
| 알림 A | requestPermission=denied, query=denied | 거부·조회 일치 |
| 알림 B | A 거부 후에도 최초 query=prompt, B 요청 후 denied | 이번 두 origin의 결정 격리 |
| 위치 A | 관측 시간 내 결과 없음, query=prompt | 두 assertion 실패, G06 미충족 |
| 마이크 A | NotAllowedError, native media callback origin=A | 요청 거부 확인 |
| 카메라 A | NotAllowedError, native media callback origin=A | 요청 거부 확인 |
| 카메라·마이크 조회 | 둘 다 prompt | 요청 거부를 지속적인 denied 상태로 반영하지 못함 |
| B iframe의 위임된 미디어 요청 | NotAllowedError, origin=B·main=false·mask=3 | 최상위 A로 오인하지 않고 B 요청으로 관측 |

미디어 조회의 prompt는 결과 JSON의 mediaQueriesAfter에 저장했다. 요청 거부 assertion은 통과했지만 이 관측을 권한 조회 일치의 통과로 집계하지 않았다. Cancel은 개별 요청의 취소이므로, 사용자 정책을 영구 거부로 저장·조회에 반영하는 별도 경로가 필요할 수 있다. 이번 시험에서 그 경로가 구현됐다고 주장하지 않는다.

## 웹·네이티브 경계

- 웹과 iframe에서 NativePolicySend·SwiftPolicyRequest·cefQuery·Node require/process 진입점은 노출되지 않았다.
- window.postMessage에 Jena.policy 형태의 메시지를 넣어도 native revision과 저장 선택이 바뀌지 않았다. 이는 웹 메시지 입력 시험이며 CEF 내부 IPC 위조·취약점 공격 전체가 아니다.
- HTTPS 페이지의 file URL fetch는 TypeError로 실패했다. 대상은 직접 만든 시험 파일이며 개인 파일을 읽지 않았다.
- B iframe에서 A 부모 DOM 접근은 SecurityError였다.
- file 및 시험 외부 스킴의 Page.navigate는 native handler에서 거절됐고 기존 B 문서가 유지됐다. 이 두 이동 명령은 테스트 드라이버에서 보냈으며 모든 웹 스킴 공격 경로를 검증한 것은 아니다.
- 보완 앱에서 종료용 제목으로 변경한 뒤에도 페이지가 살아 있었다. 제목 기반 종료 장치 제거를 확인했다.

코드에서도 CefMessageRouter·CefV8 확장·Node 브리지를 등록하지 않은 것을 확인했다. 브리지가 없는 probe에서의 결과를 미래 제품 브리지의 보안 증거로 재사용하면 안 된다. sandbox 요청과 helper 초기화는 유지했지만 sandbox 탈출 시험이나 독립 보안 감사는 수행하지 않았다.

## 남은 항목과 12차 판단

- G06: 위치 요청 경로·CEF/OS 연동 조사, 지속적인 권한 정책과 query 일치, 허용·철회·재실행·OS 거부·복구 안내
- G01: 제품 UI/브리지 구현 이후 origin·message schema·파일 경계 재검증, 다운로드·외부 스킴 전체 정책
- G02: 10차의 JavaScript 이동 오분류는 미해결
- G08·G09: 네이티브 UI 입력·접근성·성능·장시간 안정성 등 12차 묶음

현재 결과로 CEF 채택을 확정하지 않는다. 12차에는 이미 확인한 보류 사유를 포함해 채택 여부를 정리하며, 기능을 임의로 제외해 통과시키지 않는다.

## 재현

```sh
python3 validation/cef-spike/build-stage11-probe.py
validation/cef-spike/.venv/bin/python validation/cef-spike/security-stage11.py
```

macOS arm64, Swift 6 모드, CEF 156.0.27 환경이다. [집계](../../validation/cef-spike/evidence/stage11-summary.json)에 초기·보완 실행을 구분했다. 각 프로필·로그·소스 스냅샷을 보존했으며 강제 종료·기존 프로필 삭제·PRD 전체 재작성은 수행하지 않았다.
