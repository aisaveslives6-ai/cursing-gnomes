extends SceneTree
## Cursing Gnomes — tap-a-resource gather menu tests (Jeremy 2026-10-06).
##
## The tutorial promises "tap a tree, rock, or bush and order them to
## harvest", and the HTML opens a tap-menu (tmGatherMenu) for resource
## nodes — but SimIndustry.order_gather had zero callers: tapping a
## resource did nothing. Launch readiness gate 1 (playable & functional):
## tapping a harvestable work site opens the gather bottom sheet, whose
## button sends up to 6 nearby free workers via order_gather.
##
## Covers: order_gather assignment rules (up to 6, nearest first, skips
## busy/dead/foreign/non-worker units, depletes/unknown sites -> 0),
## gather_ordered emission, World.nearest_harvest_site pick math
## (nearest wins, depleted/wrong-kind/too-far skipped), and the HUD
## gather menu (content per kind, button wires the order, result hint,
## tap-outside-to-close).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gather_menu.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	print("=== Cursing Gnomes tap-a-resource gather menu tests ===")
	_run.call_deferred()


func _new_stack() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes", "undead"])
	gs.player_faction = "gnomes"
	gs.industry = SimIndustry.new(gs)
	return [gs]


func _worker(uid: int, pos: Vector2, job: String = "worker",
		faction: String = "gnomes", busy: bool = false) -> Dictionary:
	var u := {
		"id": uid, "alive": true, "faction": faction, "job": job,
		"position": pos, "work_building": 0 if busy else -1,
		"work_site": -1, "work_state": "",
	}
	return u


func _run() -> void:
	await process_frame
	await process_frame
	_test_order_gather_assignment()
	_test_order_gather_edges()
	_test_nearest_harvest_site()
	_test_gather_menu_ui()
	print("  passed=%d failed=%d" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _test_order_gather_assignment() -> void:
	var pack := _new_stack()
	var gs: GameState = pack[0]
	# Tree at origin; workers at staggered distances.
	var site := gs.add_work_site({"kind": "tree",
		"position": Vector2.ZERO, "amount": 60.0, "yield": 60.0})
	var sid := int(site["id"])
	gs.units.append(_worker(1, Vector2(50, 0)))
	gs.units.append(_worker(2, Vector2(150, 0)))
	gs.units.append(_worker(3, Vector2(250, 0)))
	var n: int = gs.industry.order_gather(sid)
	_check("order_gather sends all 3 free workers", n == 3)
	for uid in [1, 2, 3]:
		var u: Dictionary = gs.get_unit(uid)
		_check("worker %d pointed at site" % uid,
			int(u.get("work_site", -2)) == sid)
		_check("worker %d state to_resource" % uid,
			String(u.get("work_state", "")) == "to_resource")
		var tp: Vector2 = u.get("work_target_pos", Vector2(9999, 9999))
		_check("worker %d target near site" % uid,
			tp.distance_to(Vector2.ZERO) < 60.0)
	gs.queue_free()


func _test_order_gather_edges() -> void:
	var pack := _new_stack()
	var gs: GameState = pack[0]
	var site := gs.add_work_site({"kind": "gold_vein",
		"position": Vector2(1000, 1000), "amount": 150.0})
	var sid := int(site["id"])
	# 8 free workers -> HTML-verbatim cap of 6.
	for i in range(8):
		gs.units.append(_worker(10 + i, Vector2(1000 + i * 10, 1000)))
	# Busy builder, dead unit, foreign worker, soldier: all skipped.
	gs.units.append(_worker(20, Vector2(1000, 1000), "worker", "gnomes", true))
	gs.units.append(_worker(21, Vector2(1000, 1000)))
	gs.units[gs.units.size() - 1]["alive"] = false
	gs.units.append(_worker(22, Vector2(1000, 1000), "worker", "undead"))
	gs.units.append(_worker(23, Vector2(1000, 1000), "soldier"))
	var emitted := [0, -1]
	gs.bus.gather_ordered.connect(
		func(faction: String, got_site: int, count: int) -> void:
			emitted[0] += 1
			emitted[1] = count)
	var n: int = gs.industry.order_gather(sid)
	_check("order_gather caps at 6 workers", n == 6)
	_check("gather_ordered emitted once", emitted[0] == 1)
	_check("gather_ordered carries count", emitted[1] == 6)
	_check("busy builder skipped",
		int(gs.get_unit(20).get("work_site", -1)) == -1)
	_check("dead unit skipped",
		int(gs.get_unit(21).get("work_site", -1)) == -1)
	_check("foreign worker skipped",
		int(gs.get_unit(22).get("work_site", -1)) == -1)
	_check("soldier skipped",
		int(gs.get_unit(23).get("work_site", -1)) == -1)
	# Depleted site and unknown id: 0, no crash, no signal.
	var dry := gs.add_work_site({"kind": "tree",
		"position": Vector2(50, 50), "amount": 0.0})
	_check("depleted site -> 0",
		gs.industry.order_gather(int(dry["id"])) == 0)
	_check("unknown site -> 0", gs.industry.order_gather(424242) == 0)
	gs.queue_free()


func _test_nearest_harvest_site() -> void:
	var sites: Array = [
		{"id": 1, "kind": "tree", "position": Vector2(100, 100),
			"amount": 60.0},
		{"id": 2, "kind": "tree", "position": Vector2(200, 200),
			"amount": 0.0},  # depleted
		{"id": 3, "kind": "gold_vein", "position": Vector2(106, 106),
			"amount": 150.0},
		{"id": 4, "kind": "oil_pile", "position": Vector2(105, 105),
			"amount": 50.0},  # not a harvest kind
	]
	var hit := World.nearest_harvest_site(sites, Vector2(110, 110), 60.0)
	_check("nearest live site picked (gold vein id 3, not dead tree)",
		int(hit.get("id", -1)) == 3)
	var hit2 := World.nearest_harvest_site(sites, Vector2(500, 500), 60.0)
	_check("nothing in range -> empty", hit2.is_empty())
	var hit3 := World.nearest_harvest_site([], Vector2.ZERO, 60.0)
	_check("empty site list -> empty", hit3.is_empty())
	# Depleted tree alone in range: skipped, not returned.
	var only_dry := World.nearest_harvest_site([sites[1]],
		Vector2(200, 200), 60.0)
	_check("depleted site skipped", only_dry.is_empty())


func _test_gather_menu_ui() -> void:
	var pack := _new_stack()
	var gs: GameState = pack[0]
	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	await process_frame
	var site := gs.add_work_site({"kind": "tree",
		"position": Vector2.ZERO, "amount": 60.0, "yield": 60.0})
	gs.units.append(_worker(1, Vector2(50, 0)))
	gs.units.append(_worker(2, Vector2(150, 0)))
	hud.show_gather_menu(site)
	await process_frame
	_check("gather menu visible", hud._gather_menu.visible)
	_check("gather scrim visible", hud._gather_scrim.visible)
	_check("gather title per kind", hud._gather_title.text == "Tree")
	_check("gather subtitle", hud._gather_sub.text == "Chop for wood")
	_check("gather button verb + note",
		hud._gather_button.text == "Cut tree  ·  sends nearby workers")
	# Button press wires the real order: workers assigned, hint flashed.
	hud._gather_button.pressed.emit()
	await process_frame
	_check("button sends workers",
		int(gs.get_unit(1).get("work_site", -1)) == int(site["id"]))
	_check("menu closes on order", not hud._gather_menu.visible)
	_check("result hint flashed", hud._hint_label.text == "2 workers sent")
	# Gold vein flavor.
	var vein := gs.add_work_site({"kind": "gold_vein",
		"position": Vector2(300, 300), "amount": 150.0})
	hud.show_gather_menu(vein)
	_check("gold vein title", hud._gather_title.text == "Gold vein")
	_check("gold vein verb", hud._gather_button.text.begins_with("Mine gold"))
	# Tap-outside-to-close.
	hud._gather_scrim.pressed.emit()
	_check("scrim tap closes menu", not hud._gather_menu.visible)
	_check("scrim tap closes scrim", not hud._gather_scrim.visible)
	# No-free-workers path: all workers busy.
	for u in gs.units:
		u["work_building"] = 5
	hud.show_gather_menu(site)
	hud._gather_button.pressed.emit()
	_check("no free workers hint", hud._hint_label.text == "No free workers")
	hud.queue_free()
	gs.queue_free()
