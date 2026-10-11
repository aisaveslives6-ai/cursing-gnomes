extends SceneTree
## Cursing Gnomes — Milestone 2 headless world tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_world.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _frame: int = 0
var _world: Node = null


func _initialize() -> void:
	print("=== Cursing Gnomes world tests ===")
	_test_map_gen()
	_test_faction_starts()
	_test_camera_clamp()
	_test_selection_pick()
	_test_region_labels()
	# The world scene's _ready() only fires once frames run, so the scene
	# test is deferred to _process (frame 2). Everything else is pure logic.
	var ps: PackedScene = load("res://scenes/world/world.tscn")
	_check("world scene loads", ps != null)
	if ps != null:
		_world = ps.instantiate()
		root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_test_world_scene()
		print("=== %d passed, %d failed ===" % [_passed, _failed])
		for f: String in _failures:
			print("  FAIL: ", f)
		quit(1 if _failed > 0 else 0)
		return true
	return false


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _gen4() -> Dictionary:
	return MapGen.new().generate(["humans", "ogres", "elves", "gnomes"], 42)


## Map generates without errors; sizes and bake dimensions are sane.
func _test_map_gen() -> void:
	var map: Dictionary = _gen4()
	var terrain: PackedByteArray = map["terrain"]
	_check("terrain tile count", terrain.size() == 128 * 128)
	_check("world size", map["world_size"] == Vector2(4096, 4096))
	var img: Image = map["terrain_image"]
	_check("bake is 512x512", img.get_width() == 512 and img.get_height() == 512)
	var trees: PackedVector2Array = map["trees"]
	_check("trees exist", trees.size() > 100)
	var resources: Array = map["resources"]
	# Jeremy 2026-10-05: NO wood piles, NO oil piles — wood clusters plant
	# tree groves, oil comes from pumps. Resources are gold only:
	# 4 factions x 3 gold, minus water rejects.
	_check("resource nodes exist", resources.size() >= 8)
	for r in resources:
		_check("resource is gold", String(r["type"]) == "gold")
	# The wood went into tree groves near each start (200-340px out).
	var starts0: Dictionary = map["faction_starts"]
	for f in starts0:
		var sp: Vector2 = starts0[f]
		var near := 0
		for t in trees:
			if t.distance_to(sp) < 360.0:
				near += 1
		_check("wood grove near start: " + String(f), near >= 3)
	# Every faction start sits on grass (carved by gen).
	var gen := MapGen.new()
	var starts: Dictionary = map["faction_starts"]
	for f in starts:
		_check("start on grass: " + String(f), gen.tile_at(map, starts[f]) == MapGen.TILE_GRASS)
	# Determinism: same seed -> same starts.
	var map2: Dictionary = _gen4()
	var starts2: Dictionary = map2["faction_starts"]
	for f in starts:
		_check("deterministic start: " + String(f), starts[f] == starts2[f])


## The 4 starts are spread apart (quadrants), never overlapping.
func _test_faction_starts() -> void:
	var map: Dictionary = _gen4()
	var starts: Dictionary = map["faction_starts"]
	_check("four starts", starts.size() == 4)
	var keys: Array = starts.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var d: float = (starts[keys[i]] as Vector2).distance_to(starts[keys[j]])
			_check("starts spread: %s/%s" % [keys[i], keys[j]], d > 1200.0)


## Camera clamp math: inside stays, outside clamps (with 25% overscroll),
## zoomed-out centers. Jeremy 2026-10-05: scroll outside the map — the
## effective bounds grow 25% of the map size per side (1024px on 4096).
func _test_camera_clamp() -> void:
	var b := Rect2(0, 0, 4096, 4096)
	var view := Vector2(1280, 720)
	var p: Vector2 = CameraController.clamp_position(Vector2(-500, -500), view, 1.0, b)
	_check("clamp negative corner (overscroll)", p == Vector2(-384, -500))
	p = CameraController.clamp_position(Vector2(5000, 5000), view, 1.0, b)
	_check("clamp far corner (overscroll)", p == Vector2(4480, 4760))
	p = CameraController.clamp_position(Vector2(2048, 2048), view, 1.0, b)
	_check("clamp keeps inside", p == Vector2(2048, 2048))
	# Overscroll: 25% beyond the edge is reachable.
	p = CameraController.clamp_position(Vector2(-900, 2048), view, 1.0, b)
	_check("overscroll left reachable", p == Vector2(-384, 2048))
	p = CameraController.clamp_position(Vector2(2048, 4700), view, 1.0, b)
	_check("overscroll bottom reachable", p == Vector2(2048, 4700))
	# Past the overscroll limit still clamps.
	p = CameraController.clamp_position(Vector2(-2000, 2048), view, 1.0, b)
	_check("overscroll limit holds", p == Vector2(-384, 2048))
	# Zoomed way out: view dwarfs the expanded bounds horizontally, so
	# x centers on the expanded bounds; y clamps partway.
	p = CameraController.clamp_position(Vector2(0, 0), view, 0.2, b)
	_check("clamp zoomed-out centers", p == Vector2(2048, 776))
	# Zoomed in: tighter bounds, inside stays.
	p = CameraController.clamp_position(Vector2(100, 100), view, 2.0, b)
	_check("clamp zoomed-in", p == Vector2(100, 100))


## Selection pick: nearest within radius wins, far away misses.
func _test_selection_pick() -> void:
	var a := Node2D.new()
	a.position = Vector2(100, 100)
	var b2 := Node2D.new()
	b2.position = Vector2(300, 300)
	var nodes: Array = [a, b2]
	_check("pick nearest", Selection.pick(Vector2(110, 105), nodes, 60.0) == 0)
	_check("pick second", Selection.pick(Vector2(310, 290), nodes, 60.0) == 1)
	_check("pick miss", Selection.pick(Vector2(900, 900), nodes, 60.0) == -1)
	_check("pick boundary miss", Selection.pick(Vector2(160, 100), nodes, 59.0) == -1)
	a.free()
	b2.free()


## Region labels on the paper map: SimTerritory.compute_regions feeds
## PaperMap._region_label_rows() with names from the pool, faction colors,
## and map-space positions. Standing rule: labels use faction colors.
func _test_region_labels() -> void:
	var pm := PaperMap.new()
	_check("region labels: no game -> no rows", pm._region_label_rows().is_empty())
	var gs := GameState.new()
	pm._game = gs
	_check("region labels: no buildings -> no rows", pm._region_label_rows().is_empty())
	gs.buildings = [
		{"id": 1, "type": "hall", "faction": "elves",
			"alive": true, "complete": true, "position": Vector2(500, 500)},
		{"id": 2, "type": "hall", "faction": "elves",
			"alive": true, "complete": true, "position": Vector2(600, 520)},
		{"id": 3, "type": "hall", "faction": "ogres",
			"alive": true, "complete": true, "position": Vector2(3000, 3000)},
	]
	pm._map_rect = Rect2(0, 0, 640, 480)
	var rows: Array = pm._region_label_rows()
	# 2 faction clusters + 10 unclaimed sectors on the 4096x4096 world:
	# sector (0,0) is claimed by the elves halls, sector (2,2) sits within
	# TERRITORY_R*1.2 of the ogre cluster centroid.
	_check("region labels: two clusters + ten sectors", rows.size() == 12)
	# compute_regions sorts by centroid x: elves (550) first, ogres (3000) second.
	var elves_row: Dictionary = rows[0]
	var ogres_row: Dictionary = rows[1]
	var elves_col: Color = (Config.FACTIONS["elves"] as Dictionary)["color"]
	var ogres_col: Color = (Config.FACTIONS["ogres"] as Dictionary)["color"]
	_check("region labels: names from pool",
		String(elves_row["label"]) in SimTerritory.REGION_NAME_POOL
		and String(ogres_row["label"]) in SimTerritory.REGION_NAME_POOL
		and String(elves_row["label"]) != String(ogres_row["label"]))
	_check("region labels: faction colors",
		Color(elves_row["color"]).is_equal_approx(Color(elves_col, 0.95))
		and Color(ogres_row["color"]).is_equal_approx(Color(ogres_col, 0.95)))
	var sector_gray := Color(Color8(0x8a, 0x8a, 0x8a), 0.95)
	var gray_rows := 0
	var seen: Dictionary = {}
	var all_from_pool := true
	for row: Dictionary in rows:
		var lbl := String(row["label"])
		seen[lbl] = true
		if not (lbl in SimTerritory.REGION_NAME_POOL):
			all_from_pool = false
		if Color(row["color"]).is_equal_approx(sector_gray):
			gray_rows += 1
	_check("region labels: unclaimed sectors gray #8a8a8a", gray_rows == 10)
	_check("region labels: all names unique + from pool",
		seen.size() == rows.size() and all_from_pool)
	_check("region labels: positions inside map",
		Rect2(0, 0, 640, 480).has_point(elves_row["pos"])
		and Rect2(0, 0, 640, 480).has_point(ogres_row["pos"]))
	# Unknown / missing race falls back to gray (Color.GRAY), while unclaimed
	# sectors use HTML's #8a8a8a.
	var gs2 := GameState.new()
	gs2.buildings = [
		{"id": 9, "type": "hall", "faction": "zzz",
			"alive": true, "complete": true, "position": Vector2(100, 100)},
	]
	pm._game = gs2
	var rows2: Array = pm._region_label_rows()
	_check("region labels: unknown-faction cluster + sectors",
		rows2.size() == 13)
	var unknown_gray := 0
	var wild_gray := 0
	for row2: Dictionary in rows2:
		var cc := Color(row2["color"])
		if cc.is_equal_approx(Color(Color.GRAY, 0.95)):
			unknown_gray += 1
		elif cc.is_equal_approx(sector_gray):
			wild_gray += 1
	_check("region labels: unknown race gray fallback",
		unknown_gray == 1 and wild_gray == 12)
	pm.free()
	gs.free()
	gs2.free()


## The world scene instantiates: camera, units and buildings exist.
## Runs on frame 2 (see _initialize note about _ready deferral).
func _test_world_scene() -> void:
	var w: Node = _world
	_check("world instantiated", w != null)
	if w == null:
		return
	_check("camera present", w.get_node_or_null("GameCamera") != null)
	_check("units spawned", w.get_node("Units").get_child_count() >= 10)
	# Demo: 5 factions x (town_hall + guild_hall + jail + courthouse +
	# barn + coop + 4 blueprints) = 50 building nodes.
	_check("buildings spawned", w.get_node("Buildings").get_child_count() == 50)
	_check("props spawned", w.get_node("Props").get_child_count() > 100)
	var sel: Selection = w.get_node("Selection") as Selection
	_check("selection wired", sel != null and sel.camera != null)
	_check("selectables collected", sel != null and sel.selectables.size() >= 12)
	root.remove_child(w)
	w.free()
