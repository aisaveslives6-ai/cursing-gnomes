extends SceneTree
## Cursing Gnomes — Wind Waker water redo tests (Jeremy 2026-10-10 art order).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_windwaker_water.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: the baked 128px tileable spiral-curl tile (size, format, value
## range, non-trivial, deterministic, seed-sensitive, seam-tileable), the
## curl_tex map_data key from a real generate(), the rewritten water shader
## (curl uniforms, old sine-train motif gone, net-zero texture-sample
## budget), the RiverRenderer uniform wiring incl. the old-map_data neutral
## fallback, and the water_mask R-channel depth contract.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _map: Dictionary = {}


func _initialize() -> void:
	print("=== Cursing Gnomes Wind Waker water tests ===")
	_test_curl_tile_bake()
	_test_curl_tileable()
	_map = MapGen.new().generate(["humans", "ogres", "elves", "gnomes"], 42)
	_test_map_data_key()
	_test_mask_contract()
	_test_shader()
	_test_uniform_wiring()
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


## The baked curl tile: 128x128 R8, values 0..1, non-trivial, deterministic.
func _test_curl_tile_bake() -> void:
	var tile: Image = MapGen._bake_curl_tile(4242)
	_check("curl tile 128x128", tile.get_width() == 128 and tile.get_height() == 128)
	_check("curl tile R8", tile.get_format() == Image.FORMAT_R8)
	var lo := 1.0
	var hi := 0.0
	for yy in 128:
		for xx in 128:
			var v: float = tile.get_pixel(xx, yy).r
			lo = minf(lo, v)
			hi = maxf(hi, v)
	_check("curl values in 0..1", lo >= 0.0 and hi <= 1.0)
	_check("curl tile non-trivial (has crests + troughs)",
		hi > 0.75 and lo < 0.45 and (hi - lo) > 0.3)
	var again: Image = MapGen._bake_curl_tile(4242)
	_check("curl tile deterministic (same seed -> identical bytes)",
		tile.get_data() == again.get_data())
	var other: Image = MapGen._bake_curl_tile(4243)
	_check("curl tile seed-sensitive",
		tile.get_data() != other.get_data())


## Seam property: f(1.0, v) == f(0.0, v) and f(u, 1.0) == f(u, 0.0) — the
## tile repeats seamlessly when the shader scrolls it with repeat_enable.
func _test_curl_tileable() -> void:
	var centers: Array[Vector2] = MapGen._curl_centers(777)
	var worst := 0.0
	for t in [0.0, 0.13, 0.37, 0.61, 0.89, 0.999]:
		var du: float = absf(MapGen._curl_value(0.0, t, centers)
			- MapGen._curl_value(1.0, t, centers))
		var dv: float = absf(MapGen._curl_value(t, 0.0, centers)
			- MapGen._curl_value(t, 1.0, centers))
		worst = maxf(worst, maxf(du, dv))
	_check("curl field tileable across both seams", worst < 0.0001)


## generate() carries curl_tex as a real 128x128 texture.
func _test_map_data_key() -> void:
	_check("map_data has curl_tex", _map.has("curl_tex"))
	if not _map.has("curl_tex"):
		return
	var tex: Texture2D = _map["curl_tex"] as Texture2D
	_check("curl_tex is a texture", tex != null)
	if tex == null:
		return
	_check("curl_tex 128x128", tex.get_width() == 128 and tex.get_height() == 128)


## The water_mask R-channel depth contract is unchanged by the redo.
func _test_mask_contract() -> void:
	_check("map_data has water_mask", _map.has("water_mask"))
	if not _map.has("water_mask"):
		return
	var mask: Image = _map["water_mask"] as Image
	_check("water_mask is an image", mask != null)
	if mask == null:
		return
	var land := 0
	var deep := 0
	var w: int = mask.get_width()
	var h: int = mask.get_height()
	for yy in range(0, h, 8):
		for xx in range(0, w, 8):
			var d: float = mask.get_pixel(xx, yy).r
			if d < 0.01:
				land += 1
			if d > 0.5:
				deep += 1
	_check("water_mask still grades land -> deep", land > 0 and deep > 0)


## The rewritten shader: curl uniforms in, old sine-train motif out,
## net-zero texture-sample budget (7 fetches, same as before).
func _test_shader() -> void:
	var sh: Shader = load("res://assets/shaders/water_flow.gdshader") as Shader
	_check("water shader loads", sh != null)
	if sh == null:
		return
	var code: String = sh.code
	_check("shader declares curl_tex", code.find("uniform sampler2D curl_tex") >= 0)
	_check("shader keeps night_factor", code.find("night_factor") >= 0)
	_check("shader keeps water_mask + flow_tex",
		code.find("water_mask") >= 0 and code.find("flow_tex") >= 0)
	_check("old sine-train motif gone",
		code.find("Two interfering wave trains") < 0
		and code.find("ripple_tex, ruv1") < 0)
	_check("water path samples curl twice",
		code.count("texture(curl_tex") == 2)
	_check("water path no longer samples ripple",
		code.count("texture(ripple_tex") == 0)
	_check("net-zero texture-sample budget (7 fetches)",
		code.count("texture(") == 7)
	_check("has animated lapping foam", code.find("lapping foam") >= 0)
	_check("has curl-crest whitecaps",
		code.find("Whitecaps ride the curl crests") >= 0)


## RiverRenderer wires curl_tex with the old-map_data guard; maps without
## it get a neutral mid-gray fallback instead of unbound-sampler white.
func _test_uniform_wiring() -> void:
	var rr := RiverRenderer.new()
	var sprite := Sprite2D.new()
	rr._apply_flow_shader(_map, sprite)
	var mat := sprite.material as ShaderMaterial
	_check("flow shader material applied", mat != null)
	if mat == null:
		rr.free()
		sprite.free()
		return
	_check("curl_tex wired from map_data",
		mat.get_shader_parameter("curl_tex") == _map["curl_tex"])
	# Old map_data without curl_tex: no crash, neutral fallback.
	var old_map: Dictionary = _map.duplicate()
	old_map.erase("curl_tex")
	var sprite2 := Sprite2D.new()
	rr._apply_flow_shader(old_map, sprite2)
	var mat2 := sprite2.material as ShaderMaterial
	_check("old map_data still applies", mat2 != null)
	if mat2 != null:
		var fb: Texture2D = mat2.get_shader_parameter("curl_tex") as Texture2D
		_check("neutral fallback is a 1x1 tile",
			fb != null and fb.get_width() == 1 and fb.get_height() == 1)
	rr.free()
	sprite.free()
	sprite2.free()
