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
  Controllers ── ClientNet ──remotes──►  NetService ─► Services (Data, Debug, ...)
      ▲                                     │ rate limit, arg checks, suspicion
      └──── DataSnapshot / DataChanged ◄────┘ DataService (owns saved data)
Shared (ReplicatedStorage.Shared): Config, Types, PowerMath, ItemRoller, Util
```

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

## 5. Content at a glance

- **Weapons** (40): 10 Rare, 12 Epic, 12 Legendary and 6 Exotic across 13 archetypes.
  Kinetic slot = primaries with no element. Energy slot = primaries and specials
  (Flare/Storm/Null). Heavy slot = rockets, grenade launchers, machine guns, swords.
- **Perks**: 24 traits, 16 barrel/magazine options, 6 exotic weapon signatures and
  6 exotic armor signatures.
- **Armor**: 6 sets (5 pieces each) and 6 class-locked exotics.
- **Classes**: Bulwark, Ranger and Mystic, each with 2 elemental subclasses (grenade,
  melee, super, passive), a class ability and a jump.
- **Activities**: 8 story missions (350→440), 4 patrol zones, 3 strikes, a hardened
  strike with 3 difficulties and modifiers, 1 dungeon (2 encounters), 1 raid
  (3 encounters) and PvP.
- **Enemies**: 3 factions (Rustborn, Veiled, Concord). Each has minor, major,
  flying and boss units. Bosses carry scripted mechanics (immune phases, damage
  windows, add waves, enrage timers).

## 6. How to add content

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
4. Add a placeholder model name; drop a real model into `ReplicatedStorage.Assets.Weapons` later.

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
Append to `ActivityConfig.List` with `Type`, `Destination`, `RecommendedPower`,
player counts, `LootSource`, `Unlock` (the previous mission and/or a power
requirement), `Factions`, `Place` (a key in `AssetIds.Places`) and an `Objectives`
script (Travel / Defeat / Defend / Carry / Interact / Survive / Boss). Raids and
dungeons use `Encounters`, each with its own objectives and a weekly `Milestone`.
Cast optional arrays with `:: { ObjectiveDef }` (and similar) so the type checker
can check each entry.

### A new enemy
Append to `EnemyConfig.List` with its faction, tier (Minor/Major/Boss), role, base
`Health`/`Damage` (at activity power 350), movement and attack stats, an optional
elemental `Shield`, AI `Behavior`, and for bosses a `Mechanics` list. Reference it
from mission objectives by `Id`.

### A new remote
Declare it in `Shared/Net/Remotes.luau` with `Kind`, `Direction` and (for
client→server) a `RateLimit`. Handle it on the server with
`NetService.OnEvent(name, { Guard checks... }, handler)`, and never trust anything
the client sends beyond what the checks guarantee.

## 7. Original naming

The mechanics are inspired by the genre, but names are original. For reference:
players are **Keepers**, the hub is **Haven Spire**, the activity map is the
**Star Chart**, the hardened strike is **The Long Dark**, the overflow vendor is the
**Courier Depot**, and the currencies are **Quanta / Resonant Alloy / Fluxite /
Starglass**. Elements are **Flare / Storm / Null**, and the armor stats are
**Agility / Fortitude / Vitality / Ordnance / Focus / Might**. Display names live
in the configs and can be changed there without touching any logic.
