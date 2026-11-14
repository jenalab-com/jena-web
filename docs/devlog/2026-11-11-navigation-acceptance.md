# G02 전체 수용 검증과 탐색 구현 방식 확정

## 결정

**G02에 정의한 탐색 수용 시험을 통과했으며, 아래 탐색 분류·관리 브라우저 생성 방식을 확정한다.** 사용자가 확인한 범위는 G02이며 CEF 전체 채택(G01~G09)이 아니다.

최종 코드로 로컬 60개와 실제 Google·네이버 8개, **총 68/68 자동 확인 항목이 통과**했다. 실제 이미지 미리보기는 클릭 전후 캡처도 확인했다. 최종 6개 실행 모두 앱 종료 코드 0, CefShutdown 반환, 네트워크 서비스 재시작 0회였다. [집계 및 이전 실패 이력](../../validation/cef-spike/evidence/navigation-acceptance-summary.json).

이는 시험한 CEF 버전과 수용 매트릭스에 대한 구현 방식의 확정이다. 모든 웹사이트의 미래 변경을 보장하거나 제품 탭 UI·배포가 완성됐다는 의미는 아니다. 실제 로그인·OAuth 완료는 G07, 권한은 G06, 삭제는 G04로 별도 관리한다.

## 확정한 구현

기준 소스는 [NavigationFullProbe.mm](../../validation/cef-spike/NavigationFullProbe.mm), [link-policy.js](../../validation/cef-spike/navigation-full/link-policy.js), [빌드](../../validation/cef-spike/build-navigation-full-probe.py)다. 이전 10차 후보와 29개 회귀 버전은 재현 자료로 보존한다.

1. **일반 링크:** 격리 world에서 실제 anchor의 trusted 클릭을 확인하고 기본 동작의 target만 일시적으로 _blank로 바꾼다. URL·TT_LINK만 보고 일반 탐색을 취소·복제하던 방식은 사용하지 않는다.
2. **앵커·폼·스크립트·미리보기:** 내부 앵커, download·명시적 target, anchor가 아닌 동작은 변환하지 않는다. 이후 페이지 handler가 preventDefault를 호출하면 기본 탐색은 취소되므로 미리보기가 유지된다. 합성 .click()도 일반 사용자 링크로 승격하지 않는다.
3. **이벤트 전파 중단:** capture 단계에서 링크를 확인해 stopPropagation 때문에 정책이 빠지는 문제를 보완했다. 페이지의 이후 preventDefault는 그대로 존중한다.
4. **iframe:** 같은 origin의 frame에도 스크립트를 적용한다. 다른 origin의 OOPIF는 해당 CDP 세션에 Page.enable·스크립트 등록을 끝낸 뒤 기존 Swift 정책 서비스로 연결 이벤트를 전달해 실행 재개 순서를 유지한다. 설정 변경은 현재 child 세션에도 반영한다.
5. **명시적 새 탭·새 창 의도:** Command·중간 버튼 등의 OnOpenURLFromTab에서 CEF가 명시한 새 foreground/background tab·window disposition과 user gesture, HTTP(S)를 확인한 경우 관리 browser를 만든다. 기존 request context를 공유한다. 현재 문서 이동은 이 콜백에서 분류하지 않는다.
6. **popup·새 창 POST:** OnBeforePopup에서 엔진이 생성한 browser를 native 호스트에 수용한다. POST 본문을 새 GET으로 변환하지 않는다. opener와 cross-origin postMessage 복귀를 보존한다.
7. **후속 browser:** 생성한 browser에 링크 정책을 이어준다. 정책 설치 응답과 일반 시험 응답은 분리하고 CEF UI 작업 큐로 후속 명령을 보낸다.

DOM의 target 변경은 페이지에서 관측할 수 있다. 격리 world를 권한·파일 접근의 근거로 사용하지 않는다. popup 최초 요청의 쿠키 정책·생명주기, modifier별 foreground UI·실제 탭 바 배치는 각각 G05·G09·G08의 별도 검증 범위다. 명시적 새 문맥 콜백은 CEF가 제공한 URL로 열며, 모든 사이트의 referrer 의존성까지 보장한 것은 아니다.

## G02 수용 매트릭스

| 수용 항목 | 확인한 동작 | 근거 |
|---|---|---|
| 일반 링크·원본 보존 | 현재/새 browser 설정, 동적 링크, 원본 문서 유지 | 기본·확장 |
| 키보드·수정키 | Enter, Command, Shift, 중간 버튼 | 확장·특수 |
| iframe 링크 | 같은 origin·OOPIF에서 새 browser 열기, 원본 유지 | 확장 |
| 이벤트 간섭 | stopPropagation, 취소된 실제 클릭, 합성 클릭, 전역 이름 충돌 | 확장·경계 |
| target | _blank 수용, 기존 named frame 재사용, 임시 target 복원 | 기본·특수·경계 |
| 내부 앵커·미리보기 | 문서 내부 동작 유지, 실제 Google·네이버 확대 미리보기 | 기본·실제 사이트·캡처 |
| GET·POST 폼 | 메서드·한글·기호·본문 보존, popup POST | 기본 |
| 리디렉션 | 현재 문맥과 새 browser 각각 목적지 도착, 추가 browser 없음 | 기본·확장 |
| window.open | 사용자 동작의 cross-origin popup, opener·복귀 유지 | 기본 |
| 설정 해제 | 현재 페이지 및 기존 child session에서 새 창 변환 해제 | 경계·특수 |
| 기존 오분류 반례 | JavaScript 버튼 이동이 현재 문맥에 남음 | 반례 |

### 최종 실행

| 실행 | 통과 |
|---|---:|
| [확장](../../validation/cef-spike/evidence/navigation-full-20261111-150756/results.json) | 21/21 |
| [특수 입력·named target](../../validation/cef-spike/evidence/navigation-full-special-20261111-150831/results.json) | 10/10 |
| [기본 회귀](../../validation/cef-spike/evidence/navigation-full-regression-20261111-150839/results.json) | 17/17 |
| [기존 반례](../../validation/cef-spike/evidence/navigation-full-intent-20261111-150851/results.json) | 2/2 |
| [경계 회귀](../../validation/cef-spike/evidence/navigation-full-edge-20261111-150903/results.json) | 10/10 |
| [실제 Google·네이버](../../validation/cef-spike/evidence/navigation-providers-full-20261111-152728/results.json) | 8/8 |

## 실제 검색 결과와 이미지 미리보기

웹 검색어는 `국립중앙박물관`, 이미지 검색어는 `고양이 그림`을 사용했다. 검색 결과의 실제 링크를 클릭했으며 목적지 URL을 임의로 대입해 성공으로 처리하지 않았다. Google의 불투명한 /goto 중계 주소는 그대로 브라우저에 전달했다. 결과 링크의 외부 문서 도착과 검색 원본 URL 보존을 검사했다.

이미지 클릭 후 새 browser가 생기지 않고 검색 제공처 문맥이 유지되는 것을 자동 검사했다. 추가로 아래 화면에서 Google의 오른쪽 확대 미리보기와 네이버의 확대 미리보기를 확인했다.

- [Google 클릭 전](../../validation/cef-spike/evidence/navigation-providers-full-20261111-152728/Google-image-before.png), [클릭 후](../../validation/cef-spike/evidence/navigation-providers-full-20261111-152728/Google-image-after.png)
- [네이버 클릭 전](../../validation/cef-spike/evidence/navigation-providers-full-20261111-152728/Naver-image-before.png), [클릭 후](../../validation/cef-spike/evidence/navigation-providers-full-20261111-152728/Naver-image-after.png)

실제 계정 인증·결제·폼 제출은 수행하지 않았다. 키보드·마우스 입력은 CDP로 전달했고 실제 macOS IME·VoiceOver 시험으로 집계하지 않는다.

## 이번에 발견하고 보완한 문제

- **이벤트 전파·iframe 누락:** 최초 확장 시험에서 stopPropagation, same-origin iframe, OOPIF 정책 누락을 재현했다. capture 단계, 모든 frame의 스크립트 적용, 별도 OOPIF 세션 설치로 각각 보완했다.
- **Command 클릭의 원본 이동:** OnOpenURLFromTab의 기본 false 처리가 원래 browser의 최상위 frame에서 탐색을 허용했다. 새 문맥 disposition을 명시적으로 처리해 원본을 보존했다. Shift·중간 버튼도 다시 검사했다.
- **실제 사이트 시험 드라이버:** 고정 목적지 도메인만 찾는 선택 조건, Google의 불투명한 중계 URL, 고정 헤더 아래 잘못된 클릭 좌표, 목적지 대기에서 검색 URL과 비교하던 시험 코드 오류를 수정했다. 페이지 DOM·스크린샷으로 확인하고 일반 결과 제목의 실제 anchor를 선택했다. 외부 문서 도착과 모든 리소스의 load 완료도 구분했다.
- 지식 패널의 웹사이트 버튼 등과 일반 결과 링크를 혼동한 진단 시도는 수용 성공에 포함하지 않았다. 이전 오류·실패 실행은 삭제하지 않았고 집계의 earlierAttempts에 남겼다.

수정 후 최종 코드로 모든 로컬 회귀를 다시 실행했다. 실제 사이트 시험 드라이버 보완 이후에는 네이티브·링크 정책 코드를 추가 변경하지 않았다.

## 후속 관리 범위

이번 확정은 G02의 열거된 조건과 지정 제공처에서의 시험 결과다. 실제 사이트의 마크업·이벤트·브라우저 버전이 바뀌면 회귀 시험을 다시 실행한다. 극단적인 스크립트 변조, 모든 이벤트 순서, 모든 referrer·사이트별 특성을 전수 보장하지 않는다.

G06 권한 처리, G04 삭제 경계, G05 쿠키 정책 전체, G07 실제 계정 OAuth, G08·G09 제품 UI·안정성은 별도다. 이 결과로 전체 CEF 채택 보류를 해제하지 않는다. 제품 통합 시에도 기존 요구를 축소하지 않고 별도 게이트를 충족해야 한다.

## 재현

```sh
python3 validation/cef-spike/build-navigation-full-probe.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-full.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-full-special.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-full-regression.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-full-intent.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-full-edge.py
validation/cef-spike/.venv/bin/python validation/cef-spike/navigation-providers-full.py
```

macOS arm64, Swift 6 모드, CEF 156.0.27, sandbox helper 환경이다. 최종 성공 폴더에 소스 스냅샷을 저장했다. 시험 프로필과 초기 실패 자료를 보존했고 강제 프로세스 종료·기존 자료 삭제는 수행하지 않았다.
