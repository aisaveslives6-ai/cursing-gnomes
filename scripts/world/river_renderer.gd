class_name RiverRenderer
extends Node2D
## Cursing Gnomes — river + waterfall visuals (rivers visual overhaul).
##
## Owns everything water that MOVES:
##   - the animated flow shader on the terrain sprite (scrolling ripples +
##     current bands, masked to water only — one extra texture sample, no
##     extra draw calls)
##   - one _FallsNode per waterfall (scrolling falls face, rock lip, foam)
##   - one pooled _FoamLayer: drifting foam flecks, impact bursts, expanding
##     rings, rising mist — a single canvas item, no per-frame allocation
##
## 60 fps budget: a handful of tiny canvas items redrawing small regions;
## every particle is pooled and stolen oldest-first when the pool is full.
##
## setup(map_data, terrain_sprite) wires it all. flow_at() exposes the river
## flow field for anything that drifts (flecks, and later: fishing, debris).


const FLOW_SHADER := "res://assets/shaders/water_flow.gdshader"
const MAX_FALLS_NODES := 12
const MAX_FLECKS := 256
const MAX_BURSTS := 16
const MAX_RINGS := 16
const MAX_MIST := 48
const TILE_PX := 32  # must match MapGen.TILE_PX
## Lip line of the falls sheet, in node-local px (just above tile center).
## The sheet hangs screen-vertical from here to the plunge pool — the HTML
## CLIFFART84/RIVER92 language (a falling sheet is vertical, never painted
## flat into the ground plane).
const LIP_TOP := -8.0


## Screen-space falls-sheet height for a level drop (HTML CLIFFART84:
## (Lu-Ll) levels of lift). Taller drops read taller; clamped so an extreme
## drop can't throw a sheet across half the screen.
static func face_height_for(drop: float) -> float:
	return 36.0 + 30.0 * clampf(drop, 1.0, 4.0)


var _waterfalls: Array = []
var _flow: Dictionary = {}
var _rapids := PackedVector2Array()
var _foam: _FoamLayer
## Graphics-tier particle multiplier (HTML particleMul parity): gates foam
## spawns. Uses its own RNG so the position sequence stays deterministic.
var particle_mul := 1.0
var _fx_rng := RandomNumberGenerator.new()


func set_particle_mul(m: float) -> void:
	particle_mul = clampf(m, 0.05, 1.0)


func _fx_gate() -> bool:
	return _fx_rng.randf() < particle_mul
var _spawn_acc := 0.0
var _rapid_cursor := 0
var _burst_timers: Array = []  # per-waterfall seconds until next burst
var _falls_built := 0
var _rng := RandomNumberGenerator.new()


## Builds falls nodes + foam layer and puts the flow shader on the terrain.
func setup(map_data: Dictionary, terrain_sprite: Sprite2D) -> void:
	_waterfalls = map_data.get("waterfalls", [])
	_flow = map_data.get("river_flow", {})
	_rapids = map_data.get("rapids", PackedVector2Array())
	_rng.seed = 20261002
	_fx_rng.seed = 4242  # spawn-gate rolls; independent of position sequence
	# z_index -90: above the terrain (-100), below units/props (0).
	# (Parent World y-sorts; z_index is still the primary sort key.)
	z_index = -90
	_apply_flow_shader(map_data, terrain_sprite)
	_falls_built = mini(_waterfalls.size(), MAX_FALLS_NODES)
	for i in _falls_built:
		var w: Dictionary = _waterfalls[i]
		var falls := _FallsNode.new()
		falls.setup(w["position"], float(w.get("drop", 1)))
		add_child(falls)
		_burst_timers.append(_rng.randf_range(0.0, 0.8))
	_foam = _FoamLayer.new()
	add_child(_foam)


## Downhill flow direction (world space) at a position; ZERO on land.
func flow_at(world_pos: Vector2) -> Vector2:
	var t := Vector2i(int(world_pos.x / TILE_PX), int(world_pos.y / TILE_PX))
	return _flow.get(t, Vector2.ZERO)


func falls_count() -> int:
	return _falls_built


func _apply_flow_shader(map_data: Dictionary, terrain_sprite: Sprite2D) -> void:
	if terrain_sprite == null or not map_data.has("water_mask"):
		return
	var sh: Shader = load(FLOW_SHADER) as Shader
	if sh == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("water_mask",
		ImageTexture.create_from_image(map_data["water_mask"]))
	mat.set_shader_parameter("ripple_tex", map_data["ripple_tex"])
	# Wind Waker flow direction/speed (baked per tile from river_flow).
	# Guarded: very old map_data dicts may lack it.
	if map_data.has("flow_tex"):
		mat.set_shader_parameter("flow_tex", map_data["flow_tex"])
	# Wind Waker spiral-curl tile (Jeremy 2026-10-10 art order).
	# Guarded: very old map_data dicts may lack it — fall back to a neutral
	# mid-gray tile so old maps render flat mid-blue water instead of
	# unbound-sampler white (which would read as all-crest).
	if map_data.has("curl_tex"):
		mat.set_shader_parameter("curl_tex", map_data["curl_tex"])
	else:
		var neutral := Image.create_empty(1, 1, false, Image.FORMAT_R8)
		neutral.fill(Color(0.5, 0.0, 0.0))
		mat.set_shader_parameter("curl_tex",
			ImageTexture.create_from_image(neutral))
	# Stardew ground-detail overlays (AI-generated, tiled in-shader).
	var dg := load("res://assets/art/ground/detail_grass.png") as Texture2D
	var dn := load("res://assets/art/ground/detail_grain.png") as Texture2D
	if dg != null:
		mat.set_shader_parameter("detail_grass", dg)
	if dn != null:
		mat.set_shader_parameter("detail_grain", dn)
	terrain_sprite.material = mat


## Spawns foam on a fixed tick (4 Hz): each waterfall puffs flecks + a
## periodic burst/ring/mist; rapids get flecks on a round-robin cursor so a
## hundred rapids can't spike one frame.
func _process(delta: float) -> void:
	if _foam == null:
		return
	_spawn_acc += delta
	while _spawn_acc >= 0.25:
		_spawn_acc -= 0.25
		_spawn_tick(0.25)


func _spawn_tick(dt: float) -> void:
	var nfalls: int = mini(_waterfalls.size(), MAX_FALLS_NODES)
	for i in nfalls:
		var w: Dictionary = _waterfalls[i]
		var pos: Vector2 = w["position"]
		var dir: Vector2 = w["dir"]
		# Plunge pool: the sheet hangs screen-vertical from the lip, so foam
		# gathers at its base — never drifting loose across the map.
		var base := pos + Vector2(0.0,
			LIP_TOP + face_height_for(float(w.get("drop", 1))))
		# Flecks at the base, drifting downstream.
		if _fx_gate():
			_foam.spawn_fleck(
				base + Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-6, 6)),
				dir * _rng.randf_range(24.0, 44.0))
		# Burst + ring + mist on a per-falls timer.
		_burst_timers[i] = float(_burst_timers[i]) - dt
		if float(_burst_timers[i]) <= 0.0:
			_burst_timers[i] = _rng.randf_range(0.7, 1.1)
			if _fx_gate():
				_foam.spawn_burst(base)
				_foam.spawn_ring(base)
				for _m in 3:
					_foam.spawn_mist(base
						+ Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-6, 6)))
	# One rapid per tick, round-robin.
	if _rapids.size() > 0:
		_rapid_cursor = (_rapid_cursor + 1) % _rapids.size()
		var rp: Vector2 = _rapids[_rapid_cursor]
		var f: Vector2 = flow_at(rp)
		if f.length() > 0.1 and _fx_gate():
			_foam.spawn_fleck(rp + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12)),
				f * _rng.randf_range(20.0, 36.0))


## Animated waterfall face: rock lip, screen-vertical scrolling sheet,
## plunge-pool foam at the base. The sheet hangs straight DOWN the screen
## from the lip (HTML CLIFFART84/RIVER92) — a falling sheet is vertical in
## the world, never a stripe painted flat into the ground plane.
class _FallsNode extends Node2D:
	var _t := 0.0
	var _w := 40.0
	var _h := 96.0
	var _redraw_acc := 0.0

	func setup(pos: Vector2, drop: float) -> void:
		position = pos
		_h = RiverRenderer.face_height_for(drop)

	func _process(delta: float) -> void:
		_t += delta
		# Jeremy 2026-10-04: throttle waterfall redraws 60Hz -> 20Hz.
		# Streaks scroll at 150px/s; at 20Hz that's 7.5px/frame — still smooth.
		_redraw_acc += delta
		if _redraw_acc >= 0.05:
			_redraw_acc = 0.0
			# Cull off-screen waterfalls: no redraw, no process.
			var cam := get_viewport().get_camera_2d()
			if cam != null:
				var vs := get_viewport_rect().size
				var center := cam.get_screen_center_position()
				# +200px below: the sheet hangs up to 156px under the lip.
				var half := vs / maxf(cam.zoom.x, 0.01) * 0.5 + Vector2(120, 200)
				var in_view := absf(position.x - center.x) <= half.x \
					and absf(position.y - center.y) <= half.y
				if visible != in_view:
					visible = in_view
				if not in_view:
					return
			queue_redraw()

	func _draw() -> void:
		var top := RiverRenderer.LIP_TOP
		var lip := Color(0.30, 0.28, 0.26)
		var lip_hi := Color(0.44, 0.41, 0.37)
		# Wet-rock cleft behind the sheet (HTML CLIFFART84).
		draw_rect(Rect2(-_w / 2 - 4, top - 4, _w + 8, _h + 12),
			Color(0.13, 0.10, 0.08, 0.55))
		# Rock lip the water pours over.
		draw_rect(Rect2(-_w / 2 - 7, top - 14, _w + 14, 14), lip)
		draw_rect(Rect2(-_w / 2 - 7, top - 14, _w + 14, 5), lip_hi)
		# Falling sheet: vertical gradient bands, brighter toward the base.
		var bands := 7
		for i in bands:
			var y0: float = top + _h * float(i) / float(bands)
			var c := Color(0.55, 0.74, 0.90).lerp(
				Color(0.86, 0.95, 1.0), float(i) / float(bands))
			draw_rect(Rect2(-_w / 2, y0, _w, _h / float(bands) + 1.0), c)
		# Scrolling streaks fall straight down the screen (HTML RIVER92).
		for i in 9:
			var x: float = -_w / 2 + _w * (float(i) + 0.5) / 9.0 \
				+ sin(_t * 3.0 + float(i) * 1.7) * 2.0
			var yo: float = top + fmod(_t * 150.0 + float(i) * 53.0, _h + 44.0) - 22.0
			draw_line(Vector2(x, yo), Vector2(x + 1.0, yo + 30.0),
				Color(1, 1, 1, 0.55), 3.0)
		# Plunge-pool foam at the base — this grounds the falls.
		var by := top + _h
		draw_circle(Vector2(-10, by + 6), 13, Color(0.94, 0.97, 0.98, 0.9))
		draw_circle(Vector2(9, by + 9), 16, Color(0.94, 0.97, 0.98, 0.85))
		draw_circle(Vector2(0, by - 6), 11, Color(1, 1, 1, 0.7))


## Single pooled canvas item for ALL foam: flecks drift downstream and fade,
## bursts splash at impacts, rings expand, mist rises. One _draw call.
class _FoamLayer extends Node2D:
	var _flecks: Array = []
	var _bursts: Array = []
	var _rings: Array = []
	var _mist: Array = []
	var _rng := RandomNumberGenerator.new()
	var _foam_acc := 0.0  # Jeremy 2026-10-04: 20Hz throttle accumulator

	func _ready() -> void:
		_init_pools()

	func _init_pools() -> void:
		if not _flecks.is_empty():
			return
		_rng.seed = 777
		for _i in MAX_FLECKS:
			_flecks.append({"p": Vector2.ZERO, "v": Vector2.ZERO,
				"age": 1.0e9, "life": 1.0, "s": 3.0})
		for _i in MAX_BURSTS:
			_bursts.append({"p": Vector2.ZERO, "age": 1.0e9, "life": 0.7})
		for _i in MAX_RINGS:
			_rings.append({"p": Vector2.ZERO, "age": 1.0e9, "life": 1.4})
		for _i in MAX_MIST:
			_mist.append({"p": Vector2.ZERO, "v": Vector2.ZERO,
				"age": 1.0e9, "life": 1.6, "s": 6.0})

	func spawn_fleck(pos: Vector2, vel: Vector2) -> void:
		_init_pools()
		var s := _steal(_flecks)
		s["p"] = pos
		s["v"] = vel
		s["age"] = 0.0
		s["life"] = _rng.randf_range(2.4, 3.6)
		s["s"] = _rng.randf_range(2.0, 4.2)

	func spawn_burst(pos: Vector2) -> void:
		_init_pools()
		var s := _steal(_bursts)
		s["p"] = pos
		s["age"] = 0.0
		s["life"] = 0.7

	func spawn_ring(pos: Vector2) -> void:
		_init_pools()
		var s := _steal(_rings)
		s["p"] = pos
		s["age"] = 0.0
		s["life"] = 1.4

	func spawn_mist(pos: Vector2) -> void:
		_init_pools()
		var s := _steal(_mist)
		s["p"] = pos
		# Spray puffs up at the plunge pool and dies there — a short rise and
		# quick fade, so mist never drifts across the map reading as a
		# floating object (Jeremy 2026-10-05: nothing floating).
		s["v"] = Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-26, -12))
		s["age"] = 0.0
		s["life"] = _rng.randf_range(0.7, 1.1)
		s["s"] = _rng.randf_range(5.0, 9.0)

	func active_flecks() -> int:
		var n := 0
		for s in _flecks:
			if float(s["age"]) < float(s["life"]):
				n += 1
		return n

	## Test/debug hook: live counts per pool.
	func debug_counts() -> Dictionary:
		var c := {"flecks": 0, "bursts": 0, "rings": 0, "mist": 0}
		for s in _flecks:
			if float(s["age"]) < float(s["life"]):
				c["flecks"] = int(c["flecks"]) + 1
		for s in _bursts:
			if float(s["age"]) < float(s["life"]):
				c["bursts"] = int(c["bursts"]) + 1
		for s in _rings:
			if float(s["age"]) < float(s["life"]):
				c["rings"] = int(c["rings"]) + 1
		for s in _mist:
			if float(s["age"]) < float(s["life"]):
				c["mist"] = int(c["mist"]) + 1
		return c

	## Oldest-first steal: the pool never grows, no per-frame allocation.
	func _steal(pool: Array) -> Dictionary:
		var oldest: Dictionary = pool[0]
		for s in pool:
			if float(s["age"]) >= float(s["life"]):
				return s
			if float(s["age"]) > float(oldest["age"]):
				oldest = s
		return oldest

	func _process(delta: float) -> void:
		# Jeremy 2026-10-04: throttle foam updates 60Hz -> 20Hz.
		# Foam particles drift slowly; 20Hz is visually identical.
		_foam_acc += delta
		if _foam_acc < 0.05:
			return
		var dt: float = _foam_acc
		_foam_acc = 0.0
		for s in _flecks:
			if float(s["age"]) >= float(s["life"]):
				continue
			s["age"] = float(s["age"]) + dt
			# Drift + a gentle sideways wobble so flecks don't move in lockstep.
			var wob := sin(float(s["age"]) * 5.0 \
				+ (s["p"] as Vector2).x * 0.05) * 6.0
			var v: Vector2 = s["v"]
			s["p"] = (s["p"] as Vector2) + Vector2(v.x, v.y + wob) * dt
		for s in _bursts:
			if float(s["age"]) < float(s["life"]):
				s["age"] = float(s["age"]) + dt
		for s in _rings:
			if float(s["age"]) < float(s["life"]):
				s["age"] = float(s["age"]) + dt
		for s in _mist:
			if float(s["age"]) >= float(s["life"]):
				continue
			s["age"] = float(s["age"]) + dt
			s["p"] = (s["p"] as Vector2) + (s["v"] as Vector2) * dt
		queue_redraw()

	func _draw() -> void:
		for s in _flecks:
			var age: float = float(s["age"])
			var life: float = float(s["life"])
			if age >= life:
				continue
			var a: float = 1.0 - age / life
			draw_circle(s["p"], float(s["s"]) * (0.6 + 0.4 * a),
				Color(0.95, 0.98, 1.0, a * 0.85))
		for s in _bursts:
			var age: float = float(s["age"])
			var life: float = float(s["life"])
			if age >= life:
				continue
			var t: float = age / life
			var p: Vector2 = s["p"]
			var rad: float = lerpf(6.0, 30.0, 1.0 - (1.0 - t) * (1.0 - t))
			draw_arc(p, rad, 0.0, TAU, 20, Color(1, 1, 1, (1.0 - t) * 0.8), 3.0)
			for i in 6:
				var ang: float = float(i) * 2.4 + t * 3.0
				draw_circle(p + Vector2(cos(ang), sin(ang)) * rad * 0.7,
					3.0, Color(1, 1, 1, (1.0 - t) * 0.7))
		for s in _rings:
			var age: float = float(s["age"])
			var life: float = float(s["life"])
			if age >= life:
				continue
			var t: float = age / life
			var rad: float = lerpf(10.0, 58.0, t)
			draw_arc(s["p"], rad, 0.0, TAU, 28,
				Color(0.95, 0.98, 1.0, (1.0 - t) * 0.55), 2.5)
		for s in _mist:
			var age: float = float(s["age"])
			var life: float = float(s["life"])
			if age >= life:
				continue
			var t: float = age / life
			draw_circle(s["p"], float(s["s"]) * (1.0 + t * 1.6),
				Color(0.90, 0.93, 0.95, (1.0 - t) * 0.26))
