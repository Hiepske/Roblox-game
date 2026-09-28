# Testing LAST LIGHT in Studio

A checklist for playing everything in Studio: what to do, and what you should see.
If you haven't opened the game yet, start with [README → Quick try](README.md#quick-try-no-tools-needed).

- **Solo:** press **Play** (F5).
- **Fireteam:** **Test → Clients and Servers**, pick 2 or 3 players, **Start**. Each
  player gets their own window.
- **Dev commands** work for everyone in Studio (and the game owner in a live server).
  Type them in chat, or press **F2** for the developer panel with the same buttons.
- In Studio, a **zone timer panel** sits under the objective tracker during an activity.
  It shows how long each zone took, the zone you're in, the total, and the current
  music state (useful while the music ids are still placeholders).

## Dev commands

| Command | What it does |
|---------|--------------|
| `/setpower 480` | sets every equipped item to that power |
| `/give W_LAST_EMBER` | rolls one weapon or armor piece (id or part of its name) at your power and equips it |
| `/giveall` | one of every weapon at your highest power; the overflow goes to the vault |
| `/launch <activity> [difficulty]` | launches, ignoring unlocks (see the table below) |
| `/zone <n>` | jumps to zone *n* of the current activity; the gates before it open |
| `/skip` | skips the current objective step |
| `/god` | toggles taking no damage |
| `/heavy` | drops a heavy ammo box in front of you |
| `/kill` | kills you (to test respawns, revives and wipes) |
| `/leave` | returns you to the hub |
| `/resetweek` | resets weekly rewards, so Powerful and Pinnacle drops come again |
| `/wipe` | wipes your save back to a new 350 character |
| `/help` | lists the commands |

| `/launch` name | Activity | Recommended power |
|----------------|----------|-------------------|
| `firstlight` (or `story`) | First Light | 350 |
| `relay` | Sunken Relay | 380 |
| `hollow` | The Hollow Dark | 410 |
| `nightfall adept` / `hero` / `legend` | Nightfall: Hollow Spire | 450 / 470 / 490 |
| `raid` | Vault of Echoes | 495 |

Your power matters: enemies above your power hit harder and take less damage, and the
Nightfall and raid don't give you an advantage for being above it. Before a test, set
your power to the activity's number, for example `/setpower 410` then `/launch hollow`.

## The 15-minute smoke test

This follows the build order, and each step relies on the previous one working.

1. **Hub.** Play. You spawn in the Spire courtyard at the top of the wall.
2. **Inventory.** Press Tab. Equip something, then close it.
3. **Weapons.** Type `/giveall`, then shoot the range dummies with a few weapon types.
4. **Mission flow.** `/launch firstlight`. Watch the loading screen and the intro,
   follow the waypoint to the wreck and clear the first zone, then `/zone 5` for the boss.
5. **Boss and rewards.** Kill the Scrap Warden, open the chest, and check the Mission
   Complete screen. You return to the hub 30 seconds later.
6. **Raid mechanic.** `/setpower 495`, then `/launch raid`. Stand on a lit plate
   until Harrowmaw's damage phase opens.

If all six work, the core loop works. The sections below cover everything else.

## The Spire (hub)

| Check | Expected |
|-------|----------|
| Spawn | Courtyard (Y 0), fountain monument, bright sky, the ruined city far below |
| Area names | Walking into the Courtyard, Command Deck, Bazaar, Hangar or Range shows the area's name |
| Levels | Grand stairs or the lift up to the **Command Deck** (Y 34: holo-table, raid banners, balcony). East stairs down to the **Bazaar** (Y -28: Gunsmith, Postmaster, Vault terminal, café). Further down to the **Hangar** (Y -70: ships, crane, landing pad) |
| Secrets | A room behind the Command Deck's east wall; a cache on top of the Relay House, reached by jumping up its ledges |
| Director | The glowing terminal in the courtyard (click or press E), or press **M** |
| Range | West of the courtyard: dummies at 15, 30 and 55 studs; the far one has a Flare shield. They heal 3 s after you stop shooting |
| Falling | Jump off the wall: you land back at the spawn |
| Kill feed / waypoint | Not shown in the hub (activities only) |

## Inventory (Tab or I)

| Check | Expected |
|-------|----------|
| Layout | Three weapon slots on the left, five armor slots on the right, your character in the middle; power, highest possible power, class and currencies at the top |
| Details | Hover an item: stats, perks, and a comparison with what you're wearing |
| Equip / lock / dismantle | Click to equip; right-click to lock; hold **Dismantle** for 1 s (locked items refuse) |
| Vault | The Vault tab (or the Vault terminal in the Bazaar): move items both ways; `/giveall` puts its overflow here |
| Postmaster | Drops that didn't fit wait here; collect them in the hub |
| Loadouts | Save your kit to 1-3, change something, then apply the loadout again |
| Filters / sort | Rarity and type filters, sort by power, rarity or newest |
| Gamepad | D-pad moves, A equips, X locks, hold Y dismantles, LB/RB switch tabs, B closes |

## Weapons

`/giveall`, then go to the range. Every archetype should feel different:

| Archetype | Look for |
|-----------|----------|
| Auto rifle, SMG, machine gun | hold to fire; recoil climbs; the machine gun uses heavy ammo |
| Pulse rifle | 3-round bursts |
| Scout rifle, hand cannon, sidearm | semi-auto; the hand cannon has a big headshot bonus |
| Shotgun | a spread of pellets that falls off with range |
| Sniper rifle | scoped aim (right click), very high headshot damage |
| Fusion rifle | charge on hold, then a burst of bolts |
| Grenade launcher, rocket launcher | arcing and straight explosives with splash damage |
| Sword | melee swings; uses heavy ammo |

Damage numbers: white for body, yellow for headshots, blue for shield hits; hit markers
turn red on a kill. Heavy ammo boxes (purple) drop from majors and bosses. `/heavy`
spawns one.

## On every launch

| Check | Expected |
|-------|----------|
| Loading screen | Launching from the Director covers the screen with the activity name, destination, a tip and placeholder art in the map's colors (in Studio a small line names the `AssetIds.Images.Loading` entry to fill in). It lasts at least 1.6 s |
| Intro fly-over | The camera sweeps from above the start toward the first objective under letterbox bars while the name, destination and recommended power fade in. Any key or click skips it. The HUD is hidden, and you can't move or shoot until it ends |
| Waypoint | A diamond over the objective with the distance in meters. Turn around and it slides to the screen edge with an arrow. It fades when it's under your crosshair |
| Zone names | Entering a zone shows its name; the checkpoint moves with you (`/kill`, then check where you respawn) |
| Gates | When a zone clears, its gate opens: a Door slides up, a Shield fades, or a Bridge extends |
| Enemy arrivals | Waves step out of rifts or are dropped by a dropship that flies in, out of your line of sight when possible. The next wave starts at 80% cleared or on a timer |
| Kill feed | Top right: your kills (enemy colored by tier), boss defeats in gold, deaths in red with what killed you, revives in green |
| Music | Placeholder ids are silent. The Studio panel shows *Explore*, *Combat 0.xx* when enemies are close (it rises with more or bigger enemies and calms down about 8 s later), *Boss* during a boss, and *Victory* at the end |
| Boss | A big bar at the top with ticks at 66% and 33%. At each tick the boss turns grey (immune) behind a bubble until its mechanic is done. Watch for barrages (it glows, then sprays bolts) and slams (a red circle fills under you, then it leaps on it) |
| Boss death | Explosions, about a second of slow motion, then a loot chest appears |
| Mission Complete | Opening the chest shows the Mission Complete screen: time, kills, deaths (plus fireteam totals with 2+ players), and medal and score in the Nightfall, over your loot cards. **Equip upgrades** equips anything better |
| Return | 30 s after completion everyone returns to the Spire (a short loading screen covers it); anything left in the chest is paid then |

## First Light (350): snowy valley, about 5-10 min solo

`/setpower 350`, then `/launch firstlight`.

| Zone | Do | Check |
|------|----|-------|
| 1 The Crash Site | Reach the wreck, clear 2 waves | Rifts spawn scavengers; the 2nd wave arrives by dropship at 80%; the Shield gate at the tree line fades |
| 2 Frostfall Village | Walk up the street, clear the waves | Snipers on the two watch-house roofs paint you with a red laser before they fire; break line of sight. Drones hover and strafe |
| 3 Kessrin Outpost | Clear the courtyard, then stand in the uplink ring for 60 s | The timer only runs while someone is in the ring; waves keep coming; turrets fire bursts |
| 4 The Reactor | Destroy the 3 coolant regulators | The Bridge gate extends over the chasm. Falling in puts you back at the checkpoint |
| 5 The Scrap Pit | Kill the Scrap Warden | Immune at 66% until 2 waves of guards die, and at 33% until drones plus a captain die. Heavy ammo appears at the arena's edge |

Rewards: 2-3 Rare/Epic drops plus a guaranteed new weapon. Completing it unlocks Sunken
Relay and the Nightfall.

## Sunken Relay (380): overgrown coast

`/setpower 380`, then `/launch relay`.

| Zone | Do | Check |
|------|----|-------|
| 1 Glasswater Beach | Push up the beach to the dunes | Palms, landing craft; the Shield in the sea wall fades |
| 2 The Drowned Market | Clear the flooded streets | Water up to your shins; marksmen on the balconies; a Door into the tower |
| 3 Relay Tower: Lower Deck | Clear the floor | The Door at the top of the east stairs opens onto the next floor |
| 4 Relay Tower: Signal Deck | Destroy 3 jammers | The Shield at the top of the west stairs fades |
| 5 The Relay Crown | Kill the Tide Marshal | Immune at 66% until 3 tide pylons are destroyed; at 33% until the Warden escort dies |

## The Hollow Dark (410): caverns

`/setpower 410`, then `/launch hollow`.

| Zone | Do | Check |
|------|----|-------|
| 1 The Pale Woods | Reach the cave mouth | Dead trees and shrines; the Shield fades |
| 2 The Glimmering Deep | Reach the heart of the caverns | It's dark: you and your fireteam carry **flashlights** that follow your aim. Glowing crystals; Veil Seers on the ledges; the Bridge extends over the glowing river |
| 3 The Veiled Barracks | Clear the halls, then hold E on the ward seal for 2 s | The Door opens |
| 4 The Hollow Choir | Shatter 3 ritual crystals, then kill the Hollow Priest | The Priest **teleports** around the chamber. Immune at 66% (3 ward crystals) and 33% (the choir) |

## Nightfall: Hollow Spire (Adept 450 / Hero 470 / Legend 490), about 8-10 min

`/setpower 470`, then `/launch nightfall hero`. The Director needs First Light
completed; `/launch` doesn't.

| Zone | Do | Check |
|------|----|-------|
| 1 Redrock Canyon | Fight up to the canyon bend | Orange dusk sky, wrecked vehicles, turrets on the ledges |
| 2 The Iron Gate | Break the 3 shield generators | Snipers on the wall; the Door opens |
| 3 The Inner Halls | Clear the great hall, hold the lift controls for 35 s | Turret balconies |
| 4 The Spire Crown | Kill Vekta, the Spire Overseer | Immune at 66% until 2 waves of guards die. At 33% the middle of the floor flashes and **collapses**, and Vekta stays immune until 3 ward pylons are destroyed. Falling puts you back at the checkpoint |

Also check the two weekly **modifiers** (on the Director card and the tracker), the
**timer and score**, and the **medal**: the tracker shows the best medal still in
reach (Gold under 8:00, Silver under 11:00, Bronze under 15:00). The completion banner
and the Mission Complete screen show the medal you earned, and Gold adds an extra drop.
`/zone 4` straight to the boss is a quick way to see a Gold medal.

## Raid: Vault of Echoes (495; the Director needs power 480)

Solo: `/setpower 495`, then `/launch raid`. Everything can be done alone. Solo,
you respawn 10 s after a death. In a fireteam a dead Keeper leaves a ghost that a
teammate revives by holding E for 3 s; if everyone is down, it's a wipe, and the
encounter restarts from its checkpoint.

| # | Encounter | Do | Check |
|---|-----------|----|-------|
| 1 | **The Gate**: Harrowmaw | Stand on a lit echo plate (solo: one plate for 5 s; fireteam: as many plates as players, up to 3, held together for 3 s), then shoot during the 20 s damage phase (+25% damage) | Lit plates change each cycle; adds every 25 s; **enrage** (wipe) at 6:00; chest with this week's Pinnacle; the Door opens |
| 2 | **The Descent** | Jump across the platforms down to the lower level | Some platforms move. Falling returns you to the start of the jump puzzle (CP_Descent) |
| 3 | **The Echo Chamber**: Echo Warden | Each of the 3 side rooms has a marked **Echo Bearer** (it glows). Kill it to pick up its echo (30 s; "ECHO CHARGED" on the HUD), then stand in the well in the middle to deposit it. After 3 deposits the Warden's shield drops for 25 s | Adds keep coming; an echo that fades brings its Bearer back 6 s later; enrage at 8:00; chest |
| 4 | **The Silent Hall** | Get through without being burned | Sweeping, sliding and blinking laser walls (watch one cycle); a sentinel patrol walks its route and attacks when it sees you |
| 5 | **Echo Sovereign** | Three phases | Immune at 66% until 3 echo pillars are destroyed, and at 33% until 2 waves of guardians die. In phases 2 and 3 it charges a **nova**: lit circles appear, and only players inside one survive. In phase 3 it also teleports. Enrage at 9:00. The last chest shows the Mission Complete screen |

Each boss encounter's chest pays its weekly Pinnacle once per week (use `/resetweek` to
test again). A chest you walked past is paid when you leave. With a fireteam, check that
a player who joins mid-run doesn't get the chests of encounters they weren't there for.

## Saving

With API Services on (README → Setup, step 4), stop and play again: your power, items
and weekly progress should be the same. Without it, the F2 panel shows `Storage: MOCK`
and nothing persists.

## Automated checks

Most of the above also runs without Studio: `lune run tests/run` plays every mission,
the Nightfall and every raid encounter solo (and the Gate with a fireteam), and checks
the maps, the UI screens and the new presentation pieces. See README → Development checks.
