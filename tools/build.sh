#!/usr/bin/env bash
# Rebuilds everything and runs all automated checks.
#   1. Generates the test map  -> assets/TestTrack.rbxm
#   2. Builds the place file   -> build/RYDE.rbxl   (open this in Roblox Studio)
#   3. Lints the game code     (selene)
#   4. Runs the unit tests     (lune)
# Requires rojo, lune and selene on PATH (see rokit.toml for versions).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Generating test track"
lune run tools/build-testtrack

echo "== Building place"
rojo build default.project.json -o build/RYDE.rbxl

echo "== Linting"
selene src

echo "== Testing"
lune run tests/run
