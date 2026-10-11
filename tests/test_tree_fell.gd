extends SceneTree
## Cursing Gnomes — tree fell / wood pickup loop tests (Jeremy 2026-10-05).
##
## Trees no longer trickle wood into inventories and wood piles are gone.
## Chopping damages the tree; when chopped through, the tree is marked felled
## and bursts into wood pickups; the chopper collects them by walking over
## them and hauls the load to a resource camp like any other gather run.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tree_fell.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes tree-fell tests ===")
	_test_chop_no_trickle()
	_test_fell_bursts_pickups()
	_test_chopper_collects_pickups()
	_test_haul_to_camp_credits_faction()
	_test_wood_pile_not_gatherable()
	_test_pickup_save_roundtrip()
	_test_tree_prop_chop_and_fall()
	_test_lumber_camp_coverage()
	_test_lumber_camp_fallback()
	_test_lumber_camp_dropoff()
	_test_nearest_site_at_radius()
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


func _new_wai() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var wai: WorkerAI = WorkerAI.new(gs)
	return [gs, wai]


func _new_woodcutter(gs: GameState, pos: Vector2) -> Dictionary:
	return gs.add_unit({
		"alive": true, "faction": "humans", "job": "woodcutter",
		"position": pos, "work_state": "idle", "carrying": {},
	})


## Chopping damages the tree but puts NOTHING straight into inventory.
func _test_chop_no_trickle() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	var wai: WorkerAI = parts[1]
	var site: Dictionary = gs.add_work_site(
		{"kind": "tree", "position": Vector2(100, 100), "amount": 60.0})
	var u: Dictionary = _new_woodcutter(gs, Vector2(100, 100))
	u["work_state"] = "gathering"
	u["work_site"] = int(site["id"])
	wai._do_gather(u, 1.0)
	_check("chop: tree damaged", float(site["amount"]) < 60.0)
	_check("chop: no trickle into inventory",
		float((u["carrying"] as Dictionary).get("wood", 0.0)) == 0.0)
	_check("chop: not felled yet", not bool(site.get("felled", false)))
	_check("chop: no pickups yet", gs.pickups.is_empty())
	_check("chop: still gathering", String(u["work_state"]) == "gathering")


## Chopping through fells the tree and bursts the full yield as pickups.
func _test_fell_bursts_pickups() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	var wai: WorkerAI = parts[1]
	var site: Dictionary = gs.add_work_site(
		{"kind": "tree", "position": Vector2(200, 200), "amount": 0.05})
	var u: Dictionary = _new_woodcutter(gs, Vector2(200, 200))
	u["work_state"] = "gathering"
	u["work_site"] = int(site["id"])
	wai._do_gather(u, 1.0)
	_check("fell: site marked felled", bool(site.get("felled", false)))
	_check("fell: site depleted", float(site["amount"]) <= 0.0)
	_check("fell: six pickups burst", gs.pickups.size() == 6)
	var total := 0.0
	for p: Dictionary in gs.pickups:
		total += float(p.get("amount", 0.0))
		_check("fell: pickup is wood", String(p.get("kind", "")) == "wood")
	_check("fell: full 60 wood burst out", is_equal_approx(total, 60.0))
	_check("fell: chopper inventory still empty (collects by walking)",
		float((u["carrying"] as Dictionary).get("wood", 0.0)) == 0.0)


## The chopper (standing at the stump) collects the burst by walking over it.
func _test_chopper_collects_pickups() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	var wai: WorkerAI = parts[1]
	var site: Dictionary = gs.add_work_site(
		{"kind": "tree", "position": Vector2(300, 300), "amount": 0.05})
	var u: Dictionary = _new_woodcutter(gs, Vector2(300, 300))
	u["work_state"] = "gathering"
	u["work_site"] = int(site["id"])
	wai._do_gather(u, 1.0)  # fells the tree, pickups burst at its feet
	_check("collect: burst spawned", gs.pickups.size() == 6)
	wai._collect_pickups(u)
	var have: float = float((u["carrying"] as Dictionary).get("wood", 0.0))
	_check("collect: chopper grabbed a full load", is_equal_approx(have, 10.0))
	_check("collect: one pickup gone", gs.pickups.size() == 5)
	# Next gather tick: site is depleted and the chopper is loaded -> dropoff.
	gs.add_building({
		"alive": true, "complete": true, "faction": "humans",
		"type": "resource_camp", "position": Vector2(300, 360)})
	u["work_state"] = "gathering"
	wai._do_gather(u, 0.1)
	_check("collect: loaded chopper heads to dropoff",
		String(u["work_state"]) == "to_dropoff")


## Dropping the hauled wood at a resource camp credits faction inventory.
func _test_haul_to_camp_credits_faction() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	var wai: WorkerAI = parts[1]
	gs.add_building({
		"alive": true, "complete": true, "faction": "humans",
		"type": "resource_camp", "position": Vector2(400, 400)})
	var u: Dictionary = _new_woodcutter(gs, Vector2(350, 350))
	u["carrying"] = {"wood": 10.0}
	var before: float = gs.resources.get_amount("humans", "wood")
	wai._assign_dropoff(u)
	_check("haul: routed to dropoff", String(u["work_state"]) == "to_dropoff")
	_check("haul: target is the camp",
		(u["work_target_pos"] as Vector2).distance_to(Vector2(400, 400)) < 1.0)
	wai._do_dropoff(u)
	_check("haul: faction wood credited",
		is_equal_approx(gs.resources.get_amount("humans", "wood"), before + 10.0))
	_check("haul: carrying cleared", (u["carrying"] as Dictionary).is_empty())


## Wood piles are not gather targets anymore — trees are the wood source.
func _test_wood_pile_not_gatherable() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	var wai: WorkerAI = parts[1]
	gs.add_work_site(
		{"kind": "wood_pile", "position": Vector2(500, 500), "amount": 150.0})
	var u: Dictionary = _new_woodcutter(gs, Vector2(500, 500))
	_check("piles: woodcutter ignores wood piles",
		not wai._assign_gather(u, "woodcutter"))
	var tree: Dictionary = gs.add_work_site(
		{"kind": "tree", "position": Vector2(520, 520), "amount": 60.0})
	_check("piles: woodcutter takes the tree",
		wai._assign_gather(u, "woodcutter"))
	_check("piles: assigned the tree site",
		int(u["work_site"]) == int(tree["id"]))


## Pickups survive a save/load round trip.
func _test_pickup_save_roundtrip() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	gs.add_pickup({"kind": "wood", "amount": 10.0, "position": Vector2(10, 20)})
	gs.add_pickup({"kind": "wood", "amount": 5.0, "position": Vector2(30, 40)})
	var data: Dictionary = SaveSystem.snapshot(gs)
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	gs2.setup(["humans"])
	_check("save: restore ok", SaveSystem.restore(gs2, data))
	_check("save: pickups restored", gs2.pickups.size() == 2)
	var total := 0.0
	for p: Dictionary in gs2.pickups:
		total += float(p.get("amount", 0.0))
	_check("save: pickup amounts intact", is_equal_approx(total, 15.0))
	# New pickups after a load must not collide with restored ids.
	var np: Dictionary = gs2.add_pickup(
		{"kind": "wood", "amount": 1.0, "position": Vector2.ZERO})
	var ids: Dictionary = {}
	for p: Dictionary in gs2.pickups:
		ids[int(p.get("id", 0))] = true
	_check("save: pickup ids unique", ids.size() == 3)
	_check("save: new id is fresh", int(np["id"]) > 2)


## Tree prop visuals: chop shake toggles, fall topples and frees.
func _test_tree_prop_chop_and_fall() -> void:
	var prop := MapProp.new()
	root.add_child(prop)
	prop.setup("tree", Vector2(60, 60))
	_check("prop: not chopping by default", not prop._chopping)
	prop.set_chopping(true)
	_check("prop: chopping set", prop._chopping)
	prop.set_chopping(false)
	_check("prop: chopping cleared", not prop._chopping)
	prop.play_fall()
	_check("prop: falling flagged", prop._falling)
	prop.play_fall()  # second call is a safe no-op
	_check("prop: double fall safe", prop._falling)


## Lumber camp: woodcutters prefer trees inside the camp's coverage radius
## even when a closer tree sits outside it (Rise of Nations style).
func _test_lumber_camp_coverage() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	var wai: WorkerAI = parts[1]
	# Camp at (1000, 1000). Near tree OUTSIDE the radius, far tree INSIDE.
	var camp_pos := Vector2(1000, 1000)
	var r := SimBuildings.LUMBER_CAMP_RADIUS
	var outside: Dictionary = gs.add_work_site(
		{"kind": "tree", "position": camp_pos + Vector2(r + 200, 0), "amount": 60.0})
	var inside: Dictionary = gs.add_work_site(
		{"kind": "tree", "position": camp_pos + Vector2(r * 0.5, 0), "amount": 60.0})
	gs.add_building({
		"alive": true, "complete": true, "faction": "humans",
		"type": "lumber_camp", "position": camp_pos})
	# Worker stands next to the outside tree — it should still pick the
	# inside one because the camp covers it.
	var u: Dictionary = _new_woodcutter(
		gs, camp_pos + Vector2(r + 200, 10))
	_check("camp: assigns a tree", wai._assign_lumber(u))
	_check("camp: prefers the tree inside coverage",
		int(u["work_site"]) == int(inside["id"]))
	_check("camp: not the outside tree",
		int(u["work_site"]) != int(outside["id"]))


## No camp (or no trees in radius): fall back to the nearest tree anywhere.
func _test_lumber_camp_fallback() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	var wai: WorkerAI = parts[1]
	var tree: Dictionary = gs.add_work_site(
		{"kind": "tree", "position": Vector2(700, 700), "amount": 60.0})
	var u: Dictionary = _new_woodcutter(gs, Vector2(710, 710))
	_check("camp fallback: assigns without a camp", wai._assign_lumber(u))
	_check("camp fallback: nearest tree",
		int(u["work_site"]) == int(tree["id"]))
	# Incomplete camps don't count.
	gs.add_building({
		"alive": true, "complete": false, "faction": "humans",
		"type": "lumber_camp", "position": Vector2(710, 710)})
	var u2: Dictionary = _new_woodcutter(gs, Vector2(710, 710))
	_check("camp fallback: incomplete camp ignored", wai._assign_lumber(u2))
	_check("camp fallback: still the tree",
		int(u2["work_site"]) == int(tree["id"]))


## Wood carriers drop at the lumber camp first, resource camp second.
func _test_lumber_camp_dropoff() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	var wai: WorkerAI = parts[1]
	var camp_pos := Vector2(800, 800)
	var yard_pos := Vector2(820, 820)
	gs.add_building({
		"alive": true, "complete": true, "faction": "humans",
		"type": "resource_camp", "position": camp_pos})
	gs.add_building({
		"alive": true, "complete": true, "faction": "humans",
		"type": "lumber_camp", "position": yard_pos})
	var u: Dictionary = _new_woodcutter(gs, Vector2(810, 810))
	u["carrying"] = {"wood": 10.0}
	wai._assign_dropoff(u)
	_check("dropoff: wood goes to the lumber camp",
		(u["work_target_pos"] as Vector2).distance_to(yard_pos) < 1.0)
	# Non-wood carriers still prefer the resource camp.
	var u2: Dictionary = _new_woodcutter(gs, Vector2(810, 810))
	u2["carrying"] = {"gold": 5.0}
	wai._assign_dropoff(u2)
	_check("dropoff: other goods go to the resource camp",
		(u2["work_target_pos"] as Vector2).distance_to(camp_pos) < 1.0)


## _nearest_site_at: hard radius cap, lowest-id tie-break preserved.
func _test_nearest_site_at_radius() -> void:
	var parts: Array = _new_wai()
	var gs: GameState = parts[0]
	var wai: WorkerAI = parts[1]
	var near: Dictionary = gs.add_work_site(
		{"kind": "tree", "position": Vector2(100, 0), "amount": 60.0})
	var far: Dictionary = gs.add_work_site(
		{"kind": "tree", "position": Vector2(900, 0), "amount": 60.0})
	var got: Dictionary = wai._nearest_site_at(
		Vector2.ZERO, ["tree"], 500.0)
	_check("site_at: finds the near tree", int(got.get("id", 0)) == int(near["id"]))
	_check("site_at: not the far tree", int(got.get("id", 0)) != int(far["id"]))
	var none: Dictionary = wai._nearest_site_at(
		Vector2(5000, 5000), ["tree"], 500.0)
	_check("site_at: empty past the radius", none.is_empty())
	# Depleted trees are skipped.
	near["amount"] = 0.0
	var got2: Dictionary = wai._nearest_site_at(
		Vector2.ZERO, ["tree"], 1000.0)
	_check("site_at: skips depleted", int(got2.get("id", 0)) == int(far["id"]))
