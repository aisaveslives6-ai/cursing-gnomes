extends SceneTree
## Cursing Gnomes — hurt-flash white silhouette tests (2026-10-05).
##
## Port of the HTML's chibiWhite hurt flash (fix79 index.html:39034, _hurtT
## set on damage at :35279): on every survived hit the sim sets
## combat_state="hurt", the world sync edge-triggers UnitNode.play_hurt(),
## and a white silhouette overlays the unit for 0.45 s at HTML-verbatim
## alpha min(0.75, _hurtT * 2.2), hidden at/below the 0.01 cutoff.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hurt_flash.gd
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
	print("=== Cursing Gnomes hurt-flash tests ===")
	_test_shader_exists()
	_test_play_hurt_arms_timer()
	_test_flash_visible_after_hit()
	_test_alpha_html_verbatim()
	_test_hides_at_cutoff()
	_test_decay_hides()
	_test_flash_mirrors_sprite()
	_test_hurt_anim_still_plays()
	_test_giant_ass_no_flash_no_crash()
	_test_boat_gets_flash()
	_test_rebuild_resets_flash()
	_test_sneak_modulate_untouched()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _make_unit(uid: int, job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(uid, "gnomes", job, Vector2(100, 200), "m")
	return un


func _flash_alpha(un: UnitNode) -> float:
	return float(un._flash_mat.get_shader_parameter("flash_alpha"))


## The shader file ships with the game.
func _test_shader_exists() -> void:
	var f := FileAccess.open(
		"res://assets/shaders/hurt_flash.gdshader", FileAccess.READ)
	_check(f != null, "hurt: hurt_flash.gdshader exists on disk")
	if f != null:
		var src := f.get_as_text()
		_check(src.contains("flash_alpha"), "hurt: shader has flash_alpha param")
		_check(src.contains("1.0, 1.0, 1.0"), "hurt: shader outputs white")
		f.close()


## play_hurt() arms the HTML-verbatim 0.45 s timer.
func _test_play_hurt_arms_timer() -> void:
	var un := _make_unit(101, "worker")
	un.play_hurt()
	_check(is_equal_approx(un._hurt_t, 0.45), "hurt: _hurt_t == 0.45 after play_hurt")
	_check(is_equal_approx(un._hurt_t, UnitNode.HURT_FLASH_LEN),
		"hurt: timer equals HURT_FLASH_LEN const")
	un.queue_free()


## The overlay becomes visible the moment the hit lands.
func _test_flash_visible_after_hit() -> void:
	var un := _make_unit(102, "worker")
	_check(un._flash != null, "hurt: flash node built for worker")
	_check(un._flash.visible == false, "hurt: flash hidden while idle")
	un.play_hurt()
	_check(un._flash.visible == true, "hurt: flash visible right after hit")
	un.queue_free()


## Alpha follows the HTML formula min(0.75, _hurtT * 2.2).
func _test_alpha_html_verbatim() -> void:
	var un := _make_unit(103, "worker")
	un.play_hurt()
	# t = 0.45 -> min(0.75, 0.99) = 0.75 (strongest right after the hit).
	_check(is_equal_approx(_flash_alpha(un), 0.75),
		"hurt: alpha 0.75 at full timer (HTML min(0.75, t*2.2))")
	un._hurt_t = 0.2
	un._sync_flash()
	_check(is_equal_approx(_flash_alpha(un), 0.44),
		"hurt: alpha 0.44 at t=0.2 (HTML min(0.75, t*2.2))")
	un.queue_free()


## Below the 0.01 cutoff the overlay hides (HTML: hT > 0.01 draws).
func _test_hides_at_cutoff() -> void:
	var un := _make_unit(104, "worker")
	un.play_hurt()
	un._hurt_t = 0.02
	un._sync_flash()
	_check(un._flash.visible == true, "hurt: still visible at t=0.02")
	un._hurt_t = 0.01
	un._sync_flash()
	_check(un._flash.visible == false, "hurt: hidden at t=0.01 cutoff")
	un._hurt_t = 0.0
	un._sync_flash()
	_check(un._flash.visible == false, "hurt: hidden at t=0")
	un.queue_free()


## _process decays the timer and hides the overlay when it lapses.
func _test_decay_hides() -> void:
	var un := _make_unit(105, "worker")
	un.play_hurt()
	un._process(0.2)
	_check(is_equal_approx(un._hurt_t, 0.25), "hurt: timer decays by delta")
	_check(un._flash.visible == true, "hurt: still visible mid-flash")
	un._process(0.3)
	_check(is_equal_approx(un._hurt_t, 0.0), "hurt: timer clamps at 0")
	_check(un._flash.visible == false, "hurt: hidden after full decay")
	un.queue_free()


## The overlay mirrors the sprite: texture, atlas frame, flip, transform.
func _test_flash_mirrors_sprite() -> void:
	var un := _make_unit(106, "worker")
	un._sprite.flip_h = true
	un._sprite.position = Vector2(3.0, -20.0)
	un._sprite.rotation = 0.1
	un.play_hurt()
	_check(un._flash.texture == un._sprite.texture, "hurt: flash copies texture")
	_check(un._flash.flip_h == true, "hurt: flash copies flip_h")
	_check(un._flash.position == un._sprite.position, "hurt: flash copies position")
	_check(is_equal_approx(un._flash.rotation, 0.1), "hurt: flash copies rotation")
	_check(un._flash.scale == un._sprite.scale, "hurt: flash copies scale")
	_check(un._flash.frame == un._sprite.frame, "hurt: flash copies atlas frame")
	un.queue_free()


## The HURT choreography clip still plays (flash is additive, not a replacement).
func _test_hurt_anim_still_plays() -> void:
	var un := _make_unit(107, "worker")
	un.play_hurt()
	_check(un.anim.state == UnitAnimator.HURT, "hurt: HURT anim state set")
	un.queue_free()


## giant_ass is fully procedural (no sprite): no flash node, no crash.
func _test_giant_ass_no_flash_no_crash() -> void:
	var un := _make_unit(108, "giant_ass")
	_check(un._flash == null, "hurt: giant_ass builds no flash node")
	un.play_hurt()  # must not crash
	_check(is_equal_approx(un._hurt_t, 0.45), "hurt: giant_ass still arms timer")
	_check(un.anim.state == UnitAnimator.HURT, "hurt: giant_ass still plays HURT")
	un._process(0.5)  # decay with no flash node: must not crash
	_check(is_equal_approx(un._hurt_t, 0.0), "hurt: giant_ass timer decays")
	un.queue_free()


## Boats get the flash over the hull (child of the bobbing Boat node).
func _test_boat_gets_flash() -> void:
	var un := _make_unit(109, "fishing_boat")
	_check(un._flash != null, "hurt: boat builds a flash node")
	_check(un._flash.get_parent() == un._boat, "hurt: boat flash is child of Boat")
	un.play_hurt()
	_check(un._flash.visible == true, "hurt: boat flash shows on hit")
	_check(un._flash.texture == un._sprite.texture, "hurt: boat flash copies hull")
	un.queue_free()


## A job rebuild (boat <-> land) drops the old flash and resets the timer.
func _test_rebuild_resets_flash() -> void:
	var un := _make_unit(110, "worker")
	var first_flash: Sprite2D = un._flash
	un.play_hurt()
	un.set_job("fishing_boat")  # boat branch rebuilds _body
	_check(un._flash != first_flash, "hurt: rebuild points at a fresh flash node")
	_check(un._flash.get_parent() == un._boat,
		"hurt: rebuilt flash is parented to the live Boat node")
	_check(is_equal_approx(un._hurt_t, 0.0), "hurt: rebuild resets hurt timer")
	_check(un._flash.visible == false, "hurt: rebuilt flash starts hidden")
	un.queue_free()


## Sneak mode darkens the sprite via modulate; the flash must not fight it.
func _test_sneak_modulate_untouched() -> void:
	var un := _make_unit(111, "worker")
	un.set_sneaking(true)
	_check(un._sprite.modulate == Color(0.55, 0.55, 0.65),
		"hurt: sneak darkens sprite modulate")
	un.play_hurt()
	_check(un._sprite.modulate == Color(0.55, 0.55, 0.65),
		"hurt: flash does not touch sprite modulate")
	_check(un._flash.visible == true, "hurt: flash still shows while sneaking")
	un.queue_free()
