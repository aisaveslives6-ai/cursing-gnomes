class_name WarrantyFX
extends Node2D
## Cursing Gnomes — Wally the Warranty Salesman doorstep-pitch FX
## (2026-10-08 wake rapid-iteration).
##
## Wally shipped with bespoke chibi art — cheap suit, red tie, a briefcase
## full of "extended warranties" — but the pitch itself was invisible: he
## walked to a building, and the faction's gold just quietly vanished.
## This Body-child FX makes the sale visible: a swirl of warranty
## certificates orbiting him (faster and wider while he is pitching at a
## doorstep), a red "EXPIRED" rubber stamp slamming down on every pitch
## cadence (the world sync drives the pitching flag off the unit record's
## combat_state), and a gold-coin burst flung off the briefcase on every
## completed sale (edge-triggered on the warranty_sales counter). Pure
## _draw (no textures, no emoji/glyphs — ASCII-only via
## ThemeDB.fallback_font, iPhone tofu rule). The sprite is never moved —
## freeze-position law: all motion lives in this FX node's own geometry.

## Monster world height in px (Wally's scale, set by the UnitNode at
## build time).
var stage_h := 64.0

## Swirling warranty certificates.
const DOC_COUNT := 8
## One doc's orbit cycle, seconds (idle drift; pitching spins faster).
const DOC_CYCLE := 4.5
## "EXPIRED" stamp slam period while pitching, seconds.
const STAMP_PERIOD := 2.5
## Stamp slam-in + fade duration, seconds.
const STAMP_SLAM := 0.7
## Coins flung off the briefcase per completed sale.
const COINS_PER_SALE := 6
## Coin flight lifetime, seconds.
const COIN_LIFE := 1.1

var _t := 0.0
var _pitching := false
var _sales := 0
var _coin_pos: Array[Vector2] = []
var _coin_vel: Array[Vector2] = []
var _coin_age: Array[float] = []


func _process(delta: float) -> void:
	_t += delta
	# Coin flight: simple ballistic arc off the briefcase, then gone.
	var g := 320.0 * (stage_h / 64.0)
	for i in range(_coin_age.size() - 1, -1, -1):
		_coin_age[i] += delta
		if _coin_age[i] >= COIN_LIFE:
			_coin_age.remove_at(i)
			_coin_pos.remove_at(i)
			_coin_vel.remove_at(i)
			continue
		_coin_vel[i] += Vector2(0.0, g) * delta
		_coin_pos[i] += _coin_vel[i] * delta
	queue_redraw()


## Sim-side state push from UnitNode.set_warranty_state (driven by world's
## per-frame sync off the unit record: combat_state == "pitching", and the
## warranty_sales counter for the sale burst).
func set_warranty_state(pitching: bool, sales: int) -> void:
	_pitching = pitching
	if sales > _sales:
		_burst_coins()
	_sales = sales


## Fling gold coins off the briefcase anchor — a sale just closed.
## Deterministic fan (no randf): testable and stable across frames.
func _burst_coins() -> void:
	var h: float = stage_h
	var anchor := Vector2(h * 0.30, -h * 0.28)
	var n := COINS_PER_SALE
	for i in n:
		var frac := float(i) / float(maxi(n - 1, 1)) - 0.5  # -0.5..0.5
		var ang := -PI * 0.5 + frac * 1.6
		var spd := (130.0 + 70.0 * float(i % 2)) * (h / 64.0)
		_coin_pos.append(anchor)
		_coin_vel.append(Vector2(cos(ang), sin(ang)) * spd)
		_coin_age.append(0.0)


## 0..1 progress of doc i through its orbit (golden-ratio desync, like
## the MLM sparkle motes — the orbit never looks scripted).
func _doc_cycle(i: int) -> float:
	var speed_mult := 2.2 if _pitching else 1.0
	return fmod(_t / DOC_CYCLE * speed_mult + float(i) * 0.61803, 1.0)


## Where doc i sits: an elliptical orbit around the body with a gentle
## vertical bob. Pitching widens the orbit — the hard sell.
func _doc_pos(i: int, h: float) -> Vector2:
	var a := TAU * _doc_cycle(i)
	var r := h * (0.72 if _pitching else 0.55)
	var bob := sin(_t * 2.2 + float(i) * 1.7) * h * 0.06
	return Vector2(cos(a) * r, -h * 0.45 + sin(a) * r * 0.55 + bob)


## One warranty certificate: parchment doc with contract lines and a tiny
## red stamp square, drawn tilted. Pure geometry, no text.
func _draw_doc(center: Vector2, w: float, hgt: float, tilt: float) -> void:
	var c := Vector2(cos(tilt), sin(tilt))
	var s := Vector2(-sin(tilt), cos(tilt))
	var hw := w * 0.5
	var hh := hgt * 0.5
	var pts := PackedVector2Array([
		center - c * hw - s * hh, center + c * hw - s * hh,
		center + c * hw + s * hh, center - c * hw + s * hh])
	draw_colored_polygon(pts, Color(0.96, 0.90, 0.76, 0.92))
	var outline := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
	draw_polyline(outline, Color(0.55, 0.45, 0.30, 0.9), 1.5, true)
	# Contract fine print (three lines of nothing).
	for li in 3:
		var ly := -hh * 0.5 + float(li) * hh * 0.5
		draw_line(center - c * hw * 0.7 + s * ly,
			center + c * hw * 0.7 + s * ly,
			Color(0.45, 0.42, 0.38, 0.85), 1.2, true)
	# Tiny red stamp square in the corner — already denied, probably.
	var sc := center + c * hw * 0.42 + s * hh * 0.42
	var sw := w * 0.16
	var spts := PackedVector2Array([
		sc - c * sw - s * sw, sc + c * sw - s * sw,
		sc + c * sw + s * sw, sc - c * sw + s * sw,
		sc - c * sw - s * sw])
	draw_polyline(spts, Color(0.85, 0.12, 0.10, 0.9), 1.5, true)


## 0..1 phase of the stamp slam period.
func _stamp_phase() -> float:
	return fmod(_t / STAMP_PERIOD, 1.0)


## The "EXPIRED" rubber stamp: slams down right after each period
## boundary while pitching (scale 1.7 -> 1.0, ink fading), then silent.
func _draw_stamp(h: float) -> void:
	if not _pitching:
		return
	var st := _stamp_phase() * STAMP_PERIOD
	if st >= STAMP_SLAM:
		return
	var p := st / STAMP_SLAM  # 0..1 through the slam
	var scl := lerpf(1.7, 1.0, 1.0 - pow(1.0 - p, 2.0))
	var alpha := 1.0 - p * 0.75
	var ink := Color(0.85, 0.12, 0.10, alpha)
	var center := Vector2(-h * 0.10, -h * 1.02)
	# The rubber-stamp tilt.
	draw_set_transform(center, -0.16, Vector2(scl, scl))
	var rw := h * 0.52
	var rh := h * 0.20
	draw_rect(Rect2(-rw * 0.5, -rh * 0.5, rw, rh), ink, false, 3.0)
	draw_rect(Rect2(-rw * 0.5 + 4.0, -rh * 0.5 + 4.0, rw - 8.0, rh - 8.0),
		Color(0.85, 0.12, 0.10, alpha * 0.45), false, 1.5)
	# Face text, ASCII only (iPhone tofu rule).
	var font: Font = ThemeDB.fallback_font
	var word := "EXPIRED"
	var fsize := int(h * 0.15)
	var tw := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(font, Vector2(-tw * 0.5, float(fsize) * 0.35), word,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	if stage_h <= 0.0:
		return
	var h: float = stage_h
	# Swirling warranty certificates — the paperwork storm.
	for i in DOC_COUNT:
		var a := TAU * _doc_cycle(i)
		_draw_doc(_doc_pos(i, h), h * 0.16, h * 0.22, a + 0.6)
	# The EXPIRED stamp, slammed on every pitch cadence.
	_draw_stamp(h)
	# Sale coins: gold arcs off the briefcase, fading as they fall.
	for i in _coin_pos.size():
		var age: float = _coin_age[i]
		var alpha := clampf(1.0 - age / COIN_LIFE, 0.0, 1.0)
		if alpha <= 0.01:
			continue
		var cr := h * 0.038
		draw_circle(_coin_pos[i], cr, Color(1.0, 0.80, 0.25, alpha))
		draw_circle(_coin_pos[i] + Vector2(-cr * 0.3, -cr * 0.3), cr * 0.45,
			Color(1.0, 0.93, 0.55, alpha))
