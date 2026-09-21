"""Validate the external renderer boundary, including malformed requests."""

import json

import pytest
from job import read_job


def sample_job(tmp_path):
    source = tmp_path / "Artist's painting 日本.png"
    source.write_bytes(b"placeholder")
    return {
        "input": str(source),
        "width": 100,
        "height": 80,
        "points": [{"x": 10, "y": 10}, {"x": 90, "y": 10}, {"x": 90, "y": 70}],
        "background": "#F3EFE7",
        "canvas": [120, 80],
        "offset": [10, 0],
        "social": [2000, 1333],
    }


def test_reads_unicode_and_quoted_paths(tmp_path):
    data = sample_job(tmp_path)
    path = tmp_path / "job.json"
    path.write_text(json.dumps(data))
    assert read_job(path)["input"] == data["input"]


@pytest.mark.parametrize(
    "key,value",
    [
        ("background", "red"),
        ("points", []),
        ("canvas", [0, 90]),
        ("social", [90000, 20]),
        ("offset", ["x", 1]),
        ("width", True),
        ("points", [{"x": -1, "y": 0}] * 3),
        ("input", "/missing/photo.png"),
    ],
)
def test_rejects_malformed_jobs(tmp_path, key, value):
    data = sample_job(tmp_path)
    data[key] = value
    path = tmp_path / "job.json"
    path.write_text(json.dumps(data))
    with pytest.raises(ValueError):
        read_job(path)


def test_rejects_non_object_json(tmp_path):
    path = tmp_path / "job.json"
    path.write_text("[]")
    with pytest.raises(ValueError):
        read_job(path)
