extends SceneTree
## Cursing Gnomes — SimFerry R18 live-set optimization tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ferry_liveset.gd
##
## Exit code 0 = all passed, 1 = any failure. Covers: order_ferry tracks
## the boat + invitees in _live immediately; the full boarding -> sailing ->
## disembark voyage runs through tick() alone with identical outcomes and
## correct live-set membership at every stage; drop paths (_board_walk boat
## dead, _ride boat lost) untrack; idle boats keep _sail physics via the live
## set; the 30-frame resync catches externally-set flags (drift safety);
## dead units are evicted from _live by tick.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes ferry live-set tests ===")
	_test_order_tracks_live()
	_test_full_voyage_through_tick()
	_test_board_walk_drop_untracks()
	_test_ride_boat_lost_untracks()
	_test_resync_catches_drift()
	_test_idle_boat_still_sails()
	_test_dead_unit_evicted()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Synthetic world: 128x128 tiles (32px), water stripe at tile columns
## [x0, x1). Returns [gs, ferry].
func _make_world(x0: int, x1: int) -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])  # player = humans
	var terrain := PackedByteArray()
	terrain.resize(128 * 128)
	for i in terrain.size():
		terrain[i] = MapGen.TILE_GRASS
	for ty in 128:
		for tx in range(x0, x1):
			terrain[ty * 128 + tx] = MapGen.TILE_WATER
	gs.map_data = {
		"terrain": terrain, "tile_size": 32.0,
		"world_size": Vector2(4096, 4096),
	}
	var ferry := SimFerry.new(gs)
	gs.bus.gazette_story.connect(func(_s: Dictionary) -> void: pass)
	gs.bus.unit_said.connect(func(_uid: int, _t: String) -> void: pass)
	return [gs, ferry]


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


func _boat(parts: Array, faction: String, job: String,
		pos: Vector2 = Vector2(2048, 2048)) -> Dictionary:
	var gs: GameState = parts[0]
	return gs.add_unit({"faction": faction, "job": job, "town_id": -1,
		"position": pos, "alive": true, "hp": 500.0, "max_hp": 500.0,
		"speed": 95.0})


func _unit(parts: Array, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = parts[0]
	return gs.add_unit({"faction": faction, "job": job, "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0})


func _test_order_tracks_live() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var a: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2050, 2048))
	var b: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2060, 2048))
	_check("order_ferry returns true",
		ferry.order_ferry(boat, Vector2(1500, 2048), false))
	_check("boat tracked immediately",
		ferry._live.has(int(boat.get("id", 0))))
	_check("invitee a tracked immediately",
		ferry._live.has(int(a.get("id", 0))))
	_check("invitee b tracked immediately",
		ferry._live.has(int(b.get("id", 0))))
	_check("live size 3", ferry._live.size() == 3)
	_free_world(parts)


## Full voyage driven by tick() alone: invitees within EMBARK_RADIUS board
## on the first tick, sailing starts when nobody is incoming, and a nearby
## dest triggers arrival + disembark. Same outcomes as the full-scan tick.
func _test_full_voyage_through_tick() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var bid := int(boat.get("id", 0))
	var a: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2052, 2048))
	var b: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2060, 2048))
	var aid := int(a.get("id", 0))
	var bidd := int(b.get("id", 0))
	ferry.order_ferry(boat, Vector2(2090, 2048), false)
	ferry.tick(1.0 / 60.0)
	_check("both embarked after first tick",
		bool(a.get("embarked", false)) and bool(b.get("embarked", false)))
	_check("passengers 2", (boat.get("passengers", []) as Array).size() == 2)
	_check("embarked still live", ferry._live.has(aid) and ferry._live.has(bidd))
	ferry.tick(1.0 / 60.0)
	_check("sailing after boarding tick",
		String(boat.get("ferry_state", "")) == "sailing")
	# Dest is 42px away (< ARRIVE_RADIUS 120): next sailing tick arrives.
	ferry.tick(1.0 / 60.0)
	_check("disembarked at dest",
		String(boat.get("ferry_state", "")) == "")
	_check("a on land, flags cleared",
		not bool(a.get("embarked", false))
		and int(a.get("ferry_boat", -1)) == -1)
	_check("b on land, flags cleared",
		not bool(b.get("embarked", false))
		and int(b.get("ferry_boat", -1)) == -1)
	_check("passenger a left live set", not ferry._live.has(aid))
	_check("passenger b left live set", not ferry._live.has(bidd))
	_check("boat still live after voyage", ferry._live.has(bid))
	_check("live size 1 after voyage", ferry._live.size() == 1)
	_free_world(parts)


func _test_board_walk_drop_untracks() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "fishing_boat")
	var a: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2050, 2048))
	var aid := int(a.get("id", 0))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	_check("invitee tracked before drop", ferry._live.has(aid))
	boat["alive"] = false  # boat lost before the walker reaches it
	ferry.tick(1.0 / 60.0)
	_check("ferry_boat cleared", int(a.get("ferry_boat", -1)) == -1)
	_check("dropped invitee untracked", not ferry._live.has(aid))
	_free_world(parts)


func _test_ride_boat_lost_untracks() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "fishing_boat")
	var a: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2050, 2048))
	var aid := int(a.get("id", 0))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	ferry.tick(1.0 / 60.0)  # boards (within 48px)
	_check("embarked", bool(a.get("embarked", false)))
	boat["alive"] = false  # boat lost mid-voyage
	ferry.tick(1.0 / 60.0)
	_check("embarked cleared", not bool(a.get("embarked", false)))
	_check("passenger untracked", not ferry._live.has(aid))
	_free_world(parts)


## A unit flagged ferry_boat by an outside writer (no _track call) must be
## picked up by the 30-frame defensive resync.
func _test_resync_catches_drift() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "fishing_boat")
	var a: Dictionary = _unit(parts, "gnomes", "worker", Vector2(3000, 3000))
	var aid := int(a.get("id", 0))
	ferry.tick(1.0 / 60.0)  # first tick: resync, only the boat is live
	_check("boat live after first tick",
		ferry._live.has(int(boat.get("id", 0))))
	a["ferry_boat"] = int(boat.get("id", 0))  # external writer, no _track
	_check("drifted unit not live yet", not ferry._live.has(aid))
	for i in 31:
		ferry.tick(1.0 / 60.0)
	_check("resync picked up drifted unit", ferry._live.has(aid))
	_check("drifted unit steered at boat",
		a.get("move_target", null) != null)
	_free_world(parts)


## An idle boat with a move_target must keep sailing even though it is in
## no ferry state (R18 parity: boats are always live).
func _test_idle_boat_still_sails() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "fishing_boat",
		Vector2(2048, 2048))
	boat["move_target"] = Vector2(3000, 2048)
	ferry.tick(1.0)  # resync + sail
	var p: Vector2 = boat.get("position", Vector2.ZERO)
	_check("idle boat sailed", p.x > 2048.0)
	_check("idle boat live", ferry._live.has(int(boat.get("id", 0))))
	_free_world(parts)


func _test_dead_unit_evicted() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "fishing_boat")
	var a: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2050, 2048))
	var aid := int(a.get("id", 0))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	_check("invitee live", ferry._live.has(aid))
	a["alive"] = false
	ferry.tick(1.0 / 60.0)
	_check("dead unit evicted from live", not ferry._live.has(aid))
	_free_world(parts)
