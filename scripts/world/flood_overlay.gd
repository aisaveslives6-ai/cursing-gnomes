class_name FloodOverlay
extends Node2D
## Cursing Gnomes — dramatic flood visuals (Jeremy 2026-10-04: everything
## must have good graphics).
##
## Visual layer over HydroSim:
##   - Expanding translucent flood sheets per active body (pulsing, like the
##     HTML's "pulsing translucent sheet spilling over the shore")
##   - Lakes: expanding ellipse scaled by level + spill radius
##   - Rivers: widened ribbon along the polyline
##   - Animated foam flecks drifting with the current, shimmer arcs
##     (reflection glints), floating debris (planks) near drowned buildings
##   - Mud: brown patches that fade as they dry after the waters recede
##   - Warning stage: thin pulsing edge at the banks before the spill
##
## Pooled particles, one _draw call, no per-frame allocation — same pattern
## as RiverRenderer._FoamLayer. z_index -80: above rivers/terrain (-90),
## below units and buildings so drowned structures read through the water.


const MAX_FLECKS := 90
const MAX_DEBRIS := 40

var _game: GameState = null
var _t := 0.0
var _flecks: Array = []
var _debris: Array = []
var _rng := RandomNumberGenerator.new()
var _spawn_t := 0.0
var _redraw_acc := 0.0  # Jeremy 2026-10-04: 20Hz throttle


func _ready() -> void:
	# z_index -80: above the river layer (-90), below units/props (0).
	z_index = -80
	_rng.seed = 4242
	for i in MAX_FLECKS:
		_flecks.append({"p": Vector2.ZERO, "v": Vector2.ZERO,
			"age": 1.0e9, "life": 1.0, "s": 3.0})
	for i in MAX_DEBRIS:
		_debris.append({"p": Vector2.ZERO, "v": Vector2.ZERO,
			"rot": 0.0, "vr": 0.0, "age": 1.0e9, "life": 1.0, "s": 8.0})


func setup(game: GameState) -> void:
	_game = game
	set_process(true)


func _steal(pool: Array) -> Dictionary:
	var oldest: Dictionary = pool[0]
	for s in pool:
		if float(s["age"]) >= float(s["life"]):
			return s
		if float(s["age"]) > float(oldest["age"]):
			oldest = s
	return oldest


func _process(delta: float) -> void:
	_t += delta
	if _game == null:
		return
	var hydro = _game.get("hydro")
	var active: bool = hydro != null and not hydro.flood_draw_info().is_empty()
	visible = active
	if not active:
		return
	# Animate pools.
	for s in _flecks:
		if float(s["age"]) >= float(s["life"]):
			continue
		s["age"] = float(s["age"]) + delta
		var wob := sin(float(s["age"]) * 6.0 \
			+ (s["p"] as Vector2).x * 0.08) * 10.0
		var v: Vector2 = s["v"]
		s["p"] = (s["p"] as Vector2) + Vector2(v.x, v.y + wob) * delta
	for s in _debris:
		if float(s["age"]) >= float(s["life"]):
			continue
		s["age"] = float(s["age"]) + delta
		s["p"] = (s["p"] as Vector2) + (s["v"] as Vector2) * delta
		s["rot"] = float(s["rot"]) + float(s["vr"]) * delta
	# Spawn foam + debris inside active flood zones.
	_spawn_t += delta
	if _spawn_t >= 0.25:
		_spawn_t = 0.0
		_spawn_in_zones(hydro)
	# Jeremy 2026-10-04: throttle flood redraws 60Hz -> 20Hz.
	_redraw_acc += delta
	if _redraw_acc >= 0.05:
		_redraw_acc = 0.0
		queue_redraw()


func _spawn_in_zones(hydro) -> void:
	for info in hydro.flood_draw_info():
		if not bool(info.get("flooding", false)):
			continue
		var spill := float(info.get("spill", 0.0))
		if String(info.get("kind", "")) == "river":
			var pts: PackedVector2Array = info.get("points",
				PackedVector2Array())
			if pts.size() < 2:
				continue
			var i := _rng.randi_range(0, pts.size() - 2)
			var p := pts[i].lerp(pts[i + 1], _rng.randf())
			var hw := float(info.get("half_width", 40.0)) + spill
			p += Vector2(_rng.randf_range(-hw, hw),
				_rng.randf_range(-hw, hw)) * 0.5
			_spawn_fleck(p, _flow_dir(pts, i) * 60.0)
			if _rng.randf() < 0.25:
				_spawn_debris(p)
		else:
			var c: Vector2 = info.get("pos", Vector2.ZERO)
			var r := float(info.get("radius", 60.0)) + spill
			var a := _rng.randf() * TAU
			var d := sqrt(_rng.randf()) * r
			var p2 := c + Vector2(cos(a), sin(a)) * d
			_spawn_fleck(p2, Vector2(cos(a + 1.7), sin(a + 1.7)) * 34.0)
			if _rng.randf() < 0.2:
				_spawn_debris(p2)


func _flow_dir(pts: PackedVector2Array, i: int) -> Vector2:
	var d := pts[i + 1] - pts[i]
	if d.length_squared() < 1.0:
		return Vector2.DOWN
	return d.normalized()


func _spawn_fleck(pos: Vector2, vel: Vector2) -> void:
	var s := _steal(_flecks)
	s["p"] = pos
	s["v"] = vel
	s["age"] = 0.0
	s["life"] = _rng.randf_range(2.0, 3.4)
	s["s"] = _rng.randf_range(2.5, 5.0)


func _spawn_debris(pos: Vector2) -> void:
	var s := _steal(_debris)
	s["p"] = pos
	s["v"] = Vector2(_rng.randf_range(-24, 24), _rng.randf_range(-14, 30))
	s["rot"] = _rng.randf() * TAU
	s["vr"] = _rng.randf_range(-1.2, 1.2)
	s["age"] = 0.0
	s["life"] = _rng.randf_range(4.0, 7.0)
	s["s"] = _rng.randf_range(6.0, 12.0)


func _draw() -> void:
	if _game == null:
		return
	var hydro = _game.get("hydro")
	if hydro == null:
		return
	var pulse := 0.5 + 0.5 * sin(_t * 2.6)
	for info in hydro.flood_draw_info():
		_draw_body(info, pulse)
	_draw_mud(hydro)
	_draw_flecks()
	_draw_debris()


func _draw_body(info: Dictionary, pulse: float) -> void:
	var lvl := float(info.get("level", 0.5))
	var flooding := bool(info.get("flooding", false))
	var spill := float(info.get("spill", 0.0))
	# Alpha ramps with severity: warning = thin edge, flood = deep sheet.
	var alpha := 0.22 + 0.30 * pulse if flooding else 0.10 + 0.08 * pulse
	var water := Color(0.20, 0.50, 0.85, alpha)
	var deep := Color(0.10, 0.32, 0.66, alpha * 0.85)
	var edge := Color(0.65, 0.85, 1.0, 0.35 + 0.25 * pulse)
	if String(info.get("kind", "")) == "river":
		_draw_river(info, water, deep, edge, spill, pulse)
	else:
		_draw_lake(info, water, deep, edge, spill, pulse)


func _draw_lake(info: Dictionary, water: Color, deep: Color, edge: Color,
		spill: float, pulse: float) -> void:
	var c: Vector2 = info.get("pos", Vector2.ZERO)
	var r := float(info.get("radius", 60.0)) + spill
	# Outer sheet (spill zone) then the swollen lake core.
	draw_circle(c, r, water)
	draw_circle(c, r * 0.72, deep)
	# Foam ring lapping at the flood edge + reflection glints.
	var segs := 40
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var rr := r * (1.0 + 0.02 * sin(_t * 3.0 + a * 3.0))
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	pts.append(pts[0])
	draw_polyline(pts, edge, 5.0, true)
	# Shimmer arcs: curved glints drifting across the sheet.
	for k in 3:
		var a0 := _t * 0.35 + float(k) * TAU / 3.0
		var arc := PackedVector2Array()
		for j in 7:
			var a := a0 + float(j) * 0.12
			arc.append(c + Vector2(cos(a), sin(a)) * r * 0.55)
		draw_polyline(arc, Color(1, 1, 1, 0.18 + 0.10 * pulse), 3.0, true)


func _draw_river(info: Dictionary, water: Color, deep: Color, edge: Color,
		spill: float, pulse: float) -> void:
	var pts: PackedVector2Array = info.get("points", PackedVector2Array())
	if pts.size() < 2:
		return
	var hw := float(info.get("half_width", 40.0)) + spill
	# Wide translucent ribbon + darker core current + bright banks.
	draw_polyline(pts, water, hw * 2.0, true)
	draw_polyline(pts, deep, hw * 1.1, true)
	# Bank foam: offset polylines on both sides.
	for side in [-1.0, 1.0]:
		var bank := PackedVector2Array()
		for i in range(pts.size()):
			var dir := Vector2.DOWN
			if i < pts.size() - 1:
				dir = (pts[i + 1] - pts[i]).normalized()
			elif i > 0:
				dir = (pts[i] - pts[i - 1]).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var wob := sin(_t * 4.0 + float(i) * 0.8) * 4.0
			bank.append(pts[i] + nrm * side * (hw + wob))
		draw_polyline(bank, edge, 4.0, true)


func _draw_mud(hydro) -> void:
	var now := _game.game_time
	for m in hydro.mud_patches:
		var until := float(m.get("until", 0.0))
		if until <= now:
			continue
		var total := HydroSim.MUD_DURATION * Config.DAY_LENGTH_SECONDS
		var frac := clampf((until - now) / total, 0.0, 1.0)
		var c: Vector2 = m.get("pos", Vector2.ZERO)
		var r := float(m.get("radius", 100.0))
		# Squelchy brown, fading as it dries.
		draw_circle(c, r, Color(0.32, 0.22, 0.12, 0.30 * frac))
		draw_arc(c, r * 0.7, 0.4, 2.4, 24,
			Color(0.25, 0.17, 0.09, 0.35 * frac), 8.0, true)


func _draw_flecks() -> void:
	for s in _flecks:
		var age := float(s["age"])
		var life := float(s["life"])
		if age >= life:
			continue
		var fade := 1.0 - age / life
		draw_circle(s["p"], float(s["s"]),
			Color(0.90, 0.96, 1.0, 0.55 * fade))


func _draw_debris() -> void:
	for s in _debris:
		var age := float(s["age"])
		var life := float(s["life"])
		if age >= life:
			continue
		var fade := 1.0 - age / life
		var p: Vector2 = s["p"]
		var sz := float(s["s"])
		var rot := float(s["rot"])
		# Drifting plank: rotated brown rect.
		var col := Color(0.42, 0.30, 0.18, 0.85 * fade)
		var d := Vector2(cos(rot), sin(rot)) * sz
		var d2 := Vector2(-d.y, d.x) * 0.35
		draw_colored_polygon(
			[p - d - d2, p + d - d2, p + d + d2, p - d + d2], col)
