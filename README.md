# MomongaPet

macOS 화면 아래 Dock 위를 돌아다니는 작은 데스크톱 펫.

- Dock 위를 걷고, 가만히 있고, 가끔 낮잠을 자요
- 잡아서 끌면 대롱대롱 흔들리고, 던지면 날아가서 떨어져요
- 맨 앞 창 위로 뛰어올라가 그 위에서 놀아요 (창을 움직이면 따라가고, 창이 가려지거나 닫히면 떨어짐)
- 3분 동안 컴퓨터를 안 쓰면 잠들고, 다시 쓰면 깨요

## 설치

1. [Releases](../../releases)에서 `MomongaPet.zip`을 받아 압축을 풀고 `MomongaPet.app`을 응용 프로그램 폴더로 옮기기
2. 처음 실행할 때 "확인되지 않은 개발자" 경고가 뜨면:
   - **시스템 설정 → 개인정보 보호 및 보안** 아래쪽의 **"그래도 열기"** 클릭
   - 또는 터미널에서 `xattr -dr com.apple.quarantine /Applications/MomongaPet.app`

macOS 12 이상, Apple Silicon / Intel 모두 지원.

### Dock 위에서만 다니게 하기 (선택)

기본은 화면 아래쪽 전체 너비를 돌아다녀요. Dock 아이콘 줄 위에서만 다니게 하려면
우클릭 → **Dock 위에서만 다니게 하기 (권한 필요)** → 시스템 설정의 **손쉬운 사용**에서 MomongaPet 켜기.
Dock 위치를 읽는 데만 쓰고, 다른 앱을 조작하지 않아요.

## 사용법

| 동작 | 결과 |
|---|---|
| 드래그 | 잡아서 옮기기, 놓으면 던지기 |
| 더블클릭 | 점프 |
| 클릭 (자는 중) | 깨우기 |
| 우클릭 | 메뉴 (스프라이트 폴더 열기 / 다시 불러오기 / 재우기 / 종료) |

## 스프라이트 넣기

캐릭터 이미지는 저장소에 포함돼 있지 않아요. 이미지가 없으면 흰 동그라미가 나와요.

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
