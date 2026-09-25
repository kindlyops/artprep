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
Private-key access for signing and a real signed install/relaunch test remain pending; the first
signing probe timed out. The private key has not been read or exported by the agent.

Independent review found missing Sparkle redistribution notices. A new regression test failed
before the fix and passed afterward; all four downloader tests passed. The rebuilt ZIP contains
the exact 6,154-byte upstream combined license file. No other confirmed code defects were found.
These checks do not establish a completed signed update installation; publication remains blocked
on signing access and signed integration evidence.

## Existing public release

Art Prep v1.0.2 was signed with Kindly Ops Developer ID, notarized by Apple, and stapled on
2026-09-24. The published ZIP was downloaded and its SHA-256 verified. The extracted app passed
signature, stapled-ticket and Gatekeeper checks. It targets Apple Silicon and macOS 14 or later.
Intel distribution and every supported macOS version have not been tested.

The updater is new work after v1.0.2. Users of earlier versions need one manual download of the
first updater-enabled release. GIMP is separately installed and updated.
