class_name SimSandbox
extends RefCounted
## Cursing Gnomes — sandbox observe mode (director layer).
##
## HTML parity (build-staging/fix79/index.html, `sandboxMode`):
##   - Observe-only: no player faction (playerRace = null in HTML;
##     game.player_faction = "" here). All factions run on full AI
##     (playerArmyStance = 'auto').
##   - The observer camera is free: pan & zoom to watch. Boot message:
##     "Sandbox live — pan & zoom to watch. All factions are AI."
##   - Standard RTS chrome is hidden while this is active; a sandbox HUD
##     (faction buttons + census, director actions, log) replaces it.
##   - Win/defeat are never triggered for an observer. Instead the last
##     civilization standing is announced once and the run soft-ends:
##     "SIMULATION COMPLETE — <Name> dominated the continent.
##      (Sandbox — you were an observer.)"
##
## Pure logic — no rendering, no input, no audio. The world ticks this
## every physics frame and shows the sandbox end-screen variant on
## sim_complete (see WIRING below).
##
## WIRING (needs scripts/main.gd + scripts/world/world.gd + scripts/ui/hud.gd
## — owned by other agents, DO NOT edit from here):
##   main.gd  _on_sandbox(): call _start_world("", "")
##            (empty player faction = observe-only; world.configure already
##            skips the player camera re-aim and _check_end_conditions
##            already skips victory/defeat when player_faction == "").
##   world.gd: var sandbox: SimSandbox (null unless player_faction == "").
##            In configure(): if player_faction == "": sandbox =
##            SimSandbox.new(game); sandbox.begin(); zoom the camera out
##            (~0.7) centered on a random hall or mid-map (HTML parity).
##            In _physics_process(): if sandbox != null: sandbox.tick(delta).
##            Connect sandbox.sim_complete -> show the "sandbox" end-screen
##            variant: "<Winner> dominated the continent. (Sandbox — you
##            were an observer.)"
##   hud.gd:  hide the standard RTS chrome when game.player_faction == ""
##            (HTML showSandboxHud hides #ui-panel / #side-panel) and show
##            the sandbox director HUD: faction focus buttons with census
##            (sandbox.faction_census), director actions wired to the
##            helpers below (boost_race / spawn_troops / war_all /
##            force_peace_all), and a log line.


## Director troop roster per faction (HTML sbSpawnTroops `jobs` parity).
const SANDBOX_JOBS := {
	"humans": ["swordsman", "archer", "knight", "cleric"],
	"ogres": ["clubber", "musketeer", "berserker", "warlord", "blunderbuss"],
	"gnomes": ["axeman", "mage", "tinker_mech", "saboteur"],
	"elves": ["ranger", "warlock", "treant", "spellweaver"],
	"undead": ["skeleton", "zombie", "ghoul", "wraith", "necromancer",
		"plaguebearer", "bone_golem", "lich"],
}
const MAX_UNITS := 96  # HTML POPCAP11: sandbox troop spawn hard global guard
const END_GRACE := 2.5  # seconds after boot before the last-civ check runs

## Fired once when a single civilization remains standing. The world shows
## the sandbox end-screen variant (SIMULATION COMPLETE).
signal sim_complete(winner_name: String)

var _gs: GameState

var active := false
## Faction the observer's camera is focused on (HTML sbFocusRace; Godot ids).
var focus_race := "humans"
var _announced := false
var _grace := END_GRACE


func _init(game_state: GameState) -> void:
	_gs = game_state


## Boots observe-only mode: no player faction, full AI for everyone.
func begin() -> void:
	if active:
		return
	_gs.player_faction = ""  # observe-only: no player faction (HTML playerRace = null)
	if not _gs.active_factions.is_empty():
		focus_race = String(_gs.active_factions[0])
	_announced = false
	_grace = END_GRACE
	active = true


func is_observe() -> bool:
	return active


## Focus the observer camera on another faction (HTML sbFocusCam target).
func set_focus(faction: String) -> void:
	if _gs.active_factions.has(faction):
		focus_race = faction


## Alive + complete halls for a faction (world._check_end_conditions parity).
func hall_count(faction: String) -> int:
	var n := 0
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) in ["town_hall", "hall"] \
				and bool(b.get("alive", true)) \
				and bool(b.get("complete", false)) \
				and String(b.get("faction", "")) == faction:
			n += 1
	return n


## Census for the sandbox faction buttons (HTML refreshSandboxFactionButtons):
## pop + hall count.
func faction_census(faction: String) -> Dictionary:
	var pop := 0
	for u: Dictionary in _gs.units:
		if bool(u.get("alive", false)) \
				and String(u.get("faction", "")) == faction:
			pop += 1
	return {"pop": pop, "halls": hall_count(faction)}


## The last civilization with a hall, or "" while 0 or 2+ remain standing
## (HTML checkWin sandbox branch: alive = factions with halls; announce
## only when exactly one).
func last_civ_standing() -> String:
	var alive: Array[String] = []
	for f: String in _gs.active_factions:
		if hall_count(f) > 0:
			alive.append(f)
	if alive.size() == 1:
		return alive[0]
	return ""


## Called every physics tick by the world. After the boot grace period,
## announces the last civilization standing exactly once.
func tick(delta: float) -> void:
	if not active or _announced:
		return
	if _grace > 0.0:
		_grace -= delta
		return
	var winner := last_civ_standing()
	if winner == "":
		return
	_announced = true
	sim_complete.emit(winner)


# ------------------------------------------------------------------ director
# Pure-sim director actions for the sandbox HUD (HTML handleSandboxAction).

## HTML sbBoost parity: +5000 gold, +5000 wood, +2000 food.
func boost_race(faction: String) -> void:
	_gs.resources.ensure_faction(faction)
	_gs.resources.add_resource(faction, "gold", 5000.0, true)
	_gs.resources.add_resource(faction, "wood", 5000.0, true)
	_gs.resources.add_resource(faction, "food", 2000.0, true)


## Public wrapper for the observer camera (HTML sbFocusCam parity):
## position of a faction's first hall, or Vector2.ZERO when none stands.
func hall_position(faction: String) -> Vector2:
	return _hall_pos(faction)


func _hall_pos(faction: String) -> Vector2:
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) in ["town_hall", "hall"] \
				and bool(b.get("alive", true)) \
				and String(b.get("faction", "")) == faction:
			return b.get("position", Vector2.ZERO)
	return Vector2.ZERO


## HTML sbSpawnTroops parity: one of each roster job beside the faction's
## hall. Hard global 96-unit guard (HTML POPCAP11). Returns spawned count.
func spawn_troops(faction: String) -> int:
	if _gs.units.size() >= MAX_UNITS:
		return 0
	var hall := _hall_pos(faction)
	var cx: float = hall.x if hall != Vector2.ZERO else _gs.map_data.get(
		"world_w", 4096.0) * 0.5
	var cy: float = hall.y if hall != Vector2.ZERO else _gs.map_data.get(
		"world_h", 4096.0) * 0.5
	var n := 0
	for job in SANDBOX_JOBS.get(faction, SANDBOX_JOBS["humans"]):
		if _gs.units.size() >= MAX_UNITS:
			break
		_gs.add_unit({
			"faction": faction,
			"job": String(job),
			"town_id": -1,
			"position": Vector2(cx + 60.0 + float(n) * 24.0, cy + 60.0),
			"alive": true,
			"hp": 100.0,
			"max_hp": 100.0,
		})
		n += 1
	return n


## HTML war_all parity: every faction at war with every other.
func war_all() -> void:
	for a: String in _gs.active_factions:
		for b: String in _gs.active_factions:
			if a != b:
				_gs.diplomacy.declare_war(a, b,
					"Sandbox director declared global war")


## HTML peace parity: every faction pair neutral (wars ended).
func force_peace_all() -> void:
	for a: String in _gs.active_factions:
		for b: String in _gs.active_factions:
			if a != b:
				_gs.diplomacy.make_peace(a, b)


## HTML handleSandboxAction 'ally' parity: every faction pair allied.
func ally_all() -> void:
	for a: String in _gs.active_factions:
		for b: String in _gs.active_factions:
			if a != b and a < b:  # each unordered pair once
				_gs.diplomacy.form_alliance(a, b)


## HTML handleSandboxAction 'war_target' parity: picks a random other
## faction as the enemy of `faction` and declares war. Returns the target
## faction id, or "" when no other faction exists.
func war_target(faction: String) -> String:
	var others: Array[String] = []
	for f: String in _gs.active_factions:
		if f != faction:
			others.append(f)
	if others.is_empty():
		return ""
	var target: String = others[randi() % others.size()]
	_gs.diplomacy.declare_war(faction, target,
		"Sandbox director pitted them against each other")
	return target


# ------------------------------------------------- weather / time director
# HTML parity (handleSandboxAction weather + time-of-day actions):
#   w_clear/w_cloud/w_rain/w_storm/w_snow, day/night/skip_day.
# In Godot the seasons sim is the single source of truth for conditions
# (the render layer mirrors seasons.weather), and the clock derives from
# game_time / DAY_LENGTH_SECONDS.


## Weather kinds the director can force (HTML w_* buttons).
const DIRECTOR_WEATHER := ["clear", "cloudy", "rain", "storm", "snow"]


## HTML sbSetWeather parity: force the sim weather. Storm/rain imply rain
## downstream (seasons → weather.gd mirror). Returns false when the kind
## is unknown or the seasons sim isn't wired (bare headless tests).
func set_weather(kind: String) -> bool:
	if kind not in DIRECTOR_WEATHER:
		return false
	var seas = _gs.get("seasons")
	if seas == null:
		return false
	seas.weather = kind
	return true


## HTML day/night parity: jump the clock to `hour` (0-24) on the same
## game day (HTML: day → 10, night → 22). day_number is re-synced with
## the same formula game_state.tick() uses (it only recomputes there).
func set_time_of_day(hour: float) -> void:
	var day_len: float = Config.DAY_LENGTH_SECONDS
	var day_start: float = float(_gs.day_number - 1) * day_len
	_gs.game_time = day_start + clampf(hour, 0.0, 24.0) / 24.0 * day_len
	_gs.day_number = int(_gs.game_time / day_len) + 1


## HTML skip_day parity: advance the calendar one full day and land the
## clock at 08:00 (HTML: advanceCalendar(); timeOfDay = 8).
func skip_day() -> void:
	var day_len: float = Config.DAY_LENGTH_SECONDS
	_gs.game_time = float(_gs.day_number) * day_len \
		+ 8.0 / 24.0 * day_len
	_gs.day_number = int(_gs.game_time / day_len) + 1


# ------------------------------------------------------- disaster director
# HTML parity (handleSandboxAction d_* disaster buttons). Button ids map
# onto the Godot disaster kinds. d_nuke has NO Godot equivalent — nukes
# are vehicle-fired via artillery.gd and there is no detonate-at-point
# API — so it is intentionally absent from this table.


## Sandbox disaster buttons (HTML d_* ids) → Godot disaster kinds.
const DIRECTOR_DISASTERS := {
	"bandits": "bandit_raid",
	"butt": "giant_ass",
	"moose": "thicc_moose",
	"lizard": "giant_lizard",
	"cat": "cardboard_cat",
	"bastard": "count_bastard",
	"wizard": "rogue_wizard",
	"fire": "wildfire",
	"volcano": "volcano",
	"karen": "hoa_karen",
}

## Intensity for the 8 director wildfires (HTML sbSpawnDisaster 'fire':
## seedFire(x, y, 1.2, 12) — 1.2 on the 0-3 HTML scale ≈ 40 on the
## 1-100 Godot ignite scale).
const DIRECTOR_FIRE_INTENSITY := 40.0


## Director meddling point: near the focused faction's hall (HTML aims at
## the listener/camera), jittered ±200 px like HTML.
func _director_point() -> Vector2:
	var hall := _hall_pos(focus_race)
	if hall == Vector2.ZERO:
		hall = Vector2(
			float(_gs.map_data.get("world_w", 4096.0)) * 0.5,
			float(_gs.map_data.get("world_h", 4096.0)) * 0.5)
	return hall + Vector2(randf_range(-200.0, 200.0),
		randf_range(-200.0, 200.0))


## HTML sbSpawnDisaster parity: unleash a disaster at the director point.
## Returns the Godot disaster kind spawned, or "" when nothing could
## spawn (unknown button id, missing disasters sim, singleton monster
## already present, no valid volcano site).
func spawn_disaster(kind: String) -> String:
	if not DIRECTOR_DISASTERS.has(kind):
		return ""
	var sys = _gs.get("disasters")
	if sys == null:
		return ""
	var gkind: String = DIRECTOR_DISASTERS[kind]
	var pos := _director_point()
	if gkind == "wildfire":
		# HTML: 8 seedFire around the point. Godot firefighter
		# auto-dispatch (tick_firefighter) replaces alertFireDepartments.
		for i in 8:
			sys.ignite(pos + Vector2(randf_range(-60.0, 60.0),
				randf_range(-60.0, 60.0)), DIRECTOR_FIRE_INTENSITY)
		return gkind
	if gkind == "volcano":
		for _try in 12:
			var p: Vector2 = pos + Vector2(randf_range(-300.0, 300.0),
				randf_range(-300.0, 300.0))
			if sys.volcano_site_ok(p):
				sys.erupt_volcano_at(p)
				return gkind
		return ""
	var u: Dictionary = sys.spawn(gkind, pos)
	return gkind if not u.is_empty() else ""


## HTML clear_fire parity: put out every fire and clear burning buildings.
## Returns the number of fires extinguished.
func clear_fires() -> int:
	var n := 0
	var sys = _gs.get("disasters")
	if sys != null:
		for f: Dictionary in sys.fires.duplicate():
			sys.extinguish(f)
			n += 1
	for b: Dictionary in _gs.buildings:
		if bool(b.get("on_fire", false)):
			b["on_fire"] = false
	return n


## HTML sbForceExpand parity: order a faction to expand — resource boost
## (sbBoost, verbatim) plus one developed zone lot (ensureZonesAndDevelop,
## one site per call). HTML's forceCivWork housing nudge is covered by
## SimHousing (15+15 caps, homeless migration, homesteads).
func force_expand(faction: String) -> void:
	boost_race(faction)
	_develop_zone_lot(faction)


## HTML sbForceExpand zone-development parity (ensureZonesAndDevelop, one
## lot per call): develops a single empty faction zone into a building
## blueprint. Serialized like the HTML — no new lot while an incomplete
## site exists (crews finish first; Godot's worker AI keeps builders
## assigned to existing sites, the HTML ensureConstructionCrew role).
## HTML's forceCivWork housing nudge is covered by SimHousing (15+15 caps,
## homeless migration, homesteads), so it is not duplicated here.
## Returns the placed blueprint, or {} when nothing was developed.
func _develop_zone_lot(faction: String) -> Dictionary:
	var hall := _hall_dict(faction)
	if hall.is_empty():
		return {}
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)) or bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in ["wall", "gate", "bridge"]:
			continue
		return {}  # crews are still on an existing site — finish it first
	var sys := SimBuildings.new(_gs)
	var map_rect := Rect2(Vector2.ZERO, Vector2(
		float(_gs.map_data.get("world_w", 4096.0)),
		float(_gs.map_data.get("world_h", 4096.0))))
	for ztype: String in SimZoning.ZONE_TYPES:
		for z: Dictionary in _gs.zoning.zones_of(ztype, faction):
			for btype: String in _pick_zone_builds(faction, ztype):
				var spot := _clear_spot_in_zone(z, btype, map_rect)
				if spot == Vector2.INF:
					continue
				if btype == "house" and _house_capped(faction, spot, hall):
					continue
				var bp: Dictionary = sys.place_blueprint(btype, faction,
					_town_for_spot(faction, spot, hall), spot)
				if not bp.is_empty():
					return bp
	return {}


## The faction's first living hall record (HTML sbForceExpand's hall
## lookup), or {} when the faction has no hall standing.
func _hall_dict(faction: String) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) in ["town_hall", "hall"] \
				and bool(b.get("alive", true)) \
				and String(b.get("faction", "")) == faction:
			return b
	return {}


## Living buildings of a faction and type (HTML countBuild parity).
func _count_build(faction: String, btype: String) -> int:
	var n := 0
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) == btype:
			n += 1
	return n


## Ordered candidate builds for a zone type — HTML ensureZonesAndDevelop's
## pickType verbatim (counts gate the priorities; the caller tries each
## until one places). Faction war uniques are per-faction like the HTML
## (_uqT table); undead gets none, matching the HTML.
func _pick_zone_builds(faction: String, ztype: String) -> Array[String]:
	var out: Array[String] = []
	match ztype:
		"R":
			out = ["house"]
		"C":
			if _count_build(faction, "restaurant") < 2:
				out.append("restaurant")
			if _count_build(faction, "weaponsmith") < 1:
				out.append("weaponsmith")
			if _count_build(faction, "clinic") < 1:
				out.append("clinic")
			out.append("inn")
		"I":
			for t: String in ["stock_wood", "stock_gold", "stock_food",
					"stock_oil", "stock_seeds", "storage", "cannon_foundry",
					"fire_station"]:
				if _count_build(faction, t) < 1:
					out.append(t)
			out.append("storage")
		"M":
			if _count_build(faction, "shooting_range") < 1:
				out.append("shooting_range")
			if _count_build(faction, "armory") < 1:
				out.append("armory")
			if _count_build(faction, "barracks") < 1:
				out.append("barracks")
			var uq: String = str({"humans": "knights_castle", "ogres": "war_hut",
				"gnomes": "mage_spire", "elves": "tome_library"}.get(faction, ""))
			if uq != "" and _count_build(faction, uq) < 2:
				out.append(uq)
			if _count_build(faction, "medic_camp") < 1:
				out.append("medic_camp")
			if _count_build(faction, "aa_tower") < 2:
				out.append("aa_tower")
			if _count_build(faction, "field_camp") < 1:
				out.append("field_camp")
			if _count_build(faction, "barracks") < 2:
				out.append("barracks")
			out.append("field_camp")
	return out


## True when the town nearest a spot has hit Jeremy's 15-house cap
## (HTML TOWN_HOUSE_CAP), so the caller skips house picks there.
func _house_capped(faction: String, spot: Vector2, hall: Dictionary) -> bool:
	var tid: int = _town_for_spot(faction, spot, hall)
	if tid < 0:
		return false
	var n: int = _town_house_count(faction, tid)
	return n >= SimHousing.TOWN_HOUSE_CAP


## Town id for a blueprint: nearest same-faction town within 1500px of the
## spot, else the hall's town, else -1.
func _town_for_spot(faction: String, spot: Vector2,
		hall: Dictionary) -> int:
	var best := -1
	var best_d := 1500.0
	for tid: int in _gs.towns.keys():
		var t: Dictionary = _gs.towns[tid]
		if String(t.get("faction", "")) != faction:
			continue
		var d: float = spot.distance_to(t.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = tid
	if best >= 0:
		return best
	return int(hall.get("town_id", -1))


## Town houses for the cap check: SimHousing when the world wired it,
## manual count in bare test fixtures.
func _town_house_count(faction: String, town_id: int) -> int:
	if _gs.housing != null:
		return int(_gs.housing.town_house_count(faction, town_id))
	var n := 0
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) != "house":
			continue
		if bool(b.get("countryside", false)):
			continue
		if int(b.get("town_id", -2)) == town_id:
			n += 1
	return n


## First clear build spot inside a zone rect for a building type:
## no footprint overlap (can_place_at) and not on water (HTML's
## footprintInWater guard). Grid scan, deterministic. Vector2.INF when
## the zone has no room.
func _clear_spot_in_zone(z: Dictionary, btype: String,
		map_rect: Rect2) -> Vector2:
	var rect: Rect2 = z.get("rect", Rect2())
	var faction: String = String(z.get("faction", ""))
	var step := 64.0
	var y: float = rect.position.y + step * 0.5
	while y < rect.end.y:
		var x: float = rect.position.x + step * 0.5
		while x < rect.end.x:
			var p := Vector2(x, y)
			if SimBuildings.can_place_at(_gs.buildings, btype, p,
					map_rect, faction, 0.0,
					SimCommandPosts.claimants_of_game(_gs)) and not _water_blocked(p, btype):
				return p
			x += step
		y += step
	return Vector2.INF


## True when the building footprint touches water (HTML footprintInWater
## guard): center plus the four cardinal points at footprint radius.
func _water_blocked(p: Vector2, btype: String) -> bool:
	var r: float = SimBuildings.footprint(btype)
	if _water_at(p):
		return true
	for off: Vector2 in [Vector2(r, 0), Vector2(-r, 0),
			Vector2(0, r), Vector2(0, -r)]:
		if _water_at(p + off):
			return true
	return false


## Water probe against the baked terrain grid (MapGen.is_water parity).
func _water_at(pos: Vector2) -> bool:
	var md: Dictionary = _gs.map_data
	var terrain: PackedByteArray = md.get("terrain", PackedByteArray())
	if terrain.is_empty():
		return false
	var tpx: float = float(md.get("tile_size", 32.0))
	var tx: int = int(pos.x / tpx)
	var ty: int = int(pos.y / tpx)
	if tx < 0 or ty < 0 or tx >= MapGen.MAP_TILES or ty >= MapGen.MAP_TILES:
		return true
	return MapGen.is_water(terrain[ty * MapGen.MAP_TILES + tx])
