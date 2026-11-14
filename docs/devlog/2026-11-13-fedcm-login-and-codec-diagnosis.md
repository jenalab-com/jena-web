# Pinterest Google 로그인 무반응 수정과 TikTok 영상 재생 진단

## Pinterest Google 로그인

- 재현: 임시 프로필(`CFFIXED_USER_HOME`)과 `--remote-debugging-port`로 `build/product-engine-lock` 앱을 실행하고 `https://www.pinterest.com/login/`의 Google 버튼을 신뢰 입력으로 클릭했다. 사용자 프로필은 사용하지 않았다.
- 증거: 클릭 시 팝업 요청이 전혀 발생하지 않고 콘솔에 `[GSI_LOGGER]: FedCM get() rejects with NetworkError: Error retrieving a token.`만 기록됐다. `OnBeforePopup`에 도달하지 않으므로 2026-11-12에 추가한 팝업 사이트 설정은 이 증상의 원인이 아니었다.
- 원인: 엔진이 FedCM API(`IdentityCredential`)를 노출하지만 앱에는 계정 선택 화면이 없다. Google 로그인 스크립트가 FedCM 경로를 선택하고 화면 없이 실패한다.
- 변경: `JenaBridge.mm`의 `EngineApp::OnBeforeCommandLineProcessing`에서 브라우저 프로세스에 `disable-features=FedCm`을 추가한다. 기존 값이 있으면 병합한다.
- 확인: 추가 실행 인자 없이 새 빌드에서 `IdentityCredential` 미노출, 클릭 시 `accounts.google.com/o/oauth2/v2/auth` 팝업이 새 탭으로 열리고 Google 로그인 화면이 표시됐다.
- 미확인: 실제 계정으로 로그인을 끝내는 단계(자격 증명 입력, Google의 내장 브라우저 판정, Pinterest 복귀)는 실행하지 않았다.

## TikTok 영상 재생

- 증거: 사용자 프로필의 `cef.log`에 `DEMUXER_ERROR_NO_SUPPORTED_STREAMS`가 반복 기록돼 있고, 현재 엔진에서 `canPlayType('video/mp4; codecs="avc1.42E01E, mp4a.40.2"')`가 빈 문자열, VP9 WebM은 `probably`다.
- 원인: 사용 중인 공식 CEF 배포본에 H.264/AAC 코덱이 없다. 앱 코드로 해결할 수 없으며 `proprietary_codecs=true ffmpeg_branding=Chrome`으로 빌드한 엔진이 필요하다.
- 상태: `build/cef-codecs-8078-arm64`의 소스 폴더가 현재 없다. 코덱 엔진 산출물은 없다.

## 빌드

- `cmake --build build/product-engine-lock --config Debug --target JenaWeb` 성공. 로그: `build/fedcm-fix-build.log`.
- 검증에 사용한 앱 프로세스는 종료했다.
