class_name HeroDestMarker
extends Node2D
## Cursing Gnomes — hero destination marker (port completion).
##
## HTML source of truth: drawHeroDestMarker (fix79 index.html:49584).
## When the player orders the hero to walk, HTML sets
## heroDestMarker = { x, y, life: 1.2 } and draws a yellow X (stroke
## '#ffeb3b', lineWidth 3, arms ±10px) inside a circle (r 8) with
## globalAlpha = min(1, life), culled with inView(x, y, 20). The tick
## (fix79 :52729) drops it once life <= 0.
##
## Improvements over the HTML original:
##   - Attack orders get a marker too (HTML only marked move orders):
##     red '#ef5350' for attack, yellow '#ffeb3b' for move.
##   - Spawn pop: the marker blooms 0.6 -> 1.0 scale over the first 0.12 s
##     so it reads as a confirmation ping, not a sticker.
##   - Zero per-frame cost when idle: _process disables itself and visible
##     goes false while no marker is alive, so _draw short-circuits.
##
## Wired in world.gd _ready() (camera) + _on_tapped_adventure() pushes the
## order position, mirroring HTML setting heroDestMarker next to
## playerHero.playerOrder. Tests drive the pure statics headless.


## HTML-verbatim numbers.
const MARK_LIFE := 1.2            ## heroDestMarker life, seconds
const X_HALF := 10.0              ## X arms: moveTo(x ± 10, y ± 10)
const CIRCLE_R := 8.0             ## circle radius
const LINE_W := 3.0               ## lineWidth 3
const MOVE_COL := Color8(0xff, 0xeb, 0x3b)   ## '#ffeb3b'
const ATTACK_COL := Color8(0xef, 0x53, 0x50) ## '#ef5350' (improvement)
const VIEW_MARGIN := 20.0         ## inView margin, world px

## Spawn-pop envelope (improvement): first 0.12 s scales 0.6 -> 1.0.
const POP_TIME := 0.12
const POP_FROM := 0.6


var _camera: Camera2D = null
var _marker: Dictionary = {}  ## {pos: Vector2, life: float, kind: String}


func _init() -> void:
	z_index = 60  # above tap ripples (50), below HUD CanvasLayer markers


func set_camera(cam: Camera2D) -> void:
	_camera = cam


## HTML: heroDestMarker = { x, y, life: 1.2 } — a single global, so a new
## order replaces the old marker. kind is "move" (HTML) or "attack".
func push(world_pos: Vector2, kind: String = "move") -> void:
	_marker = {"pos": world_pos, "life": MARK_LIFE,
		"kind": kind if kind == "attack" else "move"}
	visible = true
	set_process(true)
	queue_redraw()


## Marker live? (tests / HUD hooks).
func has_marker() -> bool:
	return not _marker.is_empty()


## HTML draw math as a pure function: alpha = min(1, life); pop scale
## blooms 0.6 -> 1.0 over the first 0.12 s (improvement).
static func draw_params(life: float) -> Dictionary:
	var age: float = clampf(MARK_LIFE - life, 0.0, MARK_LIFE)
	var pop: float = POP_FROM + (1.0 - POP_FROM) * clampf(age / POP_TIME, 0.0, 1.0)
	return {
		"alpha": minf(1.0, life),
		"pop": pop,
	}


static func color_for(kind: String) -> Color:
	return ATTACK_COL if kind == "attack" else MOVE_COL


func _process(delta: float) -> void:
	if _marker.is_empty():
		visible = false
		set_process(false)
		return
	_marker["life"] = float(_marker["life"]) - delta
	# HTML tick: drop once life <= 0.
	if float(_marker["life"]) <= 0.0:
		_marker = {}
		visible = false
		set_process(false)
		queue_redraw()
		return
	queue_redraw()


func _visible_rect() -> Rect2:
	if _camera == null:
		return Rect2()
	var vp := get_viewport_rect().size
	var zoom := _camera.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return Rect2()
	var size := Vector2(vp.x / zoom.x, vp.y / zoom.y)
	return Rect2(_camera.get_screen_center_position() - size * 0.5, size)


func _draw() -> void:
	if _marker.is_empty():
		return
	var pos: Vector2 = _marker["pos"]
	var view := _visible_rect().grow(VIEW_MARGIN)
	if view != Rect2() and not view.has_point(pos):
		return  # HTML inView(x, y, 20) cull
	var p := draw_params(float(_marker["life"]))
	var base := color_for(String(_marker["kind"]))
	var col := Color(base.r, base.g, base.b, float(p["alpha"]))
	var s := float(p["pop"])
	var h := X_HALF * s
	# X: HTML verbatim — two strokes from (x ± 10, y ± 10).
	draw_line(pos + Vector2(-h, -h), pos + Vector2(h, h), col, LINE_W, true)
	draw_line(pos + Vector2(h, -h), pos + Vector2(-h, h), col, LINE_W, true)
	# Circle: HTML verbatim — arc r 8.
	draw_arc(pos, CIRCLE_R * s, 0.0, TAU, 32, col, LINE_W, true)
