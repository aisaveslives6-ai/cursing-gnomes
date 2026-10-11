class_name SimArtillery
extends RefCounted
## Cursing Gnomes — artillery vehicles, crews, and air defense (Milestone 5).
##
## Faithful port of the HTML build's artyVehicles system:
##   - fireArtyVehicle / launchOneRocket / updateArtyVehicles
##   - mountVehicle / dismountVehicle / assignArtilleryCrew / ensureArtyCrew
##   - spawnVehicleAtDepot (motor pool), vehicle cook-off (Unit.explodeDeath radii)
##   - aa_tower / air_defense rapid interceptors, anti_nuke batteries
##
## HTML numbers carried over verbatim (fix79):
##   - Vehicles are parking-lot machines, NOT living units: hp 220, max 2 crew,
##     motor pool capped at 24 parked per faction.
##   - grape_cannon 900 rng / 35 dmg / 1.8 s; field_cannon 1800 / 45 / 2.5 s;
##     heavy_artillery 5000 / 70 / 2.5 s; siege_rocket 12000 / salvo 18-22;
##     jumbo_rocket 14000 / 280 dmg warhead / 320 splash / 60 s cooldown.
##   - Costs: grape 60g/40w, field 70g/45w, siege 90g/55w, jumbo 160g/100w,
##     heavy 100g/70w. Train times: 2.8 / 3.0 / 3.2 / 4.5 / 3.5 s.
##   - Any faction with a cannon_foundry can train all five (HTML canTrain has
##     no race gate on the foundry); undead crews are legal (bone-pale skin).
##   - Grape shot = single 'grape' projectile, splash 90 @ 0.75 — the
##     anti-infantry answer is the wide splash at short range, not pellets.
##   - aa_tower: intercepts hostile rockets/jumbos/mortars (NOT nukes),
##     range 4200, up to 6 locks, 0.10 s between shots, interceptor speed 2200.
##   - anti_nuke: intercepts nukes only, range 5000, 0.8 s cooldown, speed 2400.
##
## Godot mapping notes:
##   - Crew ARE living units: spawned/mounted through Spawner, so Jeremy's
##     16/town - 48/faction - 240/global caps apply to them (standing rule 5).
##   - Projectiles are fired through SimCombat.fire_projectile so there is one
##     projectile system; SimCombat resolves splash (its own 70% falloff — see
##     HOOK in the subagent report for splash_mul plumbing).
##   - Vehicles roll toward a standoff of min(650, range*0.5) at 300 px/s;
##     rockets never roll, they only aim. Fire band is (40, range].
## Pure logic — no rendering, no input, no audio.


## Vehicle types = parking-lot machines, not living units (HTML VEHICLE_TYPES).
const VEHICLE_TYPES := [
	"grape_cannon", "field_cannon", "siege_rocket", "heavy_artillery",
	"jumbo_rocket",
]

## Per-type stats. hp/size/range/dmg from spawnVehicleAtDepot; cooldowns from
## updateArtyVehicles; costs from COSTS; train times from TRAIN_TIME.
const VEHICLE_STATS := {
	"grape_cannon": {
		"label": "Grape Cannon", "hp": 220.0, "size": 34.0,
		"range": 900.0, "dmg": 35.0, "cooldown": 1.8,
		"splash": 90.0, "splash_mul": 0.75,
		"proj_kind": "grape", "proj_speed": 400.0,
		"cost": {"gold": 60.0, "wood": 40.0}, "train_time": 2.8,
	},
	"field_cannon": {
		"label": "Field Cannon", "hp": 220.0, "size": 34.0,
		"range": 1800.0, "dmg": 45.0, "cooldown": 2.5,
		"splash": 110.0, "splash_mul": 0.75,
		"proj_kind": "cannonball", "proj_speed": 400.0,
		"cost": {"gold": 70.0, "wood": 45.0}, "train_time": 3.0,
	},
	"siege_rocket": {
		"label": "Rocket Truck", "hp": 220.0, "size": 38.0,
		"range": 12000.0, "dmg": 85.0, "cooldown": 60.0,
		"cost": {"gold": 90.0, "wood": 55.0}, "train_time": 3.2,
		# Salvo: 18-22 rockets, 0.35 s rail windup, one every 0.12-0.20 s,
		# then a 60 s reload (HTML fireArtyVehicle / updateArtyVehicles).
		"salvo_min": 18, "salvo_max": 22, "salvo_windup": 0.35,
		# Individual rocket: 25% wild arc, rest scattered toward target
		# (Jeremy 2026-10-06: duds deleted — every rocket is live).
		"rocket_speed_min": 380.0, "rocket_speed_max": 540.0,
		"wild_chance": 0.25,
		"rocket_dmg_min": 70.0, "rocket_dmg_max": 100.0,
		"rocket_splash_min": 180.0, "rocket_splash_max": 240.0,
		"rocket_splash_mul": 0.9,
	},
	"heavy_artillery": {
		"label": "Heavy Artillery", "hp": 220.0, "size": 34.0,
		"range": 5000.0, "dmg": 70.0, "cooldown": 2.5,
		"splash": 110.0, "splash_mul": 0.75,
		"proj_kind": "cannonball", "proj_speed": 400.0,
		"cost": {"gold": 100.0, "wood": 70.0}, "train_time": 3.5,
	},
	"jumbo_rocket": {
		"label": "JUMBO Rocket Tank", "hp": 220.0, "size": 38.0,
		"range": 14000.0, "dmg": 220.0, "cooldown": 60.0,
		"cost": {"gold": 160.0, "wood": 100.0}, "train_time": 4.5,
		# One massive warhead (HTML fireArtyVehicle jumbo branch).
		"warhead_dmg": 280.0, "warhead_splash": 320.0,
		"warhead_speed": 280.0,
	},
}

const CREW_MAX := 2              # HTML: crew full at 2
const MOTOR_POOL_MAX := 24       # HTML: "Military motor pool full" at 24 parked
const GUNNER_HP := 80.0          # HTML: dedicated spawned gunner hp 80
const ROLL_SPEED := 300.0        # px/s self-propelled roll toward standoff
const MIN_FIRE_DIST := 40.0      # HTML fire band lower bound
const TARGET_SCAN_INTERVAL := 0.33  # HTML: retarget at most every 20 frames
const COOKOFF_RADIUS_ROCKET := 170.0  # HTML explodeDeath: rocket 170
const COOKOFF_RADIUS_FIELD := 135.0   # HTML explodeDeath: field_cannon/cannoneer 135
const COOKOFF_RADIUS_OTHER := 115.0   # HTML explodeDeath: everything else 115

## Air defense (HTML: AA tower block + anti-nuke block in the projectile tick).
const AA_TOWER_STATS := {
	"range": 4200.0, "shot_cd": 0.10, "max_locks": 6,
	"interceptor_speed": 2200.0, "interceptor_life": 6.0,
	"cost": {"gold": 40.0, "wood": 30.0},
}
const ANTINUKE_STATS := {
	"range": 5000.0, "shot_cd": 0.8,
	"interceptor_speed": 2400.0, "interceptor_life": 7.0,
	"cost": {"gold": 200.0, "wood": 140.0},
}
## Jeremy 2026-10-06: interception is dramatic. When an AA interceptor slams
## into a missile there is a 15% chance the missile is knocked off course —
## it arcs away and slams into the ground nearby (still explodes) instead of
## air-bursting on the spot.
const DEFLECT_CHANCE := 0.15
const DEFLECT_KINDS: Array[String] = ["rocket", "jumbo_rocket", "crashing_rocket", "mortar"]
## Military building types for artillery target scoring (HTML MIL_BUILD_TYPES).
const MIL_BUILD_TYPES := [
	"barracks", "knights_castle", "war_hut", "mage_spire", "tome_library",
	"cannon_foundry", "medic_camp", "field_camp", "equip_camp", "aa_tower",
	"air_defense", "anti_nuke", "guard_tower", "shooting_range", "armory",
	"nuke_silo", "vehicle_depot",
]


var _gs: GameState
var _combat = null  # SimCombat, duck-typed (set by the world)

var vehicles: Array[Dictionary] = []      # vehicle records (not living units)
var interceptors: Array[Dictionary] = []   # live 'aa' interceptor records
var _train_queue: Array[Dictionary] = []  # cannon_foundry training queue
var _next_vehicle_id: int = 1
var _next_interceptor_id: int = 1

## Human-readable reason from the last blocked train ("pool_full" | "cant_afford").
var last_block_reason: String = ""

## HTML parity (fix79 commander_guns -> 'GUNS CREWED'): every artillery piece
## that reaches a full crew is Gazette news. Each vehicle announces once in
## its lifetime; a crewing wave publishes one story per faction with the real
## count. Stories route through court.publish_story (Chronicle archive).
var _guns_story_pending := {}  # faction -> newly fully-crewed pieces


func _init(game_state: GameState, combat = null) -> void:
	_gs = game_state
	_combat = combat


## ---- training ------------------------------------------------------------

## True when a vehicle of this type can be queued (pool space + affordable).
func can_train_vehicle(faction: String, vtype: String) -> bool:
	if not VEHICLE_STATS.has(vtype):
		return false
	if _parked_count(faction) >= MOTOR_POOL_MAX:
		return false
	var cost: Dictionary = VEHICLE_STATS[vtype]["cost"]
	return _gs.resources.can_afford(faction, cost)


## Queue a vehicle at the foundry. Deducts cost immediately (HTML spends on
## train start); the vehicle parks on completion after train_time seconds.
func train_vehicle(faction: String, vtype: String, town_id: int,
		position: Vector2) -> bool:
	if not VEHICLE_STATS.has(vtype):
		last_block_reason = "bad_type"
		return false
	if _parked_count(faction) >= MOTOR_POOL_MAX:
		last_block_reason = "pool_full"
		return false
	var cost: Dictionary = VEHICLE_STATS[vtype]["cost"]
	if not _gs.resources.spend(faction, cost):
		last_block_reason = "cant_afford"
		return false
	last_block_reason = ""
	_train_queue.append({
		"faction": faction, "type": vtype, "town_id": town_id,
		"position": position,
		"t": float(VEHICLE_STATS[vtype]["train_time"]),
	})
	return true


## ---- crew ----------------------------------------------------------------

## Mounts a crew member on a vehicle (HTML mountVehicle). Max 2 crew.
## The citizen becomes military crew: job artillery_crew, dmg >= 14,
## range = the piece's range. Returns false when refused.
func mount_crew(unit: Dictionary, vehicle: Dictionary) -> bool:
	if unit.is_empty() or vehicle.is_empty():
		return false
	if not bool(unit.get("alive", false)) or not bool(vehicle.get("alive", false)):
		return false
	var crew: Array = vehicle.get("crew", [])
	if crew.size() >= CREW_MAX:
		return false
	var uid: int = int(unit.get("id", 0))
	if crew.has(uid):
		return false
	if bool(unit.get("is_leader", false)):
		return false
	# Dismount from any other vehicle first (HTML mountVehicle).
	var cur: int = int(unit.get("mounted_vehicle", -1))
	if cur >= 0 and cur != int(vehicle.get("id", -1)):
		dismount_crew(unit)
	crew.append(uid)
	vehicle["crew"] = crew
	if int(vehicle.get("driver_id", -1)) < 0:
		vehicle["driver_id"] = uid
	vehicle["parked"] = false
	# Stat change — citizen becomes military crew (HTML mountVehicle).
	unit["mounted_vehicle"] = int(vehicle.get("id", -1))
	unit["job"] = "artillery_crew"
	unit["is_worker"] = false
	unit["artillery"] = true
	unit["rocket_crew"] = String(vehicle.get("type", "")).contains("rocket")
	unit["grapeshot_crew"] = String(vehicle.get("type", "")) == "grape_cannon"
	unit["dmg"] = maxf(float(unit.get("dmg", 8.0)), 14.0)
	unit["crew_range"] = float(VEHICLE_STATS[vehicle["type"]]["range"])
	# HTML sets crew.speed = 0.9 (relative); Godot px/s ≈ 0.9 × soldier pace.
	unit["speed"] = 85.0
	return true


## Dismounts a crew member (HTML dismountVehicle). An emptied vehicle returns
## to the faction motor pool, parked, in the HTML grid layout.
func dismount_crew(unit: Dictionary) -> void:
	if unit.is_empty():
		return
	var vid: int = int(unit.get("mounted_vehicle", -1))
	unit["mounted_vehicle"] = -1
	unit["artillery"] = false
	unit["rocket_crew"] = false
	unit["grapeshot_crew"] = false
	if vid < 0:
		return
	var v: Dictionary = get_vehicle(vid)
	if v.is_empty():
		return
	var crew: Array = v.get("crew", [])
	var uid: int = int(unit.get("id", 0))
	crew.erase(uid)
	v["crew"] = crew
	if int(v.get("driver_id", -1)) == uid:
		v["driver_id"] = int(crew[0]) if not crew.is_empty() else -1
	if crew.is_empty():
		_park_vehicle(v)


## Keeps every vehicle crewed (HTML ensureArtyCrew): drafts combat units or
## workers first, else spawns a dedicated 80-hp gunner at the piece when the
## population caps allow (crew count as units — standing rule 5).
func ensure_crew(v: Dictionary) -> void:
	if v.is_empty() or not bool(v.get("alive", false)):
		return
	var crew: Array = v.get("crew", [])
	var live: Array = []
	for uid in crew:
		var u: Dictionary = _gs.get_unit(int(uid))
		if not u.is_empty() and u.get("alive", false):
			live.append(int(uid))
	v["crew"] = live
	crew = live
	var faction: String = String(v.get("faction", ""))
	var guard: int = 0
	while crew.size() < CREW_MAX and guard < 6:
		guard += 1
		var cand: Dictionary = _find_crew_candidate(faction)
		if cand.is_empty():
			if _gs.spawner.check_spawn(faction, "artillery_crew",
					int(v.get("town_id", -1))) != "ok":
				break  # pop cap — try again next tick (HTML behavior)
			cand = _gs.spawner.spawn_unit(faction, "artillery_crew",
				int(v.get("town_id", -1)),
				(Vector2(v.get("position", Vector2.ZERO))
					+ Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))))
			if cand.is_empty():
				break
			cand["hp"] = GUNNER_HP
			cand["max_hp"] = GUNNER_HP
		var before: int = crew.size()
		if not mount_crew(cand, v):
			break  # mountVehicle refused — no progress, bail out
		crew = v.get("crew", [])
		if crew.size() == before:
			break
	if int(v.get("driver_id", -1)) < 0 and not crew.is_empty():
		v["driver_id"] = int(crew[0])
	# HTML parity (fix79 'GUNS CREWED'): a piece reaching full crew is news.
	# Flagged per vehicle so each piece announces once in its lifetime.
	var crew_now: Array = v.get("crew", [])
	if crew_now.size() >= CREW_MAX \
			and not bool(v.get("_crew_story_done", false)):
		v["_crew_story_done"] = true
		var cf: String = String(v.get("faction", ""))
		_guns_story_pending[cf] = int(_guns_story_pending.get(cf, 0)) + 1


## ---- per-tick ------------------------------------------------------------

func tick(delta: float) -> void:
	_tick_training(delta)
	for v: Dictionary in vehicles:
		if v.get("alive", false):
			_tick_vehicle(v, delta)
	_tick_interceptors(delta)
	_tick_air_defense(delta)
	# Mounted crew ride the piece.
	for v: Dictionary in vehicles:
		if not v.get("alive", false):
			continue
		var vpos: Vector2 = v.get("position", Vector2.ZERO)
		for uid in v.get("crew", []):
			var u: Dictionary = _gs.get_unit(int(uid))
			if not u.is_empty() and u.get("alive", false):
				u["position"] = vpos
	_flush_guns_stories()


## One GUNS CREWED story per faction per crewing wave (HTML-verbatim text;
## publish_story sanitizes glyphs per the iPhone tofu rule).
func _flush_guns_stories() -> void:
	if _guns_story_pending.is_empty():
		return
	var court = _gs.get("court_sys")
	if court == null or not court.has_method("publish_story"):
		_guns_story_pending.clear()
		return
	for f: String in _guns_story_pending.keys():
		var n: int = int(_guns_story_pending[f])
		if n > 0:
			court.publish_story("GUNS CREWED",
				"%d artillery pieces now have crews. The depot rumbles with purpose." % n,
				"war")
	_guns_story_pending.clear()


## ---- internals -----------------------------------------------------------

func _tick_training(delta: float) -> void:
	for i: int in range(_train_queue.size() - 1, -1, -1):
		var q: Dictionary = _train_queue[i]
		q["t"] = float(q["t"]) - delta
		if float(q["t"]) <= 0.0:
			_train_queue.remove_at(i)
			_create_vehicle(String(q["faction"]), String(q["type"]),
				int(q["town_id"]), q["position"])


func _tick_vehicle(v: Dictionary, delta: float) -> void:
	var stats: Dictionary = VEHICLE_STATS[v["type"]]
	v["cool"] = maxf(0.0, float(v.get("cool", 0.0)) - delta)
	_tick_salvo(v, delta)
	ensure_crew(v)
	var crew: Array = v.get("crew", [])
	var is_rocket: bool = String(v["type"]).contains("rocket")
	var at_war: bool = _race_at_war(String(v["faction"]))
	# During war always unpark and fire from base; at peace, park (HTML).
	if at_war and not crew.is_empty():
		v["parked"] = false
	elif not at_war:
		v["parked"] = true
	# Self-propelled roll toward standoff (rockets only aim; HTML updateArtyVehicles).
	v["scan_t"] = float(v.get("scan_t", 0.0)) - delta
	if float(v.get("scan_t", 0.0)) <= 0.0:
		v["scan_t"] = TARGET_SCAN_INTERVAL
		v["target"] = _find_target(v)
	var tgt: Dictionary = v.get("target", {})
	if not tgt.is_empty() and not _target_alive(tgt):
		tgt = {}
		v["target"] = tgt
	if not bool(v.get("parked", true)) and not tgt.is_empty():
		var vpos: Vector2 = v.get("position", Vector2.ZERO)
		var tpos: Vector2 = tgt["position"]
		var to: Vector2 = tpos - vpos
		var dist: float = to.length()
		v["aim_angle"] = to.angle()
		if not is_rocket:
			var standoff: float = minf(650.0, float(stats["range"]) * 0.5)
			if dist > standoff + 80.0:
				var step: Vector2 = to.normalized() * minf(ROLL_SPEED * delta, dist)
				# Jeremy 2026-10-05: artillery never enters water — holds
				# position instead of rolling in.
				if WaterNav.is_water_at(_gs.map_data, vpos + step):
					v["rolling"] = false
				else:
					v["position"] = vpos + step
					v["rolling"] = true
			else:
				v["rolling"] = false
		# FIRE whenever war is on or a target is in range (not mid-salvo).
		var salvo: Dictionary = v.get("salvo", {})
		if crew.size() >= 1 and float(v.get("cool", 0.0)) <= 0.0 \
				and salvo.is_empty() \
				and dist <= float(stats["range"]) and dist > MIN_FIRE_DIST:
			_fire(v, tgt, stats)
			v["cool"] = 60.0 if is_rocket \
				else (1.8 if String(v["type"]) == "grape_cannon" else 2.5)


## Score-based target acquisition (HTML findArtyTarget): rockets prefer enemy
## halls; walls are nearly ignored; closer military units beat civilians.
func _find_target(v: Dictionary) -> Dictionary:
	var stats: Dictionary = VEHICLE_STATS[v["type"]]
	var max_r: float = float(stats["range"])
	var is_rocket: bool = String(v["type"]).contains("rocket")
	var vpos: Vector2 = v.get("position", Vector2.ZERO)
	var faction: String = String(v["faction"])
	var best: Dictionary = {}
	var best_score: float = INF
	# 1) Buildings — rockets prefer halls anywhere on the map.
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", true)):
			continue
		if String(b.get("faction", "")) == faction:
			continue
		if not _can_fight(faction, String(b.get("faction", ""))):
			continue
		var d: float = vpos.distance_to(b.get("position", Vector2.ZERO))
		if d > max_r or d < 50.0:
			continue
		var btype: String = String(b.get("type", ""))
		var score: float
		if btype == "town_hall" or btype == "hall":
			score = d
		elif btype in ["cannon_foundry", "aa_tower", "barracks"]:
			score = d + 80.0
		elif btype in MIL_BUILD_TYPES:
			score = d + 150.0
		elif btype == "wall":
			score = d + 2000.0
		else:
			score = d + 400.0
		if is_rocket and (btype == "town_hall" or btype == "hall"):
			score *= 0.5
		if score < best_score:
			best_score = score
			best = {"kind": "building",
				"id": int(b.get("id", -1)), "position": b.get("position", Vector2.ZERO)}
	# 2) Units if closer — rockets scan a capped 3000 px radius.
	var u_r: float = minf(max_r, 3000.0 if is_rocket else max_r)
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) == faction:
			continue
		if not _can_fight(faction, String(u.get("faction", ""))):
			continue
		var d: float = vpos.distance_to(u.get("position", Vector2.ZERO))
		if d > u_r or d < MIN_FIRE_DIST:
			continue
		var score: float = d + (0.0 if JobDefs.is_military(String(u.get("job", ""))) else 600.0) \
			+ (300.0 if is_rocket else 0.0)
		if score < best_score:
			best_score = score
			best = {"kind": "unit",
				"id": int(u.get("id", -1)), "position": u.get("position", Vector2.ZERO)}
	return best


func _target_alive(tgt: Dictionary) -> bool:
	if String(tgt.get("kind", "")) == "unit":
		var u: Dictionary = _gs.get_unit(int(tgt.get("id", -1)))
		return not u.is_empty() and u.get("alive", false)
	var b: Dictionary = _get_building(int(tgt.get("id", -1)))
	return not b.is_empty() and bool(b.get("alive", true))


## Fires the piece (HTML fireArtyVehicle): jumbo warhead, rocket salvo start,
## or a single grape/cannonball with splash payload.
func _fire(v: Dictionary, tgt: Dictionary, stats: Dictionary) -> void:
	if _combat == null:
		return
	var vpos: Vector2 = v.get("position", Vector2.ZERO)
	var tpos: Vector2 = tgt["position"]
	var tid: int = int(tgt["id"]) if String(tgt["kind"]) == "unit" else -1
	var faction: String = String(v["faction"])
	var vtype: String = String(v["type"])
	v["aim_angle"] = (tpos - vpos).angle()
	if vtype == "jumbo_rocket":
		var p: Dictionary = _combat.fire_projectile(
			vpos - (tpos - vpos).normalized() * 30.0, tid, tpos,
			"jumbo_rocket", float(stats["warhead_dmg"]),
			float(stats["warhead_splash"]), faction,
			float(stats["warhead_speed"]))
		p["huge"] = true
		p["splash_mul"] = 1.0
		return
	if vtype == "siege_rocket":
		v["salvo"] = {
			"left": randi_range(int(stats["salvo_min"]), int(stats["salvo_max"])),
			"cd": 0.08, "windup": float(stats["salvo_windup"]),
			"target_id": tid, "target_pos": tpos,
		}
		return
	var kind: String = String(stats["proj_kind"])
	var p2: Dictionary = _combat.fire_projectile(
		vpos + (tpos - vpos).normalized() * 28.0, tid, tpos,
		kind, float(stats["dmg"]), float(stats["splash"]), faction,
		float(stats["proj_speed"]))
	p2["splash_mul"] = float(stats["splash_mul"])


## Drip-fires an active rocket salvo (HTML updateArtyVehicles salvo block).
func _tick_salvo(v: Dictionary, delta: float) -> void:
	var salvo: Dictionary = v.get("salvo", {})
	if salvo.is_empty():
		return
	if float(salvo.get("windup", 0.0)) > 0.0:
		salvo["windup"] = float(salvo["windup"]) - delta
		v["salvo"] = salvo
		return
	salvo["cd"] = float(salvo.get("cd", 0.0)) - delta
	while float(salvo.get("cd", 0.0)) <= 0.0 and int(salvo.get("left", 0)) > 0:
		salvo["cd"] = 0.12 + randf() * 0.08
		_launch_one_rocket(v, salvo)
		salvo["left"] = int(salvo["left"]) - 1
	if int(salvo.get("left", 0)) <= 0:
		v["salvo"] = {}
		v["cool"] = 60.0  # 60 s reload after a full salvo (HTML balance)
	else:
		v["salvo"] = salvo


## One rocket off the rails (HTML launchOneRocket): 25% wild arc, heavy
## scatter otherwise. Duds deleted per Jeremy 2026-10-06 — every rocket is
## live. Damage/splash encoded at fire time.
func _launch_one_rocket(v: Dictionary, salvo: Dictionary) -> void:
	if _combat == null:
		return
	var stats: Dictionary = VEHICLE_STATS["siege_rocket"]
	var vpos: Vector2 = v.get("position", Vector2.ZERO)
	var tpos: Vector2 = salvo.get("target_pos", vpos + Vector2(100, 0))
	var tid: int = int(salvo.get("target_id", -1))
	var base_ang: float = (tpos - vpos).angle()
	var wild: bool = randf() < float(stats["wild_chance"])
	var miss_dist: float = 80.0 + randf() * 420.0
	var jx: float = (randf() - 0.5) * miss_dist
	var jy: float = (randf() - 0.5) * miss_dist
	var tx: float
	var ty: float
	if wild:
		tx = tpos.x + jx * 1.8
		ty = tpos.y + jy * 1.8
	else:
		tx = tpos.x + jx * 0.7
		ty = tpos.y + jy * 0.7
	var sx: float = vpos.x - cos(base_ang) * 28.0 + (randf() - 0.5) * 10.0
	var sy: float = vpos.y - sin(base_ang) * 28.0 - 8.0 + (randf() - 0.5) * 8.0
	var dmg: float = randf_range(float(stats["rocket_dmg_min"]), float(stats["rocket_dmg_max"]))
	var splash: float = randf_range(float(stats["rocket_splash_min"]), float(stats["rocket_splash_max"]))
	var speed: float = randf_range(float(stats["rocket_speed_min"]), float(stats["rocket_speed_max"]))
	var p: Dictionary = _combat.fire_projectile(
		Vector2(sx, sy), tid, Vector2(tx, ty),
		"rocket", dmg, splash, String(v["faction"]), speed)
	p["wild"] = wild
	p["huge"] = true
	p["splash_mul"] = float(stats["rocket_splash_mul"])
	v["aim_angle"] = base_ang


## ---- air defense ----------------------------------------------------------

## AA towers and anti-nuke batteries (HTML projectile-tick AA blocks).
## Towers become operational immediately so rockets can be stopped.
func _tick_air_defense(delta: float) -> void:
	if _combat == null:
		return
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", true)):
			continue
		var btype: String = String(b.get("type", ""))
		var is_aa: bool = btype == "aa_tower" or btype == "air_defense"
		var is_an: bool = btype == "anti_nuke"
		if not (is_aa or is_an):
			continue
		b["complete"] = true
		var cd_key: String = "aa_cd" if is_aa else "an_cd"
		b[cd_key] = maxf(0.0, float(b.get(cd_key, 0.0)) - delta)
		if float(b[cd_key]) > 0.0:
			continue
		var st: Dictionary = AA_TOWER_STATS if is_aa else ANTINUKE_STATS
		var bpos: Vector2 = b.get("position", Vector2.ZERO)
		var faction: String = String(b.get("faction", ""))
		var threats: Array = _aa_threats(bpos, faction, float(st["range"]), is_an)
		if threats.is_empty():
			b["_aa_idle"] = true
			continue
		b["_aa_idle"] = false
		var shots: int = 0
		var max_shots: int = int(st["max_locks"]) if is_aa else 1
		for th in threats:
			if shots >= max_shots or float(b[cd_key]) > 0.0:
				break
			b[cd_key] = float(st["shot_cd"])
			shots += 1
			_launch_interceptor(b, th, st, is_an)
		if float(b[cd_key]) < 0.0:
			b[cd_key] = 0.0


## Hostile missiles in range, nearest first (HTML top-6 linear pass).
## Regular AA cannot engage nukes — those need anti_nuke batteries.
func _aa_threats(bpos: Vector2, faction: String, max_r: float,
		anti_nuke: bool) -> Array:
	var out: Array = []
	var r2: float = max_r * max_r
	for p: Dictionary in _combat.projectiles:
		if not p.get("alive", false):
			continue
		if String(p.get("faction", "")) == faction:
			continue
		var kind: String = String(p.get("kind", ""))
		var payload: Dictionary = p.get("payload", {})
		var is_nuke: bool = kind == "nuke" or bool(payload.get("nuke", false))
		if anti_nuke:
			if not is_nuke:
				continue
		else:
			if is_nuke:
				continue
			var big: bool = bool(p.get("big_missile", false)) \
				or bool(p.get("bigMissile", false))
			if not (kind in ["rocket", "jumbo_rocket", "crashing_rocket", "mortar"] or big):
				continue
			if kind == "aa":
				continue
		if int(p.get("aa_locks", 0)) > 6:
			continue
		var d2: float = bpos.distance_squared_to(p.get("position", Vector2.ZERO))
		if d2 >= r2:
			continue
		out.append({"p": p, "d2": d2})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["d2"]) < float(b["d2"]))
	var cap: int = 6 if not anti_nuke else 1
	return out.slice(0, cap)


func _launch_interceptor(b: Dictionary, threat: Dictionary, st: Dictionary,
		anti_nuke: bool) -> void:
	var p: Dictionary = threat["p"]
	p["aa_locks"] = int(p.get("aa_locks", 0)) + 1
	var bpos: Vector2 = b.get("position", Vector2.ZERO)
	var rec: Dictionary = {
		"id": _next_interceptor_id,
		"position": bpos + Vector2(0, -90),
		"target_proj_id": int(p.get("id", -1)),
		"target_pos": p.get("position", Vector2.ZERO),
		"speed": float(st["interceptor_speed"]),
		"life": float(st["interceptor_life"]),
		"faction": String(b.get("faction", "")),
		"anti_nuke": anti_nuke,
		"alive": true,
	}
	_next_interceptor_id += 1
	interceptors.append(rec)
	_gs.bus.projectile_fired.emit({
		"id": -rec["id"], "kind": "aa", "position": rec["position"],
		"target_pos": rec["target_pos"], "dmg": 0.0, "splash": 0.0,
		"faction": rec["faction"], "speed": rec["speed"], "alive": true,
	})


## Interceptors hard-seek their missile and kill it on contact (HTML AA
## interceptor block: lead the target, destroy both within 60 px).
func _tick_interceptors(delta: float) -> void:
	var done: Array = []
	for rec: Dictionary in interceptors:
		rec["life"] = float(rec["life"]) - delta
		if float(rec["life"]) <= 0.0:
			done.append(rec)
			continue
		var tgt: Dictionary = _find_projectile(int(rec["target_proj_id"]))
		if tgt.is_empty():
			tgt = _retarget_missile(rec)
			if tgt.is_empty():
				done.append(rec)
				continue
			rec["target_proj_id"] = int(tgt.get("id", -1))
		var tpos: Vector2 = tgt.get("position", Vector2.ZERO)
		rec["target_pos"] = tpos
		var pos: Vector2 = rec["position"]
		var to: Vector2 = tpos - pos
		var dist: float = to.length()
		var step: float = float(rec["speed"]) * delta
		if dist <= maxf(step, 60.0):
			# Impact: the interceptor slams into the missile. Usually the
			# missile air-bursts (explosion FX at the intercept point); 15%
			# of the time it is knocked off course and slams into the
			# ground nearby instead. Either way the interceptor is spent.
			var kind: String = String(tgt.get("kind", ""))
			var impact: Vector2 = tgt.get("position", Vector2.ZERO)
			if randf() < DEFLECT_CHANCE and kind in DEFLECT_KINDS:
				tgt["deflected"] = true
				tgt["target_id"] = -1  # stop homing; fly to the crash point
				var away: Vector2 = (impact - pos).normalized()
				if away.length() < 0.5:
					away = Vector2.RIGHT.rotated(randf() * TAU)
				tgt["target_pos"] = impact \
					+ away.rotated(randf_range(-0.5, 0.5)) \
						* randf_range(180.0, 420.0)
				done.append(rec)
			else:
				tgt["alive"] = false
				done.append(rec)
				_gs.bus.projectile_done.emit(tgt)
				# Air-burst: the world layer draws the explosion on this.
				_gs.bus.projectile_hit.emit(tgt, impact)
		else:
			rec["position"] = pos + to.normalized() * step
	for rec in done:
		interceptors.erase(rec)


func _find_projectile(proj_id: int) -> Dictionary:
	if _combat == null:
		return {}
	for p: Dictionary in _combat.projectiles:
		if int(p.get("id", -1)) == proj_id and p.get("alive", false):
			return p
	return {}


func _retarget_missile(rec: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d2: float = 900.0 * 900.0
	var pos: Vector2 = rec["position"]
	for p: Dictionary in _combat.projectiles:
		if not p.get("alive", false):
			continue
		if String(p.get("faction", "")) == String(rec["faction"]):
			continue
		var kind: String = String(p.get("kind", ""))
		var payload: Dictionary = p.get("payload", {})
		var is_nuke: bool = kind == "nuke" or bool(payload.get("nuke", false))
		if bool(rec["anti_nuke"]) != is_nuke:
			continue
		if kind == "aa":
			continue
		var d2: float = pos.distance_squared_to(p.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


## ---- vehicle damage --------------------------------------------------------

## Damages a vehicle. At 0 hp the piece cooks off: the crew dies with it and
## nearby units take splash (HTML explodeDeath radii: rocket 170,
## field_cannon 135, everything else 115).
func damage_vehicle(vehicle_id: int, dmg: float, source_faction: String) -> bool:
	var v: Dictionary = get_vehicle(vehicle_id)
	if v.is_empty() or not v.get("alive", false):
		return false
	v["hp"] = float(v.get("hp", 220.0)) - dmg
	if float(v["hp"]) > 0.0:
		return false
	_destroy_vehicle(v, source_faction)
	return true


func _destroy_vehicle(v: Dictionary, source_faction: String) -> void:
	v["alive"] = false
	# The crew goes up with the piece (HTML explodeDeath: "Two crewmen go up").
	for uid in v.get("crew", []):
		_gs.kill_unit(int(uid))
	v["crew"] = []
	v["driver_id"] = -1
	var radius: float = COOKOFF_RADIUS_ROCKET if String(v["type"]).contains("rocket") \
		else (COOKOFF_RADIUS_FIELD if String(v["type"]) == "field_cannon"
			else COOKOFF_RADIUS_OTHER)
	if _combat != null:
		var vpos: Vector2 = v.get("position", Vector2.ZERO)
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			var d: float = vpos.distance_to(u.get("position", Vector2.ZERO))
			if d <= radius:
				_combat.damage_unit(int(u.get("id", 0)),
					float(VEHICLE_STATS[v["type"]]["dmg"]) * (1.0 - 0.5 * d / radius),
					source_faction)


## ---- accessors ------------------------------------------------------------

func get_vehicle(vehicle_id: int) -> Dictionary:
	for v: Dictionary in vehicles:
		if int(v.get("id", -1)) == vehicle_id:
			return v
	return {}


func vehicles_of(faction: String) -> Array:
	var out: Array = []
	for v: Dictionary in vehicles:
		if String(v.get("faction", "")) == faction and v.get("alive", false):
			out.append(v)
	return out


func _parked_count(faction: String) -> int:
	var n: int = 0
	for v: Dictionary in vehicles:
		if String(v.get("faction", "")) == faction \
				and v.get("alive", false) and bool(v.get("parked", true)):
			n += 1
	return n


## Returns an emptied vehicle to the faction motor pool in the HTML grid
## layout (rows of 6, 52 × 56 spacing).
func _park_vehicle(v: Dictionary) -> void:
	var spot: Vector2 = _motor_pool_spot(String(v["faction"]))
	var parked: int = 0
	for x: Dictionary in vehicles:
		if x != v and String(x.get("faction", "")) == String(v["faction"]) \
				and x.get("alive", false) and bool(x.get("parked", true)):
			parked += 1
	var col: int = parked % 6
	var row: int = parked / 6
	v["position"] = spot + Vector2(-130.0 + col * 52.0, -84.0 + row * 56.0)
	v["parked"] = true
	_report_park_trivia(v)


## One vehicle-parking tally for the news desk's DEPOT LOGJAM trivia
## bucket (called from _park_vehicle on genuine park events: completion,
## crew dismount; the per-tick peace re-park sets the flag directly and
## does NOT tally). Null-safe: bare-sim tests and worlds without a court
## skip silently; no new persisted state, so old saves are unaffected.
## Reported straight to the news desk, not bus.gazette_story — a
## per-vehicle bus story would mint a rumor-mill whisper for every parked
## cannon and pop no toast anyway (the 2026-10-07 build/train pattern).
func _report_park_trivia(v: Dictionary) -> void:
	var court = _gs.get("court_sys")
	if court == null:
		return
	var desk = court.get("news_desk")
	if desk == null or not desk.has_method("report"):
		return
	var disp := String(v.get("type", "war machine")).replace("_", " ")
	desk.report("Parked %s at depot" % disp,
		"A %s was parked at the %s depot." % [disp, String(v.get("faction", "the")).capitalize()])


## Motor pool anchor: the faction's town hall, offset like the HTML depot.
func _motor_pool_spot(faction: String) -> Vector2:
	for b: Dictionary in _gs.buildings:
		if String(b.get("faction", "")) == faction \
				and String(b.get("type", "")) == "town_hall":
			var p: Vector2 = b.get("position", Vector2.ZERO)
			return p + Vector2(48.0, 115.0)
	return Vector2(400, 400)


func _create_vehicle(faction: String, vtype: String, town_id: int,
		position: Vector2) -> Dictionary:
	var stats: Dictionary = VEHICLE_STATS[vtype]
	var v: Dictionary = {
		"id": _next_vehicle_id, "type": vtype, "faction": faction,
		"town_id": town_id, "position": position,
		"alive": true, "parked": true,
		"hp": float(stats["hp"]), "max_hp": float(stats["hp"]),
		"size": float(stats["size"]),
		"crew": [], "driver_id": -1,
		"cool": 0.0, "salvo": {}, "target": {},
		"scan_t": 0.0, "aim_angle": 0.0, "rolling": false,
	}
	_next_vehicle_id += 1
	vehicles.append(v)
	_park_vehicle(v)
	return v


func _find_crew_candidate(faction: String) -> Dictionary:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if int(u.get("mounted_vehicle", -1)) >= 0:
			continue
		if bool(u.get("is_leader", false)):
			continue
		var job: String = String(u.get("job", ""))
		if JobDefs.is_military(job) or job in ["worker", "artillery_crew"]:
			return u
	return {}


func _race_at_war(faction: String) -> bool:
	# HTML's atWar(f) is relation-based; the Godot sim has no diplomacy layer
	# yet, so the pragmatic equivalent is: any hostile presence (unit or
	# building of another faction).
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var of: String = String(u.get("faction", ""))
		if of == faction:
			continue
		if _can_fight(faction, of):
			return true
	for b: Dictionary in _gs.buildings:
		var bf: String = String(b.get("faction", ""))
		if bf == "" or bf == faction:
			continue
		if _can_fight(faction, bf):
			return true
	return false


func _can_fight(a: String, b: String) -> bool:
	if _combat != null:
		return bool(_combat.can_fight(a, b))
	return SimCombat.is_hostile(a, b)


func _get_building(building_id: int) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if int(b.get("id", 0)) == building_id:
			return b
	return {}


## ---- save/load ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"vehicles": vehicles.duplicate(true),
		"train_queue": _train_queue.duplicate(true),
		"next_vehicle_id": _next_vehicle_id,
	}


func from_dict(data: Dictionary) -> void:
	vehicles.clear()
	for v in data.get("vehicles", []):
		vehicles.append((v as Dictionary).duplicate(true))
	# Old saves predate the GUNS CREWED story: pieces that were already
	# fully crewed must not announce on the first tick after load.
	for lv in vehicles:
		var lvd: Dictionary = lv
		if (lvd.get("crew", []) as Array).size() >= CREW_MAX:
			lvd["_crew_story_done"] = true
	_train_queue.clear()
	for q in data.get("train_queue", []):
		_train_queue.append((q as Dictionary).duplicate(true))
	_next_vehicle_id = int(data.get("next_vehicle_id", 1))
	interceptors.clear()
