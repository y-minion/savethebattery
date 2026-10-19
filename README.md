# VibeBattery

**무료·오픈소스 macOS 배터리 관리와 터미널 코딩 작업 도우미.**

개발 미리보기입니다. M4 Pro / macOS 27.0.1에서 먼저 검증합니다. 모든 AlDente 기능을 구현한 상태가 아닙니다. [지원 현황과 제약](docs/COMPATIBILITY.md)을 확인하세요.

## 현재 기능

- 실제 배터리 잔량·용량 기반 건강도·사이클·온도·충방전 전력
- CPU 활동 기반 프로세스 목록과 사용자 선택 앱 종료 (일반 백그라운드 프로세스는 활성 상태 보기로 연결)
- 로컬에 저장하는 선택적 7일 이력
- 등록한 터미널 작업 동안 화면 끄기와 제한된 잠자기 방지
- 작업 성공 후 명시적으로 등록한 임시 프로세스만 정상 종료
- iTerm2와 Ghostty에서 기존 Claude/Codex 명령을 감싸 실행하는 CLI

충전 상한과 에너지 모드는 macOS 배터리 설정으로 연결합니다. 앱 내부 항해·과열 차단·교정·MagSafe LED는 검증된 제어 경로가 없어 제공하지 않습니다. 화면에 작동하는 것처럼 표시하지 않습니다.

## 빌드

Swift 6 도구 및 호환되는 macOS SDK가 필요합니다. 일반적인 최신 Xcode 환경:

```sh
swift test --disable-xctest
python3 scripts/smoke-sessions.py .build/debug/vbctl
scripts/build-app.sh
open dist/VibeBattery.app
```

빌드 결과는 `dist/VibeBattery.app`과 `dist/VibeBattery.zip`입니다. 앱은 로컬 실행용 임시 서명을 사용합니다. 일반 배포용 Developer ID 서명·공증은 아직 포함하지 않습니다. 현재 저장소에는 원본 코드만 있고 외부 패키지 의존성은 없습니다.

## 터미널 작업

앱의 **바이브 코딩** 화면에서 명령을 복사할 수 있습니다. 또는 빌드한 CLI를 직접 사용하세요.

```sh
.build/debug/vbctl status
.build/debug/vbctl run --hours 4 --screen-off -- claude
.build/debug/vbctl run --hours 4 --screen-off -- codex
.build/debug/vbctl sessions
.build/debug/vbctl release SESSION_UUID
```

명령 인수는 셸 문자열로 다시 해석하지 않습니다. 기존 터미널 입력/출력과 로그인 환경을 사용합니다. AI 대화, 명령 인수, 출력, API 키는 저장하지 않습니다.

시간 만료 또는 어댑터 분리 시 기본적으로 **보호만 해제**합니다. 실행 중인 명령은 종료하지 않지만 macOS가 잠들 수 있습니다. 화면을 보며 조작하는 AI는 별도 호환성 검증이 필요합니다. 화면 끄기는 시스템 잠자기나 잠금 정책 해제와 다릅니다.

## 명시적 임시 리소스 정리

자동 정리는 기본적으로 꺼져 있습니다. `--cleanup`으로 시작한 관리 세션 안에서 다음 형태로 생성한 **작업 전용 임시 리소스**만 대상입니다.

```sh
/path/to/vbctl resource -- python3 -m http.server 8000
/path/to/vbctl resource --keep -- python3 -m http.server 8001
```

명령은 `VIBEBATTERY_SESSION` 환경을 상속해야 합니다. 필요하면 터미널에서 리소스를 백그라운드로 실행할 수 있습니다. 성공한 주 작업이 종료되면 등록된 리소스에 SIGTERM을 보냅니다. 실패·취소·보호 해제·시간 만료에는 자동 정리하지 않습니다. 응답하지 않아도 자동 강제 종료하지 않습니다. 공유할 서버는 반드시 `--keep`을 사용하세요. 일반 프로세스를 이름만 보고 종료하거나 파일을 삭제하지 않습니다.

기록은 `~/Library/Application Support/VibeBattery`에만 저장합니다. `VIBEBATTERY_DATA_DIR`는 테스트용 데이터 경로를 분리할 때 사용할 수 있습니다.
종료된 세션 기록은 앱 갱신 또는 새 세션 시작 시 30일 기준으로 정리합니다. 설정에서 즉시 삭제할 수도 있으며 실행 중인 관리 세션은 보존합니다.

## 개발

설계와 계획은 [docs/superpowers](docs/superpowers)에 있습니다. 공개 기록에 개인 기기의 원본 센서 덤프나 대화 내용을 올리지 않습니다.

MIT · [라이선스](LICENSE) · [참고 프로젝트](THIRD_PARTY_NOTICES.md)
