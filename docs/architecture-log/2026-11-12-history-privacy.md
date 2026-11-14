# 방문 기록 저장 및 삭제 경계

CEF main-frame load 완료 → BrowserEvent.visit → HistoryService → HistoryRepository/AppDatabase 순서로 기록한다. 앱 기록과 CEF의 내부 저장 파일은 별개이며 CEF DB를 직접 편집하지 않는다. 조회는 최근 500건이고 삭제는 표시 범위가 아닌 선택 기간 전체에 적용된다.

PrivacyWindowController는 선택 범위를 고정한 확인 화면을 제공한다. PrivacyService는 앱 기록과 BrowserPrivacy 작업을 분리해 각각 결과를 남긴다. 한쪽 실패를 전체 성공으로 표시하지 않는다. BrowserPrivacy의 CEF 구현은 빈 탭 조건을 검사하고 CDP 쿠키 목록의 정확한 tuple/partition을 유지해 삭제한다. 이어 명시한 origin 저장소와 전체 HTTP 캐시를 순차 처리한다. 웹 데이터 삭제 시작 후 탐색과 종료를 막는다.

스키마 v2는 visit 테이블과 시간 인덱스만 추가한다. 기존 v1 원본은 SQLite 백업으로 보존하며 앱 DB 큐에서 처리한다. 삭제를 위한 백업을 새로 만들지 않는다. 엔진 명령의 응답이 오지 않는 상황에 대한 별도 복구 UI는 남아 있다. 채택 판단이나 재검증 조건을 추가하지 않는다.
