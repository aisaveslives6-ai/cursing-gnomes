class_name TraderLayer
extends Node2D
## Cursing Gnomes — Captain Funky Pants world presence (launch-readiness
## gate 1: systems playable & functional).
##
## The traveling trader was sim-complete (SimIndustry.tick_trader visits,
## trade()/deposit(), AI auto-trade) but had NO map presence and NO player
## entry point: trader_arrived/trader_left fired on the bus with zero
## listeners, the funky_pants68.png chibi sprite sat unused in assets, and
## trade()/deposit()/order_gather() had no game-code callers. This layer
## closes the loop:
##   - listens to bus.trader_arrived / trader_left; shows the real anime-
##     chibi sprite (HTML-verbatim 20x46 footprint, feet grounded, facing
##     flip, sin(bob)*2 wander bob) at industry.funky_pos while visiting
##   - a soft gold ring marks the caravan for discoverability (no floating
##     text label — floating labels are out per the 2026-09-28 interiors rule)
##   - tapping the caravan opens the TraderPanel (scripts/ui/trader_panel.gd)
##   - save/load self-heal: if funky_on_map is already true at setup, the
##     caravan spawns immediately instead of waiting for the next signal
##
## Wired by World like TradeWagonLayer (units_root child, so the caravan
## interleaves with units in tree draw order); excluded from
## selection.selectables via the TraderLayer skip in _collect_selectables.
## Camera-culled; zero per-frame cost when the caravan is away.


const TEX_PATH := "res://assets/art/units/funky_pants68.png"
## HTML-verbatim footprint (fix79 draw(): drawImage(tex, -10, -32, 20, 46),
## feet y=+14, head top y=-32) — ~unit height (UnitNode.SPRITE_WORLD_H=44).
const WORLD_H := 46.0
const WORLD_W := 20.0
const TAP_RADIUS := 48.0
const RING_R := 26.0
const RING_GOLD := Color(0.85, 0.68, 0.2, 0.9)


var _bus = null
var _industry = null  ## SimIndustry (untyped: avoids load cycle)
var _camera = null  ## Camera2D live; duck-typed double in headless tests
var _placement = null
var _game = null

var _sprite: Sprite2D = null
var _bob := 0.0
var _facing := 1.0
var _last_pos := Vector2(-9999, -9999)
var _panel: TraderPanel = null
var on_map := false
## Deferred "is adventure input active?" check (Callable, may be invalid).
## In adventure mode taps belong to the hero — the caravan never steals them.
var _adventure_active := Callable()


func _init() -> void:
	visible = false


## Wired by World right after add_child (TradeWagonLayer pattern). The camera
## is untyped on purpose: headless tests drive the layer with a duck-typed
## double (tapped signal + screen_to_world), never a real Camera2D.
## adventure_active_fn is a () -> bool Callable evaluated per tap (adventure
## is created later in World's _ready, so it cannot be passed by value).
func setup(bus, industry, camera, placement, game,
		adventure_active_fn: Callable = Callable()) -> void:
	_bus = bus
	_industry = industry
	_camera = camera
	_placement = placement
	_game = game
	_adventure_active = adventure_active_fn
	if _sprite == null:
		_sprite = Sprite2D.new()
		var tex: Texture2D = load(TEX_PATH) as Texture2D
		_sprite.texture = tex
		if tex != null:
			var sc: float = WORLD_H / float(tex.get_height())
			_sprite.scale = Vector2(sc, sc)
		# Feet grounded: sprite center sits half a body above the node
		# origin (the ground point), matching UnitNode's -h*0.48 pose.
		_sprite.position = Vector2(0, -WORLD_H * 0.5)
		add_child(_sprite)
	if _panel == null:
		_panel = TraderPanel.new()
		add_child(_panel)
		_panel.setup(game)
	if _bus != null:
		if not _bus.trader_arrived.is_connected(_on_trader_arrived):
			_bus.trader_arrived.connect(_on_trader_arrived)
		if not _bus.trader_left.is_connected(_on_trader_left):
			_bus.trader_left.connect(_on_trader_left)
	if _camera != null and not _camera.tapped.is_connected(_on_tapped):
		_camera.tapped.connect(_on_tapped)
	# Save/load self-heal: the bus only fires on transitions, so a loaded
	# save with the caravan mid-visit must spawn the visual immediately.
	if _industry != null and bool(_industry.get("funky_on_map")):
		_spawn(_industry.get("funky_pos"))


func is_trader_here() -> bool:
	return on_map


func _on_trader_arrived(_trader_name: String, pos: Vector2) -> void:
	_spawn(pos)


func _on_trader_left(_trader_name: String) -> void:
	_despawn()


func _spawn(pos: Vector2) -> void:
	on_map = true
	position = pos
	_last_pos = pos
	visible = true
	queue_redraw()


func _despawn() -> void:
	on_map = false
	visible = false
	if _panel != null and is_instance_valid(_panel):
		_panel.close()


func _process(delta: float) -> void:
	if not on_map or _industry == null:
		return
	var p: Vector2 = _industry.get("funky_pos")
	var d: Vector2 = p - _last_pos
	if d.length() > 0.5:
		_facing = 1.0 if d.x >= 0.0 else -1.0
		_last_pos = p
	position = p
	# HTML-verbatim wander bob (fix79: this.bob += dt * 3, sin(bob) * 2).
	_bob += delta * 3.0
	if _sprite != null:
		_sprite.position.y = -WORLD_H * 0.5 + sin(_bob) * 2.0
		_sprite.flip_h = _facing < 0.0
	visible = _in_view()
	queue_redraw()


func _draw() -> void:
	if not on_map:
		return
	# Fallback marker if the sprite ever fails to load — a gold diamond and
	# ring, never a white square.
	if _sprite == null or _sprite.texture == null:
		var pts := PackedVector2Array([Vector2(0, -18), Vector2(14, 0),
			Vector2(0, 18), Vector2(-14, 0)])
		draw_colored_polygon(pts, Color(0.55, 0.36, 0.16))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3],
			pts[0]]), Color(0.25, 0.15, 0.06), 2.0)
	# Discoverability ring: soft gold, gently pulsing.
	var pulse := 0.65 + 0.35 * sin(_bob * 0.7)
	draw_arc(Vector2.ZERO, RING_R, 0.0, TAU, 32,
		Color(RING_GOLD.r, RING_GOLD.g, RING_GOLD.b, 0.9 * pulse), 2.5)
	draw_arc(Vector2.ZERO, RING_R + 5.0, 0.0, TAU, 32,
		Color(RING_GOLD.r, RING_GOLD.g, RING_GOLD.b, 0.3 * pulse), 1.5)


## Tap routing: the layer listens to the camera itself (world's own tap
## handler runs independently; the caravan is NOT in selectables, so taps
## just open the trade panel). Placement/adventure taps never reach here as
## trade taps — placement is guarded, adventure mode has no caravan need.
func _on_tapped(screen_pos: Vector2) -> void:
	if not on_map or not visible or _camera == null:
		return
	if _placement != null and bool(_placement.get("placing")):
		return
	if _adventure_active.is_valid() and bool(_adventure_active.call()):
		return
	var wp: Vector2 = _camera.screen_to_world(screen_pos)
	if wp.distance_to(position) > TAP_RADIUS:
		return
	if _panel != null and is_instance_valid(_panel):
		_panel.open()


func _in_view() -> bool:
	if not (_camera is Camera2D):
		return true
	var vp_size := get_viewport_rect().size
	var zoom: Vector2 = _camera.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return true
	var half := vp_size * 0.5 / zoom
	var view := Rect2(_camera.get_screen_center_position() - half,
		half * 2.0)
	return view.grow(80.0).has_point(position)
