# 제품 프로그램 구조 정리

사용자의 요청에 따라 Sources의 기능별 디렉터리, Resources, Configuration, BuildSupport를 생성했다. 제품 실행 코드는 아직 없으며 .gitkeep은 디렉터리 보존용이다. 프로그램 구조 문서에 화면·기능·CEF·OS·저장 책임, 타입 배치, 프로필과 탭 수명, 기존 코드 연결 표와 제품 구현 순서를 정리했다.

기술 설계의 상태·모듈 구조·진행 순서를 현재의 CEF 채택 및 검증 종료 결정에 맞춰 좁게 갱신했다. design-validation은 과거 기록을 보존하고 상단에 종료 결정을 추가했다. 변경 전 문서는 docs/backups/before-program-structure-*에 보존했다. 상세 결정과 절충은 architecture-log/2026-11-12-product-structure.md를 참조한다.

사용자 지시대로 빌드·테스트·새 검증은 수행하지 않았다. 기능·UI 구현 완료로 보고하지 않는다. 진행 중 사용자가 Jena G06 Permissions 창 종료를 요청해 Probe.quit을 보냈고, CEF_SHUTDOWN_RETURNED와 해당 앱·helper 프로세스가 없음을 확인했다. 다시 실행하지 않았다.
