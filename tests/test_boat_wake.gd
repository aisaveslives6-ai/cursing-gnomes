extends SceneTree
## Cursing Gnomes — boat wake tests (2026-10-04).
##
## Boats trail foam flecks from the stern while sailing (BoatWake, an
## original addition — the HTML boat branch has no wake; this extends the
## game's foam-water language, cf. river foam). Pooled + capped at 24
## flecks, batched into one _draw() call, idle boats spawn nothing, and
## the wake hides/frees with the unit (cull + job rebuild safe).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_boat_wake.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(label)
		print("FAIL: ", label)


func _initialize() -> void:
	print("=== Cursing Gnomes boat-wake tests ===")
	_test_wake_node_structure()
	_test_non_boat_no_wake()
	_test_idle_no_flecks()
	_test_moving_spawns_flecks()
	_test_fleck_fields_sane()
	_test_stern_behind_boat()
	_test_flecks_expire()
	_test_pool_cap()
	_test_cull_resets_tracker()
	_test_rebuild_single_wake()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _make_unit(unit_id: int, faction: String, job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(unit_id, faction, job, Vector2(400, 300), "m")
	return un


## Wake exists on boats: child of Body at index 0 (under the hull).
func _test_wake_node_structure() -> void:
	var un := _make_unit(9101, "gnomes", "fishing_boat")
	_check(un._wake != null, "wake: fishing_boat has a BoatWake")
	_check(un._wake is BoatWake, "wake: node is a BoatWake instance")
	_check(un._wake.get_parent() == un._body,
		"wake: wake is a child of Body (hides with the unit when culled)")
	_check(un._body.get_child(0) == un._wake,
		"wake: wake is Body child 0 — renders under the hull")
	_check(un._wake.name == "Wake", "wake: node named 'Wake'")
	un.queue_free()


## Workers (and every non-boat) get no wake.
func _test_non_boat_no_wake() -> void:
	var un := _make_unit(9102, "humans", "worker")
	_check(un._wake == null, "wake: worker has no wake node")
	_check(un._boat == null, "wake: worker is not a boat (sanity)")
	un.queue_free()


## An idle boat spawns nothing.
func _test_idle_no_flecks() -> void:
	var un := _make_unit(9103, "elves", "war_ship")
	for i in range(10):
		un._process(0.016)
	_check(un._wake.fleck_count() == 0,
		"wake: idle boat spawns no flecks")
	un.queue_free()


## A sailing boat spawns flecks at the stern.
func _test_moving_spawns_flecks() -> void:
	var un := _make_unit(9104, "ogres", "fishing_boat")
	for i in range(12):
		un.position += Vector2(4, 0)  # 4 px/frame > MOVE_THRESHOLD
		un._process(0.016)
	_check(un._wake.fleck_count() > 0,
		"wake: moving boat spawns flecks (%d)" % un._wake.fleck_count())
	un.queue_free()


## Fleck fields stay in sane ranges (life, growth, age).
func _test_fleck_fields_sane() -> void:
	var un := _make_unit(9105, "gnomes", "war_ship")
	for i in range(8):
		un.position += Vector2(0, 5)
		un._process(0.016)
	_check(un._wake.fleck_count() > 0, "wake: flecks exist for field check")
	if un._wake.fleck_count() > 0:
		var f: Dictionary = un._wake._flecks[0]
		_check(float(f["life"]) >= 1.0 and float(f["life"]) <= 1.45,
			"wake: fleck life in [1.0, 1.45]")
		_check(float(f["r1"]) > float(f["r0"]),
			"wake: fleck grows (r1 > r0)")
		_check(float(f["age"]) >= 0.0 and float(f["age"]) <= float(f["life"]),
			"wake: fleck age within life")
	un.queue_free()


## Flecks appear behind the boat (stern), not ahead of it.
func _test_stern_behind_boat() -> void:
	var un := _make_unit(9106, "humans", "fishing_boat")
	for i in range(10):
		un.position += Vector2(4, 0)  # sailing +x: stern is -x
		un._process(0.016)
	var behind := true
	for f: Dictionary in un._wake._flecks:
		var p: Vector2 = f["p"]
		if p.x >= 0.0:
			behind = false
	_check(behind, "wake: all flecks spawn behind the boat (stern, -x)")
	un.queue_free()


## Flecks fade out and are removed once the boat stops.
func _test_flecks_expire() -> void:
	var un := _make_unit(9107, "elves", "fishing_boat")
	for i in range(10):
		un.position += Vector2(4, 0)
		un._process(0.016)
	_check(un._wake.fleck_count() > 0, "wake: flecks present before expiry")
	for i in range(4):
		un._process(0.5)  # 2 s idle > max 1.45 s fleck life
	_check(un._wake.fleck_count() == 0,
		"wake: all flecks expire after the boat stops")
	un.queue_free()


## The pool never exceeds MAX_FLECKS, no matter how long the boat sails.
func _test_pool_cap() -> void:
	var un := _make_unit(9108, "undead", "war_ship")
	for i in range(40):
		un._wake._spawn(Vector2(-40, 5), 6.0)
	_check(un._wake.fleck_count() == BoatWake.MAX_FLECKS,
		"wake: pool capped at MAX_FLECKS (%d)" % BoatWake.MAX_FLECKS)
	_check(un._wake.fleck_count() <= 24, "wake: pool cap is 24")
	un.queue_free()


## Un-culling after a teleport must not burst a phantom wake.
func _test_cull_resets_tracker() -> void:
	var un := _make_unit(9109, "gnomes", "fishing_boat")
	un.set_culled(true)
	un.position += Vector2(500, 200)  # teleported while culled
	un.set_culled(false)
	_check(un._last_pos == un.position,
		"wake: un-cull resets the movement tracker")
	un._process(0.016)  # no real movement this frame
	_check(un._wake.fleck_count() == 0,
		"wake: no phantom wake burst after un-cull")
	un.queue_free()


## Boat<->worker rebuilds leave exactly one wake (no duplicates, no dangle).
func _test_rebuild_single_wake() -> void:
	var un := _make_unit(9110, "humans", "war_ship")
	_check(un._wake != null, "wake: war_ship starts with a wake")
	un.set_job("worker")
	_check(un._wake == null, "wake: worker rebuild clears the wake var")
	un.set_job("fishing_boat")
	var wakes := 0
	for c: Node in un._body.get_children():
		if c is BoatWake:
			wakes += 1
	_check(wakes == 1, "wake: exactly one wake after rebuild (no dupes)")
	_check(un._wake != null and un._wake.get_parent() == un._body,
		"wake: rebuilt wake re-attached under Body")
	un.queue_free()
