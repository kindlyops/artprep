"""Read and validate the external GIMP renderer request."""

import json
import math
import re
from pathlib import Path
from typing import Any, cast


def dimensions(value: Any, name: str) -> None:
    """Reject invalid or excessive image allocations.

    Args:
        value: Two integer dimensions from the JSON request.
        name: Field name used in error messages.
    """
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{name} must contain two dimensions.")
    if any(type(item) is not int or not 1 <= item <= 32768 for item in value):
        raise ValueError(f"Invalid {name} dimensions.")
    if value[0] * value[1] > 200_000_000:
        raise ValueError(f"{name} exceeds 200 megapixels.")


def validate_points(points: Any, size: list[int]) -> None:
    """Check that every outline vertex is finite and inside the source image."""
    if not isinstance(points, list) or not 3 <= len(points) <= 4000:
        raise ValueError("The outline requires between 3 and 4,000 points.")
    for point in points:
        if not isinstance(point, dict):
            raise ValueError("Each outline point must have x and y coordinates.")
        for key, maximum in zip(("x", "y"), size, strict=True):
            value = point.get(key)
            if type(value) not in (int, float):
                raise ValueError("Outline coordinates must be numbers.")
            if not math.isfinite(value) or not 0 <= value <= maximum:
                raise ValueError("An outline point is outside the source photo.")


def read_job(path: Path) -> dict[str, Any]:
    """Load a render request, raising ValueError for malformed or unsafe inputs."""
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError("The job must be a JSON object.")
    source = data.get("input")
    if not isinstance(source, str) or not Path(source).is_absolute():
        raise ValueError("The source must be an absolute file path.")
    if not Path(source).is_file():
        raise ValueError("Source photo is missing. Download it locally and try again.")
    color = data.get("background")
    if not isinstance(color, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        raise ValueError("Background must be a six-digit hexadecimal color.")
    validate_geometry(data)
    return data


def validate_geometry(data: dict[str, Any]) -> None:
    """Validate dimensions, translation and the source-coordinate outline."""
    size = [data.get("width"), data.get("height")]
    dimensions(size, "source")
    dimensions(data.get("canvas"), "canvas")
    dimensions(data.get("social"), "social")
    offset = data.get("offset")
    if not isinstance(offset, list) or len(offset) != 2:
        raise ValueError("Offset must contain two integers.")
    if any(type(value) is not int or abs(value) > 32768 for value in offset):
        raise ValueError("Invalid canvas offset.")
    validate_points(data.get("points"), cast(list[int], size))
