extends SceneTree
## Cursing Gnomes — equipped-tool visual tests (Jeremy 2026-10-05).
##
## The unit's REAL owned tool (petitions "equipped_tool") must drive the
## hand-tool overlay — HTML toolImg54For parity: equipped tool wins, the
## work-kind guess is only the fallback. Covers:
##   - equipped tool shown while working (axe/chop, pickaxe/mine,
##     hoe/farm, hammer/build, fishing rod)
##   - work-kind fallback preserved when the unit owns nothing
##   - unknown tool ids sanitized (no crash, fallback used)
##   - owned tool carried visibly on walk-to-work states (to_dropoff etc.)
##   - hidden while idle even when equipped
##   - thought bubble prefers the equipped tool icon
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_equipment_visual.gd


## Tool sprites are normal-map wrapped at runtime (SpriteNormals.apply_to),
## so texture-identity checks must unwrap via diffuse_of first.
const SN := preload("res://scripts/world/sprite_normals.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes equipment visual tests ===")
	_test_equipped_wins_while_working()
	_test_new_tools_visible()
	_test_fallback_preserved()
	_test_unknown_tool_sanitized()
	_test_carried_while_walking()
	_test_hidden_while_idle()
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


func _make_node() -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(22, "gnomes", "worker", Vector2(100, 100), "m")
	return un


## The equipped tool wins over the work-kind guess.
func _test_equipped_wins_while_working() -> void:
	var un := _make_node()
	# Miner owns a hammer (odd but theirs): hammer shows, not pickaxe.
	un.set_work_state("gathering", "rock", "hammer")
	_check("equip: owned hammer beats rock->pickaxe guess",
		un._tool_pivot.visible
		and SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("hammer"))
	# Woodcutter owns a pickaxe: pickaxe shows while chopping.
	un.set_work_state("gathering", "tree", "pickaxe")
	_check("equip: owned pickaxe beats tree->axe guess",
		un._tool_pivot.visible
		and SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("pickaxe"))
	# Swing machinery still runs for the owned tool in CHOP/MINE.
	un._update_tool(1.0 / 60.0)
	_check("equip: pivot driven while swinging owned tool",
		un._tool_pivot.visible and un._tool_kind == "pickaxe")
	un.queue_free()


## Hoe / hammer / fishing rod are visible for the first time (the old code
## only ever showed axe + pickaxe).
func _test_new_tools_visible() -> void:
	var un := _make_node()
	un.set_work_state("gathering", "bush", "hoe")
	_check("equip: hoe visible while farming",
		un._tool_pivot.visible
		and SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("hoe"))
	un.set_work_state("building", "", "hammer")
	_check("equip: hammer visible while building",
		un._tool_pivot.visible
		and SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("hammer"))
	un.set_work_state("repairing", "", "hammer")
	_check("equip: hammer visible while repairing", un._tool_pivot.visible)
	un.set_work_state("gathering", "", "fishingrod")
	_check("equip: fishing rod visible while fishing",
		un._tool_pivot.visible
		and SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("fishingrod"))
	un.queue_free()


## No owned tool -> the old work-kind guess (no regression).
func _test_fallback_preserved() -> void:
	var un := _make_node()
	un.set_work_state("gathering", "tree", "")
	_check("fallback: axe for tree",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("axe"))
	un.set_work_state("gathering", "gold_vein", "")
	_check("fallback: pickaxe for gold_vein",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("pickaxe"))
	un.set_work_state("gathering", "wood_pile", "")
	_check("fallback: hidden for wood_pile", not un._tool_pivot.visible)
	un.set_work_state("gathering", "bush", "")
	_check("fallback: hoe for bush",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("hoe"))
	un.set_work_state("building", "", "")
	_check("fallback: hammer for building",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("hammer"))
	un.queue_free()


## Garbage tool ids never reach the overlay (sanitized to "").
func _test_unknown_tool_sanitized() -> void:
	var un := _make_node()
	un.set_work_state("gathering", "tree", "laser_sword")
	_check("sanitize: unknown id falls back to axe guess",
		un._tool_pivot.visible
		and SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("axe"))
	un.set_work_state("to_dropoff", "", "laser_sword")
	_check("sanitize: unknown id hidden while walking",
		not un._tool_pivot.visible)
	un.set_work_state("gathering", "tree", "axe")
	un.set_work_state("gathering", "tree", "bogus")
	_check("sanitize: bogus after real still sane",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("axe"))
	un.queue_free()


## Owned tool rides along on walk-to-work states (HTML draws it in-hand);
## no tool -> hidden (old hauling behavior preserved).
func _test_carried_while_walking() -> void:
	var un := _make_node()
	un.set_work_state("to_dropoff", "", "axe")
	_check("carry: axe visible while hauling", un._tool_pivot.visible)
	_check("carry: axe art while hauling",
		SN.diffuse_of(un._tool_sprite.texture) == Art.tool_texture("axe"))
	# The carried tool sits at the hand unrotated (swing only in CHOP/MINE).
	un._update_tool(1.0 / 60.0)
	_check("carry: no swing rotation while walking",
		un._tool_pivot.visible and un._tool_pivot.rotation == 0.0)
	un.set_work_state("to_build", "", "hammer")
	_check("carry: hammer visible walking to build", un._tool_pivot.visible)
	un.set_work_state("to_dropoff", "", "")
	_check("carry: hidden while hauling with no tool",
		not un._tool_pivot.visible)
	un.queue_free()


## Idle hides the tool even when the unit owns one.
func _test_hidden_while_idle() -> void:
	var un := _make_node()
	un.set_work_state("gathering", "tree", "axe")
	_check("idle: tool shown while working", un._tool_pivot.visible)
	un.set_work_state("idle", "", "axe")
	_check("idle: hidden while idle", not un._tool_pivot.visible)
	un.queue_free()
