extends SceneTree
## Cursing Gnomes — stockpile depot FX (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## Storage is the AI's #2 most-built building (every faction raises 1-3
## depots) and every depot stood perfectly still. The six stockpile btypes
## (storage + stock_gold/wood/food/oil/seeds) draw real sprite art -
## per-faction general-store art for storage, bld_shop.png /
## bld_shop_undead.png for the stock_* types - with zero ambient FX.
## Complete depots now breathe on the shared quantized FX cadence
## (8 steps at 6/sec - the shop/restaurant precedent): dust kicks up at
## the loading door as crates shift (cold ash for the undead), hearth
## smoke rises off the chimney (human/gnome stores + shop sprite only),
## and the door lantern breathes warm light (human/ogre only).
## Blueprints stay dark. Anchors measured off the real sprites.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_stockpile_fx.gd
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


func _make_node(btype: String, faction := "gnomes", complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes stockpile depot FX tests ===")
	_test_roster()
	_test_art_keys()
	_test_anchors()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: storage + the five stock_* types. The shop keeps its
## own FX arm; clinic/tome_library/gov_* are deliberately excluded (a
## glowing clinic misreads - the civic FX comment's standing rule).
func _test_roster() -> void:
	for b in ["storage", "stock_gold", "stock_wood", "stock_food",
			"stock_oil", "stock_seeds"]:
		_check("roster contains %s" % b, b in BuildingNode.STOCKPILE_FX_BTYPES)
	_check("roster has exactly 6 types",
		BuildingNode.STOCKPILE_FX_BTYPES.size() == 6)
	for b in ["shop", "seedshop", "trade_outpost", "house", "farmhouse",
			"farm", "flesh_farm", "restaurant", "soul_cafe", "inn",
			"hotel", "town_hall", "hall", "courthouse", "clinic",
			"tome_library", "gov_office", "oil_pump", "lumber_camp",
			"sawmill", "mine", "quarry", "barracks", "wall", "barn"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.STOCKPILE_FX_BTYPES))


## Art keys: storage takes the per-faction general-store art; stock_*
## takes bld_shop.png (bld_shop_undead.png for the undead); everything
## else gets no key.
func _test_art_keys() -> void:
	_check("storage gnomes -> store_gnome",
		BuildingNode.stockpile_fx_art_key("storage", "gnomes") == "store_gnome")
	_check("storage ogres -> store_ogre",
		BuildingNode.stockpile_fx_art_key("storage", "ogres") == "store_ogre")
	_check("storage elves -> store_elf",
		BuildingNode.stockpile_fx_art_key("storage", "elves") == "store_elf")
	_check("storage humans -> store_human",
		BuildingNode.stockpile_fx_art_key("storage", "humans") == "store_human")
	_check("storage undead -> store_undead",
		BuildingNode.stockpile_fx_art_key("storage", "undead") == "store_undead")
	for b in ["stock_gold", "stock_wood", "stock_food", "stock_oil",
			"stock_seeds"]:
		_check("%s living -> shop" % b,
			BuildingNode.stockpile_fx_art_key(b, "humans") == "shop")
		_check("%s undead -> shop_undead" % b,
			BuildingNode.stockpile_fx_art_key(b, "undead") == "shop_undead")
	for b in ["shop", "house", "farm", "town_hall", "clinic", "barn",
			"lumber_camp", "oil_pump"]:
		_check("no key for %s" % b,
			BuildingNode.stockpile_fx_art_key(b, "gnomes") == "")
	# Sprite sizes: living storefronts 480x320, shop art 480x388.
	_check("store_human tex 480x320",
		BuildingNode.STOCKPILE_FX_TEX["store_human"] == Vector2(480.0, 320.0))
	_check("shop tex 480x388",
		BuildingNode.STOCKPILE_FX_TEX["shop"] == Vector2(480.0, 388.0))
	_check("shop_undead tex 480x388",
		BuildingNode.STOCKPILE_FX_TEX["shop_undead"] == Vector2(480.0, 388.0))
	# Anchor spot values (art px, measured off the real sprites).
	_check("human door (242,308)",
		BuildingNode.STOCKPILE_FX_DOOR["store_human"] == Vector2(242.0, 308.0))
	_check("ogre door (240,300)",
		BuildingNode.STOCKPILE_FX_DOOR["store_ogre"] == Vector2(240.0, 300.0))
	_check("undead door (300,340)",
		BuildingNode.STOCKPILE_FX_DOOR["store_undead"] == Vector2(300.0, 340.0))
	_check("shop door (190,285)",
		BuildingNode.STOCKPILE_FX_DOOR["shop"] == Vector2(190.0, 285.0))
	_check("human vent (125,14)",
		BuildingNode.STOCKPILE_FX_VENT["store_human"] == Vector2(125.0, 14.0))
	_check("shop vent (98,24)",
		BuildingNode.STOCKPILE_FX_VENT["shop"] == Vector2(98.0, 24.0))
	_check("elf has no chimney vent",
		not BuildingNode.STOCKPILE_FX_VENT.has("store_elf"))
	_check("ogre has no chimney vent",
		not BuildingNode.STOCKPILE_FX_VENT.has("store_ogre"))
	_check("undead has no chimney vent",
		not BuildingNode.STOCKPILE_FX_VENT.has("store_undead"))
	_check("human lantern (300,190)",
		BuildingNode.STOCKPILE_FX_LANTERN["store_human"] == Vector2(300.0, 190.0))
	_check("ogre lantern (64,198)",
		BuildingNode.STOCKPILE_FX_LANTERN["store_ogre"] == Vector2(64.0, 198.0))
	_check("gnome has no lantern",
		not BuildingNode.STOCKPILE_FX_LANTERN.has("store_gnome"))
	_check("elf has no lantern",
		not BuildingNode.STOCKPILE_FX_LANTERN.has("store_elf"))
	# Tints.
	_check("dust tint warm gray",
		BuildingNode.STOCKPILE_DUST_TINT == Color(0.72, 0.68, 0.60))
	_check("ash tint cold",
		BuildingNode.STOCKPILE_ASH_TINT == Color(0.55, 0.60, 0.55))


## Anchors: art->node conversion tracks the real render scale; every
## emitter sits above the ground line over the art (nothing floats,
## nothing buried).
func _test_anchors() -> void:
	var n := _make_node("storage", "humans")
	n._sprite_sc = 1.0
	# human door: (242-240, (308-160) - 0.48*320) = (2.0, -5.6)
	var door: Vector2 = n._stockpile_fx_anchor(
		BuildingNode.STOCKPILE_FX_DOOR["store_human"], "store_human")
	_check("human door node (2.0,-5.6)",
		absf(door.x - 2.0) < 0.01 and absf(door.y - (-5.6)) < 0.01)
	# human vent: (125-240, (14-160) - 153.6) = (-115.0, -299.6)
	var vent: Vector2 = n._stockpile_fx_anchor(
		BuildingNode.STOCKPILE_FX_VENT["store_human"], "store_human")
	_check("human vent node (-115.0,-299.6)",
		absf(vent.x - (-115.0)) < 0.01 and absf(vent.y - (-299.6)) < 0.01)
	# human lantern: (300-240, (190-160) - 153.6) = (60.0, -123.6)
	var lamp: Vector2 = n._stockpile_fx_anchor(
		BuildingNode.STOCKPILE_FX_LANTERN["store_human"], "store_human")
	_check("human lantern node (60.0,-123.6)",
		absf(lamp.x - 60.0) < 0.01 and absf(lamp.y - (-123.6)) < 0.01)
	# shop door on the 480x388 art: (190-240, (285-194) - 186.24)
	var sdoor: Vector2 = n._stockpile_fx_anchor(
		BuildingNode.STOCKPILE_FX_DOOR["shop"], "shop")
	_check("shop door node (-50.0,-95.24)",
		absf(sdoor.x - (-50.0)) < 0.01 and absf(sdoor.y - (-95.24)) < 0.01)
	# undead door: (300-240, (340-194) - 186.24) = (60.0, -40.24)
	var udoor: Vector2 = n._stockpile_fx_anchor(
		BuildingNode.STOCKPILE_FX_DOOR["store_undead"], "store_undead")
	_check("undead door node (60.0,-40.24)",
		absf(udoor.x - 60.0) < 0.01 and absf(udoor.y - (-40.24)) < 0.01)
	for v in [door, vent, lamp, sdoor, udoor]:
		_check("emitter above base", v.y < 0.0)
	# Scaling tracks _sprite_sc linearly (the restaurant precedent).
	n._sprite_sc = 2.0
	var door2: Vector2 = n._stockpile_fx_anchor(
		BuildingNode.STOCKPILE_FX_DOOR["store_human"], "store_human")
	_check("door scales 2x",
		absf(door2.x - 2.0 * door.x) < 0.01
		and absf(door2.y - 2.0 * door.y) < 0.01)
	n.free()


## The _process gate: complete depots advance the FX step on the shared
## cadence; blueprints stay static; the shop keeps its own gate.
func _test_process_gates() -> void:
	var st := _make_node("storage", "humans")
	st._process(0.1)
	_check("complete storage advances fx step",
		st._fx_step >= 0 and st._fx_step < BuildingNode.EATERY_FX_STEPS)
	st.free()
	var bp := _make_node("storage", "humans", false)
	bp._process(0.1)
	_check("storage blueprint stays static", bp._fx_step == -1)
	bp.free()
	var sg := _make_node("stock_gold", "undead")
	sg._process(0.1)
	_check("complete undead stock_gold advances fx step",
		sg._fx_step >= 0 and sg._fx_step < BuildingNode.EATERY_FX_STEPS)
	sg.free()
	var shop := _make_node("shop", "humans")
	shop._process(0.1)
	_check("shop keeps its own gate, not the stockpile one",
		shop._fx_step >= 0 and shop._fx_step < BuildingNode.EATERY_FX_STEPS)
	shop.free()
	# The draw hook starts disarmed.
	var n := _make_node("storage", "ogres")
	_check("fx hook starts disarmed", n._last_stockpile_fx == "")
	n.free()
