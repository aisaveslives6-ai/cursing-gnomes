extends SceneTree
## Cursing Gnomes — terrain climate tests (snow / desert bakes).
##
## The frozen/highlands `snow` and wasteland `desert` world-type mods were
## dead config until the 2026-10-03 graphics pass ported HTML cgGroundRGB's
## climate blends into MapGen._bake_terrain. These tests pin the formulas
## and the visible result on real bakes.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_terrain_climate.gd
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


## HTML cgGroundRGB formula parity, via MapGen.climate_weights().
func _test_formulas() -> void:
	# Frozen lowland, damp: full snow.
	var w1: Vector2 = MapGen.climate_weights(0.35, 0.42, 1.0, 0.0)
	_check("snow full on frozen lowland", is_equal_approx(w1.x, 1.0))
	_check("no desert on frozen lowland", is_equal_approx(w1.y, 0.0))
	# Frozen high dry peak: HTML gives peaks LESS snow (inverse formula).
	var w2: Vector2 = MapGen.climate_weights(0.85, 0.20, 1.0, 0.0)
	_check("snow partial on high peak", w2.x > 0.5 and w2.x < 0.8)
	# No snow configured: weight is zero even on ideal ground.
	var w3: Vector2 = MapGen.climate_weights(0.35, 0.30, 0.0, 0.0)
	_check("no snow when snow_amt=0", is_equal_approx(w3.x, 0.0))
	# Wasteland dry: strong desert; wasteland wet: none.
	var w4: Vector2 = MapGen.climate_weights(0.40, 0.20, 0.0, 0.9)
	_check("desert strong when dry", is_equal_approx(w4.y, 0.9))
	var w5: Vector2 = MapGen.climate_weights(0.40, 0.70, 0.0, 0.9)
	_check("desert zero when wet", is_equal_approx(w5.y, 0.0))
	# No desert configured: weight is zero.
	_check("no desert when desert_amt=0",
		is_equal_approx(MapGen.climate_weights(0.40, 0.20, 0.0, 0.0).y, 0.0))


## Moisture field is tile-resolution and stays in 0..1.
func _test_moisture_field() -> void:
	var mf: PackedFloat32Array = MapGen._moisture_field(7, 3.2, -0.08)
	_check("moisture field covers 128x128 tiles",
		mf.size() == 128 * 128)
	var lo := 999.0
	var hi := -999.0
	for v in mf:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_check("moisture field in 0..1", lo >= 0.0 and hi <= 1.0)
	_check("moisture field has variation", hi - lo > 0.3)


## Sampled land-pixel stats for one baked world.
## Returns [sample_count, mean_brightness, mean_red, near_white_fraction].
## NOTE: keep the image Variant untyped and divide at the call site —
## typed Image locals have returned black pixels in headless probes.
func _bake_stats(wtype: String) -> Array:
	var m: Dictionary = MapGen.new().generate(
		["humans", "ogres", "elves", "gnomes", "undead"], 7, wtype)
	var img = m["terrain_image"]
	var terrain: PackedByteArray = m["terrain"]
	var n := 0
	var bright := 0.0
	var red := 0.0
	var white := 0
	for py in range(0, 512, 16):
		for px in range(0, 512, 16):
			var tx: int = mini(px / 4, 127)
			var ty: int = mini(py / 4, 127)
			if MapGen.is_water(terrain[ty * 128 + tx]):
				continue
			var c: Color = img.get_pixel(px, py)
			n += 1
			bright += (c.r + c.g + c.b) / 3.0
			red += c.r
			if c.r > 0.80 and c.g > 0.82 and c.b > 0.82:
				white += 1
	return [n, bright, red, white]


func _mean(total: float, n: int) -> float:
	return total / maxf(float(n), 1.0)


## Real bakes: frozen reads snowy, wasteland reads arid, continents is the
## green control, highlands sits between (patchy snow, snow=0.35).
func _test_bakes() -> void:
	var fc: Array = _bake_stats("frozen")
	var ct: Array = _bake_stats("continents")
	var wl: Array = _bake_stats("wasteland")
	var hl: Array = _bake_stats("highlands")
	_check("bakes sampled land pixels",
		int(fc[0]) > 500 and int(ct[0]) > 500)
	var fc_white: float = _mean(float(fc[3]), int(fc[0]))
	var ct_white: float = _mean(float(ct[3]), int(ct[0]))
	_check("frozen bake has snow-white land (%.2f)" % fc_white,
		fc_white > 0.15)
	_check("continents bake has no snow-white land (%.2f)" % ct_white,
		ct_white < 0.05)
	var fc_b: float = _mean(float(fc[1]), int(fc[0]))
	var ct_b: float = _mean(float(ct[1]), int(ct[0]))
	_check("frozen bake brighter than continents (%.2f > %.2f)" % [fc_b, ct_b],
		fc_b > ct_b + 0.15)
	var wl_r: float = _mean(float(wl[2]), int(wl[0]))
	var ct_r: float = _mean(float(ct[2]), int(ct[0]))
	_check("wasteland bake redder than continents (%.2f > %.2f)" % [wl_r, ct_r],
		wl_r > ct_r + 0.15)
	var hl_b: float = _mean(float(hl[1]), int(hl[0]))
	_check("highlands bake between continents and frozen (%.2f)" % hl_b,
		hl_b > ct_b and hl_b < fc_b)


func _initialize() -> void:
	print("=== Cursing Gnomes terrain climate tests ===")
	_test_formulas()
	_test_moisture_field()
	_test_bakes()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
