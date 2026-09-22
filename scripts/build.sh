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
iconset="$staging/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
	sips -z "$size" "$size" assets/AppIcon.png \
		--out "$iconset/icon_${size}x${size}.png" >/dev/null
	double_size=$((size * 2))
	sips -z "$double_size" "$double_size" assets/AppIcon.png \
		--out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
swift -warnings-as-errors -module-cache-path "$cache/icon-module-cache" \
	scripts/package-icon.swift "$iconset" "$app/Contents/Resources/AppIcon.icns"
cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Art Prep</string>
<key>CFBundleDisplayName</key><string>Art Prep</string>
<key>CFBundleIdentifier</key><string>local.artprep.mac</string>
<key>CFBundleExecutable</key><string>ArtPrep</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto --norsrc --noextattr "$app" "dist/Art Prep.app"
ditto -c -k --keepParent --norsrc --noextattr "$app" "dist/Art Prep.zip"
printf 'Built %s\n' "$PWD/dist/Art Prep.app"
