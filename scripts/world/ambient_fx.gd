class_name AmbientFX
extends Node2D
## Cursing Gnomes — ambient life layer (Godot 4 GPU particles).
##
## Jeremy 2026-10-03: "give the game a major graphics update." This makes
## the world feel alive:
##   - Fireflies drift at night (screen-space GPU particles).
##   - Embers rise from live fires (world-space, pooled emitters).
##   - Leaves/pollen drift by season (screen-space, tinted per season).
##   - Cloud shadows: big soft dark blobs drifting over the terrain.
##
## All budgets scale with the graphics tier via set_tier(). Pure visual:
## sim, AI, RNG untouched. GPUParticles2D is supported in gl_compatibility.


const MAX_EMBER_EMITTERS := 6
## Per-system particle counts (iPhone 17 floor budget: fireflies + leaves
## + embers*emitters must stay within GraphicsTiers.BUDGET_AMBIENT_PARTICLES).
const FIREFLY_COUNT := 42
const LEAF_COUNT := 36
const EMBER_COUNT := 24


## Shared soft-dot texture for particles.
static var _dot_tex: Texture2D = null


static func dot_texture() -> Texture2D:
	if _dot_tex != null and is_instance_valid(_dot_tex):
		return _dot_tex
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(float(x) - half + 0.5,
					float(y) - half + 0.5).length() / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


var _cam: Camera2D = null
var _tier := "medium"
var _particle_mul := 0.5
var _map_bounds := Rect2()

var _sky_layer: CanvasLayer = null  # screen-space, follows camera
var _fireflies: GPUParticles2D = null
var _leaves: GPUParticles2D = null
var _ember_pool: Array[GPUParticles2D] = []
var _clouds: Array[Sprite2D] = []
var _cloud_vel: Array[Vector2] = []

var _phase := 0.25
var _weather := "clear"
var _season := "spring"
var _applied_season := ""
var _time := 0.0


func setup(camera: Camera2D, tier: String, map_bounds: Rect2) -> void:
	_cam = camera
	_map_bounds = map_bounds
	set_tier(tier)
	_sky_layer = CanvasLayer.new()
	_sky_layer.name = "AmbientSky"
	_sky_layer.layer = -4  # above weather tint (-5), below HUD
	_sky_layer.follow_viewport_enabled = true
	add_child(_sky_layer)
	_fireflies = _make_fireflies()
	_sky_layer.add_child(_fireflies)
	_leaves = _make_leaves()
	_sky_layer.add_child(_leaves)
	for i in range(MAX_EMBER_EMITTERS):
		var e := _make_embers()
		e.emitting = false
		add_child(e)
		_ember_pool.append(e)
	_make_clouds()


func set_tier(tier: String) -> void:
	_tier = tier
	_particle_mul = float(GraphicsTiers.knobs(tier)["particle_mul"])


func set_phase(phase: float) -> void:
	_phase = phase


func set_weather(kind: String) -> void:
	_weather = kind


func set_season(season: String) -> void:
	_season = season.to_lower()


func _screen_size() -> Vector2:
	if not is_inside_tree():
		return Vector2(1280, 720)
	return get_viewport_rect().size


func _make_fireflies() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Fireflies"
	p.amount = FIREFLY_COUNT
	p.lifetime = 5.0
	p.preprocess = 5.0
	# Wide culling rect: emission box is ±700/±400 around the node; the
	# default AABB would pop particles at screen edges.
	p.visibility_rect = Rect2(Vector2(-900, -700), Vector2(1800, 1400))
	p.texture = dot_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(700, 400, 1)
	m.direction = Vector3(0, 0, 0)
	m.spread = 180.0
	m.initial_velocity_min = 8.0
	m.initial_velocity_max = 26.0
	m.gravity = Vector3.ZERO
	m.damping_min = 20.0
	m.damping_max = 40.0
	m.scale_min = 2.0
	m.scale_max = 4.5
	m.color = Color(0.75, 1.0, 0.45, 0.9)
	p.process_material = m
	# Twinkle: alpha pulses over life.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.3, Color(1, 1, 1, 1))
	ramp.add_point(0.7, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var rg := GradientTexture1D.new()
	rg.gradient = ramp
	m.color_ramp = rg
	return p


func _make_leaves() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Leaves"
	p.amount = LEAF_COUNT
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.visibility_rect = Rect2(Vector2(-900, -700), Vector2(1800, 1400))
	p.texture = dot_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(700, 60, 1)
	m.direction = Vector3(0.35, 1, 0)
	m.spread = 25.0
	m.initial_velocity_min = 30.0
	m.initial_velocity_max = 70.0
	m.gravity = Vector3(0, 22, 0)
	m.scale_min = 2.5
	m.scale_max = 5.0
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.color = Color(0.85, 0.55, 0.25, 0.85)  # autumn default
	p.process_material = m
	return p


func _make_embers() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Embers"
	p.amount = EMBER_COUNT
	p.lifetime = 1.6
	p.visibility_rect = Rect2(Vector2(-400, -400), Vector2(800, 800))
	p.texture = dot_texture()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 14.0
	m.direction = Vector3(0, -1, 0)
	m.spread = 22.0
	m.initial_velocity_min = 60.0
	m.initial_velocity_max = 130.0
	m.gravity = Vector3(0, -40, 0)
	m.scale_min = 2.0
	m.scale_max = 4.0
	m.color = Color(1.0, 0.55, 0.15, 0.95)
	p.process_material = m
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.4, 1))
	ramp.set_color(1, Color(0.6, 0.1, 0.05, 0))
	var rg := GradientTexture1D.new()
	rg.gradient = ramp
	m.color_ramp = rg
	return p


func _make_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654
	for i in range(6):
		var s := Sprite2D.new()
		s.texture = LightingRig.radial_texture()
		s.modulate = Color(0.02, 0.03, 0.08, 0.20)
		var r := 380.0 + rng.randf() * 320.0
		s.scale = Vector2(r / 64.0, r / 96.0)
		s.position = Vector2(
			rng.randf_range(_map_bounds.position.x, _map_bounds.end.x),
			rng.randf_range(_map_bounds.position.y, _map_bounds.end.y))
		s.z_index = -80  # above terrain/grass, below units
		add_child(s)
		_clouds.append(s)
		_cloud_vel.append(Vector2(14.0 + rng.randf() * 10.0,
				3.0 + rng.randf() * 4.0))


## Fire positions (world space); emitters round-robin onto the first N.
func set_fire_positions(positions: PackedVector2Array) -> void:
	var n := mini(_ember_pool.size(), positions.size())
	for i in range(_ember_pool.size()):
		var e := _ember_pool[i]
		if i < n:
			e.position = positions[i]
			e.emitting = true
			e.amount_ratio = _particle_mul
		else:
			e.emitting = false


func _process(delta: float) -> void:
	_time += delta
	var nf: float = LightingRig.night_factor(_phase)
	var stormy := _weather == "rain" or _weather == "storm"
	# _sky_layer has follow_viewport enabled, so its children live in WORLD
	# space: the screen-space emitters must be re-anchored to the camera's
	# world position every frame. (Jeremy 2026-10-04: fireflies were parked
	# at (0,0) = the map corner, off-screen — they never rendered at all.)
	var center := _screen_center()
	# Fireflies: night only, not in storms.
	if _fireflies != null:
		_fireflies.amount_ratio = clampf(_particle_mul * nf, 0.0, 1.0) \
				* (0.0 if stormy else 1.0)
		_fireflies.position = center
	# Leaves: day, seasonal color, gentler in rain.
	if _leaves != null:
		var day_k: float = 1.0 - nf
		_leaves.amount_ratio = clampf(_particle_mul * day_k, 0.0, 1.0) \
				* (0.35 if stormy else 1.0)
		_leaves.position = center + Vector2(0, -380)
		if _season != _applied_season:
			_applied_season = _season
			var m := _leaves.process_material as ParticleProcessMaterial
			if m != null:
				m.color = _season_leaf_color()
	# Cloud shadows drift; wrap around the map.
	for i in range(_clouds.size()):
		var c := _clouds[i]
		c.position += _cloud_vel[i] * delta
		if c.position.x - 500.0 > _map_bounds.end.x:
			c.position.x = _map_bounds.position.x - 400.0
		# Thicker at night, faint at noon.
		var a: float = 0.10 + 0.14 * nf
		c.modulate.a = a


func _screen_center() -> Vector2:
	if _cam != null:
		return _cam.get_screen_center_position()
	return Vector2.ZERO


func _season_leaf_color() -> Color:
	match _season:
		"autumn", "fall":
			return Color(0.85, 0.50, 0.20, 0.85)
		"winter":
			return Color(0.92, 0.94, 1.0, 0.7)  # sparse ice crystals
		"spring":
			return Color(0.65, 0.85, 0.45, 0.8)  # pollen/green
		_:
			return Color(0.55, 0.75, 0.35, 0.75)  # summer green


## Test hook: current firefly emission ratio.
func firefly_ratio() -> float:
	if _fireflies == null:
		return 0.0
	return _fireflies.amount_ratio


## Test hook: how many ember emitters are active.
func active_ember_count() -> int:
	var n := 0
	for e in _ember_pool:
		if e.emitting:
			n += 1
	return n
