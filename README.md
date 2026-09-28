# LAST LIGHT

A sci-fi co-op looter shooter for Roblox, written in strict Luau and synced with
[Rojo](https://rojo.space). The progression systems take their cues from the genre
(power levels and caps, Powerful and Pinnacle weekly rewards, rarity tiers, rolled
perks, strikes, a raid, a social hub). Every name, piece of lore and asset in the
game is original.

> **Status: playable vertical slice.** Phase 1 (setup, configs, saving) is done, and
> Phase 2 made the game playable from end to end: hub, three working guns, a
> shooting range, enemies, a story mission, a Nightfall, the first raid encounter,
> loot and power. See [Roadmap](#roadmap).

## Quick try (no tools needed)

1. Install [Roblox Studio](https://create.roblox.com/) and log in.
2. Download the latest place file: on GitHub open **Actions**, click the most recent
   green **CI** run, and download the **LastLight-place** artifact (a zip containing
   `LastLight.rbxl`). Unzip it.
3. Double-click `LastLight.rbxl`, or open it in Studio with **File → Open from File**.
4. Press **Play**, then follow [Playing the vertical slice](#playing-the-vertical-slice).

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

## Playing the vertical slice

### Controls

| Key | Action |
|-----|--------|
| Mouse | look around (the mouse is locked to the screen center while playing) |
| Left click | fire (hold for the auto rifle) |
| Right click | aim down sights (zoom, tighter spread) |
| R | reload |
| 1 / 2 / 3 or mouse wheel | kinetic / energy / heavy weapon |
| M | the Director (launch activities, join fireteams, leave an activity) |
| Tab or I | character screen (equip and dismantle gear, live power) |
| E | interact / hold to revive a teammate's ghost in the raid |
| F2 | developer panel (Studio and the game owner only) |
| Space | close the loot screen |

Gamepad: R2 fire, L2 aim, X reload, Y swap weapon, D-pad up Director, View button
character screen. Touch devices get on-screen FIRE, AIM, R and SWAP buttons.

### Step by step

1. **Hub.** Press **Play**. You spawn on the plaza at dusk holding the starter auto
   rifle. The HUD shows shields (blue) and health (white) at the bottom, power (✦ 350)
   above them, and ammo at the bottom right. Old Phase 1 saves get the new starter
   hand cannon added and equipped automatically.
2. **Guns and the range.** Walk to the SHOOTING RANGE sign, west of the plaza (the
   merchant row with the vendor NPCs is to the east). Three dummies stand at 15, 30
   and 55 studs; the far one has a Flare shield. Shoot them: white numbers are body
   shots, yellow numbers are headshots, blue numbers hit a shield. Switch weapons with
   1/2/3: the hand cannon hits hard with a big headshot bonus, and the rocket launcher
   (1 in the tube + 2 spare) explodes. Dummies heal 3 seconds after you stop.
3. **Character screen.** Press **Tab**. You see the three weapon slots and five armor
   slots with the equipped item on top. Click another item to equip it; the small **x**
   dismantles it.
4. **The Director.** Press **M**, or walk up to the big glowing terminal north of the
   plaza and click it or press **E**. Cards show each activity's recommended power
   (your power turns red when you're below it), difficulties, this week's modifiers, rewards and whether the weekly
   reward is still available. The Nightfall unlocks after you finish First Light; the
   raid unlocks at power 480.
5. **Story: First Light (350).** Launch it. You're moved to a copy of the map far from
   the hub. Follow the objective tracker on the left and the ◆ waypoint:
   reach the outpost → clear the courtyard (0/12) → stand in the ring to hack the
   terminal for 20 seconds while waves attack → defeat Vulk, the Scrap Baron (boss bar
   at the top; he calls adds at half health). If you die, the screen turns grey and you
   respawn at the last checkpoint after 5 seconds. Enemies (mostly majors and bosses)
   can drop purple **heavy ammo** boxes: walk over them.
6. **Rewards.** When the boss dies the loot screen shows 2-3 Rare/Epic drops, each
   +0 to +5 over your power, colored by rarity. Press **Equip upgrades**, then check the
   new power at the bottom of the HUD. After 12 seconds you're back in the hub, and
   everything is saved.
7. **Nightfall: Hollow Spire (450 / 470 / 490).** Pick Adept, Hero or Legend in the
   Director. Two weekly modifiers apply (listed on the card and on the HUD), a timer and
   score run, and power advantage doesn't count (contest mode). Kaldrek becomes immune at
   half health until his bodyguard is dead. The first clear each week gives a Powerful
   reward; Legend also gives a Pinnacle. To try it without the grind: `/setpower 450`,
   then `/launch nightfall adept` (skips the First Light unlock).
8. **Raid: Vault of Echoes, encounter 1 (495).** Needs power 480: `/setpower 490`,
   then launch it from the Director or with `/launch raid`.
   Harrowmaw is immune. Stand on the glowing echo plates: with a fireteam, as many
   Keepers as there are players (up to 3) must hold plates at the same time for 3
   seconds; solo, hold one plate for 5 seconds. That opens a 20-second damage phase with
   +25% damage. Adds arrive every 25 seconds, and at 6 minutes the engine enrages and
   wipes the team. In a fireteam a dead Keeper leaves a ghost (hold **E** for 3 seconds
   to revive); if everyone is down, the encounter restarts. Solo, you respawn after 10
   seconds. Clearing it pays a Pinnacle once a week (+1/+2 power), plus a 15% chance of
   a raid-exclusive Legendary.
9. **Multiplayer.** In Studio, **Test → Clients and Servers** with 2+ players. One player
   launches; the others open the Director and press **Join** on the active fireteam.

### Developer chat commands

Type these in chat (Studio, or the game's owner in a live server):

| Command | What it does |
|---------|--------------|
| `/setpower 480` | sets every equipped item to that power |
| `/give W_LAST_EMBER` | rolls a weapon or armor piece (id or part of its name) at your power and equips it |
| `/launch story` · `/launch nightfall legend` · `/launch raid` | launches, ignoring locks |
| `/god` | toggles taking no damage |
| `/resetweek` | resets weekly rewards so Powerful/Pinnacle drop again |
| `/wipe` | wipes your save back to a new 350 character |
| `/skip` | skips the current objective |
| `/heavy` | drops a heavy ammo box in front of you |
| `/kill` | kills you (to test respawns) |
| `/leave` | returns you to the hub |
| `/help` | lists the commands |

Prefer clicking? Press **F2** for the developer panel (it frees the mouse while open).
Besides the Phase 1 buttons (currencies, random loot, save now, resets) it has
**Power 450/490**, **Launch Story/Nightfall/Raid**, **Skip Objective**, **God Mode**,
**Heavy Ammo** and **Leave Activity**.

### Checking saves (Phase 1)

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
  models and every client screen are built with Lune's real Roblox Instances, which
  reject unknown properties. `Activity.spec` runs ActivityService against fake
  services on a virtual clock: the story mission start to finish, Nightfall immunity,
  raid plates, damage phases, revives, wipes and enrage.
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
    Config/                 ALL game data: power, rarity, weapons, perks, armor, classes,
                            activities, enemies, combat, world/lighting, loot, economy...
    ConfigValidator.luau    cross-checks every config at server start
    Activities/             ActivityRules (unlocks, difficulties, weekly modifiers)
    Combat/DamageMath.luau  falloff, precision, shields, splash
    Items/                  ItemCatalog, ItemRoller, LootRoller, Inventory
    Power/PowerMath.luau    character power, drop power, combat scaling
    Weapons/WeaponStats     item rolls → fire rate, damage, spread, recoil...
    World/LightingPresets   per-map lighting
    Net/                    Remotes (definitions), Guard (argument validation)
    Util/                   Signal, TableUtil, RateLimiter, TimeUtil
    Types.luau              shared type definitions (ProfileData, ItemInstance, ...)
  server/                   ServerScriptService
    Main.server.luau        validates configs, starts services
    Services/               Net, Data, World, Character, Projectile, Enemy, Combat,
                            Weapon, Loot, Inventory, Activity, Debug
    Maps/                   MapKit + the hub and three activity maps, built in code
    Enemies/EnemyRigs       enemy models (R15 from a HumanoidDescription, or blocky)
    Weapons/WeaponModels    part-built gun models held in the right hand
    Combat/CombatContext    per-player power/activity context for damage
    Data/                   ProfileStore (session locking), MockDataStore,
                            ProfileTemplate, Migrations, Resets
  client/                   StarterPlayerScripts
    Main.client.luau        starts controllers
    Controllers/            Data, Activity, Camera, Effects, Weapon, Hud, Director,
                            CharacterScreen, Loot, DevCommand, DebugPanel
    Net/ClientNet.luau      client side of the remotes
    UI/                     Theme, UI helpers, UIState (open menus, death)
  character/                StarterCharacterScripts (replaces default health regen)
  gui/                      StarterGui ScreenGui shells
tests/                      Lune test runner, harness and specs
scripts/                    install-tools / analyze / check
DESIGN.md                   architecture, power math, loot, activities, adding content
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
placeholder (`0`) in `src/shared/Config/AssetIds.luau`; placeholder sounds are simply
skipped. Replace them only with assets you own or free-to-use Creator Store items. The
only real ids are Roblox's own default character animations (idle, walk, tool hold).

Maps, guns and enemies are built from parts in code, so nothing needs importing. To use
your own art:

- **Guns:** a Model in `ServerStorage.WeaponModels` named after the weapon's `Model`
  field (e.g. `AutoRifle_Frontier`), with its PrimaryPart at the grip and a `Muzzle`
  attachment at the barrel tip.
- **Enemies:** a rig in `ServerStorage.EnemyModels` named after the enemy's `Model`
  field, with a Humanoid, HumanoidRootPart and Head.
- **Maps:** put a Model in `ServerStorage.Activities` named `FirstLight`, `HollowSpire`
  or `VaultOfEchoes` (or a `Hub` Model in Workspace) and it replaces the generated one.
  Keep the marker parts it needs (see DESIGN.md, "Maps").

## Roadmap

The original plan had 11 phases. Phase 2 jumped ahead to a playable slice, pulling in
parts of phases 3-8 and 10, so the remaining phases now build on working systems.

| Phase | Scope | Status |
|------:|-------|--------|
| 1 | Rojo setup, folder structure, config modules, data saving | ✅ done |
| 2 | Playable vertical slice: hub, 3 guns + range, HUD, one enemy faction, story mission, Nightfall, raid encounter 1, loot + power, character screen, Director, dev commands | ✅ done |
| 3 | Full loot loop: vault, postmaster screen, infusion, masterworks, perk effects in combat | next |
| 4 | More enemy types and factions (Veiled, Concord), flying enemies, grenades | |
| 5 | Vendors, bounties, currencies in the UI, reserved-server teleports | |
| 6 | More story missions and patrol zones | |
| 7 | Milestone screen, weekly challenges, artifact | |
| 8 | Strike playlist, Nightfall rotation | |
| 9 | Classes, abilities, subclasses | |
| 10 | Dungeon and raid encounters 2-3 | |
| 11 | Polish, VFX, audio, balancing, anti-exploit review | |
