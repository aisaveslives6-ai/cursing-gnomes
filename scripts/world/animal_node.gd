class_name AnimalNode
extends Node2D
## Cursing Gnomes — animal visual: chibi pixel-art sprite.
##
## Procedural animation following the unit_animator.gd pattern (bounce
## pivoting at the feet, forward rock, squash alternation — never sliding):
##   IDLE  — slow breathing (scale pulse, tiny bob)
##   WALK  — bounce + rock + squash alternation
##   RUN   — faster, bigger bounce, forward lean (fleeing prey)
##   ATTACK — one-shot lunge toward facing direction (wolf bite)
##   HURT  — one-shot flinch + red flash when damaged
## Position is owned by the sim (SimAnimals); this node just follows and
## animates. Uses Art.animal_texture(type).


## Target on-screen sprite height in px.
const SPRITE_WORLD_H := 32.0
## 2026-10-06: procedural normal maps (CanvasTexture wraps) so the
## PointLight2D rig shades sprites directionally. Preloaded (not
## class_name-resolved) for headless single-script runs.
const SpriteNormalsScript := preload("res://scripts/world/sprite_normals.gd")
## Ground-shadow footprint: 0.75x visual height, the unit_node precedent.
const ANIMAL_SHADOW_FOOTPRINT := 24.0
## Jeremy 2026-10-06 (launch readiness, gate 3 — nothing floating): swimming
## animals get the pinned water shadow (unit_node precedent) instead of the
## sun-cast ground blob, which slides off the body on open water.
const SWIM_SHADOW_ALPHA := 0.55

## Testable shadow-dispatch contract: swimmers get the pinned water shadow,
## everyone else the sun-cast ground blob. Returns [kind, size, alpha_mul].
static func shadow_style(swimming: bool, footprint: float) -> Array:
	if swimming:
		return ["water", Shadows.water_shadow_size(footprint),
			SWIM_SHADOW_ALPHA]
	return ["ground", Vector2(footprint * 1.3, footprint * 0.85), 1.0]
## Attack lunge duration in seconds (matches sim's attack_t = 0.35).
const ATTACK_LEN := 0.35
## Hurt flinch duration in seconds (matches sim's hurt_t = 0.3).
const HURT_LEN := 0.3

var animal_id := -1
var animal_type := "boar"
var is_wild := false

var _sprite: Sprite2D
var _anim_t := 0.0
var _moving := false
var _running := false
var _swimming := false
var _attack_t := 0.0
var _hurt_t := 0.0
var _base_scale := Vector2.ONE
## Jeremy 2026-10-06 (five-books upgrade): body-mass factor — heavy
## animals cycle slower and squash deeper (Timing for Animation). Set
## from type in setup().
var _weight := 1.0
## Secondary-action wobble: extremities (ears/tail read) lag the body
## rock (Blair: jowls/ears flop to keep poses alive; Illusion of Life:
## follow-through). Applied as differential sprite rotation.
var _wobble := 0.0
var _swim_band: Polygon2D = null
## Swim band geometry (local px): sprite spans y in [-32, 0]; the
## waterline cuts the body a little below middle for half-submerged.
const SWIM_WATERLINE_Y := -12.0
const SWIM_BAND_HALF_W := 17.0
const SWIM_BAND_BOTTOM := 6.0


func setup(p_id: int, p_type: String, p_pos: Vector2, p_wild: bool = false) -> void:
	animal_id = p_id
	animal_type = p_type
	is_wild = p_wild
	position = p_pos
	# Five-books upgrade: weight-based timing per body type.
	match p_type:
		"chicken":
			_weight = 0.6
		"cat":
			_weight = 0.7  # Jeremy 2026-10-07 (pet cats): light and quick
		"sheep", "goat":
			_weight = 0.9
		"boar", "pig", "wolf":
			_weight = 1.1
		"cow":
			_weight = 1.6
		_:
			_weight = 1.0
	_sprite = Sprite2D.new()
	var tex: Texture2D = Art.animal_texture(p_type)
	if tex == null:
		tex = Art.animal_texture("boar")
	_sprite.texture = tex
	SpriteNormalsScript.apply_to(_sprite)
	if tex != null:
		var sc: float = SPRITE_WORLD_H / float(tex.get_height())
		# Bigger animals (cow) render a bit larger via draw_w.
		var st: Dictionary = SimAnimals.ANIMAL_TYPES.get(p_type, {})
		var dw: float = float(st.get("draw_w", 46.0))
		sc *= dw / 46.0
		_sprite.scale = Vector2(sc, sc)
		_base_scale = Vector2(sc, sc)
		_sprite.position = Vector2(0, -SPRITE_WORLD_H * 0.4)
	add_child(_sprite)
	_build_swim_band()


## Translucent water band drawn over the lower body while swimming —
## the half-submerged read. Child of the node after _sprite so it
## renders on top; the wavy top edge animates in _process.
func _build_swim_band() -> void:
	_swim_band = Polygon2D.new()
	_swim_band.color = Color(0.25, 0.55, 0.95, 0.45)
	_swim_band.visible = false
	add_child(_swim_band)
	_wave_band()


## Rebuild the band polygon with a sine-displaced top edge.
func _wave_band() -> void:
	if _swim_band == null:
		return
	var pts := PackedVector2Array()
	var segs := 8
	for i in range(segs + 1):
		var x := lerpf(-SWIM_BAND_HALF_W, SWIM_BAND_HALF_W,
			float(i) / float(segs))
		pts.append(Vector2(x, SWIM_WATERLINE_Y \
			+ sin(_anim_t * 2.0 + float(i) * 0.9) * 1.6))
	pts.append(Vector2(SWIM_BAND_HALF_W, SWIM_BAND_BOTTOM))
	pts.append(Vector2(-SWIM_BAND_HALF_W, SWIM_BAND_BOTTOM))
	_swim_band.polygon = pts


func _process(delta: float) -> void:
	if _sprite == null:
		return
	# One-shot timers tick down every frame.
	_attack_t = maxf(0.0, _attack_t - delta)
	_hurt_t = maxf(0.0, _hurt_t - delta)

	var lift := 0.0
	var rock := 0.0
	var squash := 0.0   # + = wide/short, - = narrow/tall
	var lunge := 0.0
	var breathe := 0.0

	if _attack_t > 0.0:
		# ATTACK: quick lunge forward — out fast, back over the full beat.
		# Anticipation: a tiny coil before the pop (Timing for Animation).
		var k: float = 1.0 - _attack_t / ATTACK_LEN
		var pop: float = sin(k * PI)
		var coil := 1.0 - smoothstep(0.0, 0.25, k)
		lunge = pop * 12.0 - coil * 3.0
		squash = -pop * 0.10 + coil * 0.05
		_anim_t += delta * 6.0 / _weight
	elif _hurt_t > 0.0:
		# HURT: flinch back + red flash, easing out.
		var k2: float = _hurt_t / HURT_LEN
		lunge = -5.0 * k2
		squash = 0.08 * k2
		_sprite.modulate = Color(1.0, lerpf(1.0, 0.45, k2),
			lerpf(1.0, 0.45, k2))
		_anim_t += delta * 6.0 / _weight
	else:
		_sprite.modulate = Color.WHITE
		if _swimming:
			# SWIM: paddling bob — fast, small, with a gentle side rock.
			_anim_t += delta * 9.0 / _weight
			var sw := sin(_anim_t)
			lift = -absf(sw) * 2.0
			rock = sw * 0.07
			if _swim_band != null:
				_swim_band.visible = true
				_wave_band()
			queue_redraw()  # ripple rings animate in _draw
		elif _moving:
			# One continuous South Park bounce — same timer always, no state
			# switching, so it can never fidget. Quadruped double-bounce:
			# diagonal legs suggest two beats per stride, the second
			# softer (Survival Kit); rock couples to the bounce phase for
			# the diagonal read. RUN (fleeing) leans forward and hits
			# harder.
			_anim_t += delta * 6.0 / _weight
			var sw2: float = sin(_anim_t)
			var up1 := maxf(sw2, 0.0)
			var up2 := maxf(-sw2, 0.0) * 0.6
			var amp := 4.2 if _running else 3.0
			lift = -(up1 + up2) * amp
			rock = sw2 * 0.05 + (0.09 if _running else 0.0)
			squash = (up1 + up2) * 0.05 * _weight
			if _swim_band != null:
				_swim_band.visible = false
		else:
			# IDLE: slow breathing + a lazy weight-shift (moving hold).
			_anim_t += delta * 2.5 / _weight
			breathe = sin(_anim_t) * 0.025
			lift = sin(_anim_t) * 1.0 - 1.0
			rock = sin(_anim_t * 0.4) * 0.02
			if _swim_band != null:
				_swim_band.visible = false

	# Secondary action: the extremities lag the body rock (Blair's
	# jowl/ear flop; Illusion of Life follow-through). The differential
	# rotation keeps the pose alive without touching the art.
	_wobble = lerpf(_wobble, rock, minf(1.0, delta * 8.0))
	_sprite.rotation = (_wobble - rock) * 1.5

	# Apply: lift offsets the sprite up; rock pivots the node at the feet.
	rotation = rock
	var fwd: float = -1.0 if _face_left else 1.0
	_sprite.position = Vector2(lunge * fwd,
		-SPRITE_WORLD_H * 0.4 + lift)
	# Always derive from the stored base scale — never compound.
	_sprite.scale = Vector2(
		_base_scale.x * (1.0 + squash),
		_base_scale.y * (1.0 - squash + breathe))
	# Face movement direction.
	if _moving:
		_sprite.flip_h = _face_left


var _face_left := false


## Sun-driven blob shadow at the ground point (animals were the only grounded
## entity without one — they read as floating/pasted on), plus ripple rings
## at the waterline while swimming (drawn under the sprite). Swimming animals
## get the pinned water shadow via shadow_style (unit_node precedent): the
## cast ground blob slides off the body on open water at dawn/dusk.
func _draw() -> void:
	var style := shadow_style(_swimming, ANIMAL_SHADOW_FOOTPRINT)
	if String(style[0]) == "water":
		Shadows.draw_water_shadow(self, style[1], float(style[2]))
	else:
		Shadows.draw_blob(self, ANIMAL_SHADOW_FOOTPRINT)
	if not _swimming:
		return
	for r in range(2):
		var k := fmod(_anim_t * 0.7 + float(r) * 0.5, 1.0)
		var rx := 10.0 + k * 22.0
		var pts := PackedVector2Array()
		for i in range(20):
			var a := TAU * float(i) / 20.0
			pts.append(Vector2(cos(a) * rx, sin(a) * rx * 0.35))
		pts.append(pts[0])
		draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.5 * (1.0 - k)), 1.5)


## Called by world sync: update position, track movement for animation,
## and consume one-shot triggers (attack_t / hurt_t) and the run flag.
func sync_to(pos: Vector2, an: Dictionary = {}) -> void:
	var d: Vector2 = pos - position
	_moving = d.length() > 0.5
	if absf(d.x) > 0.5:
		_face_left = d.x < 0.0
	position = pos
	if not an.is_empty():
		# One-shot triggers: the node takes them so they fire once even
		# though sync runs every frame.
		if float(an.get("attack_t", 0.0)) > 0.0 and _attack_t <= 0.0:
			_attack_t = float(an["attack_t"])
			an["attack_t"] = 0.0
		if float(an.get("hurt_t", 0.0)) > 0.0 and _hurt_t <= 0.0:
			_hurt_t = float(an["hurt_t"])
			an["hurt_t"] = 0.0
		_running = bool(an.get("running", false))
		var was_swim := _swimming
		_swimming = bool(an.get("swimming", false))
		if _swimming != was_swim:
			# Shadow mode swaps (water <-> ground) and stale ripple rings
			# clear: animals have no per-frame shadow-key check, so force
			# the redraw on the transition itself.
			queue_redraw()
