#!/bin/zsh
# Builds Wisp.app.
#   ./build.sh             native build            -> build/Wisp.app
#   ./build.sh install     native build, then copy to /Applications and launch
#   ./build.sh universal   Apple Silicon + Intel   -> build/Wisp.app (used for releases)
#   ./build.sh dmg         universal build, then build/Wisp-<version>.dmg
set -euo pipefail
cd "${0:A:h}"
MODE="${1:-}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

if [[ "$MODE" == "universal" || "$MODE" == "dmg" ]]; then
  swift build -c release --triple arm64-apple-macosx14.0
  swift build -c release --triple x86_64-apple-macosx14.0
  mkdir -p build
  lipo -create .build/arm64-apple-macosx/release/Wisp .build/x86_64-apple-macosx/release/Wisp -output build/Wisp-bin
  TOOL=.build/arm64-apple-macosx/release/Wisp
  [[ "$(uname -m)" == "x86_64" ]] && TOOL=.build/x86_64-apple-macosx/release/Wisp
else
  swift build -c release
  mkdir -p build
  cp .build/release/Wisp build/Wisp-bin
  TOOL=.build/release/Wisp
fi

APP=build/Wisp.app
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv build/Wisp-bin "$APP/Contents/MacOS/Wisp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/wisp-hook.py "$APP/Contents/Resources/wisp-hook.py"

# The icon is drawn by the app itself, from the same code as the mascot.
"$TOOL" --render-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "${WISP_SIGN_IDENTITY:--}" "$APP"
echo "Built $PWD/$APP"

if [[ "$MODE" == "install" ]]; then
  pkill -x Wisp 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Wisp.app
  cp -R "$APP" /Applications/Wisp.app
  open /Applications/Wisp.app
  echo "Installed to /Applications/Wisp.app"
fi

if [[ "$MODE" == "dmg" ]]; then
  STAGE=build/dmg
  rm -rf "$STAGE" && mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Wisp" -srcfolder "$STAGE" -ov -format UDZO "build/Wisp-$VERSION.dmg" >/dev/null
  echo "Packaged build/Wisp-$VERSION.dmg"
fi
