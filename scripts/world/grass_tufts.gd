class_name GrassTufts
extends Node2D
## Cursing Gnomes — sparse grass tufts (HTML ground-detail parity).
##
## The HTML drew sparse grass blades only when the effective ground detail
## was high/ultra AND the camera was zoomed in (camZoom >= 0.85) AND the
## season wasn't Winter. This is that: a single _draw item, deterministic
## placement from a world grid (no per-frame allocation), culled to the
## camera view.
##
## Purely decorative — toggled by the Ground Detail setting via the world.


## Detail level this layer requires ("high" covers ultra too, like HTML).
var required_detail := "high"
## Minimum camera zoom (HTML camZoom >= 0.85).
var min_zoom := 0.85

var _map_bounds := Rect2()
var _step := 52.0  # HTML: 40px step on ultra, 52 on high
var _cam: Camera2D = null
var _winter := false

# Wind sway animation (graphics-hourly 2026-10-04): Jeremy asked for animated
# grass (2026-10-03 graphics upgrade). The HTML drew only static 2x4 rects,
# so this is a Godot-native upgrade on top of the HTML ground-detail parity:
# each tuft bends downwind with a sinusoidal wobble driven by the sim wind
# (SimSeasons wind_dir/wind_speed), read self-contained from the parent world
# so no world wiring changes were needed. Purely visual — sim untouched.
var _time := 0.0            # animation clock (seconds)
var _wind_dir := 0.0        # radians; SimSeasons.wind_dir
var _wind_speed := 0.4      # SimSeasons default wind_speed

const SWAY_FREQ := 2.2  # rad/s — gentle breeze wobble
const SWAY_AMP := 1.6   # px lateral wobble at full wind
const WIND_LEAN := 2.4  # px downwind lean at full wind
const BLADE_H := 5.0    # blade height (HTML 2x4 -> slightly taller 3-blade tuft)
const BLADE_W := 2.0    # HTML blade width


## Wind override (tests / external drivers). Speed clamps to [0, 2].
func set_wind(wind_dir: float, wind_speed: float) -> void:
	_wind_dir = wind_dir
	_wind_speed = clampf(wind_speed, 0.0, 2.0)


## Pure sway math: tip offset for a tuft rooted at `base`. Zero wind ->
## zero offset; lean follows wind_dir; wobble phase varies per tuft so the
## field ripples instead of marching in lockstep.
static func sway_offset(base: Vector2, time: float,
		wind_dir: float, wind_speed: float) -> Vector2:
	var w := clampf(wind_speed, 0.0, 2.0)
	if w <= 0.0:
		return Vector2.ZERO
	var downwind := Vector2(cos(wind_dir), sin(wind_dir))
	var lean := downwind * (WIND_LEAN * w)
	var phase := base.x * 0.35 + base.y * 0.51
	var perp := Vector2(-downwind.y, downwind.x)
	var wobble := sin(time * SWAY_FREQ + phase) * (SWAY_AMP * w)
	return lean + perp * wobble


func setup(map_bounds: Rect2, camera: Camera2D, detail: String) -> void:
	_map_bounds = map_bounds
	_cam = camera
	_step = 40.0 if detail == "ultra" else 52.0
	z_index = -95  # above terrain (-100), below foam (-90)


func refresh(camera: Camera2D, detail: String, winter: bool) -> void:
	_cam = camera
	_winter = winter
	var show := (detail == "high" or detail == "ultra") \
		and not winter \
		and camera != null and camera.zoom.x >= min_zoom
	if visible != show:
		visible = show
	if show:
		queue_redraw()


## Jeremy 2026-10-04: throttle redraws to 15 Hz (was every frame). The sway
## is a 1.6px wobble — 60fps redraws of ~4,000 draw_line calls were the
## #1 frame cost on iPhone. 15Hz is visually identical for this motion.
var _redraw_accum := 0.0
const REDRAW_INTERVAL := 1.0 / 15.0


func _process(delta: float) -> void:
	if not visible or _cam == null:
		return
	_time += delta
	_read_wind()
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()


## Self-contained wind feed: GrassTufts is a direct child of the world node,
## which owns `game` (GameState) with `seasons` (SimSeasons). No world.gd
## changes needed; everything is guarded for headless tests.
func _read_wind() -> void:
	var world: Node = get_parent()
	if world == null:
		return
	var g: Variant = world.get("game")
	if g == null:
		return
	var seas: Variant = g.get("seasons")
	if seas == null:
		return
	var d: Variant = seas.get("wind_dir")
	var s: Variant = seas.get("wind_speed")
	if d != null:
		_wind_dir = float(d)
	if s != null:
		_wind_speed = clampf(float(s), 0.0, 2.0)


func _draw() -> void:
	if _cam == null or not visible:
		return
	# Camera view in world space.
	var vp_size := get_viewport_rect().size
	var center := _cam.get_screen_center_position()
	var half := vp_size / _cam.zoom * 0.5 + Vector2(48, 48)
	var x0 := maxf(_map_bounds.position.x, center.x - half.x)
	var y0 := maxf(_map_bounds.position.y, center.y - half.y)
	var x1 := minf(_map_bounds.end.x, center.x + half.x)
	var y1 := minf(_map_bounds.end.y, center.y + half.y)
	var gx0 := int(floor(x0 / _step)) * _step
	var gy0 := int(floor(y0 / _step)) * _step
	# HTML green: #5aaa38. Each tuft is 3 blades (was one 2x4 rect) whose tips
	# bend with the wind — the animation Jeremy asked for in the 2026-10-03
	# graphics upgrade. Density unchanged: the same sparse mask decides
	# where tufts grow.
	var col := Color(0.353, 0.667, 0.220)
	var dark := col.darkened(0.25)
	var y := gy0
	while y <= y1:
		var x := gx0
		while x <= x1:
			# Deterministic sparse mask (HTML: ((x*13 + y*17) & 15) !== 0 skip).
			if (int(x * 13.0 + y * 17.0) & 15) == 0:
				_draw_tuft(Vector2(x, y), col, dark)
			x += _step
		y += _step


## Draws one swaying 3-blade tuft rooted at `base`.
func _draw_tuft(base: Vector2, col: Color, dark: Color) -> void:
	var off := sway_offset(base, _time, _wind_dir, _wind_speed)
	for i in range(3):
		var bx := base.x + float(i - 1) * 2.2
		var tip := Vector2(bx, base.y - BLADE_H) + off * (0.75 + 0.2 * float(i))
		var c: Color = dark if i == 1 else col
		draw_line(Vector2(bx, base.y), tip, c, BLADE_W)
