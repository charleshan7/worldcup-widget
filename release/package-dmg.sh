#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=${1:-1.0.0}
build_root="$repo_root/build/ReleasePackage"
products="$build_root/DerivedData/Build/Products/Release"
source_app="$products/WorldCupWidget.app"
staging="$build_root/dmg-root"
app_name="2026世界杯摸鱼看球小组件.app"
output="$build_root/2026世界杯摸鱼看球小组件-v${version}.dmg"

rm -rf "$staging" "$output"
mkdir -p "$staging"
cp -R "$source_app" "$staging/$app_name"
ln -s /Applications "$staging/应用程序"
cp "$repo_root/release/首次打开说明.txt" "$staging/"

codesign --force --sign - \
  --entitlements "$repo_root/Widget/Widget.entitlements" \
  "$staging/$app_name/Contents/PlugIns/WorldCupWidgetExtension.appex"
codesign --force --sign - \
  --entitlements "$repo_root/App/App.entitlements" \
  "$staging/$app_name"
codesign --verify --deep --strict --verbose=2 "$staging/$app_name"

hdiutil create \
  -volname "2026世界杯摸鱼看球小组件" \
  -srcfolder "$staging" \
  -ov \
  -format UDZO \
  "$output"

echo "$output"
