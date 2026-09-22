# Signing and releasing Art Prep

Run these commands in the repository folder on an Apple Silicon Mac. Once configured, each
release takes one command:

```sh
./scripts/release.sh 1.0.2
```

Choose the next unused version, such as `1.0.3` for the following release. Merge your changes
through a pull request first, switch to `main`, and pull. The command requires a clean checkout
matching `origin/main`. It publishes to the GitHub repository identified by this checkout's `origin`.
It does not push source changes to `main`.

## One-time setup

You need an Apple Developer Program membership, Xcode with its command-line tools selected, and
a **Developer ID Application** certificate with its private key in this Mac's unlocked Keychain.
An **Apple Development** certificate alone is insufficient. In Xcode, use Settings → Accounts →
your team → Manage Certificates to manage signing identities. Signing in to Xcode does not itself
configure `notarytool` credentials. See [Apple's Developer ID guide](https://developer.apple.com/developer-id/).

Check available identities without showing private keys:

```sh
security find-identity -v -p codesigning
```

The script automatically selects the sole valid Developer ID Application identity. If you have
several, select the certificate's 40-character SHA-1 from that list:

```sh
export ARTPREP_SIGNING_IDENTITY="YOUR_CERTIFICATE_SHA1"
```

Connect an **existing `notarytool` Keychain profile** with:

```sh
./scripts/release.sh setup YOUR_KEYCHAIN_PROFILE
```

This validates the profile against Apple and saves only its name to `.artprep-notary-profile`,
which Git ignores. It never reads the password into the script. This Mac already has a working
profile; it does not need another app-specific password.

On a new Mac without a notarization profile, run:

```sh
./scripts/release.sh setup
```

Apple's tool prompts interactively for your Apple account, Developer Team ID, and an
[app-specific password](https://support.apple.com/102654), then validates and stores them in
Keychain under `artprep-notary`. You can instead use an existing API-key-based notarytool profile.
Do not put a password or private key in a script, environment variable, Git, or a chat message.

Install the development tools and hash-locked Python test environment described in the
[README](../README.md#build-and-check), plus GitHub CLI and GIMP 3. ImageMagick is needed for
the real export tests. Sign in to GitHub CLI with `gh auth login`; your account needs repository
release permission. `./scripts/release.sh --help` shows the two commands.

## GitHub Actions runner

The `Release macOS app` workflow runs on pushes to `main`, including PR merges. It also has a
**Run workflow** button on GitHub for retries. It never runs unmerged PR code on the signing Mac.
The job requests the standard labels `self-hosted`, `macOS`, and `ARM64`. Enable this repository
for the runner's organization runner group if it is shared; that group must permit this public
repository. GitHub serializes releases with concurrency control; pending runs may be replaced
by newer merges while a release is running.

The runner must run as the macOS user who owns the signing key and notarization profile, with
that Keychain unlocked. Give `codesign` access to the key before running unattended jobs. The
runner needs Xcode, GIMP 3, ImageMagick, GitHub CLI, uv, Ruff, ty, shellcheck, and shfmt installed.
Keep its checkout outside iCloud. The workflow adds Homebrew and the usual user tool directories
to PATH, creates Python 3.13's test environment from the hash-locked requirements, and runs checks.
Keep the GitHub runner software current for the pinned checkout action.

In **Settings → Secrets and variables → Actions → Variables**, set:

| Variable | Value |
| --- | --- |
| `ARTPREP_NOTARY_PROFILE` | The existing notarytool profile name on the runner |
| `ARTPREP_SIGNING_IDENTITY` | Optional certificate SHA-1, only when several Developer IDs exist |

These values are identifiers, not credentials. The certificate/private key and Apple credential
remain in the runner's Keychain. Publishing uses the job's short-lived `GITHUB_TOKEN` with
`contents: write`; no GitHub personal token is needed or persisted by checkout.

The workflow invokes `./scripts/release.sh auto`, incrementing the highest stable `vMAJOR.MINOR.PATCH`
tag's patch number (or starting at `1.0.0` when no stable tags exist). Prerelease tags are ignored.
The release is tied to the triggering commit, even if another PR merges while Apple processes it;
the script verifies that the commit remains on `main`. A manually rerun successful workflow
creates another patch release, so use the retry button for failed runs only.

## What the command does

1. Checks the certificate, GitHub login, Apple credential, clean `main`, and unused release tag.
2. Runs Swift and Python checks, then builds in local temporary storage outside iCloud.
3. Signs the app with Developer ID, Hardened Runtime, and a secure timestamp. Runs the real
   GIMP export tests against that signed executable.
4. Uploads the app ZIP to Apple's notary service and requires an explicit `Accepted` result.
5. Staples Apple's ticket to the app, makes a fresh ZIP, extracts it, and verifies the signature,
   stapled ticket, and Gatekeeper assessment on that extracted copy.
6. Rechecks the source commit, atomically creates a new GitHub tag at that exact commit, then
   creates a release requiring that tag,
   uploading `Art-Prep-vVERSION-macOS-arm64.zip` and its `.sha256` checksum.

The build version comes from the release command; development builds default to the nearest
version tag. Both use `scripts/build.sh`, so packaging and the icon stay consistent. There is no
fallback to publishing an unsigned or rejected app. Generated files live in `dist/`; the staging
path and Apple response path are printed for diagnosis. Build caches and staging stay outside
iCloud because file-provider attributes can invalidate signatures.

After downloading, check the checksum with both release assets in the same folder:

```sh
shasum -a 256 -c Art-Prep-v1.0.2-macOS-arm64.zip.sha256
```

## If a release stops

The command exits without continuing to later steps. Fix the reported issue and rerun the same
command if the version has not been published. The script never replaces an existing release.

- **Keychain or certificate error:** unlock your login Keychain, check certificate validity and
  its private key, or rerun `setup` with the correct profile. Keychain may ask permission for
  `codesign` to use your signing key.
- **“A timestamp was expected but was not found”:** Apple signing requires a connection to
  `timestamp.apple.com`. If running inside an agent's restricted environment, try the same
  release command in Terminal. If it also fails there, check the network or retry later.
  Do not disable timestamps to make the release proceed.
- **Apple rejects the app:** the printed `notarization.json` contains the submission ID and
  status. Retrieve Apple's detailed report with the following command, using your saved profile:

  ```sh
  xcrun notarytool log SUBMISSION_ID --keychain-profile YOUR_PROFILE notary-log.json
  ```

- **Apple is still processing after 30 minutes, or your connection drops:** Apple may continue
  processing after the command stops. Check the ID in `notarization.json`, or use
  `xcrun notarytool history --keychain-profile YOUR_PROFILE` if no ID was returned. Inspect with
  `xcrun notarytool info SUBMISSION_ID --keychain-profile YOUR_PROFILE`. Rerunning the release
  command builds and submits again; it does not automatically resume an earlier submission.
- **GitHub upload fails:** inspect `gh release view vVERSION` and the repository's releases page.
  GitHub may have created a draft or tag before the connection failed. The script refuses to
  overwrite it. If nothing exists, rerun. If a draft exists, finish that draft using the verified
  files in `dist/`; if only a tag exists, create its release using those same verified files.
  Do not delete or move a published tag to force a retry. An automatic retry chooses a new patch
  after an existing tag, including one left by a failed upload.
- **Source changed during the run:** commit and merge the intended changes, update local `main`,
  and rerun. A source change is never silently included under the previous commit's tag.

## What notarization means

Developer ID identifies the publisher. Notarization is Apple's automated scan for malicious
content and signing problems. The stapled ticket lets Gatekeeper verify notarization without
contacting Apple. It addresses the unidentified-developer/unverified-app distribution problem;
it is not a guarantee against every malware warning. macOS may still show its normal first-open
download confirmation. GIMP is separately installed and has its own distribution checks.

Apple documents the requirements in
[Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
and the ZIP → notarize → staple app → new ZIP sequence in
[Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
