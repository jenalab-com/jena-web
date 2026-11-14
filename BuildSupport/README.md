# 제품 프로젝트 빌드

> 2026-11-13부터 제품 기본 엔진은 시스템 WebKit이며 CEF 없이 빌드한다(루트 README의 '엔진' 참고). 이 문서의 CEF 절차는 `-DJENA_ENGINE=CEF`로 빌드할 때만 해당한다.
> 2026-11-14에 CEF 배포본(`validation/cef-spike/vendor`)과 `build/product`, `build/product-engine-lock`, 코덱 빌드 폴더를 삭제했다. 아래에서 이 경로들을 현재형으로 설명한 부분은 과거 기록이다.

제품 소스는 `Sources/`, 빌드 타깃은 `JenaWeb`, `CEFBridge`, `JenaWebHelper`다. CMake는 macOS용 Xcode 프로젝트 생성에 사용하며 Windows 공통 구조를 의미하지 않는다.

기존에 내려받은 CEF 배포본을 `CEF_ROOT`로 지정한다. 검증용 실행 파일·프로필은 링크하거나 복사하지 않는다. 배포본은 현재 `156.0.27+ga10dae3+chromium-156.0.8078.88_macosarm64_minimal`을 사용한다. 새로운 CEF 버전은 별도 빌드 디렉터리를 사용한다.

```sh
cmake -S . -B build/product -G Xcode -DPROJECT_ARCH=arm64 -DCEF_ROOT="/absolute/path/to/cef_binary_156.0.27+ga10dae3+chromium-156.0.8078.88_macosarm64_minimal"
cmake --build build/product --config Debug --target JenaWeb --parallel 6
```

생성 프로젝트는 `build/product/JenaWeb.xcodeproj`, 앱은 `build/product/Debug/JenaWeb.app`이다. 앱은 빌드만으로 실행되지 않는다. Xcode의 JenaWeb scheme에서 실행하거나 Finder에서 앱을 열 수 있다.

현재 최소 OS 13.0은 빌드 설정이며 출시 지원 범위 확정은 아니다. 로컬 개발용 ad-hoc 서명을 사용한다. 배포 서명·공증·업데이트는 미구현이다. 앱 식별자는 `local.jena.web`으로 고정하며 기존 JenaProbe와 구분한다. 사용자 프로필은 앱 최초 실행 시 해당 식별자의 Application Support 아래에 생성한다.

## CEF 입력 고정과 별도 산출물

CMake 구성 시 `cef-input-lock.json`에 CEF 경로·버전 및 include/libcef_dll/cmake/framework의 SHA-256을 고정한다. 같은 경로에서 파일이 바뀐 경우도 실패한다. 코덱 활성화 여부는 이 해시로 판정하지 않는다. 공급본 내부의 빌드 출처는 별도로 관리해야 한다.

패키징은 lock과 입력을 다시 비교하고, 기존 앱 framework가 있으면 앱 옆 `<앱 이름>.cef-receipt.json`과 서명 후 framework 해시를 비교한다. 이전 입력 또는 영수증 없는 앱에는 덮어쓰지 않고 중단한다. 서명은 Mach-O를 바꾸므로 원본 배포본 해시와 서명 후 해시를 구분한다. 영수증은 앱 외부에 둬 서명 봉인을 바꾸지 않는다.

기존 `build/product`는 이전 방식으로 만들어졌으므로 그대로 보존한다. 이후 빌드는 새로운 디렉터리를 사용한다. 새 방식의 첫 산출물은 `build/product-engine-lock`이며 현재 기본 CEF를 사용한다. 이것이 코덱 지원 앱이라는 의미는 아니다.

## macOS arm64 코덱 빌드 준비

`Configuration/cef/macos-arm64-codecs.json`에 현재 CEF/Chromium commit, arm64 및 코덱 GN 옵션을 기록한다. `status=build_recipe_not_built`이며 실제 코덱 엔진은 아직 없다.

```sh
python3 BuildSupport/prepare_cef_codecs.py --output build/cef-codecs-preparation
```

위 명령은 새 폴더에 recipe.json, environment.sh, host.json만 만든다. 폴더가 있으면 덮어쓰지 않는다. 소스를 받거나 컴파일하지 않는다. environment.sh의 GN_DEFINES는 CEF 소스 빌드용이고 Jena 실행 인자가 아니다. 실제 revision의 빌드 스크립트·도구 요구가 확정되기 전 전체 빌드 명령으로 사용하지 않는다.

다음 실제 엔진 제작 단계에서 필요한 작업:

1. 고정한 CEF commit의 소스 가용성, 해당 소스의 CHROMIUM_BUILD_COMPATIBILITY.txt와 목표 Chromium revision 일치, 요구 도구를 확인한다. 임의로 최신 버전으로 대체하지 않는다.
2. 별도 소스 작업 경로와 공간을 확보하고 공식 automate-git.py를 고정 revision 기준으로 준비한다. 기존 vendor/프로필에 소스를 풀지 않는다.
3. 코덱 옵션을 적용한 arm64 Release를 생성한다. 기본 배포본의 minimal/standard 이름만 바꾸는 것으로 대체하지 않는다.
4. 출처·GN 인자·패치·체크섬과 배포 조건을 남기고, 일치하는 headers/wrapper/framework가 포함된 배포본을 새 CEF_ROOT로 연결한다.
5. 기존 앱이 아닌 새 빌드 폴더에서 패키징한다. 앱 실행과 로그인 프로필 사용은 별도 단계이며 자동 수행하지 않는다.

참고: [CEF 자동 빌드](https://github.com/chromiumembedded/cef/blob/master/docs/automated_build_setup.md), [코덱 빌드 옵션](https://support.google.com/webdesigner/answer/10043691?hl=en). 실제 코덱 재생·사이트 로그인 완료를 빌드 설정 작성만으로 보장하지 않는다. 외부 브라우저로 넘기는 대체 기능은 사용자 결정으로 제외한다.

현재 고정 CEF commit은 GitHub API에서 확인했고 해당 commit의 호환 파일은 Chromium `refs/tags/156.0.8078.88`, depot_tools `132599ebbd8d22d1b1bd5ea703a6d3bc493edd71`을 지정한다. 이를 레시피에 기록했다. 전체 소스 다운로드나 해당 revision의 툴체인 빌드는 아직 수행하지 않았다.
