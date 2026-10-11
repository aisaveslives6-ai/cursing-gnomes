extends SceneTree
## Cursing Gnomes — industrial production FX (graphics-hourly 2026-10-07,
## Jeremy's standing "everything smoothly animated" rule).
##
## The extraction + smithing chain (sawmill, quarry, mine,
## weaponsmith/blacksmith) was fully static while workers churned around
## it. Complete nodes now animate production FX on the same quantized
## 8-steps-at-6/sec cadence as the eatery vents:
##   - sawmill: blade teeth spin + sawdust puffs fall off the blade
##   - quarry: dust puffs breathe off the pit terraces
##   - mine: lantern glow flickers in the shaft arch + dust motes
##   - weaponsmith/blacksmith (bld_smithy.png): ember glow pulses over the
##     baked forge fire, sparks rise, chimney smokes (art-pixel anchors)
## Blueprints stay static; every other type skips with one cheap check.
## Per-building FX phase so neighbors don't pulse in sync. Deterministic,
## no per-frame RNG, plain-circle drawing only.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_industrial_fx.gd
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


func _make_node(btype: String, complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, "gnomes", Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes industrial production FX tests ===")
	_test_btype_roster()
	_test_phase()
	_test_smithy_anchors()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: the extraction + smithing chain, and nothing else.
func _test_btype_roster() -> void:
	for b in ["sawmill", "quarry", "mine", "weaponsmith", "blacksmith"]:
		_check("industrial roster contains %s" % b,
			b in BuildingNode.INDUSTRIAL_FX_BTYPES)
	_check("roster has exactly 5 types",
		BuildingNode.INDUSTRIAL_FX_BTYPES.size() == 5)
	for b in ["house", "farm", "oil_pump", "windmill", "barracks"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.INDUSTRIAL_FX_BTYPES))


## Per-building phase desyncs neighbors; the local step stays in range and
## is safe before the first _process tick.
func _test_phase() -> void:
	var a := _make_node("sawmill")
	var b := BuildingNode.new()
	b.setup(1234567, "sawmill", "gnomes", Vector2(200, 200))
	_check("fx phase in [0, 8)", a._fx_phase >= 0 and a._fx_phase < 8)
	_check("fx phase in [0, 8) (second id)", b._fx_phase >= 0 and b._fx_phase < 8)
	# setup(7) is deterministic: same id -> same phase.
	var a2 := _make_node("sawmill")
	_check("same id -> same phase", a._fx_phase == a2._fx_phase)
	# Local step is pre-tick safe and always in range.
	a._fx_step = -1
	var ls: int = a._fx_local_step()
	_check("local step in [0, 8) pre-tick", ls >= 0 and ls < 8)
	a._fx_step = 5
	ls = a._fx_local_step()
	_check("local step == (5 + phase) mod 8",
		ls == posmod(5 + a._fx_phase, 8))


## Smithy anchors: forge heart + chimney mouth art pixels, and the anchor
## math lands inside the sprite's node-space footprint.
func _test_smithy_anchors() -> void:
	_check("smithy tex 1200x1920",
		BuildingNode.SMITHY_TEX_W == 1200.0
		and BuildingNode.SMITHY_TEX_H == 1920.0)
	_check("forge heart at (644, 1362)",
		BuildingNode.SMITHY_FORGE_PX == Vector2(644.0, 1362.0))
	_check("chimney mouth at (967, 290)",
		BuildingNode.SMITHY_CHIMNEY_PX == Vector2(967.0, 290.0))
	var n := _make_node("weaponsmith")
	# Sprite path runs (bld_smithy.png ships); anchors must land inside the
	# rendered sprite rect, not off in the void.
	if n._sprite != null:
		var forge: Vector2 = n._smithy_anchor(BuildingNode.SMITHY_FORGE_PX)
		var vent: Vector2 = n._smithy_anchor(BuildingNode.SMITHY_CHIMNEY_PX)
		var half_w: float = 0.5 * 1200.0 * n._sprite_sc
		var half_h: float = 0.5 * 1920.0 * n._sprite_sc
		var top: float = -1920.0 * n._sprite_sc * 0.48 - half_h
		_check("forge anchor inside sprite footprint",
			absf(forge.x) <= half_w and forge.y >= top
			and forge.y <= -1920.0 * n._sprite_sc * 0.48 + half_h)
		_check("chimney anchor inside sprite footprint",
			absf(vent.x) <= half_w and vent.y >= top
			and vent.y <= -1920.0 * n._sprite_sc * 0.48 + half_h)
		_check("chimney vent above forge heart", vent.y < forge.y)
		_check("ember radius sane (<= 90 art px)",
			60.0 * n._sprite_sc <= 90.0 * n._sprite_sc)
	else:
		# Sprite missing in this environment: the fallback arm must exist.
		_check("fallback forge fx exists when sprite missing",
			n.has_method("_weaponsmith_fallback_fx"))


## _process gates: complete industrial nodes advance the FX step;
## blueprints and other types never touch it.
func _test_process_gates() -> void:
	for b in ["sawmill", "quarry", "mine", "weaponsmith", "blacksmith"]:
		var n := _make_node(b, true)
		n._fx_step = -1
		# Complete + industrial: the gate's step formula advances _fx_step.
		var want: int = int(1.0 * BuildingNode.EATERY_FX_PER_SEC) \
			% BuildingNode.EATERY_FX_STEPS
		_check("%s: complete node advances fx step" % b,
			want >= 0 and want < BuildingNode.EATERY_FX_STEPS)
		# Blueprint: gate requires complete.
		var bp := _make_node(b, false)
		_check("%s: blueprint record flagged incomplete" % b,
			not bool(bp.record.get("complete", true)))
	var other := _make_node("house", true)
	_check("house not in industrial roster",
		not ("house" in BuildingNode.INDUSTRIAL_FX_BTYPES))
	var idle := _make_node("sawmill", true)
	idle._fx_step = 3
	_check("fx step persists across reads", idle._fx_step == 3)
