"""Validate the release described by a generated Sparkle feed."""

import base64
import hashlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NAMESPACE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def validate_appcast(feed: Path, archive: Path, version: str) -> str:
    """Check feed identity and archive metadata before cryptographic verification.

    Args:
        feed: Generated XML feed, no larger than one MiB.
        archive: Final notarized release ZIP.
        version: Expected three-part release version.

    Returns:
        The archive's base64 Ed25519 signature for Sparkle to verify.

    Raises:
        ValueError: The feed does not describe exactly this release.
        OSError: A required artifact cannot be read.
    """
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("Expected a three-part release version.")
    with feed.open("rb") as stream:
        data = stream.read(1_048_577)
    if len(data) > 1_048_576 or b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise ValueError("Update feed is oversized or contains forbidden declarations.")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise ValueError(f"Malformed update feed: {error}") from error
    items = root.findall("./channel/item")
    if root.tag != "rss" or len(items) != 1:
        raise ValueError("Update feed must advertise exactly one release.")
    item = items[0]
    expected = {
        "version": version,
        "shortVersionString": version,
        "hardwareRequirements": "arm64",
    }
    for field, value in expected.items():
        elements = item.findall(NAMESPACE + field)
        if len(elements) != 1 or elements[0].text != value:
            raise ValueError(f"Update feed {field} does not match {value}.")
    minimum = item.findall(NAMESPACE + "minimumSystemVersion")
    if len(minimum) != 1 or minimum[0].text not in ("14", "14.0", "14.0.0"):
        raise ValueError("Update feed must require macOS 14.")
    return validate_enclosure(item, archive, version)


def validate_enclosure(item: ET.Element, archive: Path, version: str) -> str:
    """Require the exact release URL, byte count and an Ed25519 signature."""
    enclosures = item.findall("enclosure")
    if len(enclosures) != 1:
        raise ValueError("Update feed must have exactly one archive.")
    enclosure = enclosures[0]
    name = f"Art-Prep-v{version}-macOS-arm64.zip"
    url = f"https://github.com/kindlyops/artprep/releases/download/v{version}/{name}"
    if archive.name != name or enclosure.get("url") != url:
        raise ValueError("Update archive name or URL does not match this release.")
    if enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("Update archive byte count does not match the feed.")
    signature = enclosure.get(NAMESPACE + "edSignature", "")
    try:
        decoded = base64.b64decode(signature, validate=True)
    except ValueError as error:
        raise ValueError("Invalid update signature encoding.") from error
    if len(decoded) != 64:
        raise ValueError("Update archive needs a 64-byte Ed25519 signature.")
    return signature


def validate_checksum(checksum: Path, archive: Path) -> None:
    """Verify one named archive without following paths supplied by a checksum file."""
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    expected = f"{digest}  {archive.name}\n"
    if checksum.read_text() != expected:
        raise ValueError("Checksum must match exactly this release archive.")


def main() -> None:
    """Print the validated archive signature or an actionable failure."""
    if len(sys.argv) != 4:
        sys.exit("Usage: update_metadata.py FEED ARCHIVE VERSION")
    try:
        if sys.argv[1] == "checksum":
            validate_checksum(Path(sys.argv[2]), Path(sys.argv[3]))
            return
        print(validate_appcast(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]))
    except (OSError, ValueError) as error:
        sys.exit(f"Update validation failed: {error}")


if __name__ == "__main__":
    main()
