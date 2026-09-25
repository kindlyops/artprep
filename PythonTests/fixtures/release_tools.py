"""Controlled macOS/GitHub boundaries for release-script behavior tests."""

import json
import os
import plistlib
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
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
if name == "xcrun" and args[0] == "notarytool" and failure == "default-keychain":
    keychain = str(Path.home() / "Library/Keychains/login.keychain-db")
    if "--keychain" not in args or args[args.index("--keychain") + 1] != keychain:
        print("Default Keychain lookup rejected credentials", file=sys.stderr)
        sys.exit(1)


def git():
    if args[0] == "status":
        print(" M file" if failure == "dirty" else "")
    elif args[:2] == ["branch", "--show-current"]:
        print("feature" if failure == "branch" else "main")
    elif args[0] == "rev-parse":
        rev_parse()
    elif args[0] == "ls-remote":
        print("abc123 refs/tags/v1.0.2" if failure == "tag" else "")
    elif args[0] == "tag":
        print("v2.0.0-beta.1\nv1.2.9\nv1.2.8\nv1.0.1")
    elif args[0] == "merge-base":
        sys.exit(1 if failure == "unmerged" else 0)
    elif args[0] == "remote":
        print("https://github.com/kindlyops/artprep.git")


def rev_parse():
    if failure == "resume-tag-mismatch" and "^{commit}" in args[-1]:
        print("different")
        return
    changed = failure == "changed" and Path("built").exists()
    print(
        "def456" if changed or (failure == "outdated" and args[-1] == "origin/main") else "abc123"
    )


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
    if "sparkle-tools.sh" in args[0]:
        print(Path("bin").absolute())
        return
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
        contents = app / "Contents"
        contents.mkdir()
        version = Path(args[-2]).name.removeprefix("Art-Prep-v").removesuffix("-macOS-arm64.zip")
        (contents / "Info.plist").write_bytes(
            plistlib.dumps(
                {
                    "CFBundleIdentifier": "foreign.app"
                    if failure == "draft-foreign-app"
                    else "local.artprep.mac",
                    "CFBundleVersion": version,
                    "ArtPrepSourceCommit": "different" if failure == "draft-source" else "abc123",
                    "SUPublicEDKey": ("B" if failure == "draft-key" else "A") * 43 + "=",
                }
            )
        )
        if failure != "archive":
            (app / "ticket").touch()
    else:
        content = "stapled" if (Path(args[-2]) / "ticket").exists() else "unstapled"
        Path(args[-1]).write_text(content)


def gh():
    if args[:2] == ["release", "list"]:
        print("v9.0.0" if failure == "newer-release" else "")
    elif args[:2] == ["release", "create"]:
        create_draft()
    elif args[:2] == ["release", "download"]:
        download_draft()
    elif args[:2] == ["release", "edit"]:
        promote_draft()
    elif args[:2] == ["release", "view"]:
        print("true" if Path("draft").exists() and failure != "already-published" else "false")
    elif args[:2] == ["repo", "view"]:
        print("kindlyops/artprep")
    elif args[0] == "api" and failure == "tag-race":
        sys.exit(1)


def promote_draft():
    if failure == "promote":
        sys.exit(1)
    Path("published").touch()


def create_draft():
    if failure == "upload":
        sys.exit(1)
    Path("draft").touch()
    assets = Path("draft-assets")
    assets.mkdir(exist_ok=True)
    for argument in args[3:]:
        candidate = Path(argument)
        if candidate.is_file():
            if failure == "upload-feed" and candidate.name == "appcast.xml":
                sys.exit(1)
            shutil.copy(candidate, assets / candidate.name)


def download_draft():
    if failure == "download-draft":
        sys.exit(1)
    destination = Path(args[args.index("--dir") + 1])
    for asset in Path("draft-assets").iterdir():
        if failure == "draft-missing" and asset.name == "appcast.xml":
            continue
        shutil.copy(asset, destination / asset.name)
    if failure == "draft-mismatch":
        next(destination.glob("*.zip")).write_text("corrupt")


def curl():
    if failure == "public-feed":
        sys.exit(1)
    if "-o" in args:
        shutil.copy("draft-assets/appcast.xml", args[args.index("-o") + 1])


def generate_appcast():
    directory = Path(args[-1])
    archive = next(directory.glob("*.zip"))
    version = archive.name.removeprefix("Art-Prep-v").removesuffix("-macOS-arm64.zip")
    ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", ns)
    root = ET.Element("rss", version="2.0")
    item = ET.SubElement(ET.SubElement(root, "channel"), "item")
    for field, value in {
        "version": version,
        "shortVersionString": version,
        "minimumSystemVersion": "14.0",
        "hardwareRequirements": "arm64",
    }.items():
        ET.SubElement(item, "{" + ns + "}" + field).text = value
    prefix = args[args.index("--download-url-prefix") + 1]
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": prefix + archive.name,
            "length": str(archive.stat().st_size),
            "{" + ns + "}edSignature": "A" * 86 + "==",
        },
    )
    ET.ElementTree(root).write(directory / "appcast.xml")


if name == "generate_keys":
    sys.exit(1) if failure == "update-key" else print("A" * 43 + "=")
elif name == "sign_update":
    is_feed = args[-1].endswith(".xml")
    sys.exit(1 if failure == "update-sign" or (failure == "update-feed" and is_feed) else 0)
elif name == "generate_appcast":
    generate_appcast()
elif name == "curl":
    curl()
elif name == "security":
    if failure != "identity":
        print("  1) " + "A" * 40 + ' "Developer ID Application: Example (1234567890)"')
elif name == "codesign":
    if "-R" in args:
        subprocess.run(
            ["/usr/bin/csreq", "-r", args[args.index("-R") + 1], "-b", os.devnull],
            check=True,
        )
    sys.exit(
        1
        if failure == "sign" or (failure == "nested-sign" and "Sparkle.framework" in args[-1])
        else 0
    )
elif name == "spctl":
    sys.exit(1 if failure == "gatekeeper" else 0)
else:
    {"git": git, "xcrun": xcrun, "bash": bash, "ditto": ditto, "gh": gh}[name]()
