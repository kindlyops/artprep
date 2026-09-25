#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/sparkle-version.env
source scripts/sparkle-version.env
root="${ARTPREP_SPARKLE_ROOT:-$HOME/Library/Caches/ArtPrep/Sparkle}/$version"
mkdir -p "$root"
stage="$(mktemp -d "$root/stage.XXXXXX")"
trap 'rm -r "$stage"' EXIT
archive="$root/download.zip"
verified() {
	[[ -f "$1" ]] && printf '%s  %s\n' "$sha256" "$1" | shasum -a 256 -c --status -
}
if ! verified "$archive"; then
	curl -fsSL --retry 2 -o "$stage/download.zip" \
		"https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-for-Swift-Package-Manager.zip"
	verified "$stage/download.zip" || {
		echo 'Sparkle checksum mismatch; nothing installed.' >&2
		exit 1
	}
	mv "$stage/download.zip" "$archive"
fi
unzip -q "$archive" -d "$stage/unpacked"
mkdir -p Vendor/Sparkle
# Reconstruct from verified bytes; a stamp cannot detect modified cached binaries.
if [[ -e Vendor/Sparkle/Sparkle.xcframework ]]; then
	mv Vendor/Sparkle/Sparkle.xcframework "$stage/previous-framework"
fi
cp -RP "$stage/unpacked/Sparkle.xcframework" Vendor/Sparkle/
if [[ -e "$root/bin" ]]; then mv "$root/bin" "$stage/previous-tools"; fi
mv "$stage/unpacked/bin" "$root/bin"
printf '%s/bin\n' "$root"
