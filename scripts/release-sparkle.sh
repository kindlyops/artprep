#!/bin/bash
# shellcheck disable=SC2154,SC2034
# Shared release variables are assigned and consumed by the sourcing release.sh.
set -euo pipefail

# Shared context is validated by release.sh before these functions run.
# These functions run inside release.sh, sharing its validated release context.
check_update_key() {
	local expected actual probe
	expected="$(cat assets/sparkle-public-key.txt)"
	actual="$(perl -e 'alarm 60; exec @ARGV' "$tools/generate_keys" --account local.artprep.mac -p)"
	[[ "$actual" == "$expected" && "$actual" =~ ^[A-Za-z0-9+/]{43}=$ ]] ||
		fail 'Sparkle key missing or mismatched. Run ./scripts/release.sh setup-updates.'
	probe="$(mktemp)"
	printf 'Art Prep update signing preflight\n' >"$probe"
	if ! perl -e 'alarm 60; exec @ARGV' "$tools/sign_update" --account local.artprep.mac "$probe" >/dev/null; then
		rm "$probe"
		fail 'Sparkle signing failed or timed out. Allow its signing tools in Keychain Access.'
	fi
	rm "$probe"
}

sign_nested_code() {
	local framework component
	framework="$app/Contents/Frameworks/Sparkle.framework"
	for component in \
		"$framework/Versions/B/XPCServices/Downloader.xpc" \
		"$framework/Versions/B/XPCServices/Installer.xpc" \
		"$framework/Versions/B/Autoupdate" \
		"$framework/Versions/B/Updater.app" \
		"$framework"; do
		codesign --force --sign "$identity" --options runtime --timestamp \
			--preserve-metadata=entitlements "$component"
	done
}

verify_update_feed() {
	local feed="$1" zip="$2" expected_version="$3" signature
	perl -e 'alarm 60; exec @ARGV' "$tools/sign_update" --account local.artprep.mac --verify "$feed"
	signature="$(.venv/bin/python scripts/update_metadata.py "$feed" "$zip" "$expected_version")"
	perl -e 'alarm 60; exec @ARGV' "$tools/sign_update" --account local.artprep.mac --verify "$zip" "$signature"
}

generate_update_feed() {
	feed_dir="$staging/feed"
	mkdir -p "$feed_dir"
	cp "$staging/$archive" "$feed_dir/"
	perl -e 'alarm 60; exec @ARGV' "$tools/generate_appcast" --account local.artprep.mac \
		--maximum-deltas 0 \
		--download-url-prefix "https://github.com/kindlyops/artprep/releases/download/$tag/" \
		--link "https://github.com/kindlyops/artprep/releases/tag/$tag" "$feed_dir"
	verify_update_feed "$feed_dir/appcast.xml" "$feed_dir/$archive" "$version"
}

setup_updates() {
	tools="$(bash scripts/sparkle-tools.sh)"
	"$tools/generate_keys" --account local.artprep.mac
	local actual
	actual="$("$tools/generate_keys" --account local.artprep.mac -p)"
	[[ "$actual" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail 'Sparkle returned an invalid public key.'
	if [[ -f assets/sparkle-public-key.txt ]]; then
		[[ "$(cat assets/sparkle-public-key.txt)" == "$actual" ]] || fail 'Existing public key differs; do not rotate it silently.'
	else
		printf '%s\n' "$actual" >assets/sparkle-public-key.txt
	fi
	check_update_key
	printf 'Update signing ready. Commit assets/sparkle-public-key.txt before releasing.\n'
}
