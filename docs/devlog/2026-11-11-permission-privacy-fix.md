# 권한·선택 삭제 소스 수정과 재검증

사용자 요청: “권한, 삭제에 대한 것도 소스를 수정해서 검증해줘.” 기존 G02 확정은 유지하고 G06·G04의 관측된 문제를 별도 네이티브 검증 소스에서 수정했다. 이전 파일·결과·프로필을 보존했다.

## 결과

최종 권한·삭제 **54/54**, 보안 회귀 **25/25**, 합계 **79/79 통과**. 검증 앱의 정상 종료 3회, 각 종료 코드 0, 네트워크 서비스 재시작 0, 원격 디버깅 포트 노출 없음. 최초 53개 통과 실행은 중복 집계하지 않았다. 검증 환경은 기존 고정 CEF 156.0.27 / Chromium 156.0.8078.88, macOS arm64, Swift 6 서비스 + Objective-C++ 어댑터다.

| 묶음 | 근거 |
|---|---|
| 최초 권한·쿠키·저장소 검증 53개 | [초기 결과](../../validation/cef-spike/evidence/permission-privacy-20261111-155607/results.json) |
| service worker 및 분할 쿠키 사전 존재 검사를 포함한 최종 54개 | [최종 권한·삭제 결과](../../validation/cef-spike/evidence/permission-privacy-20261111-155737/results.json) |
| 보안 회귀 최종 25개 | [보안 결과](../../validation/cef-spike/evidence/permission-security-20261111-155821/results.json) |
| 합산·소스 해시 | [summary](../../validation/cef-spike/evidence/permission-privacy-summary.json) |

## 구현 변경

- [PermissionPrivacyProbe.mm](../../validation/cef-spike/PermissionPrivacyProbe.mm): Stage11Probe의 별도 수정본. 미디어 거절 callback에서 엔진 content setting을 먼저 BLOCK으로 기록한다. 엔진 내부 명령 응답을 별도 ID로 분리하고 observer를 빠져나온 뒤 다음 작업을 수행한다. 웹 콘텐츠에 명령 브리지는 노출하지 않는다.
- [PermissionPrivacyCommands.inc](../../validation/cef-spike/PermissionPrivacyCommands.inc): `Permission.set/get`, `Privacy.preview/delete` 네이티브 mailbox 명령. 빈 origin/global 설정, 지원하지 않는 결정·권한, 잘못된 삭제 범위는 거절한다.
- 위치 거절은 `GEOLOCATION`과 `GEOLOCATION_WITH_OPTIONS`의 approximate/precise 거절을 함께 저장한다. reset은 override를 제거한다. JS의 permissions API를 덮어쓰거나 성공값을 가짜로 반환하지 않는다.
- 쿠키는 `Storage.getCookies`로 열거하고 소유 domain이 명시한 domain 또는 점 경계 하위 도메인인 항목만 선택한다. 이름·domain·path·partitionKey를 유지해 `Network.deleteCookies`를 실행한다. opaque partition은 성공으로 숨기지 않고 거절한다.
- origin 저장소는 검증된 명시 목록에만 `Storage.clearDataForOrigin(local_storage,indexeddb,cache_storage,service_workers)`를 순차 호출한다. 쿠키 삭제를 이 origin API에 맡기지 않는다. 엔진 오류는 완료한 단계 수를 포함한 부분 실패로 반환한다.
- preview는 데이터에 쓰지 않으며 `allSiteData:false`와 현재 범위를 반환한다. 실행 시 쿠키 목록을 다시 읽으므로 고정된 삭제 계획 토큰이나 원자적 트랜잭션은 아니다.

## 실제로 확인한 동작

권한 네 종류에서 처음 `prompt` → 명시적 거절 후 `denied` → 요청 거절 → 정상 재실행 후 `denied` 유지 → reset 후 `prompt`를 확인했다. 위치 요청은 시간 초과/무응답 대신 오류 코드 1을 반환했다. 초기화 후 카메라·마이크 요청을 새로 거절하는 callback도 query를 `denied`로 바꿨다. 별도 B origin은 `prompt`를 유지했다.

삭제 fixture는 a.test, sub.a.test, b.test, evil-a.test, a.test.evil.test다. 각 사이트에 HttpOnly 로그인 쿠키·LocalStorage·IndexedDB·CacheStorage·service worker를 만든 뒤 a.test와 sub.a.test만 삭제했다. 공유 Domain 쿠키, 별도 path 쿠키, 다른 최상위 사이트에 분할된 a.test 소유 쿠키도 제거됐다. B와 유사 이름 사이트의 인증 및 네 저장소는 유지됐고 a.test 안에 분할된 **b.test 소유** CHIPS도 유지됐다. 빈 범위와 외부 origin 혼입 요청은 쓰기 전에 거절됐으며 preview는 데이터를 바꾸지 않았다. 반복 삭제와 삭제 후 신규 로그인도 확인했다.

보안 회귀는 기존 11차 기준에 미디어 query 일치 2개를 추가했다. 위치는 **native 명시 차단을 먼저 설정한 조건**이다. 원래 미설정 prompt의 callback 무응답 자체가 고쳐졌다고 해석하지 않는다. iframe 미디어 거절·요청 origin 로그, 다른 origin DOM 접근 차단, 네이티브/Node 진입점 미노출, 웹 메시지의 정책 변경 불가, 로컬 파일·외부 scheme 차단, 웹 제목으로 앱 종료 불가를 확인했다.

## 남은 경계와 판정

**G06 전체 통과 아님:** OS 권한 허용·거부·복구, 실제 카메라·마이크 장치, 위치 prompt에서 앱 승인 UI로 이어지는 경로는 미검증이다. 일부 Chromium 권한은 top-origin 단위다. 현재 설정 명령은 요청 origin과 top-level origin이 다른 경우 거절하며, 독립적인 origin 쌍 예외를 지원한다고 주장하지 않는다. 모든 권한 종류의 제품 정책 구현도 아니다.

**G04 전체 통과 아님:** domain은 호출자가 명시하며 PSL 기반 사이트 추론·public suffix 차단을 구현하지 않았다. origin 목록도 호출자가 제공한다. 미방문/목록 누락 origin과 모든 partitioned storage key를 자동으로 찾지 않는다. B 소유 CHIPS 보존은 이번 소유 도메인 삭제의 정의이며, “A에 연결된 모든 제3자 데이터 삭제”를 검증한 것이 아니다. 기간·종류 선택, HTTP cache·sessionStorage 등 다른 데이터, 열린 탭/worker의 지속 쓰기, 재실행 후 삭제 상태, 장애 주입·중단·부분 실패 복구, 전역 동시 삭제 조정·명령 timeout은 미검증/미구현이다. 테스트는 한 삭제 명령씩 실행했고 제품 D06 범위를 확정하지 않았다.

**채택:** 이번에 정의한 거절·초기화 및 명시 범위 삭제는 검증 통과. G02와 통합된 제품 소스의 전체 수용 검증이 아니므로 CEF 전체 채택 보류를 유지한다. 기존 Stage9/Stage11/G02 소스를 덮어쓰지 않았다.

## 재현

프로젝트 루트에서 순서대로 실행한다. 각 runner는 격리된 로컬 HTTPS fixture와 고유 evidence/profile을 생성한다. 테스트 프로필은 삭제하지 않는다. 개인 계정·기존 브라우저 프로필이나 macOS 권한은 변경하지 않았다.

```sh
python3 validation/cef-spike/build-permission-privacy-probe.py
python3 validation/cef-spike/permission-privacy.py
python3 validation/cef-spike/permission-security.py
```

빌드 대상은 `build/permission-privacy-probe/JenaProbe.app`이다. 실행 폴더에는 해당 테스트·native 소스·빌드 스크립트 snapshot과 runtime.log를 보존했다. Swift 정책 서비스는 기존 stage7을 사용한다.

## API 확인 근거

고정 배포본의 `cef_request_context.h` 및 `cef_types_content_settings.h`를 우선 확인했다. 구조화된 위치 설정의 직렬화와 enum 값, 권한 범위는 Chromium의 [GeolocationSettingDelegate](https://chromium.googlesource.com/chromium/src/+/main/components/content_settings/core/browser/geolocation_setting_delegate.cc), [PermissionOption](https://chromium.googlesource.com/chromium/src/+/main/components/content_settings/core/common/content_settings.h), [권한 등록](https://chromium.googlesource.com/chromium/src/+/main/components/content_settings/core/browser/permission_settings_registry.cc), [content settings 등록](https://chromium.googlesource.com/chromium/src/+/main/components/content_settings/core/browser/content_settings_registry.cc)을 참고했다. main 소스가 고정 배포본과 동일하다고 가정하지 않고 실제 엔진의 요청·query·재실행 결과로 확인했다.
