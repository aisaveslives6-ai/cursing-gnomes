class_name RubbleLayer
extends Node2D
## Cursing Gnomes — AoE-style rubble piles where buildings fell (port completion).
##
## HTML source of truth: spawnRubble / drawRubbleMound / tapClearRubble +
## the rubble aging tick (fix79 index.html, "AoE-style rubble piles where
## buildings fell (tap to clear)"). HTML-verbatim numbers:
##   - pile: {x, y, race, type, size: b.size || 36, life: 1, maxLife: 1,
##     age: 0, seed: rand * 100}; cap 60, oldest dropped first
##   - tick: age += dt; if age > 150: life -= dt * 0.5, remove at life <= 0
##   - draw: fade = min(1, life * 3); dust puffs while age < 4 (0.15/frame);
##     shadow + two-tone mound + 9 seeded stones + 4 broken beams;
##     faint smoke while age < 25 at y = -S*0.5 - ((t*12 + seed*10) % 36)
##   - tap to clear within max(30, size * 0.7), newest pile first
##
## Improvements over the HTML original:
##   - Settling dust and tap-clear "dust puffs" are drawn particles, NOT the
##     HTML's floating '💨' emoji texts (glyph renders as tofu on iPhone).
##   - Zero per-frame cost when idle: _process self-disables and the node
##     hides while no piles or puffs are alive (same pattern as TapRipples).
##   - Camera-view culling per pile with the same inView(size + 40) margin.
##
## Wired in world.gd: created in _ready() (camera), spawn() from
## _on_building_destroyed (the single building_destroyed funnel), and
## tap_clear() in _on_tapped before target selection — mirroring HTML
## handleTap ("Tap rubble piles to clear them").
## Tests drive the pure statics and the spawn/step/tap helpers headless.


## HTML-verbatim numbers.
const MAX_PILES := 60          ## cap; oldest dropped first
const FADE_AGE := 150.0        ## seconds before the fade-out begins
const FADE_RATE := 0.5         ## life -= dt * 0.5 past FADE_AGE (2 s fade)
const DUST_AGE := 4.0          ## settling dust while age < 4
const DUST_CHANCE := 0.15      ## per-frame dust spawn chance (60 fps base)
const SMOKE_AGE := 25.0        ## faint smoke while age < 25
const CLEAR_BASE := 30.0       ## clear radius = max(30, size * 0.7)
const VIEW_MARGIN := 40.0      ## inView(r.x, r.y, size + 40)
const DEFAULT_SIZE := 36.0     ## b.size || 36
const PUFF_LIFE := 0.6         ## drawn dust-puff lifetime, seconds
const MAX_PUFFS := 48          ## drawn dust-puff cap (improvement)

const COL_DUST := Color(150.0 / 255.0, 140.0 / 255.0, 130.0 / 255.0, 0.35)
const COL_SHADOW := Color(0, 0, 0, 0.22)
const COL_MOUND := Color8(0x8d, 0x7d, 0x6d)
const COL_MOUND_HI := Color8(0xa8, 0x98, 0x88)
const COL_STONE_A := Color8(0x7a, 0x6f, 0x64)
const COL_STONE_B := Color8(0x5d, 0x56, 0x4d)
const COL_BEAM := Color8(0x5d, 0x40, 0x37)
const COL_SMOKE := Color(90.0 / 255.0, 90.0 / 255.0, 90.0 / 255.0, 0.25)


var _camera: Camera2D = null
var _piles: Array = []  ## Dictionaries {pos, size, race, type, life, age, seed}
var _puffs: Array = []  ## Dictionaries {pos, vel, life, size} (drawn dust)
var _time := 0.0


func _init() -> void:
	# Ground debris: above terrain overlays, below units/buildings.
	z_index = -40


func set_camera(cam: Camera2D) -> void:
	_camera = cam


## HTML spawnRubble(b): push the pile, drop the oldest past the cap.
func spawn(building: Dictionary) -> Dictionary:
	var pile := {
		"pos": building.get("position", Vector2.ZERO),
		"size": float(building.get("size", DEFAULT_SIZE)),
		"race": building.get("race", ""),
		"type": building.get("type", ""),
		"life": 1.0,
		"age": 0.0,
		"seed": randf() * 100.0,
	}
	_piles.append(pile)
	while _piles.size() > MAX_PILES:
		_piles.pop_front()
	visible = true
	set_process(true)
	return pile


## Number of live piles (tests / HUD hooks).
func pile_count() -> int:
	return _piles.size()


## HTML rubble aging tick: age += dt; past FADE_AGE, life -= dt * 0.5.
## Returns the number of piles removed this step.
func step(delta: float) -> int:
	_time += delta
	var removed := 0
	for i in range(_piles.size() - 1, -1, -1):
		var p: Dictionary = _piles[i]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) > FADE_AGE:
			p["life"] = float(p["life"]) - delta * FADE_RATE
			if float(p["life"]) <= 0.0:
				_piles.remove_at(i)
				removed += 1
		elif float(p["age"]) < DUST_AGE and randf() < DUST_CHANCE * delta * 60.0:
			_spawn_puff(Vector2(float(p["pos"].x) + randf_range(-0.5, 0.5) * float(p["size"]),
					float(p["pos"].y) - float(p["size"]) * 0.3 - randf() * 10.0),
				randf_range(8.0, 16.0))
	_step_puffs(delta)
	if _piles.is_empty() and _puffs.is_empty():
		visible = false
		set_process(false)
	queue_redraw()
	return removed


## HTML tapClearRubble: newest pile within max(30, size * 0.7) is cleared.
## Returns the cleared pile, or {} when no pile was under the tap.
## HTML floated '💨' texts on clear; we spawn drawn dust puffs instead
## (emoji = tofu on iPhone).
func tap_clear(world_pos: Vector2) -> Dictionary:
	for i in range(_piles.size() - 1, -1, -1):
		var p: Dictionary = _piles[i]
		var s: float = float(p["size"])
		if world_pos.distance_to(p["pos"]) < maxf(CLEAR_BASE, s * 0.7):
			_piles.remove_at(i)
			for k in range(6):
				_spawn_puff(Vector2(float(p["pos"].x) + randf_range(-15.0, 15.0),
						float(p["pos"].y) - randf() * 20.0),
					randf_range(6.0, 12.0))
			if _piles.is_empty() and _puffs.is_empty():
				visible = false
				set_process(false)
			queue_redraw()
			return p
	return {}


func _spawn_puff(pos: Vector2, size: float) -> void:
	_puffs.append({
		"pos": pos,
		"vel": Vector2(randf_range(-14.0, 14.0), randf_range(-26.0, -10.0)),
		"life": PUFF_LIFE,
		"size": size,
	})
	while _puffs.size() > MAX_PUFFS:
		_puffs.pop_front()
	visible = true
	set_process(true)


func _step_puffs(delta: float) -> void:
	for i in range(_puffs.size() - 1, -1, -1):
		var d: Dictionary = _puffs[i]
		d["life"] = float(d["life"]) - delta
		if float(d["life"]) <= 0.0:
			_puffs.remove_at(i)
			continue
		d["pos"] = Vector2(d["pos"]) + Vector2(d["vel"]) * delta
		d["vel"] = Vector2(d["vel"]) * (1.0 - 2.2 * delta)


func _process(delta: float) -> void:
	step(delta)


## HTML drawRubbleMound alpha: fade = min(1, life * 3).
static func fade_alpha(life: float) -> float:
	return maxf(0.0, minf(1.0, life * 3.0))


## HTML seeded scatter: rnd(i) = fract(sin(seed * 12.9 + i * 78.2) * 43758.5).
static func seeded(seed: float, i: float) -> float:
	return fposmod(sin(seed * 12.9 + i * 78.2) * 43758.5, 1.0)


## One scattered stone's draw params (HTML-verbatim): center, size, angle,
## and which of the two stone colors (i % 3 ? A : B).
static func stone_params(seed: float, size: float, i: int) -> Dictionary:
	var sx: float = (seeded(seed, float(i)) - 0.5) * size * 1.3
	var sy: float = size * 0.3 - seeded(seed, float(i) + 40.0) * size * 0.5
	var sr: float = 3.0 + seeded(seed, float(i) + 80.0) * maxf(3.0, size * 0.09)
	return {
		"pos": Vector2(sx, sy),
		"size": sr,
		"angle": seeded(seed, float(i) + 120.0) * 3.0,
		"color_b": i % 3 == 0,
	}


## One broken beam's draw params (HTML-verbatim): endpoints + line width.
static func beam_params(seed: float, size: float, i: int) -> Dictionary:
	var bx: float = (seeded(seed, float(i) + 200.0) - 0.5) * size
	var by: float = size * 0.25 - seeded(seed, float(i) + 240.0) * size * 0.35
	var ex: float = bx + (seeded(seed, float(i) + 300.0) - 0.5) * size * 0.8
	var ey: float = by - seeded(seed, float(i) + 320.0) * size * 0.4
	return {
		"from": Vector2(bx, by),
		"to": Vector2(ex, ey),
		"width": 3.0 + seeded(seed, float(i) + 280.0) * 3.0,
	}


## Smoke wisp center (HTML-verbatim): rises 36 px over its cycle, sways.
static func smoke_pos(seed: float, size: float, t: float) -> Vector2:
	return Vector2(sin(t + seed) * 8.0,
		-size * 0.5 - fposmod(t * 12.0 + seed * 10.0, 36.0))


func _visible_rect() -> Rect2:
	if _camera == null:
		return Rect2()
	var vp := get_viewport_rect().size
	var zoom := _camera.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return Rect2()
	var size := Vector2(vp.x / zoom.x, vp.y / zoom.y)
	return Rect2(_camera.get_screen_center_position() - size * 0.5, size)


func _pile_in_view(p: Dictionary, view: Rect2) -> bool:
	var margin: float = float(p["size"]) + VIEW_MARGIN
	return view.grow(margin).has_point(p["pos"])


func _draw() -> void:
	var view := _visible_rect()
	for v: Variant in _piles:
		var p: Dictionary = v
		if _camera != null and not _pile_in_view(p, view):
			continue
		_draw_pile(p)
	for d: Variant in _puffs:
		_draw_puff(d)


## HTML drawRubbleMound, translated to Godot draw calls.
func _draw_pile(p: Dictionary) -> void:
	var s: float = float(p["size"])
	var seed: float = float(p["seed"])
	var base := Vector2(p["pos"])
	var alpha: float = fade_alpha(float(p["life"]))
	# Ground shadow.
	draw_colored_polygon(_ellipse(base + Vector2(0, s * 0.35), s * 0.85, s * 0.22, 20),
		Color(COL_SHADOW, COL_SHADOW.a * alpha))
	# Mound (top half) + lighter cap.
	draw_colored_polygon(_half_ellipse(base + Vector2(0, s * 0.18), s * 0.8, s * 0.42, 20),
		Color(COL_MOUND, alpha))
	draw_colored_polygon(_half_ellipse(base + Vector2(-s * 0.15, s * 0.05), s * 0.45, s * 0.25, 16, -0.2),
		Color(COL_MOUND_HI, alpha))
	# 9 seeded scattered stones.
	for i in range(9):
		var st := stone_params(seed, s, i)
		var c := COL_STONE_B if bool(st["color_b"]) else COL_STONE_A
		var sr: float = float(st["size"])
		var ang: float = float(st["angle"])
		var pts := PackedVector2Array([
			base + Vector2(st["pos"]) + Vector2(-sr, -sr * 0.7).rotated(ang),
			base + Vector2(st["pos"]) + Vector2(sr, -sr * 0.7).rotated(ang),
			base + Vector2(st["pos"]) + Vector2(sr, sr * 0.7).rotated(ang),
			base + Vector2(st["pos"]) + Vector2(-sr, sr * 0.7).rotated(ang),
		])
		draw_colored_polygon(pts, Color(c, alpha))
	# 4 broken beams.
	for i in range(4):
		var bm := beam_params(seed, s, i)
		draw_line(base + Vector2(bm["from"]), base + Vector2(bm["to"]),
			Color(COL_BEAM, alpha), float(bm["width"]), true)
	# Faint smoke for a while after the collapse.
	if float(p["age"]) < SMOKE_AGE:
		var sp := smoke_pos(seed, s, _time)
		draw_colored_polygon(_ellipse(base + sp, 9.0, 13.0, 14),
			Color(COL_SMOKE, COL_SMOKE.a * alpha))


func _draw_puff(d: Dictionary) -> void:
	var k: float = 1.0 - float(d["life"]) / PUFF_LIFE  # 0 -> 1
	var sz: float = float(d["size"]) * (1.0 + k * 1.6)
	var a: float = COL_DUST.a * (1.0 - k)
	draw_colored_polygon(_ellipse(Vector2(d["pos"]), sz, sz * 0.6, 12),
		Color(COL_DUST, a))


## Full ellipse as a polygon.
static func _ellipse(center: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Top-half ellipse as a polygon (HTML arc from PI to 2*PI), with rotation.
static func _half_ellipse(center: Vector2, rx: float, ry: float, n: int,
		rot: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var a: float = PI + PI * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts
