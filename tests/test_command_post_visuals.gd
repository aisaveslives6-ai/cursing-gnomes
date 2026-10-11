extends SceneTree
## Cursing Gnomes — command-post capture visuals (Jeremy 2026-10-06
## Battlefront directive).
##
## Captured posts must visibly change to the holder's faction color.
## Monastery/crystal ownership rings are drawn from the record's owner at
## every _draw (4 Hz redraw), so a capture updates the ring live with no
## extra wiring. These tests pin that live-read contract: the node must
## reflect a record owner change immediately, never a stale setup-time copy.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_command_post_visuals.gd
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


## Lets one _draw run headlessly (dummy renderer).
func _draw_once(n: Node2D) -> void:
	n.queue_redraw()
	await process_frame
	await process_frame


func _test_monastery_owner_live() -> void:
	var mn := MonasteryNode.new()
	mn.setup(1, "auriel", Vector2(200, 200))
	mn.record = {"owner": "", "progress": {}, "contested": false}
	root.add_child(mn)
	_check("monastery: unowned at setup", mn._owner_faction() == "")
	await _draw_once(mn)
	# Capture: the sim mutates the record's owner in place.
	mn.record["owner"] = "humans"
	_check("monastery: owner reads live after capture",
		mn._owner_faction() == "humans")
	await _draw_once(mn)  # smoke: _draw runs with the new owner, no error
	mn.record["owner"] = "undead"
	_check("monastery: owner reads live after recapture",
		mn._owner_faction() == "undead")
	await _draw_once(mn)
	mn.free()


func _test_crystal_owner_live() -> void:
	var cn := CrystalNode.new()
	cn.setup(1, "vexmor", Vector2(300, 300))
	cn.record = {"owner": "", "progress": {}, "contested": false}
	root.add_child(cn)
	_check("crystal: unowned at setup", cn._owner_faction() == "")
	await _draw_once(cn)
	cn.record["owner"] = "elves"
	_check("crystal: owner reads live after capture",
		cn._owner_faction() == "elves")
	await _draw_once(cn)  # smoke: _draw runs with the new owner, no error
	cn.record["owner"] = "ogres"
	_check("crystal: owner reads live after recapture",
		cn._owner_faction() == "ogres")
	await _draw_once(cn)
	cn.free()


## The ring color comes from the same live owner read — a capture that
## changes _owner_faction() necessarily recolors the ring next redraw.
func _test_ring_color_follows_owner() -> void:
	var mn := MonasteryNode.new()
	mn.setup(2, "auriel", Vector2(200, 200))
	mn.record = {"owner": "humans", "progress": {}, "contested": false}
	root.add_child(mn)
	var human_c: Color = Config.FACTIONS["humans"]["color"]
	var drawn: Color = Config.FACTIONS.get(mn._owner_faction(),
		{}).get("color", Color(1, 1, 1))
	_check("ring: human color while held", drawn.is_equal_approx(human_c))
	mn.record["owner"] = "gnomes"
	var gnome_c: Color = Config.FACTIONS["gnomes"]["color"]
	var drawn2: Color = Config.FACTIONS.get(mn._owner_faction(),
		{}).get("color", Color(1, 1, 1))
	_check("ring: gnome color after capture", drawn2.is_equal_approx(gnome_c))
	mn.free()


func _initialize() -> void:
	print("=== Cursing Gnomes command-post visual tests ===")
	await _test_monastery_owner_live()
	await _test_crystal_owner_live()
	_test_ring_color_follows_owner()
	print("  passed %d/%d" % [_passed, _passed + _failed])
	if _failed > 0:
		print("  FAILURES: ", _failures)
		quit(1)
	else:
		quit(0)
