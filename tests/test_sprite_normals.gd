extends SceneTree
## Cursing Gnomes — procedural sprite normal-map tests.
##
## Covers SpriteNormals (scripts/world/sprite_normals.gd): dimension match,
## transparent pixels forced flat (no light halos), opaque-square edge bevel
## tilting outward with a flat center, per-texture caching, oversize skip,
## small-sprite handling, and apply_to() no-op / assignment behavior.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_sprite_normals.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


const SN := preload("res://scripts/world/sprite_normals.gd")

const FLAT := 128.0 / 255.0  # flat normal red/green channel

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes sprite-normal tests ===")
	_test_dims_match()
	_test_transparent_flat()
	_test_square_edges_tilt()
	_test_cache_same_instance()
	_test_oversize_null()
	_test_degenerate_null()
	_test_apply_to_null_texture()
	_test_apply_to_sets_map()
	_test_apply_to_idempotent()
	_test_apply_to_follows_texture_swap()
	_test_diffuse_of()
	_test_small_sprite()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f in _failures:
		print("FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)


func _make_tex(w: int, h: int, fill: Color) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	return ImageTexture.create_from_image(img)


func _px(nm: Texture2D, x: int, y: int) -> Color:
	return nm.get_image().get_pixel(x, y)


func _is_flat(c: Color) -> bool:
	return absf(c.r - FLAT) < 0.02 and absf(c.g - FLAT) < 0.02 \
		and c.b > 0.98 and c.a > 0.98


func _test_dims_match() -> void:
	var tex := _make_tex(48, 64, Color(1, 1, 1, 1))
	var nm: Texture2D = SN.generate(tex)
	_check("dims: normal map returned", nm != null)
	_check("dims: width matches", nm.get_width() == 48)
	_check("dims: height matches", nm.get_height() == 64)


func _test_transparent_flat() -> void:
	var tex := _make_tex(16, 16, Color(0, 0, 0, 0))
	var nm: Texture2D = SN.generate(tex)
	_check("transparent: map returned", nm != null)
	_check("transparent: (0,0) flat", _is_flat(_px(nm, 0, 0)))
	_check("transparent: (7,7) flat", _is_flat(_px(nm, 7, 7)))
	_check("transparent: (15,15) flat", _is_flat(_px(nm, 15, 15)))


func _square_tex() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(8, 8, 16, 16), Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


func _test_square_edges_tilt() -> void:
	var nm: Texture2D = SN.generate(_square_tex())
	_check("square: map returned", nm != null)
	# Center of the solid square: flat.
	_check("square: center flat", _is_flat(_px(nm, 16, 16)))
	# Edge pixels tilt outward (away from the silhouette).
	_check("square: left edge tilts -x", _px(nm, 8, 16).r < 0.45)
	_check("square: right edge tilts +x", _px(nm, 23, 16).r > 0.55)
	_check("square: top edge tilts -y", _px(nm, 16, 8).g < 0.45)
	_check("square: bottom edge tilts +y", _px(nm, 16, 23).g > 0.55)
	# Transparent pixels hugging the silhouette stay flat: no light halos.
	_check("halo: transparent left of edge flat", _is_flat(_px(nm, 7, 16)))
	_check("halo: transparent above edge flat", _is_flat(_px(nm, 16, 7)))


func _test_cache_same_instance() -> void:
	var tex := _make_tex(24, 24, Color(1, 1, 1, 1))
	var a: Texture2D = SN.generate(tex)
	var b: Texture2D = SN.generate(tex)
	_check("cache: same instance returned", a == b and a != null)


func _test_oversize_null() -> void:
	var tex := _make_tex(300, 200, Color(1, 1, 1, 1))
	_check("oversize: returns null", SN.generate(tex) == null)
	# Oversize result is cached too (no repeated cost).
	_check("oversize: cached null", SN.generate(tex) == null)


func _test_degenerate_null() -> void:
	_check("degenerate: null texture -> null", SN.generate(null) == null)


func _test_apply_to_null_texture() -> void:
	var sp := Sprite2D.new()
	SN.apply_to(sp)  # must not crash
	_check("apply_to: null texture leaves texture null",
		sp.texture == null)
	sp.free()


func _wrap_of(sp: Sprite2D) -> CanvasTexture:
	if sp.texture is CanvasTexture:
		return sp.texture as CanvasTexture
	return null


func _test_apply_to_sets_map() -> void:
	var sp := Sprite2D.new()
	sp.texture = _make_tex(24, 24, Color(1, 1, 1, 1))
	SN.apply_to(sp)
	var ct := _wrap_of(sp)
	_check("apply_to: texture wrapped in CanvasTexture", ct != null)
	_check("apply_to: normal_texture set",
		ct != null and ct.normal_texture != null)
	_check("apply_to: normal dims match diffuse",
		ct != null and ct.normal_texture.get_width() == 24 \
		and ct.normal_texture.get_height() == 24)
	_check("apply_to: diffuse preserved",
		ct != null and ct.diffuse_texture != null \
		and ct.diffuse_texture.get_width() == 24)
	sp.free()


func _test_apply_to_idempotent() -> void:
	var sp := Sprite2D.new()
	sp.texture = _make_tex(24, 24, Color(1, 1, 1, 1))
	SN.apply_to(sp)
	var first: Texture2D = sp.texture
	SN.apply_to(sp)
	_check("apply_to: second call keeps same wrap", sp.texture == first)
	sp.free()


func _test_apply_to_follows_texture_swap() -> void:
	var sp := Sprite2D.new()
	sp.texture = _square_tex()
	SN.apply_to(sp)
	var first: Texture2D = sp.texture
	sp.texture = _make_tex(32, 32, Color(1, 1, 1, 1))
	SN.apply_to(sp)
	var ct := _wrap_of(sp)
	_check("apply_to: texture swap rebuilds wrap",
		ct != null and sp.texture != first)
	_check("apply_to: new wrap carries new diffuse",
		ct != null and ct.diffuse_texture.get_width() == 32)
	sp.free()


func _test_diffuse_of() -> void:
	var raw := _make_tex(16, 16, Color(1, 1, 1, 1))
	var sp := Sprite2D.new()
	sp.texture = raw
	SN.apply_to(sp)
	_check("diffuse_of: unwraps to raw texture",
		SN.diffuse_of(sp.texture) == raw)
	_check("diffuse_of: raw passes through", SN.diffuse_of(raw) == raw)
	_check("diffuse_of: null passes through", SN.diffuse_of(null) == null)
	sp.free()


func _test_small_sprite() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(2, 2, 4, 4), Color(1, 1, 1, 1))
	var nm: Texture2D = SN.generate(ImageTexture.create_from_image(img))
	_check("small: 8x8 map returned", nm != null)
	_check("small: dims match", nm.get_width() == 8 and nm.get_height() == 8)
	_check("small: corner transparent flat", _is_flat(_px(nm, 0, 0)))
