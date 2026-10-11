extends SceneTree
## Cursing Gnomes — town-capture fanfare (Jeremy 2026-10-07 graphics hourly).
##
## A town hall flipping sides is the war's biggest visible moment. The world
## must flash the hall in the CONQUEROR's faction color when
## _on_command_post_captured fires — and the sim must NOT emit combat_fx
## "capture_taken" for town flips (the world flashes the nearest monastery
## for that kind, so a town falling near a monastery lit up the wrong
## building). Monasteries/crystals keep their own "capture_taken" fanfare.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_capture_fanfare.gd
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


## Live one-shot flashes on a rig: [{pos, color}] for slots with life > 0.
func _live_flashes(rig: LightingRig) -> Array:
	var out: Array = []
	for slot in rig._flash_lights:
		if float(slot["life"]) > 0.0:
			var l: PointLight2D = slot["light"]
			out.append({"pos": l.position, "color": l.color})
	return out


func _test_town_capture_flash() -> void:
	var rig := LightingRig.new()
	rig.setup(null, "low")
	var w := World.new()
	w.lighting = rig  # no scene needed: the fanfare path never touches it
	var humans_c: Color = Config.FACTIONS["humans"]["color"]
	w._on_command_post_captured("town", 4242, "elves", "humans",
		Vector2(500, 600))
	var flashes := _live_flashes(rig)
	_check("town capture: exactly one flash fires", flashes.size() == 1)
	if flashes.size() == 1:
		_check("town capture: flash at the hall",
			(flashes[0]["pos"] as Vector2).is_equal_approx(Vector2(500, 600)))
		_check("town capture: flash in the conqueror's faction color",
			(flashes[0]["color"] as Color).is_equal_approx(humans_c))
	# Non-town kinds stay silent on this path — monastery/crystal captures
	# own their fanfare through their dedicated bus signals.
	w._on_command_post_captured("monastery", 7, "elves", "humans",
		Vector2(10, 10))
	_check("monastery kind: no town flash added",
		_live_flashes(rig).size() == 1)
	# Unknown holder falls back to white, never crashes.
	w._on_command_post_captured("town", 4243, "elves", "no_such_faction",
		Vector2(0, 0))
	var flashes2 := _live_flashes(rig)
	_check("town capture: second flash fires", flashes2.size() == 2)
	w.free()
	rig.free()


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	var cps := SimCommandPosts.new()
	cps.setup(gs)
	gs.command_posts = cps
	return gs


func _test_flip_hall_fx_contract() -> void:
	var gs: GameState = _new_game()
	var hall := {
		"id": 1, "type": "town_hall", "faction": "gnomes",
		"position": Vector2(500, 500), "alive": true, "complete": true,
		"hp": 1200.0, "max_hp": 1200.0, "town_id": 101,
		"town_name": "Testville",
	}
	gs.buildings.append(hall)
	gs.building_by_id[1] = hall
	gs.towns[101] = {"id": 101, "name": "Testville", "faction": "gnomes"}
	var fx_kinds: Array = []
	gs.bus.combat_fx.connect(
		func(kind: String, _pos: Vector2) -> void: fx_kinds.append(kind))
	var post_kinds: Array = []
	gs.bus.command_post_captured.connect(
		func(kind: String, _id: int, _o: String, _n: String,
				_pos: Vector2) -> void: post_kinds.append(kind))
	var horns: Array = [0]
	gs.bus.sfx_spatial.connect(
		func(sfx_name: String, _pos: Vector2,
				_vel: Vector2) -> void:
			if sfx_name == "war_horn":
				horns[0] += 1)
	var combat := SimCombat.new(gs)
	var destroyed: bool = combat.damage_building(1, 5000.0, "humans")
	_check("hall flip: damage returns true", destroyed)
	_check("hall flip: faction flips to attacker",
		String(hall.get("faction", "")) == "humans")
	_check("hall flip: no combat_fx capture_taken for towns",
		not fx_kinds.has("capture_taken"))
	_check("hall flip: command_post_captured town still emitted",
		post_kinds == ["town"])
	_check("hall flip: war horn still sounds", int(horns[0]) == 1)
	gs.free()


func _initialize() -> void:
	print("=== Cursing Gnomes town-capture fanfare tests ===")
	_test_town_capture_flash()
	_test_flip_hall_fx_contract()
	print("  passed %d/%d" % [_passed, _passed + _failed])
	if _failed > 0:
		print("  FAILURES: ", _failures)
		quit(1)
	else:
		quit(0)
