# G06 수동 검증 창 정리

사용자가 떠 있는 JenaProbe를 모두 제거하고 새로 열어 달라고 요청했다. 기존 실행 앱(PID 50828)의 Probe.quit으로 정상 종료하고 JenaProbe 프로세스가 없는 것을 확인했다. 소스 원본은 validation/cef-spike/evidence/before-single-window-20261112-195601에 보존했다.

수동 검증용 번들 Jena G06 Permissions.app을 추가했다. 번들 ID local.jena.g06combined와 기존 프로필은 유지하고 CFBundleName/CFBundleDisplayName 및 파일명을 명확히 했다. 수동 모드는 창 1개, 시작 URL https://a.test/를 사용한다. 기존 자동검증 빌드는 창 2개·about:blank 기본값을 유지한다. controller는 active-session의 browserCount에 맞춰 준비를 기다린다. 권한 처리 정책은 변경하지 않았다.

기존 위치 서비스 항목 제거를 위해 프로젝트 번들 ID 4종에 한정해 tccutil reset Location을 시도했으나 모두 exit 70으로 실패했다. 전체 권한 초기화나 macOS 보호 데이터베이스 직접 수정은 하지 않았다. 설정 목록 항목 제거는 미완료이며 실행 앱 종료와 구분한다. 실패 결과는 기존 실행 폴더 location-registration-reset-attempt.json에 보존했다.

빌드 및 codesign --verify --deep --strict 통과. 실행 검증 결과는 후속 기록에 추가한다. 기존 검증 앱 파일·프로필·증거는 삭제하지 않았다.

새 번들의 실행은 PID 53928로 시작했으나 90초 준비 대기에서 시간 초과했다. sample 결과 RestoreCombinedLaunchState의 createDirectory → mkdirat에서 대기 중이었다. 원인을 단정하지 않고 사용자에게 macOS 파일/볼륨 접근 요청 창 존재 여부를 확인 중이다. 앱을 중복 실행하거나 강제 종료하지 않았다. 단일 창 실제 표시 검증은 아직 미완료다. 표본은 기존 실행 폴더 single-window-startup-sample.txt에 보존했다.

사용자가 볼륨 접근 권한 요청 창을 확인하고 이후 앱이 열렸다고 보고했다. 실행 검증에서 browserCount=1, Target.getTargets의 page 1개, https://a.test/의 readyState=complete 및 테스트 버튼 4개를 확인했다. 동일 프로필과 LocalStorage marker도 유지됐다. 결과는 single-window-runtime.json에 기록했다. 초기 대기는 볼륨 접근 요청과 함께 관측됐으며, 이전 실행 지연 전체의 원인으로 일반화하지 않는다.

새 번들의 native camera/microphone/location 상태는 모두 notDetermined(0), notifications는 denied(1)로 관측됐다. 번들 ID와 웹 프로필이 같아도 이전 OS 권한 상태가 유지됐다고 간주하지 않는다. 새 실행의 OS 권한 검증은 다시 필요하다. 기존 실행의 검증 결과는 당시 번들에 대한 증거로 보존한다.

새 단일 창 앱에서 사용자가 위치 요청을 거부했다. native location=2, 사이트 geolocation ALLOW(1)에서 웹 getCurrentPosition이 code=1(PERMISSION_DENIED)로 차단됐고, 사이트 ALLOW는 유지됐다. permissions.query는 전후 denied였다. 증거: single-window-location-denial-20261112-202555.json. 위치 재허용 후 실제 기능 복구는 아직 검증 전이다.

위치 서비스에서 새 앱을 켠 뒤 종료 안내 없이 동일 bootID/PID에서 native location=3으로 바뀌었다. 사이트 ALLOW(1)는 유지됐고 웹 query=granted, 실제 getCurrentPosition 성공 콜백을 확인했다. 좌표 필드는 읽거나 저장하지 않았다. 증거: single-window-location-recovery-20261112-202642.json. 이 단일 창 빌드에서 위치 OS 거부 차단과 실행 중 재허용 복구를 확인했다.

다음 알림 검사에서 native notifications=1(denied), 사이트 ALLOW(1)인데 웹 Notification은 show-event를 반환했다. show-event만으로 macOS 배너의 실제 표시 또는 OS 차단 성공을 판정하지 않는다. 사용자의 화면 관찰을 확인 중이다. 증거: single-window-notification-denial-20261112-202655.json. 알림 1건은 fixture에 따라 이벤트 후 1.5초에 close 요청했다.

자동 발송한 첫 알림은 사용자가 확인하지 못해 실제 표시 여부를 미확인으로 남겼다. 이후 사용자가 버튼으로 재시도하고 배너가 뜨지 않았다고 보고했다. 같은 bootID에서 native notifications=1, 사이트 ALLOW(1), 웹 results의 추가 show-event들을 확인했다. OS 거부 상태에서 배너 미표시는 관찰됐으나, OS 거부만이 원인인지와 OS 재허용 후 전달 성공은 아직 확정하지 않는다. 원시 증거: notification-banner-observation-20261112-203020.json.

사용자가 Jena G06 Permissions의 알림 허용·배너 설정 완료를 보고했다. 재실행 없이 동일 bootID/PID에서 native notifications=2(authorized), 사이트 ALLOW(1)를 확인했다. 실제 배너 복구는 다음 사용자 버튼 검사에서 확인한다. 버튼 전 결과 5건을 기준으로 보존했다: notification-allow-before-manual-20261112-203137.json.

알림 OS 허용 후에도 사용자가 배너가 나타나지 않았다고 보고했다. native notifications=2와 추가 웹 show-event들을 확인했으므로 알림 배너 복구는 미통과다. 1.5초 자동 close라는 관찰상의 혼동을 배제하기 위해 현재 페이지에서만 notifyTest 원본을 originalNotifyTest로 보존하고 20초 유지·중복 클릭 억제 진단 함수를 설치했다. 번들/프로필/OS 권한 변경이나 재실행은 하지 않았다. 원인은 아직 확정하지 않았다. 최초 native API 기반 OS 상태 조회는 CEF가 표시하는 알림의 실제 macOS 전달 성공을 대신하지 않는다.

20초 유지 및 다른 앱으로 전환한 검사에서도 사용자는 배너·알림 센터 모두 없다고 보고했다. OS notifications=2, 웹 created/show-event/20초 후 close 로그는 확인됐으나 표시 복구는 실패다. notification-20s-result-20261112-203529.json 및 notification-usernoted-diagnostic.log에 근거를 보존했다.

macOS usernoted 로그의 20:24:17에 같은 PID 53928과 local.jena.g06combined에 대해 “Legacy client ... connecting to modern client. You can't mix modern clients with legacy clients.”가 기록됐다. 후속 실제 웹 테스트 시각마다 LegacyConnection 메시지 3/7 거부가 반복됐다. Alerts helper에는 Failed to source application bundle도 기록됐다. 이 오류를 근거로 새/기존 알림 API 등록 충돌을 확인했으며, 검증 앱의 UNUserNotificationCenter 요청·조회 코드와 CEF 전달 경로의 혼용 및 helper 번들 구성이 수정 조사 대상이다. 모든 오류가 하나의 원인이라고 단정하지 않는다.

앞선 OS 거부 시 배너 미표시도 이 전달 오류가 개입했을 수 있으므로, 그 관찰을 독립적인 OS 차단 성공 판정으로 승격하지 않는다. 사이트 선택 유지와 native OS 상태 변경은 확인됐으나 알림 실제 전달·거부·복구 검증은 미통과다. 설정을 반복 변경하는 수동 검사는 중단하고 전달 경로 수정 후 다시 검증해야 한다. 시스템 알림 서비스 종료·등록 DB 직접 편집·전체 권한 초기화는 수행하지 않았다.
