class_name TradeWagonLayer
extends Node2D
## Cursing Gnomes — trade wagon renderer (draws SimTradeRoutes wagons).
##
## HTML source of truth: drawTradeWagons (fix79 index.html:43543) —
## covered wagons with a brown box body, arched canvas top, two dark
## wheels, and a faction-color flag, bobbing as they roll.
##
## Improvements over the HTML original:
##   - canvas ribs + faction-color trim on the canvas edge
##   - spoked wheels (they read as turning, not dots)
##   - dust puffs kicked up behind moving wagons (capped, 60fps rule)
##   - camera-culled: wagons outside the view are skipped
##   - zero per-frame cost when no wagons exist (visible = false)
##
## Wired in world.gd _ready() (routes provider + camera). Tests drive the
## pure command builder plus a live node with a stub provider Callable.


## HTML-verbatim colors.
const BODY_BROWN := Color(0.427, 0.298, 0.255)   # #6d4c41
const CANVAS_TAN := Color(0.553, 0.431, 0.388)   # #8d6e63
const DARK_OUTLINE := Color(0.102, 0.071, 0.039) # #1a120a
const WHEEL_DARK := Color(0.243, 0.153, 0.137)   # #3e2723
const DUST_TAN := Color(0.76, 0.68, 0.55, 0.35)

const MAX_PUFFS := 24        ## dust-puff cap (60fps rule)
const PUFF_LIFE := 0.9       ## seconds a puff lives
const PUFF_SPAWN := 0.28     ## seconds between puffs per wagon (moving)


var _routes = null            ## SimTradeRoutes (untyped: avoids load cycle)
var _camera: Camera2D = null
var _provider: Callable = Callable()  ## () -> Array of wagon dicts

## Last built draw commands (test hooks): Array of Dictionaries
## {kind: "wagon", at: Vector2, facing: float, bob: float, color: Color,
##  horse: bool, horse_phase: float, horse_coat: int}
## and {kind: "puff", at: Vector2, r: float, alpha: float}.
## Trade wagons are always hitched while alive (they only exist en route).
var _commands: Array = []

var _puffs: Array = []        ## {pos: Vector2, age: float}
var _puff_timer := 0.0
var _travel: Dictionary = {}  ## wagon id -> px travelled (horse gait)
var _last_pos: Dictionary = {}  ## wagon id -> Vector2 (movement detect)


func _init() -> void:
	z_index = 5  # above roads/ground, below units


func set_routes(routes) -> void:
	_routes = routes


func set_camera(cam: Camera2D) -> void:
	_camera = cam


func set_provider(call: Callable) -> void:
	_provider = call


func _wagon_list() -> Array:
	if _provider.is_valid():
		return _provider.call()
	if _routes != null and _routes.has_method("wagon_draw_list"):
		return _routes.wagon_draw_list()
	return []


func _process(delta: float) -> void:
	var wagons := _wagon_list()
	visible = not wagons.is_empty()
	if not visible:
		_puffs.clear()
		_commands.clear()
		_travel.clear()
		_last_pos.clear()
		return
	# Horse gait travel: accumulate real movement per wagon (the sim's bob
	# advances even when a wagon holds for war, so it can't drive the
	# gait — a holding horse must stand still, not walk in place).
	var seen := {}
	for w in wagons:
		var wid := String(w.get("id", ""))
		seen[wid] = true
		var pos: Vector2 = w["pos"]
		var last: Vector2 = _last_pos.get(wid, pos)
		_travel[wid] = float(_travel.get(wid, 0.0)) \
			+ pos.distance_to(last)
		_last_pos[wid] = pos
	for wid in _travel.keys():
		if not seen.has(wid):
			_travel.erase(wid)
			_last_pos.erase(wid)
	# Dust puffs behind moving wagons.
	_puff_timer += delta
	if _puff_timer >= PUFF_SPAWN:
		_puff_timer = 0.0
		for w in wagons:
			if _puffs.size() >= MAX_PUFFS:
				break
			_puffs.append({
				"pos": (w["pos"] as Vector2) \
						+ Vector2(-float(w.get("facing", 1.0)) * 14.0, 6.0),
				"age": 0.0,
			})
	var kept: Array = []
	for p in _puffs:
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) < PUFF_LIFE:
			kept.append(p)
	_puffs = kept
	_commands = _build_commands(wagons)
	queue_redraw()


## Pure: turns the wagon list into draw commands (test hook).
func _build_commands(wagons: Array) -> Array:
	var cmds: Array = []
	var view := _visible_rect()
	for w in wagons:
		var pos: Vector2 = w["pos"]
		if view != Rect2() and not view.grow(80.0).has_point(pos):
			continue  # camera-culled
		var fc: Dictionary = Config.FACTIONS.get(
			String(w.get("from_race", "")), {})
		var wid := String(w.get("id", ""))
		cmds.append({
			"kind": "wagon",
			"at": pos,
			"facing": float(w.get("facing", 1.0)),
			"bob": float(w.get("bob", 0.0)),
			"color": fc.get("color", Color.WHITE),
			"horse": true,
			"horse_phase": float(_travel.get(wid, 0.0)) \
				* VehicleArt.HORSE_GAIT,
			"horse_coat": abs(hash(wid)) % VehicleArt.HORSE_COATS.size(),
		})
	for p in _puffs:
		var age := float(p["age"])
		var k := 1.0 - age / PUFF_LIFE
		cmds.append({
			"kind": "puff",
			"at": p["pos"],
			"r": 4.0 + age * 9.0,
			"alpha": 0.35 * k,
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


func _draw() -> void:
	for c in _commands:
		if String(c["kind"]) == "puff":
			var col := DUST_TAN
			col.a = float(c["alpha"])
			draw_circle(c["at"], float(c["r"]), col)
		else:
			var fx := float(c["facing"])
			if bool(c.get("horse", false)):
				VehicleArt.draw_horse(self,
					(c["at"] as Vector2) \
						+ Vector2(VehicleArt.HORSE_AHEAD * fx, 0.0),
					fx, float(c["horse_phase"]),
					int(c["horse_coat"]))
			_draw_wagon(c["at"], fx, float(c["bob"]),
				c["color"])


## HTML-verbatim wagon geometry, improved with canvas ribs, faction trim,
## and spoked wheels. Local space: wagon base at origin, +x forward.
func _draw_wagon(at: Vector2, facing: float, bob: float,
		flag_color: Color) -> void:
	var oy := sin(bob) * 1.5  # HTML: translate(w.x, w.y + sin(bob)*1.5)
	var base := at + Vector2(0, oy)
	var fx := facing  # mirror on x for westbound wagons
	# Shadow (improvement: HTML drew none). Sun-cast onto the ground —
	# offset opposite the sun, soft falloff (Jeremy 2026-10-05).
	Shadows.draw_cast(self, Vector2(64.0, 15.0), 1.0,
		Vector2(base.x, base.y + 13.5))
	# Body: brown box, HTML fillRect(-14, -6, 26, 14) (widened 2px; symmetric).
	draw_rect(Rect2(base.x - 14.0, base.y - 6.0, 28.0, 14.0), BODY_BROWN)
	_draw_box_outline(base)
	# Canvas arch: HTML quadraticCurveTo(0,-20) peak, #8d6e63, 2px stroke.
	var top := PackedVector2Array()
	for k in range(13):
		var t := float(k) / 12.0
		var lx := lerpf(-12.0, 12.0, t) * fx
		var ly := -6.0 - 14.0 * sin(t * PI)
		top.append(base + Vector2(lx, ly))
	top.append(base + Vector2(12.0 * fx, -6.0))
	draw_colored_polygon(top, CANVAS_TAN)
	draw_polyline(top, DARK_OUTLINE, 2.0)
	# Canvas ribs (improvement): three hoop lines over the arch.
	for rib_t in [0.3, 0.5, 0.7]:
		var lx := lerpf(-12.0, 12.0, rib_t) * fx
		var ly := -6.0 - 14.0 * sin(rib_t * PI)
		draw_line(base + Vector2(lx, -6.0), base + Vector2(lx, ly),
			DARK_OUTLINE, 1.0)
	# Faction trim on the canvas hem (improvement: ownership at a glance).
	draw_line(base + Vector2(-12.0 * fx, -6.0),
		base + Vector2(12.0 * fx, -6.0), flag_color, 2.0)
	# Wheels: HTML arcs at (-8,8) and (8,8) r4, #3e2723 (symmetric).
	for wx in [-8.0, 8.0]:
		var wc := base + Vector2(wx, 8.0)
		draw_circle(wc, 4.5, WHEEL_DARK)
		draw_arc(wc, 4.5, 0.0, TAU, 12, DARK_OUTLINE, 1.0)
		# Spokes (improvement).
		for s in range(4):
			var a := s * PI / 4.0 + bob * 0.5
			draw_line(wc + Vector2(cos(a), sin(a)) * 1.5,
				wc + Vector2(cos(a), sin(a)) * 4.0, DARK_OUTLINE, 1.0)
	# Faction flag: HTML fillRect(10,-16,3,10) pole + fillRect(12,-16,8,5).
	var pole_x := base.x + 10.0 * fx
	draw_line(Vector2(pole_x, base.y - 6.0),
		Vector2(pole_x, base.y - 17.0), DARK_OUTLINE, 2.0)
	var fw := 8.0 * fx
	var flag := PackedVector2Array([
		Vector2(pole_x, base.y - 17.0),
		Vector2(pole_x + fw, base.y - 14.5),
		Vector2(pole_x, base.y - 12.0),
	])
	draw_colored_polygon(flag, flag_color)


## Body outline drawn explicitly (keeps the 2px stroke crisp on all sides).
func _draw_box_outline(base: Vector2) -> void:
	var x0 := base.x - 14.0
	var pts := PackedVector2Array([
		Vector2(x0, base.y - 6.0), Vector2(x0 + 28.0, base.y - 6.0),
		Vector2(x0 + 28.0, base.y + 8.0), Vector2(x0, base.y + 8.0),
		Vector2(x0, base.y - 6.0),
	])
	draw_polyline(pts, DARK_OUTLINE, 2.0)
