<!-- GeekNews, OKKY, 클리앙 공용 초안 (한국어). 사이트마다 말투와 분량만 조금 다듬으세요. 직접 올리는 글입니다. -->

# GeekNews (Show GN 형식)

**제목:** Show GN: Save the Battery – 무료 오픈소스 macOS 배터리 관리 메뉴 막대 앱

노트북 수명은 결국 배터리가 정한다고 생각해서 만들었습니다. 충전 상한(50~100%), 요일별 일정, 한 번만 완충, 과열 시 충전 보류, 전력 흐름, 저전력 모드 스위치, MagSafe LED, 단축어 동작까지 전부 무료입니다. 오픈소스(MIT)이고 원격 측정이 없으며, 네트워크 요청은 하루 한 번 새 버전을 확인하는 것뿐입니다(끌 수 있음).

특징은 숫자를 약속하지 않는 것입니다. "수명이 N년 늘어난다" 대신 내 맥에서 잰 값(90%·95% 이상 충전 시간, 35 °C·40 °C 이상 시간, 사이클, 용량 기반 건강도 추정)을 지난 기간과 비교해 보여 줍니다. 근거 자료는 Apple 충전 상한 안내(support.apple.com/102338)와 Battery University BU-808입니다.

터미널 코딩 에이전트(Claude, Codex 등)를 오래 돌릴 때를 위해 `stb run`으로 명령을 감싸면 작업 동안만 잠자기를 막는 기능도 있습니다.

한계: 베타(0.2.0)이고 Mac 한 대(M4 Pro, macOS 27.0.1)에서만 직접 확인했습니다. 충전 상한은 Apple 실리콘 + macOS 26.4 이상, 나머지는 macOS 15 이상(Intel 포함)입니다. 공증을 받지 않아(유료 프로그램 미가입) 터미널 설치는 경고 없이 열리고, 브라우저 다운로드는 "그래도 열기"가 한 번 필요합니다. 선택 헬퍼는 정해진 요청만 받고 SMC 키 하나(MagSafe LED)만 씁니다.

```sh
curl -fsSL https://github.com/y-minion/savethebattery/releases/latest/download/install.sh | sh
```
https://github.com/y-minion/savethebattery

---

# OKKY / 클리앙 (짧은 버전)

**제목:** 맥북 배터리 관리 앱을 무료 오픈소스로 만들었습니다 (Save the Battery)

안녕하세요. 맥북 배터리를 80%에서 멈추게 해 주는 메뉴 막대 앱을 만들어 공개했습니다. 충전 상한, 일정, 한 번만 완충, 과열 보류, 전력 흐름, 저전력 모드, 단축어 지원까지 전부 무료이고 광고도 원격 측정도 없습니다.

수명이 몇 년 늘어난다는 말은 하지 않습니다. 대신 내 맥에서 실제로 잰 값(높은 충전량·고온으로 보낸 시간, 사이클)을 보여 줍니다.

- 베타 0.2.0, 아직 제 Mac 한 대에서만 직접 테스트했습니다. 문제 있으면 이슈로 알려 주세요.
- 충전 상한은 Apple 실리콘 + macOS 26.4 이상. 나머지 기능은 macOS 15 이상 Intel도 됩니다.
- 설치 후 가장 먼저 상한을 80%로 맞추세요(Apple Silicon, macOS 26.4 이상).

설치(스크립트는 저장소에서 먼저 읽어 보실 수 있습니다):
```sh
curl -fsSL https://github.com/y-minion/savethebattery/releases/latest/download/install.sh | sh
```
저장소: https://github.com/y-minion/savethebattery
