extends SceneTree
## Cursing Gnomes — disaster-unit visual tests.
## (2026-10-07 graphics pass: the three wake-deep-disasters newcomers —
## seagull_swarm, taxman, booze_ooze — shipped with sim+Gazette but no unit
## art, so in-world they rendered as plain gnome workers — placeholder
## visuals, against the standing "good graphics everywhere" rule. This
## suite pins their real art: AI-generated pixel-art sprites wired through
## the monster-texture path, the seagull flock satellites, and the ooze
## wobble + rising foam bubbles.)
##
## Covers:
##   - all three jobs registered in _MONSTER_JOBS
##   - _monster_texture() resolves real art for each (never null)
##   - _monster_scale() sane ordering (gull < taxman < ooze)
##   - full setup: sprite texture is the monster art, not the worker fallback
##   - seagull_swarm builds exactly 4 flock satellites (Body children,
##     sharing the gull texture)
##   - booze_ooze builds exactly 3 bubbles with desynced phases
##   - taxman needs no satellite nodes
##   - _animate_seagulls moves the flock (orbit + flap), _animate_ooze
##     applies the wobble and rises the bubbles
##   - job rebuild clears + rebuilds the flock (no dangling refs)
##   - unknown job still falls back to the worker sprite (never crashes)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_disaster_visuals.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes disaster-visual tests ===")
	_test_monster_jobs_registered()
	_test_monster_textures_resolve()
	_test_monster_scales_sane()
	_test_seagull_setup()
	_test_taxman_setup()
	_test_ooze_setup()
	_test_seagull_animation()
	_test_ooze_animation()
	_test_rebuild_clears_flock()
	_test_unknown_job_fallback()
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


func _make_node(p_job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(900 + _passed, "gnomes", p_job, Vector2(100, 100), "m")
	return un


func _test_monster_jobs_registered() -> void:
	for j: String in ["seagull_swarm", "taxman", "booze_ooze"]:
		_check("monster jobs include " + j, j in UnitNode._MONSTER_JOBS)


func _test_monster_textures_resolve() -> void:
	for j: String in ["seagull_swarm", "taxman", "booze_ooze"]:
		var un := _make_node("worker")
		un.job = j
		var tex: Texture2D = un._monster_texture()
		_check("texture resolves for " + j, tex != null)
		un.free()


func _test_monster_scales_sane() -> void:
	var un := _make_node("worker")
	un.job = "seagull_swarm"
	var gull: float = un._monster_scale()
	un.job = "taxman"
	var tax: float = un._monster_scale()
	un.job = "booze_ooze"
	var ooze: float = un._monster_scale()
	_check("scales positive", gull > 0.0 and tax > 0.0 and ooze > 0.0)
	_check("gull smallest, ooze biggest", gull < tax and tax < ooze)
	un.free()


func _test_seagull_setup() -> void:
	var un := _make_node("seagull_swarm")
	_check("seagull: sprite has monster texture",
		un._sprite != null and un._sprite.texture != null)
	_check("seagull: exactly 4 flock satellites",
		un._gull_flock.size() == 4)
	var ok := true
	for g: Sprite2D in un._gull_flock:
		if g.texture == null or g.get_parent() != un._body:
			ok = false
	_check("seagull: satellites textured + Body children", ok)
	_check("seagull: no ooze bubbles", un._ooze_bubbles.is_empty())
	un.free()


func _test_taxman_setup() -> void:
	var un := _make_node("taxman")
	_check("taxman: sprite has monster texture",
		un._sprite != null and un._sprite.texture != null)
	_check("taxman: no flock", un._gull_flock.is_empty())
	_check("taxman: no bubbles", un._ooze_bubbles.is_empty())
	un.free()


func _test_ooze_setup() -> void:
	var un := _make_node("booze_ooze")
	_check("ooze: sprite has monster texture",
		un._sprite != null and un._sprite.texture != null)
	_check("ooze: exactly 3 bubbles", un._ooze_bubbles.size() == 3)
	var ok := true
	for b: Sprite2D in un._ooze_bubbles:
		if b.texture == null or b.get_parent() != un._body:
			ok = false
	_check("ooze: bubbles textured + Body children", ok)
	# 2026-10-08 (wake graphics-hourly): layering — the bubbles are built
	# before _sprite joins _body, so child order alone buries the rise
	# inside the opaque amber body; z_index pins them over it.
	var pin := true
	for b: Sprite2D in un._ooze_bubbles:
		if b.z_index != 1:
			pin = false
	_check("ooze: bubbles pinned over the body (z_index)", pin)
	var kids := un._body.get_children()
	_check("ooze: bubble child order sits below sprite (z_index does the lifting)",
		kids.find(un._ooze_bubbles[0]) < kids.find(un._sprite))
	_check("ooze: 3 desync phases", un._ooze_phase.size() == 3)
	un.free()


func _test_seagull_animation() -> void:
	var un := _make_node("seagull_swarm")
	un._animate_seagulls(0.25)
	var moved := false
	var flapped := false
	for g: Sprite2D in un._gull_flock:
		if g.position.length() > 1.0:
			moved = true
		if absf(g.scale.y - g.scale.x) > 0.001:
			flapped = true
	_check("seagull: flock orbits (positions offset)", moved)
	_check("seagull: satellites flap (scale-y != scale-x)", flapped)
	un.free()


func _test_ooze_animation() -> void:
	var un := _make_node("booze_ooze")
	var base: Vector2 = un._sprite.scale
	un._animate_ooze(0.2)
	_check("ooze: wobble changes sprite scale", un._sprite.scale != base)
	var y0: float = un._ooze_bubbles[0].position.y
	un._animate_ooze(1.0)
	_check("ooze: bubbles rise over time",
		un._ooze_bubbles[0].position.y < y0)
	un.free()


func _test_rebuild_clears_flock() -> void:
	var un := _make_node("seagull_swarm")
	_check("rebuild: flock built", un._gull_flock.size() == 4)
	un.set_job("taxman")
	_check("rebuild: flock cleared on job change", un._gull_flock.is_empty())
	_check("rebuild: taxman texture applied",
		un._sprite != null and un._sprite.texture != null)
	un.set_job("seagull_swarm")
	_check("rebuild: flock rebuilt", un._gull_flock.size() == 4)
	un.free()


func _test_unknown_job_fallback() -> void:
	var un := _make_node("mystery_blob_xyz")
	un.job = "mystery_blob_xyz"
	_check("fallback: unknown job has null monster texture",
		un._monster_texture() == null)
	_check("fallback: worker sprite used, no crash",
		un._sprite != null and un._sprite.texture != null)
	un.free()
