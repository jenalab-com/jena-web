<p align="center"><img src="icon-1024.png" width="128" alt="Jena Web icon"></p>

# Jena Web

[English](README.md) | **한국어**

Swift·AppKit UI와 macOS 시스템 WebKit 엔진으로 만드는 단순한 macOS 브라우저. 웹 페이지 보기, 영상 재생, 로그인·쿠키 유지 같은 기본 기능에 집중하며 복잡한 보안 정책은 두지 않는다.

- [프로그램 구조](docs/program-structure.md)
- [개발 기록](docs/devlog)

## 내려받기

[Releases](https://github.com/jenalab-com/jena-web/releases)에서 `JenaWeb-<버전>-macos.zip`을 받아 압축을 풀고 `JenaWeb.app`을 응용 프로그램 폴더로 옮긴다. macOS 13 이상이 필요하다.

앱은 Apple 공증을 받지 않은 ad-hoc 서명이라 처음 열 때 macOS가 막는다. **시스템 설정 → 개인정보 보호 및 보안**에서 **그래도 열기**를 누르거나 터미널에서 다음을 실행한다.

```sh
xattr -dr com.apple.quarantine /Applications/JenaWeb.app
```

## 빌드와 실행

```sh
cmake -S . -B build/product-webkit -G Xcode
cmake --build build/product-webkit --config Debug --target JenaWeb
```

- 앱: `build/product-webkit/Debug/JenaWeb.app`, Xcode 프로젝트: `build/product-webkit/JenaWeb.xcodeproj`.
- 엔진을 내려받거나 빌드하지 않는다. 영상 코덱(H.264·AAC·HEVC)은 macOS의 것을 쓴다.
- 실행 인자로 준 http/https 주소는 탭으로 연다. 인자가 없으면 빈 탭으로 시작한다.
- 로컬 개발용 ad-hoc 서명을 쓴다. 배포 서명·공증·업데이트는 미구현이다.

## 기능

- 주소·검색 입력, 검색엔진(Google·Bing·네이버) 선택, 웹·이미지 검색.
- 탭 생성·전환·닫기, 뒤로·앞으로·새로고침·중지. 마지막 탭을 닫으면 빈 탭을 유지한다.
- 링크 열기 방식(현재 탭/새 탭). ⌘·⇧·가운데 클릭은 항상 새 탭으로 연다.
- 팝업: 클릭으로 연 팝업을 엔진이 만든 탭으로 수용해 `window.opener`와 로그인 문맥을 유지한다. 클릭 없는 자동 팝업은 엔진이 막는다. Pinterest의 Google 로그인을 이 경로로 확인했다.
- 북마크(⌘D 추가, ⌘⇧B 목록), 방문 기록(⌘Y), 개인정보 관리, 현재 사이트 설정(⌘,).
- 다운로드: 파일 링크에서 저장 위치를 선택한다. 완료 후 Finder에서 확인할 수 있다. 기존 파일 덮어쓰기·중단 후 재개·다운로드 목록은 아직 지원하지 않는다.
- 탭 아이콘은 앱이 받아온다. 외부 페이지가 로컬·사설 주소로 지정한 아이콘은 건너뛰며, 그런 주소의 페이지 자신의 아이콘은 그대로 받는다.

## 데이터 위치

- 앱 DB(설정·북마크·방문 기록): `~/Library/Application Support/local.jena.web/AppData/app.sqlite`.
- 웹 로그인·쿠키·저장 데이터: WebKit 기본 저장소(`~/Library/WebKit/local.jena.web` 등). 앱 DB와 분리된다.
- 사이트 설정: 앱 설정(UserDefaults, `siteSettings.*`).
- 저장소 초기화/읽기에 실패하면 원본을 삭제하지 않는다. 설정은 앱 메뉴의 **설정 다시 불러오기**, 북마크는 목록의 **새로고침**으로 재시도한다.

## 방문 기록과 개인정보 관리

- 성공한 HTTP/HTTPS 주 문서 로드와 로드 후 주소가 바뀌는 페이지 내 이동(SPA)을 기록하고 최근 500건을 보여준다. 같은 주소의 반복 알림은 중복 저장하지 않는다.
- 개인정보 관리에서 방문 기록(기간 선택), 지정 사이트의 쿠키·저장 데이터, 모든 사이트의 HTTP 캐시를 확인 후 삭제한다.
- 사이트 데이터 삭제는 입력한 사이트가 속한 도메인 전체(하위 도메인 포함)가 대상이다. 열린 탭은 삭제 후 새로고침한다.

## 사이트 설정

- 카메라·마이크: 사이트 허용과 macOS 허용이 모두 필요하다. 미허용 요청은 안내 후 보류하고 iframe 요청은 거절한다.
- 팝업: 기본값·허용은 클릭한 팝업만 연다. 차단은 로그인 창을 포함해 그 사이트의 모든 팝업을 막는다.
- 위치·알림·쿠키의 사이트별 설정은 WebKit 엔진에서 지원하지 않으며 화면에 미지원으로 표시한다.

## 아직 없는 것

외부 앱 링크(mailto 등), 페이지 이탈 확인창, 웹 알림, 패스키 로그인.

## 이전 CEF 엔진

2026-11-13에 CEF에서 WebKit으로 교체했다. CEF 공식 배포본에는 H.264/AAC 코덱이 없어 mp4 영상이 재생되지 않았고, 코덱 포함 소스 빌드는 완료하지 못했다. 경위는 `docs/devlog/2026-11-13-*.md`에 있다.

CEF 어댑터(`Sources/browser/cef`, `Sources/browser/bridge`)와 빌드 절차([BuildSupport/README.md](BuildSupport/README.md))는 남겨 두었고 `-DJENA_ENGINE=CEF -DCEF_ROOT=...`로 빌드할 수 있다. CEF 프로필(`WebProfiles`)의 로그인은 WebKit으로 이전되지 않는다.

2026-11-14에 CEF 배포본과 과거 검증 자료(`validation/`), CEF 빌드 산출물(`build/product`, `build/product-engine-lock`, 코덱 빌드 기록)을 삭제했다. CEF로 다시 빌드하려면 배포본을 새로 내려받아 `CEF_ROOT`로 지정해야 한다.

## 라이선스

[MIT](LICENSE)
