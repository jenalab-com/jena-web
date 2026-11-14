# CEF 검증 2차: 렌더러·helper·정상 종료

## 변경과 실행 환경

1차와 동일한 macOS arm64 / Swift 6.4.2 / CEF 156.0.27 환경에서 실제 브라우저 프로세스와 helper를 실행했다. 제품 코드와 개인 브라우저 프로필은 사용하지 않았다.

- Swift 실행 진입점 → Objective-C++ RunBrowserProbe → CEF 초기화
- AppKit NSWindow/NSView에 Alloy 스타일 브라우저 호스팅
- CEF 공식 wrapper를 USE_SANDBOX=ON으로 빌드
- renderer/GPU 등 helper에서 CefScopedSandboxContext 초기화
- 고유 검증 프로필에만 캐시·CEF 로그 저장
- 외부 네트워크 사이트 대신 data URL의 테스트 HTML·JavaScript 실행

소스: [BrowserProbe.mm](../../validation/cef-spike/BrowserProbe.mm), [helper](../../validation/cef-spike/HelperProbe.cc), [빌드](../../validation/cef-spike/build-browser-probe.py), [실행](../../validation/cef-spike/run-browser-probe.py).

## 실행으로 확인한 결과

[성공 로그](../../validation/cef-spike/evidence/browser-runtime-2.log), 프로세스 종료 코드 0.

```text
PROBE_HELPER sandbox_initialized=true
CREATE_BROWSER accepted=1
CEF_INITIALIZED sandbox_requested=true
BROWSER_CREATED id=1
PASS: renderer JavaScript executed and title callback received
CLOSE_REQUEST
HOST_VIEW_DETACHED
BROWSER_BEFORE_CLOSE
CEF_SHUTDOWN_RETURNED
```

Swift 앱에서 실제 CEF 브라우저를 생성하고, renderer가 테스트 페이지 JavaScript로 변경한 제목을 browser callback에서 받았다. 종료 작업을 CEF UI task로 예약하고 호스트 뷰를 분리한 뒤 OnBeforeClose와 CefShutdown의 반환까지 확인했다.

helper의 sandbox 초기화 성공과 renderer 명령행의 seatbelt-client 인자를 확인했다. 이는 sandbox를 끄지 않고 구동했다는 증거이며, 파일·네트워크 접근의 모든 보안 격리 효과를 검증했다는 뜻은 아니다. 정식 서명·공증·배포는 수행하지 않았다.

## 실패와 수정

1. 현재 CEF 헤더는 C++20 concepts를 사용한다. C++17 빌드 실패 후 이 검증 앱의 컴파일 기준을 C++20으로 변경했다.
2. 최초 실행은 JavaScript callback까지 성공했지만 dispatch_after로 예약한 종료가 이 메시지 루프 구성에서 진행되지 않았다. 뷰 분리도 종료 생명주기에 명시적으로 연결하지 않았다.
3. CefPostDelayedTask(TID_UI)에서 CloseBrowser(false)를 호출하고 DoClose에서 호스트 뷰를 분리하도록 변경했다. 이 수정 후 새 프로필에서 전체 종료 경로가 완료됐다.
4. 최초 실행에는 LLDB로 프로필·사이트 데이터 변경 없이 호스트 뷰 분리와 비강제 CloseBrowser 요청을 시도했으나 정상 종료를 복구하지 못했다. 수정된 실행의 성공 확인 후 남은 최초 검증 프로세스만 SIGTERM으로 종료했다. 그 실행을 정상 종료 성공 사례로 집계하지 않는다. 로그와 프로필은 보존했다.

원인 해석의 한계: 이번 결과는 GCD/MainActor가 CEF와 항상 호환되지 않는다는 증거가 아니다. 현재 실행 루프 통합에서는 CEF task로 예약해야 정상 종료된다는 관찰이다. 제품 UI의 Swift Concurrency와 메시지 루프 공존은 추가 검증한다.

## 판정과 남은 작업

- G09 부분 통과: 초기화·helper·실제 렌더러·CEF task·정상 종료 경로 확인.
- G09 미검증: SwiftUI 반복 갱신, 다중 탭 callback 수명 경쟁, 재시작 반복, 사용자 닫기/beforeunload/OS 종료의 모든 경로.
- G08 미검증: 실제 화면 캡처 대조, IME·스크롤·드래그·접근성·프레임 시간. 제목 callback을 UI 부드러움의 증거로 취급하지 않는다.
- G04·G05 미검증: data URL은 유효한 사이트별 저장소·쿠키 검증 환경이 아니다. 다음 단계에서 두 개 이상의 site를 제공하는 로컬 HTTP(S) fixture를 구성한다.
- G01의 보안 공격 검증, G03 로그인 영속성, G06 권한, G07 실제 서비스 인증은 아직 미실행.

**판정: Swift + CEF의 최소 실제 실행 경로는 확인했다. 제품 아키텍처 채택과 전체 G09 통과는 아직 보류한다.**
