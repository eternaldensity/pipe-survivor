#!/usr/bin/env bash
set -euo pipefail
GODOT="${GODOT_BIN:-/tmp/opencode/godot_bin/Godot_v4.7.2-stable_linux.x86_64}"
if [ ! -x "$GODOT" ]; then
  if command -v godot >/dev/null 2>&1; then GODOT="$(command -v godot)"; fi
  if command -v godot4 >/dev/null 2>&1; then GODOT="$(command -v godot4)"; fi
fi
if [ ! -x "$GODOT" ]; then
  echo "Godot binary not found. Set GODOT_BIN." >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$GODOT" --headless --path "$ROOT" --script "res://tests/generation_harness.gd" 2>&1 | tee /tmp/opencode/pipe_survivor_generation.log
if grep -q "RESULT: PASS" /tmp/opencode/pipe_survivor_generation.log; then
  exit 0
else
  exit 1
fi