class_name DMVClerkFX
extends Node2D
## Cursing Gnomes  -  Dave the DMV Clerk ticket-window FX
## (2026-10-08 wake rapid-iteration).
##
## Dave shipped with bespoke chibi art (surly gnome, grey cardigan, folding
## table, red ticket dispenser, tall stack of forms) but his table had no
## voice: the queue formed invisibly. This Body-child FX gives the window a
## voice: a hanging marquee sign that flips between "NOW SERVING #N" and
## "CLOSED FOR LUNCH" (the sim pushes state via set_dmv_state), plus a
## gentle rain of paper ticket stubs fluttering off the table  -  the
## accumulating paperwork. Pure _draw (no textures, no emoji/glyphs  - 
## ASCII-only via ThemeDB.fallback_font, iPhone tofu rule). The sprite is
## never moved  -  freeze-position law: all motion lives in this FX node's
## own geometry.

## Monster world height in px (Dave's scale, set by the UnitNode at
## build time).
var stage_h := 64.0

## Falling paper stubs off the table.
const STUB_COUNT := 7
## One stub's fall cycle, seconds.
const STUB_CYCLE := 3.2
## Marquee sign flip duration when lunch toggles, seconds.
const FLIP_TIME := 0.45

var _t := 0.0
var _on_lunch := false
var _now_serving := 0
var _table_open := false
## 0..1 sign-flip progress; 1 = settled on the current face.
var _flip := 1.0
## The face the sign showed when the current flip started (so the old
## face holds for the first half of the turn-over).
var _was_lunch := false
## 0..1 flow of new stubs (0 on lunch / table closed  -  existing stubs
## drift out and stop).
var _flow := 1.0


func _process(delta: float) -> void:
	_t += delta
	# Ease the sign flip toward its new face.
	_flip = minf(_flip + delta / FLIP_TIME, 1.0)
	# Stub flow follows the serving state: lunch or a folded table
	# starves new paperwork.
	var want_flow := 1.0 if (_table_open and not _on_lunch) else 0.0
	_flow = move_toward(_flow, want_flow, delta * 1.6)
	queue_redraw()


## Sim-side state push from UnitNode.set_dmv_state (driven by world's
## per-frame sync off the unit record: dmv_on_lunch, dmv_now_serving,
## combat_state == "serving").
func set_dmv_state(on_lunch: bool, now_serving: int, table_open: bool) -> void:
	if on_lunch != _on_lunch:
		_was_lunch = _on_lunch
		_flip = 0.0
	_on_lunch = on_lunch
	_now_serving = now_serving
	_table_open = table_open
	visible = table_open


## 0..1 progress of stub i through its fall cycle (desynced).
func _stub_cycle(i: int) -> float:
	return fmod(_t / STUB_CYCLE + float(i) * 0.38197, 1.0)


## Where stub i sits: fluttering off the table top toward the ground,
## with a sideways sway so the fall never looks scripted.
func _stub_pos(i: int, h: float) -> Vector2:
	var cyc := _stub_cycle(i)
	var sway := sin(_t * 2.1 + float(i) * 2.7) * h * 0.11
	var x := h * 0.34 + sway
	var y := lerpf(-h * 0.30, h * 0.05, cyc)
	return Vector2(x, y)


## Stub spin through the fall: roughly two turns, alternating direction.
func _stub_rot(i: int) -> float:
	var dir := 1.0 if i % 2 == 0 else -1.0
	return _stub_cycle(i) * dir * TAU * 1.5


## Sign board geometry in Body-local space: {pos, w, h}.
func _sign_rect(h: float) -> Dictionary:
	var w := h * 1.02
	var sh := h * 0.34
	return {"pos": Vector2(-w * 0.5, -h * 1.42), "w": w, "h": sh}


## Which face the sign shows right now: the old face holds for the first
## half of the turn-over, the new face lands after mid-flip.
func _sign_face() -> String:
	if _flip < 0.5:
		return "lunch" if _was_lunch else "serving"
	return "lunch" if _on_lunch else "serving"


func _draw() -> void:
	if stage_h <= 0.0 or not _table_open:
		return
	var h: float = stage_h
	_draw_marquee(h)
	_draw_stubs(h)


## The hanging marquee: two posts + a board that flips between
## "NOW SERVING #N" and "CLOSED FOR LUNCH" on Dave's lunch break.
func _draw_marquee(h: float) -> void:
	var sr: Dictionary = _sign_rect(h)
	var pos: Vector2 = sr["pos"]
	var w: float = sr["w"]
	var sh: float = sr["h"]
	var sway := sin(_t * 1.3) * 0.03
	var cx := pos.x + w * 0.5
	var board := Rect2(pos, Vector2(w, sh))
	# Flip: board width shrinks through zero as the card turns over.
	var flip_w := board.size.x * absf(cos(PI * clampf(_flip, 0.0, 1.0)))
	var draw_board := Rect2(
		Vector2(cx - flip_w * 0.5, board.position.y + sway * h * 0.2),
		Vector2(maxf(flip_w, 1.0), board.size.y))
	# Posts (tan wood) from the ground up to the board top.
	var post_col := Color(0.55, 0.38, 0.22, 1.0)
	var post_w := h * 0.035
	draw_rect(Rect2(cx - w * 0.52, -h * 0.05, post_w, draw_board.position.y + h * 0.05),
		post_col)
	draw_rect(Rect2(cx + w * 0.52 - post_w, -h * 0.05, post_w, draw_board.position.y + h * 0.05),
		post_col)
	# Board: dark maroon card with a brass frame.
	draw_rect(draw_board.grow(h * 0.02), Color(0.72, 0.55, 0.25, 1.0))
	draw_rect(draw_board, Color(0.36, 0.10, 0.12, 1.0))
	# Face text, ASCII only (iPhone tofu rule). Skip mid-flip: the card
	# is edge-on, the new face lands after the turn.
	if absf(cos(PI * clampf(_flip, 0.0, 1.0))) < 0.45:
		return
	var font: Font = ThemeDB.fallback_font
	var face := _sign_face()
	if face == "lunch":
		var c1 := "CLOSED FOR"
		var c2 := "LUNCH"
		var f1 := int(h * 0.115)
		var f2 := int(h * 0.16)
		var tw1 := font.get_string_size(c1, HORIZONTAL_ALIGNMENT_LEFT, -1, f1).x
		var tw2 := font.get_string_size(c2, HORIZONTAL_ALIGNMENT_LEFT, -1, f2).x
		draw_string(font, Vector2(cx - tw1 * 0.5, draw_board.position.y + sh * 0.36),
			c1, HORIZONTAL_ALIGNMENT_LEFT, -1, f1, Color(1.0, 0.85, 0.70, 1.0))
		draw_string(font, Vector2(cx - tw2 * 0.5, draw_board.position.y + sh * 0.86),
			c2, HORIZONTAL_ALIGNMENT_LEFT, -1, f2, Color(1.0, 0.72, 0.55, 1.0))
	else:
		var head := "NOW SERVING"
		var num := "#%d" % maxi(_now_serving, 1)
		var f1 := int(h * 0.10)
		var f2 := int(h * 0.20)
		var twh := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, f1).x
		var twn := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, f2).x
		draw_string(font, Vector2(cx - twh * 0.5, draw_board.position.y + sh * 0.30),
			head, HORIZONTAL_ALIGNMENT_LEFT, -1, f1, Color(1.0, 0.92, 0.75, 1.0))
		draw_string(font, Vector2(cx - twn * 0.5, draw_board.position.y + sh * 0.88),
			num, HORIZONTAL_ALIGNMENT_LEFT, -1, f2, Color(1.0, 0.98, 0.80, 1.0))


## Paper ticket stubs fluttering off the table onto the ground.
func _draw_stubs(h: float) -> void:
	if _flow <= 0.01:
		return
	for i in STUB_COUNT:
		var cyc := _stub_cycle(i)
		var alpha := _flow * clampf(cyc * 6.0, 0.0, 1.0) * (1.0 - cyc)
		if alpha <= 0.01:
			continue
		var pos := _stub_pos(i, h)
		var rot := _stub_rot(i)
		var sw := h * 0.075
		var shh := h * 0.105
		draw_set_transform(pos, rot, Vector2.ONE)
		draw_rect(Rect2(-sw * 0.5, -shh * 0.5, sw, shh),
			Color(0.94, 0.92, 0.86, 0.95 * alpha))
		# Red perforation stripe near the stub's top edge.
		draw_rect(Rect2(-sw * 0.5, -shh * 0.5, sw, shh * 0.16),
			Color(0.78, 0.22, 0.20, 0.95 * alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
