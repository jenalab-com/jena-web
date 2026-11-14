# 코덱 지원 CEF 실제 빌드

- 사용자 요청에 따라 소스 다운로드와 코덱 지원 CEF 빌드를 시작했다. 기존 vendor, 제품 앱, 사용자 프로필과 실행 프로세스는 변경하지 않는다.
- 작업 폴더: build/cef-codecs-8078-arm64. 고정 revision의 공식 automate-git.py를 보존하고 SHA-256, 명령, GN 인자, PID, 상태를 build-status.json에 기록한다.
- 구성: arm64 Release, proprietary_codecs=true, ffmpeg_branding=Chrome, symbol_level=0, is_component_build=false. 컴파일 병렬 수 3. Debug 및 테스트는 빌드/실행하지 않는다. 최소 배포본 생성, 압축 생략.
- 현재 머신: macOS 26.6.2, Xcode 27.2, 메모리 16GiB, 시작 시 작업 볼륨 약 274GiB 여유. 고정 revision의 문서에 나타난 macOS 26.6+/Xcode 27.0 기준과 비교했다. 실제 빌드 결과는 별도로 기록한다.
- 런처: BuildSupport/run_cef_codecs.py. 작업 폴더는 새로 생성하며 기존 폴더가 있으면 중단한다. 강제 정리/force-clean 옵션은 사용하지 않는다. 런처 재실행으로 기존 소스를 삭제하지 않는다.
- 외부 브라우저 대안 없음. 빌드 산출물이 생성되기 전 코덱 지원 완료로 보고하지 않는다.

- 진행: CEF commit 및 depot_tools commit checkout 완료. gclient가 Chromium 본체 git clone을 시작했다. 실제 컴파일 전 소스 동기화 단계이며 실행 중 상태는 build/cef-codecs-8078-arm64/build-status.json과 build.log에서 확인한다. 공식 automate 프로세스는 소스 동기화 후 지정 Release 빌드와 최소 배포본 생성을 이어서 수행하도록 실행했다.
