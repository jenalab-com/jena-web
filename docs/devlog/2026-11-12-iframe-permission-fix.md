# iframe 미디어 요청 거절 수정

사용자 요청: “iframe 권한 문제 진행해줘.” 이후 정책 선택: **“이번 요청만 거절 — 다른 권한 유지”**. 기존 소스·실패 결과를 보존하고 별도 native probe에서 수정했다. code 스킬의 수술적 변경·실제 엔진 검증·작업 기록 기준을 적용했다.

## 결과

선택한 정책 기준 **47/47 통과**. 최종 정책 검사 25개와 경계 검사 22개는 각각 앱 종료 코드 0, CEF shutdown 1회, 네트워크 서비스 재시작 0이다. 별도 엔진 구조 진단 4개는 수용 검사 수에 합산하지 않았다.

| 구분 | 결과 | 근거 |
|---|---|---|
| 이전 기대값을 유지한 수정본 | 23/25; 두 query 기대값 실패 보존 | [결과](../../validation/cef-spike/evidence/iframe-request-guard-bundled-20261112-182826/results.json) |
| 사용자 선택 후 최종 정책 | 25/25 | [결과](../../validation/cef-spike/evidence/iframe-request-denial-20261112-183443/results.json) |
| 동일 출처·sibling·다른 상위 사이트·기존 설정 보존 | 22/22 | [결과](../../validation/cef-spike/evidence/iframe-request-guard-edges-20261112-183130/results.json) |
| 엔진 permission key 진단 | 4/4 관측 일치 | [결과](../../validation/cef-spike/evidence/iframe-permission-key-20261112-183224/results.json) |
| 합산·소스 해시 | 선택 정책 범위 통과 | [summary](../../validation/cef-spike/evidence/iframe-permission-fix-summary.json) |

## 수정 내용

[IframeRequestGuardProbe.mm](../../validation/cef-spike/IframeRequestGuardProbe.mm)의 `OnRequestMediaAccessPermission`에서 iframe이면 callback을 Cancel하고 즉시 반환한다. 최상위 frame의 기존 설정 저장 경로는 유지한다. 변경은 subframe에 대한 저장 방지 분기다.

이전 구현은 iframe 요청에서도 `SetContentSetting(requesting_origin, top_level_url, mediaType, BLOCK)`을 실행했다. 이 때문에 Permissions Policy로 접근을 금지한 iframe 요청까지 그 origin의 단독 페이지 설정에 BLOCK을 남겼다. 수정본은 같은 출처의 subframe도 포함해 iframe 요청에서 저장된 권한을 바꾸지 않는다. 미디어 요청 자체는 NotAllowedError로 거절되며, 장치 사용을 허용하지 않는다.

최종 구현은 CDP 권한 override, DOM 수정, JS permissions.query 덮어쓰기를 사용하지 않는다. 브라우저가 반환하는 query 상태를 그대로 읽는다. 기존 저장값을 reset하는 방식도 사용하지 않아 이미 저장된 거절이 보존된다.

## 요청 취소와 영구 차단의 구분

기존 검사 6개 중 4개는 상태 전파 문제였고 실제 코드 변경으로 해결됐다. 나머지 2개는 Cancel로 요청을 취소한 뒤에도 영구 차단의 query denied를 기대하던 조건이었다. [Permissions 명세의 상태 정의](https://www.w3.org/TR/permissions/#permission-state)에서는 prompt 상태의 요청도 사용자에게 묻거나 거절될 수 있다. 따라서 요청 실패만으로 영구 차단을 추론해서는 안 된다.

엔진 구조도 확인했다. [Browser.setPermission](https://chromedevtools.github.io/devtools-protocol/tot/Browser/#method-setPermission)에 상위 A와 embedded B를 지정해 카메라를 denied로 설정하자, B iframe뿐 아니라 **A 최상위 페이지의 query도 denied**가 됐다. B 단독 페이지는 prompt로 유지됐다. [Chromium PermissionOverrides](https://chromium.googlesource.com/chromium/src/+/main/content/browser/permissions/permission_overrides.cc)의 기본 embedding-origin key와 부합한다. main 소스가 고정 배포본과 같다고 가정하지 않고 실제 CEF 156에서도 진단했다.

사용자에게 요청 단위 거절, 상위 사이트 영구 차단, iframe 독립 영구 차단의 차이를 확인했고 요청 단위 거절을 선택받았다. 이에 따라 기존 실패 자료는 보존하고 새 최종 runner에서 두 query 기대값을 prompt로 명시했다. 통과 숫자를 만들기 위해 실패 기록을 삭제하거나 iframe 독립 영구 차단 요구를 충족했다고 주장하지 않는다.

## 추가 검증

- 최상위 페이지의 마이크·카메라 요청 거절 및 기존 query denied 동작 유지.
- 동일 출처 iframe 요청의 취소가 최상위 설정을 변경하지 않음.
- 같은 B origin의 sibling iframe 두 개를 요청해도 각 query와 단독 B 설정에 거절이 남지 않음.
- 다른 상위 C 사이트에서 B iframe을 사용해도 A에서의 요청 취소가 전파되지 않음.
- B 단독 사이트에 미리 저장한 거절은 iframe 요청 후에도 보존됨.
- 기존 G06 매트릭스의 Permissions Policy 금지/위임, 상위 DOM 접근 차단, origin별 설정, 위치 callback, OS 상태 불변도 확인.

## 재현과 적용 파일

```sh
python3 validation/cef-spike/build-iframe-request-guard-probe.py
python3 validation/cef-spike/iframe-request-denial.py
python3 validation/cef-spike/iframe-request-guard-edges.py
```

빌드 출력은 `build/iframe-request-guard-bundled-probe/JenaProbe.app`이다. 엔진 key 진단은 `iframe-permission-key.py`로 별도 실행한다. 최종 결과 폴더에는 해당 native 소스·runner·빌드 스크립트 snapshot을 보존했다. 이전 G06·G02·삭제 source는 덮어쓰지 않았다.

## 실행 중 확인한 문제

초기 실험 `IframePermissionProbe.mm`는 엔진 override 가능성을 조사한 후보이며 최종 적용 대상이 아니다. 해당 bundle의 페이지 탐색/observer 시간 초과 실행은 권한 검사에 도달하지 못했고 채택 근거에서 제외했다. `iframe-permission-*` 및 `iframe-permission-bundled-*` 오류 자료를 보존했다. CDP 동작 진단은 정상 실행된 최종 guard bundle에서 별도 수행했다.

다른 번들의 framework를 symlink로 공유한 최초 guard 패키징은 helper의 CEF sandbox에서 파일 접근이 차단됐다. framework를 앱 안에 복사한 별도 bundled 출력으로 수정했다. Sandbox 설정을 끄지 않았다. 최종 guard runner는 느린 실행에서 원인을 구분할 수 있도록 native 응답 대기를 90초로 설정한다. 이 수용 결과를 시작 시간·성능 예산 통과로 해석하지 않는다.

이전 수동 검증의 orphan renderer PID 30961·30962·30964가 CPU 약 279%를 사용하고 있었다. 사용자에게 해당 3개 종료를 명시적으로 승인받은 뒤, 각각 PPID=1 및 정확한 `g06-manual-probe` renderer 실행 경로를 확인하고 SIGTERM을 보냈다. 이후 세 PID 모두 사라진 것을 확인했다. 다른 프로세스를 종료하지 않았다. [종료 기록](../../validation/cef-spike/evidence/approved-renderer-termination-20261112.json)을 보존했다. 초기 시간 초과의 단일 원인이 이 프로세스였다고 단정하지 않는다.

## 남은 범위

iframe 미디어의 요청 단위 거절과 저장 권한 보존은 이번 선택 범위에서 검증 완료다. 제품 권한 UI, iframe 독립 영구 차단·허용, 웹 요청과 OS 권한의 결합, 실제 장치 사용, 자동 재실행 및 복구 UX, G02와 통합한 런타임 검증은 별도다. **G06 전체 및 CEF 전체 채택 보류는 유지한다.**
