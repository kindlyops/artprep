"""Verify the download boundary without fetching third-party binaries in tests."""

import hashlib
import os
import shutil
import subprocess
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def download_job(tmp_path):
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    script = ROOT / "scripts/sparkle-tools.sh"
    if script.exists():
        shutil.copy(script, scripts)
    archive = tmp_path / "fixture.zip"
    with zipfile.ZipFile(archive, "w") as zipped:
        zipped.writestr("Sparkle.xcframework/framework", "reviewed framework")
        zipped.writestr("bin/sign_update", "reviewed tool")
        zipped.writestr("LICENSE", "Sparkle and bundled dependency notices")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (scripts / "sparkle-version.env").write_text(f"version=2.10.0\nsha256={digest}\n")
    binary = tmp_path / "bin"
    binary.mkdir()
    curl = binary / "curl"
    curl.write_text(
        "#!/bin/bash\nset -euo pipefail\n"
        'while [[ "$1" != -o ]]; do shift; done\n'
        'cp "$FIXTURE_ARCHIVE" "$2"\n'
        '[[ "${FAIL_DOWNLOAD:-}" != true ]]\n'
    )
    curl.chmod(0o755)
    return tmp_path


def run_download(job, **settings):
    env = dict(os.environ)
    env.update(
        PATH=f"{job / 'bin'}:{env['PATH']}",
        FIXTURE_ARCHIVE=str(job / "fixture.zip"),
        ARTPREP_SPARKLE_ROOT=str(job / "cache"),
        **settings,
    )
    return subprocess.run(
        ["/bin/bash", "scripts/sparkle-tools.sh"],
        cwd=job,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def test_verified_archive_repairs_changed_framework_and_tool(download_job):
    result = run_download(download_job)
    assert result.returncode == 0, result.stderr
    framework = download_job / "Vendor/Sparkle/Sparkle.xcframework/framework"
    tool = Path(result.stdout.strip()) / "sign_update"
    framework.write_text("tampered")
    tool.write_text("tampered")
    (download_job / "fixture.zip").unlink()
    result = run_download(download_job)
    assert result.returncode == 0, result.stderr
    assert framework.read_text() == "reviewed framework"
    assert tool.read_text() == "reviewed tool"


def test_corrupt_download_never_installs_framework(download_job):
    (download_job / "fixture.zip").write_bytes(b"corrupt")
    result = run_download(download_job)
    assert result.returncode != 0
    assert "checksum" in result.stderr.lower()
    assert not (download_job / "Vendor").exists()


def test_interrupted_download_does_not_become_cache(download_job):
    result = run_download(download_job, FAIL_DOWNLOAD="true")
    assert result.returncode != 0
    assert not (download_job / "cache/2.10.0/download.zip").exists()
    result = run_download(download_job)
    assert result.returncode == 0, result.stderr


def test_preserves_redistribution_notices(download_job):
    result = run_download(download_job)
    assert result.returncode == 0, result.stderr
    notices = Path(result.stdout.strip()).parent / "LICENSE"
    assert notices.read_text() == "Sparkle and bundled dependency notices"
