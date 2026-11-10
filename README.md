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
| 드래그 | 잡아서 옮기기, 놓으면 던지기 |
| 더블클릭 | 점프 |
| 클릭 (자는 중) | 깨우기 |
| 우클릭 | 메뉴 (스프라이트 폴더 열기 / 다시 불러오기 / 재우기 / 종료) |

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
