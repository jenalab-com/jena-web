# CEF 검증 7차: 정책 응답 순서와 종료 경합

## 목적과 범위

6차에서 남긴 정책 적용 중 iframe 소멸, browser 종료, 연속 설정 변경을 Swift 서비스 수준에서 재현했다. 실제 CEF 응답 시점을 우연히 기다리는 대신, 테스트 전송 계층에서 응답을 보류·역순 전달하거나 실패시켜 순서를 고정했다. 이어 같은 수정 서비스를 실제 CEF 앱에 연결해 기존 쿠키 시나리오를 회귀 검증했다.

**경합 재현은 Swift 서비스 시험이고 실제 CEF 경합 재현은 아니다.** 브라우저 통합 시험은 별도 결과로 구분한다. 이전 6차 소스·앱·프로필을 유지하고 `validation/cef-spike/stage7`에 수정 서비스를 추가했다.

## 재현한 결함과 수정

| 상황 | 6차 코드의 실제 시험 결과 | 7차 변경 |
|---|---|---|
| root·iframe 정책 명령 대기 중 iframe detach | root 응답이 와도 ready=false 유지 | 제거된 target의 대기 작업을 적용 집계에서 완료 처리하고 늦은 응답을 무시 |
| 최신 정책 성공 후 이전 정책 실패 응답 | 최신 정책이 오류 상태로 바뀜 | 응답의 revision이 현재와 다르면 오류를 게시하지 않음; 최신 batch만 ready 갱신 |
| 정책 대기 중 browser close 후 늦은 attach 이벤트 | 닫힌 browser에 Network.enable 명령 생성 | 존재하지 않는 browser 상태의 응답·이벤트는 처리하지 않음 |
| 20회 설정 변경 후 응답 역순 전달 | 기존 코드도 최종 설정 유지 | 수정 후에도 최종 차단 설정과 완료 상태 유지 확인 |

iframe 취소의 내부 completion(true)는 사라진 target이 더 이상 적용 대상이 아니라는 집계 의미다. 해당 iframe에 정책을 적용했다는 성공 증거가 아니다. cancelled 계수와 세션 제거를 별도로 검사한다.

응답 처리 시 slot이 일치하는지 확인한 후 pending 명령을 제거하도록 순서도 수정했다. 다른 browser의 응답이 대기 명령을 지우지 않도록 하는 방어이며, 별도 잘못된 slot 입력 시험까지 수행한 것은 아니다.

## 응답 순서 시험

- [수정 전 결과](../../validation/cef-spike/evidence/stage7-baseline-tests-20261111-103543/summary.json): 4개 시나리오 중 3개 실패. 실패 assertion 이름과 소스 스냅샷을 보존했다.
- [수정 후 결과](../../validation/cef-spike/evidence/stage7-fixed-tests-20261111-103612/summary.json): 4개 시나리오, **32/32 확인 항목 통과**.
- [시험 코드](../../validation/cef-spike/stage7/PolicyRaceTests.swift), [수정 서비스](../../validation/cef-spike/stage7/SwiftPolicyService.swift), [실행기](../../validation/cef-spike/stage7/run-races.py).

종료 시험은 대기 명령이 있는 상태에서 서비스 close를 호출하고 늦은 응답·이벤트를 전달한다. 다른 browser의 정책 완료와 이후 slot 재초기화도 확인한다. 실제 renderer 강제 종료, 메모리 접근 검출, slot 재사용 이후 이전 browser 이벤트의 세대 구분을 증명하지는 않는다.

## 실제 CEF 회귀 검증

별도 `swift-policy-stage7-probe` 앱은 기존 Objective-C++ adapter와 sandbox helper를 유지하고 7차 Swift 서비스만 연결했다. 검증 환경은 macOS arm64, Swift 6 모드, CEF 156.0.27이다. 원격 디버깅 포트를 사용하지 않는다.

새 프로필 **69/69**, 동일 프로필 재실행 **27/27** 항목이 통과했다. 두 실행 모두 종료 코드 0, CefShutdown 반환, 네트워크 서비스 재시작 0회를 확인했다. 결과 경로와 실행별 집계는 [stage7-summary.json](../../validation/cef-spike/evidence/stage7-summary.json)에 기록한다. 새 프로필의 허용·차단 반복, iframe 제거·재생성, 적용 실패·재시도와 동일 프로필 재실행의 정책·영속 쿠키 복원을 검사한다. 실제 사이트 로그인 세션을 검증한 것은 아니다.

## 결정과 한계

세 가지 상태 처리 결함을 재현하고 수정했다. G05·G09는 부분 검증이며 CEF 채택은 계속 잠정이다. 서비스 시험의 통과를 native adapter의 생명주기 안전성이나 제품 탭 동작 전체의 통과로 확대하지 않는다.

다음 검증은 실제 CEF adapter에서 명령 응답을 보류한 상태로 browser를 닫는 통합 시험이다. slot 재사용 시 browser 세대 식별, callback 해제와 큐에 남은 작업, 실제 target 소멸 순서를 확인해야 한다. 초기 자동 연결 완료와 정책 변경의 교차, iframe 정책 외 단계의 실패·응답 timeout도 남아 있다.

Swift 시험은 큐 길이 상한과 프로세스 timeout을 둬 완료되지 않는 상태를 실패로 드러낸다. 테스트마다 별도 프로필을 만들며 기존 프로필·증거 자료는 삭제하지 않는다. 실제 CEF 앱 종료는 기존 검증 앱의 CloseBrowser/CefShutdown 경로를 사용한다.

## 재현

프로젝트 루트에서:

```sh
xcrun swiftc -swift-version 6 validation/cef-spike/stage7/PolicyRaceTests.swift validation/cef-spike/stage7/SwiftPolicyService.swift -import-objc-header validation/cef-spike/SwiftPolicyBridge.h -o validation/cef-spike/stage7/fixed-tests
python3 validation/cef-spike/stage7/run-races.py fixed-tests
python3 validation/cef-spike/build-stage7-probe.py
validation/cef-spike/.venv/bin/python validation/cef-spike/privacy-stage7.py
```

동일 프로필 재실행은 첫 results.json의 profile을 JENA_STAGE7_PROFILE에 지정한다. 6차 서비스로 컴파일한 baseline-tests도 동일 실행기로 실패를 재현할 수 있다. 이번 변경은 별도 검증 코드에 한정하며 기술 설계·PRD 전체를 재작성하지 않았다.
