# Art Prep

![Art Prep showing a framed chickadee painting on off-white](docs/images/art-prep-preview.jpg)

A local Mac app for preparing photographs of paintings with wooden or irregular frames.
You mark the artwork boundary; Art Prep uses your installed GIMP to replace the surrounding
background and export editable and social-ready copies. No photo uploads or cloud services.

## Use the app

Requires macOS 14 or later and **GIMP 3** in `/Applications` or `~/Applications`.
Download the Apple Silicon build from [GitHub Releases](https://github.com/kindlyops/artprep/releases/latest).
Unzip the downloaded archive, move **Art Prep.app** to
Applications, and open it. This personal build is locally signed, not Apple-notarized.
Keep the app outside an iCloud-synced Documents folder: iCloud can add bundle attributes
that invalidate local code-signing verification.

1. **Add Photos** and select JPEG or PNG files. iCloud photos must be downloaded locally.
2. Click around the **outside of all the wood**, in order. Use four corners for a rectangle
   and extra points for an irregular frame. Double-click the last point or click **Close Outline**.
3. Drag points to adjust them. Click an existing edge to insert a point; select a point and
   press Delete to remove it. **Undo** restores the previous outline edit. Use Zoom and scrollbars
   for close work; **Fit** restores the overview.
4. Optionally choose **Refine Nearby Edges**. This searches within eight original-image pixels,
   adds points along edges, and keeps your corners. Review the visible result and Undo if an
   object or shadow pulls the edge the wrong way. It is a small adjustment, not automatic selection.
5. Check **Cutout Preview**, background color, and margins. The default is warm off-white
   `#F3EFE7`. Portrait canvases are 4:5; landscape canvases are 3:2, chosen from the outline bounds.
6. Choose an output folder and **Export Ready Photos**. Each closed outline is exported in order.
   Failed photos remain in the queue for another attempt. **Stop after this photo** finishes the
   current photo, then stops the batch.

Each export creates a new `photo-name-art-prep` folder (numbered on subsequent exports):

- `artwork.xcf`: editable artwork mask, background, and hidden cropped original reference.
- `full.jpg`: full-resolution composition with an embedded sRGB profile.
- `social.jpg`: sRGB JPEG, 2000 pixels on the long edge (small originals are upscaled).
- `outline.artprep`: the outline and settings needed to repeat this export.

Source photos are never overwritten. Camera metadata is omitted from JPEG exports. Exposure,
paint texture, perspective, and photographed color are not retouched. The preview shows the
reviewed polygon; GIMP adds a subtle 1.2-pixel feather to the final mask.

**Save Project** saves the whole queue and unfinished outlines as a readable `.artprep` JSON file.
Use **Open Project** to resume. Projects reference the original photo paths; keep those photos
in place. Moving or renaming a source requires adding it again. The hidden XCF reference is
cropped to the output canvas, so retain the original photo as your master.

## Git history

The source and progress history are hosted at [kindlyops/artprep](https://github.com/kindlyops/artprep).
Released source is on `main`; development changes use feature branches and pull requests.
Run `git log --oneline` to follow the checkpoints. Release tags identify the corresponding source.

```sh
git clone https://github.com/kindlyops/artprep.git
cd artprep
```

Only source, tests, build scripts, and documentation are tracked. Photos, generated exports,
app bundles, temporary caches, and the development virtual environment are excluded.

## Build and check

The app uses system SwiftUI/AppKit, CoreGraphics, and ImageIO. It has no third-party Swift
packages. Python renderer code runs inside GIMP's own interpreter; users need no Python install.
Build with a Swift 6 toolchain and macOS SDK:

```sh
bash scripts/build.sh
```

The script builds on local temporary storage, signs the app, and writes the app and ZIP to `dist/`.
`ARTPREP_BUILD_ROOT` may override the temporary build folder. Build for the current machine's
architecture. Distributing to other people with normal Gatekeeper trust requires your own
Developer ID signing and notarization.

Development checks use Swift's test runner, swift-format, uv, Ruff, ty, pytest, shellcheck,
shfmt, and prek. Python 3.13 test dependencies are pinned with hashes:

```sh
uv venv --python 3.13
uv pip install --require-hashes -r requirements-dev.txt
prek install
prek auto-update --cooldown-days 7
prek run --all-files
```

For real GIMP integration tests, also install ImageMagick, build the app, and run:

```sh
ARTPREP_APP="$PWD/dist/Art Prep.app/Contents/MacOS/ArtPrep" .venv/bin/pytest -q
```

These tests verify output pixels, sRGB profiles, dimensions, Unicode/quoted paths, original-file
hashes, repeated exports, grayscale inputs, and malformed projects. Swift tests cover outline
geometry, margins, saved-project validation, EXIF orientation, edge refinement, and operation guards.
`ty` checks the pure Python request validator; GIMP's dynamically supplied GI API is verified by
the integration tests. Integration tests are skipped when `ARTPREP_APP` is not set.

## Command-line use

Agents and scripts can export the same saved projects without driving the interface:

```sh
"/Applications/Art Prep.app/Contents/MacOS/ArtPrep" \
  --render "/path/to/Paintings.artprep" --output "/path/to/existing/export-folder"
```

Only closed outlines are exported. The command prints each new export folder and returns a
nonzero exit code on failure. GUI batches continue past failed photos; the CLI stops at the first
failure. When running an unbundled development executable, set `ARTPREP_RENDERER` to this
repository's `renderer` folder. Paths are passed as data, never interpolated into shell commands.
