# 제품 빌드와 네이티브 연결

상태: Accepted. 프로그램 구조에 이어 제품 프로젝트 연결을 요청받았다.

전제: macOS 우선 로컬 앱, 기존 CEF 배포본 재사용, 추가 기술 검증 금지. 현재 저장소에는 Xcode 프로젝트 생성기가 없고 CMake와 Xcode가 설치돼 있다.

결정: 루트 CMakeLists.txt로 Xcode 프로젝트를 생성한다. JenaWeb(Swift), CEFBridge(Objective-C++ 정적 라이브러리), JenaWebHelper(C++)를 타깃으로 구분한다. 제품 프로젝트의 wrapper는 CEF 배포본 소스로 별도 빌드하고 검증용 라이브러리 빌드 결과나 실행 파일에는 의존하지 않는다. 별도 프로젝트 생성기 설치와 pbxproj 직접 관리는 선택하지 않았다. CMake 도입은 macOS 프로젝트 생성 목적이며 OS 공유 설계를 도입하지 않는다.

Swift 기능 코드의 BrowserRuntime 계약을 CEFBrowserRuntime이 구현한다. Objective-C delegate는 UI 실행 문맥에서 Swift 이벤트와 NSView 호스트 연결만 담당한다. 엔진 포인터와 내부 DevTools 명령은 bridge 안에 유지한다. 기존 G02의 isolated-world 링크 분류 스크립트와 관리 popup 생성 경로를 옮겼다. 쿠키·개인정보·권한 UI와 저장소는 후속 제품 기능이다.

트레이드오프: 초기 기능들은 하나의 Swift 앱 타깃에 있어 내부 의존성은 폴더 규칙으로 관리한다. ObjC delegate는 @preconcurrency로 Swift와 연결하며 CEF UI thread가 macOS 앱 메시지 루프를 처리하는 진입 구조를 사용한다. 별도의 큐로 이 경계를 변경할 때는 MainActor 전달도 함께 변경해야 한다. 제품 계약은 CEF 타입을 노출하지 않는다.

개발 기본값은 웹 검색·현재 탭 열기·마지막 탭 닫기 후 빈 탭 유지다. 검색엔진은 화면에서 선택하도록 했고 이 기본값을 최종 PRD 정책으로 확정하지 않는다. 패키징은 동일 앱 경로/식별자를 유지하며 로컬 ad-hoc 서명만 적용한다. 제품 빌드는 완료했고 자동 실행이나 추가 기능 검증은 하지 않았다.
