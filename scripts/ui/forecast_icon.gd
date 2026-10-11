class_name ForecastIcon
extends Control
## Small drawn icon for the phone Forecast app. All visuals are Godot
## primitives (circles, polygons, lines) — NO emoji, NO unicode symbols
## (Jeremy's iPhone tofu rule, 2026-10-03).
##
## kind: "clear" | "cloudy" | "rain" | "storm" | "snow" | "fog"
##       | "festival" | "disaster" (uses accent color dot)
## accent: color for the "disaster" kind marker.

var kind: String = "clear"
var accent: Color = Color(0.9, 0.25, 0.25)
## When true (disaster striking today), the marker pulses urgently.
var urgent: bool = false
## Animation clock, advanced in _process.
var time: float = 0.0


static func make(p_kind: String, p_accent: Color = Color(0.9, 0.25, 0.25),
		icon_px: float = 56.0, p_urgent: bool = false) -> ForecastIcon:
	var i := ForecastIcon.new()
	i.kind = p_kind
	i.accent = p_accent
	i.urgent = p_urgent
	i.custom_minimum_size = Vector2(icon_px, icon_px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.30
	match kind:
		"clear":
			_draw_sun(c, r)
		"cloudy":
			_draw_cloud(c, r, Color(0.72, 0.72, 0.78))
		"rain":
			_draw_rain(c, r)
		"storm":
			_draw_storm(c, r)
		"snow":
			_draw_snow(c, r)
		"fog":
			_draw_fog(c, r)
		"festival":
			_draw_starburst(c, r * 1.15, Color(1.0, 0.84, 0.35))
		"disaster":
			_draw_disaster_dot(c, r, accent)
		_:
			_draw_disaster_dot(c, r, accent)


func _draw_sun(c: Vector2, r: float) -> void:
	var gold := Color(1.0, 0.82, 0.25)
	# Rays slowly rotate; core gently breathes.
	var spin := time * 0.6
	var breathe := 1.0 + 0.06 * sin(time * 2.2)
	for k in 8:
		var a := spin + TAU * float(k) / 8.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 1.25, c + d * r * 1.75, gold, 3.0, true)
	draw_circle(c, r * breathe, gold)
	draw_circle(c, r * 0.72 * breathe, Color(1.0, 0.92, 0.55))


func _cloud_shape(c: Vector2, r: float, col: Color) -> void:
	# Three overlapping circles + a flat base = cartoon cloud.
	draw_circle(c + Vector2(-r * 0.85, r * 0.15), r * 0.62, col)
	draw_circle(c + Vector2(0.0, -r * 0.35), r * 0.85, col)
	draw_circle(c + Vector2(r * 0.85, r * 0.15), r * 0.62, col)
	draw_rect(Rect2(c + Vector2(-r * 1.35, -r * 0.05),
		Vector2(r * 2.7, r * 0.75)), col)


func _draw_cloud(c: Vector2, r: float, col: Color) -> void:
	# Cloud drifts side to side.
	var drift := Vector2(sin(time * 0.9) * r * 0.18, 0.0)
	_cloud_shape(c + Vector2(0, -r * 0.25) + drift, r, col)


func _draw_rain(c: Vector2, r: float) -> void:
	var drift := Vector2(sin(time * 0.9) * r * 0.18, 0.0)
	_cloud_shape(c + Vector2(0, -r * 0.55) + drift, r * 0.9,
		Color(0.62, 0.64, 0.70))
	var blue := Color(0.35, 0.62, 1.0)
	for k in 3:
		var x := c.x + (float(k) - 1.0) * r * 0.75
		# Drops fall: cycle a 0..1 phase, staggered per drop.
		var phase := fposmod(time * 1.6 + float(k) * 0.33, 1.0)
		var dy := lerpf(-r * 0.25, r * 0.75, phase)
		var alpha := 1.0 - phase * 0.55
		var drop_col := Color(blue.r, blue.g, blue.b, alpha)
		var top := Vector2(x + r * 0.18, c.y + r * 0.45 + dy)
		var bot := Vector2(x - r * 0.18, c.y + r * 1.05 + dy)
		draw_line(top, bot, drop_col, 4.0, true)
		draw_circle(bot, 3.0, drop_col)


func _draw_storm(c: Vector2, r: float) -> void:
	var drift := Vector2(sin(time * 0.9) * r * 0.18, 0.0)
	_cloud_shape(c + Vector2(0, -r * 0.55) + drift, r * 0.9,
		Color(0.38, 0.40, 0.46))
	# Lightning flashes: bright most of the cycle, brief dim flicker.
	var flash := 1.0
	var cyc := fposmod(time * 1.4, 1.0)
	if cyc > 0.82 and cyc < 0.90:
		flash = 0.25
	var bolt := PackedVector2Array([
		c + Vector2(r * 0.15, r * 0.15),
		c + Vector2(-r * 0.35, r * 0.85),
		c + Vector2(-r * 0.02, r * 0.85),
		c + Vector2(-r * 0.15, r * 1.55),
		c + Vector2(r * 0.38, r * 0.70),
		c + Vector2(r * 0.05, r * 0.70),
	])
	draw_colored_polygon(bolt, Color(1.0, 0.85, 0.20, flash))


func _draw_snow(c: Vector2, r: float) -> void:
	var drift := Vector2(sin(time * 0.9) * r * 0.18, 0.0)
	_cloud_shape(c + Vector2(0, -r * 0.55) + drift, r * 0.9,
		Color(0.80, 0.83, 0.90))
	var white := Color(0.95, 0.97, 1.0)
	for k in 3:
		# Flakes drift down and sway, staggered per flake.
		var phase := fposmod(time * 0.7 + float(k) * 0.33, 1.0)
		var sway := sin(time * 2.0 + float(k) * 2.1) * r * 0.18
		var p := c + Vector2((float(k) - 1.0) * r * 0.75 + sway,
			r * 0.55 + phase * r * 0.75)
		var fade := 1.0 - phase * 0.4
		var flake := Color(white.r, white.g, white.b, fade)
		# Six-spoke flake.
		for s in 3:
			var a := PI * float(s) / 3.0 + time * 0.8
			var d := Vector2(cos(a), sin(a)) * r * 0.22
			draw_line(p - d, p + d, flake, 2.5, true)
		draw_circle(p, 2.5, flake)


func _draw_fog(c: Vector2, r: float) -> void:
	var gray := Color(0.70, 0.70, 0.72)
	for k in 3:
		var y := c.y + (float(k) - 1.0) * r * 0.55
		var w := r * (1.5 - 0.25 * absf(float(k) - 1.0))
		# Bands slide horizontally, alternating direction.
		var slide := sin(time * 1.1 + float(k) * PI) * r * 0.25
		draw_line(Vector2(c.x - w + slide, y), Vector2(c.x + w + slide, y),
			gray, 5.0, true)


func _draw_starburst(c: Vector2, r: float, col: Color) -> void:
	# 8-point celebratory star: slow spin + shimmer pulse.
	var spin := time * 0.5
	var shimmer := 1.0 + 0.08 * sin(time * 3.0)
	var pts := PackedVector2Array()
	for k in 16:
		var a := spin + TAU * float(k) / 16.0 - PI / 2.0
		var rr := (r if k % 2 == 0 else r * 0.45) * shimmer
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
	draw_circle(c, r * 0.22 * shimmer, Color(1.0, 0.97, 0.80))


func _draw_disaster_dot(c: Vector2, r: float, col: Color) -> void:
	# Warning diamond with dark outline. Urgent (today) markers pulse.
	var pulse := 1.0
	if urgent:
		pulse = 1.0 + 0.12 * sin(time * 5.0)
		col = col.lightened(0.15 * (0.5 + 0.5 * sin(time * 5.0)))
	var pts := PackedVector2Array([
		c + Vector2(0, -r * 1.25 * pulse),
		c + Vector2(r * 1.25 * pulse, 0),
		c + Vector2(0, r * 1.25 * pulse),
		c + Vector2(-r * 1.25 * pulse, 0),
	])
	draw_colored_polygon(pts, col)
	var inner := PackedVector2Array([
		c + Vector2(0, -r * 0.85 * pulse),
		c + Vector2(r * 0.85 * pulse, 0),
		c + Vector2(0, r * 0.85 * pulse),
		c + Vector2(-r * 0.85 * pulse, 0),
	])
	draw_colored_polygon(inner, col.lightened(0.25))
