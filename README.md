# LAST LIGHT

A sci-fi co-op looter shooter for Roblox, written in strict Luau and synced with
[Rojo](https://rojo.space). The progression systems take their cues from the genre
(power levels and caps, Powerful and Pinnacle weekly rewards, rarity tiers, rolled
perks, strikes, a raid, a social hub). Every name, piece of lore and asset in the
game is original.

> **Status: Phase 1 of 11 is done.** That covers the project setup, every config
> module, and player data saving with session locking. See [Roadmap](#roadmap).

## Requirements

- [Roblox Studio](https://create.roblox.com/)
- [Rokit](https://github.com/rojo-rbx/rokit), the toolchain manager (Aftman still works)
- Git

## Setup

### 1. Install the toolchain

The tool versions are pinned in `rokit.toml`: Rojo, Lune, selene, StyLua and luau-lsp.

```sh
# Install Rokit once: https://github.com/rojo-rbx/rokit#installation
rokit install        # run inside the repository
```

If you use Aftman, `aftman install` reads `aftman.toml`, which pins the same versions.

### 2. Install the Rojo plugin in Studio

```sh
rojo plugin install
```

This installs the plugin version that matches the CLI. You can also install "Rojo"
from the Creator Store; its major and minor version must match `rojo --version` (7.7).

### 3. Sync the code into Studio

```sh
rojo serve
```

In Studio, open a Baseplate, then go to **Plugins → Rojo → Connect** (the default
address is `localhost:34872`). The code syncs live:

| On disk       | In Studio                                |
|---------------|------------------------------------------|
| `src/server`  | `ServerScriptService`                    |
| `src/client`  | `StarterPlayer.StarterPlayerScripts`     |
| `src/shared`  | `ReplicatedStorage.Shared`               |
| `src/gui`     | `StarterGui`                             |

`Workspace.StreamingEnabled` is turned on by the project file.

If you don't want live sync, build a place file and open it instead:

```sh
rojo build default.project.json --output LastLight.rbxl
```

### 4. Publish and enable API Services (needed for saving)

DataStores only work in a published place with API access turned on:

1. **File → Publish to Roblox** (create a new experience the first time).
2. **Home → Game Settings → Security → Enable Studio Access to API Services**, then **Save**.

If you skip this, the game still runs. It uses an in-memory store, prints a warning
that nothing will persist, and the dev panel shows `Storage: MOCK`. To force the
in-memory store even with API access on, set `GameConfig.Data.UseMockInStudio = true`.

## Testing Phase 1 in Studio

1. Press **Play**. The Output should print `[LAST LIGHT] server v0.1.0 started`, with
   no config errors. In Studio, the server refuses to start if a config is invalid.
2. The **DEV panel** opens at the top right (press **F2** or the DEV button to toggle it).
   It shows:
   - Storage: `DataStore` (saving works) or `MOCK` (see step 4 of Setup)
   - Class and subclass
   - Power 350: the eight starter items, all at 350
   - Currencies, item counts, equipped gear, reset timers and lifetime stats
3. Change the data with the buttons: **+1000 Quanta**, **Grant Legendary**,
   **Grant Exotic**, **Pinnacle Drop**, **Cycle Class**. Each change appears
   immediately, and a toast shows under *Server messages*.
4. **Check persistence** (requires API Services): press **Save Now**, stop the test,
   press Play again. The currencies, items, class and login count should all carry over.
5. **Check session locking**: under **Test → Clients and Servers**, start a local
   server with 1 player, make changes, and close that player's window. The Output
   shows `Player_<id> released (Released)`. Start again: the data loads straight
   away, with no lock wait.
6. **Apply Resets** clears weekly and daily reward claims. **Reset Profile** (click twice)
   wipes the save back to a fresh character.

Debug commands only run in Studio or for UserIds listed in
`GameConfig.Debug.AdminUserIds`. The server flags and eventually kicks anyone else
who sends them.

## Development checks

Run these before pushing. CI runs the same checks.

```sh
lune run tests/run          # unit tests (power math, loot rolls, session locking, configs...)
lune run tests/run Power    # only spec files whose name contains "Power"
bash scripts/check.sh       # format + lint + build + strict type check + tests
```

- **Tests** use Lune with a small virtual DataModel (`tests/harness/VirtualGame.luau`)
  that loads the real modules from `src/`. The data layer is tested against
  `MockDataStore`, including two "servers" fighting over one profile.
- **Type checking**: every file is `--!strict`. `scripts/analyze.sh` runs luau-lsp with
  a Rojo sourcemap, so it resolves the same requires Studio does. In VS Code, install
  the *Luau Language Server* extension and run `rojo sourcemap --watch -o sourcemap.json`.
- **Lint and format**: `selene src` and `stylua src tests`.

## Project layout

```
default.project.json        Rojo project (paths → Studio services)
rokit.toml / aftman.toml    pinned toolchain
src/
  shared/                   ReplicatedStorage.Shared (server + client)
    Config/                 ALL game data: power, rarity, weapons, perks, armor,
                            classes, activities, enemies, loot, economy, assets...
    ConfigValidator.luau    cross-checks every config at server start
    Items/                  ItemCatalog, ItemRoller (stat/perk rolls), Inventory
    Power/PowerMath.luau    character power, drop power, combat scaling
    Net/                    Remotes (definitions), Guard (argument validation)
    Util/                   Signal, TableUtil, RateLimiter, TimeUtil
    Types.luau              shared type definitions (ProfileData, ItemInstance, ...)
  server/                   ServerScriptService
    Main.server.luau        validates configs, starts services
    Services/               NetService, DataService, DebugService
    Data/                   ProfileStore (session locking), MockDataStore,
                            ProfileTemplate, Migrations, Resets
  client/                   StarterPlayerScripts
    Main.client.luau        starts controllers
    Controllers/            DataController (data replica), DebugPanelController
    Net/ClientNet.luau      client side of the remotes
    UI/Theme.luau           colors and fonts
  gui/                      StarterGui ScreenGui shells
tests/                      Lune test runner, harness and specs
scripts/                    install-tools / analyze / check
DESIGN.md                   power math, drop tables, data model, how to add content
```

## Balancing

All tuning lives in `src/shared/Config`. Logic code never hard-codes a number that a
designer would want to change. To rebalance, edit a config module, then run
`lune run tests/run`. The config tests and the validator catch broken references,
such as a weapon using an unknown perk or a mission pointing at a missing boss.
[DESIGN.md](DESIGN.md) explains the math and walks through adding a new weapon,
mission or enemy.

## Assets

The game ships without third-party assets. Every sound, image and place id is a
placeholder (`0`) in `src/shared/Config/AssetIds.luau`. Replace them only with assets
you own or free-to-use Creator Store items. Models are looked up by name under
`ReplicatedStorage.Assets` (for example, `Model = "AutoRifle_Frontier"` in
`WeaponConfig`), and clearly named grey placeholder parts stand in until you add them.

## Roadmap

| Phase | Scope | Status |
|------:|-------|--------|
| 1 | Rojo setup, folder structure, config modules, data saving | ✅ done |
| 2 | Weapon framework: shooting, damage, ammo, test weapons, dummy | next |
| 3 | Loot generator, rarity, perks, power, inventory + character screen | |
| 4 | Enemy AI and one faction | |
| 5 | Hub world, vendors, Star Chart (activity map), teleporting | |
| 6 | Story missions | |
| 7 | Powerful/Pinnacle rewards, weekly reset, milestones | |
| 8 | Strikes and The Long Dark (hardened strike) | |
| 9 | Classes, abilities, subclasses | |
| 10 | Dungeon and raid | |
| 11 | Polish, VFX, audio, balancing, anti-exploit review | |
