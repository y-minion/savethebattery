# 충전 제어 엔진 설계 — AlDente Pro 대체 1단계

작성일: 2026-10-20  
상태: 사용자 승인(대화, 2026-10-20). 상위 설계: [2026-10-18-design.md](2026-10-18-design.md)의 3단계.

## 1. 목적

사용자는 AlDente Pro를 삭제하고 VibeBattery로 완전히 대체하려 한다. 최우선 목표는 M4 Pro 맥북의 배터리 수명 보존이다. 대체 작업은 여러 하위 프로젝트로 나누며, 이 문서는 첫 하위 프로젝트인 **충전 제어 엔진**을 다룬다.

- 사용자가 고른 충전 상한(50~100%)을 적용하고, 실제 적용 여부를 확인해 표시한다.
- 한 번만 100% 충전한 뒤 원래 상한으로 돌아간다.
- 배터리 온도가 높으면 충전을 보류한다.
- 다른 충전 관리 앱과 동시에 제어하지 않는다.

완료 기준은 단위 테스트와 이 맥의 실기 검증이다. 수명 연장 효과는 주장하지 않는다.

## 2. 확인된 기기 사실 (2026-10-20, 읽기 전용 조사)

대상: MacBook Pro M4 Pro (Mac16,8), macOS 27.0.1, 펌웨어 20457.1.29.

| 항목 | 결과 |
|---|---|
| SMC 충전 중지 키 `CHTE`, `CH0B`, `CH0C`, `CH0I` | 존재하지 않음 |
| 펌웨어 상한 키 `bfD0`, `bfE0`, `bfF0` | 목록에는 있으나 읽기 거부 (kIOReturnNotPrivileged) |
| `CHIE` | 존재. 어댑터 전원을 차단하는 키로, 배터리 사용 최소화 목표와 맞지 않아 사용하지 않는다 |
| `ACLC` (MagSafe LED) | 읽기 가능, 쓰기는 미확인 |
| macOS 기본 충전 상한 (MCL) | `PowerUISmartChargeClient.isMCLSupported = true`. 설정 화면 선택지는 80·85·90·95·100 |
| 현재 상태 | MCL 활성, 상한 79% (`pmset -g battlimit`의 소유자는 PowerUIAgent). AlDente Pro 1.39.4와 root 헬퍼가 실행 중 |

PowerUI 클래스의 관련 메서드: `getMCLLimitWithError:`, `isMCLCurrentlyEnabled:`, `availableChargeLimitsWithError:`, `setMCLLimit:error:`, `temporarilyDisableMCL:`, `temporarilyOverrideMCLTargetSoC:error:`, `enableMCL:`, `disableMCL:`.

80% 미만 상한은 root 소유의 `com.apple.smartcharging.topoffprotection` 도메인에 `MCLFeatureState`와 `mclLimitValue`를 쓰고 Darwin 알림 `com.apple.smartcharging.defaultschanged`를 보내는 방식으로 적용되는 것으로 보인다. 근거는 AlDente 실행 파일의 문자열과 공개 PR(actuallymentor/battery #480)이며, 이 기기에서의 쓰기 동작은 아직 검증하지 않았다. AlDente 코드는 가져오지 않는다.

이 펌웨어에서 SMC 직접 쓰기는 root 권한으로도 막혀 있다. 따라서 상한 아래 하한을 직접 정하는 항해, 강제 방전, 교정은 어댑터 차단 없이 구현할 수 없다.

## 3. 범위

포함:
- 상한 읽기·쓰기(50~100%), 쓰기 후 확인
- 한 번 완충과 종료
- 과열 시 충전 보류와 재개
- 다른 충전 관리 앱 감지, 외부 변경 보존
- root 헬퍼(최소 실행기)와 설치·제거
- 대시보드의 충전 제어 카드, 메뉴바 앱의 로그인 시 실행 등록

제외(화면에 이유 표시):
- 항해의 재충전 하한 지정: 펌웨어가 정한다.
- 강제 방전·교정·어댑터 차단: 수명 보존 목표와 상위 설계에 어긋난다.
- MagSafe LED, 일정, 단축어, 표시 설정: 다음 하위 프로젝트에서 다룬다.

## 4. 구조

정책은 앱이 판단하고, root 헬퍼는 정해진 명령만 실행한다.

### 4.1 `BatteryCore/ChargeControl.swift` (순수 로직)

- `ChargeCommand`: `setLimit(percent)`, `clearLimit`, `startTopUp`, `endTopUp`.
- 검증: 상한은 50~100 정수만 허용한다. 80 미만은 헬퍼가 필요하다고 판단한다(`requiresHelper`).
- `ChargeLimitState`: MCL 활성 여부, 현재 상한(없으면 unknown), VibeBattery가 마지막으로 쓴 값, 다른 제어 앱 감지 결과.
- 외부 변경 판단: 현재 상한이 VibeBattery가 마지막으로 쓴 값과 다르면 외부 변경으로 보고 자동 동작을 멈춘다.
- 과열 보류 판단은 기존 `ChargePolicy`의 히스테리시스 모델을 재사용하거나 확장한다.

### 4.2 `BatteryPlatform/ChargeLimitReader` (사용자 권한)

PowerUI 프레임워크를 동적으로 불러 위 읽기 메서드를 호출한다. 클래스나 선택자가 없으면 상태를 unknown으로 둔다. 0이나 기본값으로 대체하지 않는다.

### 4.3 쓰기 경로

- 80~100%: 앱이 PowerUI `setMCLLimit:error:`를 사용자 권한으로 호출한다. 헬퍼 없이 동작한다.
- 50~79%: `VBChargeHelper`에 XPC로 요청한다.
- 한 번 완충: `temporarilyDisableMCL:`. 사용자 권한으로 동작하지 않으면 헬퍼 경로를 사용한다.
- 모든 쓰기 뒤에 다시 읽어 확인한다. 값이 다르면 "적용 실패"로 표시하고 자동 재시도하지 않는다.

### 4.4 `VBChargeHelper` (root LaunchDaemon)

- Mach 서비스 `io.github.y-minion.vibebattery.helper` 하나만 연다.
- XPC 프로토콜 메서드: `setLimit(UInt8)`, `clearLimit()`, `setTopUp(Bool)`, `readState()`. 범위 밖 값은 거부한다. 임의 도메인·키·명령 실행 인터페이스는 두지 않는다.
- 호출자 확인: 감사 토큰의 실효 UID가 현재 콘솔 사용자이고, 코드 서명 식별자가 `io.github.y-minion.vibebattery`이며, 실행 파일이 `/Applications/VibeBattery.app` 안에 있어야 한다. ad-hoc 서명이라 팀 ID로 고정할 수 없다는 한계를 문서에 남긴다. Developer ID 서명 단계에서 지정 요구 사항으로 강화한다.
- 헬퍼는 상태를 저장하지 않는다.
- 설치: 계획의 첫 작업에서 ad-hoc 서명 앱의 `SMAppService.daemon` 등록 가능 여부를 확인한다. 불가하면 관리자 암호를 한 번 요구하는 설치 스크립트로 `/Library/PrivilegedHelperTools`와 `/Library/LaunchDaemons`에 설치한다.
- 제거: 데몬과 plist만 지운다. 적용 중인 상한은 그대로 두고, 제거 화면에서 이 사실을 알린다.

### 4.5 `ChargeControllerDetector`

AlDente 앱·헬퍼(`com.apphousekitchen.aldente*`), batt, 그 밖에 알려진 충전 관리 앱의 실행 프로세스와 launchd 등록을 확인한다. 하나라도 있으면 모든 쓰기를 막고 "AlDente를 종료하거나 삭제하면 제어할 수 있습니다"라고 안내한다. 다른 앱을 종료하거나 삭제하지 않는다.

### 4.6 UI

- 대시보드 "충전 제어" 카드: 현재 상한과 출처(VibeBattery / 외부 / 알 수 없음), 상한 선택, 한 번 완충, 과열 보류 상태, 헬퍼 설치 상태, 충돌 경고, 제공하지 않는 기능과 이유.
- 메뉴바 앱의 로그인 시 실행은 `SMAppService.mainApp`으로 등록하며 사용자가 끌 수 있다.

## 5. 동작 규칙

### 상한

첫 실행에서는 현재 값을 읽어 보여주기만 하고 바꾸지 않는다. 사용자가 50~100%에서 골라 적용하며 제안값은 80%다. 적용이 확인된 값만 "VibeBattery가 쓴 값"으로 저장한다. 앱 종료·잠자기·재부팅 뒤에도 유지되는지는 실기에서 검증한다.

### 한 번 완충

macOS가 원래 상한으로 언제 돌아가는지(100% 도달, 어댑터 분리, 시간 경과)는 실기에서 관찰한 대로 표시한다. 복귀가 확인되지 않으면 "완충 모드 유지 중"으로 표시하고 사용자가 직접 끝낼 수 있게 한다.

### 과열 시 충전 보류

- 보류 조건: 배터리 온도 ≥ 보류 온도, 충전 중, 잔량 ≥ 50%.
- 보류 동작: 상한을 현재 잔량으로 일시적으로 낮춘다. 80% 미만이면 헬퍼가 필요하다.
- 재개: 재개 온도 이하가 5분 동안 유지되면 사용자 상한으로 되돌린다. 단 현재 상한이 VibeBattery가 쓴 보류값과 같을 때만 되돌린다.
- 기본값: 보류 35°C, 재개 32°C. 사용자가 바꿀 수 있으며 재개 온도는 보류 온도보다 낮아야 한다. 이 값은 Apple의 공식 안전 기준이 아닌 보수적 설계값이라고 표시한다.
- 온도가 없거나 2분 넘게 오래되면 자동 보류를 "중지됨"으로 표시한다.
- 잔량이 50% 미만이거나 헬퍼가 없어 낮출 수 없으면 경고만 표시한다.
- 메뉴바 앱이 실행 중일 때만 동작하며 이를 화면에 표시한다. 이 기능은 Apple의 하드웨어 보호를 대체하지 않는다.

### 충돌과 외부 변경

다른 충전 관리 앱이 감지되면 쓰기를 막는다. 상한이 외부에서 바뀌면 덮어쓰지 않고 "외부에서 변경됨"으로 표시한다. 사용자가 다시 적용하면 그 값을 새 기준으로 삼는다.

## 6. 오류 처리

| 상황 | 동작 |
|---|---|
| 헬퍼 없음·응답 없음 | 80~100%만 허용, 80% 미만과 그에 의존하는 과열 보류는 비활성 |
| PowerUI 클래스·선택자 없음 | 충전 제어 전체를 "이 macOS에서 확인 안 됨"으로 비활성 |
| 쓰기 뒤 읽은 값 불일치 | "적용 실패" 표시, 재시도 없음 |
| 호출자 확인 실패 | 헬퍼가 요청 거부, 앱에 이유 표시 |

## 7. 검증

단위 테스트(CI 포함): 명령 범위와 헬퍼 필요 판단, 과열 보류·재개 히스테리시스와 5분 안정 조건, 오래된 온도 처리, 외부 변경 시 복원 금지, 충돌 감지, 호출자 확인 규칙.

실기 검증(이 맥, `docs/VALIDATION.md`에 기록):
1. 시작 전 상한 값(현재 79%)을 기록하고, 검증이 끝나면 그 값으로 복원한다.
2. AlDente를 사용자가 직접 종료하거나 삭제한 뒤에만 쓰기 검증을 진행한다.
3. 80% 이상 쓰기와 확인, 79% 이하 쓰기(헬퍼), 한 번 완충과 복귀, 앱 종료·잠자기·재부팅 뒤 유지.
4. 상한 근처 동작은 잔량이 자연스럽게 도달했을 때만 확인한다. 시험을 위한 반복 완충·방전은 하지 않는다.
5. 과열 보류는 테스트 온도 주입으로 정책만 확인한다. 실제 고온 동작은 미검증으로 표시한다.

## 8. 이후 하위 프로젝트

1. MagSafe LED(쓰기 가능 여부 검증 후)
2. 일정·단축어
3. 메뉴바 표시 설정, 1년 건강도 이력
4. Developer ID 서명·공증과 헬퍼 요구 사항 강화

## 참고 자료

- batt README (macOS 27 펌웨어 제약): https://github.com/charlie0129/batt
- actuallymentor/battery PR #480 (macOS 기본 상한 사용): https://github.com/actuallymentor/battery/pull/480
- actuallymentor/battery PR #478: https://github.com/actuallymentor/battery/pull/478
- AlDente issue #1785: https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/issues/1785
