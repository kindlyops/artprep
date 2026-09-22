#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cache="${ARTPREP_BUILD_ROOT:-/private/tmp/artprep-$(id -u)}"
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
CLANG_MODULE_CACHE_PATH="$cache/cache/clang" swift test --disable-sandbox \
	--scratch-path "$cache/build" --cache-path "$cache/cache" \
	--config-path "$cache/config" --security-path "$cache/security" \
	-Xswiftc -warnings-as-errors
