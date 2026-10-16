# Progress

Status key: ✅ done & verified · 🟡 implemented, not yet verified in Roblox · ⬜ not started

| # | Milestone | Status |
|---|---|---|
| 1 | Project setup & test environment | 🟡 Built and auto-tested; waiting for your Studio check |
| 2 | First rideable bike | ⬜ |
| 3 | Riding physics (suspension, lean, wheelies, air, surfaces) | ⬜ |
| 4 | Crashes & damage | ⬜ |
| 5 | Environment (neighbourhood, roads, trail) | ⬜ |
| 6 | Traffic & police | ⬜ |
| 7 | Vehicles & customisation | ⬜ |
| 8 | Multiplayer validation & saving | ⬜ |
| 9 | Polish & release prep | ⬜ |

## Milestone 1 — Project setup

### Implemented
- Rojo project (`default.project.json`) with shared / server / client folders.
- Build pipeline (`tools/build.sh`): map generation → place build → lint → tests.
- `build/RYDE.rbxl`, ready to open in Studio.
- World settings: real-scale gravity (28.03), daytime lighting, streaming off.
- Shared foundations: `Units`, `GameConfig`, `SurfaceConfig` (30 surfaces),
  `VehicleSchema` validator, `VehicleCatalog` with 4 vehicle configs
  (Voltra Storm prototype + 3 planned).
- Server start-up checks (gravity, configs, map) reported in Output and to clients.
- Client developer HUD: server status, FPS, speed (km/h / mph), surface + grip, position.
- Generated test track (590 parts): 1 km oval, acceleration & braking markers,
  skills pad, jump park (4 lanes), 7 surface strips, bumps & curbs lane,
  hill, dirt trail, crash lane.
- Beginner guide, architecture notes, test checklist.

### Tested successfully
- Automated (Lune, outside Roblox): 51/51 tests pass; Selene lint clean.
- Map layout reviewed via generated top-down and side-view plots.

### Not yet tested
- Anything inside Roblox Studio: that the place opens, scripts run, HUD
  displays, signs render and read correctly, ground labels' orientation.

### Known limitations
- No vehicles yet — the four vehicle configs are data only. The three
  "Planned" ones have first-estimate numbers that will be tuned in Milestone 7.
- The test map is flat-ground parts, no Terrain (Terrain arrives with the real map in Milestone 5).
- Selene uses a minimal offline Roblox definition, so it doesn't check Roblox API member names.
- No live sync yet: updates come as a new `RYDE.rbxl` download.

### Next recommended action
Follow [GETTING_STARTED.md](GETTING_STARTED.md), run the checklist in
[TESTING.md](TESTING.md), and report back. Then Milestone 2: the first rideable bike.
