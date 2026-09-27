#!/usr/bin/env bash
# Runs every check CI runs: formatting, lint, build, type check, tests.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== StyLua"
stylua --check src tests
echo "== selene"
selene src
echo "== Rojo build"
mkdir -p build
rojo build default.project.json --output build/LastLight.rbxl
echo "== luau-lsp"
bash scripts/analyze.sh
echo "== Tests"
lune run tests/run
echo "All checks passed."
