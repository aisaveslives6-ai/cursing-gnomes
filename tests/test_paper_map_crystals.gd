extends SceneTree
## Cursing Gnomes — paper-map dark crystal label tests (Jeremy 2026-10-04).
##
## The Seven Dark Crystals are the evil mirror of the Seven Monasteries, so
## the far-zoom paper map draws them the same way: a small drawn jagged
## shard marker (never a glyph — tofu rule) plus the rogue god's name, in
## the owner faction's color when captured or the god's own trim accent
## color while unowned. Covers PaperMap._crystal_label_rows() (pure logic);
## the draw pass just maps those rows through draw_string/draw_polyline.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_paper_map_crystals.gd

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


func _pm() -> PaperMap:
	var pm := PaperMap.new()
	pm._map_rect = Rect2(Vector2.ZERO, Vector2(800, 600))
	var gs: GameState = GameState.new()
	var crys := SimDarkCrystals.new()
	gs.crystals = crys
	pm._game = gs
	return pm


func _rec(god_id: String, pos: Vector2, owner := "") -> Dictionary:
	return {
		"id": 1, "god_id": god_id, "position": pos, "owner": owner,
		"progress": {}, "contested": false, "contested_by": "",
		"name": "Dark Crystal of X",
	}


func _test_no_game_empty() -> void:
	var pm := PaperMap.new()
	pm._map_rect = Rect2(Vector2.ZERO, Vector2(800, 600))
	_check("no game -> empty rows", pm._crystal_label_rows().is_empty())
	pm.queue_free()


func _test_null_crystals_empty() -> void:
	var pm := PaperMap.new()
	pm._map_rect = Rect2(Vector2.ZERO, Vector2(800, 600))
	pm._game = GameState.new()  # crystals stays null
	_check("null crystals -> empty rows",
		pm._crystal_label_rows().is_empty())
	pm.queue_free()


func _test_unowned_uses_trim_color() -> void:
	var pm := _pm()
	(pm._game.get("crystals") as SimDarkCrystals).crystals = [
		_rec("vexmor", Vector2(2048, 2048)),
	]
	var rows: Array = pm._crystal_label_rows()
	_check("one unowned -> one row", rows.size() == 1)
	_check("label is god name", String(rows[0]["label"]) == "Vexmor")
	var vexmor_trim := Color(0.70, 0.40, 1.0)
	_check("unowned color = god's trim accent",
		(rows[0]["color"] as Color).is_equal_approx(vexmor_trim))
	pm.queue_free()


func _test_owned_uses_faction_color() -> void:
	var pm := _pm()
	(pm._game.get("crystals") as SimDarkCrystals).crystals = [
		_rec("morrga", Vector2(1024, 3072), "gnomes"),
	]
	var rows: Array = pm._crystal_label_rows()
	_check("one owned -> one row", rows.size() == 1)
	_check("label is god name",
		String(rows[0]["label"]) == "Blightmother Morrga")
	var expected: Color = Config.FACTIONS["gnomes"]["color"]
	_check("owned color = owner faction color",
		(rows[0]["color"] as Color).is_equal_approx(expected))
	pm.queue_free()


func _test_position_mapping() -> void:
	var pm := _pm()
	(pm._game.get("crystals") as SimDarkCrystals).crystals = [
		_rec("raijuk", Vector2(2048, 2048)),
	]
	var rows: Array = pm._crystal_label_rows()
	# 4096x4096 world -> map rect 800x600: world center = map center.
	_check("world center maps to rect center",
		(rows[0]["pos"] as Vector2).is_equal_approx(Vector2(400, 300)))
	pm.queue_free()


func _test_bad_records_skipped() -> void:
	var pm := _pm()
	(pm._game.get("crystals") as SimDarkCrystals).crystals = [
		_rec("not_a_god", Vector2(100, 100)),
		_rec("furnax", Vector2(3000, 3000)),
	]
	var rows: Array = pm._crystal_label_rows()
	_check("bad god_id skipped", rows.size() == 1)
	_check("kept row is Furnax", String(rows[0]["label"]) == "Furnax")
	pm.queue_free()


func _test_label_has_no_glyph() -> void:
	# Tofu rule: labels are plain god names — no emoji/special glyphs.
	var pm := _pm()
	(pm._game.get("crystals") as SimDarkCrystals).crystals = [
		_rec("kaul", Vector2(500, 500)),
	]
	var rows: Array = pm._crystal_label_rows()
	var label := String(rows[0]["label"])
	var ascii_only := true
	for i in label.length():
		if label.unicode_at(i) > 127:
			ascii_only = false
	_check("label is plain ASCII (no glyph risk)", ascii_only)
	pm.queue_free()


func _test_all_seven_gods_resolve() -> void:
	# Every rogue god in ROGUE_GODS must resolve to a label row — no
	# silent skips for valid god_ids (parity with the monastery suite).
	var pm := _pm()
	var recs: Array[Dictionary] = []
	for g: Dictionary in SimDarkCrystals.ROGUE_GODS:
		recs.append(_rec(String(g["id"]), Vector2(2000, 2000)))
	(pm._game.get("crystals") as SimDarkCrystals).crystals = recs
	var rows: Array = pm._crystal_label_rows()
	_check("all 7 rogue gods produce rows",
		rows.size() == SimDarkCrystals.ROGUE_GODS.size())
	pm.queue_free()


func _initialize() -> void:
	print("=== Paper-map dark crystal label tests ===")
	_test_no_game_empty()
	_test_null_crystals_empty()
	_test_unowned_uses_trim_color()
	_test_owned_uses_faction_color()
	_test_position_mapping()
	_test_bad_records_skipped()
	_test_label_has_no_glyph()
	_test_all_seven_gods_resolve()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)
