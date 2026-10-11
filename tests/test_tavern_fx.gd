extends SceneTree
## Cursing Gnomes — tavern kitchen FX (graphics-hourly 2026-10-08,
## Jeremy's standing "everything smoothly animated" rule).
##
## The sprite-path taverns were the last still kitchens: the drawn perk
## eateries got vent FX on 2026-10-06 and houses got chimney smoke on
## 2026-10-07, but the inn/tavern sprites every town actually builds never
## breathed. Complete inns (living, bld_inn.png) and undead taverns
## (undead inn/hotel, bld_tavern_undead.png) now breathe steam/smoke from
## their baked chimney mouths on the shared quantized FX cadence (8 steps
## at 6/sec), pinned to the art through the real sprite render scale, and
## never run for blueprints or chimney-less buildings (living hotels use
## the bld_shop.png art). Undead taverns exhale the same sickly green as
## the wisps baked into their sprite art, drifting left with them.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tavern_fx.gd
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


func _make_node(btype: String, faction := "gnomes",
		complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes tavern kitchen FX tests ===")
	_test_roster()
	_test_art_key()
	_test_anchors()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: inns and hotels, and nothing else.
func _test_roster() -> void:
	_check("roster contains inn", "inn" in BuildingNode.TAVERN_FX_BTYPES)
	_check("roster contains hotel", "hotel" in BuildingNode.TAVERN_FX_BTYPES)
	_check("roster has exactly 2 types",
		BuildingNode.TAVERN_FX_BTYPES.size() == 2)
	for b in ["house", "farmhouse", "oil_pump", "town_hall", "windmill",
			"shop", "bathhouse"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.TAVERN_FX_BTYPES))
	# Chimney mouths sit in the upper half of each sprite file.
	for key in ["inn", "tavern_undead"]:
		var ap: Vector2 = BuildingNode.TAVERN_FX_CHIMNEY[key]
		var tsize: Vector2 = BuildingNode.TAVERN_FX_TEX.get(
			key, BuildingNode.TAVERN_FX_TEX["inn"])
		_check("%s chimney above art midpoint" % key,
			ap.y < tsize.y * 0.5)
		_check("%s chimney inside art width" % key,
			ap.x >= 0.0 and ap.x <= tsize.x)


## Art-key routing: living inns breathe, undead inn/hotel breathe the
## tavern art, living hotels (shop art) have no chimney.
func _test_art_key() -> void:
	_check("living inn key",
		BuildingNode.tavern_fx_art_key("inn", "gnomes") == "inn")
	_check("living inn key (elves)",
		BuildingNode.tavern_fx_art_key("inn", "elves") == "inn")
	_check("undead inn key",
		BuildingNode.tavern_fx_art_key("inn", "undead") == "tavern_undead")
	_check("undead hotel key",
		BuildingNode.tavern_fx_art_key("hotel", "undead") == "tavern_undead")
	_check("living hotel has no chimney",
		BuildingNode.tavern_fx_art_key("hotel", "gnomes") == "")
	_check("house has no tavern chimney",
		BuildingNode.tavern_fx_art_key("house", "undead") == "")
	_check("town hall has no tavern chimney",
		BuildingNode.tavern_fx_art_key("town_hall", "gnomes") == "")


## Anchors land on the art: the chimney mouth inside the sprite bounds,
## tracking the real render scale.
func _test_anchors() -> void:
	var n := _make_node("inn")
	_check("inn sprite loads", n._sprite != null)
	_check("fx method exists", n.has_method("_tavern_fx"))
	_check("anchor method exists", n.has_method("_tavern_fx_anchor"))
	var sc := n._sprite_sc
	# _size_for("inn") = 28.0 -> target_w 67.2 -> sc = 67.2/453 on the
	# 453x480 art. Chimney mouth art (140,12) ->
	# x (140-226.5)*sc, y (12-240)*sc - 0.48*480*sc.
	var vent := n._tavern_fx_anchor("inn")
	_check("inn vent x at chimney mouth",
		absf(vent.x - (140.0 - 226.5) * sc) < 0.6)
	_check("inn vent y at chimney mouth",
		absf(vent.y - ((12.0 - 240.0) * sc - 0.48 * 480.0 * sc)) < 0.6)
	# The vent must sit on the art, not float beside it: inside the
	# sprite's real rendered rect (derived from the node itself).
	var hw := 453.0 * sc * 0.5
	var top := n._sprite.position.y - 240.0 * sc
	var bot := n._sprite.position.y + 240.0 * sc
	_check("inn vent inside sprite bounds",
		absf(vent.x) <= hw and vent.y >= top and vent.y <= bot)
	n.free()
	var u := _make_node("inn", "undead")
	_check("undead tavern sprite loads", u._sprite != null)
	var us2 := u._sprite_sc
	var uvent := u._tavern_fx_anchor("tavern_undead")
	_check("undead vent differs from living vent", uvent != vent)
	_check("undead vent x at chimney mouth",
		absf(uvent.x - (140.0 - 226.5) * us2) < 0.6)
	_check("undead vent y at chimney mouth",
		absf(uvent.y - ((62.0 - 240.0) * us2 - 0.48 * 480.0 * us2)) < 0.6)
	var uhw := 453.0 * us2 * 0.5
	var utop := u._sprite.position.y - 240.0 * us2
	var ubot := u._sprite.position.y + 240.0 * us2
	_check("undead vent inside sprite bounds",
		absf(uvent.x) <= uhw and uvent.y >= utop and uvent.y <= ubot)
	u.free()
	var h := _make_node("hotel", "undead")
	_check("undead hotel sprite loads", h._sprite != null)
	h.free()
	# Living hotel (shop art, no chimney): _tavern_fx early-returns before
	# any draw call, so it is safe to call directly and must not arm FX.
	var lh := _make_node("hotel", "gnomes")
	_check("living hotel sprite loads", lh._sprite != null)
	lh._tavern_fx()
	_check("living hotel fx stays disarmed",
		lh._last_tavern_fx_tint == "")
	lh.free()
	# Unknown keys fall back to the living-inn anchors.
	var n2 := _make_node("inn")
	_check("unknown key falls back to inn anchors",
		n2._tavern_fx_anchor("bogus_key") == vent)
	n2.free()


## _process animates only complete chimney-bearing taverns: blueprints
## stay static and chimney-less buildings never touch the tavern FX step.
func _test_process_gates() -> void:
	var inn := _make_node("inn")
	inn._process(0.1)
	_check("complete inn advances fx step",
		inn._fx_step >= 0 and inn._fx_step < BuildingNode.EATERY_FX_STEPS)
	inn.free()
	var uinn := _make_node("inn", "undead")
	uinn._process(0.1)
	_check("complete undead tavern advances fx step",
		uinn._fx_step >= 0 and uinn._fx_step < BuildingNode.EATERY_FX_STEPS)
	uinn.free()
	var uhotel := _make_node("hotel", "undead")
	uhotel._process(0.1)
	_check("complete undead hotel advances fx step",
		uhotel._fx_step >= 0 and uhotel._fx_step < BuildingNode.EATERY_FX_STEPS)
	uhotel.free()
	var bp := _make_node("inn", "gnomes", false)
	bp._process(0.1)
	_check("blueprint inn stays static", bp._fx_step == -1)
	bp.free()
	var lhotel := _make_node("hotel", "gnomes")
	lhotel._process(0.1)
	# 2026-10-09: a living hotel now legitimately advances the step
	# through the SHOP storefront gate (its own family, not tavern —
	# the tavern router above still gives it no chimney key).
	_check("living hotel breathes via shop gate, not tavern",
		lhotel._fx_step >= 0
		and lhotel._fx_step < BuildingNode.EATERY_FX_STEPS
		and BuildingNode.tavern_fx_art_key("hotel", "gnomes") == "")
	lhotel.free()
	var house := _make_node("house")
	house._process(0.1)
	_check("house keeps its own fx step", house._fx_step >= 0)
	house.free()
