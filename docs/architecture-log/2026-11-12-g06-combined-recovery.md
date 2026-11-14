# G06 결합 검증의 사이트 선택·OS 상태와 재실행 구성

상태: 검증용 설계, 제품 통합 전. 대상은 단일 macOS 사용자·CEF 테스트 프로필·두 native browser다.

기존 manual probe는 환경변수 없이는 종료했고, 사이트 선택과 OS 상태를 함께 실행하는 웹 허용 경로가 없었다. 이번 요청은 웹 요청/OS 권한 결합 및 복구 검증이다.

- 사이트 선택은 CEF 프로필의 content setting에 보존한다. OS 거부 때문에 사이트 allow를 deny로 덮어쓰지 않는다. 미디어 callback은 두 상태를 합쳐 요청을 계속하거나 취소한다. iframe은 사용자가 정한 요청 단위 취소를 유지한다.
- 테스트용 HTTPS origin은 앱 내 CEF scheme handler로 제공한다. 재실행 때 외부 fixture 프로세스·인증서 예외·command-line host mapping 복구에 의존하지 않는다. 실제 보안 context 여부를 검사하며 실제 인터넷 서비스 호환성의 대체 시험으로 간주하지 않는다.
- 프로필과 evidence 경로만 전용 `~/Library/Application Support/local.jena.g06combined/launch-state.json`에 원자적으로 저장한다. 환경변수 없는 재실행에서도 같은 프로필을 열고 mailbox는 매번 새로 만든다. 지난 명령을 재실행하지 않는다. 구성 파일 유실/잘못된 경로는 실패로 드러내며 임의로 기존 프로필을 교체하지 않는다.
- 앱 종료는 `NSApplication.terminate:`를 재정의해 CEF 브라우저 닫기 → OnBeforeClose → CefQuitMessageLoop → CefShutdown 순서를 따른다. 최초의 applicationShouldTerminate/NSTerminateLater 안은 실제 종료를 멈추게 해 폐기했으며 실패 소스와 결과는 보존했다. [CEF 공식 구현](https://github.com/chromiumembedded/cef/blob/master/tests/cefsimple/cefsimple_mac.mm)을 확인했다.

이는 테스트용 재실행 구조다. 다중 인스턴스 조정, 데이터 마이그레이션·백업, 제품 설정 화면, engine permission query와 OS의 모든 상태 조합은 별도 검증 대상이다. 테스트 재실행은 같은 앱 식별자를 사용하지만 배포용 서명·공증을 증명하지 않는다.
