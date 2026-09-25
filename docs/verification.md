# Verification

## Self-update branch — 2026-09-25

- 19 Swift tests passed: outline geometry, project validation, image orientation, edge refinement,
  operation guards, disabled updater behavior, and deferred-install lifecycle.
- 90 Python tests passed with real GIMP integration enabled. This includes release signing and
  publication gates, draft recovery, strict feed metadata, dependency download validation, and
  original renderer behavior. Ruff, ty, shellcheck and shfmt passed without warnings.
- Removing archive URL validation made the metadata tests fail. Removing draft publication made
  the release test fail. These mutation checks used disposable copies of the code.
- The built app embeds Sparkle 2.10.0; the upstream archive's SHA-256 matches the committed pin.
  Dependency tests reject corrupt and interrupted downloads and repair modified framework/tools.
- Native app control launched the unsigned build and verified its explanatory disabled update
  menu. A generated disposable project exercised the unsaved-outline prompt: Cancel retained the
  running editing session. No user photo was changed during this check.
- Real GIMP tests passed against the new bundled executable, checking rendered pixels, dimensions,
  sRGB profiles, Unicode/quoted paths, original-file hashes, repeated exports and malformed input.

The dedicated update key was created in the user's Keychain on 2026-09-25. Its public key
was read back, matched to the user-provided value, and embedded in a successful local build.
After the user ran setup-updates in Terminal, the production-key signing preflight passed
from the agent environment. The private key has not been read or exported by the agent.
Two isolated test builds, versions 1.0.2 and 1.0.3, were signed and notarized from Terminal.
Apple accepted submissions `4e6247d8-0cee-49c6-aa9e-c87df90d1425` and
`030f4afd-fc8d-443f-8771-43de95ea2bc0`. The user's Terminal output confirms staple validation
and Gatekeeper acceptance for both; the agent independently verified both code signatures and
read the accepted submission results. The signed app launches with update controls enabled;
an offline update check displays a recoverable error.

Production-format feed metadata and both Ed25519 signatures passed verification with the
real Sparkle tools. Two native update tests installed 1.0.3 over disposable 1.0.2 copies:

- Offline checks show a recoverable error. A modified signed feed is rejected explicitly.
- Canceling a download preserves the editing session.
- Canceling the unsaved-outline relaunch prompt preserves the project. Checking again returns
  to Install and Relaunch; retrying successfully installs and relaunches 1.0.3.
- The relaunched app reports that 1.0.3 is current. Its bundle contents match the notarized
  candidate byte for byte, and its signature passes the expected Developer ID team requirement.
- All three real GIMP integration tests pass against the installed executable after updating.
- In a second copy, installation was requested during a real GIMP export. The export produced
  its XCF, full-size JPEG, social JPEG, and saved outline, and the copy updated to 1.0.3.

The real signature check found a missing `=` prefix on the release script's inline codesign
requirement. The release boundary test now compiles requirements with Apple's actual `csreq`
parser: it failed before the fix and passed afterward. All 58 release tests pass. The corrected
requirement accepts the installed signed bundle; a wrong-team requirement rejects it.

These tests used loopback feeds configured only in disposable bundles before signing. Source
photos and the user's installed app were untouched. No test version was tagged or published.

Independent review found missing Sparkle redistribution notices. A new regression test failed
before the fix and passed afterward; all four downloader tests passed. The rebuilt ZIP contains
the exact 6,154-byte upstream combined license file. No other confirmed code defects were found.
Signed installation and relaunch are now verified. The public release still needs the merged
source workflow to build and publish its production-feed bundle.

## Existing public release

Art Prep v1.0.2 was signed with Kindly Ops Developer ID, notarized by Apple, and stapled on
2026-09-24. The published ZIP was downloaded and its SHA-256 verified. The extracted app passed
signature, stapled-ticket and Gatekeeper checks. It targets Apple Silicon and macOS 14 or later.
Intel distribution and every supported macOS version have not been tested.

The updater is new work after v1.0.2. Users of earlier versions need one manual download of the
first updater-enabled release. GIMP is separately installed and updated.
