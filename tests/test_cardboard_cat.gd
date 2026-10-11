extends SceneTree
## Cursing Gnomes — Cardboard Cat disaster art tests.
##
## Wake graphics-hourly 2026-10-08: the Cardboard Cat ("Real Cat" disaster)
## was the LAST named disaster with no art mapping — it rendered as a
## plain citizen chibi (placeholder visuals, against the standing "good
## graphics everywhere" rule). It now has AI-generated chibi pixel-art
## (cat sitting in a cardboard box) wired through the monster-texture path.
##
## Covers:
##   - _monster_texture() resolves real art for cardboard_cat (never null)
##   - full node setup: the sprite carries the monster art, not the
##     worker/chibi fallback, and is grounded (feet at the Body origin)
##   - _monster_scale() pinned at 0.9 x SPRITE_WORLD_H
##   - disaster-art coverage sweep: every named disaster kind renders
##     something intentional — a mapped texture, the JesusArt sprite, or
##     the Giant Ass procedural build — never the citizen fallback
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_cardboard_cat.gd
##
## Exit code 0 = all passed, 1 = any failure.


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


func _make_node(p_job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(700 + _passed, "gnomes", p_job, Vector2(100, 100), "m")
	return un


func _initialize() -> void:
	print("=== Cursing Gnomes Cardboard Cat art tests ===")
	_test_texture_resolves()
	_test_full_setup()
	_test_scale_pinned()
	_test_all_disasters_have_art()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_texture_resolves() -> void:
	var un := _make_node("worker")
	un.job = "cardboard_cat"
	var tex: Texture2D = un._monster_texture()
	_check("cardboard_cat monster texture resolves", tex != null)
	_check("cardboard_cat texture has size",
		tex != null and tex.get_width() > 0 and tex.get_height() > 0)
	un.free()


func _test_full_setup() -> void:
	var un := _make_node("cardboard_cat")
	var want: Texture2D = un._monster_texture()
	_check("cardboard_cat: sprite built", un._sprite != null)
	_check("cardboard_cat: sprite carries monster art (not citizen fallback)",
		un._sprite != null and un._sprite.texture != null \
		and un._sprite.texture == want)
	# Grounded: feet at the Body origin (same convention as other monsters).
	var h: float = un._monster_scale()
	_check("cardboard_cat: grounded sprite position",
		un._sprite != null and is_equal_approx(un._sprite.position.y, -h * 0.48))
	un.free()


func _test_scale_pinned() -> void:
	var un := _make_node("worker")
	un.job = "cardboard_cat"
	_check("cardboard_cat scale = 0.9 x SPRITE_WORLD_H",
		is_equal_approx(un._monster_scale(), UnitNode.SPRITE_WORLD_H * 0.9))
	un.free()


func _test_all_disasters_have_art() -> void:
	# Every named disaster kind must render something intentional.
	var textured := ["thicc_moose", "giant_lizard", "hoa_karen",
		"seagull_swarm", "taxman", "booze_ooze", "doom_prophet",
		"gig_gnome", "count_bastard", "rogue_wizard", "cardboard_cat"]
	for j: String in textured:
		var un := _make_node("worker")
		un.job = j
		_check("art resolves: " + j, un._monster_texture() != null)
		un.free()
	# jesus: hand-authored JesusArt sprite (image gen declined the request).
	var ju := _make_node("jesus")
	_check("jesus: sprite built from JesusArt",
		ju._sprite != null and ju._sprite.texture != null)
	ju.free()
	# giant_ass: intentional procedural build (the joke is the shape).
	var ga := _make_node("giant_ass")
	var has_poly := false
	for c: Node in ga._body.get_children():
		if c is Polygon2D:
			has_poly = true
	_check("giant_ass: procedural polygon built", has_poly)
	ga.free()
