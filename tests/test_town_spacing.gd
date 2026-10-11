extends SceneTree
## Regression tests for Jeremy 2026-10-07 bug report:
## "Town buildings placed too cramped together" — his iPhone screenshot
## showed watchtower, fire station, town hall, houses clustered with
## overlapping footprints. The old _spawn_demo hardcoded offsets 35-145px
## apart; every pair violated footprint(a)+footprint(b)+PLACEMENT_GAP.
##
## The layout now lives in World.DEMO_TOWN_LAYOUT (offsets from the faction
## start). These tests pin the spacing rule so a future edit can't silently
## re-cramp the starting town.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_town_spacing.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("  FAIL: ", name)


func _initialize() -> void:
	print("=== Cursing Gnomes town-spacing tests ===")
	_test_layout_covers_expected_buildings()
	_test_pairwise_spacing()
	_test_completed_split_covers_layout()
	_test_sequential_can_place_at()
	_test_no_building_at_hall_center()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _layout() -> Dictionary:
	return World.DEMO_TOWN_LAYOUT


## The starting town must contain the full expected roster.
func _test_layout_covers_expected_buildings() -> void:
	var layout: Dictionary = _layout()
	var expected: Array[String] = ["town_hall", "guild_hall", "jail",
		"courthouse", "fire_station", "house", "farm", "guard_tower",
		"barn", "coop"]
	_check(layout.size() == expected.size(),
		"layout has exactly %d buildings" % expected.size())
	for btype: String in expected:
		_check(layout.has(btype), "layout includes " + btype)


## Every pair satisfies the same rule the AI auto-layout enforces:
## center distance >= footprint(a) + footprint(b) + PLACEMENT_GAP.
func _test_pairwise_spacing() -> void:
	var layout: Dictionary = _layout()
	var gap: float = SimBuildings.PLACEMENT_GAP
	var keys: Array = layout.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: String = String(keys[i])
			var b: String = String(keys[j])
			var pa: Vector2 = layout[a]
			var pb: Vector2 = layout[b]
			var need: float = SimBuildings.footprint(a) \
				+ SimBuildings.footprint(b) + gap
			_check(pa.distance_to(pb) >= need,
				"spacing %s<->%s: %.0f >= %.0f" % [a, b,
					pa.distance_to(pb), need])


## town_hall is placed first by _spawn_demo; every other layout key must be
## in exactly one of the two placement paths (completed vs blueprint), and
## every list entry must exist in the layout (no dead entries).
func _test_completed_split_covers_layout() -> void:
	var layout: Dictionary = _layout()
	var completed: Array = World.DEMO_TOWN_COMPLETED
	var blueprints: Array = World.DEMO_TOWN_BLUEPRINTS
	_check(not completed.has("town_hall") and not blueprints.has("town_hall"),
		"town_hall in neither list (placed first by _spawn_demo)")
	for btype: String in layout.keys():
		if btype == "town_hall":
			continue
		var in_c: bool = completed.has(btype)
		var in_b: bool = blueprints.has(btype)
		_check(in_c != in_b,
			"btype in exactly one placement path: " + btype)
	for btype: String in completed + blueprints:
		_check(layout.has(btype),
			"placement-list entry exists in layout: " + btype)


## Simulate the placement order through the real can_place_at gate: each
## building, placed after the earlier ones, must be accepted.
func _test_sequential_can_place_at() -> void:
	var layout: Dictionary = _layout()
	var gap: float = SimBuildings.PLACEMENT_GAP
	var rect := Rect2(-2000, -2000, 4000, 4000)
	var placed: Array = []
	# town_hall first, like _spawn_demo.
	var order: Array = ["town_hall"]
	for btype: String in layout.keys():
		if btype != "town_hall":
			order.append(btype)
	for btype: String in order:
		var pos: Vector2 = layout[btype]
		var ok: bool = SimBuildings.can_place_at(
			placed, btype, pos, rect, "", gap, [])
		_check(ok, "can_place_at accepts " + btype)
		placed.append({"alive": true, "complete": true, "type": btype,
			"position": pos, "faction": "humans"})


## Sanity: nothing shares the hall's center tile.
func _test_no_building_at_hall_center() -> void:
	var layout: Dictionary = _layout()
	var hall: Vector2 = layout["town_hall"]
	for btype: String in layout.keys():
		if btype == "town_hall":
			continue
		_check((layout[btype] as Vector2).distance_to(hall) > 1.0,
			"btype not stacked on hall: " + btype)
