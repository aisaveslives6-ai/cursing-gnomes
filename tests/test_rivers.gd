extends SceneTree
## Cursing Gnomes — rivers & waterfalls visual-overhaul tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_rivers.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: river carving (banks clear of starts), flow field, waterfall
## placement + spread, rapids, baked depth/foam/banks, the RiverRenderer
## (falls nodes, pooled foam spawning), and fishing-dock water rules.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _frame: int = 0
var _map: Dictionary = {}
var _rivers: RiverRenderer = null


func _initialize() -> void:
	print("=== Cursing Gnomes river tests ===")
	_map = MapGen.new().generate(["humans", "ogres", "elves", "gnomes"], 42)
	_test_river_carving()
	_test_flow_field()
	_test_waterfalls()
	_test_waterfall_grounding()
	_test_rapids()
	_test_bake()
	_test_banks_and_foam()
	_test_depth_gradient()
	_test_nearest_water()
	_test_fishing_dock_rules()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_test_renderer()
		print("=== %d passed, %d failed ===" % [_passed, _failed])
		for f: String in _failures:
			print("  FAIL: ", f)
		if _rivers != null:
			_rivers.queue_free()
		quit(1 if _failed > 0 else 0)
		return true
	return false


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _river_tiles() -> Array:
	var terrain: PackedByteArray = _map["terrain"]
	var out: Array = []
	for i in terrain.size():
		if terrain[i] == MapGen.TILE_RIVER:
			out.append(Vector2i(i % 128, i / 128))
	return out


## Rivers exist, are numerous, and stay out of faction start clear zones
## (same tile-distance convention the generator uses).
func _test_river_carving() -> void:
	var rt: Array = _river_tiles()
	_check("rivers carved (>40 tiles)", rt.size() > 40)
	_check("river tile budget respected", rt.size() <= 2400)
	var starts: Dictionary = _map["faction_starts"]
	var st: Array = []
	for f in starts:
		var sp: Vector2 = starts[f]
		st.append(Vector2i(int(sp.x / 32.0), int(sp.y / 32.0)))
	var bad := 0
	for t: Vector2i in rt:
		for s: Vector2i in st:
			var dx: int = t.x - s.x
			var dy: int = t.y - s.y
			if dx * dx + dy * dy <= 100:
				bad += 1
				break
	_check("rivers clear of starts", bad == 0)


## Every carved river tile carries a normalized downhill direction.
func _test_flow_field() -> void:
	var flow: Dictionary = _map["river_flow"]
	_check("flow field exists", flow.size() > 40)
	var rt: Array = _river_tiles()
	var with_flow := 0
	var bad_len := 0
	for t: Vector2i in rt:
		if flow.has(t):
			with_flow += 1
			var d: Vector2 = flow[t]
			if absf(d.length() - 1.0) > 0.02:
				bad_len += 1
	_check("flow covers river tiles (>=95%)", with_flow >= int(rt.size() * 0.95))
	_check("flow dirs are unit length", bad_len == 0)


## Waterfalls: exist, sit on waterfall tiles, face downstream, spread out.
func _test_waterfalls() -> void:
	var falls: Array = _map["waterfalls"]
	_check("waterfalls exist", falls.size() >= 1)
	_check("waterfall cap respected", falls.size() <= 8)
	var gen := MapGen.new()
	var ok := true
	for w in falls:
		if gen.tile_at(_map, w["position"]) != MapGen.TILE_WATERFALL:
			ok = false
		if absf((w["dir"] as Vector2).length() - 1.0) > 0.02:
			ok = false
	_check("waterfalls on waterfall tiles, dirs unit", ok)
	# Spread: no two waterfalls within 6 tiles (FALL_MIN_SEPARATION).
	var spread := true
	for i in falls.size():
		for j in range(i + 1, falls.size()):
			var a: Vector2 = falls[i]["position"]
			var b: Vector2 = falls[j]["position"]
			if a.distance_to(b) < 6.0 * 32.0:
				spread = false
	_check("waterfalls spread apart", spread)
	# Jeremy 2026-10-05 (launch readiness): each waterfall exports its real
	# level drop; the renderer hangs a screen-vertical sheet from the lip to
	# the plunge pool (HTML CLIFFART84/RIVER92 language), never a flat stripe.
	var drop_ok := true
	for w in falls:
		var d: int = int(w.get("drop", 0))
		if d < 1:
			drop_ok = false
		var fh: float = RiverRenderer.face_height_for(float(d))
		if fh < 60.0 or fh > 170.0:
			drop_ok = false
	_check("waterfalls export drop>=1, sane sheet heights", drop_ok)


## Waterfall grounding (Jeremy 2026-10-05, launch readiness — "nothing
## floating"): the old renderer painted a fixed 104px stripe flat along the
## flow dir, so faces overshot the real drop and poured over arbitrary
## downstream terrain. Regression coverage: the base (downstream) tile is
## never sea, so every falls has solid landing terrain under it.
func _test_waterfall_grounding() -> void:
	var falls: Array = _map["waterfalls"]
	var terrain: PackedByteArray = _map["terrain"]
	var ts: float = float(_map["tile_size"])
	var base_ok := true
	for w in falls:
		var pos: Vector2 = w["position"]
		var d: Vector2 = w["dir"]
		var t := Vector2i(int(pos.x / ts), int(pos.y / ts))
		var nxt := Vector2i(t.x + int(round(d.x)), t.y + int(round(d.y)))
		if nxt.x < 0 or nxt.y < 0 or nxt.x >= 128 or nxt.y >= 128:
			base_ok = false
			continue
		# OCEAN80: never a waterfall into the sea / over the shoreline.
		if terrain[nxt.y * 128 + nxt.x] == MapGen.TILE_WATER:
			base_ok = false
	_check("waterfall base tile never sea", base_ok)


## Rapids: foam-fleck spawn points on steep river tiles with real flow.
func _test_rapids() -> void:
	var rapids: PackedVector2Array = _map["rapids"]
	_check("rapids exist", rapids.size() > 0)
	_check("rapids cap respected", rapids.size() <= 48)
	var rr := RiverRenderer.new()
	rr.setup(_map, null)  # null sprite: skips the flow shader, keeps data
	var ok := true
	for rp in rapids:
		if rr.flow_at(rp).length() < 0.5:
			ok = false
			break
	rr.free()
	_check("rapids sit on flowing water", ok)


## Bake dimensions and formats the renderer/shader consume.
func _test_bake() -> void:
	var img: Image = _map["terrain_image"]
	_check("bake is 512x512", img.get_width() == 512 and img.get_height() == 512)
	var mask: Image = _map["water_mask"]
	_check("water mask is 512x512 RGBA8 (R=depth, G=biome)",
		mask.get_width() == 512 and mask.get_height() == 512 \
		and mask.get_format() == Image.FORMAT_RGBA8)
	var ripple: Texture2D = _map["ripple_tex"]
	_check("ripple texture 128x128", ripple != null \
		and ripple.get_width() == 128 and ripple.get_height() == 128)


## The bake actually shows carved banks: wet-sand darkening that fades with
## distance from the waterline, and near-white foam froth at the waterline
## (patchy — water still shows through).
func _test_banks_and_foam() -> void:
	var img: Image = _map["terrain_image"]
	var terrain: PackedByteArray = _map["terrain"]
	# A sand tile next to water, and a (non-falls) water tile next to sand.
	var sand_t := Vector2i(-1, -1)
	var water_t := Vector2i(-1, -1)
	for ty in 128:
		for tx in 128:
			var t: int = terrain[ty * 128 + tx]
			var adj_water := false
			var adj_sand := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := Vector2i(tx + d.x, ty + d.y)
				if n.x < 0 or n.y < 0 or n.x >= 128 or n.y >= 128:
					continue
				var nt: int = terrain[n.y * 128 + n.x]
				if MapGen.is_water(nt):
					adj_water = true
				if nt == MapGen.TILE_SAND:
					adj_sand = true
			if t == MapGen.TILE_SAND and adj_water and sand_t.x < 0:
				sand_t = Vector2i(tx, ty)
			if (t == MapGen.TILE_WATER or t == MapGen.TILE_RIVER) \
					and adj_sand and water_t.x < 0:
				water_t = Vector2i(tx, ty)
	_check("sand-next-to-water tile exists", sand_t.x >= 0)
	_check("water-next-to-sand tile exists", water_t.x >= 0)
	if sand_t.x < 0 or water_t.x < 0:
		return
	# Bank band: sand darkens toward the water and the darkening fades
	# across the tile (a gradient, not flat fill).
	var darkest := 1.0
	var lightest := 0.0
	for oy in 4:
		for ox in 4:
			var c: Color = img.get_pixel(sand_t.x * 4 + ox, sand_t.y * 4 + oy)
			darkest = minf(darkest, c.r)
			lightest = maxf(lightest, c.r)
	_check("wet-sand bank band near water", darkest < 0.76 - 0.02)
	_check("bank band fades with distance", lightest - darkest > 0.03)
	# Foam: near-white froth at the waterline, with water showing through.
	var foamy := 0
	var watery := 0
	for oy in 4:
		for ox in 4:
			var c2: Color = img.get_pixel(water_t.x * 4 + ox, water_t.y * 4 + oy)
			if c2.r > 0.88 and c2.g > 0.90 and c2.b > 0.90:
				foamy += 1
			else:
				watery += 1
	_check("foam froth at waterline", foamy > 0)
	_check("water not entirely foam", watery > 0)


## Water depth is a gradient (shallow edges, deep centers), not flat fill.
func _test_depth_gradient() -> void:
	var mask: Image = _map["water_mask"]
	var rt: Array = _river_tiles()
	var lo := 1.0
	var hi := 0.0
	for t: Vector2i in rt:
		var d: float = mask.get_pixel(t.x * 4 + 2, t.y * 4 + 2).r
		lo = minf(lo, d)
		hi = maxf(hi, d)
	_check("depth gradient exists (shallow + deep)", lo < 0.5 and hi > 0.7)


## nearest_water_tile: finds water, reports none when there is none.
func _test_nearest_water() -> void:
	var falls: Array = _map["waterfalls"]
	_check("waterfalls available for lookup", falls.size() > 0)
	if falls.is_empty():
		return
	var wpos: Vector2 = falls[0]["position"]
	var found: Vector2i = MapGen.nearest_water_tile(_map, wpos, 0)
	_check("finds water under a waterfall",
		found != Vector2i(-1, -1) \
		and MapGen.is_water((_map["terrain"] as PackedByteArray)[found.y * 128 + found.x]))
	var none: Vector2i = MapGen.nearest_water_tile(_map, Vector2(-1000, -1000), 5)
	_check("no water off-map -> (-1,-1)", none == Vector2i(-1, -1))


## fishing_dock registry + near-water rule (enforced by the placement ghost).
func _test_fishing_dock_rules() -> void:
	_check("fishing_dock is a building", SimBuildings.is_building("fishing_dock"))
	_check("fishing_dock requires water", SimBuildings.requires_water("fishing_dock"))
	_check("house does not require water", not SimBuildings.requires_water("house"))


## The renderer builds: flow shader on the terrain, one falls node per
## waterfall, and the foam pool spawns flecks/bursts/rings/mist.
func _test_renderer() -> void:
	_rivers = RiverRenderer.new()
	root.add_child(_rivers)
	var sprite := Sprite2D.new()
	var img: Image = _map["terrain_image"]
	sprite.texture = ImageTexture.create_from_image(img)
	_rivers.setup(_map, sprite)
	_check("flow shader applied",
		sprite.material != null and sprite.material is ShaderMaterial)
	var falls: Array = _map["waterfalls"]
	_check("one falls node per waterfall", _rivers.falls_count() == falls.size())
	_check("flow_at waterfall is downstream",
		_rivers.flow_at(falls[0]["position"]).length() > 0.5)
	_check("flow_at grass is zero",
		_rivers.flow_at((_map["faction_starts"] as Dictionary)["humans"]) \
			== Vector2.ZERO)
	# Simulate one second: every waterfall should have puffed flecks.
	_rivers._process(1.0)
	var counts: Dictionary = _rivers._foam.debug_counts()
	_check("foam flecks spawn at waterfalls",
		int(counts["flecks"]) >= falls.size() * 3)
	_check("bursts + rings + mist fire",
		int(counts["bursts"]) + int(counts["rings"]) + int(counts["mist"]) > 0)
	# Flecks drift downstream along the flow field, not in place.
	_rivers._process(2.0)
	var counts2: Dictionary = _rivers._foam.debug_counts()
	_check("foam pool keeps spawning (no stall)",
		int(counts2["flecks"]) > 0)
	# A fleck spawned with a known velocity actually moves with it.
	# (Untyped on purpose: inner-class pool members resolve dynamically.)
	var foam = _rivers._foam
	foam.spawn_fleck(Vector2(100, 100), Vector2(40, 0))
	var fleck: Dictionary = {}
	for s in foam._flecks:
		if float(s["age"]) < float(s["life"]) \
				and (s["p"] as Vector2).distance_to(Vector2(100, 100)) < 1.0:
			fleck = s
			break
	_check("test fleck spawned", not fleck.is_empty())
	if not fleck.is_empty():
		var bx: float = (fleck["p"] as Vector2).x
		foam._process(1.0)
		_check("flecks drift with velocity",
			(fleck["p"] as Vector2).x - bx > 20.0)
	# Grounding: every falls node sits exactly on its exported waterfall
	# position (the lip tile's ground) — never offset into the air.
	var fnodes: Array = []
	for c in _rivers.get_children():
		if c.get("_w") != null:  # _FallsNode only; skips the _FoamLayer
			fnodes.append(c)
	var grounded := fnodes.size() == falls.size()
	for i in mini(fnodes.size(), falls.size()):
		var np: Vector2 = (fnodes[i] as Node2D).position
		var ep: Vector2 = falls[i]["position"]
		if np.distance_to(ep) > 1.0:
			grounded = false
	_check("falls nodes grounded on lip tiles", grounded)
