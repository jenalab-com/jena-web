# 코덱 빌드 구성과 엔진 패키징 준비

- 사용자 방향: 검색·영상·로그인은 앱 내부에서 완료한다. 호환성 구현안의 외부 브라우저 보조 경로를 제외하고 해당 부분만 수정했다.
- 구현: CEF 입력 디렉터리별 SHA-256과 버전·경로를 CMake build directory에 고정했다. 패키저가 원본 lock 및 기존 앱의 서명 후 framework 영수증을 비교하고, 불일치·영수증 없는 기존 앱에서는 교체 없이 중단한다.
- 이유: 기존 패키저는 framework가 이미 있으면 복사를 생략해 CEF_ROOT 변경이 앱에 반영되지 않을 수 있었다. 버전 문자열만 비교하면 같은 버전의 코덱 빌드를 구분할 수 없어 콘텐츠 해시를 사용한다.
- 구성: 현재 버전과 commit의 macOS arm64 코덱 레시피, 신규 폴더 전용 준비 스크립트, 생성된 environment.sh/host.json/recipe.json을 추가했다. 소스 다운로드·CEF 컴파일을 자동 수행하지 않는다.
- 상태: 실제 코덱 지원 framework는 아직 없다. revision별 소스·도구 요구와 배포 조건은 pending으로 명시했다. Python 문법 컴파일과 별도 제품 디렉터리의 구성/빌드만 대상으로 한다. 앱 실행·수동 권한 검사·새 검증 차수 없음.
- 보존: 기존 변경 대상은 docs/backups/before-codec-build-preparation-20261112-225316에 보존했다. 기존 앱·vendor·사용자 프로필·실행 프로세스는 변경하지 않는다.
- 비용: 전체 framework를 해시하므로 빌드 시 디스크 읽기가 추가된다. 혼용 방지를 위해 변경 없는 입력도 해시하며, 파일 시간만 신뢰하는 최적화는 하지 않았다.

- 공식 GitHub API에서 고정 CEF commit을 확인하고 해당 revision의 CHROMIUM_BUILD_COMPATIBILITY.txt가 지정하는 Chromium tag/depot_tools commit을 레시피에 추가했다. 원격 문서 도구 대신 시스템 curl을 사용해 읽었고 인증 검증은 비활성화하지 않았다.

- 결과: `build/product-engine-lock`에서 기존 기본 CEF를 사용한 Debug 빌드와 서명·패키징 완료(`BUILD SUCCEEDED`). 코덱 지원 엔진 빌드는 아니며 기존 `build/product` 앱은 그대로 보존했다.
