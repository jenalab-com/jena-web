# 사이트 설정의 저장 원본과 OS 경계

## 배경과 가정
단일 macOS 제품 프로필과 소수의 AppKit 보조 창을 유지한다. CEF 채택은 확정됐으며 이번 작업은 제품 기능 연결이다.

## 결정
SiteSettingsWindowController → SiteSettingsService → SiteSettingsEngine → CEFBrowserRuntime/JenaBridge → CefRequestContext 공개 API로 읽고 변경한다. 허용·차단은 해당 콘텐츠 유형의 CEF 기본 범위를 사용하며 요청 사이트와 최상위 사이트를 같게 제한한다. 임의의 교차 origin 권한 쌍은 노출하지 않는다. 위치는 기존 연결 코드의 GEOLOCATION_WITH_OPTIONS도 함께 반영한다.

OS 권한 조회와 사용자 요청은 platform/macos/SystemPermissions가 담당한다. 웹의 미디어 callback은 AVFoundation 허용 상태와 CEF 사이트 허용값을 결합한다. iframe은 저장 정책 변경 없이 취소한다. 알림 API 혼용을 피하기 위해 현대 macOS 알림 요청/조회는 추가하지 않는다.

## 대안과 절충
앱 SQLite에 권한 값을 복제하면 엔진과 불일치할 수 있어 사용하지 않았다. 엔진 공개 API의 반환값을 UI에 표시하되 디스크 flush 완료나 런타임 결과를 별도로 확인했다고 주장하지 않는다. 기본값 복원 뒤 유효값이 허용으로 보일 수 있으며 이는 상속된 엔진 정책이다. 서드 파티 쿠키 제어와 요청 시 권한 팝업은 후속 구현 대상이다. 기존 요청을 보류하는 경로에 설정 안내를 연결해 현재 단계의 동작을 명확히 했다.
