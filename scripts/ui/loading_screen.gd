class_name LoadingScreen
extends CanvasLayer
## Cursing Gnomes — first-boot cinematic loading screen (Jeremy 2026-10-10,
## complete remake 2026-10-10: "buggy as hell, completely redo it").
##
## The old implementation (TextureRect marching sprites, LoadBar/MarchLane
## helper classes, tween-driven fade) is GONE. This is a from-zero rebuild:
##
## CINEMATIC (GTA-opening feel):
##   Phase 0 — fade from black over a living landscape.
##   Phase 1 — slow camera sweep across the scene (parallax layers).
##   Phase 2 — the CURSING GNOMES title makes its entrance, letter by
##             letter with weight, then the motto.
##   Phase 3 — settles into the loading UI (real progress bar + stage +
##             rotating tips) while the world keeps breathing behind it.
##   Phase 4 — finish(): bar to 100%, brief hold, fade out over the live
##             world, free. Hands off to the menu the instant loading ends.
##
## HD AF (Jeremy's order): EVERYTHING is drawn procedurally in _draw() —
## resolution-independent vector-crisp shapes. No textures, no sprites, no
## upscaling, no filtering blur. It rasterizes razor-sharp at full iPhone 17
## resolution because there is nothing TO upscale. This is the
## sharpest-looking screen in the game by construction.
##
## FULLY ANIMATED living scene: chibi gnomes marching (walk cycles), a
## builder gnome hammering a house frame, a hero gnome waving at you,
## drifting clouds, birds, Wind Waker-style animated water (scrolling curls,
## whitecaps, lapping shoreline foam), chimney smoke, swaying grass,
## fireflies. The progress bar and tips ride on top of a breathing world.
##
## BULLETPROOF progress: set_progress() is the primary path (main.gd's
## staged boot). bind_world() adds a POLL BACKUP — every frame the screen
## reads world.boot_frac / world.boot_label directly, so a missed or
## reordered signal can never strand the bar. The bar fill lerps toward its
## target (never snaps, never jumps to 100 then hangs), is monotonic
## (never runs backwards), and the stage label gets an animated ellipsis so
## a long stage reads as working, not stuck. finish() is idempotent and the
## fade is driven manually in _process (no tween that a frozen tree could
## kill mid-flight).
##
## API: set_progress(frac 0..1, label), bind_world(world), finish().
## First-boot intro: play_first_boot_intro() + intro_finished signal
## (main.gd shows the menu when it fires). set_audio(am) wires sound.


const _TIP_INTERVAL := 4.5
const _TITLE := "CURSING GNOMES"
const _MOTTO := "No microtransactions. No bullshit."
## Studio card name. Jeremy 2026-10-11: the dev team is ETHOS GAMES.
const STUDIO_NAME := "ETHOS GAMES"

signal intro_finished

## AAA first-boot intro timeline (Jeremy 2026-10-11 spec): skippable
## cinematic beats BEFORE the main menu. Any tap advances to the next
## beat; a tap in the final beat finishes immediately.
##  Beat 0 STUDIO: "Ethos Games presents" fades in, holds, fades out.
##  Beat 1 LOGO:   Cursing Gnomes logo fades in (title-screen style),
##                 holds, fades out — with a gnome chuckle on arrival.
##  Beat 2 WORLD:  ambient landscape fades in (the living scene keeps
##                 breathing), intro ambience swells (wind/leaves/birds).
##  Beat 3 MUSIC:  the theme fades in over the ambience, then handoff.
const _INTRO_BEATS := [
	{"kind": "studio", "t0": 0.0, "t1": 3.8},
	{"kind": "logo", "t0": 3.8, "t1": 7.8},
	{"kind": "world", "t0": 7.8, "t1": 12.5},
	{"kind": "music", "t0": 12.5, "t1": 16.0},
]
const _INTRO_FADE := 0.9  # per-beat fade in/out seconds
const _CHUCKLE_AT := 4.2  # gnome chuckle fires once, shortly after logo

## Cinematic timeline (seconds since _ready).
## 0.0–2.0: studio card (skippable). 2.0+: landscape reveal + sweep.
const _T_STUDIO := 2.0     # studio card hands off to the landscape
const _T_FADE := 0.9       # fade from black as the landscape reveals
const _T_TITLE := 3.4      # first title letter starts
const _T_LETTER := 0.055   # stagger between letters
const _T_MOTTO := 5.2      # motto fades in
const _T_UI := 2.6         # progress UI fades in (load is real + immediate)
const _T_SWEEP := 7.0      # camera sweep duration (starts at _T_STUDIO)

var _scene: BootScene
var _stage_lbl: Label
var _pct_lbl: Label
var _tip_lbl: Label

var _t := 0.0            # seconds since ready (drives the cinematic)
var _frac := 0.0         # monotonic real progress 0..1
var _bar_shown := 0.0    # lerped fill actually painted
var _stage := "Loading…"
var _tip_time := 0.0
var _last_tip := ""
var _finishing := false
var _finish_t := 0.0     # time since finish() called
var _fade := 1.0         # 1 = black, 0 = visible (drives intro fade)
var _world: Node = null  # poll backup (bind_world)
var _ui_scale := 1.0
var _vp := Vector2.ZERO
var _skipped_intro := false
# First-boot intro state (main.gd app launch; separate from world boots).
var _intro_mode := false
var _intro_beat := 0
var _intro_done := false
var _chuckle_fired := false
var _audio: Node = null  # AudioManager, via set_audio()


func _unhandled_input(event: InputEvent) -> void:
	var tap := false
	if event is InputEventScreenTouch and event.pressed:
		tap = true
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tap = true
	if not tap:
		return
	if _intro_mode:
		# Skippable AAA intro: any tap advances a beat (final beat: done).
		_advance_intro_beat()
		return
	# Skippable studio card (world boots): any tap jumps to the reveal.
	if _t >= _T_STUDIO or _skipped_intro:
		return
	_skipped_intro = true


## Wire the AudioManager (main.gd does this at app launch).
func set_audio(am: Node) -> void:
	_audio = am


## Start the AAA first-boot intro (app launch, before the main menu).
## The game loads underneath; intro_finished fires when it's over.
func play_first_boot_intro() -> void:
	_intro_mode = true
	_intro_beat = 0
	_t = 0.0
	_fade = 1.0


## Public skip (tests + external callers). Returns the beat we landed on.
func skip_ahead() -> int:
	_advance_intro_beat()
	return _intro_beat


func _advance_intro_beat() -> void:
	if _intro_done:
		return
	if _intro_beat >= _INTRO_BEATS.size() - 1:
		_finish_intro()
		return
	_intro_beat += 1
	_t = float(_INTRO_BEATS[_intro_beat]["t0"]) + 0.001
	_on_enter_beat(_intro_beat)


func _on_enter_beat(beat: int) -> void:
	var kind := str(_INTRO_BEATS[beat]["kind"])
	if kind == "logo" and not _chuckle_fired:
		_chuckle_fired = true
		if _audio != null and _audio.has_method("play_sfx"):
			_audio.play_sfx("gnome_chuckle")
	elif kind == "world":
		if _audio != null and _audio.has_method("start_intro_ambience"):
			_audio.start_intro_ambience()
	elif kind == "music":
		if _audio != null and _audio.has_method("play_intro_music"):
			_audio.play_intro_music()


func _finish_intro() -> void:
	if _intro_done:
		return
	_intro_done = true
	if _audio != null and _audio.has_method("stop_intro_ambience"):
		_audio.stop_intro_ambience()
	intro_finished.emit()
	queue_free()


func _init() -> void:
	layer = 250
	# The world freezes the tree during its staged boot; the cinematic must
	# keep playing through the freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_scene = BootScene.new()
	_scene.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.screen = self
	add_child(_scene)

	_stage_lbl = _mk_label(24, Color(0.98, 0.90, 0.66))
	_pct_lbl = _mk_label(22, Color(1.0, 0.835, 0.310))
	_tip_lbl = _mk_label(19, Color(0.86, 0.79, 0.60))
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_stage_lbl)
	add_child(_pct_lbl)
	add_child(_tip_lbl)
	_rotate_tip()
	_layout()
	set_process(true)


func _mk_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0 # faded in by the cinematic
	return l


## iPhone safe-area insets in viewport pixels (headless-safe: zero insets).
func _safe_insets(vsz: Vector2) -> Vector4:
	var safe := DisplayServer.get_display_safe_area()
	var winsz := Vector2(DisplayServer.window_get_size())
	if winsz.x > 0.0 and winsz.y > 0.0 and safe.size.x > 0.0:
		var k := vsz / winsz
		return Vector4(
			maxf(safe.position.y * k.y, 0.0),
			maxf((winsz.y - safe.position.y - safe.size.y) * k.y, 0.0),
			maxf(safe.position.x * k.x, 0.0),
			maxf((winsz.x - safe.position.x - safe.size.x) * k.x, 0.0))
	return Vector4.ZERO


func _layout() -> void:
	var vsz: Vector2 = get_viewport().get_visible_rect().size
	if vsz.x <= 0.0 or vsz.y <= 0.0:
		return
	_vp = vsz
	_ui_scale = clampf(minf(vsz.x, vsz.y) / 760.0, 0.75, 1.7)
	_layout_labels(vsz)


func _layout_labels(vsz: Vector2) -> void:
	var s := _ui_scale
	var insets := _safe_insets(vsz)
	var cx := vsz.x * 0.5
	# Progress UI cluster sits low-center, above the home indicator.
	var bar_w := minf(vsz.x * 0.78, 620.0 * s)
	var bar_y := vsz.y - insets.y - 210.0 * s
	_stage_lbl.add_theme_font_size_override("font_size", int(24 * s))
	_stage_lbl.position = Vector2(cx - 400 * s, bar_y - 56 * s)
	_stage_lbl.size = Vector2(800 * s, 48 * s)
	_pct_lbl.add_theme_font_size_override("font_size", int(22 * s))
	_pct_lbl.position = Vector2(cx - 100 * s, bar_y + 34 * s)
	_pct_lbl.size = Vector2(200 * s, 36 * s)
	_tip_lbl.add_theme_font_size_override("font_size", int(19 * s))
	var tip_w := minf(vsz.x * 0.88, 720.0 * s)
	_tip_lbl.position = Vector2(cx - tip_w * 0.5, vsz.y - insets.y - 118 * s)
	_tip_lbl.size = Vector2(tip_w, 96 * s)
	_scene.bar_rect = Rect2(cx - bar_w * 0.5, bar_y, bar_w, 26.0 * s)


## REAL progress. Primary path: main.gd calls this from the staged boot
## (threaded asset load + world boot stages). Monotonic — a late or
## out-of-order call can never run the bar backwards.
func set_progress(frac: float, label: String) -> void:
	var f := clampf(frac, 0.0, 1.0)
	if f < _frac:
		f = _frac # never backwards; the poll backup only moves forward
	_frac = f
	_stage = label
	if is_instance_valid(_stage_lbl):
		_stage_lbl.text = label
	if is_instance_valid(_pct_lbl):
		_pct_lbl.text = "%d%%" % int(_frac * 100.0)


## Poll backup: the screen reads the world's own boot counters every frame,
## so a missed/reordered boot_progress signal can never strand the bar.
## Null-safe: unbinds itself if the world is freed.
func bind_world(world: Node) -> void:
	_world = world


func _poll_world() -> void:
	if _world == null:
		return
	if not is_instance_valid(_world):
		_world = null
		return
	var bf: Variant = _world.get("boot_frac")
	if bf is float or bf is int:
		set_progress(float(bf), str(_world.get("boot_label")))
	if bool(_world.get("booted")) and _frac < 0.88:
		set_progress(0.88, "Ready")


func _rotate_tip() -> void:
	var tip := MainMenu.random_tip()
	var guard := 0
	while tip == _last_tip and guard < 4 and MainMenu.MENU_TIPS.size() > 1:
		tip = MainMenu.random_tip()
		guard += 1
	_last_tip = tip
	if is_instance_valid(_tip_lbl):
		_tip_lbl.text = tip


func _process(delta: float) -> void:
	# Viewport can change under us (rotation, multitasking): relayout.
	var vsz: Vector2 = get_viewport().get_visible_rect().size
	if vsz != _vp:
		_layout()
	if _intro_mode:
		_process_intro(delta, vsz)
		return
	_t += delta
	_poll_world()
	if _skipped_intro and _t < _T_STUDIO:
		_t = _T_STUDIO

	# Intro fade from black (starts as the landscape reveals).
	if _t >= _T_STUDIO and _fade > 0.0:
		_fade = maxf(0.0, _fade - delta / _T_FADE)

	# Cinematic UI fade-ins (driven by the timeline, not by tweens).
	var ui_a := clampf((_t - _T_UI) / 0.6, 0.0, 1.0)
	var motto_a := clampf((_t - _T_MOTTO) / 0.8, 0.0, 1.0)
	for l: Label in [_stage_lbl, _pct_lbl, _tip_lbl]:
		if is_instance_valid(l):
			l.modulate.a = ui_a * _fade_out()
	if is_instance_valid(_scene):
		_scene.motto_alpha = motto_a * _fade_out()
		_scene.tick(delta, _vp)
		_scene.fade = _fade
		_scene.queue_redraw()

	# The painted fill chases real progress — smooth, never snaps, never
	# jumps to 100 then hangs.
	var target := _frac
	var speed := 2.5
	if target > _bar_shown:
		_bar_shown = minf(target, _bar_shown + speed * delta)
	else:
		_bar_shown = target

	# Animated ellipsis on the stage label: a long stage reads as working.
	if is_instance_valid(_stage_lbl) and not _finishing:
		var dots := int(_t * 2.0) % 4
		_stage_lbl.text = _stage + ".".repeat(dots)

	_tip_time += delta
	if _tip_time >= _TIP_INTERVAL:
		_tip_time = 0.0
		_rotate_tip()

	if _finishing:
		_finish_t += delta
		# Let the full bar paint for a beat, then fade manually (no tween —
		# a frozen tree would kill it mid-flight).
		if _finish_t > 0.30:
			var a := 1.0 - (_finish_t - 0.30) / 0.35
			_set_all_alpha(maxf(a, 0.0))
			if a <= 0.0:
				queue_free()


## First-boot intro driver: advances the cinematic clock, fires
## beat-entry hooks (chuckle / ambience / music), and ends the show.
func _process_intro(delta: float, vsz: Vector2) -> void:
	if _intro_done:
		return
	_t += delta
	# Natural beat rollover (taps can also jump via _advance_intro_beat).
	var beat: Dictionary = _INTRO_BEATS[_intro_beat]
	if _t >= float(beat["t1"]):
		if _intro_beat >= _INTRO_BEATS.size() - 1:
			_finish_intro()
			return
		_intro_beat += 1
		_on_enter_beat(_intro_beat)
	# The chuckle lands shortly after the logo arrives (even unskipped).
	if not _chuckle_fired and _t >= _CHUCKLE_AT and _intro_beat >= 1:
		_chuckle_fired = true
		if _audio != null and _audio.has_method("play_sfx"):
			_audio.play_sfx("gnome_chuckle")
	if is_instance_valid(_scene):
		_scene.tick(delta, _vp)
		_scene.queue_redraw()


## Per-beat alpha envelope: fade in, hold, fade out.
func _intro_beat_alpha(beat_idx: int) -> float:
	var beat: Dictionary = _INTRO_BEATS[beat_idx]
	var t0 := float(beat["t0"])
	var t1 := float(beat["t1"])
	var a_in := clampf((_t - t0) / _INTRO_FADE, 0.0, 1.0)
	var a_out := clampf((t1 - _t) / _INTRO_FADE, 0.0, 1.0)
	return minf(a_in, a_out)


func _fade_out() -> float:
	if not _finishing:
		return 1.0
	return clampf(1.0 - (_finish_t - 0.30) / 0.35, 0.0, 1.0)


func _set_all_alpha(a: float) -> void:
	if is_instance_valid(_scene):
		_scene.global_alpha = a
	for l: Label in [_stage_lbl, _pct_lbl, _tip_lbl]:
		if is_instance_valid(l):
			l.modulate.a = a


## Idempotent. The bar goes to a real 100% first (never a fake jump — by
## the time finish() is called the world IS booted), paints for a beat,
## then the manual fade runs in _process.
func finish() -> void:
	if _finishing:
		return
	_finishing = true
	_finish_t = 0.0
	set_progress(1.0, "Ready")


func _exit_tree() -> void:
	_world = null

## BootScene: the entire cinematic is ONE Control that draws EVERYTHING
## procedurally in _draw(). No textures, no sprites, no imports — every
## shape is resolution-independent vector geometry, so it rasterizes
## razor-sharp at full iPhone 17 resolution (no upscaling, no blur).
## A single full-screen redraw per frame at ~300 draw calls holds 60fps.
class BootScene extends Control:
	var screen: LoadingScreen = null
	var t := 0.0
	var fade := 1.0          # intro fade-from-black 1->0
	var motto_alpha := 0.0
	var global_alpha := 1.0
	var bar_rect := Rect2()

	var _sky_tex: GradientTexture2D
	var _vig_tex: GradientTexture2D
	var _bar_bg := StyleBoxFlat.new()
	var _bar_fill := StyleBoxFlat.new()
	var _march: Array[float] = [0.15, 0.55, 0.9] # 0..1.2 across
	var _smoke: Array[Dictionary] = []
	var _dust: Array[Dictionary] = []
	var _flies: Array[Dictionary] = []
	var _hammer_prev := 0.0
	var _font: Font

	const _PALETTES: Array = [
		{"hat": Color(0.75, 0.18, 0.16), "tunic": Color(0.55, 0.24, 0.18),
			"trim": Color(0.95, 0.80, 0.45), "beard": Color(0.92, 0.90, 0.86)},
		{"hat": Color(0.16, 0.35, 0.62), "tunic": Color(0.20, 0.42, 0.30),
			"trim": Color(0.95, 0.80, 0.45), "beard": Color(0.75, 0.62, 0.45)},
		{"hat": Color(0.45, 0.22, 0.55), "tunic": Color(0.50, 0.30, 0.55),
			"trim": Color(0.95, 0.80, 0.45), "beard": Color(0.88, 0.82, 0.72)},
	]
	const _SKIN := Color(0.98, 0.80, 0.62)
	const _SKIN_D := Color(0.90, 0.66, 0.48)

	func _init() -> void:
		_font = ThemeDB.fallback_font
		# Sky: warm dawn gradient (baked once, drawn scaled — 1 call).
		var g := Gradient.new()
		g.set_color(0, Color(0.35, 0.55, 0.85))
		g.add_point(0.55, Color(0.62, 0.78, 0.92))
		g.set_color(1, Color(0.98, 0.87, 0.70))
		_sky_tex = GradientTexture2D.new()
		_sky_tex.gradient = g
		_sky_tex.fill_from = Vector2(0.5, 0.0)
		_sky_tex.fill_to = Vector2(0.5, 1.0)
		_sky_tex.width = 16
		_sky_tex.height = 256
		# Vignette: transparent center, darkened corners (cinematic).
		var v := Gradient.new()
		v.set_color(0, Color(0, 0, 0, 0.0))
		v.add_point(0.62, Color(0, 0, 0, 0.0))
		v.set_color(1, Color(0.02, 0.01, 0.03, 0.42))
		_vig_tex = GradientTexture2D.new()
		_vig_tex.gradient = v
		_vig_tex.fill = GradientTexture2D.FILL_RADIAL
		_vig_tex.fill_from = Vector2(0.5, 0.5)
		_vig_tex.fill_to = Vector2(1.0, 0.5)
		_vig_tex.width = 256
		_vig_tex.height = 256
		_bar_bg.bg_color = Color(0.06, 0.04, 0.02, 0.92)
		_bar_bg.border_color = Color(0.72, 0.55, 0.16)
		_bar_fill.bg_color = Color(0.95, 0.72, 0.20)
		for i: int in 14:
			_flies.append({"x": randf(), "y": 0.55 + randf() * 0.4,
				"p": randf() * TAU, "s": 0.5 + randf()})

	## Per-frame state: particles, marchers, hammer strikes. Called by the
	## screen's _process (which also queue_redraws right after).
	func tick(delta: float, vsz: Vector2) -> void:
		t = screen._t if screen != null else t + delta
		for i: int in _march.size():
			_march[i] += delta * 0.055
			if _march[i] > 1.25:
				_march[i] = -0.25
		# Chimney smoke rises.
		if _smoke.size() < 24 and randf() < delta * 6.0:
			_smoke.append({"x": 0.0, "y": 0.0, "age": 0.0,
				"chim": randi() % 3})
		for p: Dictionary in _smoke:
			p["age"] = float(p["age"]) + delta
			p["y"] = float(p["y"]) - delta * 34.0
			p["x"] = float(p["x"]) + delta * 9.0
		_smoke = _smoke.filter(func(p: Dictionary) -> bool:
			return float(p["age"]) < 2.6)
		# Builder hammer strike -> dust burst at the frame.
		var ht := fmod(t * 1.3, 1.0)
		if ht < _hammer_prev and _dust.size() < 16:
			_dust.append({"x": 0.0, "y": 0.0, "age": 0.0})
		_hammer_prev = ht
		for p: Dictionary in _dust:
			p["age"] = float(p["age"]) + delta
		_dust = _dust.filter(func(p: Dictionary) -> bool:
			return float(p["age"]) < 0.6)
		for f: Dictionary in _flies:
			f["p"] = float(f["p"]) + delta * float(f["s"])

	# --- camera ---------------------------------------------------------
	## Cinematic sweep: starts panned left, eases across the scene, then
	## breathes with a gentle idle sway. Parallax layers scale the offset.
	func _cam(s: float) -> float:
		var st := maxf(0.0, t - LoadingScreen._T_STUDIO)
		var k := clampf(st / LoadingScreen._T_SWEEP, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0) # ease-out cubic
		var sweep := lerpf(-170.0 * s, 0.0, e)
		if k >= 1.0:
			sweep += sin((st - LoadingScreen._T_SWEEP) * 0.45) * 9.0 * s
		return sweep

	# --- small helpers ---------------------------------------------------
	func _rrect(r: Rect2, rad: float, c: Color) -> void:
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return
		var rr := minf(rad, minf(r.size.x, r.size.y) * 0.5)
		draw_rect(Rect2(r.position + Vector2(rr, 0), r.size - Vector2(rr * 2, 0)), c)
		draw_rect(Rect2(r.position + Vector2(0, rr), r.size - Vector2(0, rr * 2)), c)
		for cp: Vector2 in [r.position + Vector2(rr, rr),
				r.position + Vector2(r.size.x - rr, rr),
				r.position + Vector2(rr, r.size.y - rr),
				r.position + Vector2(r.size.x - rr, r.size.y - rr)]:
			draw_circle(cp, rr, c)

	func _poly(pts: PackedVector2Array, c: Color) -> void:
		if pts.size() >= 3:
			draw_colored_polygon(pts, c)

	# --- landscape layers ------------------------------------------------
	func _draw_sky(vsz: Vector2) -> void:
		draw_texture_rect(_sky_tex, Rect2(Vector2.ZERO, vsz), false)

	func _draw_sun(vsz: Vector2, s: float) -> void:
		var p := Vector2(vsz.x * 0.82, vsz.y * 0.15)
		var pulse := 1.0 + sin(t * 0.8) * 0.03
		draw_circle(p, 64.0 * s * pulse, Color(1.0, 0.95, 0.75, 0.18))
		draw_circle(p, 46.0 * s * pulse, Color(1.0, 0.94, 0.70, 0.35))
		draw_circle(p, 32.0 * s, Color(1.0, 0.96, 0.78))

	func _draw_clouds(vsz: Vector2, s: float, cam: float) -> void:
		for i: int in 6:
			var fi := float(i)
			var speed := 6.0 + fi * 2.5
			var cx := fmod(fi * 397.0 + t * speed + cam * 0.08, vsz.x + 480.0) - 240.0
			var cy := vsz.y * (0.08 + 0.055 * fmod(fi * 2.3, 3.0))
			var cs := (0.7 + 0.18 * fmod(fi * 1.7, 2.0)) * s
			var c := Color(1, 1, 1, 0.92)
			var shade := Color(0.88, 0.92, 0.97, 0.92)
			draw_circle(Vector2(cx, cy + 8 * cs), 34 * cs, shade)
			for off: Vector2 in [Vector2(-38, 6), Vector2(-12, -8),
					Vector2(16, -6), Vector2(40, 8)]:
				draw_circle(Vector2(cx, cy) + off * cs, 26 * cs, c)
			draw_circle(Vector2(cx, cy + 14 * cs), 30 * cs, c)

	func _draw_birds(vsz: Vector2, s: float, cam: float) -> void:
		var c := Color(0.25, 0.22, 0.28, 0.85)
		for i: int in 3:
			var fi := float(i)
			var bx := fmod(fi * 520.0 + t * (22.0 + fi * 6.0) + cam * 0.1,
				vsz.x + 200.0) - 100.0
			var by := vsz.y * 0.20 + sin(t * 1.3 + fi * 2.0) * 12.0 * s \
				+ fi * 26.0 * s
			var w := (10.0 + fi * 2.0) * s
			var flap := sin(t * 7.0 + fi * 2.4) * 4.0 * s
			draw_arc(Vector2(bx - w * 0.5, by), w * 0.55, PI * 1.15, PI * 1.85,
				8, c, 3.0 * s, true)
			draw_arc(Vector2(bx + w * 0.5, by - flap * 0.3), w * 0.55,
				PI * 1.15, PI * 1.85, 8, c, 3.0 * s, true)

	func _draw_hills(vsz: Vector2, s: float, cam: float) -> void:
		var hy := vsz.y * 0.52
		# Far hills (blue-green silhouette).
		var pts := PackedVector2Array()
		pts.append(Vector2(-50, hy + 40 * s))
		var x := -50.0
		while x < vsz.x + 50.0:
			var px := x + cam * 0.15
			pts.append(Vector2(px, hy - (46.0 + 30.0 * sin(x * 0.008)
				+ 14.0 * sin(x * 0.021 + 2.0)) * s))
			x += 46.0
		pts.append(Vector2(vsz.x + 50 + cam * 0.15, hy + 40 * s))
		_poly(pts, Color(0.35, 0.52, 0.55))
		# Near hills (rich green).
		pts = PackedVector2Array()
		var ny := vsz.y * 0.60
		pts.append(Vector2(-50, ny + 60 * s))
		x = -50.0
		while x < vsz.x + 50.0:
			var px2 := x + cam * 0.35
			pts.append(Vector2(px2, ny - (34.0 + 22.0 * sin(x * 0.011 + 1.0)
				+ 10.0 * sin(x * 0.033)) * s))
			x += 40.0
		pts.append(Vector2(vsz.x + 50 + cam * 0.35, ny + 60 * s))
		_poly(pts, Color(0.30, 0.55, 0.32))
		# Hill highlight rim.
		pts = PackedVector2Array()
		pts.append(Vector2(-50, ny + 60 * s))
		x = -50.0
		while x < vsz.x + 50.0:
			var px3 := x + cam * 0.35
			pts.append(Vector2(px3, ny - (34.0 + 22.0 * sin(x * 0.011 + 1.0)
				+ 10.0 * sin(x * 0.033)) * s))
			x += 40.0
		for i: int in range(1, pts.size() - 1):
			draw_line(pts[i] + Vector2(0, 3 * s), pts[i + 1] + Vector2(0, 3 * s),
				Color(0.55, 0.78, 0.45, 0.8), 4.0 * s, true)

	## Chibi houses with chimneys; smoke anchors are recorded for tick().
	func _draw_town(vsz: Vector2, s: float, cam: float) -> void:
		var base_y := vsz.y * 0.60
		var specs: Array = [
			[0.34, 1.0, Color(0.96, 0.90, 0.76), Color(0.72, 0.32, 0.22)],
			[0.52, 1.25, Color(0.93, 0.86, 0.70), Color(0.55, 0.28, 0.35)],
			[0.70, 0.9, Color(0.97, 0.92, 0.80), Color(0.30, 0.45, 0.62)],
		]
		for si: int in specs.size():
			var fx: float = float(specs[si][0])
			var fs: float = float(specs[si][1])
			var wall: Color = specs[si][2]
			var roof: Color = specs[si][3]
			var hx := fx * vsz.x + cam * 0.35
			var hw := 120.0 * fs * s
			var hh := 88.0 * fs * s
			var hy := base_y - (30.0 + 18.0 * sin(fx * 40.0)) * s
			# Body + roof.
			_rrect(Rect2(hx - hw / 2, hy - hh, hw, hh), 8 * s, wall)
			_poly(PackedVector2Array([Vector2(hx - hw / 2 - 14 * s, hy - hh),
				Vector2(hx + hw / 2 + 14 * s, hy - hh),
				Vector2(hx, hy - hh - 62 * fs * s)]), roof)
			# Door + glowing windows.
			_rrect(Rect2(hx - 13 * s, hy - 44 * s, 26 * s, 44 * s),
				10 * s, Color(0.30, 0.18, 0.10))
			var glow := 0.85 + 0.15 * sin(t * 2.0 + float(si) * 1.7)
			_rrect(Rect2(hx - hw / 2 + 14 * s, hy - hh + 18 * s, 26 * s, 24 * s),
				4 * s, Color(1.0, 0.85, 0.45 * glow))
			_rrect(Rect2(hx + hw / 2 - 40 * s, hy - hh + 18 * s, 26 * s, 24 * s),
				4 * s, Color(1.0, 0.85, 0.45 * glow))
			# Chimney (smoke anchors read by tick via fixed offsets).
			var chx := hx + hw * 0.28
			draw_rect(Rect2(chx - 8 * s, hy - hh - 58 * fs * s, 16 * s,
				40 * s), Color(0.45, 0.35, 0.30))
		# Smoke puffs (anchored to chimney 1/2/3 tops).
		for p: Dictionary in _smoke:
			var ci := int(p["chim"])
			var fx2: float = float([0.34, 0.52, 0.70][ci])
			var fs2: float = float([1.0, 1.25, 0.9][ci])
			var hx2 := fx2 * vsz.x + cam * 0.35
			var hw2 := 120.0 * fs2 * s
			var hy2 := base_y - (30.0 + 18.0 * sin(fx2 * 40.0)) * s
			var age := float(p["age"])
			var a := clampf(1.0 - age / 2.6, 0.0, 1.0) * 0.5
			var r := (10.0 + age * 14.0) * s
			draw_circle(Vector2(hx2 + hw2 * 0.28 + float(p["x"]) * s,
				hy2 - 88.0 * fs2 * s - 62 * fs2 * s + float(p["y"]) * s),
				r, Color(0.95, 0.95, 0.97, a))

	# --- Wind Waker water -------------------------------------------------
	## Bold cel-shaded blue, scrolling spiral curls, drifting whitecaps,
	## animated lapping shoreline foam — the same water language as the
	## game's river redo, drawn crisp at native resolution.
	func _draw_water(vsz: Vector2, s: float, cam: float) -> void:
		var wy := vsz.y * 0.68
		var ox := cam * 0.6
		# Beach strip.
		var beach := PackedVector2Array()
		beach.append(Vector2(-60, wy + 26 * s))
		var bx := -60.0
		while bx < vsz.x + 60.0:
			beach.append(Vector2(bx + ox * 0.4,
				wy - 14 * s + 8 * s * sin(bx * 0.02)))
			bx += 40.0
		beach.append(Vector2(vsz.x + 60, wy + 26 * s))
		_poly(beach, Color(0.93, 0.82, 0.58))
		# Water base.
		draw_rect(Rect2(Vector2(-60, wy), Vector2(vsz.x + 120,
			vsz.y - wy + 60)), Color(0.10, 0.42, 0.78))
		# Cel shade bands (depth).
		for bi: int in 3:
			var by := wy + (34.0 + float(bi) * 44.0) * s
			var band := PackedVector2Array()
			band.append(Vector2(-60, by + 26 * s))
			var px := -60.0
			while px < vsz.x + 60.0:
				band.append(Vector2(px, by + 7 * s * sin(px * 0.015
					+ t * (0.7 + float(bi) * 0.25) + float(bi) * 2.0)))
				px += 36.0
			band.append(Vector2(vsz.x + 60, by + 26 * s))
			_poly(band, Color(0.08, 0.33, 0.68, 0.55))
		# Scrolling spiral curls.
		var spacing := 190.0 * s
		var count := int(vsz.x / spacing) + 3
		for i: int in count:
			var scroll := fmod(t * 46.0 * s, spacing)
			var cx := float(i) * spacing - scroll - spacing + ox * 0.3
			var cyy := wy + (54.0 + 44.0 * fmod(float(i) * 2.7, 3.0)) * s
			var r := (17.0 + 6.0 * sin(float(i) * 3.1)) * s
			var wcol := Color(0.75, 0.92, 1.0, 0.9)
			draw_arc(Vector2(cx, cyy), r, PI * 0.15, PI * 1.25, 20, wcol,
				5.0 * s, true)
			draw_arc(Vector2(cx, cyy), r * 0.55, PI * 0.5, PI * 1.6, 16,
				Color(0.88, 0.97, 1.0, 0.9), 4.0 * s, true)
			# Whitecap on the crest.
			var capx := cx + r * 0.9
			draw_arc(Vector2(capx, cyy - r * 0.75), r * 0.45, PI * 1.1,
				PI * 1.9, 10, Color(1, 1, 1, 0.95), 4.5 * s, true)
		# Drifting foam flecks.
		for i: int in 16:
			var fi2 := float(i)
			var fx := fmod(fi2 * 251.0 + t * (30.0 + fi2 * 3.0),
				vsz.x + 120.0) - 60.0 + ox * 0.2
			var fy := wy + (20.0 + fmod(fi2 * 47.0, vsz.y - wy - 30.0)) * s \
				+ sin(t * 1.8 + fi2) * 6.0 * s
			var fr := (3.0 + 2.0 * sin(fi2 * 5.0)) * s
			draw_circle(Vector2(fx, fy), fr, Color(1, 1, 1, 0.55))
		# Shoreline foam: animated lapping edge.
		var fx3 := -20.0
		while fx3 < vsz.x + 20.0:
			var lap := sin(fx3 * 0.045 + t * 2.6) * 7.0 * s
			var fr2 := (9.0 + 4.0 * sin(fx3 * 0.09 - t * 3.4)) * s
			draw_circle(Vector2(fx3 + ox * 0.4, wy + lap - 4 * s), fr2,
				Color(1, 1, 1, 0.85))
			fx3 += 26.0 * s
		draw_rect(Rect2(Vector2(-60, wy - 6 * s + sin(t * 2.6) * 4 * s),
			Vector2(vsz.x + 120, 12 * s)), Color(1, 1, 1, 0.35))

	# --- chibi gnomes (procedural HD) ------------------------------------
	## Draws one anime-chibi gnome, fully procedural: big round head, huge
	## blinking eyes, big nose, beard, pointy faction hat, stubby limbs.
	## modes: "wave" (hero greeting you), "march" (walk cycle), "hammer"
	## (builder striking a frame). phase offsets individuals.
	func _gnome(pos: Vector2, h: float, pal: Dictionary, mode: String,
			phase: float) -> void:
		var s := h / 120.0
		var tt := t + phase
		var hip := pos + Vector2(0, -26 * s)
		var blink := 1.0
		if fmod(tt, 3.7) < 0.13:
			blink = 0.12
		var bob := 0.0
		var leg_sw := 0.0
		var arm_sw := 0.0
		if mode == "march":
			bob = absf(sin(tt * 9.0)) * 5.0 * s
			leg_sw = sin(tt * 9.0) * 0.5
			arm_sw = sin(tt * 9.0 + PI) * 0.45
		elif mode == "wave":
			bob = sin(tt * 2.2) * 4.0 * s
		hip.y -= bob
		var skin: Color = _SKIN
		var skin_d: Color = _SKIN_D
		var hat: Color = pal["hat"]
		var tunic: Color = pal["tunic"]
		var trim: Color = pal["trim"]
		var beard: Color = pal["beard"]
		# Legs (stubby boots).
		for side: float in [-1.0, 1.0]:
			var sw := leg_sw * side if mode == "march" else 0.0
			var foot := hip + Vector2(side * 9 * s + sw * 14 * s, 26 * s)
			var knee := hip + Vector2(side * 9 * s + sw * 7 * s, 13 * s)
			draw_line(hip + Vector2(side * 8 * s, 0), knee,
				Color(0.35, 0.25, 0.18), 11 * s, true)
			draw_line(knee, foot, Color(0.35, 0.25, 0.18), 11 * s, true)
			draw_circle(foot + Vector2(sw * 4 * s, 2 * s), 8 * s,
				Color(0.28, 0.19, 0.13))
		# Back arm.
		var sh := hip + Vector2(0, -22 * s)
		var asw := arm_sw
		var hand_b := sh + Vector2(-16 * s - asw * 10 * s, 14 * s)
		draw_line(sh + Vector2(-10 * s, 0), hand_b, skin_d, 9 * s, true)
		draw_circle(hand_b, 6 * s, skin)
		# Body (round tunic).
		_rrect(Rect2(sh + Vector2(-20 * s, -30 * s), Vector2(40 * s, 34 * s)),
			16 * s, tunic)
		draw_line(sh + Vector2(-20 * s, -2 * s), sh + Vector2(20 * s, -2 * s),
			trim, 4 * s, true)
		draw_circle(sh + Vector2(0, -2 * s), 4 * s, trim)
		# Beard (behind face bottom).
		var face := sh + Vector2(0, -52 * s)
		var hr := 30 * s
		_poly(PackedVector2Array([
			face + Vector2(-hr * 0.85, hr * 0.25),
			face + Vector2(hr * 0.85, hr * 0.25),
			face + Vector2(hr * 0.35, hr * 1.25),
			face + Vector2(0, hr * 1.45),
			face + Vector2(-hr * 0.35, hr * 1.25)]), beard)
		# Head.
		draw_circle(face, hr, skin)
		# Ears.
		draw_circle(face + Vector2(-hr * 0.95, 0), 7 * s, skin)
		draw_circle(face + Vector2(hr * 0.95, 0), 7 * s, skin)
		# Eyes (huge, blinking).
		for side: float in [-1.0, 1.0]:
			var ec := face + Vector2(side * 12 * s, -4 * s)
			draw_circle(ec, 8.5 * s, Color.WHITE)
			draw_circle(ec + Vector2(side * 1.5 * s, 1 * s),
				8.5 * s * blink, Color(0.12, 0.10, 0.14))
			draw_circle(ec + Vector2(side * 1.5 * s - 2 * s, -1 * s),
				2.5 * s * blink, Color.WHITE)
		# Big gnome nose + cheeks.
		draw_circle(face + Vector2(0, 6 * s), 7 * s, skin_d)
		draw_circle(face + Vector2(-18 * s, 8 * s), 5 * s,
			Color(1.0, 0.55, 0.5, 0.45))
		draw_circle(face + Vector2(18 * s, 8 * s), 5 * s,
			Color(1.0, 0.55, 0.5, 0.45))
		# Pointy hat.
		_poly(PackedVector2Array([
			face + Vector2(-hr * 1.05, -hr * 0.45),
			face + Vector2(hr * 1.05, -hr * 0.45),
			face + Vector2(hr * 0.25 + sin(tt * 1.7) * 4 * s,
				-hr * 2.1)]), hat)
		_rrect(Rect2(face + Vector2(-hr * 1.12, -hr * 0.62),
			Vector2(hr * 2.24, 12 * s)), 6 * s, hat.darkened(0.15))
		draw_circle(face + Vector2(hr * 0.25 + sin(tt * 1.7) * 4 * s,
			-hr * 2.1), 7 * s, trim)
		# Front arm per mode.
		var shf := sh + Vector2(10 * s, 0)
		if mode == "wave":
			var wa := -2.1 + sin(tt * 6.0) * 0.35
			var hand := shf + Vector2(cos(wa), sin(wa)) * 30 * s
			draw_line(shf, shf + Vector2(cos(wa), sin(wa)) * 16 * s,
				skin_d, 9 * s, true)
			draw_line(shf + Vector2(cos(wa), sin(wa)) * 14 * s, hand,
				skin, 8 * s, true)
			draw_circle(hand, 6.5 * s, skin)
		elif mode == "hammer":
			var ht := fmod(tt * 1.3, 1.0)
			var ha := lerpf(0.85, -0.5, ht * ht)
			var hdir := Vector2(cos(ha), sin(ha))
			var grip := shf + hdir * 26 * s
			draw_line(shf, grip, skin_d, 9 * s, true)
			draw_circle(grip, 6 * s, skin)
			var htop := grip + hdir * 16 * s
			draw_line(grip, htop + hdir * 14 * s, Color(0.5, 0.35, 0.2),
				6 * s, true)
			var perp := Vector2(-hdir.y, hdir.x)
			_rrect(Rect2(htop + hdir * 10 * s - perp * 9 * s,
				Vector2(18 * s, 12 * s)), 3 * s, Color(0.45, 0.45, 0.50))
		else: # march
			var hand_f := shf + Vector2(16 * s + asw * 10 * s, 14 * s)
			draw_line(shf, hand_f, skin_d, 9 * s, true)
			draw_circle(hand_f, 6 * s, skin)

	## House frame under construction (foundation -> frame stage).
	func _draw_frame(pos: Vector2, s: float) -> void:
		var wood := Color(0.62, 0.44, 0.26)
		var wood_d := Color(0.48, 0.33, 0.18)
		var w := 110.0 * s
		var h := 90.0 * s
		# Foundation stones.
		for i: int in 5:
			var sx := pos.x - w / 2 + float(i) * w / 4
			draw_circle(Vector2(sx, pos.y), 9 * s, Color(0.55, 0.55, 0.58))
		# Posts + beams (frame stage).
		for px: float in [-w / 2, -w / 6, w / 6, w / 2]:
			draw_rect(Rect2(pos + Vector2(px - 5 * s, -h),
				Vector2(10 * s, h)), wood)
		draw_rect(Rect2(pos + Vector2(-w / 2 - 6 * s, -h - 8 * s),
			Vector2(w + 12 * s, 10 * s)), wood_d)
		draw_rect(Rect2(pos + Vector2(-w / 2 - 6 * s, -h * 0.45),
			Vector2(w + 12 * s, 8 * s)), wood)
		# Scaffold arm (blueprint style).
		draw_line(pos + Vector2(w / 2 + 6 * s, 0),
			pos + Vector2(w / 2 + 26 * s, -h * 0.7), Color(0.4, 0.6, 0.9),
			4 * s, true)

	# --- actors ----------------------------------------------------------
	## Foreground dune the hero + builder stand on. Its top edge stays
	## clear of the progress UI (portrait phones) instead of colliding.
	func _dune_top(vsz: Vector2, s: float) -> float:
		var dt := vsz.y * 0.80
		if bar_rect.size.x > 0.0:
			dt = minf(dt, bar_rect.position.y - 190.0 * s)
		return dt

	func _draw_foreground(vsz: Vector2, s: float, cam: float) -> void:
		var dt := _dune_top(vsz, s)
		var dune := PackedVector2Array()
		dune.append(Vector2(-60, vsz.y + 60))
		var dx := -60.0
		while dx < vsz.x + 60.0:
			dune.append(Vector2(dx + cam * 0.85,
				dt + 10 * s * sin(dx * 0.018 + 1.0)))
			dx += 44.0
		dune.append(Vector2(vsz.x + 60, vsz.y + 60))
		_poly(dune, Color(0.88, 0.76, 0.53))
		# Dune crest highlight.
		var hx := -60.0
		while hx < vsz.x + 60.0:
			var p1 := Vector2(hx + cam * 0.85, dt + 10 * s * sin(hx * 0.018 + 1.0))
			var p2 := Vector2(hx + 44.0 + cam * 0.85,
				dt + 10 * s * sin((hx + 44.0) * 0.018 + 1.0))
			draw_line(p1, p2, Color(0.96, 0.85, 0.62, 0.9), 4.0 * s, true)
			hx += 44.0
		# Grass tufts on the dune.
		for i: int in 14:
			var fi := float(i)
			var gx := fmod(fi * 211.0, vsz.x + 80.0) - 40.0 + cam * 0.85
			var gy := dt + 26 * s + fmod(fi * 37.0, 60.0) * s
			var sway := sin(t * 2.2 + fi * 1.9) * 6.0 * s
			var gh := (12.0 + 8.0 * fmod(fi * 3.1, 2.0)) * s
			draw_line(Vector2(gx, gy), Vector2(gx + sway, gy - gh),
				Color(0.25, 0.50, 0.28), 3.0 * s, true)

	func _draw_actors(vsz: Vector2, s: float, cam: float) -> void:
		var beach_y := vsz.y * 0.68
		# Marching gnomes cross the beach (walk cycles).
		for i: int in _march.size():
			var mx := (_march[i] * (vsz.x + 320.0 * s) - 160.0 * s) + cam
			var pal: Dictionary = _PALETTES[i % _PALETTES.size()]
			_gnome(Vector2(mx, beach_y + 6 * s), 104.0 * s, pal, "march",
				float(i) * 2.4)
		# Builder gnome hammering a house frame, on the foreground dune.
		var dt := _dune_top(vsz, s)
		var bpos := Vector2(vsz.x * 0.80 + cam, dt + 78.0 * s)
		_draw_frame(bpos + Vector2(66 * s, 0), s)
		_gnome(bpos, 118.0 * s, _PALETTES[0], "hammer", 1.1)
		# Dust puffs from hammer strikes.
		for p: Dictionary in _dust:
			var age := float(p["age"])
			var a := clampf(1.0 - age / 0.6, 0.0, 1.0)
			draw_circle(bpos + Vector2(66 * s + sin(age * 20.0) * 8 * s,
				-6 * s - age * 26 * s), (7.0 + age * 22.0) * s,
				Color(0.80, 0.70, 0.55, 0.5 * a))
		# Hero gnome (foreground) waves at YOU.
		_gnome(Vector2(vsz.x * 0.20 + cam, dt + 86.0 * s), 208.0 * s,
			_PALETTES[1], "wave", 0.0)

	func _draw_grass(vsz: Vector2, s: float, cam: float) -> void:
		var gy := vsz.y * 0.66
		for i: int in 22:
			var fi := float(i)
			var gx := fmod(fi * 173.0, vsz.x + 80.0) - 40.0 + cam * 0.8
			var sway := sin(t * 2.0 + fi * 1.3) * 6.0 * s
			var gh := (10.0 + 8.0 * fmod(fi * 2.9, 2.0)) * s
			draw_line(Vector2(gx, gy), Vector2(gx + sway, gy - gh),
				Color(0.25, 0.50, 0.28), 3.0 * s, true)
			if fmod(fi, 4.0) < 1.0:
				draw_circle(Vector2(gx + sway, gy - gh), 4 * s,
					Color(0.95, 0.80, 0.85))

	func _draw_flies(vsz: Vector2, s: float) -> void:
		for f: Dictionary in _flies:
			var p := float(f["p"])
			var fx := (float(f["x"]) * vsz.x
				+ sin(p * 0.9) * 30.0 * s)
			var fy := (float(f["y"]) * vsz.y + cos(p * 1.2) * 18.0 * s)
			var a := 0.25 + 0.55 * (0.5 + 0.5 * sin(p * 3.0))
			draw_circle(Vector2(fx, fy), 3.2 * s, Color(1.0, 0.95, 0.6, a))

	# --- studio card (AAA intro, skippable) -------------------------------
	func _draw_studio(vsz: Vector2, s: float, a: float) -> void:
		if a <= 0.0:
			return
		var cx := vsz.x * 0.5
		var cy := vsz.y * 0.44
		var fs := int(64.0 * s)
		var pop := _back_ease(clampf(t / 0.7, 0.0, 1.0))
		draw_set_transform(Vector2(cx, cy), 0.0, Vector2(pop, pop))
		var nm := LoadingScreen.STUDIO_NAME
		var nw := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT,
			-1, fs).x
		draw_string_outline(_font, Vector2(-nw / 2, 22 * s), nm,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs / 10)),
			Color(0.10, 0.08, 0.06, a))
		draw_string(_font, Vector2(-nw / 2, 22 * s), nm,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.93, 0.86, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var pfs := int(24.0 * s)
		var pw := _font.get_string_size("P R E S E N T S",
			HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x
		draw_string(_font, Vector2(cx - pw / 2, cy + 64 * s), "P R E S E N T S",
			HORIZONTAL_ALIGNMENT_LEFT, -1, pfs,
			Color(0.70, 0.66, 0.58, a * clampf((t - 0.5) / 0.6, 0.0, 1.0)))
		# "tap to skip" whisper.
		var sfs := int(17.0 * s)
		var sw := _font.get_string_size("tap to skip",
			HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		draw_string(_font, Vector2(cx - sw / 2, vsz.y - 90 * s), "tap to skip",
			HORIZONTAL_ALIGNMENT_LEFT, -1, sfs,
			Color(0.55, 0.53, 0.48, a * 0.7))

	# --- title / motto / bar ----------------------------------------------
	func _back_ease(x: float) -> float:
		var c1 := 1.70158
		var c3 := c1 + 1.0
		return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

	func _draw_title(vsz: Vector2, s: float, a: float, cy_frac := 0.17,
			letter_t0 := -1.0) -> void:
		if a <= 0.0:
			return
		var fs := int(96.0 * s)
		var widths: Array[float] = []
		var total := 0.0
		for i: int in LoadingScreen._TITLE.length():
			var w := _font.get_string_size(LoadingScreen._TITLE.substr(i, 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			widths.append(w)
			total += w
		# HD means SHARP, not huge: shrink the whole title to fit 94% of
		# the viewport width (portrait phones) instead of overflowing.
		var fit := minf(1.0, (vsz.x * 0.94) / maxf(total, 1.0))
		var x := vsz.x * 0.5 - total * fit * 0.5
		var y := vsz.y * cy_frac
		var ascent := _font.get_ascent(fs)
		var lt0: float = LoadingScreen._T_TITLE if letter_t0 < 0.0 \
			else letter_t0
		for i: int in LoadingScreen._TITLE.length():
			var lt := (t - lt0 - float(i)
				* LoadingScreen._T_LETTER) / 0.45
			if lt > 0.0:
				var sc: float = _back_ease(minf(lt, 1.0)) * fit
				var ch := LoadingScreen._TITLE.substr(i, 1)
				draw_set_transform(Vector2(x + widths[i] * fit * 0.5, y),
					0.0, Vector2(sc, sc))
				var ow := maxi(3, int(fs / 9))
				draw_string_outline(_font,
					Vector2(-widths[i] * 0.5, ascent * 0.35), ch,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow,
					Color(0.22, 0.10, 0.03, a))
				draw_string(_font, Vector2(-widths[i] * 0.5, ascent * 0.35),
					ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(1.0, 0.835, 0.31, a))
				# Gold sheen on the top half of each letter.
				draw_string(_font, Vector2(-widths[i] * 0.5, ascent * 0.35),
					ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(1.0, 0.95, 0.62, a * 0.35 * sc))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			x += widths[i] * fit

	func _draw_motto(vsz: Vector2, s: float) -> void:
		if motto_alpha <= 0.0:
			return
		var fs := int(23.0 * s)
		var w := _font.get_string_size(LoadingScreen._MOTTO,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := vsz.y * 0.17 + 78.0 * s + sin(t * 1.4) * 3.0 * s
		draw_string(_font, Vector2(vsz.x * 0.5 - w / 2, y),
			LoadingScreen._MOTTO, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.98, 0.90, 0.64, motto_alpha))

	func _draw_bar(s: float) -> void:
		if bar_rect.size.x <= 0.0:
			return
		var frac: float = screen._bar_shown if screen != null else 0.0
		var rad := bar_rect.size.y * 0.5
		# Glow.
		_rrect(bar_rect.grow(6 * s), rad + 6 * s, Color(1.0, 0.8, 0.3, 0.16))
		_bar_bg.set_corner_radius_all(int(rad))
		_bar_bg.border_width_left = 2
		_bar_bg.border_width_right = 2
		_bar_bg.border_width_top = 2
		_bar_bg.border_width_bottom = 2
		draw_style_box(_bar_bg, bar_rect)
		var pad := 4.0 * s
		var fw: float = maxf(0.0, (bar_rect.size.x - pad * 2.0) * frac)
		if fw > 1.0:
			var fr := Rect2(bar_rect.position + Vector2(pad, pad),
				Vector2(fw, bar_rect.size.y - pad * 2.0))
			_bar_fill.set_corner_radius_all(int(fr.size.y * 0.5))
			draw_style_box(_bar_fill, fr)
			# Animated sheen sweeping the fill.
			var shx := fr.position.x + fmod(t * 160.0 * s,
				fr.size.x + 80.0 * s) - 40.0 * s
			_poly(PackedVector2Array([
				Vector2(shx, fr.position.y),
				Vector2(shx + 26 * s, fr.position.y),
				Vector2(shx + 10 * s, fr.end.y),
				Vector2(shx - 16 * s, fr.end.y)]),
				Color(1, 1, 1, 0.28))

	# --- assembly ----------------------------------------------------------
	func _draw() -> void:
		var vsz := size
		if vsz.x <= 0.0 or vsz.y <= 0.0 or _font == null:
			return
		var s: float = screen._ui_scale if screen != null else 1.0
		# AAA first-boot intro (Jeremy 2026-10-11): cinematic beats before
		# the menu. World boots keep the original cinematic below.
		if screen != null and screen._intro_mode:
			_draw_intro(vsz, s)
			return
		# Studio card beat (skippable AAA intro).
		if t < 2.0:
			draw_rect(Rect2(Vector2.ZERO, vsz), Color(0.03, 0.02, 0.02))
			_draw_studio(vsz, s, clampf(t / 0.6, 0.0, 1.0))
			return
		var cam := _cam(s)
		_draw_landscape(vsz, s, cam)
		# Cinematic title entrance.
		var title_a := clampf((t - LoadingScreen._T_TITLE + 0.4) / 0.6,
			0.0, 1.0)
		_draw_title(vsz, s, title_a * global_alpha)
		_draw_motto(vsz, s)
		_draw_bar(s)
		# Vignette (cinema).
		draw_texture_rect(_vig_tex, Rect2(Vector2.ZERO, vsz), false)
		# Crossfade: studio card hands off to the landscape.
		if t < 2.55:
			var k := 1.0 - (t - 2.0) / 0.55
			draw_rect(Rect2(Vector2.ZERO, vsz),
				Color(0.03, 0.02, 0.02, k))
			_draw_studio(vsz, s, k)
		# Intro fade-from-black (starts as the landscape reveals).
		if fade > 0.0:
			draw_rect(Rect2(Vector2.ZERO, vsz),
				Color(0.02, 0.015, 0.015, fade * global_alpha))
		# Global fade (finish).
		if global_alpha < 1.0:
			draw_rect(Rect2(Vector2.ZERO, vsz),
				Color(0, 0, 0, 1.0 - global_alpha))

	## Sky through fireflies, in order.
	func _draw_landscape(vsz: Vector2, s: float, cam: float) -> void:
		_draw_sky(vsz)
		_draw_sun(vsz, s)
		_draw_clouds(vsz, s, cam)
		_draw_birds(vsz, s, cam)
		_draw_hills(vsz, s, cam)
		_draw_town(vsz, s, cam)
		_draw_water(vsz, s, cam)
		_draw_grass(vsz, s, cam)
		_draw_foreground(vsz, s, cam)
		_draw_actors(vsz, s, cam)
		_draw_flies(vsz, s)

	# --- AAA first-boot intro beats (Jeremy 2026-10-11) ------------------
	## Beat order: studio card -> logo (+chuckle) -> living world (ambience)
	## -> music over the world -> menu. Every beat is skippable by tap.
	func _draw_intro(vsz: Vector2, s: float) -> void:
		var beat: int = screen._intro_beat
		var kind := str(LoadingScreen._INTRO_BEATS[beat]["kind"])
		var a: float = screen._intro_beat_alpha(beat)
		if kind == "studio":
			draw_rect(Rect2(Vector2.ZERO, vsz), Color(0.03, 0.02, 0.02))
			_draw_studio_intro(vsz, s, a)
		elif kind == "logo":
			draw_rect(Rect2(Vector2.ZERO, vsz), Color(0.03, 0.02, 0.02))
			_draw_logo_intro(vsz, s, a)
		else:
			# world + music beats: the living landscape keeps breathing.
			var cam := _cam(s)
			_draw_landscape(vsz, s, cam)
			draw_texture_rect(_vig_tex, Rect2(Vector2.ZERO, vsz), false)
			if a < 1.0:
				# Fade the landscape in from (and out to) the black card.
				draw_rect(Rect2(Vector2.ZERO, vsz),
					Color(0.03, 0.02, 0.02, 1.0 - a))
		# "tap to skip" whisper on every beat.
		var sfs := int(17.0 * s)
		var sw := _font.get_string_size("tap to skip",
			HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		draw_string(_font, Vector2(vsz.x * 0.5 - sw / 2, vsz.y - 90 * s),
			"tap to skip", HORIZONTAL_ALIGNMENT_LEFT, -1, sfs,
			Color(0.55, 0.53, 0.48, 0.7))

	## "ETHOS GAMES" — elegant, letter-spaced, cinematic. Fades in, holds,
	## fades out (envelope a). "presents" rides beneath in smaller caps.
	func _draw_studio_intro(vsz: Vector2, s: float, a: float) -> void:
		if a <= 0.0:
			return
		var cx := vsz.x * 0.5
		var cy := vsz.y * 0.44
		var nm := LoadingScreen.STUDIO_NAME
		var fs := int(58.0 * s)
		# Letter-spaced for the cinematic feel.
		var spaced := ""
		for i in nm.length():
			spaced += nm.substr(i, 1)
			if nm.substr(i, 1) != " ":
				spaced += " "
		var nw := _font.get_string_size(spaced, HORIZONTAL_ALIGNMENT_LEFT,
			-1, fs).x
		# Shrink to fit narrow portrait screens (HD = sharp, not huge).
		var fit := minf(1.0, (vsz.x * 0.9) / maxf(nw, 1.0))
		draw_set_transform(Vector2(cx, cy), 0.0, Vector2(fit, fit))
		draw_string(_font, Vector2(-nw / 2, 20 * s), spaced,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.93, 0.86, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var pfs := int(26.0 * s)
		var pw := _font.get_string_size("p r e s e n t s",
			HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x
		draw_string(_font, Vector2(cx - pw / 2, cy + 62 * s), "p r e s e n t s",
			HORIZONTAL_ALIGNMENT_LEFT, -1, pfs,
			Color(0.70, 0.66, 0.58, a))

	## Cursing Gnomes logo: the title-screen entrance (letter-by-letter
	## weighted pop), centered, fading in and out on the beat envelope.
	func _draw_logo_intro(vsz: Vector2, s: float, a: float) -> void:
		if a <= 0.0:
			return
		_draw_title(vsz, s, a, 0.40,
			float(LoadingScreen._INTRO_BEATS[1]["t0"]))
