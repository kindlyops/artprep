#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ruff check renderer PythonTests
ruff format --check renderer PythonTests
ty check
.venv/bin/pytest -q
