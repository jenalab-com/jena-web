# CEF 검증 10차: 탐색·새 브라우저·검색 제공처

## 판정

**G02는 보류다.** 일반 링크·폼·팝업 fixture 17개 항목은 통과했지만, 사용자 동작으로 실행된 JavaScript 이동을 일반 링크로 오인하는 반례가 재현됐다. 현재 OnBeforeBrowse 분류 조건을 제품에 그대로 채택하지 않는다. CEF 전체가 불가능하다는 결론은 아니며 탐색 의도 검출 경로를 보완해야 한다.

## 구현 범위

- [Stage10Probe.mm](../../validation/cef-spike/Stage10Probe.mm): 기존 검증 adapter에서 분리했다. 최대 16개 browser slot과 테스트용 Probe.route/close를 추가했다. 별도 AppKit 창을 관리 브라우저의 호스트로 사용한다. 실제 탭 바·TabService 구현이 아니다.
- 일반 링크 후보는 main frame, user gesture, GET, TT_LINK, 비리디렉션, 다른 문서의 HTTP(S) URL 조건으로 분류했다. 새 browser를 만들고 원본 이동을 취소하는 **검증 후보 로직**이다.
- OnBeforePopup에서 CEF가 생성하는 popup의 windowInfo와 client를 지정해 native 호스트에 수용했다. popup URL을 별도 GET으로 다시 요청하는 방식을 사용하지 않았다.
- 사용자 동작 없는 popup은 시험 정책상 거절한다. 이는 제품 기본 팝업 정책 확정이 아니다. 지연 실행된 인증 popup의 호환성은 미검증이다.
- [navigation-stage10.py](../../validation/cef-spike/navigation-stage10.py): CDP Input.dispatchMouseEvent로 fixture 요소를 누르고 서버가 받은 메서드·본문과 browser 상태를 검사한다.

새 browser 최초 탐색 전에 Swift 쿠키 정책이 모두 적용되는지까지 이 adapter에서 보장한 것은 아니다. 6~9차 정책 적용 시험과 이번 popup 초기 탐색 경합을 구분한다. 외부 스킴·다운로드·권한을 포함한 제품 보안 경로도 아직 구현하지 않았다.

## 기본 탐색 결과

[실행](../../validation/cef-spike/evidence/navigation-stage10-20261111-111327/results.json): **17/17 항목 통과**, 관리 browser 6개 생성·종료, 앱 종료 코드 0, CefShutdown 반환, 네트워크 서비스 재시작 0회.

- 현재 browser 링크 이동, 새 browser 설정에서 목적지 로드와 원본 페이지 보존
- 내부 앵커 유지, fixture의 페이지 내부 미리보기 표시
- GET·POST 폼의 메서드와 한글·공백·`&`·`+` 값 보존
- 현재 browser에서 302 리디렉션 도착
- target=_blank의 native 호스트 수용과 원본 유지
- 새 창 POST의 메서드·본문 보존
- 다른 origin으로 여는 스크립트 popup의 opener 유지와 원본 창으로 postMessage 복귀

마지막 항목은 OAuth에 필요한 문맥 보존의 기초다. 실제 OAuth 공급자·계정·쿠키·동의 화면·redirect URI 검증을 통과한 것이 아니다. fixture 미리보기는 Google·네이버 실제 이미지 미리보기 조작을 대신하지 않는다. 중복 생성·뒤로 가기·수정키 클릭 전체를 검사한 것도 아니다.

## 반례와 실패 자료

[의도 구분 시험](../../validation/cef-spike/evidence/navigation-stage10-intent-20261111-111533/results.json): **0/2 항목 통과**. 버튼 onclick이 location.href를 변경하도록 만들고 Runtime.evaluate의 userGesture=true로 버튼을 실행했다. 새 browser가 만들어지고 원본 경로는 `/`에 남았다. 이 시험의 사용자 동작은 CDP가 부여한 것으로, 실제 하드웨어 마우스 클릭 시험과 구분한다.

즉 CEF의 user gesture와 TT_LINK 정보만으로 일반 `<a>` 탐색과 JavaScript 이동을 구별할 수 있다는 가정이 반증됐다. 확인된 일반 링크만 새 browser 정책에 넘기는 추가 경로가 필요하다. 클릭 정보를 쓰더라도 비신뢰 DOM이므로 권한·파일 접근의 근거로 사용하면 안 된다.

[첫 진단 실행](../../validation/cef-spike/evidence/navigation-stage10-intent-20261111-111417/results.json)은 삽입한 버튼에 마우스 입력을 보냈지만 탐색 callback 자체를 관측하지 못했다. 해당 결과를 분류 로직 통과 근거로 쓰지 않았다. 소스·로그를 보존하고 userGesture가 지정된 직접 버튼 실행으로 재현 조건을 바꿨다. 첫 실행은 1/2 assertion이 통과했으나 전체 상태는 실패다.

## 실제 검색 제공처

[search-stage10.py](../../validation/cef-spike/search-stage10.py), [실행 결과](../../validation/cef-spike/evidence/search-stage10-20261111-111347/results.json): **7/8 항목 통과**, 전체 실행 상태는 실패다. 개인 정보가 아닌 시험 검색어 `고양이 그림`을 URL 인코딩해 Google·네이버 웹·이미지 검색 페이지를 열었다. 기존 7차 앱을 사용한 페이지 접근 시험으로, 10차의 새 링크 분류 로직을 실제 제공처에서 검증한 것은 아니다.

| 제공처 | 검색어 보존 | 로딩 완료 관측 | 콘텐츠 관측 |
|---|---|---|---|
| Google 웹 | 통과 | 25초 내 complete 미관측: 실패 | 검색 제목·결과 텍스트·링크·이미지 존재 |
| Google 이미지 | 통과 | 통과 | 이미지 검색 제목·결과 텍스트·이미지 존재 |
| 네이버 웹 | 통과 | 통과 | 검색 제목·결과 텍스트·링크·이미지 존재 |
| 네이버 이미지 | 통과 | 통과 | 이미지 검색 제목·결과 텍스트·이미지 존재 |

Google 웹의 readyState는 관측 종료 시 loading이었다. 결과가 없었다거나 CEF가 검색을 지원하지 않는다고 단정하지 않는다. 요청 지연의 원인과 사용 가능한 화면의 준비 기준은 추가 확인 대상이다. 결과 링크 클릭·이미지 미리보기·실제 사이트 이동·CAPTCHA·로그인 상태별 동작은 이 공개 페이지 시험의 통과 범위가 아니다.

## 다음 판단에 필요한 항목

- G02: 일반 링크와 스크립트 탐색을 구분하는 경로 보완 및 반례 재검증. 현재 후보는 채택 보류.
- G07: Google·네이버의 실제 결과 클릭·미리보기, 사용자 직접 계정 인증, OAuth 복귀.
- G05·G09: 새로 생성되는 popup의 첫 요청과 정책 초기화 순서, 생성 취소·slot 재사용·opener 종료.
- 11차 권한·보안 검증에서 이번 링크 후보를 신뢰 가능한 제품 경계로 취급하지 않는다.

12차는 채택 판단을 정리하는 목표이며 미해결 G02를 통과로 바꾸는 기한이 아니다. 이번에는 제품 코드의 전체 재작성이나 PRD 범위 축소 없이 후보의 한계를 검증 기록으로 남겼다.

## 재현과 보존

```sh
python3 validation/cef-spike/build-stage10-probe.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-stage10.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-stage10-intent.py
validation/cef-spike/.venv/bin/python validation/cef-spike/search-stage10.py
```

macOS arm64, Swift 6 모드, CEF 156.0.27, sandbox helper를 사용했다. 모든 실행의 프로필·로그를 보존했고 강제 프로세스 종료는 하지 않았다. 집계는 [stage10-summary.json](../../validation/cef-spike/evidence/stage10-summary.json)에 있다. 실패 실행을 성공 합계로 숨기지 않는다.
