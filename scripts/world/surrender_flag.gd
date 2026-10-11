class_name SurrenderFlag
extends Node2D
## Cursing Gnomes — surrender ceremony visual (Jeremy 2026-10-04).
##
## A proper white flag of surrender: a wooden pole planted at the losing
## faction's town hall, flying a white cloth that ripples in the wind,
## ringed by a soft golden peace-glow and rising dove-motes. Everything
## is drawn in code (no placeholder art, no textures needed) — the cloth
## is a subdivided strip whose vertices ride a traveling sine wave, the
## pole has wood banding, and the glow is a radial-gradient sprite drawn
## once to a viewport texture.
##
## Lifetime: flies for FLAG_DAYS game-days, then the cloth lowers and the
## node frees itself. The world spawns one per accepted surrender.


## Game days the flag flies before lowering.
const FLAG_DAYS := 3.0
## Real seconds for the lower-and-fade outro.
const OUTRO_SECONDS := 2.5

const POLE_HEIGHT := 120.0
const POLE_WIDTH := 7.0
const CLOTH_LENGTH := 84.0
const CLOTH_HEIGHT := 52.0
const CLOTH_SEGMENTS := 14

## Golden peace-glow color.
const GLOW_COLOR := Color(1.0, 0.9, 0.55, 1.0)

var _age := 0.0          # real seconds since planted
var _day_planted := 1    # game day planted (from the world)
var _outro := false      # lowering the flag
var _outro_age := 0.0
var _phase := 0.0        # wave phase
var _motes: Array = []   # rising peace motes {pos, vel, life, max_life}
var _mote_accum := 0.0
var _glow_tex: Texture2D = null


func _init() -> void:
	z_index = 50  # above buildings, below speech bubbles


## Plant the flag. day_planted is the current game day (for lifetime).
func setup(day_planted: int) -> void:
	_day_planted = day_planted
	_glow_tex = _make_glow_texture()
	# Seed a few motes so the first frame already has life.
	for i: int in range(6):
		_spawn_mote(true)


func _process(delta: float) -> void:
	_age += delta
	_phase += delta * 4.2
	if _outro:
		_outro_age += delta
		if _outro_age >= OUTRO_SECONDS:
			queue_free()
			return
	else:
		_mote_accum += delta
		while _mote_accum > 0.22:
			_mote_accum -= 0.22
			_spawn_mote(false)
	_update_motes(delta)
	queue_redraw()


## Begin the lowering outro (called by the world when FLAG_DAYS pass).
func begin_outro() -> void:
	_outro = true
	_outro_age = 0.0


func _update_motes(delta: float) -> void:
	for i: int in range(_motes.size() - 1, -1, -1):
		var m: Dictionary = _motes[i]
		m["life"] = float(m["life"]) - delta
		if float(m["life"]) <= 0.0:
			_motes.remove_at(i)
			continue
		var p: Vector2 = m["pos"]
		var v: Vector2 = m["vel"]
		# Gentle upward drift with a sideways sway.
		p += v * delta + Vector2(sin(_phase * 0.7 + p.y * 0.05) * 8.0, 0.0) * delta
		m["pos"] = p


func _spawn_mote(anywhere: bool) -> void:
	var base := Vector2(0, -POLE_HEIGHT * 0.5)
	var p := base + Vector2(randf_range(-50, 50), randf_range(-40, 40)) \
		if anywhere else base + Vector2(randf_range(-30, 30), randf_range(0, 20))
	_motes.append({
		"pos": p,
		"vel": Vector2(randf_range(-6, 6), randf_range(-26, -14)),
		"life": randf_range(1.6, 2.8),
		"max_life": 2.8,
		"size": randf_range(2.5, 5.0),
	})


func _draw() -> void:
	var outro_t := 0.0
	if _outro:
		outro_t = clampf(_outro_age / OUTRO_SECONDS, 0.0, 1.0)
	var alpha := 1.0 - outro_t
	var lower := outro_t * (POLE_HEIGHT - CLOTH_HEIGHT - 8.0)
	var top := Vector2(0, -POLE_HEIGHT + lower)

	# Golden peace-glow behind everything.
	if _glow_tex != null and alpha > 0.01:
		var gs := 190.0 * (1.0 - outro_t * 0.5)
		var glow_col := GLOW_COLOR
		glow_col.a = 0.32 * alpha * (0.85 + 0.15 * sin(_phase * 0.8))
		draw_set_transform(Vector2(0, -POLE_HEIGHT * 0.45), 0, Vector2.ONE)
		draw_texture(_glow_tex, -Vector2(gs, gs) * 0.5, glow_col)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Pole: wood shaft with iron bands.
	var pole_col := Color(0.42, 0.28, 0.16, alpha)
	var band_col := Color(0.25, 0.25, 0.28, alpha)
	draw_line(Vector2(-POLE_WIDTH * 0.5, 0), top + Vector2(-POLE_WIDTH * 0.5, 0),
		pole_col, POLE_WIDTH)
	draw_line(Vector2(POLE_WIDTH * 0.5, 0), top + Vector2(POLE_WIDTH * 0.5, 0),
		Color(0.5, 0.34, 0.2, alpha), 2.0)  # highlight edge
	for bf: float in [0.25, 0.55, 0.85]:
		var by: float = -POLE_HEIGHT * bf + lower * bf
		draw_line(Vector2(-POLE_WIDTH * 0.5 - 1.5, by),
			Vector2(POLE_WIDTH * 0.5 + 1.5, by), band_col, 3.0)
	# Brass finial.
	draw_circle(top + Vector2(0, -6), 6.0, Color(0.85, 0.65, 0.25, alpha))
	draw_circle(top + Vector2(-1.5, -7.5), 2.2, Color(1.0, 0.9, 0.6, alpha))

	# White cloth: subdivided strip riding a traveling wave.
	var cloth_top := top + Vector2(POLE_WIDTH * 0.5 + 2.0, 4.0)
	var pts_top: PackedVector2Array = []
	var pts_bot: PackedVector2Array = []
	for i: int in range(CLOTH_SEGMENTS + 1):
		var t: float = float(i) / float(CLOTH_SEGMENTS)
		var wave: float = sin(_phase - t * 4.5) * (6.0 + t * 14.0)
		var droop: float = sin(t * PI) * 6.0
		var x: float = cloth_top.x + t * CLOTH_LENGTH
		pts_top.append(Vector2(x, cloth_top.y + wave * 0.35 - droop * 0.3))
		pts_bot.append(Vector2(x, cloth_top.y + CLOTH_HEIGHT + wave * 0.5 + droop * 0.4))
	var poly := PackedVector2Array()
	poly.append_array(pts_top)
	for i: int in range(pts_bot.size() - 1, -1, -1):
		poly.append(pts_bot[i])
	var cloth_col := Color(0.96, 0.95, 0.92, alpha)
	draw_colored_polygon(poly, cloth_col)
	# Cloth shading: soft fold lines following the wave.
	for i: int in range(1, CLOTH_SEGMENTS):
		var t2: float = float(i) / float(CLOTH_SEGMENTS)
		if sin(_phase - t2 * 4.5) > 0.3:
			draw_line(pts_top[i], pts_bot[i],
				Color(0.82, 0.8, 0.76, alpha * 0.7), 2.0)
	# Hem stitch line.
	draw_polyline(pts_bot, Color(0.75, 0.73, 0.7, alpha), 1.5)

	# Rising peace motes (soft gold sparks).
	for m: Dictionary in _motes:
		var life_f: float = clampf(float(m["life"]) / float(m["max_life"]), 0.0, 1.0)
		var mc := Color(1.0, 0.92, 0.6, alpha * life_f * 0.85)
		draw_circle(m["pos"], float(m["size"]) * (0.5 + life_f * 0.5), mc)

	# Ground shadow ellipse.
	draw_ellipse_poly(Vector2(0, 4), 26.0, 8.0, Color(0, 0, 0, 0.22 * alpha))


## Radial-gradient glow texture, drawn once.
func _make_glow_texture() -> Texture2D:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	for y: int in range(size):
		for x: int in range(size):
			var d: float = Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a  # soft falloff
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# --- helpers ---------------------------------------------------------------

## Godot 4.7 added a native draw_ellipse; this is our own
## polygon-approximation helper under a distinct name.
func draw_ellipse_poly(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i: int in range(20):
		var a: float = TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
