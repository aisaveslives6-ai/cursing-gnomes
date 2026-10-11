extends SceneTree
## Cursing Gnomes — shop storefront FX (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## Shops were the last fully-static commercial family: the storefronts
## every town builds stood perfectly still. Complete shops now breathe
## lamplight on the shared quantized FX cadence (8 steps at 6/sec) —
## warm window-glow + winking coin glints for the living races,
## sickly-green window-glow + potion-stall wisps for the undead, and a
## warm pane-glow for the drawn living-shop arm. The lamplight flicker
## is a pure function (shop_flicker_for) so the math is pinned without
## rendering; anchors are verified against the sprite art they were
## measured from; _process gates keep blueprints dark, wells dark (they
## reuse the shop art but are not shops), and other buildings untouched.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_shop_fx.gd
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


func _make_node(btype: String, faction := "humans",
		complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes shop storefront FX tests ===")
	_test_roster()
	_test_art_keys()
	_test_anchors()
	_test_flicker()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: shops, seedshops, hotels, trade outposts — and
## nothing else (wells reuse the shop art but are not shops).
func _test_roster() -> void:
	for b in ["shop", "seedshop", "hotel", "trade_outpost"]:
		_check("roster contains %s" % b,
			b in BuildingNode.SHOP_FX_BTYPES)
	_check("roster has exactly 4 types",
		BuildingNode.SHOP_FX_BTYPES.size() == 4)
	for b in ["house", "well", "oil_pump", "town_hall", "windmill",
			"monastery", "inn", "mage_spire", "barracks", "sawmill",
			"weaponsmith", "guild_hall"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.SHOP_FX_BTYPES))


## Art-key routing: living shops use the drawn arm; undead shops take the
## bone-shop sprite; hotels/seedshops/trade outposts take the storefront
## sprite (undead hotels keep their tavern FX); wells and non-shops get
## no key at all.
func _test_art_keys() -> void:
	_check("living shop uses drawn arm", BuildingNode.shop_fx_art_key(
		"shop", "humans") == "shop_drawn")
	_check("elf shop uses drawn arm", BuildingNode.shop_fx_art_key(
		"shop", "elves") == "shop_drawn")
	_check("undead shop uses bone sprite", BuildingNode.shop_fx_art_key(
		"shop", "undead") == "shop_undead")
	_check("living hotel uses storefront", BuildingNode.shop_fx_art_key(
		"hotel", "humans") == "shop")
	_check("undead hotel keeps tavern FX", BuildingNode.shop_fx_art_key(
		"hotel", "undead") == "")
	_check("living seedshop uses storefront", BuildingNode.shop_fx_art_key(
		"seedshop", "gnomes") == "shop")
	_check("undead seedshop uses living storefront art",
		BuildingNode.shop_fx_art_key(
			"seedshop", "undead") == "shop")
	_check("living trade outpost uses storefront",
		BuildingNode.shop_fx_art_key(
			"trade_outpost", "ogres") == "shop")
	_check("undead trade outpost uses bone sprite",
		BuildingNode.shop_fx_art_key(
			"trade_outpost", "undead") == "shop_undead")
	_check("well stays dark", BuildingNode.shop_fx_art_key(
		"well", "humans") == "")
	_check("house gets no key", BuildingNode.shop_fx_art_key(
		"house", "humans") == "")
	_check("barracks gets no key", BuildingNode.shop_fx_art_key(
		"barracks", "humans") == "")
	# Test hook starts disarmed.
	var n := _make_node("shop")
	_check("fx hook starts disarmed", n._last_shop_fx == "")
	n.free()


## Anchors match the sprite art they were measured from: window centers
## in art px, both files 480x388. Anchor math is the _magespire_fx_anchor
## precedent (verified at sc = 1.0).
func _test_anchors() -> void:
	var tex: Dictionary = BuildingNode.SHOP_FX_TEX
	for key in ["shop", "shop_undead"]:
		var t: Vector2 = tex[key]
		_check("%s tex is 480x388" % key,
			absf(t.x - 480.0) < 0.01 and absf(t.y - 388.0) < 0.01)
	var wins: Dictionary = BuildingNode.SHOP_FX_WINDOWS
	var living: Array = wins["shop"]
	_check("living shop has 2 windows", living.size() == 2)
	_check("living left window (100,232)",
		living[0] == Vector2(100.0, 232.0))
	_check("living right window (295,255)",
		living[1] == Vector2(295.0, 255.0))
	var undead: Array = wins["shop_undead"]
	_check("undead shop has 3 windows", undead.size() == 3)
	_check("undead upper-left window (142,152)",
		undead[0] == Vector2(142.0, 152.0))
	_check("undead upper-right window (279,155)",
		undead[1] == Vector2(279.0, 155.0))
	_check("undead ground window (272,172)",
		undead[2] == Vector2(272.0, 172.0))
	_check("potion stall at (105,265)",
		BuildingNode.SHOP_FX_STALL == Vector2(105.0, 265.0))
	# Anchor math at unit scale: (ap.x - w/2, ap.y - h/2 - 0.48h).
	var n := _make_node("seedshop")
	n._sprite_sc = 1.0
	var a0: Vector2 = n._shop_fx_anchor("shop", 0)
	_check("living window-0 anchor x = -140.0", absf(a0.x - (-140.0)) < 0.01)
	_check("living window-0 anchor y = -148.24", absf(a0.y - (-148.24)) < 0.01)
	var u0: Vector2 = n._shop_fx_anchor("shop_undead", 0)
	_check("undead window-0 anchor x = -98.0", absf(u0.x - (-98.0)) < 0.01)
	_check("undead window-0 anchor y = -228.24", absf(u0.y - (-228.24)) < 0.01)
	# Clamp: out-of-range index pins to the last window.
	var u9: Vector2 = n._shop_fx_anchor("shop_undead", 9)
	var u2: Vector2 = n._shop_fx_anchor("shop_undead", 2)
	_check("anchor index clamps", u9 == u2)
	n.free()
	# Every sprite art key has a tint.
	var tints: Dictionary = BuildingNode.SHOP_FX_TINT
	for key in ["shop", "shop_undead"]:
		_check("%s has tint" % key, tints.has(key))


## The flicker is lamplight: bounded 0.64..1.0, varies with the step, and
## the phase shifts the wave (per-building offsets desync shops).
func _test_flicker() -> void:
	var lo := 2.0
	var hi := -1.0
	var seen := {}
	for s in range(BuildingNode.EATERY_FX_STEPS):
		for p in [0.0, 1.4, 2.8, 4.2]:
			var f := BuildingNode.shop_flicker_for(s, p)
			lo = minf(lo, f)
			hi = maxf(hi, f)
			seen[f] = true
	_check("flicker lower bound 0.64", lo >= 0.64 - 0.001)
	_check("flicker upper bound 1.0", hi <= 1.0 + 0.001)
	_check("flicker varies across steps", seen.size() > 4)
	_check("phase 0 vs 1.4 differ at step 0",
		absf(BuildingNode.shop_flicker_for(0, 0.0)
			- BuildingNode.shop_flicker_for(0, 1.4)) > 0.01)
	# Full-cycle determinism: same step+phase always gives the same value.
	_check("flicker deterministic",
		BuildingNode.shop_flicker_for(5, 2.8)
			== BuildingNode.shop_flicker_for(5, 2.8))


## _process animates only complete shops: blueprints stay dark, wells stay
## dark, and other buildings never touch the shop FX step.
func _test_process_gates() -> void:
	var shop := _make_node("shop")
	shop._process(0.1)
	_check("complete shop advances fx step",
		shop._fx_step >= 0 and shop._fx_step < BuildingNode.EATERY_FX_STEPS)
	shop.free()
	var bp := _make_node("shop", "humans", false)
	bp._process(0.1)
	_check("blueprint shop stays static", bp._fx_step == -1)
	bp.free()
	var undead := _make_node("shop", "undead")
	undead._process(0.1)
	_check("undead shop advances fx step",
		undead._fx_step >= 0
		and undead._fx_step < BuildingNode.EATERY_FX_STEPS)
	undead.free()
	var hotel := _make_node("hotel")
	hotel._process(0.1)
	_check("complete hotel advances fx step",
		hotel._fx_step >= 0
		and hotel._fx_step < BuildingNode.EATERY_FX_STEPS)
	hotel.free()
	var well := _make_node("well")
	well._process(0.1)
	_check("well stays dark (no fx gate)", well._fx_step == -1)
	well.free()
	var house := _make_node("house")
	house._process(0.1)
	_check("house keeps its own fx step (shop gate untouched)",
		house._fx_step >= 0)
	house.free()
