# 페이지 내 주소 변경 방문 기록

- 원인: URL KVO는 주소 표시만 갱신하고 방문 기록은 didFinish에서만 발생해 History API 탐색을 누락했다.
- 변경: URL KVO에서 변경 당시 URL을 보존해 전달하고 성공적으로 로드된 문서의 페이지 내 주소 변경도 visit 이벤트로 전달한다. 페이지별 마지막 기록 URL로 중복 콜백을 제거하고 새 문서 커밋 시 초기화해 같은 주소의 새로고침은 새 방문으로 남긴다.
- 제목: 이동 시점의 현재 문서 제목을 사용하며 비어 있으면 HistoryService의 기존 URL 대체 동작을 사용한다. 이전의 제목 대기 작업은 빠른 페이지 이동 시 방문이 누락될 수 있어 즉시 기록으로 바꿨다.
- 보존: docs/backups/before-spa-history-*에 런타임과 README 원본을 보관했다.
- 검증: make build 성공. 제품 런타임을 직접 컴파일한 실제 WebKit 검사에서 초기 로드, pushState, replaceState, hash 변경, 뒤로 가기, 동일 URL 중복 억제, 새로고침을 통과했다.
- 회귀 검사: python3 Tests/WebKitHistory/run.py. 로컬 18793 포트를 사용하며 임시 실행 파일과 테스트용 서버만 생성·정리한다.
- 한계: Pinterest·TikTok 실사이트 로그인 세션 검사는 수행하지 않았다. URL을 바꾸지 않는 화면 전환은 별도 방문으로 기록하지 않는다.
- 발견: 기존 파비콘 코드의 격리 문맥 evaluateJavaScript 호출에서 반환값 캐스팅 경고가 확인됐다. 이번 방문 기록 수정에는 포함하지 않았다.
