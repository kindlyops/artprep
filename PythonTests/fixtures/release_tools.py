"""Controlled macOS/GitHub boundaries for release-script behavior tests."""

import json
import os
import sys
from pathlib import Path

name = Path(sys.argv[0]).name
args = sys.argv[1:]
failure = os.environ.get("FAIL_AT")
with Path("calls").open("a") as stream:
    stream.write(json.dumps([name, args]) + "\n")
if name == "git" and (args[0], failure) in [
    ("status", "status-error"),
    ("ls-remote", "remote-error"),
]:
    sys.exit(128)


def git():
    if args[0] == "status":
        print(" M file" if failure == "dirty" else "")
    elif args[:2] == ["branch", "--show-current"]:
        print("feature" if failure == "branch" else "main")
    elif args[0] == "rev-parse":
        changed = failure == "changed" and Path("built").exists()
        print(
            "def456"
            if changed or (failure == "outdated" and args[-1] == "origin/main")
            else "abc123"
        )
    elif args[0] == "ls-remote":
        print("abc123 refs/tags/v1.0.2" if failure == "tag" else "")
    elif args[0] == "tag":
        print("v2.0.0-beta.1\nv1.2.9\nv1.2.8\nv1.0.1")
    elif args[0] == "merge-base":
        sys.exit(1 if failure == "unmerged" else 0)
    elif args[0] == "remote":
        print("https://github.com/example/artprep.git")


def notary_submit():
    if failure == "submit":
        sys.exit(1)
    if failure == "malformed":
        print("unexpected response")
        return
    status = "Invalid" if failure == "invalid" else "Accepted"
    print(json.dumps({"id": "test-submission", "status": status, "message": "Done"}))


def xcrun():
    if args[:2] == ["notarytool", "history"]:
        if failure == "credentials":
            sys.exit(1)
        print(json.dumps({"history": [], "message": "Successfully received submission history."}))
    elif args[:2] == ["notarytool", "submit"]:
        notary_submit()
    elif args[:2] == ["stapler", "staple"]:
        if failure == "staple":
            sys.exit(1)
        (Path(args[-1]) / "ticket").touch()
    elif args[:2] == ["stapler", "validate"]:
        if failure == "ticket" or not (Path(args[-1]) / "ticket").exists():
            sys.exit(1)


def bash():
    if "build.sh" not in args[0]:
        sys.exit(1 if failure == "tests" else 0)
    if failure == "build":
        sys.exit(1)
    app = Path("staging/Art Prep.app").absolute()
    app.mkdir(parents=True)
    Path("dist").mkdir(exist_ok=True)
    Path("dist/app-path.txt").write_text(str(app) + "\n")
    Path("built").touch()


def ditto():
    if "-x" in args:
        app = Path(args[-1]) / "Art Prep.app"
        app.mkdir(parents=True)
        if failure != "archive":
            (app / "ticket").touch()
    else:
        content = "stapled" if (Path(args[-2]) / "ticket").exists() else "unstapled"
        Path(args[-1]).write_text(content)


def gh():
    if args[:2] == ["release", "list"]:
        print("")
    elif args[:2] == ["release", "create"]:
        if failure == "upload":
            sys.exit(1)
        Path("published").touch()
    elif args[:2] == ["repo", "view"]:
        print("example/artprep")
    elif args[0] == "api":
        if failure == "tag-race":
            sys.exit(1)


if name == "security":
    if failure != "identity":
        print("  1) " + "A" * 40 + ' "Developer ID Application: Example (1234567890)"')
elif name == "codesign":
    sys.exit(1 if failure == "sign" else 0)
elif name == "spctl":
    sys.exit(1 if failure == "gatekeeper" else 0)
else:
    {"git": git, "xcrun": xcrun, "bash": bash, "ditto": ditto, "gh": gh}[name]()
