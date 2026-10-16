# Progress

> **Feature work is paused for a quality overhaul.** See [QUALITY_AUDIT.md](QUALITY_AUDIT.md)
> for the findings and the phased plan (waiting for approval).

Status key: ✅ done & verified in Roblox · 🟡 implemented & auto-tested, waiting for your Studio test · ⬜ not started

| # | Milestone | Status |
|---|---|---|
| 1 | Project setup & test environment | ✅ You confirmed it opens and `Server: OK` (screenshot, 2026-10-16) |
| 2 | First rideable bike | 🟡 |
| 3 | Riding physics (suspension, lean, wheelies, air, surfaces) | 🟡 First version built together with M2 — needs riding & tuning |
| 4 | Crashes & damage | ⬜ |
| 5 | Environment | 🟡 Started early at your request: garage lobby, town, lake, hills, forest |
| 6 | Traffic & police | ⬜ (streets, intersections and traffic-light props are ready for it) |
| 7 | Vehicles & customisation | ⬜ (Kestrel Sting already rideable for testing in Studio) |
| 8 | Multiplayer validation & saving | ⬜ |
| 9 | Polish & release prep | 🟡 Started early: lobby menu, HUD, sound, lighting |

## Version 0.2.0 — what's in it

### Implemented
**Bike (Milestones 2–3)**
- Two rideable electric dirt bikes generated from their configs: **Voltra Storm**
  (starter) and **Kestrel Sting** (more powerful; free to test in Studio only).
- Physics: one rigid body, raycast (sphere-cast) suspension front and rear,
  tyre forces at the contact patches with a grip limit per surface (friction
  circle), power-limited electric motor, aero drag, rolling resistance,
  regenerative braking, speed-sensitive steering, rider weight shift.
- Wheelies and stoppies emerge from the physics (no animation fakery).
- Airborne: limited pitch control, weak roll, no auto-levelling.
- Visuals: bike + rider lean into turns, steering, suspension travel,
  spinning wheels, brake light, hands on grips / feet on pegs (R15).
- Riding: ProximityPrompt to get on (owner only, checked by the server),
  F to get off, R to reset upright; network ownership given to the rider.
- Server: one bike per player, spawn slots in the garage, kickstand
  parking, recovery if a bike falls out of the world, speed sanity check.

**Presentation**
- Lobby: garage showroom with turntable, cinematic camera, menu
  (Play / Garage / Settings / Controls), player chip, fade transitions.
- HUD: arc speedometer, throttle & brake bars, surface, trick indicators
  (wheelie/stoppie angle, airtime, slides), controls hint, toasts.
- Settings: km/h–mph, chase camera, controls hint, dev overlay, 5 volume sliders.
- Audio: motor whine, tyre roll (paved/loose), skids, wind, landings,
  ambience, lobby music, UI sounds — through 4 sound groups.
- World: Future lighting + atmosphere/bloom/colour grading, terrain grass
  with grass blades, lake with beach and pier, rolling hills, mountain
  border, free-ride dirt park, "Voltville" town (streets, kerbs, 12 shops,
  parking, street lights, crossings, traffic-light props), 650 trees, plus
  all Milestone 1 test zones.

### Tested successfully (automated, outside Roblox)
- 107/107 Lune tests, Selene lint clean. Includes: handling design
  checks from the real configs (top speed reached, 0–50 km/h time,
  wheelie and stoppie thresholds, brakes don't endo), model structure,
  sound config, built place contents.

### Not yet tested (needs you in Studio)
- Everything at runtime: whether riding feels good, camera, sounds
  (the audio IDs were chosen by title — not listened to), terrain look,
  menu layout on your screen, performance.

### Known limitations
- Bikes are built from Roblox parts, not sculpted meshes, so they look
  "stylised" next to games with professional Blender models. The model
  layout is documented so a mesh bike can replace it later.
- No crashes/damage yet (Milestone 4): hitting a wall just stops you;
  looping a wheelie flips the bike — press R.
- No mobile touch controls yet (PC keyboard + gamepad only).
- Settings aren't saved between sessions yet (Milestone 8).
- Terrain is generated at server start — in Studio's edit mode the map
  floats over a flat floor; press Play to see the real ground.
- E-bike and scooter have configs but no models yet.

### Next recommended action
Open the new `build/RYDE.rbxl`, ride, and report back using the checklist
in [TESTING.md](TESTING.md). Feel is what matters now — tell me what feels
too slow, twitchy, floaty, etc. and I'll tune the numbers.

## 2026-10-16 — Real bikes from the Creator Store + effects

- **Implemented:** the server loads the user's chosen Creator Store bikes
  (Sur-Ron Light Bee Gear / Light Bee X / Truly / detailed, KTC Racing,
  Yamaha YZ450F) at start-up, strips their scripts/physics/sounds and fits
  them onto our physics bike (`AssetImportService`). Garage has a **STYLE**
  picker. Real names kept (Sur-Ron Light Bee X, Talaria Sting R).
  Dust / pebbles / tyre smoke / sparks particles (`VehicleEffects`), using
  the chosen Creator Store effects when they load, built-in ones otherwise.
- **Tested (offline):** 120/120 tests, Selene clean, place file allows
  third-party asset loading.
- **Not tested:** whether Roblox actually loads those assets in Studio,
  and how well the automatic fitting (scale/orientation/wheels) looks.
  Output prints `[RYDE] Import ...` lines describing each fit.
- **Fallback:** if a style fails to load, the old built-in bike is used.
