class_name MapGen
extends RefCounted
## Cursing Gnomes — procedural world generation (Milestone 2 + rivers).
##
## Pure logic, no nodes: builds terrain tiles, faction starts, trees and
## resource nodes, carves rivers with waterfalls, and bakes terrain + water
## visuals the renderer turns into textures (few draw calls for the map).
##
## generate() returns a Dictionary:
##   size_tiles: Vector2i, tile_size: int, world_size: Vector2
##   terrain: PackedByteArray (row-major, TILE_* ids)
##   terrain_image: Image (baked, BAKE_PX_PER_TILE px per tile)
##   water_mask: Image (FORMAT_RGBA8; R = water depth 0..1, G = ground-detail
##     biome selector 0..1 — drives the flow/detail shader)
##   ripple_tex: ImageTexture (small noise tile the flow shader scrolls)
##   flow_tex: ImageTexture (1 px/tile RGBA8; RG = flow dir, B = flow speed)
##   curl_tex: ImageTexture (128px tileable Wind Waker spiral-curl tile)
##   faction_starts: Dictionary faction_id -> Vector2 (world px)
##   trees: PackedVector2Array (world px)
##   resources: Array of {type: String, position: Vector2}
##   waterfalls: Array of {position: Vector2 (world px), dir: Vector2,
##     drop: int (fall_levels delta, >= 1 — drives the falls face height)}
##   river_flow: Dictionary Vector2i -> Vector2 (downhill dir, tile space)
##   rapids: PackedVector2Array (world px, foam-fleck spawn points)
##
## Rivers are carved downhill from land springs through a dedicated
## elevation field (HTML fix79 parity): watershed paths walk the steepest
## descent from high-elevation grass origins to the coast, terminate at the
## shoreline, and never continue into the ocean (carving stops at the first
## water tile — the river mouth). Each river is one connected path from its
## spring. Waterfalls exist ONLY where the river crosses a real height-level
## change (underlying terrain level drops >= 1 to the downstream tile —
## HTML's CLIFFART84 rule), never into the sea, never onto lowland.
## Old-save sanitation drops orphan flow entries (Godot saves don't persist
## terrain — worlds regenerate from seed — so no legacy river geometry can
## exist in a save). Steepest drops are marked as waterfalls, steep tiles as
## rapids, and depth shading + foam edges + muddy banks bake into the
## terrain texture.


const TILE_GRASS := 0
const TILE_WATER := 1
const TILE_SAND := 2
const TILE_RIVER := 3
const TILE_WATERFALL := 4

const MAP_TILES := 128
## Tile size in world px (set by generate() from size_key; 32 = normal).
var _tile_px := 32.0
const BAKE_PX_PER_TILE := 4  # 512x512 bake, Nearest-filtered up to 4096 px

const WATER_THRESHOLD := -0.22
const START_CLEAR_RADIUS_TILES := 10
const TREE_MIN_START_DIST := 380.0
const MAX_TREES := 700

# River carving.
const RIVER_COUNT := 7
const MAX_RIVER_TILES := 2400
const MAX_RIVER_STEPS := 420
const MAX_WATERFALLS := 8
const FALL_MIN_LAND_ELEV := 0.355  # HTML CLIFFART84: falls land on solid land, not shoreline
const FALL_MIN_SEPARATION := 6  # tiles: waterfalls spread along the rivers
const RAPID_MIN_DROP := 0.028  # descent that reads as rapids
const MAX_RAPIDS := 48

# Cliffs (the Cliffs Update): mountain massifs for the level field.
const MOUNTAIN_RANGES := 3
const ALPINE_TREE_LINE := 5  # no trees at/above this level (bare peaks)

## World sizes: tiles per side (HTML CGWSEL_SIZES parity — world px / 32).
## Mobile 8k, normal 16k, large 24k, huge 32k world px.
const WORLD_SIZES := {
	"mobile": 96,    # Small map for phones. Fast and stable.
	"normal": 128,   # The classic map (was the fixed size).
	"large": 192,    # 2.25x the land (HTML parity).
	"huge": 256,     # 4x the land (HTML parity). Desktop only.
}

## World type modifiers (HTML CGWSEL_TYPES parity).
## elev_f: elevation noise frequency multiplier
## elev_bias: added to elevation noise (negative = more water)
## moist_f: moisture noise frequency multiplier
## moist_bias: added to moisture noise
## lake_mul: water/lake amount multiplier
## tree_mul: tree density multiplier
## mine_mul: resource/mine count multiplier
## snow: 0..1 snow coverage (visual)
## desert: 0..1 desert coverage (visual)
const WTYPE_MODS := {
	"continents": {},
	"archipelago": {"elev_f": 2.2, "elev_bias": -0.06, "lake_mul": 2.2},
	"highlands": {"moist_f": 3.0, "elev_gain": 1.7, "snow": 0.35, "mine_mul": 2.0},
	"wasteland": {"elev_f": 2.4, "moist_bias": -0.22, "desert": 0.9,
		"lake_mul": 0.4, "tree_mul": 0.35},
	"frozen": {"moist_f": 3.2, "moist_bias": -0.08, "snow": 1.0,
		"lake_mul": 0.7, "tree_mul": 0.8},
	"wilds": {"moist_bias": 0.15, "tree_mul": 1.8},
}

## Shaping option multipliers (HTML cgTypeMods61 parity).
const OPT_WATER_MUL := {"low": 0.55, "normal": 1.0, "high": 1.6}
const OPT_FOREST_MUL := {"sparse": 0.5, "normal": 1.0, "dense": 1.7}
const OPT_RES_MUL := {"scarce": 0.5, "normal": 1.0, "abundant": 1.8}

# Bake look (bake-px units; bake is 4 px per tile).
const DEPTH_FULL_PX := 10.0  # shore distance that reads as fully deep
const FOAM_BAND_PX := 2.6    # froth ring at the waterline (patchy wobble)
const BANK_BAND_PX := 6.0    # wet-sand / muddy bank on the land side
# Climate blend targets — HTML cgGroundRGB (fix79) exact values.
const SNOW_C := Color(0.9137, 0.9373, 0.9608)    # (233, 239, 245) icy white
const DESERT_C := Color(0.8392, 0.7294, 0.5020)  # (214, 186, 128) sand


## True for any tile id that is water for gameplay (movement, resources).
static func is_water(t: int) -> bool:
	return t == TILE_WATER or t == TILE_RIVER or t == TILE_WATERFALL


## Nearest water tile center (tile coords) within max_radius_tiles of a world
## position, or Vector2i(-1, -1) when none. Used by fishing-dock placement.
static func nearest_water_tile(map_data: Dictionary, world_pos: Vector2,
		max_radius_tiles: int) -> Vector2i:
	var terrain: PackedByteArray = map_data["terrain"]
	var tpx := float(map_data.get("tile_size", 32.0))
	var ct := Vector2i(int(world_pos.x / tpx), int(world_pos.y / tpx))
	for r in range(max_radius_tiles + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var t := Vector2i(ct.x + dx, ct.y + dy)
				if t.x < 0 or t.y < 0 or t.x >= MAP_TILES or t.y >= MAP_TILES:
					continue
				if is_water(terrain[t.y * MAP_TILES + t.x]):
					return t
	return Vector2i(-1, -1)


## Generates the map for the given factions with a fixed rng seed.
## wtype: world type (continents, archipelago, highlands, wasteland, frozen, wilds)
## size_key: world size (mobile, normal, large, huge)
## opts: shaping options {water, forest, resources, start}
func generate(faction_ids: Array[String], rng_seed: int,
		wtype: String = "continents", size_key: String = "normal",
		opts: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var noise := FastNoiseLite.new()
	noise.seed = rng_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	# Elevation drives rivers only — kept separate from the terrain noise so
	# the land/ocean layout never changes when rivers are tuned.
	var elev := FastNoiseLite.new()
	elev.seed = int(rng_seed) ^ 0x9e3779b9
	elev.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev.frequency = 0.008
	elev.fractal_octaves = 2

	# --- Apply world settings (Jeremy 2026-10-03: settings must do something). ---
	var type_mods: Dictionary = WTYPE_MODS.get(wtype, {})
	var size_tiles: int = WORLD_SIZES.get(size_key, 128)
	# Tile size scales with world size (keeps 128x128 grid, world gets bigger).
	var size_mul := float(size_tiles) / 128.0
	_tile_px = 32.0 * size_mul
	# Option multipliers (HTML cgTypeMods61 parity).
	var water_opt: String = str(opts.get("water", "normal"))
	var forest_opt: String = str(opts.get("forest", "normal"))
	var res_opt: String = str(opts.get("resources", "normal"))
	var lake_mul := float(type_mods.get("lake_mul", 1.0)) \
		* float(OPT_WATER_MUL.get(water_opt, 1.0))
	var tree_mul := float(type_mods.get("tree_mul", 1.0)) \
		* float(OPT_FOREST_MUL.get(forest_opt, 1.0))
	var mine_mul := float(type_mods.get("mine_mul", 1.0)) \
		* float(OPT_RES_MUL.get(res_opt, 1.0))
	# Elevation/moisture modifiers affect terrain noise.
	var elev_f := float(type_mods.get("elev_f", 1.0))
	var elev_bias := float(type_mods.get("elev_bias", 0.0))
	var elev_gain := float(type_mods.get("elev_gain", 1.0))
	# Climate visuals (HTML cgGroundRGB parity): snow whites the ground on
	# frozen/highland worlds, desert tans it on wasteland. These were dead
	# config until the bake below learned to read them (2026-10-03).
	var snow_amt := float(type_mods.get("snow", 0.0))
	var desert_amt := float(type_mods.get("desert", 0.0))
	var moist_f := float(type_mods.get("moist_f", 1.0))
	var moist_bias := float(type_mods.get("moist_bias", 0.0))

	var world_px: float = float(MAP_TILES) * _tile_px

	# --- Faction starts: quadrant centers with jitter, spread apart. ---
	var starts := {}
	# Jeremy 2026-10-03: factions spread in a pentagon — 5 positions,
	# not 4 quadrants. Minimum 35% of world size apart.
	var start_tiles: Array = []
	var min_sep: float = world_px * 0.35
	var _fc: int = faction_ids.size()
	for i in _fc:
		var f: String = faction_ids[i]
		# Pentagon distribution: evenly spaced around center.
		var ang: float = TAU * float(i) / float(maxi(_fc, 1)) - PI / 2.0
		var radius: float = world_px * 0.32
		var cx: float = world_px * 0.5 + cos(ang) * radius
		var cy: float = world_px * 0.5 + sin(ang) * radius
		var p := Vector2(cx, cy) \
			+ Vector2(rng.randf_range(-120.0, 120.0), rng.randf_range(-120.0, 120.0))
		p.x = clampf(p.x, 64.0, world_px - 64.0)
		p.y = clampf(p.y, 64.0, world_px - 64.0)
		# Enforce minimum separation from already-placed factions.
		var tries := 0
		while tries < 30:
			var too_close := false
			for of in starts:
				if p.distance_to(starts[of]) < min_sep:
					too_close = true
					break
			if not too_close:
				break
			# Nudge away from the closest faction.
			var closest: Vector2 = p
			var best_d := 999999.0
			for of in starts:
				var d: float = p.distance_to(starts[of])
				if d < best_d:
					best_d = d
					closest = starts[of]
			var away: Vector2 = (p - closest).normalized()
			if away.length() < 0.1:
				away = Vector2(cos(ang + PI), sin(ang + PI))
			p += away * (min_sep - best_d + 40.0)
			p.x = clampf(p.x, 64.0, world_px - 64.0)
			p.y = clampf(p.y, 64.0, world_px - 64.0)
			tries += 1
		starts[f] = p
		start_tiles.append(Vector2i(int(p.x / _tile_px), int(p.y / _tile_px)))

	# --- Terrain tiles from noise. ---
	# World type modifies water level via elev_bias (archipelago = more water).
	var water_thresh := WATER_THRESHOLD + elev_bias
	var terrain := PackedByteArray()
	terrain.resize(MAP_TILES * MAP_TILES)
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var n: float = noise.get_noise_2d(float(tx) * elev_f, float(ty) * elev_f)
			terrain[ty * MAP_TILES + tx] = TILE_WATER if n < water_thresh else TILE_GRASS

	# Carve guaranteed grass around each faction start.
	for st: Vector2i in start_tiles:
		for dy in range(-START_CLEAR_RADIUS_TILES, START_CLEAR_RADIUS_TILES + 1):
			for dx in range(-START_CLEAR_RADIUS_TILES, START_CLEAR_RADIUS_TILES + 1):
				if dx * dx + dy * dy > START_CLEAR_RADIUS_TILES * START_CLEAR_RADIUS_TILES:
					continue
				var tx2: int = st.x + dx
				var ty2: int = st.y + dy
				if tx2 >= 0 and ty2 >= 0 and tx2 < MAP_TILES and ty2 < MAP_TILES:
					terrain[ty2 * MAP_TILES + tx2] = TILE_GRASS

	# --- Rivers: downhill watershed carving pass (keeps clear of starts). ---
	# HTML fix79 parity: rivers start at land springs (high-elevation grass),
	# walk downhill to the coast, and NEVER continue into the ocean —
	# carving stops at the first water tile (the river mouth), so no river
	# band renders across the sea (HTML's OCEAN80 truncation rule).
	var river_flow := {}  # Vector2i -> Vector2 downhill dir (tile space)
	var river_count := int(float(RIVER_COUNT) * lake_mul)
	var river_origins: Array = []
	for _r in river_count:
		var origin := _find_river_origin(terrain, elev, start_tiles, rng)
		if origin == Vector2i(-1, -1):
			continue
		river_origins.append(origin)
		_carve_river(origin, terrain, elev, start_tiles, river_flow)
	_widen_rivers(terrain, river_flow, start_tiles, rng, river_origins)
	# Mountain massifs + raw elevation field, shared by waterfall detection
	# and the cliffs pass below (generated here so both see the same rng
	# stream the old inline code consumed).
	var mountains := _gen_mountains(rng, start_tiles)
	var ef := _elev_field(elev, mountains)
	# Moisture field (tile resolution, 0..1) for the climate blends below.
	# HTML cgTerrainAt parity: moist_f scales the noise frequency, moist_bias
	# shifts it (wasteland dries out, wilds stay lush).
	var moist := _moisture_field(rng_seed, moist_f, moist_bias)
	# Waterfalls: HTML CLIFFART84 rule — a fall exists ONLY where the river
	# crosses a real height-level change (underlying terrain level drops >= 1
	# to the downstream tile), never into the sea / over the shoreline
	# (OCEAN80), and only onto solid land (landing elev >= 0.355).
	var fall_levels := _fall_level_grid(terrain, ef)
	var waterfalls: Array = _mark_waterfalls(terrain, ef, fall_levels, river_flow)
	var rapids := _pick_rapids(terrain, elev, river_flow)
	# Old-save sanitation: no river band across the sea, no orphan flow
	# entries (Godot saves don't persist terrain — worlds regenerate from
	# seed — so this is a defensive repair pass, HTML OCEAN80 parity).
	_sanitize_rivers(terrain, river_flow)

	# --- Cliffs: discrete height levels 0..6 (the Cliffs Update). ---
	# Computed after rivers so carved water is level 0 (HTML: gameplay
	# water is ALWAYS level 0). Stepped mountains from gaussian ranges and
	# sharp crag noise, quantized with the HTML's level formula.
	# Faction starts are flattened for buildable towns.
	var levels := _build_levels(terrain, ef, start_tiles)

	# Sand: grass tiles adjacent to water (shorelines AND riverbanks).
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var idx: int = ty * MAP_TILES + tx
			if terrain[idx] != TILE_GRASS:
				continue
			var near_water := false
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = tx + dx
					var ny: int = ty + dy
					if nx >= 0 and ny >= 0 and nx < MAP_TILES and ny < MAP_TILES \
							and is_water(terrain[ny * MAP_TILES + nx]):
						near_water = true
						break
				if near_water:
					break
			if near_water:
				terrain[idx] = TILE_SAND

	# --- Trees: scattered on grass, kept clear of starts. ---
	# No trees on the high peaks (alpine tree line, like the HTML).
	var trees := PackedVector2Array()
	var tree_attempts := int(6000.0 * tree_mul)
	for _a in tree_attempts:
		var p := Vector2(rng.randf_range(0.0, world_px), rng.randf_range(0.0, world_px))
		if tile_at({"terrain": terrain}, p) != TILE_GRASS:
			continue
		var ttx: int = clampi(int(p.x / _tile_px), 0, MAP_TILES - 1)
		var tty: int = clampi(int(p.y / _tile_px), 0, MAP_TILES - 1)
		if levels[tty * MAP_TILES + ttx] >= ALPINE_TREE_LINE:
			continue
		var clear := true
		for f in starts:
			if p.distance_to(starts[f]) < TREE_MIN_START_DIST:
				clear = false
				break
		if clear:
			trees.append(p)
		var max_trees := int(float(MAX_TREES) * tree_mul)
		if trees.size() >= max_trees:
			break

	# --- Resource nodes near each start. ---
	# Jeremy 2026-10-05: NO wood piles — the old "wood" cluster now plants a
	# small grove of real trees near each start (trees are the wood source).
	# Jeremy 2026-10-05: NO oil piles either — oil comes from oil pumps
	# placed in industrial zones.
	var resources: Array = []
	var res_defs := [
		["wood", 5, 200.0, 340.0],
		["gold", 3, 280.0, 480.0],
	]
	for f in starts:
		var sp2: Vector2 = starts[f]
		for rd in res_defs:
			var rtype: String = rd[0]
			var count: int = int(float(rd[1]) * mine_mul)
			for _k in count:
				var ang: float = rng.randf_range(0.0, TAU)
				var dist: float = rng.randf_range(rd[2], rd[3])
				var p2: Vector2 = sp2 + Vector2(cos(ang), sin(ang)) * dist
				p2.x = clampf(p2.x, 64.0, world_px - 64.0)
				p2.y = clampf(p2.y, 64.0, world_px - 64.0)
				if is_water(tile_at({"terrain": terrain}, p2)):
					continue
				if rtype == "wood":
					if tile_at({"terrain": terrain}, p2) != TILE_GRASS:
						continue
					var ptx: int = clampi(int(p2.x / _tile_px), 0, MAP_TILES - 1)
					var pty: int = clampi(int(p2.y / _tile_px), 0, MAP_TILES - 1)
					if levels[pty * MAP_TILES + ptx] >= ALPINE_TREE_LINE:
						continue
					trees.append(p2)
				else:
					resources.append({"type": rtype, "position": p2})

	# --- Bake terrain + water mask (renderer upscales them). ---
	var baked := _bake_terrain(terrain, levels, noise, rng_seed, starts,
		world_px, ef, moist, snow_amt, desert_amt, river_flow)

	# --- Water bodies for the hydro/flood sim (Jeremy 2026-10-04): lakes
	# as flood-filled regions, rivers as walked polylines from origins. ---
	var water_bodies: Array = _build_water_bodies(terrain, river_flow,
		river_origins)

	return {
		"size_tiles": Vector2i(MAP_TILES, MAP_TILES),
		"tile_size": _tile_px,
		"world_size": Vector2(world_px, world_px),
		"terrain": terrain,
		"levels": levels,
		"terrain_image": baked["image"],
		"water_mask": baked["mask"],
		"ripple_tex": baked["ripple"],
		"flow_tex": baked["flow"],
		"curl_tex": baked["curl"],
		"faction_starts": starts,
		"trees": trees,
		"resources": resources,
		"waterfalls": waterfalls,
		"river_flow": river_flow,
		"rapids": rapids,
		"water_bodies": water_bodies,
	}


## Water bodies for the hydro/flood sim (Jeremy 2026-10-04).
## Lakes: flood-filled TILE_WATER regions -> {kind, pos (centroid px),
## radius (px)}. Rivers: walked polylines from each origin following
## river_flow -> {kind, points (PackedVector2Array px), width (px)}.
## Tiny puddles (< 4 tiles) are skipped — they can't threaten towns.
func _build_water_bodies(terrain: PackedByteArray, river_flow: Dictionary,
		river_origins: Array) -> Array:
	var bodies: Array = []
	var seen := {}
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var key := Vector2i(tx, ty)
			if seen.has(key):
				continue
			if terrain[ty * MAP_TILES + tx] != TILE_WATER:
				continue
			# Flood-fill this lake region.
			var region: Array = []
			var stack: Array = [key]
			seen[key] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				region.append(c)
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
						Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if n.x < 0 or n.y < 0 or n.x >= MAP_TILES \
							or n.y >= MAP_TILES:
						continue
					if seen.has(n):
						continue
					if terrain[n.y * MAP_TILES + n.x] != TILE_WATER:
						continue
					seen[n] = true
					stack.append(n)
			if region.size() < 4:
				continue
			var cx := 0.0
			var cy := 0.0
			for t in region:
				cx += float(t.x)
				cy += float(t.y)
			cx /= float(region.size())
			cy /= float(region.size())
			var rad := 0.0
			for t in region:
				var d: float = Vector2(float(t.x) - cx,
					float(t.y) - cy).length()
				rad = maxf(rad, d)
			var center := Vector2((cx + 0.5) * _tile_px,
				(cy + 0.5) * _tile_px)
			bodies.append({
				"kind": "lake",
				"pos": center,
				"radius": (rad + 0.5) * _tile_px,
			})
	# Rivers: walk each origin downhill through river_flow.
	for origin in river_origins:
		var o := origin as Vector2i
		var pts := PackedVector2Array()
		var cur := o
		var visited := {}
		var guard := 0
		while guard < MAX_RIVER_STEPS + 40:
			guard += 1
			if visited.has(cur):
				break
			visited[cur] = true
			pts.append(Vector2((float(cur.x) + 0.5) * _tile_px,
				(float(cur.y) + 0.5) * _tile_px))
			if not river_flow.has(cur):
				break
			var dir: Vector2 = river_flow[cur]
			var nxt := Vector2i(cur.x + int(round(dir.x)),
				cur.y + int(round(dir.y)))
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= MAP_TILES \
					or nxt.y >= MAP_TILES:
				break
			cur = nxt
		if pts.size() >= 3:
			bodies.append({
				"kind": "river",
				"points": pts,
				"width": 55.0 * (_tile_px / 32.0),
			})
	return bodies


## River origin: random grass tile, high elevation, away from starts/edges.
func _find_river_origin(terrain: PackedByteArray, elev: FastNoiseLite,
		start_tiles: Array, rng: RandomNumberGenerator) -> Vector2i:
	for _t in 240:
		var tx: int = rng.randi_range(8, MAP_TILES - 9)
		var ty: int = rng.randi_range(8, MAP_TILES - 9)
		if terrain[ty * MAP_TILES + tx] != TILE_GRASS:
			continue
		if elev.get_noise_2d(float(tx), float(ty)) < 0.16:
			continue
		if _near_start(Vector2i(tx, ty), start_tiles, START_CLEAR_RADIUS_TILES + 4):
			continue
		return Vector2i(tx, ty)
	return Vector2i(-1, -1)


## Walks downhill from origin, carving TILE_RIVER; stops at sinks, water, or
## the tile budget. Records downhill flow per carved tile. The origin
## (spring) is carved too, so each river is one connected path from its
## land origin to its coastal mouth.
func _carve_river(origin: Vector2i, terrain: PackedByteArray,
		elev: FastNoiseLite, start_tiles: Array,
		river_flow: Dictionary) -> void:
	var cur := origin
	terrain[cur.y * MAP_TILES + cur.x] = TILE_RIVER  # the spring itself
	var visited := {}
	var steps := 0
	while steps < MAX_RIVER_STEPS and river_flow.size() < MAX_RIVER_TILES:
		steps += 1
		if visited.has(cur):
			break
		visited[cur] = true
		var ce: float = elev.get_noise_2d(float(cur.x), float(cur.y))
		var best := Vector2i(-1, -1)
		var best_e: float = ce - 0.0012  # must genuinely descend
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var n := Vector2i(cur.x + dx, cur.y + dy)
				if n.x < 2 or n.y < 2 or n.x >= MAP_TILES - 2 or n.y >= MAP_TILES - 2:
					continue
				if _near_start(n, start_tiles, START_CLEAR_RADIUS_TILES):
					continue
				var e: float = elev.get_noise_2d(float(n.x), float(n.y))
				if e < best_e:
					best_e = e
					best = n
		if best == Vector2i(-1, -1):
			break  # sink — the river ends here
		var step := Vector2(best - cur)
		river_flow[cur] = step.normalized()
		var nt: int = terrain[best.y * MAP_TILES + best.x]
		if nt == TILE_GRASS or nt == TILE_SAND:
			terrain[best.y * MAP_TILES + best.x] = TILE_RIVER
		elif is_water(nt):
			break  # reached water — river mouth; flow already points at it
		else:
			break  # hit another river/waterfall — merge, stop
		cur = best


## Widens carved rivers: narrow streams upstream, wider water downstream.
## Widened tiles inherit the parent tile's flow direction. Spring origins
## stay narrow (they're the upstream tip) — and skipping them keeps the
## widen rng stream identical with/without carved origins.
func _widen_rivers(terrain: PackedByteArray, river_flow: Dictionary,
		start_tiles: Array, rng: RandomNumberGenerator,
		origins: Array) -> void:
	var by_parent := {}  # child tile -> parent tile (for flow inheritance)
	var keys: Array = river_flow.keys()
	# Rebuild simple paths: group is overkill — widen around every river tile
	# with a downstream-biased probability using its flow's "progress".
	for t: Vector2i in keys:
		if t in origins:
			continue
		var nt: int = terrain[t.y * MAP_TILES + t.x]
		if nt != TILE_RIVER:
			continue
		# Downstream bias: tiles whose flow points away from high elevation
		# are "later"; approximate with hash-free pseudo progress from the
		# tile coords (deterministic, cheap).
		var prog: float = 0.5 + 0.5 * sin(float(t.x * 7 + t.y * 13) * 0.01)
		var p: float = 0.10 + 0.45 * prog
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if rng.randf() > p:
				continue
			var m: Vector2i = t + d
			if m.x < 2 or m.y < 2 or m.x >= MAP_TILES - 2 or m.y >= MAP_TILES - 2:
				continue
			if _near_start(m, start_tiles, START_CLEAR_RADIUS_TILES):
				continue
			var mi: int = m.y * MAP_TILES + m.x
			if (terrain[mi] == TILE_GRASS or terrain[mi] == TILE_SAND) \
					and not river_flow.has(m):
				terrain[mi] = TILE_RIVER
				by_parent[m] = t
				if river_flow.size() >= MAX_RIVER_TILES:
					break
	for m: Vector2i in by_parent:
		river_flow[m] = river_flow[by_parent[m]]


## Waterfalls: HTML CLIFFART84 rule — a fall exists ONLY where the river
## crosses a real height-level change: the underlying terrain level (NOT the
## gameplay water-forced grid — HTML's cgHeightLevelAt reads the terrain's
## own level under a river) must drop >= 1 between a river tile and its
## downstream neighbor. Never into the sea / over the shoreline (OCEAN80),
## and never onto lowland (HTML: landing elev < 0.355 is shoreline, not a
## falls landing). Picks the steepest drops, spread apart, capped.
## Returns [{position: Vector2 (world px), dir: Vector2}].
func _mark_waterfalls(terrain: PackedByteArray, ef: PackedFloat32Array,
		fall_levels: PackedByteArray, river_flow: Dictionary) -> Array:
	var drops: Array = []  # [drop, tile_idx]
	for t: Vector2i in river_flow.keys():
		if terrain[t.y * MAP_TILES + t.x] != TILE_RIVER:
			continue
		var d: Vector2 = river_flow[t]
		if d.length() < 0.5:
			continue
		var nxt := Vector2i(int(round(t.x + d.x)), int(round(t.y + d.y)))
		if nxt.x < 0 or nxt.y < 0 or nxt.x >= MAP_TILES or nxt.y >= MAP_TILES:
			continue
		# OCEAN80: never a waterfall into the sea / over the shoreline.
		if terrain[nxt.y * MAP_TILES + nxt.x] == TILE_WATER:
			continue
		var drop: int = int(fall_levels[t.y * MAP_TILES + t.x]) \
			- int(fall_levels[nxt.y * MAP_TILES + nxt.x])
		if drop < 1:
			continue
		# HTML: landing elev < 0.355 reads as shoreline, not a falls landing.
		if ef[nxt.y * MAP_TILES + nxt.x] < FALL_MIN_LAND_ELEV:
			continue
		drops.append([drop, t.y * MAP_TILES + t.x])
	# Steepest drops first; tile index breaks level-drop ties so the pick is
	# deterministic for a given seed.
	drops.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0]
		return a[1] < b[1])
	var out: Array = []
	var chosen: Array = []
	for e in drops:
		if out.size() >= MAX_WATERFALLS:
			break
		var t := Vector2i(e[1] % MAP_TILES, e[1] / MAP_TILES)
		# Spread waterfalls out — one steep stretch shouldn't hog them all.
		var too_close := false
		for c: Vector2i in chosen:
			var ddx: int = t.x - c.x
			var ddy: int = t.y - c.y
			if ddx * ddx + ddy * ddy < FALL_MIN_SEPARATION * FALL_MIN_SEPARATION:
				too_close = true
				break
		if too_close:
			continue
		chosen.append(t)
		terrain[t.y * MAP_TILES + t.x] = TILE_WATERFALL
		out.append({
			"position": Vector2((float(t.x) + 0.5) * _tile_px,
				(float(t.y) + 0.5) * _tile_px),
			"dir": river_flow[t],
			# Jeremy 2026-10-05 (launch readiness): the renderer hangs the
			# falls sheet screen-vertical from the lip to the plunge pool
			# (HTML CLIFFART84/RIVER92 language); the real level drop sets
			# the sheet height so taller drops read taller.
			"drop": e[0],
		})
	return out


## Old-save sanitation (HTML OCEAN80 parity): drops flow entries that sit on
## non-river tiles (orphans from an older carve/terrain), so every flow
## entry belongs to a real carved river/waterfall tile. Generation already
## guarantees no river band crosses the sea — carving stops at the first
## water tile and widening only touches grass/sand — so there is nothing
## further to truncate; this stays as the defensive repair pass.
func _sanitize_rivers(terrain: PackedByteArray, river_flow: Dictionary) -> void:
	var orphans: Array = []
	for t: Vector2i in river_flow.keys():
		var tt: int = terrain[t.y * MAP_TILES + t.x]
		if tt != TILE_RIVER and tt != TILE_WATERFALL:
			orphans.append(t)
	for t: Vector2i in orphans:
		river_flow.erase(t)


## Steep non-falls river tiles read as rapids (foam-fleck spawn points).
func _pick_rapids(terrain: PackedByteArray, elev: FastNoiseLite,
		river_flow: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var stride := 0
	for t: Vector2i in river_flow.keys():
		if terrain[t.y * MAP_TILES + t.x] != TILE_RIVER:
			continue
		var d: Vector2 = river_flow[t]
		if d.length() < 0.5:
			continue
		var nxt := Vector2i(int(round(t.x + d.x)), int(round(t.y + d.y)))
		if nxt.x < 0 or nxt.y < 0 or nxt.x >= MAP_TILES or nxt.y >= MAP_TILES:
			continue
		var drop: float = elev.get_noise_2d(float(t.x), float(t.y)) \
			- elev.get_noise_2d(float(nxt.x), float(nxt.y))
		if drop < RAPID_MIN_DROP:
			continue
		stride += 1
		if stride % 4 != 0:
			continue
		out.append(Vector2((float(t.x) + 0.5) * _tile_px,
			(float(t.y) + 0.5) * _tile_px))
		if out.size() >= MAX_RAPIDS:
			break
	return out


func _near_start(t: Vector2i, start_tiles: Array, radius: int) -> bool:
	for st: Vector2i in start_tiles:
		var dx: int = t.x - st.x
		var dy: int = t.y - st.y
		if dx * dx + dy * dy <= radius * radius:
			return true
	return false


## Mountain massifs for the elevation field (extracted from _build_levels
## so waterfall detection and the cliffs pass share identical input).
## Consumes the rng stream exactly where the old inline code did.
func _gen_mountains(rng: RandomNumberGenerator,
		start_tiles: Array) -> Dictionary:
	# Mountain ranges: 3 massifs, kept clear of starts and map edges.
	var ranges: Array = []
	var tries := 0
	while ranges.size() < MOUNTAIN_RANGES and tries < 60:
		tries += 1
		var cx: int = rng.randi_range(18, MAP_TILES - 19)
		var cy: int = rng.randi_range(18, MAP_TILES - 19)
		var c := Vector2i(cx, cy)
		if _near_start(c, start_tiles, 26):
			continue
		var ok := true
		for r in ranges:
			var d: Vector2i = c - r["center"]
			if d.x * d.x + d.y * d.y < 40 * 40:
				ok = false
				break
		if not ok:
			continue
		ranges.append({
			"center": c,
			"sigma": rng.randf_range(8.0, 14.0),
			"amp": rng.randf_range(0.38, 0.55),
		})
	# Sharp crag noise: ridged, high-frequency — carves the sheer faces.
	var crag := FastNoiseLite.new()
	crag.seed = int(rng.seed) ^ 0xC0A6
	crag.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	crag.frequency = 0.09
	crag.fractal_octaves = 2
	return {"ranges": ranges, "crag": crag}


## Raw normalized elevation (0..1) per tile: river elevation noise plus
## mountain massifs and crag bite — the same field _build_levels quantizes.
func _elev_field(elev: FastNoiseLite, mountains: Dictionary) -> PackedFloat32Array:
	var ranges: Array = mountains["ranges"]
	var crag: FastNoiseLite = mountains["crag"]
	var ef := PackedFloat32Array()
	ef.resize(MAP_TILES * MAP_TILES)
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var e: float = elev.get_noise_2d(float(tx), float(ty)) * 0.5 + 0.5
			# Mountain massifs.
			for r in ranges:
				var d: Vector2i = Vector2i(tx, ty) - r["center"]
				var dd: float = float(d.x * d.x + d.y * d.y)
				var s: float = float(r["sigma"])
				e += float(r["amp"]) * exp(-dd / (2.0 * s * s))
			# Crags bite into high ground (jagged, can drop 2 levels
			# across one tile — those are the climbable cliff faces).
			if e > 0.52:
				var ridged: float = 1.0 - absf(
					crag.get_noise_2d(float(tx), float(ty)))
				e += 0.18 * (ridged - 0.4)
			ef[ty * MAP_TILES + tx] = e
	return ef


## Tile-resolution moisture field (0..1), HTML cgTerrainAt parity.
## moist_f scales the noise frequency, moist_bias shifts the result.
static func _moisture_field(rng_seed: int, moist_f: float,
		moist_bias: float) -> PackedFloat32Array:
	var mn := FastNoiseLite.new()
	mn.seed = int(rng_seed) ^ 0x6d6f6973
	mn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mn.frequency = 0.008 * maxf(moist_f, 0.05)
	mn.fractal_octaves = 2
	var mf := PackedFloat32Array()
	mf.resize(MAP_TILES * MAP_TILES)
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var m: float = mn.get_noise_2d(float(tx), float(ty)) * 0.5 \
				+ 0.5 + moist_bias
			mf[ty * MAP_TILES + tx] = clampf(m, 0.0, 1.0)
	return mf


## HTML cgGroundRGB climate weights (fix79): snow blends ground toward
## icy white (233,239,245), desert toward sand (214,186,128).
## Returns Vector2(snow_weight, desert_weight), each 0..1.
static func climate_weights(elev: float, moist: float, snow_amt: float,
		desert_amt: float) -> Vector2:
	var sw := 0.0
	if snow_amt > 0.0:
		sw = snow_amt * clampf((0.85 - elev * 0.55 - moist * 0.45) / 0.45,
			0.0, 1.0)
	var ds := 0.0
	if desert_amt > 0.0:
		ds = desert_amt * clampf((0.60 - moist) / 0.40, 0.0, 1.0)
	return Vector2(sw, ds)


## Underlying terrain height levels for waterfall detection (HTML parity:
## cgHeightLevelAt reads the terrain's own level under a river, and 0 for
## ocean water). Despiked like the cliffs pass so pillar artifacts can't
## read as falls.
func _fall_level_grid(terrain: PackedByteArray,
		ef: PackedFloat32Array) -> PackedByteArray:
	var lv := PackedByteArray()
	lv.resize(MAP_TILES * MAP_TILES)
	for i in MAP_TILES * MAP_TILES:
		if terrain[i] == TILE_WATER:
			lv[i] = 0
		else:
			lv[i] = Cliffs.level_for_elev(ef[i])
	_despike(lv)
	return lv


## Despike (HTML's CLIFFSMOOTH88): a cell towering 2+ levels above ALL
## 8 neighbors is a pillar artifact, not a cliff — pull it down one.
func _despike(levels: PackedByteArray) -> void:
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var idx: int = ty * MAP_TILES + tx
			var lv: int = levels[idx]
			if lv < 3:
				continue
			var nmax := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nx: int = tx + dx
					var ny: int = ty + dy
					if nx < 0 or ny < 0 or nx >= MAP_TILES or ny >= MAP_TILES:
						continue
					nmax = maxi(nmax, levels[ny * MAP_TILES + nx])
			if lv - nmax >= 2:
				levels[idx] = lv - 1


## The Cliffs Update — discrete height levels 0..6 per tile.
##
## Quantized with the HTML's level formula (Cliffs.level_for_elev):
## water/lowland is 0, then 0.10 elevation bands up to 6. Mountains come
## from gaussian ranges (smooth massifs) plus sharp ridged "crag" noise so
## real sheer faces (|level diff| > 1 between neighbors) exist for the
## cliff renderer and the slope-aware movement to work with.
## Water tiles are ALWAYS level 0 (HTML gameplay rule); faction starts are
## flattened to level 1 so towns are buildable.
func _build_levels(terrain: PackedByteArray, ef: PackedFloat32Array,
		start_tiles: Array) -> PackedByteArray:
	var levels := PackedByteArray()
	levels.resize(MAP_TILES * MAP_TILES)
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var idx: int = ty * MAP_TILES + tx
			if is_water(terrain[idx]):
				levels[idx] = 0
				continue
			var lv: int = Cliffs.level_for_elev(ef[idx])
			# Flat, buildable towns around each faction start.
			if _near_start(Vector2i(tx, ty), start_tiles,
					START_CLEAR_RADIUS_TILES):
				lv = 1
			levels[idx] = lv
	_despike(levels)
	return levels


## Bakes the terrain color image plus the water-depth mask and a small
## Wind Waker spiral-curl tile (Jeremy 2026-10-10 art order). Static so tests
## can bake and verify it without a full world gen: 128x128 R8, tileable
## (wrapped-UV spiral math is continuous across tile edges), deterministic
## per seed. R = curl-crest field 0..1 (1 = curl crest center).
static func _curl_centers(rng_seed: int) -> Array[Vector2]:
	var cn := FastNoiseLite.new()
	cn.seed = int(rng_seed) ^ 0xC117
	cn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cn.frequency = 0.05
	var centers: Array[Vector2] = []
	for ci in 3:
		centers.append(Vector2(
			0.18 + 0.64 * absf(cn.get_noise_1d(float(ci * 7 + 1))),
			0.18 + 0.64 * absf(cn.get_noise_1d(float(ci * 7 + 40)))))
	return centers


## Curl-crest field at tile UV (cu, cv in tile units — 1.0 == one full
## tile). Wrapped deltas make f(1.0, v) == f(0.0, v), so the tile repeats
## seamlessly. sin(3a) stays continuous across atan2's branch cut (odd
## multiple of pi reads 0 on both sides).
static func _curl_value(cu: float, cv: float,
		centers: Array[Vector2]) -> float:
	var curl := 0.0
	for ctr: Vector2 in centers:
		var dx: float = cu - ctr.x
		var dy: float = cv - ctr.y
		dx -= floor(dx + 0.5)
		dy -= floor(dy + 0.5)
		var r: float = sqrt(dx * dx + dy * dy)
		var a: float = atan2(dy, dx)
		# Spiral arms: phase grows with angle AND radius.
		var arm: float = sin(a * 3.0 + r * 26.0 - r * r * 30.0)
		# Envelope: strong near the center, fading to the rim.
		var env: float = clampf(1.0 - r * 2.4, 0.0, 1.0)
		env = env * env
		curl = maxf(curl, 0.5 + 0.5 * arm * env)
	# Base swell keeps open water alive between curls; 4 full periods per
	# tile on each axis so it wraps seamlessly too.
	var base: float = 0.32 + 0.10 * sin((cu + cv) * 25.1327412)
	return clampf(maxf(curl, base), 0.0, 1.0)


static func _bake_curl_tile(rng_seed: int) -> Image:
	var centers := _curl_centers(rng_seed)
	var cimg := Image.create_empty(128, 128, false, Image.FORMAT_R8)
	for yy in 128:
		for xx in 128:
			var v := _curl_value(float(xx) / 128.0, float(yy) / 128.0,
				centers)
			cimg.set_pixel(xx, yy, Color(v, 0, 0))
	return cimg


## ripple noise texture. Distance fields run at 2 px/tile (256x256) for
## speed; the color bake is 4 px/tile (512x512).
##
## The Cliffs Update additions (HTML parity):
##   - height shading: land at level L > 1 reads lighter
##     (Cliffs.hill_shade_mult — HTML's cgHillShade82).
##   - cliff faces: a tile a full level+ above a lower neighbor gets a
##     rocky tint, and the drop-side edge pixels are drawn as exposed rock
##     with a jagged lip (HTML's CLIFFART84/CLIFFART86 rim passes).
func _bake_terrain(terrain: PackedByteArray, levels: PackedByteArray,
		noise: FastNoiseLite, rng_seed: int, starts: Dictionary,
		world_px: float, ef: PackedFloat32Array, moist: PackedFloat32Array,
		snow_amt: float, desert_amt: float, river_flow: Dictionary) -> Dictionary:
	var bw := MAP_TILES * BAKE_PX_PER_TILE          # 512
	var fw := MAP_TILES * 2                        # 256 (distance fields)
	# Faction territory tint weights (HTML parity: factionTerritories()).
	# Each faction tints nearby ground: humans bright, elves green,
	# gnomes warm, ogres tan/brown, undead ashen.
	var terr_factions: Array = starts.keys()
	var terr_pos: Array = []
	for f in terr_factions:
		terr_pos.append(starts[f])
	var terr_radius := world_px * 0.45
	# Binary water image at field resolution.
	var binary := PackedByteArray()
	binary.resize(fw * fw)
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			if is_water(terrain[ty * MAP_TILES + tx]):
				var bx0: int = tx * 2
				var by0: int = ty * 2
				for oy in 2:
					for ox in 2:
						binary[(by0 + oy) * fw + bx0 + ox] = 1
	# d_w: for water px, distance to nearest land. d_l: for land px, distance
	# to nearest water. Chamfer 1 / 1.4142, two passes.
	var d_w := _chamfer(binary, fw, fw, 0)
	var d_l := _chamfer(binary, fw, fw, 1)

	var grass_a := Color(0.32, 0.55, 0.25)
	var grass_b := Color(0.28, 0.50, 0.23)
	var grass_c := Color(0.36, 0.60, 0.28)  # light meadow
	var grass_d := Color(0.25, 0.46, 0.21)  # dark shade
	var grass_e := Color(0.40, 0.62, 0.30)  # sunlit highlight
	var dirt_p := Color(0.48, 0.38, 0.24)   # dirt patch
	var sand_c := Color(0.76, 0.68, 0.45)
	var wet_sand := Color(0.62, 0.53, 0.35)
	var mud := Color(0.55, 0.46, 0.30)
	var foam_c := Color(0.96, 0.98, 0.99)
	var rock := Color(0.38, 0.34, 0.30)
	var rock_hi := Color(0.48, 0.44, 0.39)
	# River: bright Wind Waker shallows -> saturated azure deep.
	var bed_river := Color(0.30, 0.58, 0.78)
	var deep_river := Color(0.08, 0.32, 0.68)
	# Ocean: bright Wind Waker shallows -> deep azure.
	var bed_sea := Color(0.25, 0.55, 0.80)
	var deep_sea := Color(0.05, 0.28, 0.66)

	var img := Image.create_empty(bw, bw, false, Image.FORMAT_RGB8)
	# RGBA8: R = water depth 0..1 (flow shader), G = ground-detail biome
	# selector 0..1 (0 = grass blades, 1 = granular speckle) so the
	# shader's detail overlay picks art per biome.
	var mask := Image.create_empty(bw, bw, false, Image.FORMAT_RGBA8)
	var wob := FastNoiseLite.new()
	wob.seed = int(rng_seed) ^ 0x51ab3f
	wob.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wob.frequency = 0.11
	# Ground detail noises (HTML parity: per-pixel variation, not per-tile).
	# detail_n: fine grass blade variation at pixel scale.
	# patch_n: low-frequency dirt/meadow patches.
	# grain_n: tiny per-pixel brightness grain (baked, like HTML's overlay tile).
	var detail_n := FastNoiseLite.new()
	detail_n.seed = int(rng_seed) ^ 0x9e3779b9
	detail_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_n.frequency = 0.045
	var patch_n := FastNoiseLite.new()
	patch_n.seed = int(rng_seed) ^ 0x1234abcd
	patch_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch_n.frequency = 0.008
	var grain_n := FastNoiseLite.new()
	grain_n.seed = int(rng_seed) ^ 0x55aa55aa
	grain_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain_n.frequency = 0.35
	for ty in MAP_TILES:
		for tx in MAP_TILES:
			var t: int = terrain[ty * MAP_TILES + tx]
			# Climate weights for this tile (HTML cgGroundRGB snow/desert
			# formulas); per-pixel wobble keeps snowlines from reading
			# tile-blocky.
			var cw := Vector2.ZERO
			if snow_amt > 0.0 or desert_amt > 0.0:
				cw = climate_weights(ef[ty * MAP_TILES + tx],
					moist[ty * MAP_TILES + tx], snow_amt, desert_amt)
			for oy in BAKE_PX_PER_TILE:
				for ox in BAKE_PX_PER_TILE:
					var bx: int = tx * BAKE_PX_PER_TILE + ox
					var by: int = ty * BAKE_PX_PER_TILE + oy
					# Field sample (field is 2 px/tile; bake is 4 px/tile).
					var fx: int = mini(bx / 2, fw - 1)
					var fy: int = mini(by / 2, fw - 1)
					var col: Color
					var depth01 := 0.0
					# Ground-detail biome selector for the shader overlay:
					# 0 = grass blades, 1 = granular (sand/dirt/snow/rock).
					var biome := 0.0
					if is_water(t):
						var dw: float = d_w[fy * fw + fx] * 2.0  # -> bake px
						depth01 = clampf(dw / DEPTH_FULL_PX, 0.0, 1.0)
						var bed: Color = bed_river if t == TILE_RIVER else bed_sea
						var deep: Color = deep_river if t == TILE_RIVER else deep_sea
						col = bed.lerp(deep, pow(depth01, 0.65))
						if t == TILE_WATERFALL:
							# Cliff rock with white water streaks; the
							# animated falls face draws over this.
							var streak: float = wob.get_noise_2d(float(bx) * 0.9,
								float(by) * 0.9) * 0.5 + 0.5
							col = rock.lerp(rock_hi, streak * 0.5)
							if oy >= 2:
								col = col.lerp(foam_c, 0.55)
							depth01 = 0.55
						else:
							# Carved-bank inner shadow FIRST: the first water
							# pixels darken steeply, so rivers/lakes read as
							# cut INTO the ground, not painted on top. Foam
							# below stays bright white over the dark edge.
							if dw <= 4.0:
								var carve: float = clampf(
									(1.0 - dw / 4.0) * 1.6, 0.0, 0.85)
								col = col.lerp(col * 0.25, carve)
							# Subtle current variation (before foam, so the
							# foam keeps its bright white).
							var v: float = noise.get_noise_2d(
								float(tx) * 0.7 + 500.0, float(ty) * 0.7 + 500.0)
							var vm: float = 0.94 + 0.10 * (v * 0.5 + 0.5)
							col = Color(col.r * vm, col.g * vm, col.b * vm)
							# Foam froth at the waterline, wobbled so it
							# doesn't read as a perfect ring — and broken
							# into dashes by a second noise so shores read
							# as natural foam patches, not a painted outline.
							# Decisive lerp applied last: foam stays bright
							# white over the carved dark edge.
							var wobble: float = wob.get_noise_2d(
								float(bx) * 0.6, float(by) * 0.6) * 1.2
							if dw <= FOAM_BAND_PX + wobble:
								var fbrk: float = wob.get_noise_2d(
									float(bx) * 1.7 + 99.0, float(by) * 1.7)
								if fbrk > -0.15:
									col = col.lerp(foam_c, 0.93)
					else:
						# Grass: per-pixel variation (HTML parity — the old code
						# sampled noise per-TILE, making flat chunky squares).
						# 1. Base shade from detail noise (5-shade meadow blend).
						var dn: float = detail_n.get_noise_2d(float(bx), float(by)) * 0.5 + 0.5
						if dn < 0.25:
							col = grass_d.lerp(grass_b, dn / 0.25)
						elif dn < 0.5:
							col = grass_b.lerp(grass_a, (dn - 0.25) / 0.25)
						elif dn < 0.75:
							col = grass_a.lerp(grass_c, (dn - 0.5) / 0.25)
						else:
							col = grass_c.lerp(grass_e, (dn - 0.75) / 0.25)
						# 2. Dirt patches: low-frequency noise -> worn earth.
						var pn: float = patch_n.get_noise_2d(float(bx), float(by)) * 0.5 + 0.5
						if pn > 0.72:
							var pw: float = clampf((pn - 0.72) / 0.18, 0.0, 1.0)
							col = col.lerp(dirt_p, pw * 0.65)
							biome = maxf(biome, pw * 0.85)
						# 3. Fine grain: tiny brightness variation (baked).
						var gn: float = grain_n.get_noise_2d(float(bx), float(by))
						var gm: float = 1.0 + gn * 0.07
						col = Color(col.r * gm, col.g * gm, col.b * gm)
						# 4. Faction territory tint (HTML parity: factionTerritories).
						# Smooth falloff from each faction start; tints the
						# ground so territories read visually (tan undead
						# wastes, green elf groves, etc.).
						var wx: float = float(bx) / float(bw) * world_px
						var wy: float = float(by) / float(bw) * world_px
						var tw := 0.0
						var tr := 0.0
						var tg := 0.0
						var tb := 0.0
						for fi in terr_factions.size():
							var fp: Vector2 = terr_pos[fi]
							var dd: float = Vector2(wx - fp.x, wy - fp.y).length() / terr_radius
							if dd >= 1.0:
								continue
							var wgt: float = 1.0 - dd * dd * (3.0 - 2.0 * dd)
							tw += wgt
							var fr: String = String(terr_factions[fi])
							# HTML tint multipliers per faction.
							if fr == "humans":
								tr += wgt * 1.04; tg += wgt * 1.05; tb += wgt * 0.96
							elif fr == "elves":
								tr += wgt * 0.60; tg += wgt * 0.98; tb += wgt * 0.74
							elif fr == "gnomes":
								tr += wgt * 1.16; tg += wgt * 1.00; tb += wgt * 0.55
							elif fr == "ogres":
								tr += wgt * 0.95; tg += wgt * 0.95; tb += wgt * 0.92
								# Ogres/undead: tan/brown earth tint.
								col = col.lerp(Color(0.60, 0.52, 0.38), wgt * 0.45)
							elif fr == "undead":
								tr += wgt * 0.85; tg += wgt * 0.80; tb += wgt * 0.75
								# Undead: ashen tan wastes (matches HTML screenshot).
								col = col.lerp(Color(0.66, 0.58, 0.42), wgt * 0.55)
							# Jeremy 2026-10-04: every faction's territory must
							# visibly glow in its faction color when zoomed out
							# (only the undead ashen tint was noticeable before;
							# the rest were subtle green shifts). Blend toward
							# the faction's Config color so all 5 read clearly.
							var fcol: Color = Config.FACTIONS.get(fr, {}).get("color", Color.WHITE)
							col = col.lerp(fcol, wgt * 0.38)
						if tw > 0.001:
							var base := 1.0 / (1.0 + tw)
							var mr: float = clampf((base + tr / (1.0 + tw)) , 0.55, 1.45)
							var mg2: float = clampf((base + tg / (1.0 + tw)), 0.55, 1.45)
							var mb: float = clampf((base + tb / (1.0 + tw)), 0.55, 1.45)
							col = Color(col.r * mr, col.g * mg2, col.b * mb)
						if t == TILE_SAND:
							col = sand_c
							biome = 1.0
						else:
							# Cliffs: height shading — higher ground reads
							# lighter (HTML cgHillShade82; the beach band
							# keeps its flat colors).
							var _lv: int = levels[ty * MAP_TILES + tx]
							var _hm: float = Cliffs.hill_shade_mult(_lv)
							if _hm > 1.0:
								col = Color(minf(col.r * _hm, 1.0),
									minf(col.g * _hm, 1.0),
									minf(col.b * _hm, 1.0))
						# Climate: snow / desert terrain blends (HTML cgGroundRGB
						# parity — the last word on ground color, so frozen
						# beaches read frozen and wasteland reads arid; the
						# detail-noise wobble keeps snowlines organic).
						if cw.x > 0.001 or cw.y > 0.001:
							var swp: float = clampf(cw.x + (dn - 0.5) * 0.2,
								0.0, 1.0)
							var dsp: float = clampf(cw.y + (dn - 0.5) * 0.2,
								0.0, 1.0)
							if swp > 0.001:
								col = col.lerp(SNOW_C, swp)
								biome = maxf(biome, swp * 0.9)
							if dsp > 0.001:
								col = col.lerp(DESERT_C, dsp)
								biome = maxf(biome, dsp * 0.9)
						# Muddy bank band + wet sand darkening near water.
						var dl: float = d_l[fy * fw + fx] * 2.0
						if dl <= BANK_BAND_PX:
							var band: float = 1.0 - dl / BANK_BAND_PX
							if t == TILE_SAND:
								col = col.lerp(wet_sand, band * 0.8)
								biome = 1.0
							else:
								col = col.lerp(mud, band * 0.7)
								biome = maxf(biome, band * 0.8)
							# Dark wet line right at the water's edge —
							# grounds the shoreline.
							if dl <= 2.0:
								col = col.lerp(Color(0.30, 0.24, 0.16),
									(1.0 - dl / 2.0) * 0.6)
					img.set_pixel(bx, by, col)
					mask.set_pixel(bx, by, Color(depth01, biome, 0.0, 1.0))

	# --- Autotile edge pass: soft irregular transitions between land
	# biomes (grass <-> sand). For each land tile edge shared with a
	# different land type, blend a noise-wobbled band of edge pixels
	# toward the neighbor's baked center color — Stardew-style, no hard
	# tile seams. Water edges already get foam/mud bands above.
	var edge_rng := RandomNumberGenerator.new()
	edge_rng.seed = int(rng_seed) ^ 91711
	var edge_dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1)]
	for ety in MAP_TILES:
		for etx in MAP_TILES:
			var et: int = terrain[ety * MAP_TILES + etx]
			if is_water(et):
				continue
			for ed: Vector2i in edge_dirs:
				var ntx: int = etx + ed.x
				var nty: int = ety + ed.y
				if ntx < 0 or nty < 0 or ntx >= MAP_TILES \
						or nty >= MAP_TILES:
					continue
				var nt: int = terrain[nty * MAP_TILES + ntx]
				if is_water(nt) or nt == et:
					continue
				# Neighbor's baked center color = its biome representative.
				var nc: Color = img.get_pixel(
					ntx * BAKE_PX_PER_TILE + 2, nty * BAKE_PX_PER_TILE + 2)
				for ei in BAKE_PX_PER_TILE:
					# Wobbled boundary: 1..3 px into this tile.
					var wdepth: int = 1 + int(edge_rng.randf() * 3.0)
					for ek in wdepth:
						var ex2: int
						var ey2: int
						if ed.x == 1:
							ex2 = etx * BAKE_PX_PER_TILE \
								+ (BAKE_PX_PER_TILE - 1 - ek)
							ey2 = ety * BAKE_PX_PER_TILE + ei
						elif ed.x == -1:
							ex2 = etx * BAKE_PX_PER_TILE + ek
							ey2 = ety * BAKE_PX_PER_TILE + ei
						elif ed.y == 1:
							ex2 = etx * BAKE_PX_PER_TILE + ei
							ey2 = ety * BAKE_PX_PER_TILE \
								+ (BAKE_PX_PER_TILE - 1 - ek)
						else:
							ex2 = etx * BAKE_PX_PER_TILE + ei
							ey2 = ety * BAKE_PX_PER_TILE + ek
						var ef2: float = 1.0 - float(ek) / float(wdepth)
						ef2 = ef2 * ef2 * (3.0 - 2.0 * ef2)
						var cc2: Color = img.get_pixel(ex2, ey2)
						img.set_pixel(ex2, ey2, cc2.lerp(nc, ef2 * 0.85))

	# --- Cliffs rim pass: visible cliff faces (HTML CLIFFART84/86). ---
	# A land tile a full level above a lower neighbor gets a rocky tint,
	# and the drop-side edge pixels are drawn as exposed rock with a
	# jagged lip (seeded wobble, so edges read as broken rock, not cubes).
	# The south edge gets a 3 px face on sheer drops (HTML draws the south
	# cliff face down to the neighbor's top); 2 px on single-level steps.
	# Jeremy 2026-10-03: cliffs must read clearly in the main sim, not just
	# the preview — tint and faces strengthened for visibility at game zoom.
	var rock_c := Color(0.52, 0.46, 0.38)
	var rock_dark := Color(0.30, 0.27, 0.23)
	for cty in MAP_TILES:
		for ctx in MAP_TILES:
			var cidx: int = cty * MAP_TILES + ctx
			var cl: int = levels[cidx]
			if cl <= 0 or is_water(terrain[cidx]):
				continue
			var maxdrop := 0
			var drop_dirs: Array[Vector2i] = []
			for ddy in [-1, 0, 1]:
				for ddx in [-1, 0, 1]:
					if ddx == 0 and ddy == 0:
						continue
					var nnx: int = ctx + ddx
					var nny: int = cty + ddy
					if nnx < 0 or nny < 0 or nnx >= MAP_TILES \
							or nny >= MAP_TILES:
						continue
					var nl: int = levels[nny * MAP_TILES + nnx]
					if cl - nl >= 1:
						maxdrop = maxi(maxdrop, cl - nl)
						drop_dirs.append(Vector2i(ddx, ddy))
			if maxdrop <= 0:
				continue
			# Rocky warning tint over the whole tile (deeper for sheer).
			var tint: float = 0.35 if maxdrop == 1 else 0.55
			var sheer: bool = maxdrop >= 2
			var wob_seed: int = (ctx * 73856093) ^ (cty * 19349663)
			for oy in BAKE_PX_PER_TILE:
				for ox in BAKE_PX_PER_TILE:
					var bx: int = ctx * BAKE_PX_PER_TILE + ox
					var by: int = cty * BAKE_PX_PER_TILE + oy
					var is_edge := false
					var is_south := false
					for d: Vector2i in drop_dirs:
						if d.x == 1 and ox == BAKE_PX_PER_TILE - 1:
							is_edge = true
						elif d.x == -1 and ox == 0:
							is_edge = true
						elif d.y == 1 and (oy >= BAKE_PX_PER_TILE - 3 if sheer else oy >= BAKE_PX_PER_TILE - 2):
							# South face: 3 px on sheer drops, 2 px on steps
							# (HTML draws the south cliff face down to the
							# neighbor's top).
							is_edge = true
							is_south = true
						elif d.y == -1 and oy == 0:
							is_edge = true
						elif d.x != 0 and d.y != 0 \
								and ox == (BAKE_PX_PER_TILE - 1 if d.x == 1 else 0) \
								and oy == (BAKE_PX_PER_TILE - 1 if d.y == 1 else 0):
							is_edge = true
							is_south = d.y == 1
					if is_edge:
						# Jagged lip: seeded wobble skips some pixels.
						var h: int = (wob_seed + ox * 31 + oy * 57) & 7
						if h < 6:
							img.set_pixel(bx, by,
								rock_dark if is_south else rock_c)
							var _cm: Color = mask.get_pixel(bx, by)
							mask.set_pixel(bx, by, Color(_cm.r, 0.7, 0.0, 1.0))
					else:
						var cur: Color = img.get_pixel(bx, by)
						img.set_pixel(bx, by, cur.lerp(rock_c, tint))
						var _cm2: Color = mask.get_pixel(bx, by)
						mask.set_pixel(bx, by, Color(_cm2.r, 0.7, 0.0, 1.0))

	# Ripple tile for the flow shader (scrolls over water only).
	var rn := FastNoiseLite.new()
	rn.seed = int(rng_seed) ^ 0x77aa11
	rn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	rn.frequency = 0.09
	var rimg := Image.create_empty(128, 128, false, Image.FORMAT_R8)
	for yy in 128:
		for xx in 128:
			var vv: float = rn.get_noise_2d(float(xx), float(yy)) * 0.5 + 0.5
			rimg.set_pixel(xx, yy, Color(vv, 0, 0))
	# Wind Waker spiral-curl tile (Jeremy 2026-10-10 art order): 128x128 R8,
	# tileable — the flow shader scrolls it at large scales for big stylized
	# wave curls. Baked by the static _bake_curl_tile (testable standalone).
	var cimg: Image = _bake_curl_tile(int(rng_seed))
	# Flow-direction texture for the Wind Waker water shader (1 px/tile,
	# RGBA8): RG = flow dir * 0.5 + 0.5, B = flow speed 0..1. Rivers scroll
	# along their carved downhill direction; lakes/ocean drift slowly on
	# the prevailing wind so still water still feels alive.
	var fimg := Image.create_empty(MAP_TILES, MAP_TILES, false,
		Image.FORMAT_RGBA8)
	var wind := Vector2(0.64, 0.77).normalized()
	for fyy in MAP_TILES:
		for fxx in MAP_TILES:
			var fdir := Vector2.ZERO
			var fspd := 0.0
			var ftt: int = terrain[fyy * MAP_TILES + fxx]
			if ftt == TILE_RIVER or ftt == TILE_WATERFALL:
				var rd: Vector2 = river_flow.get(Vector2i(fxx, fyy),
					Vector2.ZERO)
				if rd.length() > 0.01:
					fdir = rd.normalized()
					fspd = clampf(rd.length(), 0.25, 1.0)
				else:
					fdir = wind
					fspd = 0.25
			elif ftt == TILE_WATER:
				fdir = wind
				fspd = 0.12
			fimg.set_pixel(fxx, fyy, Color(fdir.x * 0.5 + 0.5,
				fdir.y * 0.5 + 0.5, fspd, 1.0))
	return {
		"image": img,
		"mask": mask,
		"ripple": ImageTexture.create_from_image(rimg),
		"flow": ImageTexture.create_from_image(fimg),
		"curl": ImageTexture.create_from_image(cimg),
	}


## Two-pass chamfer distance transform. Cells whose binary value equals
## zero_val get distance 0; every other cell gets its distance to the
## nearest zero cell (px units, 1 / 1.4142 weights).
static func _chamfer(binary: PackedByteArray, w: int, h: int,
		zero_val: int) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(w * h)
	var INF := 1.0e9
	for i in w * h:
		d[i] = 0.0 if binary[i] == zero_val else INF
	for y in h:
		var row: int = y * w
		for x in w:
			var i: int = row + x
			if d[i] == 0.0:
				continue
			var best: float = d[i]
			if x > 0:
				best = minf(best, d[i - 1] + 1.0)
			if y > 0:
				best = minf(best, d[row - w + x] + 1.0)
				if x > 0:
					best = minf(best, d[row - w + x - 1] + 1.4142)
				if x < w - 1:
					best = minf(best, d[row - w + x + 1] + 1.4142)
			d[i] = best
	for y in range(h - 1, -1, -1):
		var row: int = y * w
		for x in range(w - 1, -1, -1):
			var i: int = row + x
			if d[i] == 0.0:
				continue
			var best: float = d[i]
			if x < w - 1:
				best = minf(best, d[i + 1] + 1.0)
			if y < h - 1:
				best = minf(best, d[row + w + x] + 1.0)
				if x < w - 1:
					best = minf(best, d[row + w + x + 1] + 1.4142)
				if x > 0:
					best = minf(best, d[row + w + x - 1] + 1.4142)
			d[i] = best
	return d


## Returns the tile id at a world position (needs at least {"terrain": ...}).
func tile_at(map_data: Dictionary, world_pos: Vector2) -> int:
	var terrain: PackedByteArray = map_data["terrain"]
	var tx: int = int(world_pos.x / _tile_px)
	var ty: int = int(world_pos.y / _tile_px)
	if tx < 0 or ty < 0 or tx >= MAP_TILES or ty >= MAP_TILES:
		return TILE_WATER
	return terrain[ty * MAP_TILES + tx]
