extends SceneTree
## Cursing Gnomes — resource-building art tests (graphics-hourly 2026-10-04).
##
## Sawmill, quarry, and mine used to share one generic box+hole silhouette.
## Each now gets its own drawn art (saw blade + log pile / terraced pit +
## derrick / timber shaft entrance + ore heap), and _draw dispatches to the
## right arm. _draw runs headlessly (verified: NOTIFICATION_DRAW fires with
## the dummy renderer), so the _last_art hook pins the dispatch contract:
## a future edit cannot silently collapse the three back into one arm.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_resource_building_art.gd
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


func _make_node(btype: String, complete := true, faction := "gnomes") -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	root.add_child(n)
	return n


## Adds the node, lets _draw run, returns the art arm it used.
func _drawn_art(n: BuildingNode) -> String:
	n.queue_redraw()
	await process_frame
	await process_frame
	var art: String = n._last_art
	n.free()
	return art


func _initialize() -> void:
	print("=== Cursing Gnomes resource-building art tests ===")
	await _test_dispatch()
	_test_programmer_art_path()
	_test_sizes()
	_test_incomplete_blueprint_no_art()
	await _test_farm_dock_spire()
	await _test_fire_station()
	await _test_well()
	await _test_civic_art()
	await _test_bathhouse_guard_warhut()
	await _test_bathhouse_undead_art()
	await _test_undead_tavern_art()
	await _test_undead_house_barracks_art()
	await _test_aa_tower()
	await _test_nuke_silo()
	await _test_medic_camp_foundry_library_armory()
	await _test_weaponsmith_range_depot_inn()
	await _test_farmhouse()
	await _test_fence()
	await _test_necropolis()
	await _test_eatery_art()
	await _test_perk_eatery_art()
	await _test_repair_shop_art()
	await _test_eatery_fx()
	await _test_townhall_alias_art()
	await _test_tent_smithy_art()
	await _test_store_gov_trade_art()
	await _test_pier_shop_seedshop_garden()
	await _test_undead_shop_art()
	await _test_spire_guardhouse_art()
	await _test_bridge_art()
	await _test_air_defense_art()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for fl: String in _failures:
		print("  FAIL: ", fl)
	quit(1 if _failed > 0 else 0)


## Wake routine 2026-10-04: fix79's bldMageSpireSprite64() and
## bldGuardHouseSprite61() ports — real per-race pixel art for the two
## military HQ types. Verbatim fallbacks: undead mage_spire -> bld_tower,
## undead guard_house -> drawn _guard_house arm (HTML fallback key has no art).
func _test_spire_guardhouse_art() -> void:
	_check("mage_spire base art is bld_tower.png (HTML fallback verbatim)",
		String(Art.BUILDING_ART.get("mage_spire", "")) == "bld_tower.png")
	var spire_files := {
		"humans": "bld_mage_spire_human.png",
		"ogres": "bld_mage_spire_ogre.png",
		"elves": "bld_mage_spire_elf.png",
		"gnomes": "bld_mage_spire_gnome.png",
	}
	var guard_files := {
		"humans": "bld_guard_house_human.png",
		"ogres": "bld_guard_house_ogre.png",
		"elves": "bld_guard_house_elf.png",
		"gnomes": "bld_guard_house_gnome.png",
	}
	for f: String in spire_files.keys():
		_check("%s mage_spire maps to %s" % [f, spire_files[f]],
			String(Art.BUILDING_ART_FACTION.get("mage_spire", {}).get(f, "")) == spire_files[f])
		_check("%s mage_spire texture resolves" % f,
			Art.building_texture_for("mage_spire", f) != null)
		_check("%s guard_house maps to %s" % [f, guard_files[f]],
			String(Art.BUILDING_ART_FACTION.get("guard_house", {}).get(f, "")) == guard_files[f])
		_check("%s guard_house texture resolves" % f,
			Art.building_texture_for("guard_house", f) != null)
		_check("%s mage_spire node takes sprite path (no programmer-art arm)" % f,
			await _drawn_art(_make_node("mage_spire", true, f)) == "")
		_check("%s guard_house node takes sprite path (no programmer-art arm)" % f,
			await _drawn_art(_make_node("guard_house", true, f)) == "")
	# Undead fallbacks verbatim from the HTML routers.
	_check("undead has no per-race mage_spire key",
		not Art.BUILDING_ART_FACTION.get("mage_spire", {}).has("undead"))
	_check("undead mage_spire texture resolves via bld_tower fallback",
		Art.building_texture_for("mage_spire", "undead") != null)
	_check("undead mage_spire node takes sprite path with tower art",
		_make_node("mage_spire", true, "undead")._sprite != null)
	_check("undead guard_house has no sprite art (HTML fallback key missing)",
		Art.building_texture_for("guard_house", "undead") == null)
	_check("undead guard_house keeps the drawn arm",
		await _drawn_art(_make_node("guard_house", true, "undead")) == "guard_house")
	_check("mage_spire size still 48",
		_make_node("mage_spire")._size_for("mage_spire") == 48.0)
	_check("guard_house size still 30",
		_make_node("guard_house")._size_for("guard_house") == 30.0)


## Each resource building draws its own silhouette arm.
func _test_dispatch() -> void:
	for btype: String in ["sawmill", "quarry", "mine"]:
		_check("draw dispatches %s to its own arm" % btype,
			await _drawn_art(_make_node(btype)) == btype)
	_check("draw dispatches farm to farm arm",
		await _drawn_art(_make_node("farm")) == "farm")
	# Wake routine 2026-10-04: windmill now has real art (bld_windmill,
	# ported verbatim from fix79's AGRI62_BLD_B64) — sprite path, so no
	# programmer-art arm fires, exactly like house.
	_check("windmill uses real sprite art (no programmer-art arm)",
		await _drawn_art(_make_node("windmill")) == "")
	_check("windmill texture maps to bld_windmill.png",
		Art.building_texture_for("windmill", "gnomes") != null)
	_check("unknown type falls back to generic arm",
		await _drawn_art(_make_node("granary")) == "generic")
	_check("sprite building (house) uses no programmer-art arm",
		await _drawn_art(_make_node("house")) == "")


## The three types still take the programmer-art path (no source sprite).
func _test_programmer_art_path() -> void:
	for btype: String in ["sawmill", "quarry", "mine"]:
		_check("%s has no source sprite art" % btype,
			Art.building_texture_for(btype, "gnomes") == null)
		var n := _make_node(btype)
		_check("%s node takes programmer-art path" % btype, n._sprite == null)
		n.free()


## Footprint sizes unchanged (shadow/door/glow math untouched).
func _test_sizes() -> void:
	var n := _make_node("sawmill")
	for btype: String in ["sawmill", "quarry", "mine"]:
		_check("%s size still 32" % btype, n._size_for(btype) == 32.0)
	n.free()


## Incomplete blueprints draw the scaffold, not the finished art.
func _test_incomplete_blueprint_no_art() -> void:
	_check("incomplete sawmill blueprint sets no art arm",
		await _drawn_art(_make_node("sawmill", false)) == "")
	_check("incomplete fishing_dock blueprint sets no art arm",
		await _drawn_art(_make_node("fishing_dock", false)) == "")


## Farm, fishing dock, and mage spire used to share plain box/roof silhouettes
## (the dock was two flat rects). Each now gets its own drawn art — farmhouse
## + crop rows, pier on posts over water with a moored boat, tapering tower
## with an arcane crystal — and _draw dispatches to the right arm. Same
## _last_art hook contract as the sawmill/quarry/mine set.
func _test_farm_dock_spire() -> void:
	# Wake routine 2026-10-04: mage_spire moved to the spire/guard-house
	# art test below (fix79 bldMageSpireSprite64 port) — it no longer takes
	# the programmer-art path.
	for btype: String in ["farm", "fishing_dock"]:
		_check("draw dispatches %s to its own arm" % btype,
			await _drawn_art(_make_node(btype)) == btype)
		_check("%s has no source sprite art" % btype,
			Art.building_texture_for(btype, "gnomes") == null)
		var n := _make_node(btype)
		_check("%s node takes programmer-art path" % btype, n._sprite == null)
		n.free()
	var n2 := _make_node("farm")
	_check("farm size still 40", n2._size_for("farm") == 40.0)
	_check("fishing_dock size still 30", n2._size_for("fishing_dock") == 30.0)
	_check("mage_spire size still 48", n2._size_for("mage_spire") == 48.0)
	n2.free()


## Fire station used to draw a generic box with a red stripe — "just a
## house" — then got its own drawn arm. The 2026-10-04 building-art audit
## extracted real sprite art (bld_fire_station.png), so it now takes the
## sprite path: no programmer-art arm, texture resolves.
func _test_fire_station() -> void:
	_check("fire_station resolves to sprite art",
		Art.building_texture_for("fire_station", "gnomes") != null)
	var n := _make_node("fire_station")
	_check("fire_station node takes sprite path", n._sprite != null)
	_check("fire_station size still 38", n._size_for("fire_station") == 38.0)
	n.free()
	_check("fire_station uses no programmer-art arm",
		await _drawn_art(_make_node("fire_station")) == "")
	_check("incomplete fire_station blueprint sets no art arm",
		await _drawn_art(_make_node("fire_station", false)) == "")
	await _test_stock_shop_art()


## Stockpiles and storage used to draw the generic house-box silhouette.
## fix79's BLD_SPRITE_FOR maps all six to bld_shop (bld_shop_undead for the
## undead race), and both arts were already extracted — the port just never
## mapped them. Sprite path now: no programmer-art arm, texture resolves,
## undead faction gets the undead variant, sizes unchanged.
func _test_stock_shop_art() -> void:
	var types: Array[String] = ["storage", "stock_gold", "stock_wood",
		"stock_food", "stock_oil", "stock_seeds"]
	for btype: String in types:
		_check("%s resolves to shop sprite art" % btype,
			Art.building_texture_for(btype, "gnomes") != null)
		_check("%s resolves to undead shop art for undead" % btype,
			Art.building_texture_for(btype, "undead") != null)
		_check("%s gnomes and undead arts differ" % btype,
			Art.building_texture_for(btype, "gnomes")
			!= Art.building_texture_for(btype, "undead"))
		var n := _make_node(btype)
		_check("%s node takes sprite path" % btype, n._sprite != null)
		n.free()
		_check("%s uses no programmer-art arm" % btype,
			await _drawn_art(_make_node(btype)) == "")
		var nu := _make_node(btype, true, "undead")
		_check("%s undead node takes sprite path" % btype, nu._sprite != null)
		nu.free()
	var n2 := _make_node("stock_gold")
	_check("stockpile size still 30", n2._size_for("stock_gold") == 30.0)
	_check("storage size still 30", n2._size_for("storage") == 30.0)
	n2.free()
	_check("incomplete stock_gold blueprint sets no art arm",
		await _drawn_art(_make_node("stock_gold", false)) == "")


## Wake routine 2026-10-05 (launch-readiness graphics pass): fix79's
## BLD_SPRITE_FOR patch assigns well -> bld_shop (verbatim, the same patch
## that maps seedshop -> bld_shop), so the well takes the sprite path now.
## The drawn _well() arm stays as missing-art fallback only.
func _test_well() -> void:
	_check("well maps to bld_shop.png (fix79 patch)",
		Art.BUILDING_ART.get("well", "") == "bld_shop.png")
	_check("well texture resolves for gnomes",
		Art.building_texture_for("well", "gnomes") != null)
	_check("draw dispatches well to the sprite path (no drawn arm)",
		await _drawn_art(_make_node("well")) == "")
	var n := _make_node("well")
	_check("well node takes sprite path", n._sprite != null)
	_check("well size still 20", n._size_for("well") == 20.0)
	n.free()
	_check("incomplete well blueprint sets no art arm",
		await _drawn_art(_make_node("well", false)) == "")


## Wake routine 2026-10-04: the six civic offices (gov_office, gov_treasury,
## gov_war_office, gov_justice, tome_library, clinic) used to draw
## programmer-art silhouettes, but fix79's BLD_SPRITE_FOR maps them all to
## bld_civic (bld_office_undead for the undead race via bldHouseUndead68) —
## the same real pixel art courthouse already uses. The drawn _clinic() /
## _tome_library() arms stay as missing-art fallback only.
func _test_civic_art() -> void:
	var civic := ["gov_office", "gov_treasury", "gov_war_office",
		"gov_justice", "tome_library", "clinic"]
	var factions := ["humans", "ogres", "elves", "gnomes", "undead"]
	for t in civic:
		_check("civic %s maps to bld_civic" % t,
			String(Art.BUILDING_ART.get(t, "")) == "bld_civic.png")
		_check("civic %s undead variant maps to bld_office_undead" % t,
			String((Art.BUILDING_ART_FACTION.get(t, {}) as Dictionary).get("undead", "")) == "bld_office_undead.png")
		for f in factions:
			_check("civic %s texture resolves for %s" % [t, f],
				Art.building_texture_for(t, f) != null)
	_check("civic art distinguishes undead variant",
		Art.building_texture_for("gov_office", "undead")
		!= Art.building_texture_for("gov_office", "gnomes"))
	for t in civic:
		var n := _make_node(t)
		_check("civic %s node takes sprite path" % t, n._sprite != null)
		_check("civic %s draws no programmer-art arm" % t,
			await _drawn_art(_make_node(t)) == "")
		n.free()
	var c1 := _make_node("clinic")
	var c2 := _make_node("gov_office")
	var c3 := _make_node("tome_library")
	_check("civic sizes unchanged (clinic 32, others default 30)",
		c1._size_for("clinic") == 32.0
		and c2._size_for("gov_office") == 30.0
		and c3._size_for("tome_library") == 30.0)
	c1.free()
	c2.free()
	c3.free()
	_check("incomplete clinic blueprint sets no art arm",
		await _drawn_art(_make_node("clinic", false)) == "")
	_check("incomplete gov_office blueprint sets no art arm",
		await _drawn_art(_make_node("gov_office", false)) == "")


## Wake routine 2026-10-05 (launch-readiness graphics pass): fix79's
## BLD_SPRITE_FOR maps bathhouse -> bld_civic and war_hut -> bld_barracks
## (verbatim, extracted from fix79/index.html), so both take the sprite
## path now. The drawn _bathhouse() / _war_hut() arms stay as missing-art
## fallback only. Sizes unchanged (bathhouse 32, war_hut 48).
func _test_bathhouse_guard_warhut() -> void:
	# Wake routine 2026-10-04: guard_house moved to the spire/guard-house
	# art test below (fix79 bldGuardHouseSprite61 port) — living races no
	# longer take the programmer-art path.
	for spec: Array in [
		["bathhouse", "bld_civic.png", 32.0],
		["war_hut", "bld_barracks.png", 48.0],
	]:
		var bt: String = spec[0]
		var png: String = spec[1]
		var size: float = spec[2]
		_check("%s maps to %s (fix79 BLD_SPRITE_FOR)" % [bt, png],
			Art.BUILDING_ART.get(bt, "") == png)
		_check("%s texture resolves for gnomes" % bt,
			Art.building_texture_for(bt, "gnomes") != null)
		_check("draw dispatches %s to the sprite path (no drawn arm)" % bt,
			await _drawn_art(_make_node(bt)) == "")
		var n := _make_node(bt)
		_check("%s node takes sprite path" % bt, n._sprite != null)
		_check("%s size still %d" % [bt, int(size)],
			n._size_for(bt) == size)
		n.free()
		_check("incomplete %s blueprint sets no art arm" % bt,
			await _drawn_art(_make_node(bt, false)) == "")


## fix79's bldHouseUndead68() reroutes UNDEAD bathhouse -> bld_office_undead
## (verbatim, same clause as the civic offices). Wake routine 2026-10-05:
## living races now take fix79's base BLD_SPRITE_FOR mapping (bathhouse ->
## bld_civic) — the drawn _bathhouse arm is missing-art fallback only.
## hotel/inn are deliberately NOT part of the undead route here — the same
## C70 clause sends undead tavern/inn/hotel -> bld_tavern_undead (pinned in
## _test_undead_tavern_art below).
func _test_bathhouse_undead_art() -> void:
	for r: String in ["gnomes", "ogres", "elves", "humans"]:
		_check("living %s bathhouse maps to bld_civic (fix79 base)" % r,
			Art.building_texture_for("bathhouse", r) != null)
		var n := _make_node("bathhouse", true, r)
		_check("living %s bathhouse node takes sprite path" % r,
			n._sprite != null)
		_check("living %s bathhouse draws no programmer-art arm" % r,
			await _drawn_art(n) == "")
	# _drawn_art frees its node, so make a fresh one for the size pin.
	var s := _make_node("bathhouse", true, "gnomes")
	_check("bathhouse size still 32", s._size_for("bathhouse") == 32.0)
	s.free()
	# Undead: sprite path, the same bld_office_undead as the civic offices.
	var u := Art.building_texture_for("bathhouse", "undead")
	_check("undead bathhouse texture resolves", u != null)
	_check("undead bathhouse uses bld_office_undead (same as clinic)",
		u == Art.building_texture_for("clinic", "undead"))
	var un := _make_node("bathhouse", true, "undead")
	_check("undead bathhouse node takes sprite path", un._sprite != null)
	_check("undead bathhouse draws no programmer-art arm",
		await _drawn_art(un) == "")
	_check("incomplete undead bathhouse blueprint sets no art arm",
		await _drawn_art(_make_node("bathhouse", false, "undead")) == "")


## fix79's bldHouseUndead68() routes undead tavern/inn/hotel ->
## bld_tavern_undead (verbatim, same C70 clause as the shops and civic
## offices). The port has no 'tavern' btype, so hotel + inn take the
## mapping. Wake routine 2026-10-05: living races now take fix79's base
## BLD_SPRITE_FOR mappings (hotel -> bld_shop, inn -> bld_inn) — the drawn
## _bathhouse arm is missing-art fallback only.
func _test_undead_tavern_art() -> void:
	var living := {"hotel": "bld_shop.png", "inn": "bld_inn.png"}
	for r: String in ["gnomes", "ogres", "elves", "humans"]:
		for hr: String in ["hotel", "inn"]:
			_check("living %s %s maps to %s (fix79 base)" % [r, hr, living[hr]],
				Art.BUILDING_ART.get(hr, "") == living[hr])
			_check("living %s %s texture resolves" % [r, hr],
				Art.building_texture_for(hr, r) != null)
			var ln := _make_node(hr, true, r)
			_check("living %s %s node takes sprite path" % [r, hr],
				ln._sprite != null)
			_check("living %s %s draws no programmer-art arm" % [r, hr],
				await _drawn_art(ln) == "")
	# Undead: sprite path, bld_tavern_undead — NOT the civic bld_office_undead.
	var u := Art.building_texture_for("hotel", "undead")
	_check("undead hotel texture resolves", u != null)
	_check("undead inn texture resolves",
		Art.building_texture_for("inn", "undead") != null)
	_check("undead hotel and inn share the tavern sprite",
		u == Art.building_texture_for("inn", "undead"))
	_check("undead hotel not routed to bld_office_undead",
		u != Art.building_texture_for("clinic", "undead"))
	var un := _make_node("hotel", true, "undead")
	_check("undead hotel node takes sprite path", un._sprite != null)
	_check("undead hotel draws no programmer-art arm",
		await _drawn_art(un) == "")
	var ui := _make_node("inn", true, "undead")
	_check("undead inn node takes sprite path", ui._sprite != null)
	_check("undead inn draws no programmer-art arm",
		await _drawn_art(ui) == "")
	_check("incomplete undead inn blueprint sets no art arm",
		await _drawn_art(_make_node("inn", false, "undead")) == "")


## Graphics-hourly 2026-10-04: the last two parked bldHouseUndead68
## clauses. Undead houses (house -> bld_house_undead) and the whole undead
## military family (barracks, war_hut, cannon_foundry, armory,
## vehicle_depot -> bld_barracks_undead), verbatim from the HTML. Living
## races keep their current art: house/barracks keep their base sprites;
## wake 2026-10-05 maps war_hut/cannon_foundry/armory/vehicle_depot to
## bld_barracks via fix79's base BLD_SPRITE_FOR (their drawn arms are
## missing-art fallback only).
func _test_undead_house_barracks_art() -> void:
	var military := ["barracks", "war_hut", "cannon_foundry", "armory",
		"vehicle_depot"]
	for r: String in ["gnomes", "ogres", "elves", "humans"]:
		_check("living %s house keeps bld_house art" % r,
			Art.building_texture_for("house", r) != null)
		_check("living %s house not routed to the undead sprite" % r,
			Art.building_texture_for("house", r)
				!= Art.building_texture_for("house", "undead"))
		_check("living %s barracks keeps bld_barracks art" % r,
			Art.building_texture_for("barracks", r) != null)
		_check("living %s barracks not routed to the undead sprite" % r,
			Art.building_texture_for("barracks", r)
				!= Art.building_texture_for("barracks", "undead"))
		for m: String in ["war_hut", "cannon_foundry", "armory", "vehicle_depot"]:
			_check("living %s %s maps to bld_barracks (fix79 base)" % [r, m],
				Art.BUILDING_ART.get(m, "") == "bld_barracks.png")
			_check("living %s %s texture resolves" % [r, m],
				Art.building_texture_for(m, r) != null)
			var lm := _make_node(m, true, r)
			_check("living %s %s node takes sprite path" % [r, m],
				lm._sprite != null)
			_check("living %s %s draws no programmer-art arm" % [r, m],
				await _drawn_art(lm) == "")
	# Undead house: real bld_house_undead sprite, not the office sprite.
	var uh := Art.building_texture_for("house", "undead")
	_check("undead house texture resolves", uh != null)
	_check("undead house not routed to bld_office_undead",
		uh != Art.building_texture_for("clinic", "undead"))
	_check("undead house differs from living house sprite",
		uh != Art.building_texture_for("house", "gnomes"))
	var uhn := _make_node("house", true, "undead")
	_check("undead house node takes sprite path", uhn._sprite != null)
	_check("undead house draws no programmer-art arm",
		await _drawn_art(uhn) == "")
	# NOTE: _drawn_art frees its node, so size pins use a fresh node.
	var uhn2 := _make_node("house", true, "undead")
	_check("undead house size still 30",
		uhn2._size_for("house") == 30.0)
	uhn2.free()
	# Undead military family: all five share bld_barracks_undead.
	for m: String in military:
		_check("undead %s texture resolves" % m,
			Art.building_texture_for(m, "undead") != null)
		_check("undead %s not routed to bld_office_undead" % m,
			Art.building_texture_for(m, "undead")
				!= Art.building_texture_for("clinic", "undead"))
		_check("undead %s not routed to bld_tavern_undead" % m,
			Art.building_texture_for(m, "undead")
				!= Art.building_texture_for("hotel", "undead"))
		var um := _make_node(m, true, "undead")
		_check("undead %s node takes sprite path" % m, um._sprite != null)
		_check("undead %s draws no programmer-art arm" % m,
			await _drawn_art(um) == "")
	_check("undead barracks size still 42",
		_make_node("barracks", true, "undead")._size_for("barracks") == 42.0)
	_check("undead war_hut size still 48",
		_make_node("war_hut", true, "undead")._size_for("war_hut") == 48.0)
	_check("undead vehicle_depot size still 44",
		_make_node("vehicle_depot", true, "undead")._size_for("vehicle_depot") == 44.0)
	_check("incomplete undead barracks blueprint sets no art arm",
		await _drawn_art(_make_node("barracks", false, "undead")) == "")

## Wake routine 2026-10-05 (launch-readiness graphics pass): fix79's
## BLD_SPRITE_FOR maps aa_tower -> bld_tower (verbatim), so it takes the
## sprite path now. The drawn _aa_tower() arm stays as missing-art
## fallback only. Size unchanged (26).
func _test_aa_tower() -> void:
	_check("aa_tower maps to bld_tower.png (fix79 BLD_SPRITE_FOR)",
		Art.BUILDING_ART.get("aa_tower", "") == "bld_tower.png")
	_check("aa_tower texture resolves for gnomes",
		Art.building_texture_for("aa_tower", "gnomes") != null)
	_check("draw dispatches aa_tower to the sprite path (no drawn arm)",
		await _drawn_art(_make_node("aa_tower")) == "")
	var n := _make_node("aa_tower")
	_check("aa_tower node takes sprite path", n._sprite != null)
	_check("aa_tower size still 26", n._size_for("aa_tower") == 26.0)
	n.free()
	_check("incomplete aa_tower blueprint sets no art arm",
		await _drawn_art(_make_node("aa_tower", false)) == "")


## Wake routine 2026-10-05 (launch-readiness graphics pass): fix79's
## BLD_SPRITE_FOR maps nuke_silo -> bld_tower (verbatim), so it takes the
## sprite path now. The drawn _nuke_silo() arm stays as missing-art
## fallback only. Size unchanged (30).
func _test_nuke_silo() -> void:
	_check("nuke_silo maps to bld_tower.png (fix79 BLD_SPRITE_FOR)",
		Art.BUILDING_ART.get("nuke_silo", "") == "bld_tower.png")
	_check("nuke_silo texture resolves for gnomes",
		Art.building_texture_for("nuke_silo", "gnomes") != null)
	_check("draw dispatches nuke_silo to the sprite path (no drawn arm)",
		await _drawn_art(_make_node("nuke_silo")) == "")
	var n := _make_node("nuke_silo")
	_check("nuke_silo node takes sprite path", n._sprite != null)
	_check("nuke_silo size still 30", n._size_for("nuke_silo") == 30.0)
	n.free()
	_check("incomplete nuke_silo blueprint sets no art arm",
		await _drawn_art(_make_node("nuke_silo", false)) == "")


## Wake routine 2026-10-05 (launch-readiness graphics pass): fix79's
## BLD_SPRITE_FOR maps cannon_foundry and armory -> bld_barracks
## (verbatim), so both take the sprite path now. Their drawn arms stay as
## missing-art fallback only. medic_camp moved to real tent sprite art
## (bld_tent_medic) earlier — see _test_tent_smithy_art. tome_library also
## left this group: fix79's BLD_SPRITE_FOR maps it to bld_civic — see
## _test_civic_art.
func _test_medic_camp_foundry_library_armory() -> void:
	for t: String in ["cannon_foundry", "armory"]:
		_check("%s maps to bld_barracks.png (fix79 BLD_SPRITE_FOR)" % t,
			Art.BUILDING_ART.get(t, "") == "bld_barracks.png")
		_check("%s texture resolves for gnomes" % t,
			Art.building_texture_for(t, "gnomes") != null)
		_check("draw dispatches %s to the sprite path (no drawn arm)" % t,
			await _drawn_art(_make_node(t)) == "")
		var n := _make_node(t)
		_check("%s node takes sprite path" % t, n._sprite != null)
		_check("%s size still 30" % t, n._size_for(t) == 30.0)
		n.free()
		_check("incomplete %s blueprint sets no art arm" % t,
			await _drawn_art(_make_node(t, false)) == "")


## The farmhouse used to fall through to the generic box+roof arm. It now
## gets fix79's real pixel-art sprite (bld_farmhouse, from AGRI62_BLD_B64),
## exactly like house and windmill: sprite path, no programmer-art arm.
func _test_farmhouse() -> void:
	_check("farmhouse uses real sprite art (no programmer-art arm)",
		await _drawn_art(_make_node("farmhouse")) == "")
	_check("farmhouse texture maps to bld_farmhouse.png",
		Art.building_texture_for("farmhouse", "gnomes") != null)
	var n := _make_node("farmhouse")
	_check("farmhouse node takes sprite path", n._sprite != null)
	_check("farmhouse size still 34", n._size_for("farmhouse") == 34.0)
	n.free()
	_check("incomplete farmhouse blueprint sets no art arm",
		await _drawn_art(_make_node("farmhouse", false)) == "")


## The fence fell through to the generic box+roof arm. It now gets fix79's
## real pixel-art sprite (bld_fence62, from AGRI62_BLD_B64): sprite path,
## no programmer-art arm. The other two AGRI62 sprites (bld_crop_field,
## bld_cow62) are staged in assets for the future crop_field/cattle_pen
## sim port, so the test also pins their presence.
func _test_fence() -> void:
	_check("fence uses real sprite art (no programmer-art arm)",
		await _drawn_art(_make_node("fence")) == "")
	_check("fence texture maps to bld_fence62.png",
		Art.BUILDING_ART.get("fence", "") == "bld_fence62.png")
	var n := _make_node("fence")
	_check("fence node takes sprite path", n._sprite != null)
	_check("fence size still 30 (default)", n._size_for("fence") == 30.0)
	n.free()
	_check("incomplete fence blueprint sets no art arm",
		await _drawn_art(_make_node("fence", false)) == "")
	_check("bld_crop_field.png staged for future crop_field port",
		FileAccess.file_exists("res://assets/art/buildings/bld_crop_field.png"))
	_check("bld_cow62.png staged for future cattle_pen port",
		FileAccess.file_exists("res://assets/art/buildings/bld_cow62.png"))


## Wake routine 2026-10-05 (launch-readiness graphics pass): fix79's
## BLD_SPRITE_FOR maps vehicle_depot -> bld_barracks (verbatim), so it
## takes the sprite path now; its drawn arm stays as missing-art fallback.
## shooting_range used to be in the drawn group too, but the 2026-10-04
## building-art audit mapped it to real sprite art (bld_archery_range.png)
## — sprite path now, no programmer-art arm. hotel/inn take fix79's base
## mappings (hotel -> bld_shop, inn -> bld_inn); their drawn _bathhouse arm
## is missing-art fallback only.
func _test_weaponsmith_range_depot_inn() -> void:
	for t: String in ["vehicle_depot"]:
		_check("%s maps to bld_barracks.png (fix79 BLD_SPRITE_FOR)" % t,
			Art.BUILDING_ART.get(t, "") == "bld_barracks.png")
		_check("%s texture resolves for gnomes" % t,
			Art.building_texture_for(t, "gnomes") != null)
		_check("draw dispatches %s to the sprite path (no drawn arm)" % t,
			await _drawn_art(_make_node(t)) == "")
		var n := _make_node(t)
		_check("%s node takes sprite path" % t, n._sprite != null)
		n.free()
		_check("incomplete %s blueprint sets no art arm" % t,
			await _drawn_art(_make_node(t, false)) == "")
	var sr := _make_node("shooting_range")
	_check("shooting_range resolves to sprite art",
		Art.building_texture_for("shooting_range", "gnomes") != null)
	_check("shooting_range node takes sprite path", sr._sprite != null)
	_check("shooting_range size 48", sr._size_for("shooting_range") == 48.0)
	sr.free()
	_check("shooting_range uses no programmer-art arm",
		await _drawn_art(_make_node("shooting_range")) == "")
	_check("incomplete shooting_range blueprint sets no art arm",
		await _drawn_art(_make_node("shooting_range", false)) == "")
	_check("weaponsmith size 32", _make_node("weaponsmith")._size_for("weaponsmith") == 32.0)
	_check("vehicle_depot size 44", _make_node("vehicle_depot")._size_for("vehicle_depot") == 44.0)
	for t: String in ["hotel", "inn"]:
		var png := "bld_shop.png" if t == "hotel" else "bld_inn.png"
		_check("%s maps to %s (fix79 BLD_SPRITE_FOR)" % [t, png],
			Art.BUILDING_ART.get(t, "") == png)
		_check("draw dispatches %s to the sprite path (no drawn arm)" % t,
			await _drawn_art(_make_node(t)) == "")
		_check("%s size 32" % t,
			_make_node(t)._size_for(t) == 32.0)
		_check("incomplete %s blueprint sets no art arm" % t,
			await _drawn_art(_make_node(t, false)) == "")


## The ten SimFoodPerks eateries used to share the drawn _eatery arm.
## Launch-readiness 2026-10-06: the port ships genuine per-race C61/C70
## pixel-art restaurant sprites (one per race, giant rooftop product statue
## baked in), so each perk eatery now resolves to its race's real sprite.
## Dispatch contract: every perk eatery takes the sprite path (no drawn
## arm); incomplete blueprints set no arm; vent FX still animates on the
## node (driven by btype, independent of the arm).
func _test_perk_eatery_art() -> void:
	var expected: Dictionary = {
		"greasy_spoon": "eat_cheese_shop.png",
		"salad_bar": "eat_cheese_shop.png",
		"ogre_sausage_shop": "eat_turkey_shop.png",
		"meat_tornado": "eat_turkey_shop.png",
		"moonberry_lounge": "eat_acorn_shop.png",
		"dewdrop_diner": "eat_acorn_shop.png",
		"bastard_drivethru": "eat_taco_shop.png",
		"fungus_hut": "eat_taco_shop.png",
		"crypt_kitchen": "eat_soul_cafe.png",
		"grave_snacks": "eat_soul_cafe.png",
	}
	_check("perk eateries cover all 10 types", expected.size() == 10)
	for t: String in expected:
		_check("%s maps to its race's restaurant sprite" % t,
			String(Art.BUILDING_ART.get(t, "")) == String(expected[t]))
		_check("%s texture resolves" % t,
			Art.building_texture_for(t, "gnomes") != null)
		_check("%s dispatches to sprite path, not a drawn arm" % t,
			await _drawn_art(_make_node(t)) == "")
		var n := _make_node(t)
		_check("%s node takes sprite path" % t, n._sprite != null)
		n.free()
		_check("incomplete %s blueprint sets no art arm" % t,
			await _drawn_art(_make_node(t, false)) == "")
	# Theme labels are ASCII-only (iPhone tofu rule) and non-empty
	# (they back the missing-art fallback arm, still in the game).
	for t: String in expected:
		var label: String = String(
			(BuildingNode.EATERY_THEMES[t] as Array)[0])
		var ascii_ok := label.length() > 0
		for i in range(label.length()):
			if label.unicode_at(i) > 127:
				ascii_ok = false
		_check("%s label non-empty ASCII" % t, ascii_ok)


## The repair shop fell through to the generic box+roof arm. It now gets
## the workshop arm (steel shop body + REPAIR sign + wrench prop).
func _test_repair_shop_art() -> void:
	_check("repair_shop dispatches to repair_shop arm, not generic",
		await _drawn_art(_make_node("repair_shop")) == "repair_shop")
	_check("incomplete repair_shop blueprint sets no art arm",
		await _drawn_art(_make_node("repair_shop", false)) == "")
	_check("repair_shop grounded like the shop",
		float(BuildingNode.DRAWN_GROUND_Y.get("repair_shop", -1.0)) == 26.0)
	_check("repair_shop paints its own doorway",
		"repair_shop" in BuildingNode.SELF_DOOR_BTYPES)
	_check("repair_shop size 32 (workshop footprint)",
		_make_node("repair_shop")._size_for("repair_shop") == 32.0)


## The 10 perk eateries + repair shop got animated vent FX (graphics-hourly
## 2026-10-06, launch readiness: "everything smoothly animated") — quantized
## chimney smoke/steam/spores/mist rising from the roof, the windmill/banner
## precedent (~6 redraws/sec, redraw only on step change). The FX tables must
## cover every type, params must be sane, the fx step must quantize into
## [0, STEPS), and non-eatery buildings must not animate this path.
func _test_eatery_fx() -> void:
	var types: Array[String] = ["greasy_spoon", "salad_bar",
		"ogre_sausage_shop", "meat_tornado", "moonberry_lounge",
		"dewdrop_diner", "bastard_drivethru", "fungus_hut",
		"crypt_kitchen", "grave_snacks", "repair_shop"]
	_check("EATERY_FX_BTYPES covers 10 eateries + repair_shop",
		BuildingNode.EATERY_FX_BTYPES.size() == 11)
	for t: String in types:
		_check("%s animates vent FX" % t, t in BuildingNode.EATERY_FX_BTYPES)
	# Every kind maps to a param set with sane values.
	for t: String in types:
		var kind: String = String(BuildingNode.EATERY_FX_KIND.get(t, ""))
		_check("%s has a vent FX kind" % t, kind != "")
		_check("%s FX kind has params" % t,
			BuildingNode.EATERY_FX_PARAMS.has(kind))
		var p: Array = BuildingNode.EATERY_FX_PARAMS.get(kind, [])
		var sane := p.size() == 4 and p[0] is Color \
			and float(p[1]) > 0.0 \
			and float(p[3]) > 0.0 and float(p[3]) <= 0.9
		_check("%s FX params sane (tint/rise/drift/alpha)" % t, sane)
	# Dispatch unchanged with the FX path live (draw must not error).
	# The perk eateries now take the sprite path; the vent FX animates on
	# the node regardless of the arm, and repair_shop keeps its drawn arm.
	_check("greasy_spoon dispatches to sprite path with FX live",
		await _drawn_art(_make_node("greasy_spoon")) == "")
	_check("repair_shop still dispatches to repair_shop arm with FX",
		await _drawn_art(_make_node("repair_shop")) == "repair_shop")
	# The fx step quantizes: advance _process frames, step lands in range.
	var n := _make_node("greasy_spoon")
	for _i in range(40):
		await process_frame
	_check("eatery fx_step quantizes into [0, STEPS)",
		n._fx_step >= 0 and n._fx_step < BuildingNode.EATERY_FX_STEPS)
	n.free()
	# A non-eatery building never touches the vent-FX path. 2026-10-09:
	# farms breathe via their own FARM_FX gate (crop sway), not eatery
	# vents — the farm roster stays out of EATERY_FX_BTYPES.
	var m := _make_node("farm")
	for _i in range(10):
		await process_frame
	_check("farm skips eatery vent roster",
		not ("farm" in BuildingNode.EATERY_FX_BTYPES))
	m.free()


## 'townhall' is a real placed btype (alias def) but had no BUILDING_ART
## entry, so it fell to the generic box. It now maps to bld_townhall.png.
func _test_townhall_alias_art() -> void:
	_check("townhall resolves to townhall sprite art",
		Art.building_texture_for("townhall", "gnomes") != null)
	var n := _make_node("townhall")
	_check("townhall node takes sprite path", n._sprite != null)
	n.free()
	_check("townhall uses no programmer-art arm",
		await _drawn_art(_make_node("townhall")) == "")


## The three military camps and the weaponsmith drew programmer-art
## silhouettes, but fix79's BLD_SPRITE_FOR routes them to real pixel art
## (bld_tent_field / bld_tent_camp / bld_tent_medic / bld_smithy) — the
## sprite path runs before the vector branches in the HTML, so the drawn
## tent/medic/smith arms survive only as missing-art fallback. Sprite
## path, no programmer-art arm, camps at default 30, weaponsmith at 32.
func _test_tent_smithy_art() -> void:
	var mapping := {
		"field_camp": "bld_tent_field.png",
		"camp": "bld_tent_camp.png",
		"equip_camp": "bld_tent_camp.png",
		"medic_camp": "bld_tent_medic.png",
		"weaponsmith": "bld_smithy.png",
	}
	for t: String in mapping:
		_check("%s maps to %s" % [t, mapping[t]],
			Art.BUILDING_ART.get(t, "") == mapping[t])
		_check("%s has source sprite art" % t,
			Art.building_texture_for(t, "gnomes") != null)
		_check("draw dispatches %s to the sprite path (no drawn arm)" % t,
			await _drawn_art(_make_node(t)) == "")
		var n := _make_node(t)
		_check("%s node takes sprite path" % t, n._sprite != null)
		n.free()
		_check("incomplete %s blueprint sets no art arm" % t,
			await _drawn_art(_make_node(t, false)) == "")
	_check("camp sizes default 30",
		_make_node("field_camp")._size_for("field_camp") == 30.0
		and _make_node("camp")._size_for("camp") == 30.0
		and _make_node("medic_camp")._size_for("medic_camp") == 30.0)
	_check("weaponsmith size 32", _make_node("weaponsmith")._size_for("weaponsmith") == 32.0)


## The necropolis (undead town center) fell through to the generic box+roof
## arm. It now gets fix79's real pixel-art sprite (bld_necropolis, via the
## HTML's bldHouseUndead68 undead-hall reroute): sprite path, no
## programmer-art arm, and the NECROHALL79 1.5x grand-hall size (52 * 1.5).
func _test_necropolis() -> void:
	_check("necropolis uses real sprite art (no programmer-art arm)",
		await _drawn_art(_make_node("necropolis", true, "undead")) == "")
	_check("necropolis texture maps to bld_necropolis.png",
		Art.BUILDING_ART.get("necropolis", "") == "bld_necropolis.png")
	var n := _make_node("necropolis", true, "undead")
	_check("necropolis node takes sprite path", n._sprite != null)
	n.free()
	_check("necropolis size 78.0 (hall 52 * 1.5, NECROHALL79)",
		_make_node("necropolis", true, "undead")._size_for("necropolis") == 78.0)
	_check("incomplete necropolis blueprint sets no art arm",
		await _drawn_art(_make_node("necropolis", false, "undead")) == "")


## The restaurant and soul_cafe fell through to the generic box+roof arm.
## They now get fix79's C61 faction eatery pixel art (Jeremy 2026-09-28:
## true 2:1 isometric pixel art, one per race, rooftop statue baked in):
## restaurant maps per race (taco/turkey/acorn/cheese/soul-cafe), soul_cafe
## keeps the Soul Cafe art for every race (C70). Sprite path, no
## programmer-art arm, civic size 40, incomplete blueprints draw nothing.
func _test_eatery_art() -> void:
	var variants: Dictionary = Art.BUILDING_ART_FACTION.get("restaurant", {})
	_check("restaurant maps gnomes to taco shop",
		String(variants.get("gnomes", "")) == "eat_taco_shop.png")
	_check("restaurant maps ogres to turkey shop",
		String(variants.get("ogres", "")) == "eat_turkey_shop.png")
	_check("restaurant maps elves to acorn shop",
		String(variants.get("elves", "")) == "eat_acorn_shop.png")
	_check("restaurant maps humans to cheese shop",
		String(variants.get("humans", "")) == "eat_cheese_shop.png")
	_check("restaurant maps undead to soul cafe",
		String(variants.get("undead", "")) == "eat_soul_cafe.png")
	var cafe_variants: Dictionary = Art.BUILDING_ART_FACTION.get("soul_cafe", {})
	for f: String in ["gnomes", "ogres", "elves", "humans", "undead"]:
		_check("soul_cafe maps %s to soul cafe art" % f,
			String(cafe_variants.get(f, "")) == "eat_soul_cafe.png")
	for f: String in ["gnomes", "ogres", "elves", "humans", "undead"]:
		_check("restaurant texture resolves for %s" % f,
			Art.building_texture_for("restaurant", f) != null)
		_check("soul_cafe texture resolves for %s" % f,
			Art.building_texture_for("soul_cafe", f) != null)
	for t: String in ["restaurant", "soul_cafe"]:
		_check("%s uses real sprite art (no programmer-art arm)" % t,
			await _drawn_art(_make_node(t)) == "")
		var n := _make_node(t)
		_check("%s node takes sprite path" % t, n._sprite != null)
		n.free()
		_check("%s size 40 (civic footprint)" % t,
			_make_node(t)._size_for(t) == 40.0)
		_check("incomplete %s blueprint sets no art arm" % t,
			await _drawn_art(_make_node(t, false)) == "")
	var nu := _make_node("restaurant", true, "undead")
	_check("undead restaurant node takes sprite path", nu._sprite != null)
	nu.free()


## The trade_outpost fell through to the generic box+roof arm. fix79's
## BLD_SPRITE_FOR maps it to bld_shop, and fix79's bldHouseUndead68
## reroutes undead shops to bld_shop_undead. Storage also gets its fix79
## bldStoreSprite57 faction storefront: bld_general_store_{race} per living
## race (bld_shop fallback), undead keeps bld_shop_undead. Sprite path, no
## programmer-art arm, shop size 30 for both.
## (The gov offices this pass also checked are already covered by the
## sibling's _test_civic_art — bld_civic + bld_office_undead.)
func _test_store_gov_trade_art() -> void:
	# --- trade_outpost: bld_shop base, bld_shop_undead for undead ---
	_check("trade_outpost maps to bld_shop.png",
		Art.BUILDING_ART.get("trade_outpost", "") == "bld_shop.png")
	_check("undead trade_outpost maps to bld_shop_undead.png",
		String(Art.BUILDING_ART_FACTION.get("trade_outpost", {}).get("undead", "")) == "bld_shop_undead.png")
	_check("trade_outpost texture resolves for gnomes",
		Art.building_texture_for("trade_outpost", "gnomes") != null)
	_check("undead trade_outpost texture resolves",
		Art.building_texture_for("trade_outpost", "undead") != null)
	_check("trade_outpost uses real sprite art (no programmer-art arm)",
		await _drawn_art(_make_node("trade_outpost")) == "")
	_check("trade_outpost node takes sprite path",
		_make_node("trade_outpost")._sprite != null)
	_check("trade_outpost size 30 (shop footprint)",
		_make_node("trade_outpost")._size_for("trade_outpost") == 30.0)
	_check("incomplete trade_outpost blueprint sets no art arm",
		await _drawn_art(_make_node("trade_outpost", false)) == "")
	# --- storage: per-race general-store storefronts (bldStoreSprite57) ---
	var store_variants: Dictionary = Art.BUILDING_ART_FACTION.get("storage", {})
	_check("storage maps gnomes to general store gnome",
		String(store_variants.get("gnomes", "")) == "bld_general_store_gnome.png")
	_check("storage maps ogres to general store ogre",
		String(store_variants.get("ogres", "")) == "bld_general_store_ogre.png")
	_check("storage maps elves to general store elf",
		String(store_variants.get("elves", "")) == "bld_general_store_elf.png")
	_check("storage maps humans to general store human",
		String(store_variants.get("humans", "")) == "bld_general_store_human.png")
	_check("storage keeps undead bld_shop_undead",
		String(store_variants.get("undead", "")) == "bld_shop_undead.png")
	for f: String in ["gnomes", "ogres", "elves", "humans", "undead"]:
		_check("storage texture resolves for %s" % f,
			Art.building_texture_for("storage", f) != null)
	_check("storage node takes sprite path",
		_make_node("storage")._sprite != null)
	_check("undead storage node takes sprite path",
		_make_node("storage", true, "undead")._sprite != null)


## Pier, shop, seedshop, and garden used to fall through to the generic
## box+roof arm. They now get their own drawn arms: pier and shop ported
## verbatim from fix79's procedural drawBuilding branches (pier posts +
## stiltwood / z_shop storefront), seedshop in the same z_shop visual
## language (no HTML art exists), garden from fix79's drawGardenLayer
## (soil bed + deterministic 3x3 flower grid).
func _test_pier_shop_seedshop_garden() -> void:
	# Wake routine 2026-10-05: seedshop moved to real sprite art
	# (fix79 BLD_SPRITE_FOR patch: seedshop -> bld_shop) — sprite path.
	for t: String in ["pier", "shop", "garden"]:
		_check("draw dispatches %s to its own arm" % t,
			await _drawn_art(_make_node(t)) == t)
		_check("%s has no source sprite art" % t,
			Art.building_texture_for(t, "gnomes") == null)
		var n := BuildingNode.new()
		n.setup(7, t, "gnomes", Vector2(100, 100))
		n.record = {"complete": true}
		_check("%s node takes programmer-art path" % t, n._sprite == null)
		_check("%s size still 30 (default footprint)" % t,
			n._size_for(t) == 30.0)
		n.free()
		_check("incomplete %s blueprint sets no art arm" % t,
			await _drawn_art(_make_node(t, false)) == "")
	_check("seedshop maps to bld_shop.png (fix79 patch)",
		Art.BUILDING_ART.get("seedshop", "") == "bld_shop.png")
	_check("seedshop texture resolves for gnomes",
		Art.building_texture_for("seedshop", "gnomes") != null)
	_check("draw dispatches seedshop to the sprite path (no drawn arm)",
		await _drawn_art(_make_node("seedshop")) == "")
	var sn := _make_node("seedshop")
	_check("seedshop node takes sprite path", sn._sprite != null)
	sn.free()
	_check("incomplete seedshop blueprint sets no art arm",
		await _drawn_art(_make_node("seedshop", false)) == "")
	# Garden determinism: same position -> same bloom colors (HTML
	# seed = (x*7 + y*13) | 0). Two nodes at the same spot must pick the
	# same arm; different spots still draw the garden arm.
	_check("garden arm fires at a second position too",
		await _drawn_art(_make_node("garden", true, "ogres")) == "garden")


## Building-art fix 2026-10-06: bridge segments fell through to the
## generic box+roof arm. They now get the STILTWOOD76 drawBridgeDeck port
## (plank deck, railings both sides, water stilts, auto-oriented along
## neighbor segments) — a real arm, never "generic". Grounded at the
## segment center (DRAWN_GROUND_Y 0.0, deck drawn HTML-verbatim around it),
## no doorway rect (decks are walked on), flat glow at night (halo only),
## and the arm draws no text at all — the iPhone tofu rule is vacuous.
func _test_bridge_art() -> void:
	_check("bridge dispatches to bridge arm, not generic",
		await _drawn_art(_make_node("bridge")) == "bridge")
	_check("bridge has no source sprite art",
		Art.building_texture_for("bridge", "gnomes") == null)
	var n := _make_node("bridge")
	_check("bridge node takes programmer-art path", n._sprite == null)
	_check("bridge size 40 (BUILDINGS def footprint)",
		n._size_for("bridge") == 40.0)
	n.free()
	_check("incomplete bridge blueprint sets no art arm",
		await _drawn_art(_make_node("bridge", false)) == "")
	_check("bridge grounded at the segment center (gy 0.0)",
		float(BuildingNode.DRAWN_GROUND_Y.get("bridge", -1.0)) == 0.0)
	_check("bridge paints no doorway (decks are walked on)",
		"bridge" in BuildingNode.SELF_DOOR_BTYPES)
	_check("bridge gets flat night glow (halo only, no lit windows)",
		"bridge" in BuildingNode.FLAT_GLOW_BTYPES)
	await _test_bridge_span_angle()


## Span orientation (HTML bridgeNeighborAngle parity): angle to the
## nearest sibling bridge segment within 75px, 0 when none. Scenarios run
## against _scan_bridge_span_angle directly (deterministic — no TTL).
func _test_bridge_span_angle() -> void:
	var parent := Node2D.new()
	root.add_child(parent)
	var a := BuildingNode.new()
	a.setup(101, "bridge", "gnomes", Vector2(100, 100))
	a.record = {"complete": true}
	parent.add_child(a)
	_check("lone bridge span angle is 0 (HTML: no neighbor -> 0)",
		a._scan_bridge_span_angle() == 0.0)
	var b := BuildingNode.new()
	b.setup(102, "bridge", "gnomes", Vector2(200, 100))
	b.record = {"complete": true}
	parent.add_child(b)
	_check("bridge aims at east neighbor (angle 0)",
		is_equal_approx(a._scan_bridge_span_angle(), 0.0))
	b.position = Vector2(100, 160)
	_check("bridge aims at south neighbor (angle PI/2)",
		is_equal_approx(a._scan_bridge_span_angle(), PI / 2.0))
	b.position = Vector2(500, 100)
	_check("bridge ignores neighbors past the 75px HTML threshold",
		a._scan_bridge_span_angle() == 0.0)
	var farm := BuildingNode.new()
	farm.setup(103, "farm", "gnomes", Vector2(120, 100))
	farm.record = {"complete": true}
	parent.add_child(farm)
	_check("bridge ignores non-bridge siblings (farm at 20px)",
		a._scan_bridge_span_angle() == 0.0)
	# The cached path serves the same angle within its TTL.
	a._bridge_ang_ms = -1
	b.position = Vector2(130, 100)
	_check("cached span angle serves the scan result",
		is_equal_approx(a._bridge_span_angle(), 0.0))
	_check("span angle cache timestamp set",
		a._bridge_ang_ms >= 0)
	a.free()
	b.free()
	farm.free()
	parent.free()


## Building-art fix 2026-10-06: 'air_defense' is the legacy alias of
## aa_tower (artillery.gd treats them identically; fix79 draws both in the
## same drawBuilding branch). It fell through to the generic box+roof arm;
## it now takes the aa_tower sprite (bld_tower.png, fix79 BLD_SPRITE_FOR
## verbatim) — sprite path, no programmer-art arm, aa_tower footprint.
func _test_air_defense_art() -> void:
	_check("air_defense maps to bld_tower.png (same as aa_tower)",
		Art.BUILDING_ART.get("air_defense", "") == "bld_tower.png")
	_check("air_defense texture resolves for gnomes",
		Art.building_texture_for("air_defense", "gnomes") != null)
	_check("air_defense shares aa_tower's sprite",
		Art.building_texture_for("air_defense", "gnomes")
		== Art.building_texture_for("aa_tower", "gnomes"))
	_check("draw dispatches air_defense to the sprite path (no drawn arm)",
		await _drawn_art(_make_node("air_defense")) == "")
	var n := _make_node("air_defense")
	_check("air_defense node takes sprite path", n._sprite != null)
	_check("air_defense size 26 (aa_tower parity)",
		n._size_for("air_defense") == 26.0)
	n.free()
	_check("incomplete air_defense blueprint sets no art arm",
		await _drawn_art(_make_node("air_defense", false)) == "")
## shops wrongly drew the living _shop() programmer-art arm. Verbatim from
## fix79 (index.html:104905): (t === 'shop' || t === 'storage' ||
## t === 'trade_outpost' || ...) && undead -> 'bld_shop_undead'. The port has
## no z_shop btype (HTML-only type), so only 'shop' is mapped here. Living
## Wake routine 2026-10-04 14:19: the bldHouseUndead68 clause covering
## 'shop' was never mapped (storage/trade_outpost/stock_* were) — undead
## shops wrongly drew the living _shop() programmer-art arm. Verbatim from
## fix79 (index.html:104905): (t === 'shop' || t === 'storage' ||
## t === 'trade_outpost' || ...) && undead -> 'bld_shop_undead'. The port has
## no z_shop btype (HTML-only type), so only 'shop' is mapped here. Living
## races keep the drawn _shop arm (no living sprite exists); the drawn arm
## stays as missing-art fallback only.
func _test_undead_shop_art() -> void:
	_check("undead shop maps to bld_shop_undead.png",
		String(Art.BUILDING_ART_FACTION.get("shop", {}).get("undead", "")) == "bld_shop_undead.png")
	for f: String in ["gnomes", "ogres", "elves", "humans"]:
		_check("%s shop keeps the drawn arm (no sprite)" % f,
			Art.building_texture_for("shop", f) == null)
	_check("undead shop texture resolves",
		Art.building_texture_for("shop", "undead") != null)
	_check("undead shop shares bld_shop_undead with undead trade_outpost",
		Art.building_texture_for("shop", "undead") == Art.building_texture_for("trade_outpost", "undead"))
	_check("undead shop node takes sprite path (no programmer-art arm)",
		_make_node("shop", true, "undead")._sprite != null)
	_check("undead shop fires no drawn arm",
		await _drawn_art(_make_node("shop", true, "undead")) == "")
	_check("living shop node still takes the drawn arm",
		await _drawn_art(_make_node("shop")) == "shop")
	_check("shop size still 30 (default footprint)",
		_make_node("shop", true, "undead")._size_for("shop") == 30.0)
	_check("incomplete undead shop blueprint sets no art arm",
		await _drawn_art(_make_node("shop", false, "undead")) == "")
