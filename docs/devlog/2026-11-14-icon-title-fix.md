# 아이콘 버튼의 텍스트 겹침 수정

- 변경: 아이콘 설정 함수에서 title과 alternateTitle을 빈 문자열로 설정한 뒤 imageOnly를 적용한다.
- 이유: 아이콘 전환 뒤에도 title에 기능명이 남아 있어 사용자가 보고한 글자 겹침을 제거한다.
- 결정: 기능 설명은 툴팁과 접근성 이름으로 유지한다. 새로고침·중지 상태 전환에도 동일하게 적용된다.
- 보존: 수정 전 소스를 docs/backups/before-icon-title-fix-*에 백업했다.
- 한계: 실제 화면의 시각 검증은 수행하지 않았다.
- 검증: `make build` 성공 (`BUILD SUCCEEDED`).
