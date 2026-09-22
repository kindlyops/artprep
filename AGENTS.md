# Art Prep development

- The user requests a Git commit at the end of every development turn so progress is visible.
  Commit coherent working checkpoints during longer turns too. Never claim uncommitted work is saved.
- Keep work on a feature branch. The user plans to add GitHub later; do not create a remote or push
  without a new instruction to do so.
- Keep photos, export files, app bundles, and local caches out of Git. Source photos stay untouched.
- Run relevant tests and local prek hooks before committing. Use local temporary storage for Swift
  builds: iCloud adds attributes that can invalidate signed app and XCTest bundles.
- The UI and CLI must use the same reviewed outline and local GIMP renderer. No image uploads.
- Read README.md for build/test commands and docs/verification.md for established checks.
