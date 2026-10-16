# RYDE — Electric Bike & Street Riding Simulator (Roblox)

A semi-realistic Roblox riding game: electric dirt bikes, e-bikes and
scooters, wheelies and stunts, traffic, police pursuits, crashes and damage.

**Current state: version 0.2.0 — first rideable bikes, garage lobby, town and
countryside map, sound.** See [docs/PROGRESS.md](docs/PROGRESS.md).

## Play it in Roblox Studio

New to Roblox Studio? Follow **[docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)**.

Short version: open `build/RYDE.rbxl` in Roblox Studio and press **Play**.

## Documentation

- [Getting started](docs/GETTING_STARTED.md) — install, open, play, report problems
- [Testing](docs/TESTING.md) — automated tests and manual checklists
- [Architecture](docs/ARCHITECTURE.md) — project layout and key technical decisions
- [Progress](docs/PROGRESS.md) — milestone status, limitations, next steps

## Developer setup

Tools (versions pinned in `rokit.toml`): [Rojo](https://rojo.space),
[Lune](https://lune-org.github.io/docs), [Selene](https://kampfkarren.github.io/selene/).

```sh
rokit install          # or install the three tools another way
./tools/build.sh       # generate map, build place, lint, test
rojo serve             # optional: live-sync into Studio with the Rojo plugin
```

## Project layout

```
src/shared   -> ReplicatedStorage.Shared                     configs, units, validation
src/server   -> ServerScriptService.Server                   server logic
src/client   -> StarterPlayer.StarterPlayerScripts.Client    input, UI
assets/      generated models (World.rbxm, Vehicles.rbxm)
tools/       world + vehicle generators and build script
tests/       Lune test suite
build/       RYDE.rbxl — the place file to open in Studio
```

All vehicles and brands in this game are fictional.
