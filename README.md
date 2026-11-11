# MomongaPet

macOS 화면 아래 Dock 위를 돌아다니는 작은 데스크톱 펫.

- Dock 위를 걷고, 가만히 있고, 가끔 낮잠을 자요
- 잡아서 끌면 대롱대롱 흔들리고, 던지면 날아가서 떨어져요
- 맨 앞 창 위로 뛰어올라가 그 위에서 놀아요 (창을 움직이면 따라가고, 창이 가려지거나 닫히면 떨어짐)
- 3분 동안 컴퓨터를 안 쓰면 잠들고, 다시 쓰면 깨요

## 설치

```sh
./build.sh
cp -R build/MomongaPet.app /Applications/
open /Applications/MomongaPet.app
```

펫이 Dock 위에서만 다니게 하려면 시스템 설정 → 개인정보 보호 및 보안 → **손쉬운 사용**에서 MomongaPet을 켜세요
(우클릭 메뉴의 **Dock 크기 자동 맞추기**로 바로 열 수 있어요). 앱을 켜고 끌 때 바뀌는 Dock 너비를 2초마다 읽어 맞춰요.
권한이 없으면 `main.swift`의 `dockRangeFallback` 고정값을 써요.

빌드할 때마다 서명이 바뀌어서, 새로 빌드한 뒤엔 손쉬운 사용 목록에서 MomongaPet을 지우고 다시 켜야 할 수 있어요.

## 사용법

| 동작 | 결과 |
|---|---|
| 클릭 | 말 걸기 창 열기/닫기 |
| ⌃⌥M (어디서든) | 말 걸기 창 열기/닫기 |
| 드래그 | 잡아서 옮기기, 놓으면 던지기 |
| 더블클릭 | 점프 |
| 클릭 (자는 중) | 깨우기 |
| 우클릭 | 메뉴 (말 걸기 / 새 대화 / 말투 바꾸기 / 스프라이트 폴더 / 재우기 / 종료) |

## 비서 (Claude Code)

펫을 클릭하거나 **⌃⌥M**(또는 우클릭 → **말 걸기…**)으로 일을 시키면 펫이 백그라운드에서 `claude -p`를 실행하고, 답을 머리 위 말풍선으로 알려줘요.
[Claude Code](https://claude.com/claude-code) CLI가 설치돼 있고 로그인돼 있어야 해요 (구독 사용량을 씀).

- 홈 폴더에서 `--permission-mode auto`로 실행돼요. 파일 읽기·수정·명령 실행을 하고, 위험해 보이는 동작은 Claude Code가 스스로 막아요
- 모델은 가벼운 Haiku를 써요 (`main.swift`의 `claudeModel`로 sonnet·opus로 바꿀 수 있음)
- 대화는 이어져요. 처음부터 다시 하려면 **새 대화 시작**. 맥이 잠자기에서 깨어나면 자동으로 새 대화로 시작해요
- 일하는 중엔 **하던 일 그만두기**로 취소
- 펫이 먼저 말을 걸기도 해요 (자리에 있을 때만, 최소 30분 간격). 말풍선을 누르면 바로 대답할 수 있어요
  - 그날 처음 만났을 때 (새벽 5시 기준으로 하루를 셈)
  - 맥북 덮개를 열고 돌아왔을 때 (인터넷이 다시 연결될 때까지 기다렸다가, 실패하면 15초 뒤 다시 시도)
  - 2시간 넘게 쉬지 않고(5분 이상 입력 없음 = 쉼) 일할 때
  - 이때는 도구 없이 한마디만 만드는 가벼운 호출이라 토큰을 거의 안 써요 (`main.swift`의 `chatMinInterval` 등으로 조절)
- 긴 답은 잘려서 보이고, 말풍선을 누르면 전체(`~/MomongaPet/last_reply.txt`)가 열려요
- 말투는 **말투 바꾸기…**로 `~/MomongaPet/persona.txt`를 고치면 돼요. 말투가 바뀌면 자동으로 새 대화로 시작해요 (예전 말투로 쌓인 대화에 끌려가지 않게)

## 스프라이트 넣기

우클릭 → **스프라이트 폴더 열기** (`~/MomongaPet/sprites`)에 PNG를 넣고 **스프라이트 다시 불러오기**.

파일 이름 규칙: `상태_번호.png` (예: `idle_01.png`, `idle_02.png`)

| 상태 | 언제 | 없으면 |
|---|---|---|
| `idle` | 가만히 있을 때 | 흰 동그라미 |
| `walk` | 걸을 때 | idle |
| `drag` | 잡혀 있을 때 | idle |
| `jump` | 뛰어오를 때 (한 번만 재생) | fall → idle |
| `fall` | 떨어질 때 | idle |
| `sleep` | 잘 때 | idle |
| `dizzy` | 떨어지거나 던져진 뒤 2초 (스스로 뛴 점프는 제외) | idle |
| `notice` | 창 위에서 그 창 안의 마우스가 움직이면 0.5초 "!" (4칸 고정 순서: idle왼쪽·idle오른쪽·walk왼쪽·walk오른쪽) | idle |
| `watchright` / `watchleft` | "!" 뒤 마우스 쪽을 내려다봄. 2초간 움직임 없으면 평소대로 (뒤집지 않음) | idle |
| `listenright` / `listenleft` | 말 걸기 창이 열려 있거나 답을 기다리는 동안 멈춰서 귀 기울임 (보던 방향에 맞춰, 뒤집지 않음) | idle |

원본 그림은 오른쪽을 보고 있어야 해요 (왼쪽으로 걸을 땐 자동으로 뒤집힘).

### 그린스크린 시트 자르기

초록 배경에 캐릭터가 가로로 나란히 있는 이미지를 프레임별 투명 PNG로 잘라줘요.

```sh
pip install pillow numpy
python tools/slice_sprites.py sheet.png idle      # -> ~/MomongaPet/sprites/idle_01.png ...
```

## 직접 빌드

Xcode Command Line Tools만 있으면 돼요 (`xcode-select --install`).

```sh
./build.sh          # build/MomongaPet.app
./build.sh --zip    # 배포용 zip도 생성
```

`sprites/` 폴더에 PNG를 넣고 빌드하면 앱 안에 기본 스프라이트로 들어가요.
설정값(크기, 속도, 잠드는 시간, Dock 범위 등)은 `main.swift` 맨 위에 있어요.
