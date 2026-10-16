# Testing

## Automated tests (run by the developer, not in Roblox)

```
./tools/build.sh
```

Regenerates the world and bike models, builds `build/RYDE.rbxl`, lints
with Selene and runs the Lune test suite (107 tests). They cover:

- Every `.luau` file in `src/` compiles.
- Units and gravity (and that the project file matches).
- Surface table, vehicle configs and the config validator.
- **Handling design checks** computed from the real config numbers: each
  bike reaches ~its top speed; Voltra Storm does 0–50 km/h in < 4 s;
  Kestrel out-accelerates Voltra; Voltra only wheelies when you lean back;
  the normal brake never flips a bike; the front brake can do a stoppie;
  steering lock shrinks with speed and on slippery surfaces.
- Bike model structure (only the chassis has mass, joints exist, seat
  can't be touch-sat, IK attachments, mass = bike + rider).
- Sound config.
- The built place: scripts in the right services, lighting, world zones,
  garage lobby pieces, part budget, decoration doesn't block wheels.

**What they can't cover:** the real Roblox engine — physics behaviour,
rendering, sound playback, input, networking. Those need the checks below.

## Milestone 2 checklist (in Roblox Studio)

Open the new `build/RYDE.rbxl`, then **Home → Play**. Tick what works,
and for anything that doesn't, tell me what happened.

### Lobby & menu
- [ ] You see the garage showroom: dark room, teal neon, a bike turning on a platform, the RYDE menu on the left, music playing.
- [ ] Hovering the menu items highlights them with a click sound.
- [ ] **GARAGE** lists 4 vehicles; Voltra Storm "OWNED", Kestrel Sting "TEST RIDE", the other two "COMING SOON". Selecting Kestrel swaps the showroom bike and the stats card.
- [ ] **SETTINGS**: switches and volume sliders respond. **CONTROLS** shows the key list.
- [ ] **PLAY** fades to black and you appear sitting on your bike inside the garage, facing out.

### Riding (Voltra Storm)
- [ ] **W** accelerates smoothly (not instantly); the speedometer climbs to ~75 km/h on the long straight.
- [ ] **S** slows you firmly without flipping you over.
- [ ] **A / D** steer. At walking pace the bars turn a lot; at speed the bike turns gently and **leans** into the corner.
- [ ] The bike stays upright when stopped and at low speed.
- [ ] **Shift + W** from slow speed lifts the front wheel (WHEELIE pill shows the angle). Releasing throttle brings it down. Holding too long flips the bike backwards → press **R**.
- [ ] **Space** at speed (front brake) lifts the rear (STOPPIE). **Shift** while braking keeps the rear down.
- [ ] Riding over the **bumps lane**: rumble strip, speed bumps and curbs make the suspension move, nothing launches you into the sky.
- [ ] **Jump park**: the bike leaves the kicker, flies (AIR pill shows time) and lands with a thump. **Shift/Ctrl** in the air rotates the bike a little.
- [ ] **Surface strips**: grass, sand and mud feel slower and slidier than asphalt (and the speedometer shows the surface name).
- [ ] **F** gets you off; the bike stands on its kickstand. Walk up and press **E** to ride again.
- [ ] **R** stands a fallen bike back up.

### Sound
- [ ] Electric whine rises in pitch with speed.
- [ ] Rolling noise on asphalt, crunching on dirt/gravel, wind at speed.
- [ ] A thump on landing. Birds/distant traffic ambience in the world.
- [ ] If any sound is missing, wrong, or annoying, tell me which one.

### World
- [ ] Grass terrain with waving grass blades, a lake with a beach and pier, hills, mountains at the edges, forests.
- [ ] Town (past the oval's far end): streets with kerbs, shops with signs, parked cars, street lights.
- [ ] No floating or sunken objects; nothing you fall through.

### Multiplayer (optional, Studio → Test → Clients and Servers, 2 players)
- [ ] Each player gets their own bike; you can't ride the other player's bike (no Ride prompt on it).
- [ ] You see the other player's bike lean, steer and make sounds.

### Performance
- [ ] Turn on the developer overlay (F2): FPS stays smooth (50+) while riding around town.

## Results log

| Date | Version | Who | Result |
|---|---|---|---|
| 2026-10-16 | 0.1.0 | Claude (automated) | 51/51 tests passed, Selene clean |
| 2026-10-16 | 0.1.0 | You (Studio) | Place opens, `Server: OK`, HUD and map visible ✅ |
| 2026-10-16 | 0.2.0 | Claude (automated) | 107/107 tests passed, Selene clean |
| — | 0.2.0 | You (Studio) | *Not yet tested* |
