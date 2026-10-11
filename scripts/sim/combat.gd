class_name SimCombat
extends RefCounted
## Cursing Gnomes — combat simulation (Milestone 4: combat & disasters).
##
## Melee, ranged, and artillery combat over GameState unit/building records.
## Design ported from the HTML build (not its code):
##   - soldiers/guards: melee, chase (soldiers) or hold post (guards)
##   - archers/rangers/mages: ranged projectiles (arrows, spells)
##   - cannoneers: long-range artillery with splash (HTML's field/grape
##     cannons: ~70-100 dmg, ~180-240 px splash)
##   - guard towers: auto-fire arrows at hostiles in range
##   - hostility is diplomacy-gated (Milestone 8): factions fight ONLY when
##     their pair state is WAR. NEUTRAL/HOSTILE/FRIENDLY/ALLIED pairs do not
##     fight; "monster" is hostile to everything. When no diplomacy system
##     is wired, combat falls back to free-for-all (legacy default).
##   - death: hp <= 0 -> kill_unit -> corpse lingers 20 s -> purged
##
## PERFORMANCE (60 fps, HTML lessons baked in):
##   - combat AI runs on the world's round-robin AI budget (world.gd), not
##     per-frame for every unit
##   - target search uses a per-frame unit spatial grid (expanding rings,
##     exact stopping rule) instead of a linear scan: identical results,
##     a fraction of the diplomacy lookups
##   - corpse purge runs on a 1 s accumulator, not per tick
##
## Pure logic — no rendering, no input, no audio. Visuals (projectiles, FX)
## live in world/projectile.gd and world/combat_fx.gd, driven by bus events.


## ---- Blood & gore (HTML rollInjury / bleedRate / spawnGore parity) ----
## Jeremy 2026-10-04: "Do we still have the blood and gore system and all
## that from the original?" — ported from fix79/index.html Unit.rollInjury,
## spawnGore, and the bleed-out tick. Per-unit fields (lazily initialized so
## old saves keep working):
##   limbs: {leftArm, rightArm, leftLeg, rightLeg} — all true until severed
##   bleed_rate: ongoing blood loss (injury +6 per severed limb, max 25)
##   blood: 100-point blood pool; hits 0 → the unit bleeds out and dies
##   injured: true once hurt — drains blood slowly until a doctor heals
const LIMB_KEYS := ["leftArm", "rightArm", "leftLeg", "rightLeg"]
const LIMB_LABEL := {
	"leftArm": "left arm", "rightArm": "right arm",
	"leftLeg": "left leg", "rightLeg": "right leg",
}


## Lazily attaches the gore fields to a unit record (old saves / spawns that
## predate the system get them on first touch — never crashes on missing).
func _ensure_gore_fields(u: Dictionary) -> void:
	if not u.has("limbs"):
		u["limbs"] = {"leftArm": true, "rightArm": true,
			"leftLeg": true, "rightLeg": true}
	if not u.has("bleed_rate"):
		u["bleed_rate"] = 0.0
	if not u.has("blood"):
		u["blood"] = 100.0
	if not u.has("injured"):
		u["injured"] = false


## Counts severed limbs on a unit.
func _limbs_missing(u: Dictionary) -> int:
	_ensure_gore_fields(u)
	var n := 0
	var limbs: Dictionary = u["limbs"]
	for k: String in LIMB_KEYS:
		if not bool(limbs.get(k, true)):
			n += 1
	return n


## HTML parity: Unit.rollInjury(dmgTaken) — combat injury dice, chance to lose
## limbs permanently. Called when a unit survives damage.
func roll_injury(u: Dictionary, dmg_taken: float, is_artillery: bool) -> void:
	if not u.get("alive", false):
		return
	_ensure_gore_fields(u)
	var pos: Vector2 = u.get("position", Vector2.ZERO)
	_bus_blood(pos, 1 + randi_range(0, 1))
	u["injured"] = true
	u["bleed_rate"] = minf(20.0,
		float(u["bleed_rate"]) + 0.6 + dmg_taken / 80.0)
	u["blood_trail_cd"] = 8.0
	# Higher damage → higher limb loss; artillery hits are brutal.
	var chance: float = minf(0.22, 0.03 + dmg_taken / 200.0)
	if is_artillery:
		chance = minf(0.55, chance * 2.8 + 0.08)
	if randf() > chance:
		return
	var limbs: Dictionary = u["limbs"]
	var options: Array[String] = []
	for k: String in LIMB_KEYS:
		if bool(limbs.get(k, true)):
			options.append(k)
	if options.is_empty():
		return
	# Sometimes lose multiple limbs at once.
	var losses: int = 2 if randf() < 0.25 else 1
	var faction: String = String(u.get("faction", "humans"))
	for i: int in range(losses):
		if options.is_empty():
			break
		var limb: String = options[randi_range(0, options.size() - 1)]
		options.erase(limb)
		limbs[limb] = false
		var label: String = String(LIMB_LABEL.get(limb, limb))
		_bus_blood(pos, 4)
		_bus_gore(pos, "limb", 1)
		_gs.bus.unit_said.emit(int(u.get("id", 0)), _limb_cry(faction, label))
		u["bleed_rate"] = minf(25.0, float(u["bleed_rate"]) + 6.0)
		_bus_blood(pos, 18)
		_bus_gore(pos, "limb", 2)
		_gs.bus.combat_fx.emit("blood_stains", pos)
	# Permanent limb loss — the unit seeks a doctor to stabilize.
	u["seek_doctor"] = true


## Faction-voiced limb-loss cry (HTML unitBubble parity — no emoji, tofu rule).
func _limb_cry(faction: String, label: String) -> String:
	match faction:
		"ogres":
			return "MY %s!" % label.to_upper()
		"gnomes":
			return "Bloody hell — my %s!" % label
		_:
			return "Ahh! My %s!" % label


## HTML parity: blood loss while injured. bleedRate + 2.5 per missing limb +
## 0.8 while injured drains the blood pool; at 0 the unit bleeds out with a
## gore burst. Doctors reset bleed_rate / blood / injured on heal.
## Jeremy 2026-10-04: staggered — 1/4th of units per frame (15Hz effective,
## delta scaled to compensate). Was: all 240 units every frame (14,400/s).
func _tick_bleed(delta: float) -> void:
	var units: Array = _gs.units
	var n: int = units.size()
	if n == 0:
		return
	var slice: int = mini(maxi(1, n / 4), n)
	# Scale = frames per full pass (n/slice), not a hardcoded x4: with few
	# units the old x4 over-applied (a single unit bled 4x too fast).
	var scaled_delta: float = delta * float(n) / float(slice)
	var idx: int = _bleed_cursor % n
	for i: int in range(slice):
		var u: Dictionary = units[(idx + i) % n]
		_tick_bleed_unit(u, scaled_delta)
	_bleed_cursor = (idx + slice) % n


## Single-unit bleed tick (extracted for staggering).
func _tick_bleed_unit(u: Dictionary, delta: float) -> void:
	if not u.get("alive", false) or bool(u.get("downed", false)):
		return
	# Jeremy 2026-10-04 perf: cheap early-out BEFORE _ensure_gore_fields.
	# Healthy units (the vast majority) skip 4 dict .has() calls each.
	# Using .get() with defaults avoids allocating missing keys.
	if not bool(u.get("injured", false)) and float(u.get("bleed_rate", 0.0)) <= 0.0:
		return
	_ensure_gore_fields(u)
	var bleed: float = float(u["bleed_rate"])
	var missing: int = _limbs_missing(u)
	var rate: float = bleed + float(missing) * 2.5 \
		+ (0.8 if bool(u["injured"]) else 0.0)
	u["blood"] = float(u["blood"]) - rate * delta
	var pos: Vector2 = u.get("position", Vector2.ZERO)
	if rate > 1.0 and randf() < delta * minf(4.0, rate * 0.4):
		_bus_blood(pos, 1 + int(float(missing) * 0.7))
	if float(u["blood"]) <= 0.0:
		_bus_blood(pos, 12)
		_bus_gore(pos, "chunk", 6)
		_bus_gore(pos, "limb", 2)
		var uid: int = int(u.get("id", 0))
		_gs.bus.unit_said.emit(uid, "Bled out")
		if _gs.kill_unit(uid):
			u["death_time"] = _gs.game_time
			u["combat_state"] = "dead"
			_gs.bus.unit_killed.emit(uid, "bleedout")


## Sim-side blood spray: emits the pooled "blood" FX a few times (capped so a
## single 18-burst doesn't starve the 48-slot pool).
func _bus_blood(pos: Vector2, count: int) -> void:
	for i: int in range(mini(count, 6)):
		_gs.bus.combat_fx.emit("blood", pos)


## Sim-side gore: one "gore_<kind>" bus event per piece (HTML spawnGore
## spawns exactly `count` pieces; world.gd turns each into one fx piece).
func _bus_gore(pos: Vector2, kind: String, count: int) -> void:
	for i: int in range(mini(count, 16)):
		_gs.bus.combat_fx.emit("gore_" + kind, pos)


## Military job stats: {dmg, range (px), cooldown (s), ranged, proj_speed,
## splash (px, 0 = none), aggro (px, acquire range), speed (px/s)}.
const MILITARY_STATS := {
	"soldier":   {"dmg": 15.0, "range": 42.0,  "cooldown": 1.0,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 600.0, "speed": 95.0},
	"guard":     {"dmg": 12.0, "range": 48.0,  "cooldown": 1.2,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 420.0, "speed": 85.0},  # holds post, leashes to it
	"archer":    {"dmg": 10.0, "range": 300.0, "cooldown": 1.5,
		"ranged": true,  "proj_speed": 700.0,  "splash": 0.0,
		"aggro": 420.0, "speed": 90.0},
	"ranger":    {"dmg": 9.0,  "range": 220.0, "cooldown": 1.1,
		"ranged": true,  "proj_speed": 750.0,  "splash": 0.0,
		"aggro": 500.0, "speed": 130.0},  # fast skirmisher
	"mage":      {"dmg": 26.0, "range": 340.0, "cooldown": 2.6,
		"ranged": true,  "proj_speed": 500.0,  "splash": 40.0,
		"aggro": 460.0, "speed": 80.0},
	"cannoneer": {"dmg": 70.0, "range": 600.0, "cooldown": 4.0,
		"ranged": true,  "proj_speed": 450.0,  "splash": 180.0,
		"aggro": 650.0, "speed": 70.0},  # crewed artillery
	"bandit":    {"dmg": 10.0, "range": 42.0,  "cooldown": 1.2,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 700.0, "speed": 100.0},  # raiders: fast, fragile
	# --- Faction uniques (HTML roster parity, wired via apply_faction_stats) ---
	# Humans (base dmg 9)
	"swordsman": {"dmg": 9.0,  "range": 42.0,  "cooldown": 0.42,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 550.0, "speed": 95.0},
	"knight":    {"dmg": 12.0, "range": 48.0,  "cooldown": 0.22,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 600.0, "speed": 119.0},  # cavalry charge x2.2
	"cleric":    {"dmg": 8.0,  "range": 50.0,  "cooldown": 0.55,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 500.0, "speed": 100.0},  # smites undead x1.6, medic
	# Ogres (base dmg 38)
	"clubber":   {"dmg": 41.0, "range": 58.0,  "cooldown": 0.55,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 550.0, "speed": 137.0},
	"musketeer": {"dmg": 51.0, "range": 210.0, "cooldown": 0.95,
		"ranged": true,  "proj_speed": 800.0,  "splash": 0.0,
		"aggro": 600.0, "speed": 129.0},  # long-range gunner
	"berserker": {"dmg": 57.0, "range": 68.0,  "cooldown": 0.65,
		"ranged": false, "proj_speed": 0.0,   "splash": 72.0,
		"aggro": 600.0, "speed": 236.0},  # hammer splash
	"warlord":   {"dmg": 68.0, "range": 70.0,  "cooldown": 0.7,
		"ranged": false, "proj_speed": 0.0,   "splash": 80.0,
		"aggro": 650.0, "speed": 167.0},  # aura buffs allies
	"blunderbuss": {"dmg": 41.0, "range": 95.0, "cooldown": 0.9,
		"ranged": true,  "proj_speed": 520.0,  "splash": 0.0,
		"aggro": 550.0, "speed": 137.0},  # 5-pellet cone
	# Gnomes (base dmg 14)
	"axeman":    {"dmg": 16.0, "range": 40.0,  "cooldown": 0.45,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 550.0, "speed": 135.0},
	"tinker_mech": {"dmg": 30.0, "range": 54.0, "cooldown": 0.8,
		"ranged": false, "proj_speed": 0.0,   "splash": 90.0,
		"aggro": 600.0, "speed": 90.0},  # mech suit, splash punches
	"saboteur":  {"dmg": 11.0, "range": 40.0,  "cooldown": 0.4,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 500.0, "speed": 192.0},  # shreds walls x1.5
	# Elves (base dmg 11)
	"warlock":   {"dmg": 24.0, "range": 125.0, "cooldown": 0.9,
		"ranged": true,  "proj_speed": 600.0,  "splash": 70.0,
		"aggro": 550.0, "speed": 125.0},  # summons nature spirits
	"treant":    {"dmg": 28.0, "range": 56.0,  "cooldown": 1.1,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 600.0, "speed": 68.0},  # siege: shreds buildings x2
	"spellweaver": {"dmg": 12.0, "range": 230.0, "cooldown": 0.75,
		"ranged": true,  "proj_speed": 650.0,  "splash": 0.0,
		"aggro": 550.0, "speed": 114.0},  # snares enemies
	# Undead (base dmg 15)
	"skeleton":  {"dmg": 13.0, "range": 42.0,  "cooldown": 0.5,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 550.0, "speed": 100.0},
	"zombie":    {"dmg": 16.0, "range": 42.0,  "cooldown": 0.8,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 500.0, "speed": 57.0},  # infects on hit
	"ghoul":     {"dmg": 18.0, "range": 42.0,  "cooldown": 0.45,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 600.0, "speed": 138.0},
	"wraith":    {"dmg": 15.0, "range": 52.0,  "cooldown": 0.6,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 550.0, "speed": 128.0},  # life drain, ignores walls
	"necromancer": {"dmg": 18.0, "range": 240.0, "cooldown": 0.9,
		"ranged": true,  "proj_speed": 550.0,  "splash": 0.0,
		"aggro": 550.0, "speed": 90.0},  # soul-bolt ranged
	"plaguebearer": {"dmg": 12.0, "range": 50.0, "cooldown": 0.7,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 500.0, "speed": 81.0},  # infection cloud on death
	"bone_golem": {"dmg": 42.0, "range": 60.0,  "cooldown": 1.2,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 650.0, "speed": 52.0},  # siege engine: shreds buildings x2
	"lich":      {"dmg": 30.0, "range": 260.0, "cooldown": 0.8,
		"ranged": true,  "proj_speed": 600.0,  "splash": 70.0,
		"aggro": 600.0, "speed": 95.0},
	# Summoned units
	"spirit":    {"dmg": 12.0, "range": 40.0,  "cooldown": 1.0,
		"ranged": false, "proj_speed": 0.0,   "splash": 0.0,
		"aggro": 500.0, "speed": 110.0},  # warlock summon, 18 s life
}

## Race-based combat modifiers (HTML RACES table parity — Jeremy 2026-10-02 audit).
## Ogres are tanks, gnomes are frail but hit hard (especially magic).
const RACE_COMBAT := {
	"humans": {"hp": 200.0, "dmg_mul": 1.0,  "magic_mul": 1.0},
	"ogres":   {"hp": 550.0, "dmg_mul": 1.9,  "magic_mul": 0.8},
	"elves":   {"hp": 180.0, "dmg_mul": 1.0,  "magic_mul": 1.3},
	"gnomes":  {"hp": 160.0, "dmg_mul": 1.4,  "magic_mul": 1.75},
	"undead":  {"hp": 220.0, "dmg_mul": 1.1,  "magic_mul": 1.2},
}


## Guard tower auto-defense.
const TOWER_STATS := {"dmg": 12.0, "range": 400.0, "cooldown": 2.0,
	"proj_speed": 650.0}

const CORPSE_LINGER := 20.0   # seconds a corpse record survives
const GUARD_LEASH := 150.0     # guards don't chase past this from their post

## Downed / knockout (HTML goDowned parity): a fighter knocked out by direct
## unit-vs-unit combat goes DOWN (alive, revivable) instead of dying.
## Splash, artillery, and unknown-source damage are always lethal.
const DOWNED_BLEEDOUT := 60.0  # seconds a downed unit survives without a medic
const DOWNED_CRY := {  # race-flavored "help me" bubbles (HTML goDowned)
	"humans": "Ahhh! Help!", "ogres": "Ahhh! Help me!",
	"elves": "Ahh… aid me!", "gnomes": "Ahhh help! I'm down!",
	"undead": "Aid… me…",
}

## Combat micro-tactics (HTML applyCombatTactics "FIX 'EM THEN FLANK 'EM").
const UNDER_FIRE_WINDOW := 3.5   # seconds after a hit a unit counts as "under fire"
const COVER_DMG_MUL := 0.65      # HTML: inCover damage x0.65
const COVER_SEARCH := 150.0      # px: how far a unit looks for cover
const FIX_DURATION := 2.2        # seconds the line holds (FIX) before flanking
const FLANK_RANGE := 420.0       # commander must be this close for tactics
const TACTIC_MARCH := 0          # formation slot wings: computed from slot % 3

## War horn stinger (HTML playWarHorn: combat begins, 20 s global cooldown).
const WAR_HORN_COOLDOWN := 20.0

## Faction-correct firearms (HTML FIREARMS / FIREARM_NAMES, 2026-09-19):
## mechanical tiers are identical for all factions; only the display names
## differ — never a universal "Issue Rifle" outside humans.
const FIREARMS := {
	"basic":   {"dmg_mul": 1.0,  "range_mul": 1.0,  "min_skill": 0},
	"shotgun": {"dmg_mul": 1.45, "range_mul": 0.55, "min_skill": 25},
	"assault": {"dmg_mul": 1.25, "range_mul": 1.15, "min_skill": 45},
	"sniper":  {"dmg_mul": 1.9,  "range_mul": 1.85, "min_skill": 70},
}
const FIREARM_NAMES := {
	"humans": {"basic": ["Issue Rifle", "🔫"], "shotgun": ["Shotgun", "💥"],
		"assault": ["Assault Rifle", "🔫"], "sniper": ["Sniper Rifle", "🎯"]},
	"ogres": {"basic": ["Musket", "🔫"], "shotgun": ["Blunderbuss", "💥"],
		"assault": ["War Musket", "🔫"], "sniper": ["Long Musket", "🎯"]},
	"elves": {"basic": ["Oak Bow", "🏹"], "shotgun": ["Scatterbow", "🏹"],
		"assault": ["War Bow", "🏹"], "sniper": ["Elven Longbow", "🎯"]},
	"gnomes": {"basic": ["Rune Staff", "✨"], "shotgun": ["Blast Rod", "💥"],
		"assault": ["Rune Repeater", "✨"], "sniper": ["Runesniper", "🎯"]},
	"undead": {"basic": ["Issue Rifle", "🔫"], "shotgun": ["Shotgun", "💥"],
		"assault": ["Assault Rifle", "🔫"], "sniper": ["Sniper Rifle", "🎯"]},
}

## Weapon upgrades at the weaponsmith (HTML weapon_up1/2/3 costs).
## Each level is +8% damage (HTML applyFirearmStats).
const WEAPON_UPGRADES := [
	{"gold": 40, "wood": 15},
	{"gold": 80, "wood": 30},
	{"gold": 140, "wood": 50},
]
const WEAPON_LEVEL_DMG := 0.08
const MAX_WEAPON_LEVEL := 3

## Warlord aura (HTML warlordAuraPulse61): allies within 320 px deal x1.25.
const WARLORD_AURA_RANGE := 320.0
const WARLORD_AURA_MUL := 1.25
const WARLORD_SPLASH := 80.0  # warlord melee splash (HTML splashRadius 80)


var _gs: GameState
var projectiles: Array[Dictionary] = []  # live projectile records
var _next_proj_id: int = 1
var _corpse_accum: float = 0.0
var _blood_accum := 0.0  # Jeremy 2026-10-04 perf: 10Hz blood trail throttle
# Jeremy 2026-10-04: staggering cursors — evenly distribute periodic work.
var _bleed_cursor := 0  # _tick_bleed: 1/4th of units per frame (15Hz)
var _trail_cursor := 0  # _tick_blood_trails: 1/2 of units per 10Hz tick
var _tower_cursor := 0  # tick_towers: 1/6th of buildings per frame (10Hz)
# Perf R27: warlord aura cache — faction -> {unit_id: Vector2} of live
# promoted warlords, rebuilt once per tick. _warlord_nearby() used to
# linear-scan all units on EVERY attack (~134us/call); the cache makes it
# O(warlords of one faction). Behavior-identical (same filter set, same
# strict distance test, self excluded); frame-granularity staleness is
# invisible. Ephemeral — not saved.
var _warlord_cache := {}
var _warlord_cache_init := false  # lazy-build on first _warlord_nearby call (AI slices run before combat.tick on frame 1)
var _last_horn_time: float = -999.0  # war horn stinger cooldown (global)
## Jeremy 2026-10-07 (wake audio lane): melee-hit SFX throttle. Melee
## contact had no sound (projectile impacts sound via the world layer);
## a big battle lands dozens of melee hits per tick, so emissions are
## capped per 0.1 s game-time bucket to protect the 16-voice spatial pool.
const SFX_MELEE_BUCKET := 0.1
const SFX_MELEE_PER_BUCKET := 8
var _sfx_melee_bucket := -1
var _sfx_melee_n := 0

## --- Perf: unit spatial grid (2026-10-05) ---
## _nearest_hostile was a full O(units) scan per military AI slice and per
## tower tick, each scan carrying a diplomacy can_fight lookup per unit.
## The grid buckets unit record refs by 256px cell, rebuilt at most once
## per physics frame (units move every frame, so no version stamp can work
## — the physics frame clock is the invalidation). Queries walk expanding
## rings with the exact stopping rule, so results are identical to the old
## full scan; ties break by lowest units-array index, matching the old
## first-match order. Implementation only: zero behavior change.
const UNIT_GRID_CELL := 256.0
var _unit_grid := {}  # Vector2i cell -> flat Array [unit, build_idx, ...]
var _unit_grid_frame := -1  # Engine.get_physics_frames() at last rebuild
var _unit_grid_n := -1  # _gs.units.size() at last rebuild
## Perf R43: alive non-downed unit tally per faction, rebuilt with the unit
## grid. Lets _nearest_hostile skip the ring walk entirely when no hostile
## faction fields a valid target - the walk would visit every cell and find
## nothing. Bit-identical: the tally mirrors the scan's skip filters exactly
## (alive, not downed), keyed by faction, rebuilt from the same records.
var _faction_alive := {}  # String faction -> int

## Perf R42: building spatial grid for _nearest_hostile_building. Buildings
## never move (unlike units) EXCEPT during Ricky-the-Repo-Gnome tows, so the
## grid rebuilds when membership changes — add_building / erase_building /
## clear / save-load all change _gs.buildings.size(), which is the
## invalidation signal (same trick as the unit grid's count check, minus the
## per-frame clock) — and disasters.gd calls _invalidate_building_grid()
## at every Ricky tow/restore position write (the only building moves in the
## game). Destroyed flags and faction flips are read off the LIVE records at
## scan time, so a building destroyed or conquered mid-frame is filtered
## correctly with no rebuild. Ring walk + stopping rule mirror R41:
## bit-identical to the old linear scan, ties break by lowest
## buildings-array index. Implementation only: zero behavior change.
const BLDG_GRID_CELL := 512.0
var _bldg_grid := {}  # Vector2i cell -> flat Array [building, build_idx, ...]
var _bldg_grid_n := -1  # _gs.buildings.size() at last rebuild

## Perf R23: per-faction hostile-set cache. _hostile_factions walks ~7
## diplomacy relations per scan; the result only changes when a relation
## STATE changes, which bumps SimDiplomacy.relation_version. Cache hit =
## one dict lookup. Bit-identical results, zero behavior change.
var _hostile_cache := {}  # faction -> [relation_version:int, set:Dictionary]


## Cached hostile-faction set for a faction. Safe with duck-typed /
## mock diplomacy: a missing relation_version reads as 0 (constant),
## and is_hostile() is pure, so the cached set stays valid.
func _hostile_cached(faction: String) -> Dictionary:
	var ver := 0
	if diplomacy != null:
		var rv: Variant = diplomacy.get("relation_version")
		if rv != null:
			ver = int(rv)
	var e: Array = _hostile_cache.get(faction, [])
	if not e.is_empty() and int(e[0]) == ver:
		return e[1]
	var s: Dictionary = _hostile_factions(faction)
	_hostile_cache[faction] = [ver, s]
	return s

## Optional SimMind (set by the world). Duck-typed (no class annotation) to
## avoid a cyclic class reference between SimCombat and SimMind.
var mind = null

## Optional SimAdventure (set by the world). Duck-typed for the same reason.
## Lets adventure mode mitigate hero damage (armor/vit) inside damage_unit.
var adventure = null

## Optional SimDiplomacy (set by the world). Duck-typed like mind.
## When wired, combat between factions is allowed ONLY at WAR; when null,
## combat falls back to the free-for-all legacy default.
var diplomacy = null

## Optional SimMonasteries (set by the world). Duck-typed like mind.
## Powers the Seven Monasteries magic attacks, shields, and capture rules.
var monasteries = null
## Optional SimDarkCrystals (set by the world). Duck-typed like mind.
## Powers the Seven Dark Crystals devastating attacks and corruption.
var crystals = null
## Optional SimNuclear (set by the world). Duck-typed like mind.
## Detonates nuke warheads (HTML detonateNuke parity).
var nuclear = null


func _init(game_state: GameState) -> void:
	_gs = game_state


## Legacy free-for-all default: any two different factions are hostile.
## Kept static for the no-diplomacy baseline; live games use can_fight().
static func is_hostile(faction_a: String, faction_b: String) -> bool:
	if faction_a == faction_b:
		return false
	return true


## Diplomacy-aware hostility check used by all combat targeting.
## Monsters are always hostile to everyone (they sit outside diplomacy).
func can_fight(faction_a: String, faction_b: String) -> bool:
	if faction_a == faction_b:
		return false
	if faction_a == "monster" or faction_b == "monster":
		return true
	if diplomacy == null:
		return is_hostile(faction_a, faction_b)
	return bool(diplomacy.combat_enabled(faction_a, faction_b))


## True if this unit's job fights (military roster).
static func is_fighter(unit: Dictionary) -> bool:
	return JobDefs.is_military(String(unit.get("job", "")))


## One AI tick for a single military unit record.
## Jeremy 2026-10-07: tap-command artillery rules. Artillery units
## (cannoneer job, or units crewing artillery with the "artillery" flag)
## never close to melee — they hold at range and kite when enemies get
## inside the dead zone.
## Jeremy 2026-10-07: ALL ranged units kite, not just artillery. Ranged
## units never let enemies close distance — they back away to maintain
## firing range.
const KITE_FRACTION := 0.35  ## kite when enemy inside 35% of range
const KITE_STEP := 160.0  ## world px to back away per kite decision
## Back-compat aliases.
const ARTY_KITE_FRACTION := KITE_FRACTION
const ARTY_KITE_STEP := KITE_STEP


static func is_artillery_unit(unit: Dictionary) -> bool:
	return String(unit.get("job", "")) == "cannoneer" \
		or bool(unit.get("artillery", false))


func tick_unit(unit: Dictionary, delta: float) -> void:
	if not unit.get("alive", false):
		return
	if bool(unit.get("downed", false)):
		return  # knocked out: out of the fight until revived
	var job: String = String(unit.get("job", ""))
	if not JobDefs.is_military(job):
		return
	_ensure_fields(unit)
	var stats: Dictionary = MILITARY_STATS.get(job, MILITARY_STATS["soldier"])
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var faction: String = String(unit.get("faction", ""))

	# Cooldown always ticks down.
	unit["attack_cd"] = maxf(0.0, float(unit.get("attack_cd", 0.0)) - delta)
	# Warlock summon cooldown ticks down.
	if float(unit.get("summon_cd", 0.0)) > 0.0:
		unit["summon_cd"] = maxf(0.0, float(unit.get("summon_cd", 0.0)) - delta)
	# Summoned spirits fade after their lifetime (HTML 18 s).
	if bool(unit.get("summoned", false)):
		var life: float = float(unit.get("summon_life", 18.0)) - delta
		unit["summon_life"] = life
		if life <= 0.0:
			unit["alive"] = false
			# Stamp death_time so _purge_corpses can reclaim the record
			# (without it the corpse linger check defaults to `now` and
			# faded spirits accumulate in _gs.units forever).
			unit["death_time"] = _gs.game_time
			_gs.bus.unit_died.emit(int(unit.get("id", 0)),
				String(unit.get("faction", "")))
			return

	# Zoning: troops garrisoned inside a military zone of their faction
	# recover hit points (the training-readiness bonus).
	if _gs.zoning != null:
		var regen: float = _gs.zoning.garrison_regen_at(upos, faction)
		if regen > 0.0:
			var mhp: float = float(unit.get("max_hp", 100.0))
			var hp: float = float(unit.get("hp", mhp))
			if hp < mhp:
				unit["hp"] = minf(mhp, hp + regen * delta)

	# Acquire nearest hostile unit (monsters included; downed skipped).
	# Siege engines (treant, bone_golem) prioritize buildings, but still
	# fight back against attackers in melee range.
	var is_siege: bool = bool(unit.get("siege", false))
	var deploy_kind: String = String(unit.get("deploy_target_kind", ""))
	var deploy_id: int = int(unit.get("deploy_target_id", -1))
	# Jeremy 2026-10-07: tap-command orders. "move" = walk there, ignore
	# enemies (aggro suppressed below). "attack_move" = advance, engaging
	# units first then buildings (building leg added below).
	var order_type: String = SimTapCommand.order_type_of(unit)
	var is_pure_move: bool = order_type == "move"
	var is_attack_move: bool = order_type == "attack_move"
	var target: Dictionary = {}
	# Jeremy 2026-10-04: disaster hunt order — military ordered to attack
	# a disaster beelines for it instead of nearest-hostile.
	var hunt_id: int = int(unit.get("disaster_hunt_id", -1))
	if hunt_id >= 0:
		var prey: Dictionary = _gs.get_unit(hunt_id)
		if not prey.is_empty() and prey.get("alive", false):
			target = prey
		else:
			unit["disaster_hunt_id"] = -1  # prey dead or gone
	# A hunt order takes precedence: the unit beelines for its disaster
	# instead of the nearest hostile. (The old if/else clobbered a found
	# hunt target with the close-range scan for non-siege units too.)
	# Jeremy 2026-10-07: tap-command auto-retaliation. A unit that was
	# attacked fights back against its attacker even without orders —
	# damage_unit stamps retaliate_id on survivors; it clears when the
	# attacker dies, goes down, or stops being hostile.
	if target.is_empty():
		var ret_id: int = int(unit.get("retaliate_id", -1))
		if ret_id >= 0:
			var att: Dictionary = _gs.get_unit(ret_id)
			if not att.is_empty() and att.get("alive", false) \
					and not bool(att.get("downed", false)) \
					and can_fight(faction, String(att.get("faction", ""))):
				target = att
			else:
				unit["retaliate_id"] = -1
	# Perf R15: idle soldiers stagger the aggro scan at 20Hz (every 3rd AI
	# slice) instead of every slice. Only applies when the unit is truly
	# order-free (no hunt, no deploy, no active target) — engaged, hunting,
	# or deployed units scan every slice, so combat behavior is unchanged.
	# Idle units notice new enemies up to ~2 slices later (imperceptible).
	var do_aggro_scan := true
	if target.is_empty() and hunt_id < 0 and deploy_kind == "" \
			and not bool(unit.get("deployed_for_war", false)) \
			and int(unit.get("combat_target", -1)) < 0 \
			and not unit.has("move_target"):
		# Jeremy 2026-10-07: units with an active move order are NOT idle
		# — the stagger must not early-return before move_target is
		# honored below, or tap-command move orders crawl at 1/3 speed.
		var acd: int = int(unit.get("_aggro_cd", 0))
		if acd > 0:
			unit["_aggro_cd"] = acd - 1
			do_aggro_scan = false
		else:
			unit["_aggro_cd"] = 2
	if not do_aggro_scan:
		# Perf R15: stagger skip — no unit scan ran this slice. Siege
		# units still need building targeting, so they fall through
		# (the unit-scan block below is guarded by do_aggro_scan).
		# Pure idle fighters preserve state and return: cooldowns and
		# garrison regen already ticked; the idle reset (which wipes
		# tactic_contact_t) waits for the next scan tick.
		var needs_building: bool = is_siege
		if not needs_building:
			return
	if target.is_empty() and do_aggro_scan and not is_pure_move:
		if is_siege:
			# Siege: only engage units in close self-defense (within 1.5x
			# melee reach); buildings are the priority.
			target = _nearest_hostile(upos, faction,
				float(stats["range"]) * 1.5)
		else:
			target = _nearest_hostile(upos, faction,
				float(stats["aggro"]))
	# Siege units, or troops with a building deploy order, or any deployed
	# troop with no units in range: target buildings.
	if target.is_empty():
		var btarget: Dictionary = {}
		# 1) Explicit deploy order to a building.
		if deploy_kind == "building" and deploy_id >= 0:
			var db: Dictionary = _get_building(deploy_id)
			if not db.is_empty() and can_fight(faction,
					String(db.get("faction", ""))):
				btarget = db
		# 2) Siege units, war-deployed troops, and attack-move orders seek
		# hostile buildings when no units are in range. (Plain aggro keeps
		# units-only targeting; attack-move explicitly wants the Jeremy
		# 2026-10-07 "units first, then buildings" behavior.)
		if btarget.is_empty() and (is_siege or deploy_kind == "building" \
				or bool(unit.get("deployed_for_war", false)) \
				or is_attack_move):
			btarget = _nearest_hostile_building(upos, faction,
				float(stats["aggro"]))
		if not btarget.is_empty():
			_tick_building_attack(unit, btarget, stats, delta)
			return
	if target.is_empty():
		# Jeremy 2026-10-04: AI move orders were silently discarded —
		# combat.tick_unit() never read move_target. Honor it now.
		if unit.has("move_target"):
			var mt: Vector2 = unit["move_target"]
			if upos.distance_to(mt) > 40.0:
				_walk_to(unit, mt, float(stats["speed"]), delta)
				unit["combat_state"] = "moving"
				return
			else:
				unit.erase("move_target")
		# Jeremy 2026-10-05: HTML tryBuyWeapon port (Economy AI: equipment).
		# Idle fighters spend their OWN coins at a weaponsmith for +1
		# weapon level — the faction treasury is never touched, so there
		# is no sovereignty question for the player faction either.
		if _tick_weapon_smith(unit, stats, delta):
			return
		unit["combat_state"] = "idle"
		unit["combat_target"] = -1
		unit["tactic_contact_t"] = -1.0  # tactics reset out of contact
		return
	var tpos: Vector2 = target.get("position", Vector2.ZERO)
	var dist: float = upos.distance_to(tpos)
	# Firearm range (HTML applyFirearmStats): ranged jobs use their tier's
	# range multiplier; melee keeps melee reach (blunderbuss = close-range).
	var wrange: float = float(stats["range"])
	if bool(stats["ranged"]):
		wrange *= _weapon_range_mult(unit)
	var is_arty: bool = is_artillery_unit(unit)
	var is_ranged: bool = bool(stats["ranged"])

	# Jeremy 2026-10-07: ranged units kite (artillery first, but ALL ranged).
	# An enemy inside the dead zone pushes the unit back to maintain firing
	# distance — never stand and take melee.
	if is_ranged and dist < wrange * KITE_FRACTION:
		var away: Vector2 = upos - tpos
		if away.length() < 1.0:
			away = Vector2.RIGHT
		_walk_to(unit, upos + away.normalized() * KITE_STEP,
			float(stats["speed"]), delta)
		unit["combat_state"] = "kiting"
		unit["combat_target"] = int(target.get("id", -1))
		return

	if dist <= wrange:
		# In range: plant feet and attack on cooldown (peek-fire from
		# cover when tactics repositioned us).
		unit["combat_state"] = "attacking"
		unit["combat_target"] = int(target.get("id", -1))
		_apply_tactics(unit, target, stats, dist, delta)
		if float(unit.get("attack_cd", 0.0)) <= 0.0:
			_attack(unit, target, stats)
	else:
		if is_ranged:
			# Jeremy 2026-10-07: ranged units never charge. They hold
			# their ground and fire at what's in range; repositioning
			# comes from player move/attack-move orders (move_target),
			# not from chasing individual targets.
			unit["combat_state"] = "holding"
			unit["combat_target"] = int(target.get("id", -1))
			if unit.has("move_target"):
				var mt2: Vector2 = unit["move_target"]
				if upos.distance_to(mt2) > 40.0:
					_walk_to(unit, mt2, float(stats["speed"]), delta)
			return
		var tac: String = _apply_tactics(unit, target, stats, dist, delta)
		if tac == "hold":
			# FIX phase: hold the formation line, engage when able.
			unit["combat_state"] = "holding"
			unit["combat_target"] = int(target.get("id", -1))
		elif tac == "moved":
			unit["combat_state"] = "repositioning"
			unit["combat_target"] = int(target.get("id", -1))
		else:
			# Chase, unless a guard would leave its post.
			if job == "guard":
				var post: Vector2 = unit.get("guard_post", upos)
				if tpos.distance_to(post) > GUARD_LEASH \
						and upos.distance_to(post) > 20.0:
					# Too far from post: walk home instead of chasing.
					_walk_to(unit, post, float(stats["speed"]), delta)
					unit["combat_state"] = "returning"
					return
			unit["combat_state"] = "chasing"
			unit["combat_target"] = int(target.get("id", -1))
			_walk_to(unit, tpos, float(stats["speed"]), delta)


## --- weapon shopping (HTML tryBuyWeapon port) --------------------------------
## Economy AI: equipment. Idle fighters spend their OWN coins (never the
## faction treasury) at a weaponsmith: walk there, pay the HTML-verbatim
## gold price (40/80/140), gain +1 weapon_level. Damage scales through the
## existing _weapon_dmg_mult / _weapon_range_mult, so the purchase is the
## only new behavior. HTML gates ported: level < 3, 0.004 roll, nearest
## complete smith within 500 px, walk-to within 50 px, personal coins.
## Deliberate deviations: guards hold their posts (no shopping trips);
## the unit must be truly order-free (no player_order, no deployment, no
## disaster hunt, no withdrawal — HTML's !midWork && !onCampaign); and a
## smith of a faction we're at war with is skipped (HTML said "any
## faction's smith serves anyone", but strolling into an enemy town to
## shop is suicide, not commerce).
const SMITH_SEEK_RANGE := 500.0  # px: how far an idle fighter looks
const SMITH_BUY_RANGE := 50.0    # px: close enough to pay the smith
const SMITH_ROLL_PER_TICK := 0.004  # HTML per-frame roll @60fps
const SMITH_LINES := {  # race-flavored purchase bubbles (HTML unitBubble)
	"gnomes": "New steel. About fucking time.",
	"ogres": "Sharper smash!",
}


## Returns true when this tick was consumed by the smith trip.
func _tick_weapon_smith(unit: Dictionary, stats: Dictionary,
		delta: float) -> bool:
	var lvl := int(unit.get("weapon_level", 0))
	if lvl >= MAX_WEAPON_LEVEL:
		unit.erase("_smith_id")
		return false
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var sid := int(unit.get("_smith_id", -1))
	if sid < 0:
		# Start a trip? Only the truly idle and order-free.
		if _weapon_trip_blocked(unit):
			return false
		# HTML 0.004/frame at 60fps, normalized to this unit's real
		# round-robin tick cadence (delta is slice-scaled).
		if randf() >= 1.0 - pow(1.0 - SMITH_ROLL_PER_TICK, 60.0 * delta):
			return false
		var shop := _find_weapon_shop(upos, String(unit.get("faction", "")))
		if shop.is_empty():
			return false
		unit["_smith_id"] = int(shop.get("id", -1))
		return true  # the walk itself starts on the next tick
	# Trip in progress: new orders abort it; the walk otherwise continues.
	if _weapon_trip_blocked(unit) or unit.has("move_target"):
		unit.erase("_smith_id")
		return false
	var smith := _get_building(sid)
	if smith.is_empty() or not bool(smith.get("alive", false)) \
			or not bool(smith.get("complete", false)):
		unit.erase("_smith_id")
		return false
	var spos: Vector2 = smith.get("position", Vector2.ZERO)
	if upos.distance_to(spos) > SMITH_BUY_RANGE:
		_walk_to(unit, spos, float(stats["speed"]), delta)
		unit["combat_state"] = "moving"
		return true
	# At the counter: pay personal coins, HTML gold price only (units
	# carry no wood). Damage/range follow via the weapon_level scaling.
	unit.erase("_smith_id")
	var cost: Dictionary = WEAPON_UPGRADES[lvl]
	var price := float(cost.get("gold", 40.0))
	var coins := float(unit.get("coins", 0.0))
	if coins < price:
		return false  # broke — back to idle; the roll may try again later
	unit["coins"] = coins - price
	unit["weapon_level"] = lvl + 1
	var faction: String = String(unit.get("faction", ""))
	_gs.bus.unit_said.emit(int(unit.get("id", -1)),
		String(SMITH_LINES.get(faction, "Weapon upgraded.")))
	return true


## True when the unit may not start (or must abort) a smith trip.
func _weapon_trip_blocked(unit: Dictionary) -> bool:
	if String(unit.get("job", "")) == "guard":
		return true  # post-holders don't wander off to shop
	if not (unit.get("player_order", {}) as Dictionary).is_empty():
		return true  # explicit player orders win
	if bool(unit.get("deployed_for_war", false)):
		return true
	if int(unit.get("deploy_target_id", -1)) >= 0:
		return true
	if int(unit.get("disaster_hunt_id", -1)) >= 0:
		return true
	if bool(unit.get("withdrawing", false)):
		return true
	if bool(unit.get("summoned", false)):
		return true  # spirits fade in 18 s; no shopping
	if bool(unit.get("fleeing", false)):
		return true
	return false


## Nearest usable weaponsmith: alive, complete, within seek range.
## Any faction's smith serves anyone (HTML 2026-09-19) except one we'd
## have to fight our way into.
func _find_weapon_shop(upos: Vector2, faction: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d := SMITH_SEEK_RANGE
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) != "weaponsmith":
			continue
		if not bool(b.get("alive", false)) \
				or not bool(b.get("complete", false)):
			continue
		if can_fight(faction, String(b.get("faction", ""))):
			continue
		var d: float = upos.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	return best


## Guard towers (completed) auto-fire arrows at hostiles in range.
## Jeremy 2026-10-04: staggered — 1/6th of buildings per frame (10Hz
## effective, delta scaled to compensate). Was: all buildings every frame.
func tick_towers(delta: float) -> void:
	var buildings: Array = _gs.buildings
	var n: int = buildings.size()
	if n == 0:
		return
	var slice: int = mini(maxi(1, n / 6), n)
	# Scale = frames per full pass (n/slice), not a hardcoded x6: with few
	# buildings the old x6 over-applied (a lone tower fired 6x too fast).
	var scaled_delta: float = delta * float(n) / float(slice)
	var idx: int = _tower_cursor % n
	for i: int in range(slice):
		_tick_tower(buildings[(idx + i) % n], scaled_delta)
	_tower_cursor = (idx + slice) % n


## Single-tower tick (extracted for staggering).
func _tick_tower(b: Dictionary, delta: float) -> void:
	if String(b.get("type", "")) != "guard_tower":
		return
	if not bool(b.get("complete", false)):
		return
	b["tower_cd"] = maxf(0.0, float(b.get("tower_cd", 0.0)) - delta)
	if float(b["tower_cd"]) > 0.0:
		return
	var bpos: Vector2 = b.get("position", Vector2.ZERO)
	var faction: String = String(b.get("faction", ""))
	var target: Dictionary = _nearest_hostile(bpos, faction,
		float(TOWER_STATS["range"]))
	if target.is_empty():
		return
	b["tower_cd"] = float(TOWER_STATS["cooldown"])
	# Zoning: towers inside a military zone of their faction hit harder.
	var dmg: float = float(TOWER_STATS["dmg"])
	if _gs.zoning != null:
		dmg *= _gs.zoning.defense_mult_at(bpos, faction)
	fire_projectile(bpos, int(target.get("id", -1)),
		target.get("position", Vector2.ZERO), "arrow",
		dmg, 0.0, faction,
		float(TOWER_STATS["proj_speed"]))


## Moves projectiles and resolves arrivals. Called every physics tick.
func tick(delta: float) -> void:
	_refresh_warlord_cache()  # Perf R27: per-frame warlord positions for _warlord_nearby
	_tick_projectiles(delta)
	# Jeremy 2026-10-04 perf: blood trail timer at 10Hz, not 60Hz.
	# It's a simple countdown; 0.1s granularity is invisible.
	_blood_accum += delta
	if _blood_accum >= 0.1:
		_tick_blood_trails(_blood_accum)
		_blood_accum = 0.0
	_tick_bleed(delta)
	_corpse_accum += delta
	if _corpse_accum >= 1.0:
		# Pass the real elapsed time (not a literal 1.0) so the downed
		# bleed-out clock doesn't drift slow over long sessions.
		var elapsed: float = _corpse_accum
		_corpse_accum = 0.0
		_purge_corpses()
		_tick_downed(elapsed)


## HTML parity: bloodTrailCd — the injured-unit blood drip timer.
## Set on heavy hits in damage_unit; decremented here so the visual side
## (world sync) only ever reads it.
## Jeremy 2026-10-04: staggered — 1/2 of units per 10Hz tick, delta scaled
## to compensate (n/slice, not a hardcoded x2).
func _tick_blood_trails(delta: float) -> void:
	var units: Array = _gs.units
	var n: int = units.size()
	if n == 0:
		return
	var slice: int = mini(maxi(1, n / 2), n)
	var scaled_delta: float = delta * float(n) / float(slice)
	var idx: int = _trail_cursor % n
	for i: int in range(slice):
		var u: Dictionary = units[(idx + i) % n]
		var cd: float = float(u.get("blood_trail_cd", 0.0))
		if cd > 0.0:
			u["blood_trail_cd"] = maxf(0.0, cd - scaled_delta)
	_trail_cursor = (idx + slice) % n


## Downed bleed-out (HTML: downedTimer / blood). A knocked-out unit with no
## medic dies when the timer runs out.
## Ticks EVERY unit on every 1Hz corpse tick — no staggering. The HTML
## decrements every downed unit's timer every frame; the 2026-10-04 stagger
## (1/4th of units per tick) let a downed unit live seconds past its timer,
## caught by test_army "downed: bleed-out kills when timer expires". The
## scan is two dict gets per unit at 1Hz — negligible — so the stagger
## bought nothing here. Do NOT re-stagger this without fixing that test.
func _tick_downed(delta: float) -> void:
	var units: Array = _gs.units
	var n: int = units.size()
	if n == 0:
		return
	for i: int in range(n):
		_tick_downed_unit(units[i], delta)


## Single-unit downed tick (extracted for staggering).
func _tick_downed_unit(u: Dictionary, delta: float) -> void:
	if not u.get("alive", false) or not bool(u.get("downed", false)):
		return
	var left: float = float(u.get("downed_timer", 0.0)) - delta
	u["downed_timer"] = left
	if left <= 0.0:
		var uid: int = int(u.get("id", 0))
		var by: String = String(u.get("downed_by", ""))
		u["downed"] = false
		if _gs.kill_unit(uid):
			u["death_time"] = _gs.game_time
			u["combat_state"] = "dead"
			_gs.bus.unit_killed.emit(uid, by)
			_gs.bus.unit_said.emit(uid, "Bled out")
			var dpos: Vector2 = u.get("position", Vector2.ZERO)
			_bus_blood(dpos, 12)
			_bus_gore(dpos, "chunk", 6)
			_bus_gore(dpos, "limb", 2)


## Doctors rush to downed allies and revive them (HTML medic behavior:
## 3.2x speed to a downed patient, heal on arrival).
## Doctors rush to downed units and revive them. Clerics share the medic
## duty (HTML MEDIC_JOBS: field_medic, doctor, cleric heal & cure); a
## cleric's revive also purges the zombie plague.
func tick_medics(delta: float) -> void:
	# Perf 2026-10-04 (30-min pass): patient index. One O(units) pass builds
	# the downed/seek_doctor list in unit order; each doctor then scans only
	# the index instead of all units (was O(doctors x units) per tick).
	# Provably identical: the index preserves unit order, the live
	# (alive / is_downed / seek_doctor) filter is re-checked per candidate
	# (a doctor earlier in this loop may have healed them), and no new
	# patients can appear inside this loop (revive/heal only clear states)
	# — so patient selection, weighting, and tie-breaks match the
	# brute-force scan exactly. Covered by tests/test_medic_index.gd.
	var patients: Array[Dictionary] = []
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and (is_downed(u) or bool(u.get("seek_doctor", false))):
			patients.append(u)
	if patients.is_empty():
		return
	for m: Dictionary in _gs.units:
		if not m.get("alive", false):
			continue
		var mjob: String = String(m.get("job", ""))
		if mjob != "doctor" and mjob != "cleric":
			continue
		var mpos: Vector2 = m.get("position", Vector2.ZERO)
		var faction: String = String(m.get("faction", ""))
		var patient: Dictionary = {}
		var best_d2: float = 800.0 * 800.0
		for u: Dictionary in patients:
			# Live re-check: an earlier doctor may have healed them.
			if not u.get("alive", false):
				continue
			# Downed units first; injured limb-loss victims (seek_doctor)
			# second — HTML medic heals both.
			if not is_downed(u) and not bool(u.get("seek_doctor", false)):
				continue
			if String(u.get("faction", "")) != faction:
				continue
			var d2: float = mpos.distance_squared_to(
				u.get("position", Vector2.ZERO))
			# Prefer the truly downed: weight their distance lower.
			if not is_downed(u):
				d2 *= 4.0
			if d2 < best_d2:
				best_d2 = d2
				patient = u
		if patient.is_empty():
			continue
		var ppos: Vector2 = patient.get("position", Vector2.ZERO)
		if mpos.distance_to(ppos) <= 40.0:
			if is_downed(patient):
				if revive_unit(int(patient.get("id", 0))):
					# Clerics purge the zombie plague on revive
					# (HTML: doctors & clerics cure the infection).
					if mjob == "cleric":
						(patient as Dictionary).erase("infected")
					_gs.bus.unit_said.emit(int(m.get("id", 0)),
						"You're going to be fine!")
			elif bool(patient.get("seek_doctor", false)):
				# HTML doctor heal: full hp, blood restored, bleeding
				# stopped. Limbs stay lost (permanent).
				patient["hp"] = float(patient.get("max_hp", 100.0))
				patient["blood"] = 100.0
				patient["bleed_rate"] = 0.0
				patient["injured"] = false
				patient["seek_doctor"] = false
				patient["blood_trail_cd"] = 0.0
				_gs.bus.unit_said.emit(int(m.get("id", 0)),
					"You're going to be fine!")
		else:
			var spd: float = float(m.get("speed", 90.0)) * 3.2
			_walk_to(m, ppos, spd, delta)


## Fires a projectile record. Emits projectile_fired for the visual layer.
func fire_projectile(from_pos: Vector2, target_id: int, target_pos: Vector2,
		kind: String, dmg: float, splash: float, faction: String,
		speed: float) -> Dictionary:
	# Guard: a zero/negative speed leaves a projectile that can never
	# arrive (step = 0, dist > 6 forever) — an immortal record that grows
	# the projectiles array without bound. Clamp to a sane minimum.
	speed = maxf(speed, 50.0)
	var p: Dictionary = {
		"id": _next_proj_id,
		"kind": kind,  # "arrow" | "spell" | "cannonball"
		"position": from_pos,
		"target_id": target_id,
		"target_pos": target_pos,
		"dmg": dmg,
		"splash": splash,
		"faction": faction,
		"speed": speed,
		"alive": true,
	}
	_next_proj_id += 1
	projectiles.append(p)
	_gs.bus.projectile_fired.emit(p)
	return p


## Jeremy 2026-10-07 (wake audio lane): throttled melee-contact SFX.
## Emits at most SFX_MELEE_PER_BUCKET "hit" sounds per 0.1 s game-time
## bucket — the crunch of a big battle without pool exhaustion.
func _emit_melee_hit(pos: Vector2) -> void:
	var bucket: int = int(_gs.game_time / SFX_MELEE_BUCKET)
	if bucket != _sfx_melee_bucket:
		_sfx_melee_bucket = bucket
		_sfx_melee_n = 0
	if _sfx_melee_n >= SFX_MELEE_PER_BUCKET:
		return
	_sfx_melee_n += 1
	_gs.bus.sfx_spatial.emit("hit", pos, Vector2.ZERO)


## Applies damage to a unit. Returns true if the unit died.
## Sets combat "hurt" flash state on survivors (animator reads it).
## attacker_id is the attacking unit's id (-1 when unknown, e.g. splash);
## it lets the mind record who did it.
## kind is the projectile kind ("arrow"|"spell"|"cannonball", "" = melee):
## cannonball hits are always lethal (HTML: artillery blows units apart).
##
## Knockout rule (HTML goDowned parity): a fighter dropped by a direct
## unit-vs-unit hit goes DOWNED — alive but out of the fight, revivable by
## a doctor — instead of dying. Splash, artillery, and unknown-source hits
## kill outright, as do hits on non-fighters.
func damage_unit(unit_id: int, dmg: float, source_faction: String,
		attacker_id: int = -1, kind: String = "") -> bool:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty() or not u.get("alive", false):
		return false
	# Downed units can't be hit again (HTML canAttackTarget skips downed).
	if bool(u.get("downed", false)):
		return false
	# Jeremy 2026-10-04: Seven Monasteries.
	# Durnhelm's Aegis: a ward absorbs damage first.
	if monasteries != null:
		dmg = monasteries.absorb_shield(u, dmg)
		if dmg <= 0.0:
			return false  # fully absorbed by the ward
		# Ostra's Truthbeam: illuminated targets take +25% from everything.
		if float(u.get("illum_t", 0.0)) > 0.0:
			dmg *= 1.25
	# Adventure hook: the hero mitigates via armor + vitality.
	if adventure != null:
		dmg = float(adventure.mitigate_damage(unit_id, dmg))
	# Cover: dug-in / sheltered units take less (HTML inCover x0.65).
	if bool(u.get("in_cover", false)):
		dmg *= COVER_DMG_MUL
	# Jeremy 2026-10-08 (rapid-iteration): floating damage numbers. The
	# final mitigated amount goes to the world layer so every landed hit —
	# grazes, downing blows, and kills alike — reads on the battlefield.
	# Ward-absorbed (dmg <= 0) and downed-target hits returned above, so
	# they correctly show nothing.
	_gs.bus.unit_damaged.emit(unit_id, dmg, u.get("position", Vector2.ZERO), kind)
	# Jeremy 2026-10-11: veteran fighters hit harder — combat skill scales
	# damage dealt (1 + 0.08/level). Cheap dict read on the hot path.
	if attacker_id >= 0:
		var _att: Dictionary = _gs.get_unit(attacker_id)
		if not _att.is_empty():
			dmg *= SimSkills.combat_mult(_att)
	# Jeremy 2026-10-07 (wake audio lane): melee contact finally has a
	# sound. Projectile impacts already sound via world._on_projectile_hit,
	# so only direct melee hits (kind == "") emit here — throttled per
	# 0.1 s bucket so big battles don't exhaust the spatial SFX pool.
	if kind == "":
		_emit_melee_hit(u.get("position", Vector2.ZERO))
	u["last_hit_time"] = _gs.game_time  # micro-tactics "under fire" window
	var hp: float = float(u.get("hp", 100.0)) - dmg
	u["hp"] = hp
	if hp <= 0.0:
		var artillery: bool = kind == "cannonball"
		if not artillery and attacker_id >= 0 and is_fighter(u):
			_go_downed(u, source_faction)
			return false
		if _gs.kill_unit(unit_id):
			u["death_time"] = _gs.game_time
			u["combat_state"] = "dead"
			_gs.bus.unit_killed.emit(unit_id, source_faction)
			# Lane 2 (war counsel, Jeremy 2026-10-06): kill credit for
			# notable-fallen reports — veterans are named by kill count.
			if attacker_id >= 0:
				var att: Dictionary = _gs.get_unit(attacker_id)
				if not att.is_empty():
					att["kills"] = int(att.get("kills", 0)) + 1
					# Jeremy 2026-10-11: fighters level combat by killing.
					SimSkills.grant(_gs, att, "combat", 12.0)
			var dpos: Vector2 = u.get("position", Vector2.ZERO)
			if kind == "cannonball":
				# HTML parity: rockets / artillery blow units to bits —
				# never just downed. The "holy shit" gib moment.
				_bus_blood(dpos, 16)
				_bus_gore(dpos, "chunk", 16)
				_bus_gore(dpos, "limb", 6)
				_gs.bus.combat_fx.emit(
					"gib_" + String(u.get("faction", "humans")), dpos)
			else:
				# HTML kill-gore parity: chunks + a limb burst so ordinary
				# combat deaths read as deaths.
				_bus_blood(dpos, 5)
				_bus_gore(dpos, "chunk", 6)
				_bus_gore(dpos, "limb", 2)
			# Jeremy 2026-10-04: attribute disaster deaths for the Gazette.
			var d = _gs.disasters
			if d != null and d.has_method("attribute_death"):
				d.attribute_death(u, source_faction, attacker_id)
		return true
	u["hurt_flash"] = 0.45  # animator shows HURT for one clip
	u["combat_state"] = "hurt"
	# HTML parity: a heavy hit (hp < 45% of max) starts an 8-second blood
	# trail — injured units drip blood particles while the timer runs.
	if hp < float(u.get("max_hp", 100.0)) * 0.45:
		u["blood_trail_cd"] = 8.0
	# HTML parity: rollInjury — the injury dice runs on every survived hit.
	# Cannonball hits are artillery (brutal limb-loss odds).
	roll_injury(u, dmg, kind == "cannonball")
	# Undead infection: zombie/plaguebearer hits can infect (undead port).
	if _gs.get("undead") != null and attacker_id >= 0:
		_gs.undead.maybe_infect_on_hit(_gs.get_unit(attacker_id), u)
	# Spellweaver snare: spellweaver hits slow the victim x0.5 for 6 s
	# (faction roster port).
	if _gs.get("factions") != null and attacker_id >= 0:
		if _gs.factions.maybe_snare_on_hit(_gs.get_unit(attacker_id), u):
			_gs.bus.combat_fx.emit("snare",
				u.get("position", Vector2.ZERO))
	# Mind hook: the victim remembers, feels, and may flee.
	if mind != null:
		mind.on_attacked(u, _gs.get_unit(attacker_id), dmg, source_faction)
	# Jeremy 2026-10-07: tap-command auto-retaliation. A military unit that
	# survives a hit stamps its attacker — tick_unit picks the attacker up
	# as its target and fights back without needing a player order.
	if attacker_id >= 0 and is_fighter(u) and not bool(u.get("downed", false)):
		var att: Dictionary = _gs.get_unit(attacker_id)
		if not att.is_empty() \
				and can_fight(String(u.get("faction", "")), String(att.get("faction", ""))):
			u["retaliate_id"] = attacker_id
	return false


## Knocks a fighter out of the fight without killing them (HTML goDowned).
## Alive, immobile, untargetable; bleeds out after DOWNED_BLEEDOUT unless
## a doctor revives them.
func _go_downed(u: Dictionary, source_faction: String) -> void:
	u["downed"] = true
	u["downed_timer"] = DOWNED_BLEEDOUT
	u["hp"] = 0.0
	u["in_cover"] = false
	u["combat_state"] = "downed"
	u["combat_target"] = -1
	u["downed_by"] = source_faction
	var faction: String = String(u.get("faction", "humans"))
	# HTML goDowned gore parity: blood burst + chunks + limb burst; a downed
	# unit starts the bleed clock hard.
	_ensure_gore_fields(u)
	var dpos: Vector2 = u.get("position", Vector2.ZERO)
	_bus_blood(dpos, 5)
	_bus_gore(dpos, "chunk", 6)
	_bus_gore(dpos, "limb", 2)
	u["bleed_rate"] = maxf(float(u["bleed_rate"]), 8.0)
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		String(DOWNED_CRY.get(faction, "Ahhh! Help!")))


## Revives a downed unit (doctor/medic path, HTML medic revive).
## Returns false when the unit isn't downed.
func revive_unit(unit_id: int) -> bool:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty() or not u.get("alive", false):
		return false
	if not bool(u.get("downed", false)):
		return false
	u["downed"] = false
	u["downed_timer"] = 0.0
	u["hp"] = float(u.get("max_hp", 100.0))
	u["combat_state"] = "idle"
	u["combat_target"] = -1
	u.erase("downed_by")
	# A revived unit is stabilized like a doctor heal (HTML medic revive):
	# without this the bleed_rate >= 8.0 stamped by _go_downed drains its
	# blood pool and it bleeds out minutes after being saved — and revived
	# units never re-enter the medic patient list (no seek_doctor), so no
	# doctor would ever stop the bleeding.
	u["blood"] = 100.0
	u["bleed_rate"] = 0.0
	u["injured"] = false
	u["blood_trail_cd"] = 0.0
	return true


## True when the unit is knocked out (alive but out of the fight).
static func is_downed(unit: Dictionary) -> bool:
	return bool(unit.get("downed", false)) and bool(unit.get("alive", false))


## Damages a building (siege, monsters, splash). Destroys at 0 hp.
func damage_building(building_id: int, dmg: float,
		source_faction: String) -> bool:
	var b: Dictionary = _get_building(building_id)
	if b.is_empty():
		return false
	var hp: float = float(b.get("hp", 400.0)) - dmg
	b["hp"] = hp
	if hp <= 0.0:
		# Jeremy 2026-10-06: Command Posts (Battlefront directive) — a
		# hall felled by enemy WAR action is CAPTURED, not destroyed.
		# The town and its land flip to the attacker.
		if _is_hall_capture(b, source_faction):
			_flip_hall(b, source_faction)
			return true
		b["destroyed"] = true
		_gs.erase_building(b)
		# Jeremy 2026-10-11 (war-spare/aid votes): who felled it decides
		# which vote fires — a real faction means the fate vote, anything
		# else (fire/monster/"") means the disaster-aid vote.
		b["destroyed_by"] = source_faction
		_gs.bus.building_destroyed.emit(b)
		# Jeremy 2026-10-07 (wake audio lane): a felled building finally
		# makes a sound — the "explode" SFX at the rubble.
		_gs.bus.sfx_spatial.emit("explode",
			b.get("position", Vector2.ZERO), Vector2.ZERO)
		# Jeremy 2026-10-08 (wake rapid-iteration): player-facing alert when
		# YOUR buildings are destroyed mid-raid (queued recon finding from the
		# damage-numbers lane). Urgent Gazette story -> UrgentToast pops +
		# Chronicle records it. AI-vs-AI destruction stays toast-quiet; the
		# rubble/explosion FX already cover those battlefields.
		var owner: String = String(b.get("faction", ""))
		if owner != "" and owner == _gs.player_faction:
			var bname: String = SimBuildings.building_name(
				String(b.get("type", "")))
			var cause: String = "unknown raiders" if source_faction == "" \
				else "%s's troops" % _fname(source_faction)
			# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
			SimGazette.publish_or_emit(_gs,
				"Your %s was destroyed!" % bname,
				"Your %s has been destroyed by %s. Rebuild it from the build menu before the next raid." % [bname, cause],
				"war" if source_faction != "" else "disaster",
				{"urgent": true})
		return true
	return false


## Command-post capture test: only war action flips a hall. Disasters,
## decay, and accidents still destroy.
func _is_hall_capture(b: Dictionary, source_faction: String) -> bool:
	if not String(b.get("type", "")) in SimTerritory.CLAIM_TYPES:
		return false
	if source_faction == "":
		return false
	var holder: String = String(b.get("faction", ""))
	if holder == "" or holder == source_faction:
		return false
	return can_fight(source_faction, holder)


## Flip a captured hall: faction, town record, Gazette, rename prompt.
## The building survives at 25% HP — burning, needs repair.
func _flip_hall(b: Dictionary, new_faction: String) -> void:
	var old: String = String(b.get("faction", ""))
	var max_hp: float = float(b.get("max_hp",
		b.get("hp", 1200.0)))
	b["faction"] = new_faction
	b["hp"] = maxf(1.0, max_hp * 0.25)
	b["captured_t"] = 0.0
	var bpos: Vector2 = b.get("position", Vector2.ZERO)
	var pname: String = String(b.get("town_name", "Town"))
	# The town goes with its hall.
	var tid: int = int(b.get("town_id", -1))
	if _gs.towns.has(tid):
		(_gs.towns[tid] as Dictionary)["faction"] = new_faction
	# Unified capture signal + log (drives territory flip + war score).
	var cps = _gs.get("command_posts")
	if cps != null and cps.has_method("log_capture"):
		cps.log_capture("town", int(b.get("id", 0)), old, new_faction,
			bpos, pname)
	else:
		# Bare contexts (tests) without command_posts wired: the capture
		# still happened — emit the signal directly so listeners (the
		# conquest prompt) behave identically. Exactly-once either way.
		_gs.bus.command_post_captured.emit("town", int(b.get("id", 0)),
			old, new_faction, bpos)
	# Jeremy 2026-10-07 (wake audio lane): a command post flipping sides
	# is the war's loudest moment — the war horn stinger at the hall.
	_gs.bus.sfx_spatial.emit("war_horn", bpos, Vector2.ZERO)
	# Jeremy 2026-10-08 (wake rapid-iteration): losing YOUR hall is the
	# raid's loudest moment — toast it urgently. AI-vs-AI captures stay
	# toast-quiet (no spam). Chronicle archive + bus (news-desk rule).
	SimGazette.publish_or_emit(_gs,
		"%s seizes %s" % [_fname(new_faction), pname],
		"%s's troops have stormed %s and raised their banner over the hall. The town and all its claimed land now answer to %s." % [
			_fname(new_faction), pname, _fname(new_faction)],
		"war",
		{"urgent": old != "" and old == _gs.player_faction})
	# Jeremy 2026-10-07 (graphics hourly): the town-capture fanfare moved to
	# the world's _on_command_post_captured — a one-shot flash in the
	# conqueror's faction color. The old combat_fx "capture_taken" here was
	# wrong: the world flashes the nearest MONASTERY for that kind, so a
	# town falling near a monastery lit up the wrong building.
	# (Monasteries/crystals keep their own "capture_taken" fanfare.)
	# Keep-or-rename prompt for the player's conquests (HTML parity):
	# log_capture (above) emitted command_post_captured, which queues the
	# prompt in SimArmy — no gs.army lookup needed (Lane 3, 2026-10-06).


func _fname(faction: String) -> String:
	return String(Config.FACTIONS.get(faction, {}).get("name", faction))


## ---- internals --------------------------------------------------------


func _ensure_fields(unit: Dictionary) -> void:
	if not unit.has("attack_cd"):
		unit["attack_cd"] = 0.0
	if not unit.has("combat_state"):
		unit["combat_state"] = "idle"
	if not unit.has("combat_target"):
		unit["combat_target"] = -1
	if not unit.has("guard_post"):
		unit["guard_post"] = unit.get("position", Vector2.ZERO)
	if not unit.has("speed"):
		var job: String = String(unit.get("job", "soldier"))
		unit["speed"] = float(
			MILITARY_STATS.get(job, MILITARY_STATS["soldier"])["speed"])
	# Knockout / tactics / loadout fields (army system writes most of these).
	if not unit.has("downed"):
		unit["downed"] = false
	if not unit.has("downed_timer"):
		unit["downed_timer"] = 0.0
	if not unit.has("last_hit_time"):
		unit["last_hit_time"] = -999.0
	if not unit.has("in_cover"):
		unit["in_cover"] = false
	if not unit.has("firearm"):
		unit["firearm"] = "basic"
	if not unit.has("weapon_level"):
		unit["weapon_level"] = 0
	if not unit.has("coins"):
		# HTML: units start with 20-40 coins (matches SimHousing/_ensure_coins
		# and WorkerAI) — fighters need pocket money for the weaponsmith.
		unit["coins"] = 20.0 + float(int(unit.get("id", 0)) % 40)
	if not unit.has("_aggro_cd"):
		# Perf R15: idle target-acquisition scans run at 20Hz (every 3rd AI
		# slice) instead of every slice. Init staggered by unit id so idle
		# soldiers don't all scan on the same tick.
		unit["_aggro_cd"] = int(unit.get("id", 0)) % 3


func _attack(unit: Dictionary, target: Dictionary, stats: Dictionary) -> void:
	# Jeremy 2026-10-04: Seven Monasteries — Felicity's Jubilance speeds up
	# attacks for inspired units.
	var cd_mult := 1.0
	if monasteries != null:
		cd_mult = monasteries.attack_rate_mult(unit)
	unit["attack_cd"] = float(stats["cooldown"]) * cd_mult
	var tid: int = int(target.get("id", -1))
	var faction: String = String(unit.get("faction", ""))
	var uid: int = int(unit.get("id", -1))
	var job: String = String(unit.get("job", ""))
	# Adventure hook: level-scaled denizens / the Bandit King carry their
	# own damage via dmg_override (the stats table is fixed).
	var dmg: float = float(unit.get("dmg_override", float(stats["dmg"])))
	# Race-based damage (HTML RACES table): ogres hit like trucks, gnomes
	# hit 1.4x — and 1.75x on magic. Jeremy 2026-10-02 audit.
	var rmod: Dictionary = RACE_COMBAT.get(faction, {"dmg_mul": 1.0, "magic_mul": 1.0})
	if job == "mage":
		dmg *= float(rmod.get("magic_mul", 1.0))
	else:
		dmg *= float(rmod.get("dmg_mul", 1.0))
	# Firearm tier + weaponsmith upgrades (HTML applyFirearmStats):
	# dmg x tier_mul x (1 + 0.08 x weapon_level).
	dmg *= _weapon_dmg_mult(unit)
	# Jeremy 2026-10-04: food perk strength modifier (Sausage Strength etc.).
	dmg *= SimFoodPerks.get_modifier(unit, "strength", _gs.game_time)
	# Policies: guard tier strength (HTML guard policy parity).
	if job == "guard" \
			and _gs.get("court_sys") != null \
			and _gs.court_sys.get("policies") != null:
		dmg *= _gs.court_sys.policies.guard_strength_mult()
	# Warlord aura: nearby allied warlord's troops hit harder (HTML x1.25).
	# The aura61 timer is the warlord JOB's pulse (factions.gd); the
	# _warlord_nearby check is the promoted-warlord flag (army.gd).
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var tpos: Vector2 = target.get("position", Vector2.ZERO)
	if _warlord_nearby(upos, faction, uid) \
			or float(unit.get("aura61", 0.0)) > 0.0:
		dmg *= WARLORD_AURA_MUL
	# Faction roster hooks (HTML C61): cleric smites the undead x1.6;
	# knight cavalry charge x2.2 after a >200 px approach.
	if job == "cleric" and String(target.get("faction", "")) == "undead":
		dmg = floorf(dmg * SimFactions.CLERIC_SMITE_MUL)
	if job == "knight" \
			and upos.distance_squared_to(tpos) > SimFactions.KNIGHT_CHARGE_RANGE2:
		dmg = floorf(dmg * SimFactions.KNIGHT_CHARGE_MUL)
	# Cliffs: high-ground combat edge (HTML cgHighGroundMul83) — attacking
	# down from a higher level hits +15% harder per level, capped at +45%.
	var hg_mult: float = Cliffs.high_ground_mult(_gs.map_data, upos, tpos)
	# War horn stinger: first attack after 20 s of calm (HTML playWarHorn).
	if _gs.game_time - _last_horn_time > WAR_HORN_COOLDOWN:
		_last_horn_time = _gs.game_time
		_gs.bus.sfx_spatial.emit("war_horn", upos, Vector2.ZERO)
	# Blunderbuss: 5-pellet cone instead of a single shot (HTML).
	if job == "blunderbuss":
		_fire_blunderbuss(unit, tpos, dmg)
		_fire_monastery_magic(unit, target, tpos, upos)
		_fire_crystal_dark(unit, target, tpos, upos)
		return
	if bool(stats["ranged"]):
		var kind := "arrow"
		var fx_kind := ""
		match job:
			"mage":
				kind = "spell"
				# Rotating spells (HTML): fireball / lightning / arcane.
				var spell_idx: int = int(unit.get("spell_idx", 0)) \
					% SimFactions.MAGE_SPELLS.size()
				var spell: Dictionary = SimFactions.MAGE_SPELLS[spell_idx]
				unit["spell_idx"] = spell_idx + 1
				dmg = floorf(dmg * float(spell.get("mul", 1.0)))
				fx_kind = "spell_" + String(spell.get("kind", "fire"))
				if fx_kind == "spell_fireball":
					fx_kind = "spell_fire"
			"cannoneer":
				kind = "cannonball"
			"musketeer":
				kind = "bullet"
				fx_kind = "muzzle_big"
			"warlock":
				kind = "spell"
				fx_kind = "spell_nature"
				# Warlock summons nature spirits (HTML: 35% while fighting,
				# 8 s cooldown).
				_maybe_warlock_summon(unit, upos, faction)
			"spellweaver":
				kind = "spell"
				fx_kind = "spell_arcane"
			"necromancer", "lich":
				kind = "spell"
				fx_kind = "spell_arcane"
		if fx_kind != "":
			_gs.bus.combat_fx.emit(fx_kind, upos)
		elif job == "archer" or job == "ranger":
			_gs.bus.combat_fx.emit("muzzle", upos)
		var p := fire_projectile(upos, tid, tpos, kind,
			dmg, float(stats["splash"]), faction,
			float(stats["proj_speed"]))
		p["from_pos"] = upos  # high-ground mult on direct hits
		p["attacker_id"] = uid  # knockout rule + splash attribution
		if fx_kind != "":
			p["fx_kind"] = fx_kind
		_fire_monastery_magic(unit, target, tpos, upos)
		_fire_crystal_dark(unit, target, tpos, upos)
	else:
		damage_unit(tid, dmg * hg_mult, faction, uid)
		# Faction melee FX: berserker/warlord slam, knight charge.
		if job == "berserker" or job == "warlord" \
				or bool(unit.get("warlord", false)):
			_gs.bus.combat_fx.emit("siege_hit", tpos)
		# Warlord cleave: melee splash around the target (HTML splash 80).
		if bool(unit.get("warlord", false)):
			_warlord_splash(tpos, dmg * hg_mult * 0.5, faction, tid, uid)
		_fire_monastery_magic(unit, target, tpos, upos)
		_fire_crystal_dark(unit, target, tpos, upos)


## Jeremy 2026-10-04: Seven Monasteries — every captured monastery grants
## the faction a stacking magical ranged attack on top of the unit's normal
## attack. Melee units hurl it too (a holy bolt from their hands).
func _fire_monastery_magic(unit: Dictionary, target: Dictionary,
		tpos: Vector2, upos: Vector2) -> void:
	if monasteries == null:
		return
	# Magic needs a live target position; building targets go through
	# _attack_building which handles its own magic below.
	if target.is_empty():
		return
	monasteries.fire_magic_attacks(unit, target, tpos, upos)


## Jeremy 2026-10-04: Seven Dark Crystals — every unit of a crystal-holding
## faction hurls devastating dark blasts (TWO per attack) on top of their
## normal attack and monastery magic. Melee units hurl them too.
func _fire_crystal_dark(unit: Dictionary, target: Dictionary,
		tpos: Vector2, upos: Vector2) -> void:
	if crystals == null:
		return
	if target.is_empty():
		return
	crystals.fire_dark_attacks(unit, target, tpos, upos)


## Blunderbuss 5-pellet cone (HTML): each pellet flies 95 px along its
## spread angle and bursts (splash 32/0.5) for floor(dmg*0.55).
func _fire_blunderbuss(unit: Dictionary, tpos: Vector2, dmg: float) -> void:
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var faction: String = String(unit.get("faction", ""))
	var uid: int = int(unit.get("id", -1))
	var base_ang: float = (tpos - upos).angle()
	var pellet_dmg: float = floorf(dmg * SimFactions.BLUNDER_PELLET_DMG_MUL)
	for i: int in SimFactions.BLUNDER_PELLETS:
		var ang: float = base_ang \
			+ (float(i) - 2.0) * SimFactions.BLUNDER_SPREAD
		var hit_pos: Vector2 = upos \
			+ Vector2(cos(ang), sin(ang)) * SimFactions.BLUNDER_RANGE
		var p: Dictionary = fire_projectile(upos, -1, hit_pos, "shotgun",
			pellet_dmg, SimFactions.BLUNDER_SPLASH, faction,
			SimFactions.BLUNDER_PROJ_SPEED)
		p["splash_mul"] = SimFactions.BLUNDER_SPLASH_MUL
		p["attacker_id"] = uid  # knockout rule + splash attribution


## Warlock nature-spirit summon (HTML: 35% roll while fighting, 8 s
## cooldown; spirit hp 40 / dmg 12 / range 40 / 18 s life).
func _maybe_warlock_summon(unit: Dictionary, upos: Vector2,
		faction: String) -> void:
	var cd: float = float(unit.get("summon_cd", 0.0))
	if cd > 0.0:
		return
	if randf() > SimFactions.WARLOCK_SUMMON_CHANCE:
		return
	unit["summon_cd"] = SimFactions.WARLOCK_SUMMON_CD
	# Spawn the spirit as a temporary allied unit.
	var spirit: Dictionary = _gs.add_unit({
		"faction": faction,
		"job": "spirit",
		"town_id": int(unit.get("town_id", -1)),
		"position": upos + Vector2(randf_range(-30.0, 30.0),
			randf_range(-30.0, 30.0)),
		"alive": true,
		"hp": SimFactions.SPIRIT_HP,
		"max_hp": SimFactions.SPIRIT_HP,
		"dmg": SimFactions.SPIRIT_DMG,
		"speed": 110.0,
		"range": SimFactions.SPIRIT_RANGE,
		"summoned": true,
		"summon_life": SimFactions.SPIRIT_LIFE,
	})
	_gs.bus.unit_spawned.emit(spirit)
	_gs.bus.combat_fx.emit("spell_nature", upos)
	_gs.bus.unit_said.emit(int(unit.get("id", -1)), "Rise, spirit!")


## Firearm + weaponsmith damage multiplier for a unit.
func _weapon_dmg_mult(unit: Dictionary) -> float:
	var fw: Dictionary = FIREARMS.get(String(unit.get("firearm", "basic")),
		FIREARMS["basic"])
	return float(fw.get("dmg_mul", 1.0)) \
		* (1.0 + WEAPON_LEVEL_DMG * float(int(unit.get("weapon_level", 0))))


## Firearm range multiplier (ranged jobs only; melee keeps melee reach).
func _weapon_range_mult(unit: Dictionary) -> float:
	var fw: Dictionary = FIREARMS.get(String(unit.get("firearm", "basic")),
		FIREARMS["basic"])
	return float(fw.get("range_mul", 1.0))


## Display name + icon for a unit's firearm (HTML firearmName/firearmIcon).
static func firearm_name(faction: String, tier: String) -> String:
	var row: Dictionary = FIREARM_NAMES.get(faction, FIREARM_NAMES["humans"])
	var cell: Array = row.get(tier, row["basic"])
	return String(cell[0])


static func firearm_icon(faction: String, tier: String) -> String:
	var row: Dictionary = FIREARM_NAMES.get(faction, FIREARM_NAMES["humans"])
	var cell: Array = row.get(tier, row["basic"])
	return String(cell[1])


## True when a living allied warlord stands within aura range.
func _warlord_nearby(upos: Vector2, faction: String, self_id: int) -> bool:
	# Perf R27: served from the per-tick warlord position cache instead of
	# a full unit scan. Same filter set (alive, not downed, same faction,
	# warlord flag), same strict distance test, self excluded — bit-identical
	# results to the old linear scan.
	if not _warlord_cache_init:
		_refresh_warlord_cache()
	var r2: float = WARLORD_AURA_RANGE * WARLORD_AURA_RANGE
	var spots: Dictionary = _warlord_cache.get(faction, {})
	for wid in spots:
		if int(wid) == self_id:
			continue
		if upos.distance_squared_to(spots[wid]) < r2:
			return true
	return false


## Perf R27: rebuild the warlord position cache once per frame. Warlords
## are rare (a handful per faction at most), so this turns _warlord_nearby
## from O(all units) per attack into O(warlords of one faction) per attack
## at the cost of one O(units) pass per frame.
func _refresh_warlord_cache() -> void:
	var cache := {}
	for u: Dictionary in _gs.units:
		if not bool(u.get("warlord", false)):
			continue
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		var f: String = String(u.get("faction", ""))
		var pos: Vector2 = u.get("position", Vector2.ZERO)
		var wid: int = int(u.get("id", -1))
		if cache.has(f):
			(cache[f] as Dictionary)[wid] = pos
		else:
			cache[f] = {wid: pos}
	_warlord_cache = cache
	_warlord_cache_init = true


## Warlord melee splash (HTML splashRadius 80, splashMul 0.5).
func _warlord_splash(impact: Vector2, dmg: float, faction: String,
		skip_id: int, attacker_id: int) -> void:
	var r2: float = WARLORD_SPLASH * WARLORD_SPLASH
	for u: Dictionary in _gs.units:
		if int(u.get("id", -1)) == skip_id:
			continue
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if not can_fight(faction, String(u.get("faction", ""))):
			continue
		if impact.distance_squared_to(u.get("position", Vector2.ZERO)) \
				<= r2:
			damage_unit(int(u.get("id", 0)), dmg, faction, attacker_id)


func _unit_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / UNIT_GRID_CELL)),
		int(floor(pos.y / UNIT_GRID_CELL)))


## Rebuilds the unit grid when the physics frame has advanced — at most one
## O(units) rebuild per frame no matter how many _nearest_hostile queries
## run. Units move every frame, so the grid is inherently per-frame data.
## A unit-count change also triggers a rebuild (spawns/purges mid-frame;
## headless tests that spawn between ticks without advancing the clock).
## Tests: call _invalidate_unit_grid() after moving units mid-frame.
func _sync_unit_grid() -> void:
	var frame: int = Engine.get_physics_frames()
	var n: int = _gs.units.size()
	if frame == _unit_grid_frame and n == _unit_grid_n:
		return
	_unit_grid_frame = frame
	_unit_grid_n = n
	# Perf R23: inlined _unit_cell and hoisted the grid ref out of the
	# loop — the per-unit call + member lookups were ~25% of rebuild cost.
	# Perf R32: pairs pack flat as [unit, idx, ...] in the cell array, so
	# the per-unit [u, i] array allocation is gone (~2/3 fewer allocs per
	# rebuild). Same dict-op count, same contents and pair order.
	var grid := _unit_grid
	grid.clear()
	# Perf R43: tally alive non-downed units per faction for the
	# _nearest_hostile early-out. Mirrors _scan_hostile_cell's skip filters
	# exactly; piggybacked on the rebuild's unit loop (no extra pass).
	_faction_alive.clear()
	var tally: Dictionary = _faction_alive
	var units: Array = _gs.units
	for i in range(units.size()):
		var u: Dictionary = units[i]
		if u.get("alive", false) and not bool(u.get("downed", false)):
			var fs := String(u.get("faction", ""))
			tally[fs] = int(tally.get(fs, 0)) + 1
		var pos: Vector2 = u.get("position", Vector2.ZERO)
		var c := Vector2i(int(floor(pos.x / UNIT_GRID_CELL)),
			int(floor(pos.y / UNIT_GRID_CELL)))
		if grid.has(c):
			var cell: Array = grid[c]
			cell.append(u)
			cell.append(i)
		else:
			grid[c] = [u, i]


## Forces a grid rebuild on the next query (tests / structural changes).
func _invalidate_unit_grid() -> void:
	_unit_grid_frame = -1
	_unit_grid_n = -1


## Snapshot of the factions this faction can fight, computed once per scan.
## Perf R15: hoists the per-candidate diplomacy lookup out of
## _nearest_hostile's inner loop. Identical result — diplomacy can't change
## mid-scan — but can_fight() (relation_state dictionary walk) runs ~6 times
## per scan instead of once per candidate.
func _hostile_factions(faction: String) -> Dictionary:
	var out := {}
	if _gs != null:
		for f in _gs.active_factions:
			var fs: String = String(f)
			if can_fight(faction, fs):
				out[fs] = true
	# Monsters are a special faction outside active_factions; always hostile.
	if can_fight(faction, "monster"):
		out["monster"] = true
	return out


func _nearest_hostile(upos: Vector2, faction: String,
		max_dist: float) -> Dictionary:
	_sync_unit_grid()
	if _unit_grid.is_empty():
		return {}
	# Perf R15: hostile-faction set snapshotted once per scan (hoists the
	# per-candidate diplomacy lookup out of the inner loop).
	# Perf R23: the snapshot itself is cached per relation-version.
	var hostile: Dictionary = _hostile_cached(faction)
	# Perf R43: no hostile faction fields a valid target -> the ring walk
	# below would visit every cell and return {}. Skip it. Bit-identical:
	# the tally counts exactly the units the scan keeps (alive, not downed),
	# rebuilt from the same records by _sync_unit_grid above.
	var prey := 0
	for hf in hostile:
		prey += int(_faction_alive.get(hf, 0))
	if prey == 0:
		return {}
	var cc := _unit_cell(upos)
	# Rings beyond this can't hold anything within max_dist.
	var max_ring: int = int(ceil(max_dist / UNIT_GRID_CELL)) + 1
	# Perf R41: walk the rings by coordinate and look up only those cells.
	# The old code bucketed EVERY occupied grid cell into per-ring arrays
	# first (O(occupied) Vector2i allocs + casts + appends per scan) and
	# then processed the rings. Rings are still processed in ascending
	# order with the same stopping rule, the visited candidate SET per
	# ring is unchanged (empty cells hold no units), and the argmin +
	# build-index tie-break is order-independent within a ring — so the
	# returned unit is bit-identical, but a scan that finds its target in
	# ring 0/1 now pays ~9-25 dict lookups instead of hundreds of
	# bucket iterations. Mutable best-state rides in `st`:
	# [best_dict, best_d2, best_idx].
	var st: Array = [{}, max_dist * max_dist, -1]
	# best_idx < 0 until best is set: tie-break stays off, preserving the
	# old strict-d2< semantics at exactly max_dist.
	# Perf R41: hoist the grid ref out of the per-cell calls.
	var grid: Dictionary = _unit_grid
	var ring := 0
	while ring <= max_ring:
		if ring == 0:
			_scan_hostile_cell(grid, cc, upos, hostile, st)
		else:
			var cx: int = cc.x
			var cy: int = cc.y
			for dx in range(-ring, ring + 1):
				_scan_hostile_cell(grid, Vector2i(cx + dx, cy - ring),
					upos, hostile, st)
				_scan_hostile_cell(grid, Vector2i(cx + dx, cy + ring),
					upos, hostile, st)
			for dy in range(-ring + 1, ring):
				_scan_hostile_cell(grid, Vector2i(cx - ring, cy + dy),
					upos, hostile, st)
				_scan_hostile_cell(grid, Vector2i(cx + ring, cy + dy),
					upos, hostile, st)
		# Exact stopping rule: ring r+1's closest possible point is
		# r*CELL away, so once best_d2 <= (r*CELL)^2 nothing farther can
		# beat it — the TRUE nearest, identical to the old full scan.
		var stop_d: float = float(ring) * UNIT_GRID_CELL
		if float(st[1]) <= stop_d * stop_d:
			break
		ring += 1
	return st[0]


## Perf R41: scans one grid cell for hostile candidates, folding the best
## into st = [best_dict, best_d2, best_idx]. Missing cells cost one dict
## get; the candidate loop is the R32 flat [unit, idx, ...] walk.
func _scan_hostile_cell(grid: Dictionary, ckey: Vector2i, upos: Vector2,
		hostile: Dictionary, st: Array) -> void:
	var cell: Array = grid.get(ckey, [])
	if cell.is_empty():
		return
	var best: Dictionary = st[0]
	var best_d2: float = st[1]
	var best_idx: int = st[2]
	var p := 0
	while p < cell.size():
		var u: Dictionary = cell[p]
		if not u.get("alive", false):
			p += 2
			continue
		if bool(u.get("downed", false)):
			p += 2
			continue  # knocked-out units are not targets
		if not hostile.has(String(u.get("faction", ""))):
			p += 2
			continue
		var d2: float = upos.distance_squared_to(
			u.get("position", Vector2.ZERO))
		var idx: int = int(cell[p + 1])
		if d2 < best_d2 or (best_idx >= 0 \
				and d2 == best_d2 and idx < best_idx):
			best_d2 = d2
			best_idx = idx
			best = u
		p += 2
	st[0] = best
	st[1] = best_d2
	st[2] = best_idx


## Perf R42: building-grid sync + invalidation. See the member comment at
## BLDG_GRID_CELL for the invalidation contract.
func _bldg_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / BLDG_GRID_CELL)),
		int(floor(pos.y / BLDG_GRID_CELL)))


func _sync_building_grid() -> void:
	var n: int = _gs.buildings.size()
	if n == _bldg_grid_n:
		return
	_bldg_grid_n = n
	# Same flat [building, idx, ...] packing as the R32 unit grid: no
	# per-building pair allocations, pairs stay in build order.
	var grid: Dictionary = _bldg_grid
	grid.clear()
	var buildings: Array = _gs.buildings
	for i in range(buildings.size()):
		var b: Dictionary = buildings[i]
		var pos: Vector2 = b.get("position", Vector2.ZERO)
		var c := Vector2i(int(floor(pos.x / BLDG_GRID_CELL)),
			int(floor(pos.y / BLDG_GRID_CELL)))
		if grid.has(c):
			var cell: Array = grid[c]
			cell.append(b)
			cell.append(i)
		else:
			grid[c] = [b, i]


## Forces a building-grid rebuild on the next query (structural changes
## that keep the building count identical; tests).
func _invalidate_building_grid() -> void:
	_bldg_grid_n = -1


## Nearest hostile building (for siege engines and war deployments).
## Destroyed buildings are skipped. Perf R42: ring-walk over the building
## grid instead of the old linear scan over all buildings — ascending
## rings, same stopping rule, same argmin + build-index tie-break, so the
## result is bit-identical at a fraction of the per-scan cost.
func _nearest_hostile_building(upos: Vector2, faction: String,
		max_dist: float) -> Dictionary:
	_sync_building_grid()
	if _bldg_grid.is_empty():
		return {}
	# Perf R15: same diplomacy hoist as _nearest_hostile.
	# Perf R23: the snapshot itself is cached per relation-version.
	var hostile: Dictionary = _hostile_cached(faction)
	var cc := _bldg_cell(upos)
	# Rings beyond this can't hold anything within max_dist.
	var max_ring: int = int(ceil(max_dist / BLDG_GRID_CELL)) + 1
	# Mutable best-state rides in `st`: [best_dict, best_d2, best_idx].
	# best_idx < 0 until best is set: tie-break stays off, preserving the
	# old strict-d2< semantics at exactly max_dist.
	var st: Array = [{}, max_dist * max_dist, -1]
	var grid: Dictionary = _bldg_grid
	var ring := 0
	while ring <= max_ring:
		if ring == 0:
			_scan_hostile_bcell(grid, cc, upos, hostile, st)
		else:
			var cx: int = cc.x
			var cy: int = cc.y
			for dx in range(-ring, ring + 1):
				_scan_hostile_bcell(grid, Vector2i(cx + dx, cy - ring),
					upos, hostile, st)
				_scan_hostile_bcell(grid, Vector2i(cx + dx, cy + ring),
					upos, hostile, st)
			for dy in range(-ring + 1, ring):
				_scan_hostile_bcell(grid, Vector2i(cx - ring, cy + dy),
					upos, hostile, st)
				_scan_hostile_bcell(grid, Vector2i(cx + ring, cy + dy),
					upos, hostile, st)
			# Exact stopping rule: ring r+1's closest possible point is
			# r*CELL away, so once best_d2 <= (r*CELL)^2 nothing farther
			# can beat it — the TRUE nearest, identical to the old scan.
			var stop_d: float = float(ring) * BLDG_GRID_CELL
			if float(st[1]) <= stop_d * stop_d:
				break
		ring += 1
	return st[0]


## Perf R42: scans one building-grid cell for hostile candidates, folding
## the best into st = [best_dict, best_d2, best_idx]. Missing cells cost one
## dict get; the candidate loop is the R32 flat [building, idx, ...] walk.
## Destroyed buildings and friendly factions are skipped live off the
## records, matching the old linear scan's filters exactly.
func _scan_hostile_bcell(grid: Dictionary, ckey: Vector2i, upos: Vector2,
		hostile: Dictionary, st: Array) -> void:
	var cell: Array = grid.get(ckey, [])
	if cell.is_empty():
		return
	var best: Dictionary = st[0]
	var best_d2: float = st[1]
	var best_idx: int = st[2]
	var p := 0
	while p < cell.size():
		var b: Dictionary = cell[p]
		if bool(b.get("destroyed", false)):
			p += 2
			continue
		if not hostile.has(String(b.get("faction", ""))):
			p += 2
			continue
		var d2: float = upos.distance_squared_to(
			b.get("position", Vector2.ZERO))
		var idx: int = int(cell[p + 1])
		if d2 < best_d2 or (best_idx >= 0 \
				and d2 == best_d2 and idx < best_idx):
			best_d2 = d2
			best_idx = idx
			best = b
		p += 2
	st[0] = best
	st[1] = best_d2
	st[2] = best_idx


## Siege behavior: walk to a hostile building and smash it on cooldown.
## Sets combat_state to "sieging" (in range) or "advancing" (moving).
func _tick_building_attack(unit: Dictionary, building: Dictionary,
		stats: Dictionary, delta: float) -> void:
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var bpos: Vector2 = building.get("position", Vector2.ZERO)
	var dist: float = upos.distance_to(bpos)
	var wrange: float = float(stats["range"])
	if bool(stats["ranged"]):
		wrange *= _weapon_range_mult(unit)
	# Buildings are big: melee units can hit from a bit farther out.
	if not bool(stats["ranged"]):
		wrange += 30.0
	var bid: int = int(building.get("id", -1))
	if dist <= wrange:
		unit["combat_state"] = "sieging"
		unit["combat_target"] = -1
		unit["siege_target"] = bid
		if float(unit.get("attack_cd", 0.0)) <= 0.0:
			_attack_building(unit, building, stats)
	else:
		unit["combat_state"] = "advancing"
		unit["combat_target"] = -1
		unit["siege_target"] = bid
		# Guards don't leave their post to siege.
		if String(unit.get("job", "")) == "guard":
			var post: Vector2 = unit.get("guard_post", upos)
			if bpos.distance_to(post) > GUARD_LEASH:
				unit["combat_state"] = "idle"
				unit["siege_target"] = -1
				return
		_walk_to(unit, bpos, float(stats["speed"]), delta)


## Smash a building. Siege engines (treant, bone_golem) deal x2 (HTML
## SIEGE_BUILDING_MUL); saboteurs shred walls x1.5 (HTML SABOTEUR_WALL_MUL).
## Emits combat_fx for impact visuals.
func _attack_building(unit: Dictionary, building: Dictionary,
		stats: Dictionary) -> void:
	unit["attack_cd"] = float(stats["cooldown"])
	var bid: int = int(building.get("id", -1))
	var bpos: Vector2 = building.get("position", Vector2.ZERO)
	var btype: String = String(building.get("type", ""))
	var faction: String = String(unit.get("faction", ""))
	var job: String = String(unit.get("job", ""))
	var uid: int = int(unit.get("id", -1))
	# Base damage: prefer the unit's stamped dmg (apply_faction_stats),
	# fall back to the stats table.
	var dmg: float = float(unit.get("dmg", float(stats["dmg"])))
	var rmod: Dictionary = RACE_COMBAT.get(faction, {"dmg_mul": 1.0})
	dmg *= float(rmod.get("dmg_mul", 1.0))
	dmg *= _weapon_dmg_mult(unit)
	# Jeremy 2026-10-04: food perk strength modifier (Sausage Strength etc.).
	dmg *= SimFoodPerks.get_modifier(unit, "strength", _gs.game_time)
	# Warlord aura still applies to siege work.
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	if _warlord_nearby(upos, faction, uid) \
			or float(unit.get("aura61", 0.0)) > 0.0:
		dmg *= WARLORD_AURA_MUL
	if bool(unit.get("siege", false)):
		dmg *= SimFactions.SIEGE_BUILDING_MUL
	if bool(unit.get("wall_shred", false)) and btype == "wall":
		dmg *= SimFactions.SABOTEUR_WALL_MUL
	# Ranged siege (cannoneer): visual projectile, damage on impact.
	# Melee siege: direct damage + impact FX.
	if bool(stats["ranged"]):
		var kind := "arrow"
		if job == "cannoneer":
			kind = "cannonball"
		elif job == "mage":
			kind = "spell"
		var p := fire_projectile(upos, -1, bpos, kind, 0.0,
			float(stats["splash"]), faction, float(stats["proj_speed"]))
		p["building_target_id"] = bid
		p["building_dmg"] = dmg
		p["attacker_id"] = uid
		_gs.bus.combat_fx.emit("muzzle", upos)
		# Jeremy 2026-10-04: Seven Monasteries — magic stacks on siege too.
		if monasteries != null:
			monasteries.fire_magic_at_building(unit, building, bpos, upos)
		# Jeremy 2026-10-04: Seven Dark Crystals — dark magic stacks too.
		if crystals != null:
			crystals.fire_dark_at_building(unit, building, bpos, upos)
	else:
		damage_building(bid, dmg, faction)
		_gs.bus.combat_fx.emit("siege_hit", bpos)
		# Jeremy 2026-10-04: Seven Monasteries — magic stacks on siege too.
		if monasteries != null:
			monasteries.fire_magic_at_building(unit, building, bpos, upos)
		# Jeremy 2026-10-04: Seven Dark Crystals — dark magic stacks too.
		if crystals != null:
			crystals.fire_dark_at_building(unit, building, bpos, upos)
		# Heavy hits shake the building: start/refresh its fire visual
		# once it's below half HP (burning-building system).
		var b: Dictionary = _get_building(bid)
		if not b.is_empty():
			var hp: float = float(b.get("hp", 400.0))
			var max_hp: float = float(b.get("max_hp", 400.0))
			if max_hp > 0.0 and hp < max_hp * 0.5:
				_gs.bus.combat_fx.emit("building_burning", bpos)


## Combat micro-tactics (HTML applyCombatTactics "FIX 'EM THEN FLANK 'EM",
## scaled port). Returns "hold" when the unit should plant feet instead of
## chasing, "moved" when tactics already moved it this tick, "" for normal
## chase/attack behavior. Never suppresses attacks — cover troops peek-fire.
func _apply_tactics(unit: Dictionary, target: Dictionary,
		stats: Dictionary, dist: float, delta: float) -> String:
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	var tpos: Vector2 = target.get("position", Vector2.ZERO)
	var faction: String = String(unit.get("faction", ""))
	var wrange: float = float(stats["range"])
	var speed: float = float(stats["speed"])
	var under_fire: bool = _gs.game_time \
		- float(unit.get("last_hit_time", -999.0)) < UNDER_FIRE_WINDOW

	# Cover: ranged units under fire (or with the enemy inside range+160)
	# pull behind a nearby friendly building and peek-fire (HTML cover).
	if bool(stats["ranged"]):
		if under_fire or dist < wrange + 160.0:
			var cov: Dictionary = _nearest_cover(upos, faction)
			if not cov.is_empty():
				var cpos: Vector2 = cov.get("position", upos)
				var away: Vector2 = (upos - tpos).normalized()
				if away.length() < 0.5:
					away = Vector2.RIGHT
				var hold: Vector2 = cpos + away * 50.0
				unit["in_cover"] = upos.distance_to(cpos) < 70.0
				if bool(unit.get("in_cover", false)):
					unit["combat_state"] = "taking_cover"
				if upos.distance_to(hold) > 40.0:
					_walk_to(unit, hold, speed * 0.6, delta)
					return "moved"
			else:
				unit["in_cover"] = false
		else:
			unit["in_cover"] = false

	# FIX then FLANK: troops marching under a commander (army lead stance)
	# hold the formation line for FIX_DURATION, then the wings peel off.
	var cmd_id: int = int(unit.get("tactic_cmd", -1))
	if cmd_id >= 0:
		var cmd: Dictionary = _gs.get_unit(cmd_id)
		if not cmd.is_empty() and cmd.get("alive", false) \
				and not bool(cmd.get("downed", false)):
			var cpos: Vector2 = cmd.get("position", Vector2.ZERO)
			if upos.distance_to(cpos) < FLANK_RANGE:
				if float(unit.get("tactic_contact_t", -1.0)) < 0.0:
					unit["tactic_contact_t"] = _gs.game_time
				var age: float = _gs.game_time \
					- float(unit.get("tactic_contact_t", 0.0))
				var wing: int = int(unit.get("formation_slot", 0)) % 3
				if age < FIX_DURATION or wing == 1:
					unit["tactic"] = "fix"
					return "hold"  # hold the line and engage
				unit["tactic"] = "flank_left" if wing == 0 else "flank_right"
				var to_threat: Vector2 = (tpos - cpos).normalized()
				if to_threat.length() < 0.5:
					to_threat = Vector2.RIGHT
				var perp := Vector2(-to_threat.y, to_threat.x)
				var side: float = -1.0 if wing == 0 else 1.0
				_walk_to(unit, tpos + perp * side * 140.0, speed, delta)
				return "moved"
	return ""


## Nearest completed friendly building (soft cover for micro-tactics).
func _nearest_cover(upos: Vector2, faction: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d2: float = COVER_SEARCH * COVER_SEARCH
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var d2: float = upos.distance_squared_to(
			b.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = b
	return best


func _walk_to(unit: Dictionary, target_pos: Vector2, speed: float,
		delta: float) -> void:
	# Jeremy 2026-10-04: global slowdown — units moved too fast.
	# 0.55x multiplier preserves relative speeds (fast units still faster).
	speed *= 0.55
	# Long hauls route around buildings/obstacles (A*); short combat
	# shuffles steer direct.
	if SimPathfinder.walk_to(_gs, unit, target_pos, speed, delta):
		return


func _tick_projectiles(delta: float) -> void:
	var done: Array[Dictionary] = []
	for p: Dictionary in projectiles:
		if not p.get("alive", false):
			done.append(p)
			continue
		# Homing-lite: track a live target's current position.
		var tpos: Vector2 = p.get("target_pos", Vector2.ZERO)
		var tid: int = int(p.get("target_id", -1))
		if tid >= 0:
			var t: Dictionary = _gs.get_unit(tid)
			if not t.is_empty() and t.get("alive", false):
				tpos = t.get("position", Vector2.ZERO)
				p["target_pos"] = tpos
		var pos: Vector2 = p.get("position", Vector2.ZERO)
		var to: Vector2 = tpos - pos
		var dist: float = to.length()
		var step: float = float(p.get("speed", 500.0)) * delta
		if dist <= maxf(step, 6.0):
			p["alive"] = false
			_resolve_hit(p, tpos)
			done.append(p)
		else:
			var dir: Vector2 = to.normalized()
			p["position"] = pos + dir * step
			# HTML SFX parity: rocket flyby whoosh with Doppler (0.35 roll
			# per tick, like HTML's SFX.rocketFlyby block). Distance gating
			# stays in the audio manager (5600-unit cutoff).
			var pkind: String = String(p.get("kind", ""))
			if pkind == "rocket" or pkind == "jumbo_rocket" \
					or pkind == "crashing_rocket":
				if randf() < 0.35:
					_gs.bus.sfx_spatial.emit("rocketFlyby",
						p["position"], dir * float(p.get("speed", 500.0)))
	for p: Dictionary in done:
		projectiles.erase(p)
		_gs.bus.projectile_done.emit(p)


## Direct hit on the target, or splash damage around the impact point.
func _resolve_hit(p: Dictionary, impact: Vector2) -> void:
	# Jeremy 2026-10-04: Seven Monasteries — magic projectiles resolve
	# through the monastery system (stacking holy attacks + god effects).
	if p.has("magic_id") and monasteries != null:
		monasteries.resolve_magic_hit(p, impact)
	# Jeremy 2026-10-04: Seven Dark Crystals — dark projectiles resolve
	# through the crystal system (twin blasts, knockback, god effects).
	if p.has("dark_id") and crystals != null:
		crystals.resolve_dark_hit(p, impact)
		_gs.bus.projectile_hit.emit(p, impact)
		return
	# Jeremy 2026-10-04: nuclear warfare — nuke warheads detonate through
	# the nuclear system (HTML detonateNuke parity), not the generic splash.
	if String(p.get("kind", "")) == "nuke" and nuclear != null:
		nuclear.detonate_nuke(impact, String(p.get("faction", "")))
		_gs.bus.projectile_hit.emit(p, impact)
		return
	var faction: String = String(p.get("faction", ""))
	var dmg: float = float(p.get("dmg", 0.0))
	var splash: float = float(p.get("splash", 0.0))
	var tid: int = int(p.get("target_id", -1))
	var aid: int = int(p.get("attacker_id", -1))
	var kind: String = String(p.get("kind", ""))
	# Artillery sets splash_mul (edge damage fraction): 0.75 cannon/grape,
	# 0.9 rocket, 1.0 jumbo (no falloff). Default 0.3 = classic falloff.
	var edge: float = clampf(float(p.get("splash_mul", 0.3)), 0.0, 1.0)
	if splash > 0.0:
		var s2: float = splash * splash
		# Units: full damage at center, falloff to `edge` at the rim.
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			if not can_fight(faction, String(u.get("faction", ""))):
				continue
			var d2: float = impact.distance_squared_to(
				u.get("position", Vector2.ZERO))
			if d2 <= s2:
				var k: float = 1.0 - (1.0 - edge) * sqrt(d2) / splash
				damage_unit(int(u.get("id", 0)), dmg * k, faction, aid, kind)
		for b: Dictionary in _gs.buildings.duplicate():
			if not can_fight(faction, String(b.get("faction", ""))):
				continue
			var d2: float = impact.distance_squared_to(
				b.get("position", Vector2.ZERO))
			if d2 <= s2:
				var k: float = 1.0 - (1.0 - edge) * sqrt(d2) / splash
				damage_building(int(b.get("id", 0)), dmg * k, faction)
		# Jeremy 2026-10-06: HTML detonateJumbo parity — jumbo warheads
		# leave a small 90 s radiation hot zone (intensity 0.55).
		if kind == "jumbo_rocket" and nuclear != null:
			nuclear.detonate_jumbo(impact, splash)
	elif tid >= 0:
		# Cliffs: direct projectile hits keep the high-ground edge;
		# splash (no attacker position) is unaffected (HTML rule).
		var mult := 1.0
		if p.has("from_pos"):
			mult = Cliffs.high_ground_mult(_gs.map_data,
				p["from_pos"], impact)
		damage_unit(tid, dmg * mult, faction, aid, kind)
	# Siege projectiles aimed at a building: apply the stored building
	# damage on arrival + impact visuals.
	if p.has("building_target_id"):
		var bid2: int = int(p.get("building_target_id", -1))
		var bdmg: float = float(p.get("building_dmg", 0.0))
		if bid2 >= 0 and bdmg > 0.0:
			damage_building(bid2, bdmg, faction)
			_gs.bus.combat_fx.emit("siege_hit", impact)
	# Jeremy 2026-10-04: Seven Monasteries force-field rule — splash
	# washing over a monastery makes it glow instead of hurting it.
	# (Monasteries are indestructible and never targeted.)
	if splash > 0.0 and monasteries != null:
		monasteries.force_field_at(impact, splash)
	# Jeremy 2026-10-04: Seven Dark Crystals — same force-field rule.
	# (Crystals are indestructible and never targeted.)
	if splash > 0.0 and crystals != null:
		crystals.force_field_at(impact, splash)
	# Jeremy 2026-10-04: artillery knocks a big cartoon crater into the
	# ground on impact (persistent terrain decal).
	if kind == "cannonball":
		_gs.bus.combat_fx.emit("crater", impact)
	_gs.bus.projectile_hit.emit(p, impact)


func _purge_corpses() -> void:
	var now: float = _gs.game_time
	var kept: Array[Dictionary] = []
	var removed: int = 0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) \
				and now - float(u.get("death_time", now)) >= CORPSE_LINGER:
			removed += 1
			_gs.bus.unit_purged.emit(int(u.get("id", 0)))
		else:
			kept.append(u)
	if removed > 0:
		_gs.units = kept


func _get_building(building_id: int) -> Dictionary:
	# Jeremy 2026-10-05 perf: shared O(1) id index on GameState.
	return _gs.get_building(building_id)
