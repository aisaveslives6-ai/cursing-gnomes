extends SceneTree
## Cursing Gnomes — Jesus disaster pixel-art sprite tests.
##
## Jeremy 2026-10-04: the Jesus disaster's flat procedural polygons were
## replaced with hand-authored chibi pixel art (JesusArt: 32x46, 2-frame
## walk strip embedded as base64 PNG). These tests pin the art contract:
## decodes to a 64x46 strip, both frames are real pixel data and differ
## (a genuine 2-frame walk cycle, not a duplicated frame), the signature
## details (halo, ember, shotgun metal) are present, and the UnitNode
## builds Jesus with the textured sprite + frame cycling intact.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_jesus_visual.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


const JesusArtScript := preload("res://scripts/world/jesus_art.gd")

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


func _initialize() -> void:
	print("=== Cursing Gnomes Jesus visual tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_texture_decodes()
	_test_frames_differ()
	_test_signature_pixels()
	_test_unit_node_build()
	_test_walk_frame_cycle()
	print("passed=%d failed=%d" % [_passed, _failed])
	if not _failures.is_empty():
		print("failures: ", _failures)
	quit(1 if _failed > 0 else 0)


func _strip_image() -> Image:
	var tex: Texture2D = JesusArtScript.make_texture()
	if tex == null:
		return null
	return tex.get_image()


func _test_texture_decodes() -> void:
	var tex: Texture2D = JesusArtScript.make_texture()
	_check("make_texture returns a texture", tex != null)
	if tex == null:
		return
	_check("strip is 64x46 (2x 32x46 frames)",
		tex.get_width() == 64 and tex.get_height() == 46)
	var img := _strip_image()
	_check("strip image readable", img != null)
	if img == null:
		return
	var opaque := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				opaque += 1
	_check("figure has real pixel data (>400 opaque px, got %d)" % opaque,
		opaque > 400)


func _test_frames_differ() -> void:
	var img := _strip_image()
	_check("strip image available for frame diff", img != null)
	if img == null:
		return
	var w := JesusArtScript.FRAME_W
	var h := JesusArtScript.FRAME_H
	var diff := 0
	for y in h:
		for x in w:
			var a: Color = img.get_pixel(x, y)
			var b: Color = img.get_pixel(x + w, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) \
					+ absf(a.a - b.a) > 0.05:
				diff += 1
	# Bob + feet swap + hem sway + smoke drift + ember flicker must move
	# more than a handful of pixels, but the frames must stay the same
	# figure (not a wholesale redraw).
	_check("walk frames differ (>30 px, got %d)" % diff, diff > 30)
	_check("walk frames are the same figure (<600 px, got %d)" % diff,
		diff < 600)


## Signature details a viewer must be able to read: gold halo, orange
## ember (cigarette), dark shotgun metal, brown hair.
func _test_signature_pixels() -> void:
	var img := _strip_image()
	_check("strip image available for signature check", img != null)
	if img == null:
		return
	var halo := false
	var ember := false
	var metal := false
	var hair := false
	for y in img.get_height():
		for x in JesusArtScript.FRAME_W:  # frame A only
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if c.r > 0.95 and c.g > 0.78 and c.b < 0.55:
				halo = true
			if c.r > 0.9 and c.g > 0.4 and c.g < 0.55 and c.b < 0.2:
				ember = true
			if c.r < 0.3 and c.g < 0.3 and c.b < 0.3 and c.r > 0.15:
				metal = true
			if c.r > 0.2 and c.r < 0.3 and c.g > 0.12 and c.g < 0.2 \
					and c.b < 0.1:
				hair = true
	_check("gold halo pixels present", halo)
	_check("cigarette ember pixels present", ember)
	_check("shotgun metal pixels present", metal)
	_check("brown hair pixels present", hair)


func _new_jesus_node() -> UnitNode:
	var n := UnitNode.new()
	root.add_child(n)
	n.setup(4242, "gnomes", "jesus", Vector2(100, 100), "m")
	return n


func _test_unit_node_build() -> void:
	var n := _new_jesus_node()
	_check("jesus node has a sprite (not procedural-null)",
		n._sprite != null)
	if n._sprite != null:
		_check("jesus sprite uses the JesusArt texture",
			n._sprite.texture != null)
		_check("jesus sprite has 2 walk frames",
			n._sprite.hframes == 2)
		_check("jesus sprite starts on frame 0", n._sprite.frame == 0)
		_check("jesus sprite scaled to monster height (>1.0)",
			n._sprite.scale.x > 1.0)
	n.queue_free()


func _test_walk_frame_cycle() -> void:
	var n := _new_jesus_node()
	if n._sprite == null:
		_check("walk cycle needs a sprite", false)
		n.queue_free()
		return
	# Fake movement: shift x, then run _process — anim.moving goes true.
	n.position = Vector2(100, 100)
	n._last_px = 90.0  # force dx = 10 on the next _process
	n._last_pos = Vector2(90, 100)  # 2D tracker agrees (2026-10-06:
		# movement is real displacement, not x-only)
	n._process(1.0 / 7.0)
	_check("walking advances to frame 1", n._sprite.frame == 1)
	n._process(1.0 / 7.0)
	_check("walking wraps back to frame 0", n._sprite.frame == 0)
	# Stop: park trackers so displacement == 0, frame must reset to 0.
	n._last_px = n.position.x
	n._last_pos = n.position
	n._process(1.0 / 7.0)
	_check("idle parks on frame 0", n._sprite.frame == 0)
	n.queue_free()
