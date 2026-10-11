extends SceneTree
## Cursing Gnomes — oil pumpjack production FX (wake routine 2026-10-07,
## Jeremy's standing "everything smoothly animated" rule).
##
## The pumpjack is the game's ONLY oil source and AI towns run four of them;
## a static pumpjack reads as dead. Complete pumpjacks now exhale dark
## exhaust puffs from the engine stack (bld_oil_pump.png pixel 230,235) and
## shimmer an iridescent sheen on the wellhead puddle (pixel 540,380).
## FX is quantized to 8 steps at 6/sec (the eatery-vent precedent), pinned
## to the art through the real sprite render scale, and never runs for
## blueprints or other building types.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_oil_pump_fx.gd
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
	print("=== Cursing Gnomes oil-pumpjack FX tests ===")
	_test_step_formula()
	_test_sprite_scale_and_anchors()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The quantized step formula: 8 steps at 6/sec, wrapping.
func _test_step_formula() -> void:
	_check("step at t=0 is 0", BuildingNode.oil_pump_step_for(0.0) == 0)
	_check("step at t=1/6s is 1",
		BuildingNode.oil_pump_step_for(1.0 / 6.0) == 1)
	_check("step at t=2/6s is 2",
		BuildingNode.oil_pump_step_for(2.0 / 6.0) == 2)
	_check("steps stay in [0, 8)",
		BuildingNode.oil_pump_step_for(7.0 / 6.0) == 7)
	_check("step wraps after 8 steps",
		BuildingNode.oil_pump_step_for(8.0 / 6.0) == 0)


## The vent/puddle anchors land on the art: vent at the engine stack,
## puddle at the wellhead base, both inside the sprite bounds.
func _test_sprite_scale_and_anchors() -> void:
	var n := _make_node("oil_pump")
	_check("pumpjack sprite loads", n._sprite != null)
	# _size_for("oil_pump") defaults to 30.0 -> target_w 72 -> sc 0.1.
	_check("sprite scale is tracked", absf(n._sprite_sc - 0.1) < 0.001)
	var vent := n._oil_pump_anchor(BuildingNode.OIL_PUMP_VENT_PX)
	var puddle := n._oil_pump_anchor(BuildingNode.OIL_PUMP_PUDDLE_PX)
	_check("vent x at engine stack", absf(vent.x - (-13.0)) < 0.6)
	_check("vent y at engine stack", absf(vent.y - (-23.54)) < 0.6)
	_check("puddle x at wellhead base", absf(puddle.x - 18.0) < 0.6)
	_check("puddle y at wellhead base", absf(puddle.y - (-9.04)) < 0.6)
	# Sprite spans x [-36, 36], y ~[-47, 1] at this scale: FX must not float.
	_check("vent inside sprite bounds",
		absf(vent.x) <= 36.0 and vent.y >= -48.0 and vent.y <= 1.0)
	_check("puddle inside sprite bounds",
		absf(puddle.x) <= 36.0 and puddle.y >= -48.0 and puddle.y <= 1.0)
	_check("fx method exists", n.has_method("_oil_pump_fx"))
	n.free()


## _process animates only complete pumpjacks: blueprints stay static and
## other buildings never touch the pumpjack FX step.
func _test_process_gates() -> void:
	var pump := _make_node("oil_pump")
	pump._process(0.1)
	_check("complete pumpjack advances fx step",
		pump._fx_step >= 0 and pump._fx_step < BuildingNode.EATERY_FX_STEPS)
	pump.free()
	var bp := _make_node("oil_pump", false)
	bp._process(0.1)
	_check("pumpjack blueprint stays static", bp._fx_step == -1)
	bp.free()
	# 2026-10-07 graphics-hourly: houses now breathe chimney smoke on the
	# shared _fx_step cadence, so the "no FX at all" probe moved to
	# town_hall (banner only — never touches _fx_step). 2026-10-09
	# graphics-hourly: town_hall now breathes civic-seat FX, so the probe
	# moved to the well — documented dark (shop lane: wells reuse the shop
	# art but are NOT shops), in no FX roster.
	var hall := _make_node("well")
	hall._process(0.1)
	_check("other buildings skip pumpjack fx", hall._fx_step == -1)
	hall.free()
