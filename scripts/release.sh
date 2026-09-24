#!/bin/bash
set -euo pipefail
set -E
cd "$(dirname "$0")/.."
keychain="$HOME/Library/Keychains/login.keychain-db"

fail() {
	printf 'Release stopped: %s\n' "$*" >&2
	exit 1
}

trap 'printf "Release stopped at line %s. Fix the error above before retrying.\n" "$LINENO" >&2' ERR

check_credentials() {
	xcrun notarytool history --keychain-profile "$profile" --keychain "$keychain" \
		--output-format json |
		plutil -extract history xml1 -o /dev/null - ||
		fail "Cannot use Keychain profile '$profile'. Run ./scripts/release.sh setup PROFILE."
}

setup() {
	profile="${1:-artprep-notary}"
	[[ -n "$profile" && "$profile" != *$'\n'* ]] || fail "Use a nonempty profile name."
	if [[ $# == 0 ]]; then
		printf 'Apple will prompt securely. Use an app-specific password, not your login password.\n'
		xcrun notarytool store-credentials "$profile" --keychain "$keychain"
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
		fail "Need one Developer ID Application identity; set ARTPREP_SIGNING_IDENTITY to select a SHA-1."
	grep -Fxq "$identity" <<<"$identities" || fail "Selected Developer ID identity is unavailable."
}

check_source() {
	local status head branch upstream
	status="$(git status --porcelain)"
	head="$(git rev-parse HEAD)"
	[[ -z "$status" ]] || fail "Commit your changes before releasing."
	[[ "$head" == "$commit" ]] || fail "Source changed during the release. Start again."
	if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
		[[ "${GITHUB_REPOSITORY:-}" == kindlyops/artprep-build &&
			"${GITHUB_REF:-}" == refs/heads/main &&
			"${GITHUB_EVENT_NAME:-}" == workflow_dispatch &&
			"${ARTPREP_SOURCE_COMMIT:-}" == "$commit" ]] ||
			fail "CI releases require the private main builder and its validated source commit."
		git merge-base --is-ancestor "$commit" origin/main || fail "Commit is not merged to main."
	else
		branch="$(git branch --show-current)"
		upstream="$(git rev-parse origin/main)"
		[[ "$branch" == main ]] || fail "Switch to main after merging your PR."
		[[ "$commit" == "$upstream" ]] || fail "Update main from origin first."
	fi
}

choose_version() {
	local tags candidate major minor patch
	if [[ "$version" == auto ]]; then
		tags="$(git tag --list 'v[0-9]*' --sort=-version:refname)"
		version=1.0.0
		while IFS= read -r candidate; do
			if [[ "$candidate" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
				IFS=. read -r major minor patch <<<"${candidate#v}"
				version="$major.$minor.$((patch + 1))"
				break
			fi
		done <<<"$tags"
	fi
	tag="v$version"
	printf 'Preparing %s…\n' "$tag"
}

preflight() {
	[[ "$(uname -m)" == arm64 ]] || fail "Build this arm64 release on an Apple Silicon Mac."
	profile="${ARTPREP_NOTARY_PROFILE:-}"
	if [[ -z "$profile" ]]; then
		[[ -f .artprep-notary-profile ]] || fail "Run ./scripts/release.sh setup PROFILE once first."
		IFS= read -r profile <.artprep-notary-profile
	fi
	select_identity
	gh auth status
	git fetch origin main --tags
	commit="$(git rev-parse HEAD)"
	check_source
	choose_version
	local releases remote_tag remote_url
	remote_tag="$(git ls-remote --tags origin "refs/tags/$tag")"
	[[ -z "$remote_tag" ]] || fail "Tag $tag already exists."
	remote_url="$(git remote get-url origin)"
	repository="$(gh repo view "$remote_url" --json nameWithOwner --jq .nameWithOwner)"
	releases="$(gh release list --repo "$repository" --limit 100 --json tagName --jq '.[].tagName')"
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
		--keychain "$keychain" --wait --timeout 30m --output-format json >"$response"; then
		fail "Notarization did not finish successfully. See $response and docs/releasing.md."
	fi
	status="$(plutil -extract status raw -o - "$response")"
	[[ "$status" == Accepted ]] ||
		fail "Apple returned '$status'. See $response for the submission ID."
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
	gh api --method POST "repos/$repository/git/refs" \
		-f "ref=refs/tags/$tag" -f "sha=$commit" >/dev/null
	gh release create "$tag" "dist/$archive" "dist/$archive.sha256" --repo "$repository" \
		--verify-tag --target "$commit" --title "Art Prep $version" \
		--notes-file "$staging/release-notes.md"
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
	printf 'Choose the next patch automatically: ./scripts/release.sh auto\n'
	exit 0
fi
[[ $# == 1 ]] || fail "Usage: ./scripts/release.sh VERSION"
version="$1"
[[ "$version" == auto || "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
	fail "Use a version such as 1.0.2 (without v)."
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
