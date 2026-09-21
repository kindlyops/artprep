# Art Prep Implementation Plan

Goal: ship the approved native Mac app for reviewed artwork cutouts and local GIMP exports.
Spec: ../art-prep-design-memo.html in the containing outputs directory.
Architecture: Swift/AppKit canvas inside a native SwiftUI window; Codable project/job files;
bundled Python renderer invoked by the installed GIMP. No third-party runtime dependencies.

## Constraints and rulings

- User approved the design and requested a working local app. Execute inline through delivery.
- This is a new, isolated repository; there is no existing project branch to protect.
- JPEG/PNG input, reviewed outlines, warm #F3EFE7 background, adjustable margins.
- Preserve source files and photographed artwork; never silently overwrite outputs.
- Save editable XCF, full JPEG, and 2000-pixel-long-edge social JPEG in sRGB.
- Saved JSON projects and batch jobs support agent use as well as the interface.
- Validate rotated metadata, coordinate conversion, crossing outlines, file failures and retries.

## Task 1: Geometry and project data

Files: Sources/ArtPrepCore/{Geometry,Project,Layout}.swift; Tests/ArtPrepCoreTests.
Interfaces: Vertex(x:y:), ImageSize(width:height:), Outline.validate(_:in:),
CanvasLayout.make(points:margin:), SavedProject and RenderJob Codable types.
Write tests for crossing/out-of-bounds/degenerate outlines, both winding directions,
preview coordinate round trips, aspect ratio/margins, and malformed projects.
Run `swift test` and observe failure; implement the contract, then rerun to green.

## Task 2: Local renderer and process runner

Files: renderer/{job,render}.py, tests/test_job.py; Sources/ArtPrepCore/Renderer.swift.
Interfaces: JSON RenderJob -> unique output directory containing XCF/full/social files.
Test malformed jobs, source/output collisions, missing inputs, and output geometry.
Validate the real renderer on a synthetic image, including the actual output pixels,
layer mask, preserved source hash, repeated export, and an invalid-job failure.
GIMP work runs in a separate process with its own temporary profile and a captured log.

## Task 3: Native photo queue and outline editor

Files: Sources/ArtPrep/{App,Workspace,ContentView,CanvasView,ImageLoader}.swift.
Interfaces: project records carry source-image coordinates; canvas edits emit vertices.
Implement add/open/save, per-photo undo, closed outlines, point dragging/insertion/deletion,
zoom and scroll, original/cutout preview, color/margin controls and batch progress.
Validate image orientation and load failures using fixtures, then inspect the actual UI.

## Task 4: End-to-end verification and packaging

Files: scripts/{build,check}.sh, README.md, packaged Art Prep.app and source archive.
Build with compiler warnings treated as errors; run geometry, job, and integration tests.
Run Swift format checks, Ruff, ty, shellcheck, and shfmt; install and run local prek hooks.
Test real painting exports, save/reopen a project, verify sRGB/dimensions, and inspect the app.
Review changes, correct defects, and deliver the .app, source, and concise usage guide.

## Review focus

1. EXIF rotation must map clicks and masks to the same oriented source pixels.
2. Near-corner and crossing selections must not produce damaged artwork silently.
3. Spaces, Unicode, and quotes in filenames must not become executable command text.
4. A failed/cancelled export must preserve existing outputs and allow retry.
5. Reopening partial projects must retain points while reporting missing source photos.

## Progress

- Plan and spec reviewed; existing scripts verified; new repository initialized.
- Geometry and project tests demonstrated failures first; all 8 now pass.
- Swift builds use temporary local storage because iCloud adds signing-invalid bundle attributes.
- User requested a Git checkpoint at the end of each turn; commit working milestones too.
- Task 1 complete: 8 geometry/project tests passed; checkpoint 8658539.
- Image orientation and refinement tests demonstrated failure then passed (11 Swift tests total).
- Renderer validation demonstrated 9 failures then passed (10 Python tests total).
- Native queue/editor implemented; first real GIMP CLI export produced XCF and both JPEGs.
- Refinement is an explicit, undoable outline edit, so the displayed selection is the exported one.
