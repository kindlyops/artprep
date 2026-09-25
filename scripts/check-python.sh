#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ruff check renderer PythonTests scripts/*.py
ruff format --check renderer PythonTests scripts/*.py
ty check
.venv/bin/pytest -q
