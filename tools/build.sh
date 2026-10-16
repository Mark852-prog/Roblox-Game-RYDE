#!/usr/bin/env bash
# Rebuilds everything and runs all automated checks.
#   1. Generates the world     -> assets/World.rbxm, assets/Vehicles.rbxm
#   2. Builds the place file   -> build/RYDE.rbxl   (open this in Roblox Studio)
#   3. Lints the game code     (selene)
#   4. Runs the unit tests     (lune)
# Requires rojo, lune and selene on PATH (see rokit.toml for versions).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Generating world"
lune run tools/build-world

echo "== Generating vehicle models"
lune run tools/build-vehicles

echo "== Building place"
rojo build default.project.json -o build/RYDE.rbxl

echo "== Linting"
selene src

echo "== Testing"
lune run tests/run
