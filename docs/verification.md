# Verification

The release was built with warnings treated as errors and checked on the user's Apple Silicon Mac
with GIMP 3.2.6. No originals were edited by the app.

- 13 Swift tests: geometry, malformed/partial projects, EXIF orientation, asymmetric edge sampling,
  and mutation guards during operations. Core tests: 12; app state tests: 1.
- 45 Python tests when integration is enabled: request validation, 32 release workflow cases,
  and three real GIMP integration cases. Without integration enabled, 42 pass and three skip.
- Integration checks: grayscale and RGB, warm background pixels, artwork pixels, source hash,
  ICC/sRGB output, social size, new output folders on repeat runs, malformed-project failure.
- Real painting export inspected: full JPEG 4093×5116, social JPEG 1600×2000. The reopened XCF has
  three layers, an editable artwork mask, and a hidden original reference.
- Native interface exercised: project opening, correct photo orientation, cutout view, outline reset,
  undo, point placement, outline closure, saving three outlines, and cancelling a window close.
- Ruff, ty (request validator), Swift formatting, shellcheck, shfmt, and local prek hooks passed.
- One independent code review completed; all three consequential findings received fixes.

The app is a personal, locally signed build. It has not been tested on an Intel Mac or every macOS
version. The minimum deployment target is macOS 14; the supplied executable is arm64. Edge
refinement remains a reviewed assist, particularly where background objects touch the wood.

## Release automation

The release tests replace macOS and GitHub command boundaries, exercising successful publication
and failure gates for credentials, signing, Apple rejection, malformed responses, stapling,
Gatekeeper, ZIP verification, changed source, and upload failures. A mutation check removing the
Apple `Accepted` gate made the rejection test fail. These tests do not simulate Apple's actual
security assessment.

Additional cases cover failing Git commands, an existing tag appearing during notarization,
automatic patch selection, and Actions building a merged commit while `main` advances. The
workflow passes actionlint and zizmor, and checkout is pinned to a commit with credentials not
persisted. The first runner execution still requires a macOS ARM64 runner enabled for this repo.

A real Developer ID build with Hardened Runtime passed all three GIMP integration tests. On this
agent's execution environment, adding the required secure timestamp failed with “A timestamp was
expected but was not found,” although Apple's timestamp endpoint responded to a direct request.
The saved notarization Keychain profile authenticated successfully. No notarized release was
published during these checks; the script retains the timestamp and notarization requirements.
