#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -d .venv ]]; then
  echo "[error] .venv not found. run scripts/setup_env.sh first"
  exit 1
fi

source .venv/bin/activate
PYTHONPATH=. python -m unittest discover -s tests -v
