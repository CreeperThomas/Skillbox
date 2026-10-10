#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/.build/cache"
mkdir -p "$CACHE"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
export SWIFT_MODULECACHE_PATH="$CACHE/swift"
exec "$@"
