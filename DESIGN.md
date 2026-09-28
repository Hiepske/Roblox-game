# LAST LIGHT: Design Notes

This document covers how the systems fit together, the power and loot math, and
how to add content. Every number quoted here comes from a config module in
`src/shared/Config`. If this document and a config disagree, the config wins.

## 1. Architecture

**The server is authoritative.** Damage, drops, power, currency and saving all
happen on the server. A client only sends *intents* ("equip this uid", "fire at
this ray") through remotes, and the server validates every one.

```
Client (StarterPlayerScripts)            Server (ServerScriptService)
  Controllers ── ClientNet ──remotes──►  NetService ─► Services
      ▲                                     │ rate limit, arg checks, suspicion
      └──── DataSnapshot / DataChanged ◄────┘ DataService (owns saved data)
Shared (ReplicatedStorage.Shared): Config, Types, PowerMath, ItemRoller, Util
```

Server services, in start order (later ones may use earlier ones):

| Service | Owns |
|---------|------|
| NetService | remotes, validation, rate limits |
| DataService | saved data, replication to the owner |
| WorldService | hub + activity map templates, runtime folders, lighting |
| CharacterService | spawning, shields/health, damage to players, death, respawn timing |
| ProjectileService | server-simulated projectiles (enemy bolts, rockets) |
| EnemyService | enemy rigs, AI, health/shields, immunity, death |
| CombatService | player → enemy damage pipeline, hit feedback |
| WeaponService | loadouts, ammo, fire/reload/swap validation, gun models |
| LootService | drops, ammo boxes, weekly milestones, activity rewards |
| InventoryService | equip and dismantle |
| MissionService | the zone flow of every activity: zones, steps, waves, gates, checkpoints, boss fights, the loot chest (helpers in `server/Missions`) |
| ActivityService | activity instances (map copy + terrain), players, deaths, wipes, rewards, the Director |
| DebugService | developer commands |

Cycles are avoided with injection: ActivityService installs resolvers into
CharacterService (what happens on death, where to respawn), CombatContext (power and
modifiers for damage) and LootService (which activity an enemy belonged to), and
listens to signals (`EnemyKilled`, `CharacterSpawned`, `PlayerDied`). A player's
activity is the `InstanceId` attribute on the Player (nil in the hub).

- **Services** live in `src/server/Services`. Each has `Init()` (create remotes and
  connect handlers, never yields) and `Start()` (begin loops). `Main.server.luau`
  runs `ConfigValidator` first, then initializes services in a fixed order.
- **Controllers** live in `src/client/Controllers` and follow the same Init/Start pattern.
- **Remotes** are declared once in `Shared/Net/Remotes.luau` with a direction and a
  rate limit. NetService creates them and enforces these rules:
  - every client→server remote needs a per-player token-bucket `RateLimit`
  - arguments are checked with `Guard` validators; wrong types, NaN or infinite
    numbers, oversized strings and extra arguments are rejected
  - a client firing a server→client remote is flagged
  - RemoteFunctions only run client→server, so the server never waits on a client
  - suspicion points decay over time; above `GameConfig.Security.KickThreshold`
    the player is kicked
- **Pure logic** (PowerMath, ItemRoller, Inventory, TimeUtil, Migrations, Resets,
  ProfileStore) touches no engine services. Its dependencies are injected, which is
  what lets the Lune tests run it outside Studio.

## 2. Player data

### Schema (`Types.ProfileData`, version 1)

| Field | Contents |
|-------|----------|
| `SchemaVersion` | data format version (see Migrations) |
| `Class`, `Subclasses` | chosen class; selected subclass per class |
| `Items` | every owned item keyed by `Uid`, whether on the character, in the vault or at the postmaster |
| `Equipped` | gear slot → `Uid` (3 weapon slots and 5 armor slots) |
| `Currencies` | Quanta, Alloy, Fluxite, Starglass |
| `Progress` | story completions, activity clear counts, unlock flags |
| `Weekly` / `Daily` | the reset each block belongs to, claimed Powerful/Pinnacle rewards, milestone progress |
| `Bounties.Active` | held bounties with progress and expiry |
| `Artifact` | seasonal artifact level and XP |
| `Lifetime` | highest power reached, kills, playtime, ... |
| `Settings` | sensitivity, FOV, invert-Y, keybind overrides |
| `Flags` | one-off flags such as `StarterLoadoutGranted` |

An `ItemInstance` stores everything about its roll (`DefId`, `Rarity`, `Slot`,
`Power`, rolled `Stats`, `Perks` in column order, `Masterwork`, `Location`, `Locked`),
so rebalancing a def never changes items players already own.

### Session locking (`Data/ProfileStore.luau`)

A player hopping servers (teleporting to an activity, or rejoining after a crash)
can briefly have two servers holding their data. Without protection, that causes
rollbacks and item dupes. ProfileStore prevents both:

1. **Load**: `UpdateAsync` claims `Meta.ActiveSession = this server`. If another live
   server owns the record, we write `Meta.ForceLoadSession` (a request to let go)
   and retry every `LoadRetryDelay` seconds.
2. **The owner's next save** sees that request, writes its data one last time, clears
   the lock, and kicks the player from the old server. The new server then gets the
   freshest data.
3. **A crashed owner** stops refreshing `LastUpdate`. After `SessionStaleSeconds` the
   lock counts as dead. From attempt `StealAfterAttempts` on, the lock is taken
   anyway, so nobody gets stuck.
4. **Every save re-checks ownership** inside `UpdateAsync`. A server that lost the
   lock never writes again; it marks the profile `SessionLost` and kicks the player.
5. A stored value that isn't a profile record is **never overwritten**; the load fails instead.
6. In Studio, data is validated before every write (no NaN, functions, mixed tables
   or cycles), and invalid data is refused instead of being silently mangled.

DataService autosaves each profile every `AutosaveInterval` (60 s), saves and
releases when a player leaves, and on `BindToClose` releases every profile and
waits up to `ShutdownTimeout`. Saves go through `waitForBudget`, which respects
DataStore request budgets.

### Loading pipeline (`DataService.prepareData`)

```
load record → Migrations.Run → TableUtil.Reconcile(template) → ProfileTemplate.Sanitize
            → grant starter loadout if missing → Resets.Apply → send DataSnapshot
```

- **Migrations**: `Steps[n]` upgrades version n to n+1. Data from a *newer* build is
  never loaded. The player gets "please rejoin" and the save is left untouched, so
  an old server in a rolling update can't wipe new fields.
- **Reconcile** copies fields added to `ProfileTemplate` into older saves. New fields
  therefore don't need a migration; renames and reshapes do.
- **Sanitize** repairs bad data: equips that point at missing or wrong-slot items,
  more than one exotic per category, class-locked armor on the wrong class, NaN or
  out-of-cap currencies, and unknown classes.

**Adding a field:** add it to `Types.ProfileData` and `ProfileTemplate.buildTemplate`.
Only if you rename, move or reshape existing data: bump `Migrations.CurrentVersion`
and add a step.

### Replication

The server sends a full `DataSnapshot` on load, then `DataChanged(path, value)` for
each change made through `DataService.Set` and its helpers (`AddCurrency`, `Spend`,
`GiveItem`, `RemoveItem`). Updates are path-based, so granting one item sends one
item, not the whole inventory. Clients read their replica through `DataController`.

## 3. Power math (`Power/PowerMath.luau`, `Config/PowerConfig.luau`)

| Stage | Range | What raises power |
|-------|-------|-------------------|
| Starting | 350 | new character (starter loadout, all 350) |
| Soft cap | 350 → 450 | any drop |
| Powerful cap | 450 → 490 | only Powerful rewards |
| Pinnacle cap | 490 → 500 | only Pinnacle rewards |

- **Character power** = `floor(sum of the 8 equipped items' power / 8)`. An empty slot counts as 0.
- **Highest possible power** uses the best item per slot across the character, vault
  and postmaster, with at most one exotic weapon and one exotic armor piece (the
  same rule as equipping). All drops are rolled relative to this number, so
  un-equipped gear still counts.

### Drop power (`PowerMath.RollDropPower(highest, kind, tier, rng)`)

| Reward kind | Below 450 | 450 – 489 | 490 – 500 |
|-------------|-----------|-----------|-----------|
| **World** (enemies, chests, story, patrol) | +0…+5, max 450 | at current power ¹ | at current power ¹ |
| **Powerful** tier 1 / 2 / 3 | +3 / +4 / +5 | +3 / +4 / +5, max 490 | at current power |
| **Pinnacle** | best of +5 (max 490) and +1…+2 | same | +1…+2, max 500 |

¹ `PowerConfig.World.AboveSoftCap = "AtCurrent"`: once past the soft cap, world
drops come at your current power. They are never junk, but they never raise power.
Set it to `"AtSoftCap"` to make them drop at exactly 450 instead.

Examples (these are also unit tests): a world drop at 448 gives 448–450; a Tier 2
Powerful at 455 gives 459; a Pinnacle at 460 gives 465; a Pinnacle at 499 gives 500.

Powerful and Pinnacle sources pay out once per weekly reset (Tuesday 17:00 UTC,
`GameConfig.Resets`). Claims are tracked in `ProfileData.Weekly.ClaimedRewards`
and cleared by `Resets.Apply`. The sources themselves are listed in `MilestoneConfig`.

### Activity power gap

`delta = (character power + artifact bonus) − activity recommended power`, clamped
to the ends of the curve and optionally capped per activity (`PowerDeltaCap = 0`
means being over-leveled gives no advantage; used by the hardened strike, dungeon
and raid).

| delta | −50 | −30 | −20 | −10 | −5 | 0 | +10 | +20 |
|-------|-----|-----|-----|-----|----|---|-----|-----|
| damage dealt × | 0.30 | 0.50 | 0.65 | 0.82 | 0.91 | 1.00 | 1.06 | 1.10 |
| damage taken × | 3.00 | 2.00 | 1.60 | 1.25 | 1.10 | 1.00 | 0.92 | 0.88 |

Values between points are linearly interpolated. PvP sets `PowerEnabled = false`,
which makes both multipliers 1.

Enemies are also sturdier in higher activities, whatever the player's power:
health × `1 + 0.004 × (activity power − 350)` and damage × `1 + 0.003 × (…)`.
At activity power 500 that is 1.6× health and 1.45× damage.

### Artifact and infusion

- **Artifact**: +1 combat power per level (`PowerConfig.Artifact`). It is separate
  from gear power and can go past 500, but it is only used in combat math. XP for
  level n is `BaseXp + (n − 1) × XpGrowth`.
- **Infusion**: the target keeps its roll and takes the fodder's power
  (`max(target, fodder)`). The fodder is destroyed. Costs are in
  `EconomyConfig.Infusion`, by the target's rarity.

## 4. Loot

### Rarity (`RarityConfig`)

| Rarity | Color | Weapon perks | Weapon stat roll | Armor stat total | Masterwork |
|--------|-------|--------------|------------------|------------------|------------|
| Rare | blue | 1 random trait | base −15…+5 | 34–46 | – |
| Epic | purple | Trait1 + Trait2 | base −10…+8 | 42–54 | – |
| Legendary | gold | Barrel + Magazine + Trait1 + Trait2 | base −6…+10 | 50–64 | rolled on drop |
| Exotic | yellow | fixed signature perk set | base +0…+6 | 56–68 | via Gunsmith |

Only **one exotic weapon and one exotic armor piece** can be equipped at a time.

A weapon stat is `archetype base (WeaponTypeConfig) + weapon StatBias + rarity roll`,
clamped to 0–100. Low rolls are deliberate: they are the trash worth dismantling.
Armor rolls a total and spreads it over the six stats (each 2–30). A set's
`StatFocus` stats are twice as likely to receive points.

**God rolls**: `PerkConfig.Synergies` lists Trait1 + Trait2 pairs that play well
together. `ItemRoller.IsGodRoll` is true for a synergy pair on a top-quartile stat
roll (`RollQuality >= 0.75`).

### Drop tables (`LootConfig`)

| Source | Rare | Epic | Legendary | Exotic chance | Armor chance |
|--------|------|------|-----------|---------------|--------------|
| World | 70 | 25 | 5 | 0.2% | 50% |
| Story | 45 | 45 | 10 | 1% | 40% |
| Patrol | 50 | 40 | 10 | 0.5% | 50% |
| Strike | 10 | 50 | 40 | 2% | 50% |
| Hardened strike | – | 30 | 70 | 5% | 40% |
| Dungeon | – | – | 100 | 5% | 50% |
| Raid | – | – | 100 | 8% | 50% |
| PvP | – | 50 | 50 | 1% | 40% |

Enemies drop gear with a 2% (Minor), 10% (Major) or 100% (Boss) chance. A drop picks
a def whose `Sources` contain the source's `PoolTag`, rolls its rarity from the
weights above, and gets its power from `RollDropPower`.

### Economy (`EconomyConfig`)

Dismantling gives Quanta, plus Alloy for Epic and above, a 25% Fluxite chance for
Legendary, and Starglass for Exotic. Default capacities are 9 spare items per gear
slot on the character, a vault of 200 and a postmaster of 21. When a slot is full,
drops go to the postmaster (`Inventory.ResolveDropLocation`).

## 5. Combat

### Weapons (`Weapons/WeaponStats.luau`, `WeaponTypeConfig`, `CombatConfig.WeaponStats`)

`WeaponStats.Compute(item)` turns a rolled weapon into combat numbers: the archetype's
base damage, RPM, magazine, reload/swap time and range, adjusted by the item's rolled
stats (Impact → damage, Range → falloff distance, Stability → recoil, Handling →
swap time, Reload → reload time) after perk stat modifiers and the masterwork. Primary ammo is
infinite; heavy weapons carry `Reserves` and start each activity with
`CombatConfig.Weapons.HeavyStartingReserve` spare rounds.

A shot, end to end:

1. The client (`WeaponController`) checks fire rate, magazine and reload locally for
   responsiveness, casts a ray from the camera through the crosshair (with spread),
   and sends `WeaponFire(slot, aimPoint, shotId)`. It draws its own tracer, flash and
   recoil immediately.
2. The server (`WeaponService`) re-checks the active slot, swap and reload timers,
   the fire interval (× `FireRateTolerance`, faster fire is flagged) and the magazine,
   then raycasts from the character's **head** toward the aim point, ignoring
   player characters. Rockets become server projectiles instead.
3. `CombatService` computes damage (below), applies it through `EnemyService`, and
   sends the shooter `CombatFeedback` (damage number + hit marker). Other players get
   `ShotEffect` so they see the tracer.

### Damage (`Combat/DamageMath.luau`)

```
damage = base × falloff(distance) × precision(if headshot, capped by enemy CritSpot)
       × outgoing power multiplier × (1 + surge) × damage buff
```

The outgoing/incoming power multipliers come from `PowerMath.CombatMultipliers` with
the player's `CombatContext` (character power, activity power, delta cap). In the hub
activity power = your own power, so the range shows raw weapon damage. Shields absorb
damage first; a weapon matching the shield's element does bonus shield damage and
bursts it (splash to nearby enemies); overflow carries into health. Kinetic weapons
do reduced shield damage but a bonus against unshielded targets. Under the Match Game
modifier, only the matching element damages a shield at all.

### Players (`CharacterService`, `CombatConfig.Player`)

Shields (class value) then health. After `ShieldRegenDelay` (4 s) without damage the
shield refills, then health. Incoming damage × the incoming power multiplier × (1 −
Fortitude reduction). The default Roblox health regen is replaced by an empty script.

## 6. Enemies (`EnemyService`, `EnemyConfig`, `Enemies/EnemyRigs.luau`)

Rigs are R15 models made from a HumanoidDescription colored per faction, decorated
with parts (glowing eyes, helmet, shoulder pads, gun or blades, shield pack), scaled
by `Scale`, and put in the `Enemies` collision group. Headshots are the head and
anything named `Eye`/`Helmet`/`Crown`. If R15 creation fails a blocky R6 rig is built.
Machines are built from parts with an anchored root (model attribute `Rig`): drones
(`Flying` role) are orbs with rotors, turrets (`Turret`) sit on tripods, objects
(`Object`: generators, pylons) are frames around a glowing core. Their `Head` (eye,
sensor or core) is the crit spot.

AI runs on the server every `CombatConfig.Enemies.TickInterval`:

| State | Behavior |
|-------|----------|
| Idle | no player of the same instance within `AggroRange` |
| Alert | just noticed someone: short pause, turns to face them |
| Chase | direct `MoveTo` with line of sight, PathfindingService without |
| Attack | ranged: strafe and fire dodgeable bolts (bosses fire volleys); melee: wind up, then hit if still in reach |
| Cover | ranged units hurt below half health run to a spot the target can't see |

Roles with their own brains: **drones** circle their target at `PreferredRange`,
hovering `DroneHover` studs up, moved every frame and firing bolts; **snipers** paint
you with a red laser (a beam to a dot on you) that tracks for `SniperWindup` s, locks
for the last `SniperLock` s, then fires one fast, heavy shot (step out of the beam);
**turrets** swivel and fire `TurretBurst`-round bursts; **objects** do nothing.
Boss scripts can pause the AI (`SetBusy`), move bosses (`Relocate`, `Leap`), fire
volleys (`FireVolley`) and set a health floor so damage can't skip an immune phase.

Health and damage scale with the activity's recommended power
(`PowerMath.ActivityEnemyScale`), modifiers (Ironhide, Bloodlust, Overcharged
Shields) and fireteam size (`CombatConfig.PartyScaling`: +25% health per extra
player for regular enemies, +60% for bosses, and +35% more enemies per wave). Health bars are BillboardGuis: red minors, yellow majors and
bosses with name and title, and `[IMMUNE]` when immune. Dummies never die and refill
after 3 seconds.

## 7. Activities (`ActivityService`, `MissionService`, `ActivityConfig`, `BossConfig`)

### Instances

With `GameConfig.Activities.USE_RESERVED_SERVERS = false` (default, works in Studio)
each launch clones the map template from `ServerStorage.Activities` into
`Workspace.Instances` at `X = InstanceSpacing × slot` (5000, 10000, ...; up to
`MaxInstances`), fills in the map's terrain there (`MapKit.ApplyTerrain`), tags
players with `InstanceId`, and teleports them to `PlayerStart`. Enemies, projectiles,
ammo boxes and damage only interact within one instance. When everyone leaves or
`ReturnToHubDelay` passes after completion, the terrain is cleared and the copy is
destroyed. With the flag on, `Launch` reserves a server for
`AssetIds.Places[activity.Place]` and teleports the player with
`{ ActivityId, DifficultyId }` as teleport data; the reserved server launches or joins
that activity when the player arrives.

The HUD reads live state from attributes on `ReplicatedStorage.LiveRuns.<runId>`:
`ObjectiveText/Count/Progress`, `Waypoint`, `Wave`, `ZoneName/ZoneIndex/ZoneCount/
ZoneStartedAt/ZoneLog`, `BossName/Health/Shield/Immune/Thresholds`, `Phase`,
`PhaseEndsAt`, `Charge`, `EnrageAt`, `Score`, `StartedAt`, `Status`, `ReturnAt`,
`Elapsed`, `Kills_<userId>`/`Deaths_<userId>`.

### Zones (`MissionService`, `MissionRules.ZoneList`)

Every playable activity is a list of **zones** (raids: each playable encounter's
zones, in order). Entering a zone moves the respawn checkpoint to its `Checkpoint`
(default: the marker `CP_<zone Id>`) and pops its `Name` up on screen; clearing it
logs its time (the Studio HUD lists every zone's time), opens its gate (`Gate`,
default `Gate_<zone Id>`: a Door slides up, a Shield fades, a Bridge turns solid) and,
for the last zone of a raid encounter, records the encounter as cleared. Falling below
the map's `KillY` attribute puts you back at the checkpoint (jumping puzzles).

A zone's **steps** run in order (`server/Missions/Steps.luau`):

| Kind | Completes when |
|------|----------------|
| Travel | a living player is inside the `Target` marker box |
| Waves | every wave is dead; the next wave comes when `Advance` (0.8) of the current one is down or after `Timer` (45) s, and waits while `Missions.MaxAlive` enemies live |
| Defend | players have stood in `Target` for `Duration` s (paused while it's empty); waves keep coming every `WaveInterval` |
| Survive | `Duration` s have passed with someone alive; waves keep coming |
| Destroy | the `Count` objects (default Shield Generator) at markers `<Target>_1..n` are destroyed; waves keep coming |
| Interact | someone held E at the `Target` console |
| Boss | the boss is dead (below) |

Waves (`Wave({ ENEMY_ID = count }, arrival?, spawnsFolder?)`) spawn at the
`EnemySpawns/<Spawns>` markers (default folder: the zone's Id), preferring points no
player can see and at least `SpawnMinDistance` away. **Portal** waves step out of
rifts after `PortalDelay`; **Dropship** waves are dropped from a ship that flies in
over one point (`DropshipDelay`); **Ambush** waves appear silently. Counts are for one
player and grow with the fireteam.

### Bosses (`BossConfig`, `server/Missions/BossFight.luau`)

Boss health is 15-30 captains (`EnemyConfig.CaptainHealth` = a Rustbreaker), checked
by the validator. The HUD shows a big bar with ticks at the immune thresholds.

- **Immune phases** at each `Immune[].At` (0.66, 0.33): damage can't push the boss
  past the threshold; there it raises a shield bubble until the break is done
  (`Adds`: kill `Waves` waves of `Enemies`; `Pylons`: destroy the object enemies at
  `Pylon_1..n`). `Collapse` makes part of the floor flash and fall.
- **Attacks** on cooldowns, only one at a time: `Barrage` (wind-up glow, then a spray
  of bolts at everyone), `Slam` (a red circle under a player fills up for `Windup` s,
  then the boss leaps onto it), `Teleport` (to `Teleport_n`), `Nova` (only the lit
  `Safe_n` circles survive).
- **Adds** trickle in every `Adds.Interval` s; **heavy ammo** drops at `Ammo_n` every
  `HeavyAmmoEvery` s; raid bosses **enrage** after `Enrage.After` s (wipe).
- **EchoPlates** (raid encounter 1) replaces the loop: immune until
  `min(3, fireteam size)` plates are held at once for `PlateChargeSeconds` (solo: one
  plate for `SoloPlateHoldSeconds`), then a `DamagePhaseSeconds` window with
  `DamageBuff`.
- **Death**: a chain of explosions with a second of slow motion on every client, the
  remaining enemies fall, and the loot chest appears where the boss died.

### Deaths

| Where | Result |
|-------|--------|
| Hub | respawn after `Respawn.Hub` s |
| Story / Nightfall | respawn at the checkpoint after `Respawn.Activity` s |
| Raid, solo | respawn at the checkpoint after `Respawn.RaidSolo` s |
| Raid, fireteam | a ghost with a 3-second "Revive" prompt; nobody left alive = wipe: everyone respawns at the checkpoint after `Respawn.RaidWipe` s and the current encounter restarts from scratch |

### Unlocks, difficulty, modifiers, score

`ActivityRules.CheckUnlock`: the Nightfall needs `STORY_01` completed, the raid needs
power 480. Launching below the recommended power is allowed (the Director shows it in
red; the power delta curve makes it hard). `RAID_MIN_PLAYERS` (default 1) is the
fireteam size needed to launch the raid. Nightfall difficulties set the power (450 /
470 / 490), extra drops and weekly milestones; two modifiers are picked each week from
`NightfallModifiers` deterministically from the weekly reset time, so the Director and
the server agree. Scored activities count kill points plus a bonus for each second
under `Score.ParSeconds`.

### Rewards (`LootService.AwardCompletion`)

Rewards come from the loot chest (or the `Chest` marker): opening it claims them;
anything unclaimed is sent when the fireteam returns to the hub (or leaves).

| Activity | Rewards |
|----------|---------|
| First Light | 2-3 drops, Rare 60 / Epic 40, World power (+0..+5 below 450) |
| Nightfall | 1-2 drops (+1 Hero, +2 Legend); weekly `NIGHTFALL_WEEKLY` Powerful (tier 3); Legend adds weekly `NIGHTFALL_LEGEND` Pinnacle |
| Raid encounter 1 | weekly `RAID_ENCOUNTER_1` Pinnacle (+1/+2); 15% chance of a raid-exclusive Legendary; after the weekly claim, 1 ordinary drop instead |

Enemy kills can also drop gear (`LootConfig.EnemyGearChance`, bosses excluded) and
heavy ammo boxes (`LootConfig.AmmoDrops`, × the Scarcity modifier).

## 8. Maps (`server/MapBuilders`)

Maps are built in code with `MapKit` (blocks, rooms with door gaps, ramps, neon trim,
lights, signs) so the repository needs no binary files. Each map is a Model with three
folders:

- `Geometry`: everything you see and stand on.
- `Markers`: invisible, non-colliding parts the code looks up by name:
  `PlayerStart`, `Checkpoint_*`, `Zone_*` (a box sized to the zone), `Spawn_<Group>_<n>`,
  `BossSpawn`, and in the hub `HubSpawn` and `Dummy_1..3`.
- `Doors`: force-field parts named in objectives (`Door_*`); opening makes them
  non-colliding and invisible.

Raid plates (`Plate_1..3`) are visible parts anywhere in the map. `Maps.spec` builds
every map and checks that each marker, spawn group, door and plate referenced by
`ActivityConfig` exists. To hand-build a map in Studio, keep the same folder and marker
names, name the Model after `ActivityDef.Map`, and put it in `ServerStorage.Activities`:
WorldService only generates maps that aren't already there.

## 9. Content at a glance

- **Weapons** (41): 11 Rare, 12 Epic, 12 Legendary and 6 Exotic across 13 archetypes.
  Starter loadout: Frontier Standard (auto rifle), Last Ember (hand cannon), Scrapfire
  Tube (rocket launcher).
  Kinetic slot = primaries with no element. Energy slot = primaries and specials
  (Flare/Storm/Null). Heavy slot = rockets, grenade launchers, machine guns, swords.
- **Perks**: 24 traits, 16 barrel/magazine options, 6 exotic weapon signatures and
  6 exotic armor signatures.
- **Armor**: 6 sets (5 pieces each) and 6 class-locked exotics.
- **Classes**: Bulwark, Ranger and Mystic, each with 2 elemental subclasses (grenade,
  melee, super, passive), a class ability and a jump.
- **Activities**: 8 story missions (350→440), 4 patrol zones, 3 strikes, a Nightfall
  with 3 difficulties and modifiers, 1 dungeon (2 encounters), 1 raid (3 encounters)
  and PvP. **Playable now:** First Light, the Hollow Spire Nightfall and raid encounter
  1 (The Echo Chamber); the rest are configured and appear once they get a map.
- **Enemies**: 3 factions (Rustborn, Veiled, Concord). Each has minor, major,
  flying and boss units. Bosses carry scripted mechanics (immune phases, damage
  windows, add waves, enrage timers).

## 10. How to add content

Run `lune run tests/run` after any config change. `ConfigValidator` runs in the
tests and at server start, and names the exact broken reference.

### A new weapon
1. Pick an archetype from `WeaponTypeConfig.Order`. To add a brand-new archetype,
   add it to `WeaponTypeConfig.Types` and `.Order` and to `Types.WeaponTypeId`, then
   add its type to the right `AppliesTo` lists in `PerkConfig`.
2. Append an entry to `WeaponConfig.List`: unique `Id` (`W_...`), `Name`, `Flavor`,
   `Rarity`, `Type`, `Slot` (allowed by the archetype; Kinetic slot ⇔ Kinetic element),
   `Element`, `Sources` and `Model`. Optional fields: `StatBias`, `Rpm`, `Magazine`.
3. Exotics need `FixedPerks` that include one `Column = "Exotic"` perk. Add that perk
   to `PerkConfig.List` with `AppliesTo = { "<its type>" }` and an `Effect` for the
   combat code.
4. Set `Model` to a name. The game builds a part model for the archetype; a real model
   with that name in `ServerStorage.WeaponModels` replaces it (PrimaryPart = grip, a
   `Muzzle` attachment at the tip).

### A new perk
Append to `PerkConfig.List` with a `Column` and `AppliesTo`, plus `StatModifiers`
(barrels and magazines) or an `Effect` (traits). To make it part of a god roll, add
a `{ Trait1, Trait2 }` pair to `Synergies`. The validator checks that both perks can
roll on the same weapon type.

### A new armor set
Append to `ArmorConfig.Sets`. The five pieces (`A_<SET>_<SLOT>`) are generated
automatically. Exotic armor goes in `Exotics` with a `ClassRestriction` and an
`ExoticArmor` perk.

### A new mission
1. Build a map: a module `server/MapBuilders/<Name>Builder.luau` returning
   `Build(): Model` (copy an existing builder), with markers `Spawns/PlayerStart`,
   `Checkpoints/CP_<zone>`, `Objectives/...`, `EnemySpawns/<zone>/...`,
   `BossArena/BossSpawn` (+ `Ammo_n`, `Pylon_n`...) and gates `Gate_<zone>`. Register it
   in `WorldConfig.Maps` and add a lighting preset.
2. Append to `ActivityConfig.List` with `Type`, `Destination`, `RecommendedPower`,
   player counts, `LootSource`, `Unlock`, `Factions`, `Place` (a key in
   `AssetIds.Places`), `Map`, `Playable = true`, `Rewards`, and `Zones` (each with
   `Steps`; see section 7). Raids use `Encounters`, each with its own `Zones`,
   `Playable` and a weekly `Milestone`. Bosses go in `BossConfig`.
3. Run the tests: the validator and `Maps.spec` (`MapMarkers.Missing`) catch steps
   that point at markers the map doesn't have. Cast `Zones`/`Steps` tables with
   `:: { ZoneDef }` / `:: { StepDef }` and write waves with `Wave(...)` so the type
   checker can check each entry.

### A new enemy
Append to `EnemyConfig.List` with its faction, tier (Minor/Major/Boss), role, base
`Health`/`Damage` (at activity power 350), movement and attack stats, an optional
elemental `Shield`, AI `Behavior`, `Scale`/`Title` for majors and bosses, and for
bosses a `BossConfig` entry (health 15-30 captains). Reference it from waves or a
Boss step by `Id`. A rig named after its `Model` field in `ServerStorage.EnemyModels` replaces the
generated one.

### A new remote
Declare it in `Shared/Net/Remotes.luau` with `Kind`, `Direction` and (for
client→server) a `RateLimit`. Handle it on the server with
`NetService.OnEvent(name, { Guard checks... }, handler)`, and never trust anything
the client sends beyond what the checks guarantee.

## 11. Original naming

The mechanics are inspired by the genre, but names are original. For reference:
players are **Keepers**, the hub is **Haven Spire**, the activity map is **the
Director**, the weekly hardened strike is **Hollow Spire** (listed as "Nightfall", the
name the Phase 2 brief asked for; change `TYPE_LABELS` in `DirectorController` to
rename it), the overflow vendor is the **Courier Depot**, and the currencies are **Quanta / Resonant Alloy / Fluxite /
Starglass**. Elements are **Flare / Storm / Null**, and the armor stats are
**Agility / Fortitude / Vitality / Ordnance / Focus / Might**. Display names live
in the configs and can be changed there without touching any logic.
