# 제품 엔진을 시스템 WebKit으로 교체

- 배경: CEF 공식 배포본에 H.264/AAC가 없어 TikTok 영상이 재생되지 않았다(`2026-11-13-fedcm-login-and-codec-diagnosis.md`). 코덱 포함 CEF 소스 빌드는 약 이틀간 다운로드 단계에서 끝났고 사용자가 엔진 교체를 결정했다.
- 사전 실험: `validation/webkit-spike`. WKWebView에서 TikTok 추천 피드 영상 디코딩·재생(720×1280)을 확인했다. 사용자가 Pinterest Google 로그인을 비밀번호와 2차 이메일 인증으로 완료했고 팝업 자동 종료 후 Pinterest 복귀를 로그로 확인했다. 패스키 인증은 실패했다.
- 변경: `Sources/browser/webkit/WebKitBrowserRuntime.swift` 추가. 기존 `BrowserRuntime`·`BrowserPrivacy`·`SiteSettingsEngine` 계약을 구현한다. 공통 코드는 `ProductBrowserRuntime` 별칭으로 엔진을 참조한다. CMake에 `JENA_ENGINE`(기본 WEBKIT, CEF 선택 가능)을 추가했다. CEF 소스·빌드 스크립트·기존 산출물은 삭제하지 않았다.
- 동작 차이: 팝업은 클릭으로 연 것만 수용(자동 팝업 허용 설정 없음), 사이트 설정은 카메라·마이크·팝업만 지원, 사이트 데이터 삭제는 도메인 단위, 페이지 이탈 확인·위치·알림·사이트별 쿠키 설정·패스키 미지원. User-Agent는 설치된 Safari 버전에 맞춘다.
- 추가: 실행 인자의 http/https 주소를 탭으로 연다.
- 확인: Swift 6 모드 Debug 빌드 성공(`build/product-webkit`, 앱 1.1MB). 격리된 홈에서 실행해 Pinterest 로그인 페이지·TikTok 로드, 제목·주소 표시, 방문 기록 저장, 클릭 없는 Google 팝업이 열리지 않음을 확인했다.
- 미확인: 새 제품 앱에서의 Google 버튼 클릭 로그인, 탭 UI 조작, 링크 새 탭 정책, 카메라·마이크 허용, 사이트 데이터 삭제, 파일 선택 창, JS 대화상자는 실행 확인하지 않았다.
