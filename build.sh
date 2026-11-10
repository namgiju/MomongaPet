#!/bin/zsh
# MomongaPet.app 빌드 (Apple Silicon + Intel 유니버설)
# 사용법: ./build.sh            -> build/MomongaPet.app
#         ./build.sh --zip      -> build/MomongaPet.zip 도 생성 (배포용)
set -euo pipefail
cd "${0:A:h}"

APP=build/MomongaPet.app
MIN=12.0

# 설치된 Command Line Tools의 기본 SDK가 컴파일러보다 새로우면 빌드가 깨져서,
# 컴파일러와 맞는 SDK를 찾아 씀 (SDK 환경변수로 직접 지정 가능)
if [[ -z "${SDK:-}" ]]; then
  SDK=$(xcrun --show-sdk-path)
  if ! echo 'import Cocoa' | swiftc -sdk "$SDK" -typecheck - 2>/dev/null; then
    for s in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -Vr); do
      if echo 'import Cocoa' | swiftc -sdk "$s" -typecheck - 2>/dev/null; then SDK=$s; break; fi
    done
  fi
fi
echo "SDK: $SDK"

rm -rf build && mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -sdk "$SDK" -target $arch-apple-macos$MIN main.swift -o build/MomongaPet-$arch
done
lipo -create build/MomongaPet-arm64 build/MomongaPet-x86_64 -output "$APP/Contents/MacOS/MomongaPet"
rm build/MomongaPet-arm64 build/MomongaPet-x86_64
cp Info.plist "$APP/Contents/"

# 기본 스프라이트 (sprites/ 폴더가 있으면 앱 안에 포함)
if [[ -d sprites ]] && ls sprites/*.png >/dev/null 2>&1; then
  mkdir -p "$APP/Contents/Resources/sprites"
  cp sprites/*.png "$APP/Contents/Resources/sprites/"
fi

# 앱 아이콘: icon.png가 있으면 그걸, 없으면 sprites/idle_01.png로 생성
ICON_SRC=""
[[ -f icon.png ]] && ICON_SRC=icon.png
[[ -z "$ICON_SRC" && -f sprites/idle_01.png ]] && ICON_SRC=sprites/idle_01.png
if [[ -n "$ICON_SRC" ]]; then
  SET=build/AppIcon.iconset; mkdir -p $SET
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz "$ICON_SRC" --out $SET/icon_${sz}x${sz}.png >/dev/null
    sips -z $((sz*2)) $((sz*2)) "$ICON_SRC" --out $SET/icon_${sz}x${sz}@2x.png >/dev/null
  done
  iconutil -c icns $SET -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf $SET
fi

codesign --force --deep -s - "$APP"   # ad-hoc 서명 (Apple Silicon에서 실행에 필요)
echo "완료: $APP"

if [[ "${1:-}" == "--zip" ]]; then
  ditto -c -k --keepParent "$APP" build/MomongaPet.zip
  echo "완료: build/MomongaPet.zip"
fi
