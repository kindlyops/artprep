"""Run against a built app and installed GIMP: ARTPREP_APP=/path/to/ArtPrep pytest."""

import hashlib
import json
import os
import subprocess
import uuid
from pathlib import Path

import pytest

APP = os.environ.get("ARTPREP_APP")
pytestmark = pytest.mark.skipif(
    not APP, reason="Set ARTPREP_APP to test the installed GIMP boundary"
)


def command(*arguments):
    """Run a local test utility, surfacing captured diagnostics on failure."""
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=180)


def project_for(source, path):
    """Write a reviewed, closed outline around the test artwork."""
    photo = {
        "id": str(uuid.uuid4()),
        "source": str(source),
        "size": {"width": 300, "height": 200},
        "points": [{"x": x, "y": y} for x, y in [(60, 40), (240, 40), (240, 160), (60, 160)]],
        "closed": True,
    }
    path.write_text(
        json.dumps(
            {
                "version": 1,
                "photos": [photo],
                "settings": {"background": "#F3EFE7", "margin": 0.08},
            }
        )
    )


@pytest.mark.parametrize("grayscale", [False, True])
def test_export_preserves_source_color_and_repeated_outputs(tmp_path, grayscale):
    source = tmp_path / "Artist's painting 日本.png"
    args = [
        "magick",
        "-size",
        "300x200",
        "xc:blue",
        "-fill",
        "#c84333",
        "-draw",
        "rectangle 60,40 239,159",
    ]
    if grayscale:
        args += ["-colorspace", "Gray"]
    command(*args, str(source))
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    project = tmp_path / "test.artprep"
    project_for(source, project)
    folder = tmp_path / "exports"
    folder.mkdir()
    result = command(APP, "--render", str(project), "--output", str(folder))
    output = Path(result.stdout.strip())
    assert (output / "artwork.xcf").stat().st_size > 0
    assert (output / "outline.artprep").is_file()
    details = command(
        "magick",
        "identify",
        "-format",
        "%wx%h %[profiles] %[colorspace]",
        str(output / "social.jpg"),
    ).stdout
    assert details == "2000x1333 icc sRGB"
    pixels = subprocess.run(
        ["magick", str(output / "full.jpg"), "-depth", "8", "rgb:-"],
        check=True,
        capture_output=True,
        timeout=30,
    ).stdout
    assert all(abs(a - b) <= 2 for a, b in zip(pixels[:3], (243, 239, 231), strict=True))
    if not grayscale:
        center = (70 * 215 + 100) * 3
        assert all(
            abs(a - b) <= 2 for a, b in zip(pixels[center : center + 3], (200, 67, 51), strict=True)
        )
    assert hashlib.sha256(source.read_bytes()).hexdigest() == before
    if not grayscale:
        second = command(APP, "--render", str(project), "--output", str(folder))
        assert Path(second.stdout.strip()) != output
        assert (output / "full.jpg").is_file()


def test_malformed_project_fails_without_outputs(tmp_path):
    project = tmp_path / "bad.artprep"
    project.write_text(
        '{"version":99,"photos":[],"settings":{"background":"#F3EFE7","margin":0.08}}'
    )
    result = subprocess.run(
        [APP, "--render", str(project), "--output", str(tmp_path)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 1
    assert "Unsupported project version" in result.stderr
    assert list(tmp_path.iterdir()) == [project]
