# 주소창과 버튼의 표시 높이 일치

- 원인: NSButton의 시스템 alignment rect와 사용자 정의 배경이 그려지는 bounds가 달랐다. 기존 검사는 텍스트 영역만 확인해 보이는 높이 차이를 놓쳤다.
- 변경: 사용자 정의 버튼의 alignmentRectInsets를 0으로 명시하고 베젤 설정을 그리기 이전으로 옮겼다. 버튼·주소창은 공통 34pt 높이를 사용하며 툴바에서 centerY로 정렬한다. 텍스트 내부 중앙 정렬은 유지한다.
- 보존: docs/backups/before-chrome-visible-height-*에 원본을 백업했다.
- 검증: 제품의 실제 컨트롤 클래스를 추출해 AppKit NSStackView에서 레이아웃했다. 버튼 frame=(0,0,32,34), 주소창 frame=(40,0,560,34). 높이와 minY 일치 및 34pt 높이를 assert로 확인했다. 실행 중인 제품 창의 시각 검증은 아직 수행하지 않았다.
- 제품 빌드: `make build` 성공 (`BUILD SUCCEEDED`).
