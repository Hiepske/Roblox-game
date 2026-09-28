# LAST LIGHT

A sci-fi co-op looter shooter for Roblox, written in strict Luau and synced with
[Rojo](https://rojo.space). The progression systems take their cues from the genre
(power levels and caps, Powerful and Pinnacle weekly rewards, rarity tiers, rolled
perks, strikes, a raid, a social hub). Every name, piece of lore and asset in the
game is original.

> **Status: Phase 3 done.** The game plays from end to end and looks the part: a
> multi-level social hub (the Spire), the full inventory with vault, postmaster and
> loadouts, 13 weapon archetypes with their own feel, three story missions (First Light,
> Sunken Relay, The Hollow Dark), the Hollow Spire Nightfall with medals, and the
> five-part Vault of Echoes raid, all playable solo or with a fireteam. On top of that:
> mission intros, loading screens, waypoints, a kill feed, adaptive music and a Mission
> Complete screen. See [TESTING.md](TESTING.md) to try all of it in Studio.

## Quick try (no tools needed)

1. Install [Roblox Studio](https://create.roblox.com/) and log in.
2. Download the latest place file: on GitHub open **Actions**, click the most recent
   green **CI** run, and download the **LastLight-place** artifact (a zip containing
   `LastLight.rbxl`). Unzip it.
3. Double-click `LastLight.rbxl`, or open it in Studio with **File → Open from File**.
4. Press **Play**, then follow the [Studio test guide](TESTING.md).

The steps below set up live code sync, which you only need to edit the code.

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
address is `localhost:34872`). The code syncs live, along with a placeholder floor
and spawn point in `Workspace`:

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

## Playing

### Controls

| Key | Action |
|-----|--------|
| Mouse | look around (the mouse is locked to the screen center while playing) |
| Left click | fire (hold for automatic weapons, charge the fusion rifle) |
| Right click | aim down sights (zoom, tighter spread; sniper scope) |
| R | reload |
| 1 / 2 / 3 or mouse wheel | kinetic / energy / heavy weapon |
| M | the Director (launch activities, join fireteams, leave an activity) |
| Tab or I | inventory (character, vault, postmaster, loadouts) |
| E | interact: terminals, chests, consoles; hold to revive a teammate's ghost in the raid |
| Any key | skip the mission intro |
| F2 | developer panel (Studio and the game owner only) |
| Space | close the loot / Mission Complete screen |

Gamepad: R2 fire, L2 aim, X reload, Y swap weapon, D-pad up Director, View button
inventory. Touch devices get on-screen FIRE, AIM, R and SWAP buttons.

### What's in the game

| Activity | Power | Where | Highlights |
|----------|------:|-------|------------|
| The Spire (hub) | | the top of a giant wall | four levels (courtyard, Command Deck, Bazaar, Hangar), vendors, Gunsmith, Postmaster, Vault, a shooting range and two secrets |
| First Light | 350 | Frostreach, a snowy valley | crash site → frozen village (roof snipers) → outpost uplink hack (60 s) → reactor regulators → the Scrap Warden |
| Sunken Relay | 380 | Meridian Coast, an overgrown shore | beach landing → drowned market → the relay tower floor by floor → the Tide Marshal on the roof |
| The Hollow Dark | 410 | Hollowmere caves | flashlights; pale woods → crystal caverns → Veiled barracks → ritual chamber → the teleporting Hollow Priest |
| Nightfall: Hollow Spire | 450 / 470 / 490 | a cliff fortress at dusk | weekly modifiers, score and timer, Bronze/Silver/Gold medals; Vekta collapses the arena floor at 33% |
| Raid: Vault of Echoes | 495 | a gold and black vault | The Gate (echo plates), the Descent (jumping puzzle), the Echo Chamber (carry echoes to the well), the Silent Hall (lasers and patrols), the Echo Sovereign (safe circles against its nova); a weekly Pinnacle per encounter; up to 6 players, solo-launchable |

Story missions unlock in order, drop Rare/Epic gear and always give a new weapon. The
Nightfall unlocks after First Light, the raid at power 480. Every boss has immune
phases at 66% and 33%, barrages and telegraphed slams, heavy ammo in its arena and a
slow-motion death into a loot chest.

### Testing it

[TESTING.md](TESTING.md) is the Studio test guide: a 15-minute smoke test, then what to
do and what to check in the hub, the inventory, every weapon type, each mission, the
Nightfall and each raid encounter, solo and with a fireteam.

### Developer chat commands

Type these in chat (everyone in Studio, or the game's owner in a live server):

| Command | What it does |
|---------|--------------|
| `/setpower 480` | sets every equipped item to that power |
| `/give W_LAST_EMBER` | rolls a weapon or armor piece (id or part of its name) at your power and equips it |
| `/giveall` | one of every weapon (the overflow goes to the vault) |
| `/launch firstlight` · `relay` · `hollow` · `nightfall legend` · `raid` | launches, ignoring unlocks |
| `/zone 3` | jumps to zone 3 of the current activity (gates before it open) |
| `/skip` | skips the current objective step |
| `/god` | toggles taking no damage |
| `/heavy` | drops a heavy ammo box in front of you |
| `/kill` | kills you (to test respawns) |
| `/leave` | returns you to the hub |
| `/resetweek` | resets weekly rewards so Powerful/Pinnacle drop again |
| `/wipe` | wipes your save back to a new 350 character |
| `/help` | lists the commands |

Prefer clicking? Press **F2** for the developer panel (it frees the mouse while open):
currencies, random loot, save now, resets, power presets, launches, skip, god mode,
heavy ammo and leave.

### Checking saves

With API Services on (step 4 of Setup), progress survives a restart: press **Save Now**
in the F2 panel or just stop and play again. Under **Test → Clients and Servers**, closing
a player's window prints `Player_<id> released (Released)`, and the next load is instant.

## Development checks

Run these before pushing. CI runs the same checks.

```sh
lune run tests/run          # unit + integration tests (power, loot, saving, maps, UI, activities...)
lune run tests/run Power    # only spec files whose name contains "Power"
bash scripts/check.sh       # format + lint + build + strict type check + tests
```

- **Tests** use Lune with a small virtual DataModel (`tests/harness/VirtualGame.luau`)
  that loads the real modules from `src/`. The data layer is tested against
  `MockDataStore`, including two "servers" fighting over one profile. Maps, rigs, gun
  models and every client screen (HUD, Director, inventory, loot/Mission Complete,
  loading screen, intro, waypoint, kill feed, music) are built with Lune's real Roblox
  Instances, which reject unknown properties. `Activity.spec` runs ActivityService
  and MissionService against fake services on a virtual clock: every story mission and
  the Nightfall to the loot chest, and every raid encounter solo plus the Gate with a
  fireteam (plates, revives, wipes, echoes, safe circles, chests).
- **Type checking**: every file is `--!strict`. `scripts/analyze.sh` runs luau-lsp with
  a Rojo sourcemap, so it resolves the same requires Studio does. In VS Code, install
  the *Luau Language Server* extension and run `rojo sourcemap --watch -o sourcemap.json`.
- **Lint and format**: `selene src` (CI fails on any warning) and `stylua src tests`.

## Project layout

```
default.project.json        Rojo project (paths → Studio services)
rokit.toml / aftman.toml    pinned toolchain
src/
  shared/                   ReplicatedStorage.Shared (server + client)
    Config/                 ALL game data: power, rarity, weapons, perks, armor, classes,
                            activities (zones, steps, waves), bosses, enemies, combat,
                            world/lighting, loot, economy, presentation, asset ids
    ConfigValidator.luau    cross-checks every config at server start
    Activities/             ActivityRules (unlocks, difficulties, weekly modifiers),
                            MissionRules (zone lists, requirements, scaling, medals)
    Combat/DamageMath.luau  falloff, precision, shields, splash
    Items/                  ItemCatalog, ItemRoller, LootRoller, Inventory
    Power/PowerMath.luau    character power, drop power, combat scaling
    Weapons/WeaponStats     item rolls → fire rate, damage, spread, recoil...
    World/                  LightingPresets (per-map lighting), Motion (mover/laser timing)
    Net/                    Remotes (definitions), Guard (argument validation)
    Util/                   Signal, TableUtil, RateLimiter, TimeUtil
    Types.luau              shared type definitions (ProfileData, ItemInstance, ...)
  server/                   ServerScriptService
    Main.server.luau        validates configs, starts services
    Services/               Net, Data, World, Hub, Character, Projectile, Enemy, Combat,
                            Weapon, Loot, Inventory, Mission, Activity, Debug
    Missions/               the zone runner's parts: Steps, Spawner (waves), Gates,
                            BossFight (phases, attacks, raid scripts), MapMarkers, MissionKit
    MapBuilders/            MapKit, Props, Generate + a builder per map (see MAPS.md)
    Enemies/EnemyRigs       enemy models (humanoids, drones, turrets, objects)
    Weapons/WeaponModels    part-built gun models held in the right hand
    Combat/CombatContext    per-player power/activity context for damage
    Data/                   ProfileStore (session locking), MockDataStore,
                            ProfileTemplate, Migrations, Resets
  client/                   StarterPlayerScripts
    Main.client.luau        starts controllers
    Controllers/            Data, Activity, Loading, Camera, Intro, Effects, Weapon,
                            Music, Hud, Waypoint, KillFeed, Cue (mission effects),
                            WorldMotion, Area, Flashlight, Director, Inventory, Loot,
                            DevCommand, DebugPanel
    Net/ClientNet.luau      client side of the remotes
    UI/                     Theme, UI helpers, UIState (open menus, death, cutscenes)
  character/                StarterCharacterScripts (replaces default health regen)
  gui/                      StarterGui ScreenGui shells
tests/                      Lune test runner, harness and specs
scripts/                    install-tools / analyze / check
DESIGN.md                   architecture, power math, loot, activities, adding content
TESTING.md                  the Studio test guide
MAPS.md                     building and hand-editing maps, every map's markers
```

## Balancing

All tuning lives in `src/shared/Config`. Logic code never hard-codes a number that a
designer would want to change. To rebalance, edit a config module, then run
`lune run tests/run`. The config tests and the validator catch broken references,
such as a weapon using an unknown perk or a mission pointing at a missing boss.
[DESIGN.md](DESIGN.md) explains the math and walks through adding a new weapon,
mission or enemy.

## Maps

Maps are built from parts and Terrain in code (`src/server/MapBuilders`), so nothing needs
importing. To look at one in Studio, paste this in the command bar (**View → Command Bar**):

```lua
require(game.ServerScriptService.MapBuilders.Generate)("FirstLight")
-- or "Hub", "SunkenRelay", "HollowDark", "HollowSpire", "VaultOfEchoes"
```

It builds the map into Workspace with its terrain and selects it. For the bare Model, use
`require(game.ServerScriptService.MapBuilders.FirstLightBuilder).Build()`.
[MAPS.md](MAPS.md) explains how to keep a hand-edited version, which maps are worth
editing, and where every marker is.

## Assets

The game ships without third-party assets. Every sound, image and place id is a
placeholder (`0`) in `src/shared/Config/AssetIds.luau`. Placeholder sounds are skipped,
placeholder loading art is drawn in the map's colors, and Studio's zone panel shows the
music state so you can test without audio. Replace them only with assets you own or
free-to-use Creator Store items. The only real ids are Roblox's own default character
animations (idle, walk, run, tool hold).

The placeholders to fill in (104):

| Group | Keys |
|-------|------|
| `Sounds.Music` | `Hub`, `Explore`, `Combat`, `Boss` (looping), `Victory` (once) |
| `Sounds.Ambient` | `HubWind`, `HubCrowd`, `HubShips` (looping hub ambience) |
| `Sounds.Weapons.<Type>` | `Fire` and `Reload` for AutoRifle, PulseRifle, ScoutRifle, HandCannon, SMG, Sidearm, Shotgun, SniperRifle, MachineGun; FusionRifle adds `Charge`; GrenadeLauncher and RocketLauncher add `Explode`; Sword has `Swing` and `Hit` |
| `Sounds.Combat` | `HitMarker`, `CritMarker`, `KillConfirm`, `ShieldBreak`, `PlayerHurt`, `EnemyFire`, `EnemyMelee`, `Explosion`, `AmmoPickup`, `Death`, `Revive`, `Portal`, `Dropship`, `GateOpen`, `SniperCharge`, `BossSlam`, `BossDeath` |
| `Sounds.UI` | `Click`, `Hover`, `LootRare`, `LootEpic`, `LootLegendary`, `LootExotic`, `PowerUp` |
| `Images.Loading` | `Default`, `Hub`, `FirstLight`, `SunkenRelay`, `HollowDark`, `HollowSpire`, `VaultOfEchoes` (loading screen art, 16:9) |
| `Images.HubSky` | `Bk`, `Dn`, `Ft`, `Lf`, `Rt`, `Up` (hub skybox faces; 0 keeps Roblox's default sky) |
| `Images.Currencies` | `Quanta`, `Alloy`, `Fluxite`, `Starglass` |
| `Images.Elements` | `Kinetic`, `Flare`, `Storm`, `Null` |
| `Images.Classes` | `Bulwark`, `Ranger`, `Mystic` |
| `Images.Ammo` | `Primary`, `Special`, `Heavy` |
| `Images.Rarity` | `Rare`, `Epic`, `Legendary`, `Exotic` |
| `Images` | `PowerIcon`, `Crosshair` |
| `Places` | `Hub`, `Mission`, `PatrolVeyra`, `PatrolHollowmere`, `PatrolKessler`, `PatrolSolace`, `Strike`, `Dungeon`, `Raid`, `PvP` (only used with `USE_RESERVED_SERVERS`; activities run in the current place by default) |

To use your own models instead of the part-built ones:

- **Guns:** a Model in `ServerStorage.WeaponModels` named after the weapon's `Model`
  field (e.g. `AutoRifle_Frontier`), with its PrimaryPart at the grip and a `Muzzle`
  attachment at the barrel tip.
- **Enemies:** a rig in `ServerStorage.EnemyModels` named after the enemy's `Model`
  field, with a Humanoid, HumanoidRootPart and Head.
- **Maps:** see [MAPS.md](MAPS.md).

## Roadmap

| Phase | Scope | Status |
|------:|-------|--------|
| 1 | Rojo setup, folder structure, config modules, data saving | ✅ done |
| 2 | Playable vertical slice: hub, guns + range, HUD, enemies, a story mission, Nightfall, raid encounter 1, loot + power, character screen, Director, dev commands | ✅ done |
| 3 | Look great and feel complete: the Spire hub, full inventory, 13 weapon archetypes, MissionService (zones, waves, gates, bosses), three story missions, the Hollow Spire Nightfall with medals, the full Vault of Echoes raid, and polish (intros, loading, waypoints, music, kill feed, Mission Complete) | ✅ done |
| next | Real art and audio in `AssetIds`, perk effects and masterworks, vendors and bounties, classes and abilities, the remaining story missions, patrols and strikes, the dungeon, PvP, reserved-server teleports, balancing and an anti-exploit review | |
