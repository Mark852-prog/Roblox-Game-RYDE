# Testing

## Automated tests (run by the developer, not in Roblox)

```
./tools/build.sh
```

Regenerates the map, builds `build/RYDE.rbxl`, lints with Selene and runs
the Lune test suite. What the automated tests cover:

- Every `.luau` file in `src/` compiles.
- Unit conversions and the gravity value (including that
  `default.project.json` sets the matching `Workspace.Gravity`).
- `SurfaceConfig`: sane values, every key is a real Roblox material,
  attribute overrides and fallbacks.
- Vehicle configs: all four validate, and the validator catches eight kinds
  of broken config.
- The built place file: scripts are the right type in the right service,
  world settings, every test zone exists, only cones/crates are unanchored,
  no oversized parts, road paint is non-colliding, road surface height.

**What they can't cover:** anything needing the real Roblox engine —
physics, rendering, player input, networking. Those need the manual checks below.

## Milestone 1 manual checklist (in Roblox Studio)

Open `build/RYDE.rbxl` and press **Play** (see [GETTING_STARTED.md](GETTING_STARTED.md)).

### Start-up
- [ ] You spawn on the concrete plaza facing the blue "RYDE TEST TRACK" sign.
- [ ] HUD (top-left) shows `Server: OK (v0.1.0)`.
- [ ] Output shows `[RYDE] Server ready - all startup checks passed` and no red errors.
- [ ] **F2** hides and shows the HUD.

### HUD readings
- [ ] Standing still: Speed ≈ 0.0 km/h.
- [ ] Walking: Speed ≈ 20 km/h (walk speed 16 studs/s × 0.35 m × 3.6).
- [ ] On the plaza: `Surface: Concrete [Concrete]`, `Grip: 0.95`.
- [ ] On the grass: `Surface: Grass [Grass]`, `Grip: 0.60`.
- [ ] On the road: `Surface: Asphalt [Asphalt]`, `Grip: 1.00`.
- [ ] At the top of a jump: `Surface: (airborne)` briefly appears.

### Map walk-through (look for floating, sunken, or flickering parts)

Directions are from where you spawn: "ahead" is the way you face, "behind" is
back past the spawn pad. The map is about 1,000 studs across — roughly a
minute of walking from one side to the other. You can also stop the game
and fly the editor camera around instead (right mouse button + W A S D, E/Q for up/down).

- [ ] **Oval track** (ahead of spawn): smooth curves, white edge lines, yellow dashed centre lines on the straights.
- [ ] **Main straight** (the near straight): start line + "ACCELERATION TEST" sign at the right-hand end; 100–500 boards; red brake line and white lines toward the left-hand end.
- [ ] **Skills pad** (right side of the infield): 15 orange cones in a line (they can be knocked over), white & yellow circle dots, wooden balance plank.
- [ ] **Jump park** (centre of the infield, brown dirt): 4 lanes — small table, medium table, gap jump, drop-off — ramps rise as you ride away from the near straight.
- [ ] **Surface strips** (left side of the infield): 7 strips with names painted at the end nearest the spawn. Check the HUD on each: Asphalt, Concrete, LeafyGrass, Dirt (Ground), Gravel (Pebble), Sand, Mud.
- [ ] **Bumps & curbs lane** (just beyond the far straight): rumble strip, 3 yellow speed bumps, 3 curbs, broken pavement patches, dirt whoops.
- [ ] **Hill** (far right): two climbs (gentle and steep), a flat top, and a descent on the far side.
- [ ] **Dirt trail** (far left): a brown loop path.
- [ ] **Crash test lane** (behind the spawn): loose crates, lamp post, red car-sized block, concrete wall with red stripes at the right-hand end.
- [ ] Signs are readable from the direction you approach them. Painted ground labels read the right way up when you approach them from the spawn side.

### Things we know can't be judged yet
Ramp angles, bump heights and the track layout were chosen for the bike
that arrives in Milestone 2; whether they *feel* right can only be judged by riding.

## Results log

| Date | Milestone | Who | Result |
|---|---|---|---|
| 2026-10-16 | M1 | Claude (automated) | `tools/build.sh`: 51/51 tests passed, Selene 0 warnings |
| — | M1 | You (Studio) | *Not yet tested* |
