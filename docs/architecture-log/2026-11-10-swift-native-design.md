# Swift 기반 macOS 네이티브 설계 결정

- 날짜: 2026-11-10
- 상태: Swift·네이티브 UI 방향 Accepted by user; AppKit/SwiftUI 역할 배분과 CEF 연결 Provisional
- 대체 대상: [기존 기록](2026-11-10-desktop-design.md)의 A01·A03
- 적용 문서: [기술 설계](../technical-design.md), [검증 계획](../design-validation.md)

## 맥락과 가정

사용자는 OS 공통화보다 macOS 우선 개발을 원하며 Swift를 예상했다. Electron·React를 기본안으로 삼는 데 동의하지 않았고 UI 흐름과 반응성을 우선한다고 명시했다. 이후 이 방향으로 설계 문서 수정을 요청했다.

Blink 요구는 유지한다. Windows는 장기 지원 목표에서 삭제하지 않지만 현재 설계의 코드 공유·UI 추상화 기준으로 삼지 않는다. 네이티브 UI 자체가 성능을 보장한다고 가정하지 않는다.

## 선택과 대안

- Electron·React 공통 UI: 이번 기본안에서 철회한다.
- Swift + AppKit/SwiftUI: 앱 구성 방향으로 채택한다. 창·탭·입력·웹 호스트는 AppKit 중심, 보조 화면은 SwiftUI 검토를 제안한다. 정확한 역할은 성능·접근성 검증 후 결정한다.
- Blink 통합: CEF와 Objective-C++ wrapper를 첫 검증안으로 제안한다. 공개 API로 로그인·권한·선택 삭제·쿠키 정책을 충족해야 채택한다.
- WebKit 전환: 기존 Blink 요구를 바꾸므로 이번 수정에서 선택하지 않는다.
- SQLite: UI 변경과 독립적인 기존 저장소 후보로 유지한다.

## 구조와 비용

Swift UI와 서비스는 타입 계약을 사용한다. CEF의 프로세스 메시지·C++ 참조·스레드는 wrapper 내부에 격리한다. 웹 UI preload·IPC 구조를 제거하고 네이티브 명령을 웹페이지에 노출하지 않는다.

이 방향은 macOS 입력·창 동작을 직접 제어할 수 있지만 CEF 메시지 루프·helper·sandbox·서명, Swift/C++ 객체 수명 관리 비용이 생긴다. Windows 포팅 비용을 지금 줄이려는 구조는 추가하지 않는다.

## 검증과 보존

G01–G09는 미실행이다. 특히 선택 삭제·서드 파티 쿠키·Swift/CEF 생명주기 검증 전에는 CEF 채택을 확정하지 않는다. 실패해도 Electron 복귀나 WebKit 변경을 임의로 결정하지 않는다.

변경 전 문서는 docs/backups/before-swift-design-20261110-225227/에 보존했다. 기존 원안·기획서·PRD, 데이터 모델과 탐색·삭제 요구는 유지한다. 옛 결정은 삭제하지 않고 Superseded로 표시했다.
