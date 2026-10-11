extends SceneTree
# Stub-validation of the staged _fishing_dock_fx body (byte-identical extract).
const EATERY_FX_STEPS := 8
const FISHING_FX_BTYPES := ["fishing_dock"]
## Foam flecks along the waterline (the baked foam edge runs y=8, x -26..42).
const FISHING_FX_FLECKS := [Vector2(-14.0, 8.5), Vector2(2.0, 9.0),
	Vector2(20.0, 8.5)]
## Hull water-laps just outside the moored boat (hull spans x 24..38,
## top edge y=10) - reads as the boat nudging the water without its art
## ever moving (freeze-position law).
const FISHING_FX_LAPS := [Vector2(23.0, 10.5), Vector2(39.0, 10.5)]
## Lantern on the pennant pole (pole x=-18, deck top y=-6, pennant ends
## y=-12) - hangs below the pennant, above the deck.
const FISHING_FX_LANTERN := Vector2(-18.0, -9.0)
const FISHING_FX_FOAM_TINT := Color(0.80, 0.88, 0.95)
const FISHING_FX_LANTERN_TINT := Color(1.0, 0.80, 0.50)
## Test hook: "dock" once _fishing_dock_fx has run; "" before the first
## draw or when the btype has no dock anchors.
var _last_fishing_dock_fx := ""
class GlowShim:
	static var _g := 0.0
	static func current() -> float:
		return _g

var draws: Array = []
var btype := "fishing_dock"
var _fx_step := 3
var _fx_phase := 2

static func monastery_flicker_for(step: int, phase: float) -> float:
	return 0.86 + 0.14 * sin(TAU * float(step) / float(EATERY_FX_STEPS) + phase)

func _fx_local_step() -> int:
	return posmod(maxi(_fx_step, 0) + _fx_phase, EATERY_FX_STEPS)

func draw_line(a: Vector2, b: Vector2, c: Color, w: float = 1.0) -> void:
	draws.append(["line", a, b, c, w])

func draw_circle(p: Vector2, r: float, c: Color) -> void:
	draws.append(["circle", p, r, c])

func draw_rect(r: Rect2, c: Color) -> void:
	draws.append(["rect", r, c])
func _fishing_dock_fx() -> void:
	if not (btype in FISHING_FX_BTYPES):
		return
	_last_fishing_dock_fx = "dock"
	var step := _fx_local_step()
	var night := GlowShim.current()
	var foam := FISHING_FX_FOAM_TINT
	# Foam flecks lapping the waterline: three staggered dashes along the
	# baked foam edge that brighten and wash out over one FX cycle.
	for i in range(FISHING_FX_FLECKS.size()):
		var life: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var f: Vector2 = FISHING_FX_FLECKS[i]
		var wob: float = sin(life * 5.0 + float(i) * 2.4) * 3.0
		var fa: float = 0.55 * (1.0 - life)
		draw_line(f + Vector2(-3.0 + wob, 0.0),
			f + Vector2(3.0 + wob, 0.0),
			Color(foam.r, foam.g, foam.b, fa), 1.6)
	# Hull water-laps: alternating glints just outside the moored boat's
	# ends - the boat rides the water while its art never moves.
	for i in range(FISHING_FX_LAPS.size()):
		var hflick := monastery_flicker_for(step, float(i) * 2.1)
		var h: Vector2 = FISHING_FX_LAPS[i]
		draw_line(h + Vector2(-2.5, 0.0), h + Vector2(2.5, 0.0),
			Color(foam.r, foam.g, foam.b, 0.30 + 0.35 * hflick), 1.4)
	# Dock lantern: iron cap where it meets the pennant pole, warm glass
	# dot, halo breathing around it - deeper after dark like the shop panes.
	var lamp := FISHING_FX_LANTERN
	var iron := Color(0.16, 0.14, 0.15)
	draw_rect(Rect2(lamp.x - 2.5, lamp.y - 5.5, 5.0, 2.5), iron)
	var lflick := monastery_flicker_for(step, 4.2)
	var lt := FISHING_FX_LANTERN_TINT
	draw_circle(lamp, 11.0 * lflick,
		Color(lt.r, lt.g, lt.b, (0.08 + 0.20 * night) * lflick))
	draw_circle(lamp, 3.0,
		Color(lt.r, lt.g, lt.b, (0.30 + 0.60 * night) * lflick))
var _passed := 0
var _failed := 0
func _check(n: String, c: bool) -> void:
	if c: _passed += 1
	else: _failed += 1; print("  FAIL: ", n)

func _initialize() -> void:
	draws.clear(); _last_fishing_dock_fx = ""
	_fishing_dock_fx()
	_check("hook arms to dock", _last_fishing_dock_fx == "dock")
	_check("draws something", draws.size() > 0)
	var lines := draws.filter(func(d): return d[0] == "line").size()
	var circles := draws.filter(func(d): return d[0] == "circle").size()
	var rects := draws.filter(func(d): return d[0] == "rect").size()
	_check("5 lines (3 flecks + 2 laps)", lines == 5)
	_check("2 lantern circles", circles == 2)
	_check("1 iron cap rect", rects == 1)
	btype = "pier"; draws.clear(); _last_fishing_dock_fx = ""
	_fishing_dock_fx()
	_check("non-roster draws nothing", draws.is_empty())
	_check("non-roster hook disarmed", _last_fishing_dock_fx == "")
	btype = "fishing_dock"
	draws.clear(); _fishing_dock_fx()
	var snap1 := str(draws)
	draws.clear(); _fishing_dock_fx()
	_check("deterministic", str(draws) == snap1)
	GlowShim._g = 0.0
	draws.clear(); _fishing_dock_fx()
	var day_halo: float = draws.filter(func(d): return d[0] == "circle")[0][3].a
	var day_glass: float = draws.filter(func(d): return d[0] == "circle")[1][3].a
	GlowShim._g = 1.0
	draws.clear(); _fishing_dock_fx()
	var ng_halo: float = draws.filter(func(d): return d[0] == "circle")[0][3].a
	var ng_glass: float = draws.filter(func(d): return d[0] == "circle")[1][3].a
	_check("night halo deeper", ng_halo > day_halo)
	_check("night glass brighter", ng_glass > day_glass)
	_check("day glass visible", day_glass > 0.0)
	var bad := false
	for d in draws:
		var a: float = d[3].a
		if a != a or a < 0.0 or a > 1.0:
			bad = true
	_check("all alphas sane", not bad)
	print("=== stub: " + str(_passed) + " passed " + str(_failed) + " failed ===")
	quit(1 if _failed > 0 else 0)
