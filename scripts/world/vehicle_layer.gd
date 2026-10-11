class_name VehicleLayer
extends Node2D
## Cursing Gnomes — SimVehicles renderer (Jeremy 2026-10-10 vehicle order,
## phase P2: generalize the wagon renderer into a vehicle layer).
##
## Draws every SimVehicles record — wagons, carts, carriages today; fire
## trucks and military vehicles when P5 adds their types — with real
## driving presentation: turn-mirrored bodies, wheels that spin with
## distance travelled, a rolling bob while driving, dust puffs kicked up
## behind moving vehicles, sun-cast shadows, faction trim, camera culling,
## and zero per-frame cost when the fleet is empty.
##
## HTML source of truth for the wagon: drawTradeWagons (fix79:43543).
## Art lives in VehicleArt (shared by all vehicle drawing); this layer owns
## culling, dust, motion phase, and the command list. Wired in world.gd
## next to TradeWagonLayer. Tests drive the pure command builder plus a
## live node with a stub provider Callable.


const DUST_TAN := Color(0.76, 0.68, 0.55, 0.35)
const MAX_PUFFS := 24        ## dust-puff cap (60fps rule)
const PUFF_LIFE := 0.9       ## seconds a puff lives
const PUFF_SPAWN := 0.28     ## seconds between puffs per vehicle (moving)
const MIN_ROLL_SPEED := 1.0  ## px/s below which wheels/bob/dust stop

## Bob phase: radians of bob per px travelled (gentle rolling rock).
const BOB_FREQ := 0.11
const BOB_AMP := 1.5


var _veh = null               ## SimVehicles (untyped: avoids load cycle)
var _camera: Camera2D = null
var _provider: Callable = Callable()  ## () -> Array of vehicle dicts
var _unit_provider: Callable = Callable()  ## () -> Array of unit dicts
	## (graphics-hourly 2026-10-11: resolves rider chibi sprites)

## Last built draw commands (test hooks): Array of Dictionaries
## {kind: "vehicle", type, at, fx, wheel_spin, bob, trim, horse, horse_phase,
## horse_coat, rider_texs} and {kind: "puff", at, r, alpha}.
## `horse` = draft horse hitched (driving, or driver aboard); `horse_phase`
## = gait radians from distance travelled; `horse_coat` = HORSE_COATS index.
## `rider_texs` = driver-first Array of chibi Texture2Ds (nulls for unknown
## units), drawn seated by VehicleArt.
var _commands: Array = []

var _puffs: Array = []        ## {pos: Vector2, age: float}
var _puff_timer := 0.0
var _travel: Dictionary = {}  ## vehicle id -> px travelled (spin + bob)


func _init() -> void:
	z_index = 5  # above roads/ground, below units (same as trade wagons)


func set_vehicles(veh) -> void:
	_veh = veh


func set_camera(cam: Camera2D) -> void:
	_camera = cam


func set_provider(call: Callable) -> void:
	_provider = call


## Units provider for rider sprites: () -> Array of unit dicts
## ({id, faction, job, gender}). Wired by world.gd to game.units.
func set_unit_provider(call: Callable) -> void:
	_unit_provider = call


func _vehicle_list() -> Array:
	if _provider.is_valid():
		return _provider.call()
	if _veh != null and _veh.get("vehicles") != null:
		return _veh.get("vehicles")
	return []


func _process(delta: float) -> void:
	var fleet := _vehicle_list()
	visible = not fleet.is_empty()
	if not visible:
		_puffs.clear()
		_commands.clear()
		_travel.clear()
		return
	# Accumulate travel per vehicle (drives wheel spin + bob phase);
	# drop records for despawned vehicles.
	var seen := {}
	for v in fleet:
		seen[int(v.get("id", 0))] = true
	for vid in _travel.keys():
		if not seen.has(vid):
			_travel.erase(vid)
	for v in fleet:
		var vid := int(v.get("id", 0))
		if String(v.get("state", "")) == SimVehicles.STATE_DRIVING \
				and float(v.get("speed", 0.0)) > MIN_ROLL_SPEED:
			_travel[vid] = float(_travel.get(vid, 0.0)) \
				+ float(v.get("speed", 0.0)) * delta
	# Dust puffs behind moving vehicles.
	_puff_timer += delta
	if _puff_timer >= PUFF_SPAWN:
		_puff_timer = 0.0
		for v in fleet:
			if _puffs.size() >= MAX_PUFFS:
				break
			if String(v.get("state", "")) != SimVehicles.STATE_DRIVING \
					or float(v.get("speed", 0.0)) <= MIN_ROLL_SPEED:
				continue
			var facing := float(v.get("facing", 0.0))
			var dir := Vector2(cos(facing), sin(facing))
			_puffs.append({
				"pos": (v["pos"] as Vector2) - dir * 14.0 \
					+ Vector2(0, 6.0),
				"age": 0.0,
			})
	var kept: Array = []
	for p in _puffs:
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) < PUFF_LIFE:
			kept.append(p)
	_puffs = kept
	# Unit lookup for rider sprites (built once per frame, not per vehicle).
	var units_by_id := {}
	if _unit_provider.is_valid():
		for u in _unit_provider.call():
			if u is Dictionary:
				units_by_id[int((u as Dictionary).get("id", 0))] = u
	_commands = _build_commands(fleet, units_by_id)
	queue_redraw()


## Pure: turns the vehicle list into draw commands (test hook).
func _build_commands(fleet: Array, units_by_id: Dictionary = {}) -> Array:
	var cmds: Array = []
	var view := _visible_rect()
	for v in fleet:
		var pos: Vector2 = v["pos"]
		if view != Rect2() and not view.grow(80.0).has_point(pos):
			continue  # camera-culled
		var vtype := String(v.get("type", "wagon"))
		var facing := float(v.get("facing", 0.0))
		var fx := 1.0 if cos(facing) >= 0.0 else -1.0
		var driving := String(v.get("state", "")) \
			== SimVehicles.STATE_DRIVING \
			and float(v.get("speed", 0.0)) > MIN_ROLL_SPEED
		var dist := float(_travel.get(int(v.get("id", 0)), 0.0))
		var radius: float = VehicleArt.WHEEL_RADIUS.get(vtype, 4.5)
		var fc: Dictionary = Config.FACTIONS.get(
			String(v.get("faction", "")), {})
		# Draft horse (Jeremy 2026-10-11 deep animation pass): hitched while
		# driving or while a driver is aboard (parked + driverless = the
		# horse is unhitched in the stable). Gait rides the same accumulated
		# travel as the wheels, so a standing horse stands still.
		var hitched := driving \
			or int(v.get("driver_id", -1)) >= 0
		# Seated riders (graphics-hourly 2026-10-11): driver-first chibi
		# textures for VehicleArt's seats; extras ride inside, unseen.
		var rider_texs := _rider_textures(v, units_by_id,
			VehicleArt.rider_seats(vtype).size())
		cmds.append({
			"kind": "vehicle",
			"type": vtype,
			"at": pos,
			"fx": fx,
			"wheel_spin": dist / radius if driving else 0.0,
			"bob": sin(dist * BOB_FREQ) * BOB_AMP if driving else 0.0,
			"trim": fc.get("color", Color.WHITE),
			"horse": hitched,
			"horse_phase": dist * VehicleArt.HORSE_GAIT,
			"horse_coat": abs(int(v.get("id", 0))) \
				% VehicleArt.HORSE_COATS.size(),
			"rider_texs": rider_texs,
		})
	for p in _puffs:
		var age := float(p["age"])
		var k := 1.0 - age / PUFF_LIFE
		cmds.append({
			"kind": "puff",
			"at": p["pos"],
			"r": 4.0 + age * 9.0,
			"alpha": 0.35 * k,
		})
	return cmds


## Resolves driver-first chibi textures for a vehicle's riders (up to
## `max_riders`), or nulls when the unit is unknown / has no art. The
## texture cache in Art makes this a cheap dictionary hit per frame.
func _rider_textures(v: Dictionary, units_by_id: Dictionary,
		max_riders: int) -> Array:
	var out: Array = []
	if max_riders <= 0:
		return out
	var ids: Array = []
	var did := int(v.get("driver_id", -1))
	if did >= 0:
		ids.append(did)
	for c in v.get("crew", []):
		ids.append(int(c))
		if ids.size() >= max_riders:
			break
	for rid in ids:
		var u: Dictionary = units_by_id.get(rid, {})
		var tex: Texture2D = null
		if not u.is_empty():
			var faction := String(u.get("faction", ""))
			tex = Art.unit_texture(faction, String(u.get("job", "worker")),
				rid, String(u.get("gender", "m")))
			if tex == null:
				# Same fallback UnitNode.setup uses: worker m0.
				tex = Art.unit_texture(faction, "worker", 0, "m")
		out.append(tex)
	return out


func _visible_rect() -> Rect2:
	if _camera == null:
		return Rect2()
	var zoom := _camera.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return Rect2()
	if not is_inside_tree():
		return Rect2()  # headless tests: no viewport, no culling
	var vp := get_viewport_rect().size
	var size := Vector2(vp.x / zoom.x, vp.y / zoom.y)
	return Rect2(_camera.get_screen_center_position() - size * 0.5, size)


func _draw() -> void:
	for c in _commands:
		if String(c["kind"]) == "puff":
			var col := DUST_TAN
			col.a = float(c["alpha"])
			draw_circle(c["at"], float(c["r"]), col)
		else:
			var fx := float(c["fx"])
			if bool(c.get("horse", false)):
				VehicleArt.draw_horse(self,
					(c["at"] as Vector2) \
						+ Vector2(VehicleArt.HORSE_AHEAD * fx, 0.0),
					fx, float(c["horse_phase"]),
					int(c["horse_coat"]))
			VehicleArt.draw_vehicle(self, String(c["type"]), c["at"],
				fx, float(c["wheel_spin"]), float(c["bob"]),
				c["trim"], c.get("rider_texs", []))
