extends SceneTree
## Cursing Gnomes — Stardew ground detail + Wind Waker water tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ground_detail.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: baked per-pixel ground variance (no flat tiles), the mask G
## biome-selector channel, the flow-direction texture, the upgraded water
## shader (Wind Waker uniforms), the AI-generated detail overlays (real
## pixels, no baked checkerboard), autotile grass<->sand edge blending,
## carved river banks (inner shadow + dark wet line), and the bright
## Wind Waker water palette.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _map: Dictionary = {}


func _initialize() -> void:
	print("=== Cursing Gnomes ground-detail tests ===")
	_map = MapGen.new().generate(["humans", "ogres", "elves", "gnomes"], 42)
	_test_ground_variance()
	_test_biome_channel()
	_test_flow_texture()
	_test_shader()
	_test_detail_assets()
	_test_autotile_edges()
	_test_carved_rivers()
	_test_ww_palette()
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


## A pure-grass interior region must have real per-pixel variance —
## Stardew texture, not a flat fill.
func _test_ground_variance() -> void:
	var img: Image = _map["terrain_image"]
	var terrain: PackedByteArray = _map["terrain"]
	var gt := Vector2i(-1, -1)
	for ty in range(2, 126):
		for tx in range(2, 126):
			var ok := true
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if terrain[(ty + dy) * 128 + tx + dx] != MapGen.TILE_GRASS:
						ok = false
			if ok:
				gt = Vector2i(tx, ty)
				break
		if gt.x >= 0:
			break
	_check("pure-grass interior tile exists", gt.x >= 0)
	if gt.x < 0:
		return
	var vals: Array[float] = []
	for oy in 4:
		for ox in 4:
			var c: Color = img.get_pixel(gt.x * 4 + ox, gt.y * 4 + oy)
			vals.append(c.g)
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= vals.size()
	var var_sum := 0.0
	for v in vals:
		var_sum += (v - mean) * (v - mean)
	var sd: float = sqrt(var_sum / vals.size())
	_check("grass has per-pixel texture variance", sd > 0.015)


## Mask G channel carries the biome selector: ~0 on grass, ~1 on sand.
func _test_biome_channel() -> void:
	var mask: Image = _map["water_mask"]
	var terrain: PackedByteArray = _map["terrain"]
	var glo := 2.0
	var ghi := -1.0
	var slo := 2.0
	var shi := -1.0
	for i in terrain.size():
		var t: int = terrain[i]
		if t != MapGen.TILE_GRASS and t != MapGen.TILE_SAND:
			continue
		var tx: int = i % 128
		var ty: int = i / 128
		var g: float = mask.get_pixel(tx * 4 + 2, ty * 4 + 2).g
		if t == MapGen.TILE_GRASS:
			glo = minf(glo, g)
			ghi = maxf(ghi, g)
		else:
			slo = minf(slo, g)
			shi = maxf(shi, g)
	_check("grass biome selector near 0", glo < 0.35)
	_check("sand biome selector near 1", shi > 0.65)


## Flow texture: present, 128x128, rivers carry direction + speed.
func _test_flow_texture() -> void:
	_check("flow_tex present", _map.has("flow_tex"))
	if not _map.has("flow_tex"):
		return
	var ft: Texture2D = _map["flow_tex"]
	_check("flow_tex 128x128", ft != null and ft.get_width() == 128 \
		and ft.get_height() == 128)
	if ft == null:
		return
	var fimg: Image = ft.get_image()
	var terrain: PackedByteArray = _map["terrain"]
	var ndir := 0
	var nspd := 0
	var bad := 0
	for i in terrain.size():
		if terrain[i] != MapGen.TILE_RIVER:
			continue
		var tx: int = i % 128
		var ty: int = i / 128
		var c: Color = fimg.get_pixel(tx, ty)
		var d := Vector2(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0)
		if c.b > 0.05:
			nspd += 1
		if c.b > 0.2:
			ndir += 1
			if absf(d.length() - 1.0) > 0.08:
				bad += 1
	_check("river tiles carry flow speed", nspd > 0)
	_check("flow directions are unit-ish", ndir > 0 and bad == 0)


## The upgraded shader parses and exposes the Wind Waker uniforms.
func _test_shader() -> void:
	var sh: Shader = load("res://assets/shaders/water_flow.gdshader") as Shader
	_check("water shader loads", sh != null)
	if sh == null:
		return
	var code: String = sh.code
	_check("shader has flow_tex uniform", code.find("flow_tex") >= 0)
	_check("shader has detail uniforms",
		code.find("detail_grass") >= 0 and code.find("detail_grain") >= 0)
	_check("shader has whitecaps", code.find("cap") >= 0)


## Detail overlays: real files, 64x64, mid-gray centered, no checkerboard.
func _test_detail_assets() -> void:
	for p in ["res://assets/art/ground/detail_grass.png",
			"res://assets/art/ground/detail_grain.png"]:
		var tex: Texture2D = load(p) as Texture2D
		_check("detail asset loads: " + p, tex != null)
		if tex == null:
			continue
		_check("detail asset 64x64: " + p,
			tex.get_width() == 64 and tex.get_height() == 64)
		var im: Image = tex.get_image()
		var white := 0
		var tot := 0
		var sum := 0.0
		for y in range(0, 64, 4):
			for x in range(0, 64, 4):
				var c: Color = im.get_pixel(x, y)
				tot += 1
				sum += c.r
				if c.r > 0.90 and c.g > 0.90 and c.b > 0.90:
					white += 1
		_check("detail centered near mid-gray: " + p, sum / tot > 0.40 \
			and sum / tot < 0.60)
		_check("no baked checkerboard: " + p, white < tot / 4)


## Grass<->sand borders are blended, not hard tile seams.
func _test_autotile_edges() -> void:
	var img: Image = _map["terrain_image"]
	var terrain: PackedByteArray = _map["terrain"]
	var gt := Vector2i(-1, -1)
	var dir := Vector2i(0, 0)
	for ty in 128:
		for tx in 128:
			if terrain[ty * 128 + tx] != MapGen.TILE_GRASS:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := Vector2i(tx + d.x, ty + d.y)
				if n.x < 0 or n.y < 0 or n.x >= 128 or n.y >= 128:
					continue
				if terrain[n.y * 128 + n.x] == MapGen.TILE_SAND:
					gt = Vector2i(tx, ty)
					dir = d
					break
			if gt.x >= 0:
				break
		if gt.x >= 0:
			break
	_check("grass-next-to-sand border exists", gt.x >= 0)
	if gt.x < 0:
		return
	var gc: Color = img.get_pixel(gt.x * 4 + 2, gt.y * 4 + 2)
	var st: Vector2i = gt + dir
	var sc: Color = img.get_pixel(st.x * 4 + 2, st.y * 4 + 2)
	# Edge pixels on the grass side of the border.
	var blended := 0
	for ei in 4:
		var ex: int = gt.x * 4 + (3 if dir.x == 1 else (0 if dir.x == -1 else ei))
		var ey: int = gt.y * 4 + (3 if dir.y == 1 else (0 if dir.y == -1 else ei))
		var ec: Color = img.get_pixel(ex, ey)
		var dg: float = absf(ec.r - gc.r) + absf(ec.g - gc.g) + absf(ec.b - gc.b)
		var ds: float = absf(ec.r - sc.r) + absf(ec.g - sc.g) + absf(ec.b - sc.b)
		# Strictly between the two biome centers = a blend happened.
		if dg > 0.02 and ds > 0.02:
			blended += 1
	_check("border pixels are blended (autotile)", blended > 0)


## Rivers read carved: dark inner shadow at the waterline + bright WW blue.
func _test_carved_rivers() -> void:
	var img: Image = _map["terrain_image"]
	var terrain: PackedByteArray = _map["terrain"]
	var dark := 0
	var bright := 0
	var n := 0
	for i in terrain.size():
		if terrain[i] != MapGen.TILE_RIVER and terrain[i] != MapGen.TILE_WATER:
			continue
		var tx: int = i % 128
		var ty: int = i / 128
		for oy in 4:
			for ox in 4:
				var c: Color = img.get_pixel(tx * 4 + ox, ty * 4 + oy)
				n += 1
				if c.r < 0.18 and c.g < 0.34 and c.b < 0.48:
					dark += 1
				if c.b > 0.55 and c.b > c.r + 0.15:
					bright += 1
	_check("carved inner shadow exists", dark > 0)
	_check("bright Wind Waker blue water", bright > n / 20)


## Wind Waker palette: water is saturated azure, not teal/gray.
func _test_ww_palette() -> void:
	var img: Image = _map["terrain_image"]
	var mask: Image = _map["water_mask"]
	var tot := 0
	var azure := 0
	for y in range(0, 512, 8):
		for x in range(0, 512, 8):
			if mask.get_pixel(x, y).r < 0.5:
				continue
			tot += 1
			var c: Color = img.get_pixel(x, y)
			if c.b > 0.50 and c.b > c.r + 0.12 and c.b >= c.g - 0.05:
				azure += 1
	_check("deep water reads azure", tot > 0 and float(azure) / tot > 0.5)
