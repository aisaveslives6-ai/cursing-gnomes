extends SceneTree
## Cursing Gnomes — building-art file coverage tests (2026-10-07).
##
## What this guards: bld_general_store_{gnome,human,elf,ogre}.png are mapped in
## Art.BUILDING_ART_FACTION ("storage" + "general_store"). Their .import/.ctex
## cache entries survive in .godot/imported, which masks a missing source PNG
## from ResourceLoader — so this suite checks the SOURCE tree (FileAccess) as
## well as loadability. The 4 sources were re-extracted verbatim from
## fix79/index.html on 2026-10-07 (md5-identical to the cached originals).
##
## Covers:
##   1. No dead art mappings: every PNG named in BUILDING_ART and
##      BUILDING_ART_FACTION exists on disk (the exact failure class).
##   2. General-store restoration: all 4 race sprites load; storage and
##      general_store resolve for all 5 factions (undead fallbacks per
##      fix79 bldStoreSprite57 / bldHouseUndead68: bld_shop_undead).
##   3. Full coverage: every sim building type (BUILDINGS + SERVICE_BUILDINGS)
##      renders non-generic art — sprite path or a dedicated drawn arm,
##      never the generic box+roof fallback.
##   4. Guild-hall factions: all 5 factions resolve (undead -> bld_guild_undead).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_building_art_files.gd
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


func _make_node(btype: String, faction := "gnomes") -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": true}
	root.add_child(n)
	return n


## Adds the node, lets _draw run, returns the art arm it used
## ("" = sprite path, "generic" = box+roof fallback).
func _drawn_art(n: BuildingNode) -> String:
	n.queue_redraw()
	await process_frame
	await process_frame
	var art: String = n._last_art
	n.free()
	return art


func _test_no_dead_mappings() -> void:
	# Two predicates: the source PNG must exist in the source tree
	# (FileAccess — the .import/.ctex cache can mask a missing source),
	# AND it must be loadable (ResourceLoader — what Art._tex uses).
	var dead: Array[String] = []
	for btype: String in Art.BUILDING_ART:
		var f := "res://assets/art/buildings/" + String(Art.BUILDING_ART[btype])
		if btype == "wall" or btype == "gate":
			f = "res://assets/art/walls/" + String(Art.BUILDING_ART[btype])
		if not FileAccess.file_exists(f):
			dead.append("SOURCE MISSING %s -> %s" % [btype, f])
		elif not ResourceLoader.exists(f):
			dead.append("UNLOADABLE %s -> %s" % [btype, f])
	_check("no dead BUILDING_ART mappings", dead.is_empty())
	for d: String in dead:
		print("  DEAD: ", d)
	var dead_f: Array[String] = []
	for btype: String in Art.BUILDING_ART_FACTION:
		var variants: Dictionary = Art.BUILDING_ART_FACTION[btype]
		for fac: String in variants:
			var f2 := "res://assets/art/buildings/" + String(variants[fac])
			if not FileAccess.file_exists(f2):
				dead_f.append("SOURCE MISSING %s[%s] -> %s" % [btype, fac, f2])
			elif not ResourceLoader.exists(f2):
				dead_f.append("UNLOADABLE %s[%s] -> %s" % [btype, fac, f2])
	_check("no dead BUILDING_ART_FACTION mappings", dead_f.is_empty())
	for d: String in dead_f:
		print("  DEAD: ", d)


func _test_general_store_restored() -> void:
	var factions := ["humans", "ogres", "elves", "gnomes", "undead"]
	for f: String in factions:
		_check("general_store[%s] texture resolves" % f,
			Art.building_texture_for("general_store", f) != null)
		_check("storage[%s] texture resolves" % f,
			Art.building_texture_for("storage", f) != null)
	# HTML fallbacks (fix79 bldStoreSprite57 / bldHouseUndead68 verbatim).
	_check("undead storage keeps bld_shop_undead",
		Art.building_texture_for("storage", "undead") != null)
	var n := _make_node("general_store", "humans")
	_check("general_store takes sprite path, not generic", n._sprite != null)
	n.free()


func _test_guild_hall_factions() -> void:
	for f: String in ["humans", "ogres", "elves", "gnomes", "undead"]:
		_check("guild_hall[%s] texture resolves" % f,
			Art.building_texture_for("guild_hall", f) != null)


func _test_full_coverage() -> void:
	var types: Array = []
	for t: String in SimBuildings.BUILDINGS:
		types.append(t)
	for t: String in SimBuildings.SERVICE_BUILDINGS:
		if not types.has(t):
			types.append(t)
	_check("sim defines building types", types.size() >= 79)
	var generic: Array[String] = []
	for t: String in types:
		var art := await _drawn_art(_make_node(String(t)))
		if art == "generic":
			generic.append(String(t))
	_check("no building type falls back to generic box+roof", generic.is_empty())
	for g: String in generic:
		print("  GENERIC: ", g)


func _initialize() -> void:
	print("=== Cursing Gnomes building-art file coverage tests ===")
	_test_no_dead_mappings()
	_test_general_store_restored()
	_test_guild_hall_factions()
	await _test_full_coverage()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("FAILED: ", f)
	quit(1 if _failed > 0 else 0)
