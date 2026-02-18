#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY_CLIENT_DIR="$ROOT_DIR/apps/mac-client/python"

cd "$PY_CLIENT_DIR"
./scripts/run.sh "$@"
