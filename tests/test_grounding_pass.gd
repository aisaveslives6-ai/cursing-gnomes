extends SceneTree
## Cursing Gnomes — launch-readiness graphics pass tests (2026-10-05).
##
## Covers the deep graphics pass on the drawn building renderer:
##  1. The 12 remaining drawn-silhouette types now map to real fix79 pixel
##     art (Art.BUILDING_ART), so BuildingNode takes the sprite path for
##     them (feet at origin, iso art, correct y-sort).
##  2. Undead faction variants still route through BUILDING_ART_FACTION.
##  3. DRAWN_GROUND_Y covers every drawn match arm, so the re-anchor in
##     _draw() grounds each silhouette (shadow under the footprint).
##  4. SELF_DOOR_BTYPES keeps the pre-existing doorway skips and adds the
##     types that paint their own doors (no double-draw at the ground).
##  5. Animals now carry the sun-driven blob shadow (no more floating).
##  6. MapProp tree has a drawn pine fallback (never an invisible tree).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_grounding_pass.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes grounding-pass tests ===")
	_test_new_art_mappings()
	_test_faction_variants()
	_test_sprite_path_taken()
	_test_drawn_ground_table()
	_test_self_door_table()
	_test_animal_shadow()
	_test_tree_fallback()
	_test_flat_glow_table()
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


## The 12 types fix79's BLD_SPRITE_FOR maps to real art now resolve.
func _test_new_art_mappings() -> void:
	var mapped := {
		"inn": "bld_inn.png",
		"hotel": "bld_shop.png",
		"bathhouse": "bld_civic.png",
		"war_hut": "bld_barracks.png",
		"cannon_foundry": "bld_barracks.png",
		"vehicle_depot": "bld_barracks.png",
		"armory": "bld_barracks.png",
		"aa_tower": "bld_tower.png",
		"nuke_silo": "bld_tower.png",
		"anti_nuke": "bld_anti_nuke.png",
		"well": "bld_shop.png",
		"seedshop": "bld_shop.png",
	}
	for btype: String in mapped:
		var tex: Texture2D = Art.building_texture_for(btype, "humans")
		_check("art mapped: %s -> %s loads" % [btype, mapped[btype]],
			tex != null)
		_check("art base: %s" % btype,
			Art.BUILDING_ART.get(btype, "") == mapped[btype])


## Undead variants keep their dedicated reroutes (faction table first).
func _test_faction_variants() -> void:
	_check("inn/undead -> tavern_undead",
		Art.building_texture_for("inn", "undead") != null)
	_check("hotel/undead -> tavern_undead",
		Art.building_texture_for("hotel", "undead") != null)
	_check("bathhouse/undead -> office_undead",
		Art.building_texture_for("bathhouse", "undead") != null)
	_check("war_hut/undead -> barracks_undead",
		Art.building_texture_for("war_hut", "undead") != null)
	_check("armory/undead -> barracks_undead",
		Art.building_texture_for("armory", "undead") != null)
	# Living races take the new base art, not the drawn arm.
	_check("inn/humans is bld_inn base",
		Art.BUILDING_ART["inn"] == "bld_inn.png")


## BuildingNode.setup takes the sprite path (not the drawn arm) for the
## newly mapped types: _sprite exists and sits feet-at-origin.
func _test_sprite_path_taken() -> void:
	for btype: String in ["inn", "war_hut", "aa_tower", "nuke_silo",
			"well", "bathhouse", "armory", "seedshop"]:
		var b := BuildingNode.new()
		b.setup(9000 + abs(hash(btype)) % 500, btype, "humans",
			Vector2(100, 200))
		_check("sprite path: %s builds a sprite" % btype, b._sprite != null)
		if b._sprite != null:
			_check("sprite path: %s feet at origin" % btype,
				b._sprite.position.y < 0.0)
		b.free()
	# Types with no fix79 art still use the drawn fallback arm.
	var f := BuildingNode.new()
	f.setup(7777, "farm", "humans", Vector2.ZERO)
	_check("farm keeps drawn fallback (no fix79 art)", f._sprite == null)
	f.free()
	var m := BuildingNode.new()
	m.setup(7778, "monastery", "humans", Vector2.ZERO)
	_check("monastery keeps drawn fallback (no fix79 art)", m._sprite == null)
	m.free()


## Every drawn match arm has a ground entry; values are sane.
func _test_drawn_ground_table() -> void:
	var drawn := ["farm", "clinic", "aa_tower", "well", "windmill",
		"mage_spire", "monastery", "fishing_dock", "flesh_farm",
		"fire_station", "sawmill", "quarry", "mine", "bathhouse", "hotel",
		"inn", "guard_house", "war_hut", "nuke_silo", "medic_camp",
		"cannon_foundry", "tome_library", "armory", "weaponsmith",
		"shooting_range", "vehicle_depot", "pier", "shop", "seedshop",
		"trade_outpost", "garden"]
	for btype: String in drawn:
		_check("ground table has %s" % btype,
			BuildingNode.DRAWN_GROUND_Y.has(btype))
		var gy: float = float(BuildingNode.DRAWN_GROUND_Y.get(btype, 999.0))
		_check("ground %s sane (|y|<=40)" % btype, absf(gy) <= 40.0)
	# Spot checks against the measured arm geometry.
	_check("monastery ground 24",
		is_equal_approx(float(BuildingNode.DRAWN_GROUND_Y["monastery"]), 24.0))
	_check("guard_house ground 26",
		is_equal_approx(float(BuildingNode.DRAWN_GROUND_Y["guard_house"]), 26.0))
	_check("quarry rim negative (open pit)",
		float(BuildingNode.DRAWN_GROUND_Y["quarry"]) < 0.0)
	_check("garden flat (0)",
		is_equal_approx(float(BuildingNode.DRAWN_GROUND_Y["garden"]), 0.0))
	_check("trade_outpost already grounded (0)",
		is_equal_approx(float(BuildingNode.DRAWN_GROUND_Y["trade_outpost"]), 0.0))


## Doorway skip list: pre-existing skips kept, self-door types added.
func _test_self_door_table() -> void:
	var keep := ["quarry", "mine", "fishing_dock", "pier", "garden",
		"shooting_range", "vehicle_depot"]
	for btype: String in keep:
		_check("doorway still skipped: %s" % btype,
			btype in BuildingNode.SELF_DOOR_BTYPES)
	var added := ["monastery", "guard_house", "shop", "seedshop",
		"clinic", "bathhouse", "hotel", "inn", "tome_library",
		"weaponsmith", "war_hut", "cannon_foundry", "armory"]
	for btype: String in added:
		_check("self-door skip: %s" % btype,
			btype in BuildingNode.SELF_DOOR_BTYPES)
	# Types without their own door keep the generic ground doorway.
	_check("farm keeps generic doorway",
		not ("farm" in BuildingNode.SELF_DOOR_BTYPES))
	_check("windmill keeps generic doorway",
		not ("windmill" in BuildingNode.SELF_DOOR_BTYPES))


## Animals carry the sun-driven blob shadow now.
func _test_animal_shadow() -> void:
	_check("animal shadow footprint positive",
		AnimalNode.ANIMAL_SHADOW_FOOTPRINT > 0.0)
	_check("animal shadow = 0.75x visual height (unit precedent)",
		is_equal_approx(AnimalNode.ANIMAL_SHADOW_FOOTPRINT,
			AnimalNode.SPRITE_WORLD_H * 0.75))


## Tree props never render invisible: fallback flag defaults off, art
## present today so the sprite path is taken.
func _test_tree_fallback() -> void:
	var t := MapProp.new()
	t.setup("tree", Vector2(123.0, 456.0))
	_check("tree fallback defaults off", t._tree_fallback == false)
	_check("tree art present: sprite path taken", t._sprite != null)
	t.free()


## Flat/non-box drawn types get the night halo only (no floating windows
## or doorway); box types keep windows + doorway.
func _test_flat_glow_table() -> void:
	for btype: String in ["quarry", "mine", "fishing_dock", "pier",
			"garden", "shooting_range", "farm"]:
		_check("flat glow: %s" % btype,
			btype in BuildingNode.FLAT_GLOW_BTYPES)
	_check("monastery keeps windows+door (box chapel)",
		not ("monastery" in BuildingNode.FLAT_GLOW_BTYPES))
	_check("shop keeps windows+door (box storefront)",
		not ("shop" in BuildingNode.FLAT_GLOW_BTYPES))
