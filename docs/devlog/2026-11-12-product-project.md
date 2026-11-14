# 제품 프로젝트와 첫 탐색 화면 연결

사용자가 프로그램 구조 다음 구현 진행을 요청했다. CMake에서 JenaWeb 앱, CEFBridge 정적 연결부, JenaWebHelper 타깃과 Xcode 프로젝트를 생성하도록 구성했다. 기존 배포본은 CEF_ROOT 빌드 입력으로 사용하고 wrapper는 제품 빌드 폴더에 따로 빌드한다. 검증 실행 파일을 제품에 링크하지 않는다.

제품 Sources에 Swift 계약·CEF 어댑터·TabService·검색 URL 구성·입력 처리·AppKit 창과 메뉴·제품 프로필 경로를 구현했다. 기존 link-policy.js를 제품 리소스로 복사했고 Native managed-popup 방식을 제품 페이지 ID·호스트 소유권에 맞춰 옮겼다. mailbox·고정 슬롯·진단 버튼은 제외했다. 현재 앱 식별자는 local.jena.web이며 프로필은 최초 실행 시 Application Support 아래 별도 생성한다.

이번에는 선택한 설정의 DB 저장, 북마크·방문 기록·권한·삭제 화면은 연결하지 않았다. 미지원 권한 요청은 요청 단위로 거절하고, 외부 스킴은 오류 안내한다. 앱의 새 알림 API를 호출하지 않아 이전 충돌을 재도입하지 않는다. 검색엔진은 사용자가 선택하며 웹/현재 탭/마지막 빈 탭 유지의 개발 시작값을 README에 명시했다. 이는 최종 제품 정책의 확정을 뜻하지 않는다.

UI는 검색과 자료 탐색에 집중한 AppKit 기본 구성이다. 별도 디자인 시스템은 도입하지 않았고 시각 디자인 최종본도 아니다. CMake를 쓰는 이유는 이미 있는 도구로 Xcode 프로젝트를 생성하고 C++ wrapper를 연결하기 위해서이며 OS 공통화 목적이 아니다.

사용자 요청에 따라 새 기능 검증·사이트 탐색·권한 수동 검사는 하지 않는다. 제품 컴파일과 패키징만 수행하며 앱은 자동 실행하지 않는다. 빌드 결과와 제한은 후속 문단에 기록한다.

## 빌드 결과

제품 Xcode 프로젝트 생성과 Debug JenaWeb 타깃 빌드가 완료됐다(`build/product-build.log`: BUILD SUCCEEDED). 산출물은 build/product/Debug/JenaWeb.app이다. 패키징 스크립트에서 기존 CEF framework와 역할별 Helper 번들을 포함하고 개발용 서명을 적용했다. 앱 실행·웹사이트 접속·권한 요청·기능 테스트는 수행하지 않았다. 빌드 성공을 기능 동작 완료 판정으로 확대하지 않는다.

첫 빌드의 Helper 코드 서명 identity 오류는 CEF CMake 기본 설정이 빈 identity를 지정한 문제였다. 제품 타깃에 개발용 identity 및 서명 설정을 명시해 해결했다. 앱 PRODUCT_BUNDLE_IDENTIFIER도 plist와 맞췄다. Xcode의 별도 iOS Simulator 버전 경고는 macOS 제품 빌드를 막지 않았으며 해당 환경을 변경하지 않았다.

종료는 모든 탭의 beforeunload를 한꺼번에 띄우지 않도록 순차 요청한다. AppComposition은 엔진 메시지 루프 동안 withExtendedLifetime으로 유지한다. 이 변경은 새로운 검증 절차가 아니라 제품 연결 코드의 구현이다.
