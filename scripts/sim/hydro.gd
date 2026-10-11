class_name HydroSim
extends RefCounted
## Cursing Gnomes — hydro/flood disaster system (Jeremy 2026-10-04).
##
## Full port of the HTML build's STAGE3 hydrology sim (fix79 index.html,
## "STAGE3-HYDROLOGY-SIM"): water bodies (lakes + rivers) carry a water
## level driven by rainfall + season. Levels rise visibly over game-hours;
## at >= 0.94 a flood WARNING fires (toast + Gazette); at >= 1.04 real
## flooding starts — buildings in the spill zone take damage and can be
## destroyed, crops wash out, NPCs flee to high ground. Below 0.84 the
## waters recede, leaving mud behind (Gazette reports each stage).
##
## Per-body state persists in save/load; geometry comes from
## map_data["water_bodies"] (built by MapGen._build_water_bodies).
##
## Pure logic — no rendering (see world/flood_overlay.gd for the visual
## layer). Flood news goes through the event bus (gazette_story +
## disaster_spawned/disaster_left).


const HYDRO_WARN := 0.94
const HYDRO_FLOOD := 1.04
const HYDRO_RECEDE := 0.84
const HYDRO_MAX := 1.25

const LAKE_FILL_K := 0.05     # lakes fill slow (HTML verbatim)
const RIVER_FILL_K := 0.07    # rivers react to rain fast
const LAKE_RATE_K := 0.2      # level lerp rate per game-hour
const RIVER_RATE_K := 0.3

const STEP_INTERVAL := 0.5    # flood state machine ticks at 2 Hz per body

## Fishing (fix79 Lake verbatim): lakes stock 80–200 fish; each catch
## depletes the stock and it slowly respawns (HTML Lake.update: dt * 2.5).
const FISH_REGEN := 2.5

## Building damage per game-hour at the flood line, scaling with level
## (HTML hydroFloodDamage, verbatim: 26 + 60 * max(0, lvl - 1)).
const DMG_BASE := 26.0
const DMG_SCALE := 60.0

const FLEE_REPATH := 8.0      # re-issue flee orders at most every 8 s
const FLEE_RANGE := 1500.0    # how far an NPC will run for dry ground

## Mud left behind when waters recede: 2 game days of halved crop growth.
const MUD_DURATION := 2.0

var _gs: GameState
var _combat: SimCombat
var _bodies: Array = []       # built lazily from map_data
var _built := false
var _bounds := Rect2()
## Mud patches stamped when floods recede: {pos, radius, until}.
## Used by the overlay (brown tint) and farming (growth penalty).
var mud_patches: Array = []


func _init(game_state: GameState, combat: SimCombat) -> void:
	_gs = game_state
	_combat = combat


func setup_bounds(bounds: Rect2) -> void:
	_bounds = bounds


## Game-hours per real second (HTML: gh = dt / 150 at a 3600 s day;
## Godot's day is Config.DAY_LENGTH_SECONDS).
func _game_hours(delta: float) -> float:
	return delta / (Config.DAY_LENGTH_SECONDS / 24.0)


## ---- water bodies ----------------------------------------------------

func _build() -> void:
	_bodies.clear()
	_built = true
	var defs: Array = _gs.map_data.get("water_bodies", [])
	for d in defs:
		if not (d is Dictionary):
			continue
		var b: Dictionary = (d as Dictionary).duplicate()
		b["level"] = 0.5
		b["wet_acc"] = 0.0
		b["warned"] = false
		b["flooding"] = false
		b["seq"] = 0
		b["warn_seq"] = 0
		b["acc"] = 0.0
		# Fishing (fix79 Lake verbatim): lakes carry a fish stock of
		# 80–200; max_fish pins the regen ceiling. Rivers hold none.
		if String(b.get("kind", "")) == "lake":
			var stock := 80.0 + randf() * 120.0
			b["fish"] = stock
			b["max_fish"] = stock
		_bodies.append(b)


func bodies() -> Array:
	if not _built:
		_build()
	return _bodies


## Bodies currently flooding (for the visual layer + tests).
func flooding_bodies() -> Array:
	var out: Array = []
	for b in bodies():
		if bool(b.get("flooding", false)):
			out.append(b)
	return out


## ---- rain + season drivers (HTML hydroRainRate/hydroSeasonOffset) -----

func _rain_rate() -> float:
	var seas = _gs.get("seasons")
	if seas == null:
		return 0.0
	match String(seas.weather):
		"storm":
			return 1.0
		"rain":
			return 0.65
		"snow":
			return 0.25   # snowpack feeds a slow melt
		"cloudy":
			return 0.12
	return 0.0


func _rain_cause() -> String:
	var seas = _gs.get("seasons")
	var w := "" if seas == null else String(seas.weather)
	match w:
		"storm":
			return "the storm has drowned the hills"
		"rain":
			return "days of hard rain have fed it"
		"snow":
			return "the melt runs heavy"
	return "the wet season has filled it"


func _season_offset() -> float:
	var seas = _gs.get("seasons")
	if seas == null or not seas.has_method("season"):
		return 0.0
	match String(seas.season()):
		"Winter":
			return 0.15    # wet season: high water
		"Spring":
			return 0.05
		"Autumn":
			return 0.08
	return -0.18             # Summer: dry season, low water


## ---- geometry: flood zones --------------------------------------------

static func level_of(b: Dictionary) -> float:
	return clampf(float(b.get("level", 0.5)), 0.0, HYDRO_MAX)


## Effective lake radius at current level (HTML lakeEffR verbatim).
static func lake_eff_r(b: Dictionary) -> float:
	return float(b.get("radius", 55.0)) * (0.75 + level_of(b) * 0.5)


## Effective river half-width at current level (HTML riverEffHW verbatim).
static func river_eff_hw(b: Dictionary) -> float:
	return (float(b.get("width", 55.0)) / 2.0) \
		* (0.72 + level_of(b) * 0.56)


## Spill distance past the banks (HTML hydroSpillPx verbatim): 0 below
## warning, ~150 px at warning, hundreds of px at full flood.
static func spill_px(b: Dictionary) -> float:
	var lvl := level_of(b)
	if lvl < HYDRO_WARN:
		return 0.0
	var frac := minf(1.0, (lvl - HYDRO_WARN) / (HYDRO_MAX - HYDRO_WARN))
	return 150.0 + 330.0 * frac


## Point-in-flood-zone test (HTML hydroInFlood parity).
static func in_flood(b: Dictionary, pos: Vector2) -> bool:
	var spill := spill_px(b)
	if String(b.get("kind", "")) == "river":
		var pts: PackedVector2Array = b.get("points", PackedVector2Array())
		if pts.size() < 2:
			return false
		var hw := river_eff_hw(b) + spill
		for i in range(pts.size() - 1):
			if _dist_to_seg(pos, pts[i], pts[i + 1]) < hw:
				return true
		return false
	var c: Vector2 = b.get("pos", Vector2.ZERO)
	return pos.distance_to(c) < lake_eff_r(b) + spill


static func _dist_to_seg(p: Vector2, a: Vector2, b2: Vector2) -> float:
	var ab := b2 - a
	var denom := ab.length_squared()
	if denom < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## True when no body floods this point.
func is_dry(pos: Vector2) -> bool:
	for b in bodies():
		if in_flood(b, pos):
			return false
	return true


## Nearest dry point within max_dist (HTML nearestDry parity): sample
## expanding rings, prefer higher ground (cliff levels) that is dry.
func nearest_dry(pos: Vector2, max_dist: float = FLEE_RANGE) -> Vector2:
	var best := Vector2(-1, -1)
	var best_score := -1.0e9
	var my_level := _level_at(pos)
	var steps := 12
	var rings := 5
	for r in range(1, rings + 1):
		var dist := max_dist * float(r) / float(rings)
		for i in range(steps):
			var ang := TAU * float(i) / float(steps) + float(r) * 0.35
			var cand := pos + Vector2(cos(ang), sin(ang)) * dist
			if not _in_bounds(cand):
				continue
			if not is_dry(cand):
				continue
			# Prefer closer + higher ground.
			var score := -cand.distance_to(pos) \
				+ float(_level_at(cand) - my_level) * 400.0
			if score > best_score:
				best_score = score
				best = cand
	if best.x >= 0.0:
		return best
	# Nowhere dry in range: run directly away from the nearest body.
	var away := Vector2.RIGHT
	var best_d := 1.0e18
	for b in bodies():
		var c := _body_center(b)
		var d := pos.distance_squared_to(c)
		if d < best_d:
			best_d = d
			away = (pos - c)
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT
	var p := pos + away.normalized() * max_dist
	p.x = clampf(p.x, 32.0, _bounds.size.x - 32.0) \
		if _bounds.size.x > 64.0 else p.x
	p.y = clampf(p.y, 32.0, _bounds.size.y - 32.0) \
		if _bounds.size.y > 64.0 else p.y
	return p


func _body_center(b: Dictionary) -> Vector2:
	if String(b.get("kind", "")) == "river":
		var pts: PackedVector2Array = b.get("points", PackedVector2Array())
		if pts.is_empty():
			return Vector2.ZERO
		return pts[pts.size() / 2]
	return b.get("pos", Vector2.ZERO)


func _in_bounds(p: Vector2) -> bool:
	if _bounds.size.x <= 0.0:
		return true
	return _bounds.has_point(p)


func _level_at(pos: Vector2) -> int:
	var lv = _gs.map_data.get("levels", null)
	if lv == null:
		return 0
	return Cliffs.level_at(_gs.map_data, pos)


## ---- per-tick driver (HTML hydroTick parity) --------------------------

func tick(delta: float) -> void:
	var bs := bodies()
	if bs.is_empty():
		return
	var gh := _game_hours(delta)
	var rain := _rain_rate()
	var season_off := _season_offset()
	for b in bs:
		_step_body(b, gh, rain, season_off, delta)


func _step_body(b: Dictionary, gh: float, rain: float, season_off: float,
		delta: float) -> void:
	var is_river := String(b.get("kind", "")) == "river"
	var k := RIVER_FILL_K if is_river else LAKE_FILL_K
	var wet := clampf(float(b.get("wet_acc", 0.0)) + (rain - 0.45) * k * gh,
		0.0, 1.0)
	b["wet_acc"] = wet
	var target := clampf(0.5 + wet * 1.05 + season_off, 0.06, 1.08)
	var rate := minf(1.0, gh * (RIVER_RATE_K if is_river else LAKE_RATE_K))
	var lv := float(b.get("level", 0.5))
	b["level"] = lv + (target - lv) * rate
	b["acc"] = float(b.get("acc", 0.0)) + delta
	# Fishing: lake stocks slowly respawn (HTML Lake.update verbatim).
	if not is_river and b.has("fish"):
		var mx := float(b.get("max_fish", 0.0))
		b["fish"] = minf(mx, float(b.get("fish", 0.0)) + delta * FISH_REGEN)
	if float(b["acc"]) >= STEP_INTERVAL:
		var fgh := float(b["acc"]) / (Config.DAY_LENGTH_SECONDS / 24.0)
		b["acc"] = 0.0
		_flood_step(b, fgh)


## Flood state machine: warning -> flood -> recede (HTML hydroFloodStep).
## The warning gate is structural: flooding can only start on a step AFTER
## the warning was issued, so the warning always fires first.
func _flood_step(b: Dictionary, gh: float) -> void:
	b["seq"] = int(b.get("seq", 0)) + 1
	var lvl := level_of(b)
	if not bool(b.get("warned", false)) and lvl >= HYDRO_WARN:
		b["warned"] = true
		b["warn_seq"] = int(b.get("seq", 0))
		_on_warning(b)
	elif not bool(b.get("flooding", false)) \
			and bool(b.get("warned", false)) \
			and int(b.get("warn_seq", 0)) < int(b.get("seq", 0)) \
			and lvl >= HYDRO_FLOOD:
		b["flooding"] = true
		_on_flood_start(b)
	elif bool(b.get("flooding", false)):
		if lvl < HYDRO_RECEDE:
			_on_recede(b)
		else:
			_flood_damage(b, gh)


func _body_name(b: Dictionary) -> String:
	# Nearest town name for Gazette stories (HTML hydroTownNear parity).
	var c := _body_center(b)
	var best_name := "the wilds"
	var best_d := 1.0e18
	for t in _gs.towns.values():
		var hall_pos: Vector2 = (t as Dictionary).get("position",
			Vector2(-1, -1))
		if hall_pos.x < 0.0:
			continue
		var d := c.distance_squared_to(hall_pos)
		if d < best_d:
			best_d = d
			best_name = String((t as Dictionary).get("name", "the wilds"))
	return best_name


func _gazette(headline: String, body: String) -> void:
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs, headline, body, "flood")


func _on_warning(b: Dictionary) -> void:
	var wtype := "river" if String(b.get("kind", "")) == "river" else "lake"
	var tname := _body_name(b)
	_gs.bus.disaster_spawned.emit("flood_warning", _body_center(b))
	_gazette("FLOOD WARNING",
		"The %s by %s swells toward its banks — %s. %sside farms are sandbagging; the elders urge the low streets to climb."
		% [wtype, tname, _rain_cause(), wtype.capitalize()])


func _on_flood_start(b: Dictionary) -> void:
	var tname := _body_name(b)
	var c := _body_center(b)
	_gs.bus.disaster_spawned.emit("flood", c)
	_gazette("FLOOD!",
		"The waters have breached their banks near %s — %s. Low streets are under water; the town flees uphill."
		% [tname, _rain_cause()])
	_flood_damage(b, 0.0)  # immediate first damage pass (HTML parity)


func _on_recede(b: Dictionary) -> void:
	b["flooding"] = false
	b["warned"] = false
	var tname := _body_name(b)
	# Clear flooded flags on buildings still standing in the zone, stamp mud.
	for bd in _gs.buildings:
		if not (bd is Dictionary):
			continue
		var bb: Dictionary = bd
		if bool(bb.get("flooded", false)) and is_dry(bb.get("position",
				Vector2.ZERO)):
			bb["flooded"] = false
	_stamp_mud(b)
	_gazette("WATERS RECEDE",
		"The floodwaters near %s fall back within their banks. Muck, stranded fish, and tall tales remain."
		% [tname])
	_gs.bus.disaster_left.emit("flood")


## Stamp mud patches where the water was (visual + farm penalty).
func _stamp_mud(b: Dictionary) -> void:
	var c := _body_center(b)
	var r := _max_spill_radius(b)
	mud_patches.append({
		"pos": c, "radius": r,
		"until": _gs.game_time + MUD_DURATION * Config.DAY_LENGTH_SECONDS,
	})
	# Farms in the old flood zone get a mud penalty on regrowth.
	var farming = _gs.get("farming")
	if farming != null and farming.get("plots") != null:
		for p in farming.get("plots"):
			if not (p is Dictionary):
				continue
			var pp: Dictionary = p
			if (pp.get("position", Vector2.ZERO) as Vector2) \
					.distance_to(c) < r:
				pp["mud_until"] = _gs.game_time + MUD_DURATION \
					* Config.DAY_LENGTH_SECONDS


func _max_spill_radius(b: Dictionary) -> float:
	if String(b.get("kind", "")) == "river":
		return river_eff_hw(b) + 480.0
	return lake_eff_r(b) + 480.0


## Flood damage + NPC flight (HTML hydroFloodDamage parity), throttled to
## the 2 Hz flood-step.
func _flood_damage(b: Dictionary, gh: float) -> void:
	var lvl := level_of(b)
	var dmg := (DMG_BASE + DMG_SCALE * maxf(0.0, lvl - 1.0)) * gh
	for bd in _gs.buildings.duplicate():
		if not (bd is Dictionary):
			continue
		var bb: Dictionary = bd
		var btype := String(bb.get("type", ""))
		if btype == "wall" or btype == "bridge":
			continue  # HTML: walls and bridges are flood-proof
		if not in_flood(b, bb.get("position", Vector2.ZERO)):
			continue
		bb["flooded"] = true
		if dmg > 0.0 and _combat != null:
			var destroyed: bool = _combat.damage_building(
				int(bb.get("id", -1)), dmg, "flood")
			if destroyed:
				_gazette("FLOOD CLAIMS A BUILDING",
					"The waters took the %s at %s. Timbers and thatch drift downstream."
					% [btype if btype != "" else "building",
						_body_name(b)])
	_wash_crops(b)
	# NPCs flee to high ground (HTML: skip units in combat).
	var now := _gs.game_time
	for u in _gs.units:
		if not (u is Dictionary):
			continue
		var uu: Dictionary = u
		if not bool(uu.get("alive", false)):
			continue
		if int(uu.get("combat_target", -1)) >= 0:
			continue  # in combat: holds position (HTML parity)
		if bool(uu.get("fleeing", false)):
			continue
		if not in_flood(b, uu.get("position", Vector2.ZERO)):
			continue
		if now - float(uu.get("_flood_flee_t", -100.0)) < FLEE_REPATH:
			continue
		uu["_flood_flee_t"] = now
		uu["flood_flee"] = true
		uu["flood_target"] = nearest_dry(uu.get("position", Vector2.ZERO))
		_gs.bus.unit_said.emit(int(uu.get("id", 0)), "The water! Run!")


## Wash out crops in flooded farm plots (HTML parity: floods ruin farms).
func _wash_crops(b: Dictionary) -> void:
	var farming = _gs.get("farming")
	if farming == null or farming.get("plots") == null:
		return
	for p in farming.get("plots"):
		if not (p is Dictionary):
			continue
		var pp: Dictionary = p
		if not in_flood(b, pp.get("position", Vector2.ZERO)):
			continue
		pp["flooded"] = true
		for t in pp.get("tiles", []):
			if not (t is Dictionary):
				continue
			var tt: Dictionary = t
			var crop: Dictionary = tt.get("crop", {})
			if not crop.is_empty():
				crop["g"] = 0.0   # crop washed away
				crop["watered"] = false
				crop["waterT"] = 0.0


## ---- draw info for the visual layer -----------------------------------

## Per-body draw records for FloodOverlay: {kind, pos, points, radius,
## half_width, spill, level, alpha, flooding}.
func flood_draw_info() -> Array:
	var out: Array = []
	for b in bodies():
		var lvl := level_of(b)
		if lvl < HYDRO_WARN and not bool(b.get("flooding", false)) \
				and mud_patches.is_empty():
			continue
		var info := {"kind": String(b.get("kind", "lake")), "level": lvl,
			"flooding": bool(b.get("flooding", false)),
			"spill": spill_px(b)}
		if String(b.get("kind", "")) == "river":
			info["points"] = b.get("points", PackedVector2Array())
			info["half_width"] = river_eff_hw(b)
		else:
			info["pos"] = b.get("pos", Vector2.ZERO)
			info["radius"] = lake_eff_r(b)
		out.append(info)
	return out


## ---- sandbox / debug ----------------------------------------------------

## Force a body into full flood (sandbox + tests).
func force_flood(body_idx: int = 0) -> void:
	var bs := bodies()
	if body_idx < 0 or body_idx >= bs.size():
		return
	var b: Dictionary = bs[body_idx]
	b["level"] = 1.2
	b["wet_acc"] = 1.0
	b["warned"] = true
	b["warn_seq"] = int(b.get("seq", 0))
	b["flooding"] = true
	_on_flood_start(b)


## ---- save / load (HTML: flood state persists) ---------------------------

func to_dict() -> Dictionary:
	var arr: Array = []
	for b in bodies():
		arr.append({
			"level": float(b.get("level", 0.5)),
			"wet_acc": float(b.get("wet_acc", 0.0)),
			"warned": bool(b.get("warned", false)),
			"flooding": bool(b.get("flooding", false)),
			"seq": int(b.get("seq", 0)),
			"warn_seq": int(b.get("warn_seq", 0)),
			"fish": float(b.get("fish", -1.0)),
			"max_fish": float(b.get("max_fish", -1.0)),
		})
	var mud: Array = []
	for m in mud_patches:
		mud.append({
			"pos": (m as Dictionary).get("pos", Vector2.ZERO),
			"radius": float((m as Dictionary).get("radius", 0.0)),
			"until": float((m as Dictionary).get("until", 0.0)),
		})
	return {"bodies": arr, "mud": mud}


func from_dict(d: Dictionary) -> void:
	var bs := bodies()
	var arr: Array = d.get("bodies", [])
	for i in range(mini(arr.size(), bs.size())):
		var s: Dictionary = arr[i]
		var b: Dictionary = bs[i]
		b["level"] = float(s.get("level", 0.5))
		b["wet_acc"] = float(s.get("wet_acc", 0.0))
		b["warned"] = bool(s.get("warned", false))
		b["flooding"] = bool(s.get("flooding", false))
		b["seq"] = int(s.get("seq", 0))
		b["warn_seq"] = int(s.get("warn_seq", 0))
		# Fish stock roundtrips with the lake (fix79 restores l.fish too).
		if float(s.get("fish", -1.0)) >= 0.0:
			b["fish"] = float(s.get("fish", 0.0))
			b["max_fish"] = float(s.get("max_fish", 0.0))
	mud_patches.clear()
	for m in d.get("mud", []):
		if m is Dictionary:
			mud_patches.append((m as Dictionary).duplicate())
