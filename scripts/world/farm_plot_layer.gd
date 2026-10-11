class_name FarmPlotLayer
extends Node2D
## Cursing Gnomes — farm plot renderer (draws SimFarming plots).
##
## Launch-readiness 2026-10-05 (gate 2, graphics): the auto-plots pass gave
## every farm/farmhouse a working 4x4 field, but plots were pure sim state
## with zero map rendering — farms grew invisible food. This layer renders
## each plot as an isometric tilled-soil bed sunk into the ground plane,
## with per-tile crop growth (from tiles[i].g), watered-soil darkening,
## gently swaying sprouts, and a faction-color marker post.
##
## Mirrors TradeWagonLayer: provider Callable, z_index 5 (above ground,
## below units), camera-culled, pure _build_commands test hook,
## _process-driven redraw, zero cost when no plots exist.
##
## Wired in world.gd _ready() next to _trade_wagons. Tests drive the pure
## command builder plus a live node with a stub provider Callable.


## Isometric bed geometry (2:1 iso diamond on the ground plane).
const BED_HW := 56.0  ## diamond half-width (px)
const BED_HH := 28.0  ## diamond half-height (px)
const GRID_N := 4     ## 4x4 tiles (matches SimFarming.TILES_PER_SIDE)

## Soil + sprout colors (building_node _farm() palette).
const SOIL := Color(0.36, 0.25, 0.15)
const SOIL_BORDER := Color(0.25, 0.17, 0.10)
const SOIL_WATERED := Color(0.27, 0.21, 0.15)
const FURROW := Color(0.29, 0.20, 0.12)
const SPROUT_PALE := Color(0.55, 0.85, 0.45)
const SPROUT_DEEP := Color(0.22, 0.60, 0.24)
const POST_WOOD := Color(0.50, 0.36, 0.22)

const SPROUT_MIN_G := 0.05  ## tiles below this growth read as bare soil
const SWAY_SPEED := 2.2     ## crop sway, radians per second
const SWAY_AMP := 1.6       ## sway px at full growth


var _farming = null            ## SimFarming (untyped: avoids load cycle)
var _camera: Camera2D = null
var _provider: Callable = Callable()  ## () -> Array of plot dicts

## Last built draw commands (test hooks): Array of Dictionaries
## {kind: "plot", at: Vector2, faction: String, color: Color,
##  tiles: Array (raw tile dicts)}.
var _commands: Array = []
var _time := 0.0  ## shared sway clock (one timer, no per-plot state)


func _init() -> void:
	z_index = 5  # above roads/ground, below units (same as trade wagons)


func set_farming(f) -> void:
	_farming = f


func set_camera(cam: Camera2D) -> void:
	_camera = cam


func set_provider(call: Callable) -> void:
	_provider = call


func _plot_list() -> Array:
	if _provider.is_valid():
		return _provider.call()
	if _farming != null:
		return _farming.plots
	return []


func _process(delta: float) -> void:
	_time += delta
	var plots := _plot_list()
	visible = not plots.is_empty()
	if not visible:
		_commands.clear()
		return
	_commands = _build_commands(plots)
	queue_redraw()


## Pure: turns the plot list into draw commands (test hook).
func _build_commands(plots: Array) -> Array:
	var cmds: Array = []
	var view := _visible_rect()
	for p in plots:
		if not (p is Dictionary):
			continue
		var pos: Vector2 = p.get("position", Vector2.ZERO)
		if view != Rect2() and not view.grow(70.0).has_point(pos):
			continue  # camera-culled
		var faction := String(p.get("faction", ""))
		var fc: Dictionary = Config.FACTIONS.get(faction, {})
		cmds.append({
			"kind": "plot",
			"at": pos,
			"faction": faction,
			"color": fc.get("color", Color.WHITE),
			"tiles": p.get("tiles", []),
		})
	return cmds


func _visible_rect() -> Rect2:
	if _camera == null:
		return Rect2()
	var vp := get_viewport_rect().size
	var zoom := _camera.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return Rect2()
	var size := Vector2(vp.x / zoom.x, vp.y / zoom.y)
	return Rect2(_camera.get_screen_center_position() - size * 0.5, size)


## Isometric param map: (u, v) in [0,1]^2 -> bed-local coords.
static func bed_point(u: float, v: float) -> Vector2:
	return Vector2((u - v) * BED_HW, (u + v - 1.0) * BED_HH)


## Center of tile (i, j) in bed-local coords.
static func tile_center(i: int, j: int) -> Vector2:
	return bed_point((float(i) + 0.5) / float(GRID_N),
		(float(j) + 0.5) / float(GRID_N))


## Sprout blade height for growth g (0 below SPROUT_MIN_G: bare soil).
static func sprout_height(g: float) -> float:
	if g < SPROUT_MIN_G:
		return 0.0
	return 3.0 + g * 10.0


## Sprout color ramps pale -> deep green with growth.
static func sprout_color(g: float) -> Color:
	return SPROUT_PALE.lerp(SPROUT_DEEP, clampf(g, 0.0, 1.0))


func _draw() -> void:
	for c in _commands:
		if String(c.get("kind", "")) == "plot":
			_draw_plot(c)


func _draw_plot(c: Dictionary) -> void:
	var at: Vector2 = c["at"]
	# Ground bed: an isometric diamond sunk into the terrain — the field
	# reads as carved into the ground, never floating.
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -BED_HH), at + Vector2(BED_HW, 0.0),
		at + Vector2(0.0, BED_HH), at + Vector2(-BED_HW, 0.0),
	]), SOIL_BORDER)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -BED_HH + 4.0), at + Vector2(BED_HW - 8.0, 0.0),
		at + Vector2(0.0, BED_HH - 4.0), at + Vector2(-BED_HW + 8.0, 0.0),
	]), SOIL)
	# Furrow grid: 4x4 tile lines along the iso axes.
	for k in range(1, GRID_N):
		var f := float(k) / float(GRID_N)
		draw_line(at + bed_point(f, 0.0), at + bed_point(f, 1.0),
			FURROW, 1.0)
		draw_line(at + bed_point(0.0, f), at + bed_point(1.0, f),
			FURROW, 1.0)
	_draw_tiles(at, c.get("tiles", []))
	_draw_faction_post(at, c.get("color", Color.WHITE))


func _draw_tiles(at: Vector2, tiles: Array) -> void:
	var n := mini(tiles.size(), GRID_N * GRID_N)
	for idx in n:
		var t = tiles[idx]
		if not (t is Dictionary):
			continue
		var tc := at + tile_center(idx % GRID_N, idx / GRID_N)
		var g := float(t.get("g", 0.0))
		if bool(t.get("watered", false)):
			_draw_watered_tile(tc)
		var h := sprout_height(g)
		if h > 0.0:
			_draw_sprout(tc, g, h)


## Watered tiles read darker and damp.
func _draw_watered_tile(tc: Vector2) -> void:
	var hw := BED_HW / float(GRID_N) * 0.42
	var hh := BED_HH / float(GRID_N) * 0.42
	draw_colored_polygon(PackedVector2Array([
		tc + Vector2(0.0, -hh), tc + Vector2(hw, 0.0),
		tc + Vector2(0.0, hh), tc + Vector2(-hw, 0.0),
	]), SOIL_WATERED)


## Three blades per tile, swaying on the shared clock — smooth, cheap
## (one sin per tile, no allocations in the draw path).
func _draw_sprout(tc: Vector2, g: float, h: float) -> void:
	var col := sprout_color(g)
	var sway := sin(_time * SWAY_SPEED + (tc.x + tc.y) * 0.05) \
		* SWAY_AMP * g
	var base := tc + Vector2(0.0, -1.0)
	var blades := [[-2.5, 0.7], [0.0, 1.0], [2.5, 0.7]]
	for b in blades:
		var bx: float = b[0]
		var k: float = b[1]
		draw_line(base + Vector2(bx * 0.4, 0.0),
			base + Vector2(bx * 0.6 + sway, -h * k), col, 1.5)


## Faction marker post at the bed's south corner — ownership at a glance.
func _draw_faction_post(at: Vector2, color: Color) -> void:
	var foot := at + Vector2(0.0, BED_HH + 2.0)
	draw_line(foot, foot + Vector2(0.0, -10.0), POST_WOOD, 2.5)
	draw_colored_polygon(PackedVector2Array([
		foot + Vector2(0.0, -10.0),
		foot + Vector2(9.0, -7.5),
		foot + Vector2(0.0, -5.0),
	]), color)
