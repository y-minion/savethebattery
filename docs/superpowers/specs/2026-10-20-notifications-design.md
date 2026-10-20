# 로컬 알림 설계

작성일: 2026-10-20 · 하위 프로젝트 2 (C 로컬 알림)

## 목적

배터리 보존에 중요한 순간(상한이 풀림, 고온, 과열 보류 문제, 다른 충전 관리 앱)과 바이브 코딩 작업의 끝을 놓치지 않게 한다. AlDente Pro 대체 앱으로서 "상한이 몰래 풀려 100%까지 충전되는" 상황을 알려주는 것이 가장 중요하다.

성공 기준:
- 이벤트마다 켜고 끌 수 있고, 처음에는 꺼져 있으면 손해가 생기는 것만 켜져 있다.
- 같은 조건이 이어지는 동안 한 번만 알리고, 앱을 다시 켜도 반복하지 않는다.
- 알림 판단은 순수 함수로 테스트한다.
- 알림을 누르면 관련 화면이 열린다.

독립 검토(Opus)를 거쳐 트리거를 실제 코드 데이터에 맞게 고쳤다.

## 범위

포함: 아래 이벤트, 설정 화면 "알림" 카드(권한 상태, 테스트 알림, 이벤트별 토글, 기준값), 알림 클릭 이동, `notify.json` 기억.

제외: 알림 안의 동작 버튼, 알림 기록 화면, 소리 선택, 시간에 민감한 알림(ad-hoc 서명으로는 entitlement를 받을 수 없음), 단축어·일정(하위 프로젝트 3).

## 구조

- `BatteryCore/NotificationPolicy.swift` (순수, 테스트 대상)
  - `NotificationSettings`: 이벤트별 Bool과 기준값. 빠진 키는 기본값.
  - `NotificationInput`: 한 번의 평가에 필요한 값(아래 "입력").
  - `NotificationMemory`: 재무장 상태와 마지막 발송 시각. 빠진 키는 기본값.
  - `AlertEvent`: `id`(같은 종류는 덮어씀), `title`, `body`, `section`, `thread`, `duplicatesAppMessage`.
  - `NotificationPolicy.evaluate(_ input, settings, memory) -> NotificationOutcome(events, removals, memory)`.
  - 한국어 문구는 `NotificationText`.
- `BatteryPlatform/NotificationStore.swift`: 기존 `JSONFile`로 `notify.json`을 읽고 쓴다(손상 시 격리, 0600). 값이 바뀔 때만 쓴다.
- `VibeBattery/Notifier.swift`
  - `NotificationSink` 프로토콜, `SystemNotificationSink`(UNUserNotificationCenter), `NoNotificationSink`.
  - 앱이 `.app` 번들 안에서 bundleIdentifier를 갖고 실행될 때만 `SystemNotificationSink`를 만든다. `swift run`·테스트에서 UNUserNotificationCenter는 예외로 앱을 죽이기 때문이다.
  - `NotificationRouter`: UN delegate. `willPresent`는 배너·목록·소리를 반환한다(앱이 앞에 있어도 보이게). `didReceive`는 허용된 화면만 받아 앱에 전달하고, 앱 모델이 아직 없으면 보관한다.
  - `@NSApplicationDelegateAdaptor`의 `applicationWillFinishLaunching`에서 delegate를 지정한다(알림 클릭으로 앱이 실행된 경우에도 받기 위해).
- 앱: `AppModel`이 30초 측정 끝(`refresh`)과 깨어날 때 `evaluate`를 한 번 부르고, 결과를 싱크로 보내고, 기억을 저장한다. 창 열기 동작은 항상 그려지는 MenuBarExtra 레이블에서 받아 둔다.

## 입력

- `now`
- 배터리: `percent?`, `onAC`, `charging`, `temperature?`(측정 시각이 now−120초~now+5초일 때만), `hasBattery`(`percent != nil`)
- 충전 상한: `limit: ChargeLimitState`, `lastWritten: Int?`, `topUpRequested: Date?`
- 과열 보류: `heatEnabled`, `heatHolding`(holdLimit 있음), `heatStuckLimit: Int?`(heatPaused이면서 holdLimit 있음), `heatSensorMissing`(켜져 있고 마지막 동작이 `sensorUnavailable`), `heatEvent: HeatEvent?`(이번 측정의 일회성 결과: `held(Int)`, `restored`, `yielded`, `holdFailed`)
- `conflicts: [String]`(다른 충전 관리 앱 이름)
- `sessions: [SessionSummary]`(id, command, outcome, started, ended, exitCode, released)
- `wake: SleepEvent?`(이번 평가가 깨어남 직후일 때만)
- `suggestions: [SuggestionKind]`, `week: UsageSummary?`
- `calendar`

## 이벤트

설정 키 / 처음 상태 / 알림 ID / 조건 / 재무장.

### 충전 상태 (화면: 대시보드, thread `charge`)
- `limitReached` / 꺼짐 / `charge.limitReached`: 직전 평가에서 충전 중이었고 지금은 `onAC && !charging && limit.enabled==true`, 잔량 ≥ 상한−1. 과열 보류 중이거나 24시간 안의 완충 요청 중이면 보내지 않는다. 재무장: 어댑터를 5분 넘게 분리했거나 상한 값이 바뀜.
- `topUpDone` / 켜짐 / `charge.topUpDone`: `topUpRequested != nil && onAC && 잔량 ≥ 99`. 요청 하나당 한 번. 문구는 복귀 시점을 약속하지 않는다("오래 연결해 두면 배터리에 부담이 됩니다"). Task 8 실기기 검증 결과에 따라 조건을 확정한다.
- `lowBattery` / 꺼짐 / `charge.low`: `!onAC && 잔량 ≤ 기준`(기본 20, 10~50, 5 단위). 재무장: 잔량 ≥ 기준+5, 또는 어댑터를 2분 이상 계속 연결. 재무장 시 알림 센터에서 지운다.
- `limitChanged` / 켜짐 / `charge.limitChanged`: 직전 출처가 `vibeBattery`였는데 지금 `external` 또는 `none`이고, `lastWritten`과 앱의 충전 쓰기 횟수(`ChargeRecord.writes`, 과열 보류·복원·종료 시 복원 포함)가 그사이 바뀌지 않았고(앱이 직접 바꾼 것이 아님), 24시간 안의 완충 요청 중이 아님(확인되지 않은 완충 요청이 알림을 영원히 막지 않도록). `unknown`은 판단을 미루고 이전 출처를 유지한다. 재무장: 출처가 다시 `vibeBattery`.
- `controlUnavailable` / 켜짐 / `charge.unavailable`: 이전에 `supported==true`를 본 적이 있는데 `false`가 됨. 재무장: 다시 `true`.

### 보호 경고 (화면: 설정, 충돌만 대시보드, thread `protect`)
- `highTemperature` / 켜짐 / `protect.heat`: 신선한 온도 ≥ 기준(충전 중, 기본 40, 36~45), 배터리 사용 중에는 기준+2. 재무장: 온도 ≤ 그때 기준−3. 재무장 후에도 마지막 발송 30분 안에는 보내지 않는다. 재무장 시 알림 센터에서 지운다.
- `conflict` / 켜짐 / `protect.conflict`: 처음 보는 이름이 목록에 생김(설치만 돼 있어도 감지됨). 문구: "<이름>이(가) 감지되어 VibeBattery는 충전 설정을 바꾸지 않습니다." 목록이 비면 기억을 비우고 알림을 지운다.
- `heatProblem` / 켜짐:
  - `heat.stuck`: `heatStuckLimit`이 있음 → "상한이 N%로 남아 있습니다". 해결될 때까지 24시간마다 다시. 해결되면 지운다.
  - `heat.paused`: `heatEvent == yielded` → 다른 곳에서 상한이 바뀌어 보류를 멈춤.
  - `heat.failed`: `heatEvent == holdFailed` → 보류를 걸지 못함.
  - `heat.sensor`: `heatSensorMissing`이 10분 이상 이어짐 → 한 번. 센서가 돌아오면 재무장.
  - `heat.failed`는 앱 안 경고창도 띄우므로 `duplicatesAppMessage = true`. `heat.paused`는 앱 경고창이 없으므로 항상 보낸다.
- `heatActivity` / 꺼짐 / `heat.activity`: `held(N)` → 보류 시작, `restored` → 보류 해제.

### 바이브 코딩 (화면: 바이브 코딩, thread `session`)
- `sessionEnded` / 켜짐 / `session.end.<id>`: 직전에 `ended == nil`로 본 세션이 `ended`를 갖게 됨. 결과는 종료 코드로: 0이면 "완료", 아니면 "실패 · 코드 N". outcome이 `detached`/`expired`이면 "보호 해제 후 종료". 본문은 실행 파일 이름과 걸린 시간만(인수 없음).
- `sessionCancelled` / 꺼짐: outcome `cancelled`로 끝남(Ctrl‑C 등). 위 `session.end.<id>`를 쓴다.
- 종료는 10분 이내일 때만 알린다. 처음 보는 세션(앱이 꺼져 있었거나 30초 사이에 시작·종료)과, 앱을 다시 켰을 때 그사이 끝나 있던 세션 모두 같다.
- 한 번의 평가에서 종료 알림이 3개를 넘으면 `session.batch` 한 건으로 묶는다("작업 N개 종료 · 완료 a · 실패 b").
- `protectionReleased` / 켜짐 / `session.released.<id>`: 직전에 `running`으로 본 세션이 아직 끝나지 않았는데 outcome이 `expired`이거나, `detached`이면서 사용자 해제 표시(`released`)가 없음. "어댑터 분리로 잠자기 방지가 풀렸습니다. 작업은 계속되지만 맥이 잠들 수 있습니다." 처음 볼 때 이미 풀려 있던 세션은 알리지 않는다.
- 기억의 세션 목록은 입력에 있는 ID만 남긴다(세션 기록은 30일 뒤 지워짐).

### 건강 분석 (화면: 건강 분석, thread `health`)
- `sleepDrain` / 켜짐 / `health.sleep`: `wake?.isHigh == true` → "잠자기 중 배터리가 시간당 N% 줄었습니다".
- `suggestions` / 꺼짐 / `health.suggestion.<kind>`: 제안 종류가 있고 같은 종류를 7일 안에 보내지 않음.
- `weeklySummary` / 꺼짐 / `health.weekly`: 이번 주(월요일 시작) 월요일 09:00 이후이고, 저장된 "연도-주차" 키가 이번 주와 다름, `week.observed > 0`. 본문: 잔량 95% 이상 시간, 평균 스트레스, 상한 80% 비교.

## 공통 규칙

- 꺼진 이벤트와 권한이 없을 때의 이벤트도 기억에는 "보냄"으로 기록한다. 나중에 켜거나 허용했을 때 밀린 알림이 쏟아지지 않는다.
- 첫 실행과 공백: 직전 평가가 300초보다 오래됐거나 없으면(앱 종료, 잠자기), 변화형 판단(상한 도달의 "직전 충전 중")은 기준점만 잡고 보내지 않는다. 상태형(고온, 충돌, 보류 멈춤, 잔량 부족)은 지금 참이면 보낸다.
- 시계: 기억의 시각이 now보다 미래면 만료로 본다(쿨다운 해제, 지속 시간은 now부터 다시 잰다).
- 배터리가 없는 맥(`hasBattery == false`): 배터리 이벤트(상한 도달, 완충, 잔량 부족, 고온)를 보내지 않는다.
- 앱이 앞에 있으면 `duplicatesAppMessage` 알림은 시스템 알림을 생략한다(앱 경고창이 이미 뜸).
- 집중 모드와 잠금 화면 미리보기는 macOS 알림 설정을 따른다.
- 앱이 실행 중일 때만 알린다. 앱이 백그라운드에서 App Nap에 들면 측정이 최대 약 2분 늦어질 수 있고(기존 이력에서 측정한 최대 간격 120초) 알림도 그만큼 늦을 수 있다. 배터리 앱이 늘 깨어 있으면 목적에 어긋나므로 App Nap 방지는 하지 않는다.

## 화면

설정 "알림" 카드:
- 권한 상태: 허용됨 / 거부됨 / 아직 묻지 않음 / 개발 실행이라 사용 불가. 버튼: "알림 허용"(요청), "시스템 설정 열기"(거부 시), "테스트 알림 보내기".
- 권한은 앱 시작 때 묻지 않고 "알림 허용"을 누를 때만 묻는다.
- 네 묶음의 토글과 한 줄 설명, 잔량 부족 기준(10~50%, 5 단위), 고온 기준(충전 중 36~45°C, 배터리 사용 중 +2°C).
- 안내: 앱 실행 중에만, 최대 2분 지연 가능, 집중 모드에서 가려질 수 있음, 잠금 화면 미리보기는 macOS 설정.

건강 분석 제안 카드: "새 제안 알림" 토글.

알림 클릭: `dashboard`, `settings`, `sessions`, `health`만 허용, 그 밖은 `dashboard`. 섹션을 바꾸고 창을 열어 앞으로 가져온다.

## 오류 처리

- 알림 권한 거부·미결정: 보내지 않고 기억은 갱신한다. 설정에 상태 표시.
- 알림 추가 실패: 무시한다(다음 이벤트에 영향 없음).
- `notify.json` 손상: `JSONFile`이 격리하고 빈 기억으로 시작. 쓰기 실패는 조용히 무시하고 다음 측정에서 다시 쓴다(알림 기억 때문에 사용자를 방해하지 않는다).

## 검증

- 단위 테스트: 이벤트마다 보냄·안 보냄·재무장·꺼짐; 첫 실행과 공백; 시계 역행; 주차 변경; 배터리 없음과 오래된 온도; 어댑터 흔들림; 세션(보호 해제 후 종료, 사용자 해제, 취소, 3개 초과 묶음, 앱 꺼진 동안 종료 10분 이내/초과, 사라진 ID 정리); 상한 출처 변화(앱이 직접 바꿈, 보류 복원, 완충 중은 제외); 설정·기억의 빠진 키; 손상 파일 격리와 0600.
- 원격: 전체 테스트, CI, 출시용 빌드를 임시 데이터 폴더로 실행해 시작 시 권한을 묻지 않고 죽지 않는지, `notify.json`이 0600으로 생기는지 확인.
- 맥 앞(Task 8과 함께): ad-hoc 서명 앱의 권한 창, 앱이 앞·뒤에 있을 때 테스트 알림, 클릭 이동, 재빌드 후 권한 유지, 완충 끝남 조건 확정.
