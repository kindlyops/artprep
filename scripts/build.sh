#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cache="${ARTPREP_BUILD_ROOT:-/private/tmp/artprep-$(id -u)}"
CLANG_MODULE_CACHE_PATH="$cache/cache/clang" swift build -c release --disable-sandbox \
	--scratch-path "$cache/build" --cache-path "$cache/cache" \
	--config-path "$cache/config" --security-path "$cache/security" \
	-Xswiftc -warnings-as-errors
binary="$(swift build -c release --show-bin-path --scratch-path "$cache/build" --cache-path "$cache/cache" --config-path "$cache/config" --security-path "$cache/security")/ArtPrep"
staging="$(mktemp -d "$cache/bundle.XXXXXX")"
app="$staging/Art Prep.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/renderer" dist
cp "$binary" "$app/Contents/MacOS/ArtPrep"
cp renderer/job.py renderer/render.py "$app/Contents/Resources/renderer/"
cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Art Prep</string>
<key>CFBundleDisplayName</key><string>Art Prep</string>
<key>CFBundleIdentifier</key><string>local.artprep.mac</string>
<key>CFBundleExecutable</key><string>ArtPrep</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto --norsrc --noextattr "$app" "dist/Art Prep.app"
ditto -c -k --keepParent --norsrc --noextattr "$app" "dist/Art Prep.zip"
printf 'Built %s\n' "$PWD/dist/Art Prep.app"
