# 탐색 분류 수정과 회귀 검증

## 문제와 변경

10차 후보는 CEF OnBeforeBrowse의 user gesture·GET·TT_LINK 조합을 일반 링크로 해석했다. 사용자 동작이 있는 버튼의 location.href 변경도 같은 조건에 들어가 원래 문맥을 잃고 새 browser로 열렸다.

수정 후보는 **탐색 요청을 URL만으로 취소·복제하지 않는다.** 격리된 JavaScript world에서 실제 링크의 기본 동작만 새 창 대상으로 바꾸고, 엔진이 생성한 popup을 기존 native 호스트에 수용한다. 스크립트 이동·폼 요청에는 이 변환을 적용하지 않는다.

기존 10차 소스·실패 결과를 보존하고 별도 검증 파일과 앱에 구현했다. 제품 앱의 TabService가 완성됐다는 뜻은 아니다.

## 구현 파일

- [link-policy.js](../../validation/cef-spike/navigation-fix/link-policy.js): 링크 처리의 단일 원본이다. 빌드 시 헤더로 생성해 native adapter에 포함한다.
- [NavigationFixedProbe.mm](../../validation/cef-spike/NavigationFixedProbe.mm): Page.enable 후 Page.addScriptToEvaluateOnNewDocument의 worldName과 runImmediately로 정책을 설치한다. 설정 변경 시 기존 등록을 제거하고 새 정책을 현재·후속 문서에 적용한다. CEF 내부 명령 응답을 일반 시험 응답과 구분하고 후속 명령은 CEF UI 큐로 예약한다.
- [build-navigation-fixed-probe.py](../../validation/cef-spike/build-navigation-fixed-probe.py): 별도 navigation-fixed-enabled-probe 앱을 만든다.
- [기본 회귀](../../validation/cef-spike/navigation-regression.py), [기존 반례](../../validation/cef-spike/navigation-intent-regression.py), [경계 회귀](../../validation/cef-spike/navigation-edge-regression.py).

10차 probe에서 가져온 웹 제목 기반 종료 장치는 포함하지 않는다. 종료는 테스트 드라이버의 Probe.close로 요청한다. 웹에 native 호출 함수를 추가하지 않았다.

## 링크 처리 규칙

격리 world의 window click listener에서 다음을 확인한다.

- 최상위 문서의 trusted 기본 클릭이며 수정키가 없음
- composedPath에 실제 HTMLAnchorElement가 있음
- 페이지가 preventDefault로 취소하지 않았음
- download 속성이 없고, 명시된 target 또는 base target이 없거나 _self임
- HTTP(S)이며 현재 문서의 내부 앵커 이동이 아님

이 경우 target을 잠시 _blank로 바꾸고 다음 task에서 원래 속성을 복원한다. preventDefault나 네이티브 URL 재요청으로 이동을 복제하지 않는다. 명시적 새 창·named target·폼·스크립트 이동은 엔진에 맡긴다.

페이지의 onclick 또는 일반 bubble handler가 미리보기를 열고 preventDefault를 호출한 경우 정책은 개입하지 않는다. .click() 같은 합성 이벤트는 userGesture가 지정된 CDP 평가에서 호출돼도 event.isTrusted가 false이므로 변환하지 않는다. 해당 호출의 원래 웹 동작 자체를 금지하는 정책은 아니다.

격리 world는 JS 상태와 전역 이름 충돌을 분리하지만 DOM은 공유한다. target의 일시적 변경은 페이지에서 관측할 수 있다. 따라서 이 스크립트를 보안 권한·파일 접근의 근거로 사용하지 않는다.

## 검증 결과

수정 후 기본 17개·반례 2개·경계 10개, **총 29/29 항목이 통과**했다. 세 성공 실행 모두 앱 종료 코드 0, CefShutdown 반환, 네트워크 서비스 재시작 0회를 확인했다. 실행별 결과와 초기 실패는 [집계](../../validation/cef-spike/evidence/navigation-fix-summary.json)에 함께 보존한다.

- [기본 17개 실행](../../validation/cef-spike/evidence/navigation-regression-20261111-144706/results.json): 현재/새 browser 링크, 원본 유지, 앵커·미리보기, GET·POST 메서드와 본문, 302, target blank, popup POST, cross-origin opener 복귀.
- [기존 반례 2개 실행](../../validation/cef-spike/evidence/navigation-intent-regression-20261111-144734/results.json): 버튼의 location.href 이동이 현재 browser에서 완료되고 새 browser를 만들지 않음.
- [경계 10개 실행](../../validation/cef-spike/evidence/navigation-edge-regression-20261111-144803/results.json): isolated state 비노출, 합성 클릭의 현재 문맥 유지, 실제 취소 클릭의 미리보기·원본 유지, 페이지 전역 이름 충돌, target 복원, 정책 비활성화.

기존 반례는 10차와 동일하게 Runtime.evaluate(userGesture=true)로 버튼을 실행한다. 기본 회귀와 취소 링크 시험은 대상 native 창을 활성화하고 렌더링을 기다린 뒤 CDP 마우스 입력을 보낸다. 이는 수동 하드웨어·키보드 수용 시험과 구분한다.

## 구현 중 실패와 보완

1. [첫 실행](../../validation/cef-spike/evidence/navigation-regression-20261111-144422/results.json)은 초기 링크 입력 후 탐색이 일어나지 않아 중단됐다. 검증 드라이버에 native 창 활성화와 두 frame 대기를 추가했다. 당시 분류 로직의 성공 근거로 쓰지 않는다.
2. [다음 실행](../../validation/cef-spike/evidence/navigation-regression-20261111-144541/results.json)은 폼 등 7개 항목 후 새 문서에서 정책이 동작하지 않아 새 browser를 받지 못했다. Page 도메인 활성화 순서가 누락돼 있었다. Page.enable을 성공시킨 뒤 스크립트를 등록하도록 수정한 후 같은 회귀가 통과했다.

실패 실행은 정상 종료했고 소스·로그를 보존했다. 수정 전 앱들도 별도 빌드 경로에 남겼다.

## 판정과 한계

**10차에서 재현한 JavaScript 이동 오분류는 수정됐다.** G02는 기존 반례 해결 및 부분 회귀 통과로 갱신한다. 전체 게이트나 CEF 채택을 확정하지 않는다.

- iframe 내부 링크에는 현재 정책을 설치하지 않는다. 최상위 문서로 범위를 제한했다.
- stopPropagation으로 window까지 전달되지 않는 클릭은 변환하지 않는다. 페이지의 이벤트 처리·SPA 라우터·동적 target 변경과 모든 순서 조합을 검증한 것은 아니다.
- modifier·키보드·named target·download는 코드에서 제외하거나 기본 동작에 맡기지만 각각의 제품 수용 시험은 남아 있다.
- 실제 Google·네이버 결과 클릭·이미지 미리보기, 실제 계정 OAuth는 이번 fixture 회귀의 통과 범위가 아니다.
- popup 첫 요청 전 쿠키 정책 적용, 생성 취소·종료 경합, 제품 탭 포커스 정책은 별도 잔여다.
- 11차 권한 문제와 9차 데이터 삭제 경계는 수정하지 않았다.

## 재현

```sh
python3 validation/cef-spike/build-navigation-fixed-probe.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-regression.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-intent-regression.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-edge-regression.py
```

macOS arm64, Swift 6 모드, 기존 CEF 156.0.27와 sandbox helper를 사용한다. 각 실행의 별도 프로필·mailbox·로그를 보존한다. 설계 상태 수정 전 원본도 docs/backups에 보존한다.
