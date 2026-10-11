class_name SnowBlanket
extends Node2D
## Cursing Gnomes — seasonal snow blanket (Godot-native graphics upgrade).
##
## Jeremy's 2026-10-04 rule: the dynamic weather/seasons must be visible in
## the sim graphics. The HTML never whitened the ground in winter (its
## winter was snow particles + hidden grass only); the Godot port lays a
## soft snow blanket over the world while SimSeasons reports Winter, fading
## in over the first days of Frostmonth and out at winter's end.
##
## Pure visual layer: sim, AI, RNG untouched. Perf (Jeremy's 60fps bar):
## a single camera-culled world-space rect, drawn only while the blanket
## is up; _process does two guarded reads + an int compare per frame, and
## queue_redraw() fires only when the quantized amount actually changes
## (a handful of times per season transition). z_index -95: above the
## terrain bake (-100), below river foam (-90) and units/props.
##
## Wired in main.gd next to WeatherFX (both _start_world and _on_continue).


## Max alpha of the blanket at full winter (soft dusting — terrain detail
## reads through; rivers keep their animated flow visible under it).
const MAX_ALPHA := 0.32
## Days to fade in/out at the winter boundaries.
const FADE_DAYS := 5
## Redraw only when the amount crosses one of these steps.
const QUANT_STEPS := 32.0


var _game: GameState = null
var _amount := 0.0
var _last_key := -1
# Test/driver override (mirrors GrassTufts.set_wind). Empty = read the sim.
var _ovr_season := ""
var _ovr_month := 1
var _ovr_day := 1


func _ready() -> void:
	# Same layer as GrassTufts (hidden in winter, so no visual conflict).
	z_index = -95
	visible = false


func setup(game: GameState) -> void:
	_game = game
	set_process(true)


## Test/driver hook: force a season without a live GameState.
func set_season_override(season: String, month: int, day: int) -> void:
	_ovr_season = season
	_ovr_month = month
	_ovr_day = day


func clear_season_override() -> void:
	_ovr_season = ""


## Current blanket alpha (0 = no snow). Test-visible.
func current_amount() -> float:
	return _amount


## Pure amount math: 0 outside winter; ramps 0->1 over the first FADE_DAYS
## of Frostmonth (month 12), full through Snowmonth (month 1), ramps back
## down over the last FADE_DAYS of Thawmonth (month 2). Winter is months
## 12/1/2 per SimSeasons.season_of_month (HTML getSeason verbatim).
static func blanket_amount_for(season: String, month: int,
		day: int) -> float:
	if season != SimSeasons.WINTER:
		return 0.0
	var d := clampi(day, 1, SimSeasons.DAYS_PER_MONTH)
	if month == 12:
		return clampf(float(d) / float(FADE_DAYS), 0.0, 1.0)
	if month == 2:
		return clampf(float(SimSeasons.DAYS_PER_MONTH - d + 1)
			/ float(FADE_DAYS), 0.0, 1.0)
	return 1.0


func _process(_delta: float) -> void:
	var s := _read_season()
	var m := _read_month()
	var d := _read_day()
	var amt := blanket_amount_for(s, m, d)
	var key := int(amt * QUANT_STEPS)
	if key == _last_key:
		return
	_last_key = key
	_amount = amt
	visible = amt > 0.004
	queue_redraw()


func _read_season() -> String:
	if _ovr_season != "":
		return _ovr_season
	var seas: Variant = _seasons()
	if seas == null:
		return ""
	return String(seas.season())


func _read_month() -> int:
	if _ovr_season != "":
		return _ovr_month
	var seas: Variant = _seasons()
	if seas == null:
		return 1
	return int(seas.month())


func _read_day() -> int:
	if _ovr_season != "":
		return _ovr_day
	var seas: Variant = _seasons()
	if seas == null:
		return 1
	return int(seas.day_of_month())


func _seasons() -> Variant:
	if _game == null:
		return null
	return _game.get("seasons")


func _draw() -> void:
	if _amount <= 0.004:
		return
	var a := MAX_ALPHA * _amount
	draw_rect(_view_rect(), Color(0.90, 0.94, 1.0, a))


## Camera view in world space (same culling math as GrassTufts._draw).
## Falls back to a 1080p rect at the origin when no camera is current
## (headless tests).
func _view_rect() -> Rect2:
	var vp := get_viewport()
	var cam: Camera2D = null
	if vp != null:
		cam = vp.get_camera_2d()
	if cam == null:
		return Rect2(-960, -540, 1920, 1080)
	var vp_size := vp.get_visible_rect().size
	var center := cam.get_screen_center_position()
	var half := vp_size / cam.zoom * 0.5 + Vector2(48, 48)
	return Rect2(center - half, half * 2.0)
