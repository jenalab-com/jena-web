# 제품 소스

Swift·AppKit + CEF 기반 macOS 앱의 기능별 소스 골격이다.

책임, 타입 배치, 의존성, 페이지 수명과 기존 코드 연결 위치는 [프로그램 구조](../docs/program-structure.md)를 따른다. 앱 시작·화면·탭·탐색·CEF 연결 코드가 추가됐다. Xcode 프로젝트는 루트 CMakeLists.txt에서 생성한다. 설정·북마크·방문 기록의 SQLite 저장과 개인정보 삭제 화면을 연결했다. 사이트 권한·쿠키 기본 설정은 CEF 저장값을 읽고 변경하며 OS 상태는 macOS 경계에서 표시한다.

- `app`: 의존성 조립과 앱 생명주기
- `workspace`: AppKit 창·툴바·탭 표시·웹 호스트
- `search`부터 `settings`까지: 기능별 판단·상태·작업과 보조 화면
- `browser`: Swift 계약, WebKit 어댑터(`webkit`, 제품 기본), CEF 어댑터와 Objective-C++ 연결부(`cef`·`bridge`, `JENA_ENGINE=CEF`일 때만 빌드)
- `platform/macos`: macOS 기능
- `storage`: 앱 데이터 저장 구현

제품은 `validation/`을 의존성으로 사용하지 않는다. 기존 코드에서 필요한 동작을 이 구조에 연결하며, 실험 파일과 증거는 원래 위치에 보존한다.
