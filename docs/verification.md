# Verification

The release was built with warnings treated as errors and checked on the user's Apple Silicon Mac
with GIMP 3.2.6. No originals were edited by the app.

- 13 Swift tests: geometry, malformed/partial projects, EXIF orientation, asymmetric edge sampling,
  and mutation guards during operations. Core tests: 12; app state tests: 1.
- 13 Python tests when integration is enabled: request validation and three real GIMP integration
  cases. Without integration enabled, ten pass and three are explicitly skipped.
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
