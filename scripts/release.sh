#!/bin/bash
set -euo pipefail
set -E
cd "$(dirname "$0")/.."

fail() {
	printf 'Release stopped: %s\n' "$*" >&2
	exit 1
}

trap 'printf "Release stopped at line %s. Fix the error above before retrying.\n" "$LINENO" >&2' ERR

check_credentials() {
	xcrun notarytool history --keychain-profile "$profile" --output-format json |
		plutil -extract history xml1 -o /dev/null - ||
		fail "Cannot use Keychain profile '$profile'. Run ./scripts/release.sh setup PROFILE."
}

setup() {
	profile="${1:-artprep-notary}"
	[[ -n "$profile" && "$profile" != *$'\n'* ]] || fail "Use a nonempty profile name."
	if [[ $# == 0 ]]; then
		printf 'Apple will prompt securely. Use an app-specific password, not your login password.\n'
		xcrun notarytool store-credentials "$profile"
	fi
	check_credentials
	printf '%s\n' "$profile" >.artprep-notary-profile
	printf 'Ready. Future releases: ./scripts/release.sh VERSION\n'
}

select_identity() {
	local identities
	identities="$(security find-identity -v -p codesigning |
		sed -n '/"Developer ID Application:/s/^[[:space:]]*[0-9]*) \([A-F0-9]*\).*/\1/p')"
	identity="${ARTPREP_SIGNING_IDENTITY:-$identities}"
	[[ "$identity" =~ ^[A-F0-9]{40}$ ]] ||
		fail "Need one Developer ID Application identity. For several, set ARTPREP_SIGNING_IDENTITY to its SHA-1."
	grep -Fxq "$identity" <<<"$identities" || fail "Selected Developer ID identity is unavailable."
}

check_source() {
	[[ -z "$(git status --porcelain)" ]] || fail "Commit your changes before releasing."
	[[ "$(git branch --show-current)" == main ]] || fail "Switch to main after merging your PR."
	[[ "$(git rev-parse HEAD)" == "$commit" ]] || fail "Source changed during the release. Start again."
	[[ "$commit" == "$(git rev-parse origin/main)" ]] || fail "Update main from origin first."
}

preflight() {
	[[ "$(uname -m)" == arm64 ]] || fail "Build this arm64 release on an Apple Silicon Mac."
	[[ -f .artprep-notary-profile ]] || fail "Run ./scripts/release.sh setup PROFILE once first."
	IFS= read -r profile <.artprep-notary-profile
	select_identity
	gh auth status
	git fetch origin main --tags
	commit="$(git rev-parse HEAD)"
	check_source
	[[ -z "$(git ls-remote --tags origin "refs/tags/$tag")" ]] || fail "Tag $tag already exists."
	local releases
	releases="$(gh release list --limit 100 --json tagName --jq '.[].tagName')"
	if grep -Fxq "$tag" <<<"$releases"; then
		fail "Release $tag exists (possibly a draft). Inspect it on GitHub before retrying."
	fi
	check_credentials
}

notarize() {
	local response status
	response="$staging/notarization.json"
	printf 'Signing with Developer ID and submitting to Apple…\n'
	codesign --force --sign "$identity" --options runtime --timestamp "$app"
	codesign --verify --deep --strict "$app"
	ARTPREP_APP="$app/Contents/MacOS/ArtPrep" bash scripts/check-python.sh
	ditto -c -k --keepParent --norsrc --noextattr "$app" "$staging/submission.zip"
	printf 'Notarization result will be saved in %s\n' "$response"
	if ! xcrun notarytool submit "$staging/submission.zip" --keychain-profile "$profile" \
		--wait --timeout 30m --output-format json >"$response"; then
		fail "Notarization did not finish successfully. See $response and docs/releasing.md."
	fi
	status="$(plutil -extract status raw -o - "$response")"
	[[ "$status" == Accepted ]] || fail "Apple returned '$status'. See $response for the submission ID."
	xcrun stapler staple "$app"
	xcrun stapler validate "$app"
}

package_release() {
	archive="Art-Prep-$tag-macOS-arm64.zip"
	ditto -c -k --keepParent --norsrc --noextattr "$app" "$staging/$archive"
	ditto -x -k "$staging/$archive" "$staging/extracted"
	local extracted="$staging/extracted/Art Prep.app"
	codesign --verify --deep --strict "$extracted"
	xcrun stapler validate "$extracted"
	spctl --assess --type execute --verbose=2 "$extracted"
	cp "$staging/$archive" "dist/$archive"
	(cd dist && shasum -a 256 "$archive" >"$archive.sha256")
}

publish() {
	git fetch origin main
	check_source
	cat >"$staging/release-notes.md" <<NOTES
Art Prep $version for Apple Silicon Macs running macOS 14 or later. Requires GIMP 3.

Download **$archive**, unzip it, and move **Art Prep.app** to Applications.

Signed with Developer ID, accepted by Apple's notarization service, and stapled for offline
verification. The extracted ZIP passed signature, ticket, and Gatekeeper checks before upload.

Source commit: $commit. The accompanying SHA-256 file verifies the download.
NOTES
	gh release create "$tag" "dist/$archive" "dist/$archive.sha256" \
		--target "$commit" --title "Art Prep $version" --notes-file "$staging/release-notes.md"
	printf 'Published %s. Local download: %s/dist/%s\n' "$tag" "$PWD" "$archive"
}

if [[ "${1:-}" == setup ]]; then
	[[ $# -le 2 ]] || fail "Usage: ./scripts/release.sh setup [EXISTING_KEYCHAIN_PROFILE]"
	shift
	setup "$@"
	exit 0
fi
if [[ "${1:-}" == --help || $# == 0 ]]; then
	printf 'One-time setup: ./scripts/release.sh setup [EXISTING_KEYCHAIN_PROFILE]\n'
	printf 'Build, notarize, and publish: ./scripts/release.sh 1.0.2\n'
	exit 0
fi
[[ $# == 1 ]] || fail "Usage: ./scripts/release.sh VERSION"
version="$1"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
	fail "Use a version such as 1.0.2 (without v)."
tag="v$version"
preflight
printf 'Running checks…\n'
bash scripts/check-swift.sh
bash scripts/check-python.sh
bash scripts/build.sh "$version"
IFS= read -r app <dist/app-path.txt
[[ -d "$app" ]] || fail "The staged app is missing; rerun the build."
staging="$(dirname "$app")"
notarize
package_release
publish
