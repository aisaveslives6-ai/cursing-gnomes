extends SceneTree
## Cursing Gnomes — naval renderer tests (2026-10-04).
##
## Boats (fishing_boat / war_ship) are drawn as AI-generated pixel-art hulls,
## not chibi characters — verbatim port of the HTML's _toonDrawCharacter
## boat branch: fix79's BOAT_SPRITE_SRC hulls extracted to
## assets/art/boats/, bob + rock wave motion, faction pennant on the mast in
## the race accent color. war_ship keeps the combat shield job tag (HTML
## COMBAT_JOBS fallback, idx 10); fishing_boat gets no tag.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_boat_art.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(label)
		print("FAIL: ", label)


func _initialize() -> void:
	print("=== Cursing Gnomes boat-art tests ===")
	_test_hull_art_ships()
	_test_boat_texture()
	_test_faction_accents()
	_test_war_ship_combat_tag()
	_test_fishing_boat_node()
	_test_war_ship_node()
	_test_boat_wave_motion()
	_test_pennant()
	_test_non_boat_unaffected()
	_test_boat_no_limb_stumps()
	_test_set_job_rebuild()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


## Both hull PNGs extracted from fix79's BOAT_SPRITE_SRC ship with the game.
func _test_hull_art_ships() -> void:
	for key: String in ["fishing_boat", "war_ship"]:
		var f := FileAccess.open(
			"res://assets/art/boats/%s.png" % key, FileAccess.READ)
		_check(f != null, "boat: %s.png exists on disk" % key)
		if f != null:
			_check(f.get_length() > 10000,
				"boat: %s.png is a real image" % key)
			f.close()


func _test_boat_texture() -> void:
	var fb: Texture2D = Art.boat_texture("fishing_boat")
	_check(fb != null, "boat: Art.boat_texture resolves fishing_boat")
	var ws: Texture2D = Art.boat_texture("war_ship")
	_check(ws != null, "boat: Art.boat_texture resolves war_ship")
	if fb != null:
		_check(fb.get_width() == 256 and fb.get_height() == 184,
			"boat: fishing_boat is 256x184")
	if ws != null:
		_check(ws.get_width() == 256 and ws.get_height() == 187,
			"boat: war_ship is 256x187")
	_check(Art.boat_texture("worker") == null,
		"boat: Art.boat_texture returns null for non-boat jobs")
	_check(Art.boat_texture("soldier") == null,
		"boat: Art.boat_texture returns null for soldier")


## HTML RACES accent colors, verbatim; plural faction names map too.
func _test_faction_accents() -> void:
	var expect := {
		"gnomes": "8e24aa", "ogres": "388e3c", "elves": "2e7d32",
		"humans": "0288d1", "undead": "37474f",
	}
	for fac: String in expect.keys():
		var got: Color = Art.faction_accent(fac)
		_check(got.to_html(false).to_lower() == expect[fac],
			"boat: faction accent for %s" % fac)
	_check(Art.faction_accent("gnome") == Art.faction_accent("gnomes"),
		"boat: singular/plural faction names map to one accent")


## HTML jobIconFor54: war_ship falls back to the combat shield icon (idx 10).
func _test_war_ship_combat_tag() -> void:
	var tag: Texture2D = Art.job_tag("war_ship")
	_check(tag != null, "boat: war_ship gets a job tag texture")
	if tag != null:
		_check("jobtag10" in tag.resource_path,
			"boat: war_ship tag is the combat shield (jobtag10)")


func _make_boat(unit_id: int, faction: String, job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(unit_id, faction, job, Vector2(400, 300), "m")
	return un


## Jeremy 2026-10-05: all bubbles removed — no ActivityBubble/SpeechBubble
## node may exist anywhere under a unit node.
func _has_bubble_child(un: UnitNode) -> bool:
	for c: Node in un.find_children("*", "", true, false):
		if "bubble" in String(c.name).to_lower():
			return true
	return false


## Fishing boat: hull sprite at HTML-verbatim scale (bw = s*2.5), no tag.
func _test_fishing_boat_node() -> void:
	var un := _make_boat(9001, "gnomes", "fishing_boat")
	_check(un._boat != null, "boat: fishing_boat node has a boat wrapper")
	_check(un._sprite != null and un._sprite.texture != null,
		"boat: fishing_boat sprite has the hull texture")
	var expect_w := 44.0 * 2.5
	_check(absf(un._boat_w - expect_w) < 0.01,
		"boat: fishing_boat hull world width = s*2.5 (%s)" % str(un._boat_w))
	var expect_h: float = expect_w * 184.0 / 256.0
	_check(absf(un._boat_h - expect_h) < 0.01,
		"boat: fishing_boat hull height follows art aspect")
	# Hull center sits at -bh*0.22 (HTML drawImage(-bw/2, -bh*0.72, bw, bh)).
	var expect_y := -un._boat_h * 0.22
	_check(absf(un._sprite.position.y - expect_y) < 0.01,
		"boat: fishing_boat hull vertical placement matches HTML")
	# No chibi body motion: the sprite scale matches the hull, not SPRITE_WORLD_H.
	_check(absf(un._sprite.scale.x - expect_w / 256.0) < 0.001,
		"boat: fishing_boat sprite scale matches hull width")
	# HTML: fishing_boat gets NO job tag.
	# Jeremy 2026-10-05: all bubbles removed — no tag bubble may exist
	# anywhere under the unit node.
	_check(not _has_bubble_child(un),
		"boat: fishing_boat has no tag bubble")
	# Wider shadow blob than a chibi's.
	_check(un._shadow_footprint() > 44.0 * 0.75,
		"boat: fishing_boat shadow footprint matches the hull")
	un.queue_free()


## War ship: hull at s*3.4 (wider than the fishing boat), combat tag on.
func _test_war_ship_node() -> void:
	var un := _make_boat(9002, "humans", "war_ship")
	_check(un._boat != null, "boat: war_ship node has a boat wrapper")
	var expect_w := 44.0 * 3.4
	_check(absf(un._boat_w - expect_w) < 0.01,
		"boat: war_ship hull world width = s*3.4")
	_check(un._boat_w > 44.0 * 2.5,
		"boat: war_ship is wider than the fishing boat")
	_check(not _has_bubble_child(un),
		"boat: war_ship has no tag bubble (all bubbles removed)")
	_check(un._pennant != null, "boat: war_ship has a pennant")
	_check(un._pennant.color.to_html(false).to_lower() == "0288d1",
		"boat: human war_ship pennant is the human accent")
	un.queue_free()


## Bob + rock advance with the boat clock; no chibi choreography applied.
func _test_boat_wave_motion() -> void:
	var un := _make_boat(9003, "elves", "fishing_boat")
	var t0: float = un._boat_time
	un._process(0.1)
	_check(un._boat_time > t0, "boat: wave clock advances in _process")
	# HTML bob: sin(t*2.1 + uid*1.7) * s * 0.07, rock: sin(t*1.3 + uid*2.3)*0.045
	var expect_bob: float = sin(un._boat_time * 2.1 + 9003.0 * 1.7) \
		* 44.0 * 0.07
	_check(absf(un._boat.position.y - expect_bob) < 0.01,
		"boat: bob matches the HTML formula")
	var expect_rock: float = sin(un._boat_time * 1.3 + 9003.0 * 2.3) * 0.045
	_check(absf(un._boat.rotation - expect_rock) < 0.0001,
		"boat: rock matches the HTML formula")
	# No facing flip on boats (HTML never flips hulls).
	un.position.x += 10.0
	un._process(0.1)
	_check(un._sprite.flip_h == false,
		"boat: hull never flips while sailing")
	# Pennant is a fluttering triangle with 3 points.
	_check(un._pennant.polygon.size() == 3,
		"boat: pennant is a triangle")
	_check(un._pennant.color.to_html(false).to_lower() == "2e7d32",
		"boat: elf pennant is the elf accent")
	# Pennant tip x matches HTML: fx = bw*0.18, tip at fx + s*0.5.
	var pts: PackedVector2Array = un._pennant.polygon
	_check(absf(pts[1].x - (un._boat_w * 0.18 + 44.0 * 0.5)) < 0.01,
		"boat: pennant geometry matches the HTML")
	un.queue_free()


## Pennant flutter animates (fy has the sin(t*6+uid)*1.5 term).
func _test_pennant() -> void:
	var un := _make_boat(9004, "undead", "war_ship")
	un._process(0.1)
	var y0: float = un._pennant.polygon[0].y
	un._process(0.3)
	var y1: float = un._pennant.polygon[0].y
	_check(absf(y1 - y0) > 0.001, "boat: pennant flutters over time")
	_check(un._pennant.color.to_html(false).to_lower() == "37474f",
		"boat: undead pennant is the undead accent")
	un.queue_free()


## Regular units are untouched by the boat branch.
func _test_non_boat_unaffected() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(9005, "gnomes", "worker", Vector2(400, 300), "m")
	_check(un._boat == null, "boat: worker has no boat wrapper")
	_check(un._pennant == null, "boat: worker has no pennant")
	_check(un._boat_w == 0.0, "boat: worker hull width is zero")
	_check(absf(un._shadow_footprint() - 44.0 * 0.75) < 0.01,
		"boat: worker shadow footprint unchanged")
	un.queue_free()


## Boats are not humanoid: no limb-stump overlays on hulls.
func _test_boat_no_limb_stumps() -> void:
	var un := _make_boat(9007, "ogres", "war_ship")
	un.set_limb_state({"leftArm": false, "rightArm": true,
		"leftLeg": true, "rightLeg": true})
	_check(un._limb_overlay == null,
		"boat: war_ship never gets limb-stump overlays")
	un.queue_free()


## Boat <-> non-boat job swaps rebuild the visual subtree cleanly.
func _test_set_job_rebuild() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(9006, "gnomes", "worker", Vector2(400, 300), "m")
	un.set_job("war_ship")
	_check(un._boat != null, "boat: worker -> war_ship builds the boat")
	_check(un._sprite != null and un._sprite.texture != null,
		"boat: war_ship sprite has hull texture after set_job")
	un.set_job("worker")
	_check(un._boat == null, "boat: war_ship -> worker tears down the boat")
	_check(un._sprite != null and un._sprite.texture != null,
		"boat: worker chibi sprite restored after set_job")
	un.set_job("worker")
	_check(un._boat == null, "boat: same-job set_job is a no-op")
	un.queue_free()
