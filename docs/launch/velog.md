<!-- velog 글 초안 (한국어). 제목 후보와 본문입니다. 올리기 전에 이미지 자리를 실제 캡처로 바꾸세요. -->

# 제목 후보
- 맥북 배터리 기록을 직접 재 보는 앱: 무료 오픈소스 VibeBattery 만든 이야기
- 노트북 수명은 배터리가 정한다 — 돈 안 받는 맥 배터리 관리 앱을 만들었습니다

# 본문

노트북이 결국 낡는 이유는 대개 배터리입니다. 리튬 이온 배터리는 높은 충전량으로 오래 있을수록, 거기에 열까지 더해지면 더 빨리 낡습니다. Apple도 그래서 macOS에 충전 상한 기능을 넣었고([support.apple.com/102338](https://support.apple.com/102338)), 스트레스가 어떻게 쌓이는지는 Battery University에 잘 정리되어 있습니다([BU-808](https://batteryuniversity.com/article/bu-808-how-to-prolong-lithium-based-batteries)).

<!-- 작성자 확인: 실제 경험에 맞게 고치세요 -->
저도 어느 블로그 글을 보고 배터리 앱을 깔았습니다. 그런데 깔고 나서도 "이게 정말 도움이 되고 있나?"를 알 방법이 없었습니다. 숫자가 하나도 안 보였거든요. 그래서 **VibeBattery**를 만들었습니다.

![메뉴 창](docs/images/menu-window.ko.gif)

## VibeBattery가 하는 일
- 메뉴 막대에서 충전 중, 상한 대기, 과열 보류를 아이콘으로 보여 줍니다.
- 충전 상한 50~100%, 요일·시각별 일정, 한 번만 100% 충전, 과열 시 충전 보류.
- 전력 흐름(어댑터 입력, 배터리, Mac이 쓰는 전력), 하드웨어 잔량.
- 저전력 모드 스위치, MagSafe LED 모드.
- 건강 기록: **실제로 잰 값**만 보여 줍니다. 90%·95% 이상으로 보낸 시간, 35 °C·40 °C 이상으로 보낸 시간, 사이클, 용량 기반 건강도 추정. 지난 기간과 비교합니다.
- 터미널에서 Claude, Codex 같은 코딩 에이전트를 오래 돌릴 때 `vbctl run`으로 감싸면 Mac이 잠들지 않습니다.
- 단축어 동작, 알림, 한국어·영어 UI.

다른 앱이 돈을 받는 기능도 전부 무료입니다. 오픈소스(MIT)이고 원격 측정은 없습니다. 네트워크 요청은 하루 한 번 새 버전을 확인하는 것뿐이고, 설정에서 끌 수 있습니다.

## 숫자를 약속하지 않는 이유
"배터리 수명이 2년 늘어납니다" 같은 말은 하지 않습니다. 앱이 보여 주는 것은 내 맥에서 실제로 잰 값뿐입니다. "상한이 80%였다면" 비교도 일반적인 리튬 이온 자료로 계산한 상대 스트레스 지수이고, 수명을 말하는 것이 아닙니다.

## 설치 (터미널 한 줄)
```sh
curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh
```
체크섬을 검증하고 sudo 없이 `/Applications`에 설치합니다. curl로 받으면 Gatekeeper 경고가 뜨지 않습니다. 앱은 무료 Apple Development 인증서로 서명했고 공증은 받지 않았습니다(유료 프로그램이 필요해서요). 브라우저로 zip을 받으면 시스템 설정 › 개인정보 보호 및 보안에서 "그래도 열기"를 한 번 눌러야 합니다. 스크립트 소스는 저장소에 있으니 `sh`에 넘기기 전에 읽어 보세요.

**가장 먼저 할 일: 충전 상한을 80%로 맞추세요(Apple Silicon, macOS 26.4 이상).**

## 솔직한 한계
- 0.2.0 베타입니다. 지금까지 제 Mac 한 대(M4 Pro, macOS 27.0.1)에서만 직접 테스트했습니다.
- 충전 상한은 Apple 실리콘 + macOS 26.4 이상에서만 됩니다. Intel과 이전 macOS에서는 나머지 기능은 되고 충전 상한은 계획 중입니다.
- 80% 미만 상한, 저전력 모드 스위치, MagSafe LED는 작은 루트 헬퍼가 필요합니다. 필요할 때만 앱에서 관리자 암호 창으로 설치하고, 정해진 요청만 받으며 SMC 키는 MagSafe LED 하나만 씁니다.

문제를 찾으면 이슈로 알려 주세요. 제거도 한 줄입니다.
```sh
curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/uninstall.sh | sh
```

## 설치 한 줄과 저장소
```sh
curl -fsSL https://github.com/y-minion/vibebattery/releases/latest/download/install.sh | sh
```
https://github.com/y-minion/vibebattery
