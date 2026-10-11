class_name RepoFX
extends Node2D
## Cursing Gnomes — Ricky the Repo Gnome bespoke FX (wake routine
## 2026-10-08, Disaster #28 completion).
##
## Ricky drags buildings off the map with his tow truck. This rig sells
## the repo: a heavy tow chain with a hook swaying from his hand, amber
## hazard chevrons pulsing on the ground under the truck, and foreclosure
## paperwork fluttering up while he works. Pure _draw, ASCII-safe,
## freeze-position law honored (the node never moves the unit; it only
## draws around the body anchor).

const CHAIN_LINKS := 7
const PAPER_COUNT_MAX := 10

# World-space height of the monster sprite this rig decorates (set by
# UnitNode._build_repo_fx, like the other monster rigs). All draw
# coordinates scale by stage_h / 64 so the chain, papers, and chevrons
# track the sprite at any monster scale.
var stage_h := 64.0

var _t := 0.0
var _papers := []  # Array[Dictionary]: pos, vel, rot, rot_vel, life, max_life
var _paper_accum := 0.0

# A foreclosure notice flutters off the clipboard about every 0.9 s.
const PAPER_PERIOD := 0.9


func _ready() -> void:
	# Above the sprite: the chain, hook, and paperwork wash OVER the cap
	# and clipboard. The FX is built before _sprite joins _body (see
	# UnitNode._build), so child order alone would bury it — z_index pins
	# it on top, like the other monster rigs (buried-FX lesson,
	# doomscroll 2026-10-08).
	z_index = 2


func _process(delta: float) -> void:
	_t += delta
	_paper_accum += delta
	if _paper_accum >= PAPER_PERIOD and _papers.size() < PAPER_COUNT_MAX:
		_paper_accum = 0.0
		_spawn_paper()
	_tick_particles(delta)
	queue_redraw()


func _spawn_paper() -> void:
	_papers.append({
		"pos": Vector2(randf_range(-14.0, 14.0), randf_range(-34.0, -20.0)),
		"vel": Vector2(randf_range(-14.0, 14.0), randf_range(-34.0, -18.0)),
		"rot": randf() * TAU,
		"rot_vel": randf_range(-3.0, 3.0),
		"life": 0.0, "max_life": randf_range(1.6, 2.4),
		"w": randf_range(7.0, 10.0), "h": randf_range(9.0, 13.0),
	})


func _tick_particles(delta: float) -> void:
	for p in _papers:
		p["life"] = float(p["life"]) + delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["rot"] = float(p["rot"]) + float(p["rot_vel"]) * delta
	_papers = _papers.filter(func(p): return float(p["life"]) < float(p["max_life"]))


func _draw() -> void:
	var s := stage_h / 64.0
	# Tow chain: heavy steel links draping from his left hand, swaying
	# with a slow pendulum as he walks the repo beat.
	var sway := sin(_t * 1.7) * 6.0 * s
	var hand := Vector2(-20.0 * s, -18.0 * s)
	var prev := hand
	var link_col := Color(0.62, 0.65, 0.7, 0.95)
	for i in CHAIN_LINKS:
		var f := float(i + 1) / float(CHAIN_LINKS)
		var nxt := hand + Vector2(sway * f, (10.0 + 6.0 * f) * f * s)
		# Each link reads as a small ring: dark outline + steel core.
		var mid := (prev + nxt) * 0.5
		var link_r := 4.2 * s
		draw_circle(mid, link_r, Color(0.25, 0.27, 0.3, 0.95))
		draw_circle(mid, link_r * 0.62, link_col)
		draw_line(prev, nxt, Color(0.25, 0.27, 0.3, 0.0), 1.0)
		prev = nxt
	# The hook: a curved claw at the chain's end with a glint that
	# sweeps as it sways.
	var hook := prev + Vector2(sway * 0.12, 6.0 * s)
	draw_arc(hook, 7.0 * s, -0.4, 2.6, 12, Color(0.25, 0.27, 0.3, 0.95), 4.5 * s, true)
	draw_arc(hook, 7.0 * s, -0.4, 2.6, 12, link_col, 2.0 * s, true)
	var glint_a := 0.5 + 0.5 * sin(_t * 3.1)
	draw_circle(hook + Vector2(-3.0 * s, -4.0 * s), 1.8 * s,
		Color(1, 1, 1, 0.75 * glint_a))
	# Hazard chevrons: an amber ring pulsing on the ground under the
	# truck — the repo zone. Nobody parks here.
	var pulse := 0.5 + 0.5 * sin(_t * 2.6)
	var ring_r := 30.0 * s
	var ring_a := 0.3 + 0.25 * pulse
	for i in 12:
		var a0 := TAU * float(i) / 12.0 + _t * 0.35
		var a1 := TAU * float(i + 0.55) / 12.0 + _t * 0.35
		var c0 := Vector2(cos(a0), sin(a0) * 0.62) * ring_r
		var c1 := Vector2(cos(a1), sin(a1) * 0.62) * ring_r
		draw_line(c0 + Vector2(0, 6.0 * s), c1 + Vector2(0, 6.0 * s),
			Color(1.0, 0.62, 0.1, ring_a), 3.5 * s)
	# Foreclosure paperwork: white slips with red "PAST DUE" bars
	# fluttering off the clipboard.
	for p in _papers:
		var a := 1.0 - float(p["life"]) / float(p["max_life"])
		var pp: Vector2 = (p["pos"] as Vector2) * s
		var w: float = float(p["w"]) * s
		var h: float = float(p["h"]) * s
		var rot: float = float(p["rot"])
		var d := Vector2(cos(rot), sin(rot))
		var n := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([
			pp - d * w * 0.5 - n * h * 0.5,
			pp + d * w * 0.5 - n * h * 0.5,
			pp + d * w * 0.5 + n * h * 0.5,
			pp - d * w * 0.5 + n * h * 0.5,
		])
		draw_colored_polygon(pts, Color(0.96, 0.94, 0.88, 0.92 * a))
		# Red PAST-DUE bar across the top of the slip.
		var bar := PackedVector2Array([
			pp - d * w * 0.5 - n * h * 0.5,
			pp + d * w * 0.5 - n * h * 0.5,
			pp + d * w * 0.5 - n * h * 0.18,
			pp - d * w * 0.5 - n * h * 0.18,
		])
		draw_colored_polygon(bar, Color(0.85, 0.15, 0.12, 0.9 * a))


## Test hook: how many live particles are on stage.
func live_counts() -> Dictionary:
	return {"papers": _papers.size()}
