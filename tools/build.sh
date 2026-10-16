#!/usr/bin/env bash
# Rebuilds everything and runs all automated checks.
#   1. Generates the world     -> assets/World.rbxm, assets/Vehicles.rbxm
#   2. Builds the place files  -> build/RYDE.rbxl (the game), build/PhysicsLab.rbxl (tests)
#   3. Lints the game code     (selene)
#   4. Runs the unit tests     (lune)
# Requires rojo, lune and selene on PATH (see rokit.toml for versions).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Generating world"
lune run tools/build-world

echo "== Generating vehicle models"
lune run tools/build-vehicles

echo "== Generating PhysicsLab"
lune run tools/build-physicslab

echo "== Building place"
rojo build default.project.json -o build/RYDE.rbxl
rojo build physicslab.project.json -o build/PhysicsLab.rbxl

echo "== Linting"
selene src

echo "== Testing"
lune run tests/run
