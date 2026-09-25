"""Reject feeds that advertise the wrong release or malformed archives."""

import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "update_metadata", ROOT / "scripts/update_metadata.py"
)


@pytest.fixture
def validator():
    assert SPEC is not None and SPEC.loader is not None
    module = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(module)
    return module.validate_appcast


@pytest.fixture
def feed_archive(tmp_path):
    archive = tmp_path / "Art-Prep-v1.0.3-macOS-arm64.zip"
    archive.write_bytes(b"verified archive")
    feed = tmp_path / "appcast.xml"
    feed.write_text("""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><item><sparkle:version>1.0.3</sparkle:version>
<sparkle:shortVersionString>1.0.3</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
<enclosure url="https://github.com/kindlyops/artprep/releases/download/v1.0.3/Art-Prep-v1.0.3-macOS-arm64.zip"
length="16" type="application/octet-stream"
sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="/>
</item></channel></rss>""")
    return feed, archive


def test_accepts_exact_release(validator, feed_archive):
    feed, archive = feed_archive
    assert validator(feed, archive, "1.0.3") == "A" * 86 + "=="


@pytest.mark.parametrize(
    "before,after",
    [
        ("1.0.3</sparkle:version>", "0.0.1</sparkle:version>"),
        ("1.0.3</sparkle:shortVersionString>", "2.0.0</sparkle:shortVersionString>"),
        ("github.com/kindlyops", "example.com/kindlyops"),
        ('length="16"', 'length="0"'),
        ('length="16"', 'length="-16"'),
        ("AAAAAA==", "broken!!"),
        (">arm64<", ">x86_64<"),
        (">14.0<", ">15.0<"),
        ("<channel><item>", "<channel>"),
        ("</channel>", "<item/></channel>"),
        (
            "<rss version",
            '<!DOCTYPE rss [<!ENTITY local SYSTEM "file:///etc/passwd">]><rss version',
        ),
        ("xml-namespaces/sparkle", "xml-namespaces/other"),
        ("<enclosure", "<enclosure/><enclosure"),
    ],
)
def test_rejects_invalid_feed(validator, feed_archive, before, after):
    feed, archive = feed_archive
    feed.write_text(feed.read_text().replace(before, after))
    with pytest.raises(ValueError):
        validator(feed, archive, "1.0.3")


def test_rejects_oversized_feed(validator, feed_archive):
    feed, archive = feed_archive
    feed.write_bytes(b" " * 1_048_577)
    with pytest.raises(ValueError):
        validator(feed, archive, "1.0.3")


def test_checksum_cannot_reference_another_file(validator, feed_archive):
    feed, archive = feed_archive
    checksum = archive.with_suffix(".zip.sha256")
    checksum.write_text("0" * 64 + "  /etc/passwd\n")
    module = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(module)
    with pytest.raises(ValueError):
        module.validate_checksum(checksum, archive)
