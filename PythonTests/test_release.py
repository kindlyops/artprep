"""Exercise the release script with OS and network command boundaries replaced."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
FAKE_TOOLS = Path(__file__).parent / "fixtures" / "release_tools.py"


@pytest.fixture
def checkout(tmp_path):
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    for source in ROOT.glob("scripts/release*.sh"):
        shutil.copy(source, scripts)
    (tmp_path / ".artprep-notary-profile").write_text("existing-profile\n")
    binary = tmp_path / "bin"
    binary.mkdir()
    tool = binary / "tool"
    tool.write_text(f"#!{sys.executable}\n" + FAKE_TOOLS.read_text())
    tool.chmod(0o755)
    for name in ["git", "gh", "security", "xcrun", "codesign", "ditto", "spctl", "bash"]:
        (binary / name).symlink_to(tool)
    return tmp_path


def run_release(checkout, *args, failure="", ci=False):
    env = dict(os.environ)
    env.update(PATH=f"{checkout / 'bin'}:{env['PATH']}", FAIL_AT=failure)
    env.pop("ARTPREP_SIGNING_IDENTITY", None)
    for key in [
        "GITHUB_ACTIONS",
        "GITHUB_REF",
        "GITHUB_SHA",
        "GITHUB_REPOSITORY",
        "GITHUB_EVENT_NAME",
        "ARTPREP_NOTARY_PROFILE",
        "ARTPREP_SOURCE_COMMIT",
    ]:
        env.pop(key, None)
    if ci:
        env.update(
            GITHUB_ACTIONS="true",
            GITHUB_REF="refs/heads/main",
            GITHUB_SHA="builder456",
            GITHUB_REPOSITORY="kindlyops/artprep-build",
            GITHUB_EVENT_NAME="workflow_dispatch",
            ARTPREP_SOURCE_COMMIT="abc123",
        )
        if failure == "pr-event":
            env["GITHUB_EVENT_NAME"] = "pull_request_target"
        if failure == "public-builder":
            env["GITHUB_REPOSITORY"] = "kindlyops/artprep"
        if failure == "source-mismatch":
            env["ARTPREP_SOURCE_COMMIT"] = "different-source"
        env["ARTPREP_NOTARY_PROFILE"] = "runner-profile"
    return subprocess.run(
        ["/bin/bash", "scripts/release.sh", *args],
        cwd=checkout,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def test_release_publishes_only_verified_stapled_archive(checkout):
    result = run_release(checkout, "1.0.2")
    assert result.returncode == 0, result.stdout + result.stderr
    assert (checkout / "published").exists()
    calls = [json.loads(line) for line in (checkout / "calls").read_text().splitlines()]
    signing = next(args for name, args in calls if name == "codesign" and "--sign" in args)
    assert "--timestamp" in signing
    assert signing[signing.index("--options") + 1] == "runtime"
    notary = next(args for name, args in calls if name == "xcrun" and "submit" in args)
    assert notary[notary.index("--keychain-profile") + 1] == "existing-profile"
    published = next(args for name, args in calls if name == "gh" and "create" in args)
    assert published[published.index("--target") + 1] == "abc123"
    assert (checkout / "dist/Art-Prep-v1.0.2-macOS-arm64.zip").read_text() == "stapled"


@pytest.mark.parametrize(
    "failure",
    [
        "dirty",
        "branch",
        "outdated",
        "tag",
        "credentials",
        "identity",
        "tests",
        "build",
        "sign",
        "submit",
        "invalid",
        "malformed",
        "staple",
        "ticket",
        "gatekeeper",
        "archive",
        "changed",
        "upload",
        "status-error",
        "remote-error",
        "tag-race",
    ],
)
def test_release_failure_never_publishes(checkout, failure):
    result = run_release(checkout, "1.0.2", failure=failure)
    assert result.returncode != 0, result.stdout + result.stderr
    assert not (checkout / "published").exists()


@pytest.mark.parametrize("version", ["", "v1.0.2", "1.2", "1.2.3;touch bad", "01.2.3"])
def test_rejects_invalid_version_before_external_work(checkout, version):
    result = run_release(checkout, version)
    assert result.returncode != 0
    assert not (checkout / "calls").exists()


def test_setup_reuses_existing_profile_without_reading_password(checkout):
    result = run_release(checkout, "setup", "saved-profile")
    assert result.returncode == 0, result.stdout + result.stderr
    assert (checkout / ".artprep-notary-profile").read_text().strip() == "saved-profile"
    assert "store-credentials" not in (checkout / "calls").read_text()


def test_failed_setup_keeps_previous_profile(checkout):
    result = run_release(checkout, "setup", "bad-profile", failure="credentials")
    assert result.returncode != 0
    assert (checkout / ".artprep-notary-profile").read_text().strip() == "existing-profile"


@pytest.mark.parametrize("args", [("setup",), ("setup", "saved-profile"), ("1.0.2",)])
def test_uses_login_keychain_when_default_lookup_rejects_credentials(checkout, args):
    result = run_release(checkout, *args, failure="default-keychain")
    assert result.returncode == 0, result.stdout + result.stderr
    if args[0] == "setup":
        expected = "saved-profile" if len(args) > 1 else "artprep-notary"
        assert (checkout / ".artprep-notary-profile").read_text().strip() == expected
    else:
        assert (checkout / "published").exists()


def test_automatic_release_increments_highest_stable_patch(checkout):
    result = run_release(checkout, "auto", ci=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (checkout / "dist/Art-Prep-v1.2.10-macOS-arm64.zip").exists()
    assert (checkout / "published").exists()


def test_ci_release_allows_later_merged_main_commit(checkout):
    result = run_release(checkout, "1.0.2", ci=True, failure="outdated")
    assert result.returncode == 0, result.stdout + result.stderr


def test_ci_rejects_commit_not_on_main(checkout):
    result = run_release(checkout, "1.0.2", ci=True, failure="unmerged")
    assert result.returncode != 0
    assert not (checkout / "published").exists()


@pytest.mark.parametrize("failure", ["pr-event", "public-builder", "source-mismatch"])
def test_ci_requires_private_main_builder_and_pinned_source(checkout, failure):
    result = run_release(checkout, "1.0.2", ci=True, failure=failure)
    assert result.returncode != 0
    assert not (checkout / "published").exists()
