extends SceneTree
## Cursing Gnomes — Stinky Gizmundo rare-catch tests.
##
## Jeremy 2026-10-07 (direct request): "It's a fish" — the Stinky Gizmundo
## is a rare, smelly, legendary catch for fishers. Covers: the roll seam,
## the special ground pickup, collection crediting food, the throttled
## Gazette story (Chronicle + bus, kind "news"), and glyph-free story text.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gizmundo.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Stinky Gizmundo tests ===")
	_test_roll_seam()
	_test_hook_creates_gizmundo_pickup()
	_test_story_throttled_per_day()
	_test_story_lands_in_chronicle_and_bus()
	_test_no_court_falls_back_to_bus()
	_test_collection_credits_food()
	_test_story_text_glyph_free()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.court_sys = SimRoyalCourt.new(gs)
	var ai := WorkerAI.new(gs)
	return {"gs": gs, "ai": ai}


func _test_roll_seam() -> void:
	var w: Dictionary = _new_world()
	var ai: WorkerAI = w["ai"]
	_check("roll true below chance", ai._roll_gizmundo(0.019))
	_check("roll true well below chance", ai._roll_gizmundo(0.0))
	_check("roll false above chance", not ai._roll_gizmundo(0.5))
	_check("roll false at boundary", not ai._roll_gizmundo(WorkerAI.GIZMUNDO_CHANCE))
	_check("roll false at 1.0", not ai._roll_gizmundo(1.0))
	(w["gs"] as GameState).queue_free()


func _test_hook_creates_gizmundo_pickup() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var unit := {"name": "Testy Fisher", "position": Vector2(100, 200)}
	ai._hook_gizmundo(unit, Vector2(100, 200))
	_check("one pickup created", gs.pickups.size() == 1)
	var p: Dictionary = gs.pickups[0]
	_check("pickup kind is gizmundo", String(p.get("kind", "")) == "gizmundo")
	_check("pickup worth a big meal", float(p.get("amount", 0.0)) == WorkerAI.GIZMUNDO_FOOD)
	_check("pickup at fisher feet", (p.get("position", Vector2.ZERO) as Vector2).distance_to(Vector2(100, 190)) < 0.01)
	gs.queue_free()


func _test_story_throttled_per_day() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var unit := {"name": "Lucky", "position": Vector2.ZERO}
	ai._hook_gizmundo(unit, Vector2.ZERO)
	ai._hook_gizmundo(unit, Vector2.ZERO)
	ai._hook_gizmundo(unit, Vector2.ZERO)
	_check("one story per day max", gs.court_sys.stories.size() == 1)
	gs.day_number += 1
	ai._hook_gizmundo(unit, Vector2.ZERO)
	_check("new day allows another story", gs.court_sys.stories.size() == 2)
	gs.queue_free()


func _test_story_lands_in_chronicle_and_bus() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var heard: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: heard.append(s))
	ai._hook_gizmundo({"name": "Bubbles"}, Vector2.ZERO)
	_check("story in Chronicle archive", gs.court_sys.stories.size() == 1)
	var s: Dictionary = gs.court_sys.stories[0]
	_check("headline names the catch", String(s.get("headline", "")) == "STINKY GIZMUNDO!")
	_check("story kind is news not war", String(s.get("kind", "")) == "news")
	_check("story reached the bus", heard.size() == 1)
	gs.queue_free()


func _test_no_court_falls_back_to_bus() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	# No court_sys wired — the direct bus fallback must still fire.
	var heard: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: heard.append(s))
	var ai := WorkerAI.new(gs)
	ai._hook_gizmundo({"name": "Solo"}, Vector2.ZERO)
	_check("fallback story reached bus", heard.size() == 1)
	_check("fallback story kind news", String((heard[0] as Dictionary).get("kind", "")) == "news")
	gs.queue_free()


func _test_collection_credits_food() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	var unit := {
		"name": "Hungry", "position": Vector2(50, 50),
		"carrying": {}, "carry_cap": 40.0,
	}
	ai._hook_gizmundo(unit, Vector2(50, 50))
	_check("gizmundo pickup on ground", gs.pickups.size() == 1)
	ai._collect_pickups(unit)
	var carrying: Dictionary = unit["carrying"]
	_check("gizmundo credited as food", float(carrying.get("food", 0.0)) == WorkerAI.GIZMUNDO_FOOD)
	_check("no stray gizmundo carrying key", not carrying.has("gizmundo"))
	_check("pickup removed after collection", gs.pickups.is_empty())
	gs.queue_free()


func _test_story_text_glyph_free() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var ai: WorkerAI = w["ai"]
	ai._hook_gizmundo({"name": "Glyphy"}, Vector2.ZERO)
	var s: Dictionary = gs.court_sys.stories[0]
	var re := RegEx.new()
	re.compile("^[\\x20-\\x7E\\n\\r\\t]*$")
	_check("headline ASCII-only", re.search(String(s.get("headline", ""))) != null)
	_check("body ASCII-only", re.search(String(s.get("body", ""))) != null)
	gs.queue_free()
