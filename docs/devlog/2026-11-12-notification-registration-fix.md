# 알림 API 혼용 및 중복 등록 수정

사용자 요청: 알림 목록에 누적된 JenaProbe와 Helper 등록 및 알림 전달 문제 수정.

G06CombinedProbe.mm에서 UNUserNotificationCenter 기반 알림 권한 요청과 상태 조회를 제거했다. CEF의 legacy 알림 센터와 modern 센터를 혼용하는 추가 등록을 막는다. Permission.requestOS notifications는 지원하지 않는 요청으로 응답하고, Permission.osStatus.notifications는 null, notificationStatusSource는 system-settings-manual-check-required로 명시한다. null을 denied나 authorized로 해석하면 안 된다. CEF 전달 경로를 별도 네이티브 발송으로 바꿔 웹 검증을 성공으로 대체하지 않았다.

단일 창 빌드에서 UserNotifications 명시적 링크를 제거하고 helper 번들에 LSUIElement=true를 추가했다. CEF 공식 helper plist와 비교해 누락을 보완한 것으로, 이 키만으로 알림 등록을 숨기거나 전달 오류를 해결한다고 주장하지 않는다. 같은 앱 경로·bundle ID·프로필을 유지하며 빌드와 codesign --verify --deep --strict가 통과했다. 정적 검사에서 UNUserNotificationCenter 호출 부재 및 모든 helper의 LSUIElement를 확인했다. 기존 실행은 정상 Probe.quit으로 종료했다.

원본 소스와 번들의 변경 대상 파일은 evidence/before-notification-api-fix-20261112-204030에 보존했다. notification-settings에 알림 등록 plist 및 sqlite backup API로 얻은 DB 스냅샷을 보존했으며 접근 권한은 0600이다. 다른 앱의 등록 데이터도 포함하는 원본이므로 외부 공유하지 않는다.

등록 식별: local.jena.cefprobe, local.jena.g06probe, local.jena.g06manual 및 각각의 .helper.alerts가 기존 6개다. 현재 local.jena.g06combined와 .helper.alerts까지 총 8개가 알림 설정/DB에 존재한다. 이름이 유사한 다른 앱은 대상에서 제외했다. 정확한 대상·경로는 notification-settings/plan.json에 기록했다.

현재 OS 등록은 아직 변경하지 않았다. 서비스 종료에는 별도 확인이 필요하다는 사용자 지침에 따라, Jena 검증용 8개 등록만 초기화하고 현재 사용자의 usernoted를 재시작하는 작업을 요청했다. 승인 전 OS 등록 수정이나 서비스 종료를 하지 않는다. 변경 후 재등록·실제 배너·중복 목록 확인은 아직 미완료다.

근거: macOS usernoted의 legacy/modern client 혼용 거절 로그(notification-usernoted-diagnostic.log), CEF a10dae3 tests/cefsimple/mac/helper-Info.plist.in, Chromium main chrome/services/mac_notifications/mac_notification_provider_impl.mm. Chromium main은 사용한 고정 바이너리와 동일 소스라는 보장은 없으며, 실제 현재 경로는 OS LegacyConnection 로그로 확인했다. Alerts helper의 Failed to source application bundle 오류도 별도로 남아 있어 재검증해야 한다.

## 승인 후 등록 초기화

사용자가 검증용 8개 초기화와 usernoted 재시작을 명시 승인했다. 추가 원본은 evidence/notification-registration-reset-20261112-204419에 보존했다. 앱 등록 8개만 sqlite 트랜잭션에서 제거했고, 대상 관련 record/requests/delivered/displayed/categories 행은 원래 0개였다. 대상 외 DB 행과 dbinfo를 전후 비교해 동일함을 확인했다. 알림 plist도 해당 8개 항목만 제외하고 defaults import 후 정확히 비교했으며 다른 앱과 나머지 키는 동일했다. 초기화 직전 plist가 준비 도중 변경되지 않았는지도 확인했다.

launchctl bootout은 SIP 때문에 거부됐고 launchctl kill도 권한 거부됐다. SIP나 설정은 바꾸지 않았다. 현재 사용자 UID 501 및 /usr/sbin/usernoted 경로를 재확인하고 승인받은 PID 768에 일반 SIGTERM을 보냈다. 서비스가 PID 79383으로 재시작됐고, 설정과 DB에서 대상 8개가 모두 없는 것을 재확인했다. 결과는 result.json과 after-restart.json에 기록했다. 수정 앱의 재실행 후 전달 검증은 이어서 진행한다.

재실행 시 현재 앱과 Alerts Helper 두 개만 재등록됐으나 설정 path가 이전 g06-combined-fixed-probe를 가리켰다. 이전 프로젝트 번들의 LaunchServices 등록을 해제하고 현재 번들을 등록했다(파일은 보존). 일부 GPU/Plugin/Renderer 등록 해제는 exit 1이었고 원시 결과를 launchservices-path-refresh.json에 남겼다. 이후 현재 두 알림 항목의 path만 현재 번들 경로로 갱신했다. 수정 직전 plist를 별도 보존했고 나머지 값을 동일하게 유지했다. 승인된 알림 서비스 재시작 범위에서 PID 79383의 UID와 실행 경로를 확인해 SIGTERM 후 다시 확인했다.

현재 current-registrations.json에는 local.jena.g06combined와 .helper.alerts 두 개만 있고 둘 다 현재 번들 경로다. 앱은 새 bootID C4A3186C-FACB-44B7-85D4-BE56517ADD91, PID 79468, 한 창으로 실행되고 Jena.status ready=true다. Permission.osStatus.notifications=null과 수동 설정 확인 필요 응답을 검증했다. 새 페이지에 20초 알림 진단 함수를 설치했고 사용자의 실제 배너 검증 대기 중이다. helper의 Failed to source application bundle은 최초 재등록 시 다시 관측되어, 경로 갱신 후 오류 여부와 실제 알림 전달은 추가 확인이 필요하다. 등록 정리 성공을 알림 전달 성공으로 간주하지 않는다.

## 사용자 화면과 저장 상태 불일치

사용자가 20:47:01 스크린샷으로 과거 JenaProbe 3개와 Alerts Helper 3개가 계속 표시됨을 보고했다. 앞서 저장 데이터 확인만으로 제거 완료라고 안내한 것은 부정확했으며 UI 반영은 미확인으로 정정한다. 재조회에서는 group 설정과 알림 DB 모두 현재 g06combined와 .helper.alerts 두 개뿐이고 legacy ncprefs에는 해당 항목이 없었다. after-user-screenshot.json에 보존했다. 설정 앱의 기존 표시 상태가 남았을 가능성은 있으나 원인으로 확정하지 않는다. 사용자에게 시스템 설정을 완전히 종료 후 다시 열어 비교하도록 요청한다. 별도 앱 jenaMemory는 수정 대상이 아니며 보존했다.

사용자가 시스템 설정을 완전히 종료하고 다시 연 뒤 이전 JenaProbe 6개가 사라졌다고 확인했다. 저장 데이터의 대상 제거와 UI 반영을 모두 확인했으므로 과거 등록 정리는 완료다. 이 과정은 화면 갱신 후 해소됐으나 macOS 내부 캐시의 구체 구현을 추정하지 않는다. 현재 앱의 실제 알림 전달은 별도 미완료 항목으로 유지한다.

## 실제 배너 전달 확인

사용자가 수정 앱의 알림을 허용하고 테스트한 뒤 배너가 나타났다고 보고했다. notification-fixed-banner-20261112-205014.json에서 동일 bootID의 웹 created/show-event와 사이트 ALLOW(1)를 확인했다. usernoted 로그에는 20:49:56에 local.jena.g06combined의 해당 a.test 요청을 .alert/.lockScreen/.notificationCenter로 Delivering하고 Presenting as banner한 기록이 있다. 웹 이벤트만으로 성공을 주장하지 않고 사용자 관찰과 OS 전달 증거를 함께 확인했다. 로그는 notification-registration-reset-20261112-204419/banner-verification-usernoted.log에 보존했다.

과거 6개 등록 정리와 수정 후 실제 웹 배너 전달은 완료다. 수정 후 OS 거부→허용 전환 및 지속형 Helper 경로는 별도 미검증으로 남는다. 앞선 빌드의 native 장치 권한 결과를 이번 재서명 빌드에 그대로 적용하지 않는다. 제품용 알림 OS 상태 안내는 CEF 경로와 충돌하지 않는 방식으로 별도 설계가 필요하다.
