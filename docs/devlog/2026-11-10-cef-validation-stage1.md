# CEF 검증 1차 결과

## 실행 환경

- macOS 26.6.2, arm64
- Xcode Developer 경로: /Applications/Xcode.app/Contents/Developer
- Apple Swift 6.4.2, clang 도구 사용 가능, CMake 설치 확인
- CEF 156.0.27+ga10dae3 / Chromium 156.0.8078.88 macOS arm64 minimal
- 배포 아카이브 체크섬 확인 후 별도 validation/cef-spike/vendor에 압축 해제

## 변경과 목적

[독립 검증 코드](../../validation/cef-spike/README.md)를 추가해 Swift와 Objective-C++ 연결, 실제 CEF framework 로딩, NSView 소유권의 최소 전제를 실행으로 확인했다. 제품 코드·PRD·기존 프로필은 변경하지 않았다.

## 실제 실행 결과

[실행 로그](../../validation/cef-spike/evidence/native-probe.log):

1. Swift → Objective-C++ → 실제 CEF의 cef_version_info 호출 통과. Chromium major 156 반환.
2. AppKit NSView의 1,000회 frame 변경 후 동일 인스턴스 유지 확인.
3. autoreleasepool 종료 후 wrapper와 NSView 약한 참조가 nil인 것 확인.

이 결과는 초기 언어 연결과 객체 소유권만 확인한다. 뷰는 실제 브라우저 콘텐츠를 표시하지 않았으므로 스크롤·드래그 반응성이나 CEF callback 수명 검증으로 확대하지 않는다.

## API 조사와 불확실성

| 항목 | 확인한 근거 | 판단 |
|---|---|---|
| G04 선택 삭제 | 배포본에 DeleteCookies, ClearHttpCache, ExecuteDevToolsMethod 존재. DevTools Storage.clearDataForOrigin / clearDataForStorageKey 정의 조사 | 구현 후보 경로 존재. 기간·쿠키 도메인·partition 경계와 service worker 재생성은 런타임 미검증 |
| G05 서드 파티 쿠키 | 배포본의 SetContentSetting과 resource-request CookieAccessFilter 조사. DevTools Network.setCookieControls는 조사한 명세에서 experimental | 요청 쿠키 필터만으로 document.cookie 등까지 통제한다고 볼 수 없음. target 범위·새 탭·worker·예외·재실행 동작 검증 필요 |
| G09 연결·생명주기 | 실제 framework 버전 호출·NSView 소유권 시험 | 사전 조건 일부 통과. CEF 초기화·helper·메시지 루프·browser callback은 미실행 |

참조: [CEF request context](https://github.com/chromiumembedded/cef/blob/master/include/cef_request_context.h), [resource request filter](https://github.com/chromiumembedded/cef/blob/master/include/cef_resource_request_handler.h), [DevTools 명세](https://github.com/ChromeDevTools/devtools-protocol/blob/master/json/browser_protocol.json).

공식 헤더와 DevTools 명세 조사만으로 G04·G05를 통과 처리하지 않는다. 실험적 DevTools 제어는 안정적인 제품 계약이 아니므로, 고정 CEF 버전에서 동작하더라도 업데이트 회귀 검증이 필요하다.

## 문제와 처리

- Python urllib의 로컬 인증서 체인 오류로 다운로드가 실패했다. 인증서 검증을 끄지 않고 curl의 정상 HTTPS 검증 경로로 다운로드했다.
- CookieAccessFilter는 별도 헤더가 아니라 cef_resource_request_handler.h에 선언되어 있어 조사 경로를 수정했다.
- 선택한 minimal 배포본에는 framework와 API 헤더가 있다. 실행 앱·helper 구성은 별도 단계가 필요하다.

## 남은 검증

G01–G08은 런타임 미실행이며 G09도 전체 통과가 아니다. CEF 채택은 계속 잠정 상태다.

다음 단계는 sandbox를 유지하는 Swift 앱·CEF helper 초기화와 테스트 페이지 렌더링이다. 그 뒤 격리 프로필과 서로 다른 site의 fixture로 G04·G05를 실행한다. 기존 로그인 정보나 개인 브라우저 프로필은 재사용하지 않는다. 이번 단계에서 사용자 앱·서비스 종료나 프로필 삭제는 수행하지 않았다.
