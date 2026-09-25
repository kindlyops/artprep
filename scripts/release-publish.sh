#!/bin/bash
# shellcheck disable=SC2154,SC2034
# Shared release variables are assigned and consumed by the sourcing release.sh.
set -euo pipefail
# release.sh provides and validates all shared release context before calling these functions.

verify_release_assets() {
	local directory="$1" extracted="$1/extracted" plist
	.venv/bin/python scripts/update_metadata.py checksum "$directory/$archive.sha256" "$directory/$archive"
	verify_update_feed "$directory/appcast.xml" "$directory/$archive" "$version"
	ditto -x -k "$directory/$archive" "$extracted"
	plist="$extracted/Art Prep.app/Contents/Info.plist"
	[[ "$(plutil -extract CFBundleIdentifier raw -o - "$plist")" == local.artprep.mac ]] || fail 'Wrong app in draft.'
	[[ "$(plutil -extract CFBundleVersion raw -o - "$plist")" == "$version" ]] || fail 'Wrong version in draft.'
	[[ "$(plutil -extract ArtPrepSourceCommit raw -o - "$plist")" == "$commit" ]] || fail 'Draft source does not match tag.'
	[[ "$(plutil -extract SUPublicEDKey raw -o - "$plist")" == "$(cat assets/sparkle-public-key.txt)" ]] || fail 'Draft signing key differs.'
	codesign --verify --deep --strict \
		-R '=anchor apple generic and certificate leaf[subject.OU] = "K5U72ZNJ2W" and certificate 1[field.1.2.840.113635.100.6.2.6] exists' \
		"$extracted/Art Prep.app"
	xcrun stapler validate "$extracted/Art Prep.app"
	spctl --assess --type execute --verbose=2 "$extracted/Art Prep.app"
}

download_draft() {
	local directory="$1"
	mkdir -p "$directory"
	gh release download "$tag" --repo "$repository" --dir "$directory" \
		--pattern "$archive" --pattern "$archive.sha256" --pattern appcast.xml
	verify_release_assets "$directory"
}

check_newer_version() {
	local latest
	latest="$(gh release list --repo "$repository" --exclude-drafts --exclude-pre-releases \
		--limit 100 --json tagName --jq '.[].tagName')"
	.venv/bin/python - "$version" "$latest" <<'PY'
import re
import sys

version = tuple(map(int, sys.argv[1].split(".")))
for tag in sys.argv[2].splitlines():
    if re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        if tuple(map(int, tag[1:].split("."))) >= version:
            sys.exit("Release stopped: this version would replace an equal or newer release.")
PY
}

promote_draft() {
	local downloaded="$staging/downloaded" public="$staging/public-appcast.xml"
	download_draft "$downloaded"
	if [[ "${release_mode:-release}" != resume ]]; then
		cmp "$downloaded/$archive" "dist/$archive"
		cmp "$downloaded/appcast.xml" "$feed_dir/appcast.xml"
	fi
	check_newer_version
	gh release edit "$tag" --repo "$repository" --draft=false --latest
	printf 'Published %s; verifying the public feed. Do not rebuild this version on failure.\n' "$tag"
	curl -fsSL --retry 3 --retry-all-errors --max-time 60 \
		"https://github.com/kindlyops/artprep/releases/latest/download/appcast.xml" -o "$public"
	verify_update_feed "$public" "$downloaded/$archive" "$version"
	curl -fsIL --retry 3 --max-time 60 \
		"https://github.com/kindlyops/artprep/releases/download/$tag/$archive" >/dev/null
	printf 'Verified public update %s.\n' "$tag"
}

resume_release() {
	version="$1"
	tag="v$version"
	repository=kindlyops/artprep
	archive="Art-Prep-$tag-macOS-arm64.zip"
	gh auth status
	git fetch origin main --tags
	commit="$(git rev-parse "$tag^{commit}")"
	check_source
	[[ "$(gh release view "$tag" --repo "$repository" --json isDraft --jq .isDraft)" == true ]] ||
		fail 'Recovery requires an existing draft release.'
	check_newer_version
	tools="$(bash scripts/sparkle-tools.sh)"
	check_update_key
	staging="$(mktemp -d "${TMPDIR:-/tmp}/artprep-resume.XXXXXX")"
	promote_draft
}
