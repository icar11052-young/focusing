#!/bin/bash
# Mac universal 앱과 DMG·ZIP을 개인 설정 없이 빌드한다.
set -euo pipefail
cd "$(dirname "$0")/.."
version=0.2.0-beta.1
out="$PWD/build/macos"
app="$out/Focusing.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$out/objects"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -target "$arch-apple-macos14.0" macos/Focusing.swift -o "$out/objects/Focusing-$arch" -framework AppKit -framework ApplicationServices -framework ServiceManagement
done
lipo -create "$out/objects/Focusing-arm64" "$out/objects/Focusing-x86_64" -output "$app/Contents/MacOS/Focusing"
/usr/bin/python3 - "$app" "$version" <<'PY'
import sys,plistlib
from pathlib import Path
app=Path(sys.argv[1]);version=sys.argv[2]
info={'CFBundleExecutable':'Focusing','CFBundleIdentifier':'com.young.focusing.mac','CFBundleName':'Focusing','CFBundleDisplayName':'포커싱','CFBundlePackageType':'APPL','CFBundleVersion':'20001','CFBundleShortVersionString':version,'LSMinimumSystemVersion':'14.0','LSUIElement':True,'NSHighResolutionCapable':True}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/Focusing" --self-test
mkdir -p "$out/dmg"
cp -R "$app" "$out/dmg/Focusing.app"
cp macos/README.md "$out/dmg/사용안내.md"
ln -sfn /Applications "$out/dmg/Applications"
hdiutil create -volname "Focusing $version" -srcfolder "$out/dmg" -ov -format UDZO "$PWD/build/Focusing-$version-macos-universal.dmg"
ditto -c -k --keepParent "$app" "$PWD/build/Focusing-$version-macos-universal.zip"
file "$app/Contents/MacOS/Focusing"
