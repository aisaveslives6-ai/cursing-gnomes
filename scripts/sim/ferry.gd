class_name SimFerry
extends RefCounted
## Cursing Gnomes — naval ferry/transport (HTML WATERX ferry parity).
##
## Ports the HTML build's ferry half of the WATERX module
## (build-staging/fix79/index.html: waterxOrderFerry, waterxEmbark,
## waterxDisembarkBoat, waterxDisembarkAll, waterxBoatFerryTick, the
## waterxAITick ferry branch, and the unit-movement EMBARK TRIGGER).
## Verbatim HTML numbers:
##   - boatCapacity: war_ship -> 8, anything else -> 4
##   - orderFerry: candidates alive, not downed, same race, not boats, not
##     embarked, no ferryBoat, within 300px; NEVER auto-grabs the player
##     hero (isPlayerHero && race == playerRace); military-first sort
##     (COMBAT_JOBS.includes(job) || isLeader) then distance; invites up to
##     capacity; ferryDest set, ferryState='boarding', ferryTimer=25,
##     anchor=false, passengers=[]; invitee gets ferryBoat + moveTarget at
##     the boat, target/playerOrder cleared; 'All aboard!' bubble
##   - embark: capacity check; passenger offset +/-17px x (+/-34 range),
##     +/-11px y (+/-22 range); clears ferryBoat/moveTarget/target/playerOrder
##   - disembark: each passenger lands at nearestLand(boat) +/-30px jitter;
##     embarked/embarkedBoat/ferryBoat/moveTarget cleared; passengers=[];
##     ferryState/ferryDest cleared
##   - ferryTick boarding: timer -= dt; incoming = a unit alive, unembarked,
##     with ferryBoat == boat; full || timer <= 0 || (!incoming && passengers
##     > 0) ends boarding; no passengers -> cancelled; else 'sailing' with
##     moveTarget = nearestWater(ferryDest) || ferryDest + 'Casting off!'
##   - ferryTick sailing: within 120px of ferryDest -> disembark +
##     'Ferry arrived — troops ashore'
##   - EMBARK TRIGGER (invitee walking to the boat): boat dead/missing, or
##     boat sailing with dist > 600 -> ferryBoat cleared (missed boat);
##     else moveTarget = boat pos; within 48px -> embark (fail -> clear)
##   - nearestLand: dry input returned as-is; else ring r=40..880 step 40,
##     12 angles, 40px map margin, first dry point wins, fallback input
##   - nearestWater: wet input returned as-is; else ring r=40..1360 step 40,
##     12 angles, 80px map margin, first wet point wins, else null
##   - AI ferry branch (waterxAITick, span > 900px): free boat (alive, same
##     race, isBoat, no ferryState) -> dest = nearestWater(enemy hall) ->
##     orderFerry(boat, dest, militaryFirst=true) -> "<Race> launches a
##     ferry assault" (the branch itself lives in SimWaterCrossing; it calls
##     this system's order_ferry + nearest_water)
##
## Godot mapping: HTML object refs become unit ids (passengers: Array of
## unit ids; embarked_boat/ferry_boat: unit id, -1 = none) so the whole
## voyage survives SaveSystem.snapshot/restore (whole unit dicts are
## encoded; Vector2s round-trip as [x, y]). Boats are unit dicts whose job
## is in SimBuildings.BOAT_JOBS. Combat-job sort uses JobDefs.is_military
## (the Godot COMBAT_JOBS counterpart); leaders use the is_leader flag;
## the player hero is the adventure hero (is_hero + player faction).
## systemMsg lines become gazette_story (kind "war"); unitBubble lines go
## through bus.unit_said (bubble visuals removed 2026-10-05).
##
## Pure logic — no rendering, no input, no audio. Sailing moves the boat
## itself (speed = boat speed x BOAT_SPECS speed_mul); invited walkers are
## steered by setting move_target, which their owning subsystem walks,
## exactly like the HTML unit tick. World owns one instance (see WIRING).
##
## WIRING (world.gd — owned by the world agent):
##   var ferry  # SimFerry — naval ferry/transport
##   configure(): ferry = SimFerry.new(game)
##                waterx = SimWaterCrossing.new(game, buildings_sys, ferry)
##   _physics_process(): if ferry != null: ferry.tick(delta)


## Ferry order/tick numbers (HTML WATERX verbatim, px / game seconds).
const BOARD_RADIUS := 300.0      # orderFerry invites within 300px
const BOARD_TIMER := 25.0        # ferryTimer counts down from 25s
const EMBARK_RADIUS := 48.0      # invitee boards within 48px of the boat
const MISSED_BOAT_PX := 600.0    # sailing boat farther than this: missed it
const ARRIVE_RADIUS := 120.0      # sailing: < 120px of ferryDest = ashore
const LAND_RING_MIN := 40.0      # nearestLand ring: 40..880, step 40
const LAND_RING_MAX := 880.0
const WATER_RING_MAX := 1360.0   # nearestWater ring: 40..1360, step 40
const RING_STEP := 40.0
const RING_ANGLES := 12
const LAND_MARGIN := 40.0        # nearestLand map margin
const WATER_MARGIN := 80.0       # nearestWater map margin
const DISEMBARK_JITTER := 30.0   # +/-30px landing jitter (HTML: *60 range)
const EMBARK_OX := 34.0          # +/-17px passenger x offset (HTML: *34)
const EMBARK_OY := 22.0          # +/-11px passenger y offset (HTML: *22)

## Ferry states (HTML ferryState: null | 'boarding' | 'sailing').
const STATE_NONE := ""
const STATE_BOARDING := "boarding"
const STATE_SAILING := "sailing"

## Default walk speed when a boat unit has no speed field (soldier
## baseline, combat.gd MILITARY_STATS); multiplied by BOAT_SPECS speed_mul.
const DEFAULT_SPEED := 95.0


var _gs: GameState

## R18 live set: unit ids (int) currently relevant to the ferry system —
## boats (any, so idle boats keep their _sail physics exactly as before),
## embarked passengers, and invited board-walkers. Rebuilt by a defensive
## full scan every 30 frames (0.5 s) so no drift can persist; every mutation
## site in this file tracks/untracks immediately so invites embark without
## resync latency. _live is ephemeral (no save/load) — first tick after a
## load does a full resync.
var _live := {}
var _resync_cd := 0
const RESYNC_EVERY := 30


func _init(game_state: GameState) -> void:
	_gs = game_state


## Boat passenger capacity (HTML boatCapacity verbatim).
func boat_capacity(boat: Dictionary) -> int:
	if boat.is_empty():
		return 4
	return 8 if String(boat.get("job", "")) == "war_ship" else 4


## True when the unit dict is a boat (HTML isBoat flag).
func is_boat(u: Dictionary) -> bool:
	return SimBuildings.BOAT_JOBS.has(String(u.get("job", "")))


## Nearest dry point to (x, y) (HTML waterxNearestLand verbatim).
func nearest_land(pos: Vector2) -> Vector2:
	if not _in_water(pos):
		return pos
	var ws := _world_size()
	var r := LAND_RING_MIN
	while r <= LAND_RING_MAX:
		for a in range(RING_ANGLES):
			var ang: float = float(a) / float(RING_ANGLES) * TAU
			var px := pos.x + cos(ang) * r
			var py := pos.y + sin(ang) * r
			if px < LAND_MARGIN or py < LAND_MARGIN \
					or px > ws.x - LAND_MARGIN or py > ws.y - LAND_MARGIN:
				continue
			var p := Vector2(px, py)
			if not _in_water(p):
				return p
		r += RING_STEP
	return pos  # fallback: input (HTML)


## Nearest wet point to (x, y), or null when none found (HTML
## waterxNearestWater verbatim — ring max 1360, 80px margin).
func nearest_water(pos: Vector2):
	if _in_water(pos):
		return pos
	var ws := _world_size()
	var r := RING_STEP
	while r <= WATER_RING_MAX:
		for a in range(RING_ANGLES):
			var ang: float = float(a) / float(RING_ANGLES) * TAU
			var px := pos.x + cos(ang) * r
			var py := pos.y + sin(ang) * r
			if px < WATER_MARGIN or py < WATER_MARGIN \
					or px > ws.x - WATER_MARGIN or py > ws.y - WATER_MARGIN:
				continue
			var p := Vector2(px, py)
			if _in_water(p):
				return p
		r += RING_STEP
	return null


## Orders a ferry: invites nearby friendlies aboard, then the ferry_tick
## state machine sails and unloads (HTML waterxOrderFerry verbatim).
## Returns false when the boat is missing/dead/not-a-boat or dest is null.
func order_ferry(boat: Dictionary, dest, military_first: bool) -> bool:
	if boat.is_empty() or not bool(boat.get("alive", false)):
		return false
	if not is_boat(boat) or dest == null:
		return false
	var d := dest as Vector2
	boat["ferry_dest"] = d
	boat["ferry_state"] = STATE_BOARDING
	_track(boat)  # R18: boat enters the live set immediately
	boat["ferry_timer"] = BOARD_TIMER
	boat["anchor"] = false
	if not boat.has("passengers"):
		boat["passengers"] = []
	var cap := boat_capacity(boat)
	var bpos: Vector2 = boat.get("position", Vector2.ZERO)
	var bf: String = String(boat.get("faction", ""))
	var pf: String = String(_gs.player_faction) if _gs != null else ""
	var cands: Array = []
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != bf:
			continue
		if is_boat(u):
			continue
		if bool(u.get("embarked", false)):
			continue
		if int(u.get("ferry_boat", -1)) >= 0:
			continue
		# Never auto-grab the player hero (HTML isPlayerHero check).
		if bool(u.get("is_hero", false)) and String(u.get("faction", "")) == pf:
			continue
		var dd: float = (u.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(bpos)
		if dd < BOARD_RADIUS:
			cands.append({"u": u, "d": dd})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if military_first:
			var am := 0 if _is_military_unit(a["u"]) else 1
			var bm := 0 if _is_military_unit(b["u"]) else 1
			if am != bm:
				return am < bm
		return float(a["d"]) < float(b["d"]))
	var boat_id := int(boat.get("id", 0))
	var invited := 0
	for c in cands:
		if (boat.get("passengers", []) as Array).size() + invited >= cap:
			break
		var u: Dictionary = c["u"]
		u["ferry_boat"] = boat_id
		_track(u)  # R18: invited walker boards the live set immediately
		u["move_target"] = bpos
		u["target"] = null
		u["player_order"] = null
		invited += 1
	_announce("Ferry boarding" + (" — %d coming" % invited
		if invited > 0 else " — no units nearby"))
	_say(boat, "All aboard!")
	return true


## Boards a unit onto a boat (HTML waterxEmbark verbatim). Returns false
## when either is missing/dead or the boat is full.
func embark(u: Dictionary, boat: Dictionary) -> bool:
	if u.is_empty() or boat.is_empty():
		return false
	if not bool(u.get("alive", false)) or not bool(boat.get("alive", false)):
		return false
	if not boat.has("passengers"):
		boat["passengers"] = []
	if (boat["passengers"] as Array).size() >= boat_capacity(boat):
		return false
	(boat["passengers"] as Array).append(int(u.get("id", 0)))
	u["embarked"] = true
	u["embarked_boat"] = int(boat.get("id", 0))
	u["ferry_ox"] = (randf() - 0.5) * EMBARK_OX
	u["ferry_oy"] = (randf() - 0.5) * EMBARK_OY
	u["ferry_boat"] = -1
	u["move_target"] = null
	u["target"] = null
	u["player_order"] = null
	return true


## Unloads one boat's passengers onto the nearest shore (HTML
## waterxDisembarkBoat verbatim); clears the ferry order.
func disembark_boat(boat: Dictionary) -> void:
	for pid in boat.get("passengers", []):
		var p: Dictionary = _gs.get_unit(int(pid))
		if p.is_empty() or not bool(p.get("alive", false)):
			continue
		var shore := nearest_land(boat.get("position", Vector2.ZERO))
		p["position"] = Vector2(
			shore.x + (randf() - 0.5) * DISEMBARK_JITTER * 2.0,
			shore.y + (randf() - 0.5) * DISEMBARK_JITTER * 2.0)
		p["embarked"] = false
		p["embarked_boat"] = -1
		p["ferry_boat"] = -1
		p["move_target"] = null
		_untrack(p)  # R18: passenger leaves the live set
	boat["passengers"] = []
	boat["ferry_state"] = STATE_NONE
	_track(boat)  # R18: boats stay live — idle boats keep _sail physics
	boat.erase("ferry_dest")


## Save-safety sweep (HTML waterxDisembarkAll): nobody persists mid-voyage —
## flags cleared, positions kept. Kept as public API parity; the normal
## save path persists ferry fields verbatim instead.
func disembark_all() -> void:
	for u: Dictionary in _gs.units:
		if is_boat(u):
			u["passengers"] = []
			u["ferry_state"] = STATE_NONE
			u.erase("ferry_dest")
		elif bool(u.get("embarked", false)):
			u["embarked"] = false
			u["embarked_boat"] = -1
			u["ferry_boat"] = -1
	# R18: everyone flags-cleared; live set collapses back to idle boats.
	_resync()
	_resync_cd = RESYNC_EVERY


## The per-boat ferry state machine (HTML waterxBoatFerryTick verbatim).
func ferry_tick(boat: Dictionary, dt: float) -> void:
	if not boat.has("passengers"):
		boat["passengers"] = []
	var state := String(boat.get("ferry_state", STATE_NONE))
	if state == STATE_BOARDING:
		boat["ferry_timer"] = float(boat.get("ferry_timer", BOARD_TIMER)) - dt
		var incoming := false
		var boat_id := int(boat.get("id", 0))
		for u: Dictionary in _gs.units:
			if bool(u.get("alive", false)) and not bool(u.get("embarked", false)) \
					and int(u.get("ferry_boat", -1)) == boat_id:
				incoming = true
				break
		var full := (boat["passengers"] as Array).size() >= boat_capacity(boat)
		if full or float(boat.get("ferry_timer", 0.0)) <= 0.0 \
				or (not incoming and (boat["passengers"] as Array).size() > 0):
			if (boat["passengers"] as Array).is_empty():
				boat["ferry_state"] = STATE_NONE
				boat.erase("ferry_dest")
			else:
				boat["ferry_state"] = STATE_SAILING
				var fd: Vector2 = boat.get("ferry_dest",
					boat.get("position", Vector2.ZERO))
				var w = nearest_water(fd)
				boat["move_target"] = w if w != null else fd
				_say(boat, "Casting off!")
	elif state == STATE_SAILING:
		var bpos: Vector2 = boat.get("position", Vector2.ZERO)
		var fd: Vector2 = boat.get("ferry_dest", bpos)
		if bpos.distance_to(fd) < ARRIVE_RADIUS:
			disembark_boat(boat)
			_announce("Ferry arrived — troops ashore")


## Master tick: ferry state machines, sailing, passenger carrying, and the
## invitee boarding trigger. Called once per physics frame by the world.
## R18: iterates the live set (boats + embarked + board-walkers, typically
## 0-12 units) instead of scanning all units; a resync every 30 frames
## keeps the set exact. Branch behavior per unit is identical.
func tick(delta: float) -> void:
	_resync_cd -= 1
	if _resync_cd <= 0:
		# R18: amortized 30-frame full scan (~8 units/frame) catches boats
		# built by the building system plus any flag drift elsewhere.
		_resync()
		_resync_cd = RESYNC_EVERY
	for id in _live.keys():
		if not _live.has(id):
			# R18: a ferry_tick side effect (disembark_boat) may have
			# untracked this unit mid-sweep; the snapshot key is stale.
			continue
		var u: Dictionary = _live[id]
		if not bool(u.get("alive", false)):
			_live.erase(id)
			continue
		if is_boat(u):
			if String(u.get("ferry_state", STATE_NONE)) != STATE_NONE:
				ferry_tick(u, delta)
			_sail(u, delta)
		elif bool(u.get("embarked", false)):
			_ride(u)
		elif int(u.get("ferry_boat", -1)) >= 0:
			_board_walk(u)
		else:
			_live.erase(id)


## True when the unit must be in the live set (R18 predicate).
func _wants_track(u: Dictionary) -> bool:
	if is_boat(u):
		return true
	if bool(u.get("embarked", false)):
		return true
	return int(u.get("ferry_boat", -1)) >= 0


func _track(u: Dictionary) -> void:
	if u.is_empty():
		return
	_live[int(u.get("id", 0))] = u


func _untrack(u: Dictionary) -> void:
	if u.is_empty():
		return
	_live.erase(int(u.get("id", 0)))


## Defensive full scan: rebuild _live so it exactly matches the predicate
## (R18). Runs every 30 frames plus the first tick after a save-load.
func _resync() -> void:
	if _gs == null:
		return
	var keep := {}
	for u: Dictionary in _gs.units:
		if _wants_track(u):
			var id := int(u.get("id", 0))
			keep[id] = u
	_live = keep


## Sails a ferry boat toward its move_target (speed = boat speed x
## BOAT_SPECS speed_mul, the HTML (s.speed || 60) * speed_mul shape with
## the Godot px/s baseline).
func _sail(boat: Dictionary, delta: float) -> void:
	var tgt = boat.get("move_target", null)
	if tgt == null:
		return
	var p: Vector2 = boat.get("position", Vector2.ZERO)
	var t := tgt as Vector2
	var to := t - p
	var dist := to.length()
	if dist < 6.0:
		return
	var spec: Dictionary = SimBuildings.boat_spec(String(boat.get("job", "")))
	var spd: float = float(boat.get("speed", DEFAULT_SPEED)) \
		* float(spec.get("speed_mul", 1.0))
	boat["position"] = p + to.normalized() * minf(spd * delta, dist)


## Embarked passengers ride the boat (HTML: the embarked branch of the
## unit movement tick). Boat lost -> flags cleared, they swim for it.
func _ride(u: Dictionary) -> void:
	var boat: Dictionary = _gs.get_unit(int(u.get("embarked_boat", -1)))
	if boat.is_empty() or not bool(boat.get("alive", false)):
		u["embarked"] = false
		u["embarked_boat"] = -1
		_untrack(u)  # R18: no boat to ride — leave the live set
		return
	var bp: Vector2 = boat.get("position", Vector2.ZERO)
	u["position"] = bp + Vector2(float(u.get("ferry_ox", 0.0)),
		float(u.get("ferry_oy", 0.0)))
	u["move_target"] = null
	u["target"] = null


## The EMBARK TRIGGER (HTML unit-movement branch verbatim): an invited unit
## walks to its ferry boat, boards within 48px, drops the invite when the
## boat is dead/missing or sailed >600px away.
func _board_walk(u: Dictionary) -> void:
	var boat: Dictionary = _gs.get_unit(int(u.get("ferry_boat", -1)))
	if boat.is_empty() or not bool(boat.get("alive", false)):
		u["ferry_boat"] = -1
		_untrack(u)  # R18: invite dead — leave the live set
		return
	var bp: Vector2 = boat.get("position", Vector2.ZERO)
	var up: Vector2 = u.get("position", Vector2.ZERO)
	var dist := up.distance_to(bp)
	if String(boat.get("ferry_state", STATE_NONE)) == STATE_SAILING \
			and dist > MISSED_BOAT_PX:
		u["ferry_boat"] = -1
		_untrack(u)  # R18: missed the sailing boat — leave the live set
		return
	u["move_target"] = bp
	if dist < EMBARK_RADIUS:
		if not embark(u, boat):
			u["ferry_boat"] = -1
			_untrack(u)  # R18: embark refused — leave the live set


## HTML COMBAT_JOBS/includes || isLeader parity for the military-first sort.
func _is_military_unit(u: Dictionary) -> bool:
	return JobDefs.is_military(String(u.get("job", ""))) \
		or bool(u.get("is_leader", false))


## Point-in-water probe (HTML inWaterAt parity; mirrors the
## SimWaterCrossing approach: center-tile lookup on the terrain grid).
func _in_water(pos: Vector2) -> bool:
	var md: Dictionary = _gs.map_data
	if md.is_empty():
		return false
	var terrain: PackedByteArray = md.get("terrain", PackedByteArray())
	if terrain.is_empty():
		return false
	var tpx: float = maxf(1.0, float(md.get("tile_size", 32.0)))
	var tx := int(pos.x / tpx)
	var ty := int(pos.y / tpx)
	if tx < 0 or ty < 0 or tx >= MapGen.MAP_TILES or ty >= MapGen.MAP_TILES:
		return false
	return MapGen.is_water(terrain[ty * MapGen.MAP_TILES + tx])


func _world_size() -> Vector2:
	var md: Dictionary = _gs.map_data
	if not md.is_empty() and md.has("world_size"):
		return md["world_size"]
	return Vector2(4096.0, 4096.0)


## HTML systemMsg parity for ferry milestones (quiet-AI rule respected:
## only order/arrival milestones announce, like the HTML).
func _announce(body: String) -> void:
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs, "Ferry", body, "war")


## HTML unitBubble parity — emits bus.unit_said (bubble visual removed).
func _say(boat: Dictionary, text: String) -> void:
	_gs.bus.unit_said.emit(int(boat.get("id", 0)), text)
