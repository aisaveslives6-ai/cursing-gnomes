extends SceneTree
## Cursing Gnomes — paper-map monastery label tests (Jeremy 2026-10-04).
##
## The Seven Monasteries are major named landmarks, so the far-zoom
## paper map draws them alongside town and region labels: a small drawn
## diamond marker (never a glyph — tofu rule) plus the god's name, in the
## owner faction's color when captured or the god's own color while
## unowned. Covers PaperMap._monastery_label_rows() (pure logic); the
## draw pass just maps those rows through draw_string/draw_polyline.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_paper_map_monasteries.gd

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
	var mons := SimMonasteries.new()
	gs.monasteries = mons
	pm._game = gs
	return pm


func _rec(god_id: String, pos: Vector2, owner := "") -> Dictionary:
	return {
		"id": 1, "god_id": god_id, "position": pos, "owner": owner,
		"progress": {}, "contested": false, "contested_by": "",
		"name": "Monastery of X",
	}


func _test_no_game_empty() -> void:
	var pm := PaperMap.new()
	pm._map_rect = Rect2(Vector2.ZERO, Vector2(800, 600))
	_check("no game -> empty rows", pm._monastery_label_rows().is_empty())
	pm.queue_free()


func _test_null_monasteries_empty() -> void:
	var pm := PaperMap.new()
	pm._map_rect = Rect2(Vector2.ZERO, Vector2(800, 600))
	pm._game = GameState.new()  # monasteries stays null
	_check("null monasteries -> empty rows",
		pm._monastery_label_rows().is_empty())
	pm.queue_free()


func _test_unowned_uses_god_color() -> void:
	var pm := _pm()
	(pm._game.get("monasteries") as SimMonasteries).monasteries = [
		_rec("auriel", Vector2(2048, 2048)),
	]
	var rows: Array = pm._monastery_label_rows()
	_check("one unowned -> one row", rows.size() == 1)
	_check("label is god name", String(rows[0]["label"]) == "Auriel")
	var auriel_main := Color(1.0, 0.85, 0.35)
	_check("unowned color = god's own color",
		(rows[0]["color"] as Color).is_equal_approx(auriel_main))
	pm.queue_free()


func _test_owned_uses_faction_color() -> void:
	var pm := _pm()
	(pm._game.get("monasteries") as SimMonasteries).monasteries = [
		_rec("sylvara", Vector2(1024, 3072), "gnomes"),
	]
	var rows: Array = pm._monastery_label_rows()
	_check("one owned -> one row", rows.size() == 1)
	_check("label is god name", String(rows[0]["label"]) == "Sylvara")
	var expected: Color = Config.FACTIONS["gnomes"]["color"]
	_check("owned color = owner faction color",
		(rows[0]["color"] as Color).is_equal_approx(expected))
	pm.queue_free()


func _test_position_mapping() -> void:
	var pm := _pm()
	(pm._game.get("monasteries") as SimMonasteries).monasteries = [
		_rec("volkar", Vector2(2048, 2048)),
	]
	var rows: Array = pm._monastery_label_rows()
	# 4096x4096 world -> map rect 800x600: world center = map center.
	_check("world center maps to rect center",
		(rows[0]["pos"] as Vector2).is_equal_approx(Vector2(400, 300)))
	pm.queue_free()


func _test_bad_records_skipped() -> void:
	var pm := _pm()
	(pm._game.get("monasteries") as SimMonasteries).monasteries = [
		_rec("not_a_god", Vector2(100, 100)),
		_rec("ostra", Vector2(3000, 3000)),
	]
	var rows: Array = pm._monastery_label_rows()
	_check("bad god_id skipped", rows.size() == 1)
	_check("kept row is Ostra", String(rows[0]["label"]) == "Ostra")
	pm.queue_free()


func _test_label_has_no_glyph() -> void:
	# Tofu rule: labels are plain god names — no emoji/special glyphs.
	var pm := _pm()
	(pm._game.get("monasteries") as SimMonasteries).monasteries = [
		_rec("felicity", Vector2(500, 500)),
	]
	var rows: Array = pm._monastery_label_rows()
	var label := String(rows[0]["label"])
	var ascii_only := true
	for i in label.length():
		if label.unicode_at(i) > 127:
			ascii_only = false
	_check("label is plain ASCII (no glyph risk)", ascii_only)
	pm.queue_free()


func _initialize() -> void:
	print("=== Paper-map monastery label tests ===")
	_test_no_game_empty()
	_test_null_monasteries_empty()
	_test_unowned_uses_god_color()
	_test_owned_uses_faction_color()
	_test_position_mapping()
	_test_bad_records_skipped()
	_test_label_has_no_glyph()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)
