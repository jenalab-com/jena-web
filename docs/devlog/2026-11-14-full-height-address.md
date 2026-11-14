# 전체 높이 주소 필드 내부 중앙 정렬

- 이전 처리 문제: 입력 필드 자체를 고유 높이로 줄여 중앙에 놓았다. 사용자가 요청한 전체 높이 필드 내부 정렬과 달랐다.
- 변경: 주소 NSTextField를 28pt 배경의 위아래에 연결했다. BrowserAddressCell이 텍스트 표시 영역만 세로 중앙으로 계산하며 select/edit에도 같은 영역을 전달한다.
- 유지: 주소창 배경, 가로 패딩, 툴팁과 기존 탐색 동작은 유지한다.
- 보존: docs/backups/before-full-height-address-*에 원본을 백업했다.
- 검증: 실제 AppKit 셀을 사용하는 임시 Swift 검사에서 28pt 입력 영역의 텍스트 영역이 y=6, 높이=16으로 중앙에 위치하는 것을 assert로 확인했다. 화면 시각 검증은 수행하지 않았다.
- 제품 빌드: `make build` 성공 (`BUILD SUCCEEDED`).
