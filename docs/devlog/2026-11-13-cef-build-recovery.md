# CEF 소스 동기화 정체 복구

- 사용자 승인 후 명시된 PID 57678, 57680, 57846, 77805, 80096의 명령/소속을 다시 확인하고 SIGTERM으로 종료했다. 종료 후 해당 PID가 남지 않은 것을 확인했다. 다른 앱과 프로세스는 종료하지 않았다.
- Chromium 최초 pack 수신·delta 처리는 완료됐고 목표 commit 8954d18543712dc11b97c3aca0a6e714aa2d7dcd가 로컬에 존재했다. 추가 fetch의 통신 자식은 종료 상태였고 index-pack이 대기 중이었다. 네트워크 장애의 최초 원인은 단정하지 않는다.
- 기존 pack/임시 pack을 삭제하지 않았다. build-status와 .gclient, git config/HEAD/FETCH_HEAD 등은 build/cef-codecs-8078-arm64/recovery-backup-20261113에 보존했다.
- 작업 파일이 없는 clone에 목표 commit의 일반 detached checkout을 실행했다. --force, reset, clean을 사용하지 않는다.
- 복구 런처 BuildSupport/resume_cef_codecs.py는 목표 HEAD를 확인한 후 명시적 src revision·--no-history로 의존성을 동기화한다. 기존 Chromium 이력은 보존하며 신규 의존성의 불필요한 전체 이력 수신을 줄인다. broad fetch/--with_branch_heads를 다시 실행하지 않는다.
- 의존성 → hooks → --no-update로 CEF 컴파일/패키징 순서다. 각 단계별 로그와 30초 heartbeat, 로그 무출력 시간을 recovery-status.json에 기록한다. 로그가 조용하다는 이유만으로 자동 종료하지 않는다. 테스트와 앱 실행은 하지 않는다.
- 진행 상태와 빌드 완료는 구분해 보고한다. 코덱 지원 엔진 산출물은 아직 없다.
