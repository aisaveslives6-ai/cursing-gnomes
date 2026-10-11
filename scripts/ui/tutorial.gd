class_name TutorialDirector
extends Node
## Cursing Gnomes — "First Reign" guided tutorial, AAA remaster (Jeremy 2026-10-11).
##
## New games ask "Are you a first-time player?" — YES runs the full guided
## tour, "I know how, let me play dammit" skips straight in. The tour is
## guided and voiced in Ethos's own register (warm, sharp, calm, dry wit —
## a funny friend who actually wants you to get it), with flowing animated
## "tap here" callouts that direct attention at the real UI: a bouncing
## chevron + expanding pulse rings over the Build button, the phone bubble,
## the diplomacy bubble, and a pulsing gold ring on map targets.
##
## Steps teach the REAL game, verified against the repo — camera, select,
## build (staged construction), resources/stockpiles, workers/housing
## (16/town cap), roads (player road tool), phone/Bastard OS, military
## (tap-to-command), disasters (28, Forecast app), trade deals (Treasury
## advisor) — and point the player at Mr Smart Bitch in the phone contacts
## for any further questions. Purely additive: never changes sim state,
## never invents mechanics, stays out of sandbox observe and adventure mode.
##
## Persistence: user://tutorial.cfg ("completed" flag). Skipping marks
## completed so we never nag a returning ruler.
##
## Headless-safe: all world reads null-check; tests drive completion via
## the _probe dictionary instead of live refs.


const SAVE_PATH := "user://tutorial.cfg"
const OFFER_DELAY := 2.0
const CAMERA_MOVE_PX := 150.0

## Step ids, in order. "action" is the banner button label; "" means the
## step only completes via its game-state check (still skippable).
## "callout": "" (none), "world_unit" (gold ring on a subject),
## "hud_build" / "hud_phone" / "hud_diplomacy" / "hud_army" (animated
## tap-here arrow over the real HUD control).
const STEPS: Array = [
	{"id": "welcome", "title": "A new ruler approaches",
		"body": "Well, well. Fresh crown, same old cursed land. I'm Ethos — I helped build this mess, so I know where the bodies are buried. Give me a few minutes and I'll teach you to rule it. Deal?",
		"action": "Deal. Teach me.", "callout": ""},
	{"id": "camera", "title": "The lay of the land",
		"body": "First: look around. Drag with one finger to pan, pinch to zoom. Your realm is bigger than your problems — barely. Go on, take it for a spin.",
		"action": "Got it", "callout": ""},
	{"id": "select", "title": "Your subjects",
		"body": "Tap one of your people. They're small, they're busy, and statistically one of them is plotting something. The gold ring marks a fine specimen.",
		"action": "", "callout": "world_unit"},
	{"id": "build", "title": "Raise the roof. Literally.",
		"body": "Tap the BUILD button I'm pointing at, pick a building, then tap open ground. Your workers handle the rest — foundation, frame, walls, roof. You just point and take credit. That's leadership.",
		"action": "", "callout": "hud_build"},
	{"id": "gather", "title": "The economy, such as it is",
		"body": "Gold, wood, food, oil, seeds, soul essence — six flavors of treasure, ticking up at the top of your screen. Workers gather on their own. Lumber camps go near trees, oil only comes from pumpjacks. Watch the numbers climb and try not to drool.",
		"action": "Shiny", "callout": ""},
	{"id": "workers", "title": "Housing: it's a whole thing",
		"body": "People need homes — 16 per town, no more, the gnomes unionized. Build houses and your population grows. Homeless folks build their own shacks out in the countryside and take up farming. Resourceful. Smelly, but resourceful.",
		"action": "Noted", "callout": ""},
	{"id": "roads", "title": "Roads. Actual roads.",
		"body": "Your roadbuilders lay real networks between your buildings — surveyed, graded, paved, with little work zones and everything. Want your own? Open Build, pick the Roads tab, and drag. Wagons, carts, and fire trucks all prefer pavement. Snobs, the lot of them.",
		"action": "Pave the world", "callout": "hud_build"},
	{"id": "phone", "title": "The phone. Yes, really.",
		"body": "Tap the phone bubble — welcome to Bastard OS. Messages, the Chronicle, weather forecasts, diplomacy, your advisors, all in your pocket. And in your contacts lives Mr Smart Bitch. He knows literally everything about this game and answers questions. He's also rude. You'll love him.",
		"action": "", "callout": "hud_phone"},
	{"id": "military", "title": "The art of war",
		"body": "Tap your army and the WHOLE lot moves as one — attack-move chews through whatever's nearest. Train soldiers at the barracks, ring your base with star forts (mind the wall gaps — soldiers need doors too), and when war goes bad your advisors will beg for peace with real numbers. Listen. Or don't. I'm not your mom.",
		"action": "For glory", "callout": "hud_army"},
	{"id": "disasters", "title": "About the disasters",
		"body": "Twenty-eight of them. Bandit raids, thick moose, the works — the roster is frozen, so at least the horrors are familiar. The Forecast app tells you what's coming; check it like the weather, because here they're the same thing. Build fire stations. Trust me.",
		"action": "Yikes", "callout": ""},
	{"id": "trade", "title": "Make money, not war. Or both.",
		"body": "Other factions will trade — the diplomacy board I'm pointing at is where deals get made. Offer resources, haggle, sign. Your Treasury advisor tracks every deal on the ledger and can even run your trades for you if you ask nicely. Never trade with someone you're at war with. That's just called losing.",
		"action": "Show me the money", "callout": "hud_diplomacy"},
	{"id": "done", "title": "The realm is yours",
		"body": "That's the tour. Build, trade, scheme, survive — and try not to get cursed. It's in the name. It's basically a promise. And remember: Mr Smart Bitch lives in your phone contacts. Any question, any time, he's your guy. Now go be the ruler this cursed land deserves.",
		"action": "Rule!", "callout": ""},
]

const GOLD := Color(1.0, 0.835, 0.310)
const WOOD := Color(0.29, 0.20, 0.13, 1.0)
const WOOD_BORDER := Color(0.79, 0.64, 0.15, 1.0)


## Pulsing map-space highlight ring (world child, so it pans with the map).
class Ring:
	extends Node2D
	var t := 0.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var r := 52.0 + sin(t * 5.0) * 7.0
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.0, 0.84, 0.31, 0.95), 6.0)
		draw_arc(Vector2.ZERO, r * 0.82, 0.0, TAU, 48, Color(1.0, 0.84, 0.31, 0.45), 3.0)


## Animated "tap here" callout (screen space, child of the tutorial layer).
## A bouncing gold chevron flowing down toward the target + expanding pulse
## rings. Smooth sine motion — delightful, never janky.
class Callout:
	extends Node2D
	var t := 0.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
	func _draw() -> void:
		var bob := sin(t * 4.0) * 10.0
		var gold := Color(1.0, 0.84, 0.31, 0.95)
		# Chevron arrow pointing down at the target.
		var y0 := -86.0 + bob
		var pts := PackedVector2Array([
			Vector2(-26, y0), Vector2(0, y0 + 26), Vector2(26, y0),
			Vector2(26, y0 + 12), Vector2(0, y0 + 38),
			Vector2(-26, y0 + 12),
		])
		draw_colored_polygon(pts, gold)
		# Expanding pulse rings around the target point.
		for i in range(2):
			var ph := fmod(t * 0.9 + float(i) * 0.5, 1.0)
			var r := 18.0 + ph * 46.0
			var a := (1.0 - ph) * 0.7
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40,
				Color(1.0, 0.84, 0.31, a), 4.0)


var _gs: GameState
var _world: Node = null

var _offer_armed := false
var _offer_timer := 0.0
var _offer_shown := false
var _active := false
var _finished := false
var _step := 0

# Persistent event flags: set by bus signals any time after start(), so
# steps auto-complete even if the player acts ahead of the tour.
var _did_build := false
var _did_train := false
var _did_gather := false
var _res_last: Dictionary = {}

var _cam_start := Vector2.ZERO
var _cam_armed := false

# Test hook: when set, completion checks read these keys instead of the
# live world ("selected", "camera_moved", "phone_open", "callout_pos").
var _probe: Dictionary = {}

var _layer: CanvasLayer
var _holder: VBoxContainer
var _banner: PanelContainer
var _title_lbl: Label
var _body_lbl: Label
var _step_lbl: Label
var _action_btn: Button
var _offer: CenterContainer
var _ring: Node2D
var _callout: Callout

## AudioManager, wired by main.gd at world start (same pattern as the
## boot intro's set_audio). Null-safe: the tour runs fine silent.
var _audio: Node = null


## Wire the AudioManager (main.gd calls this in _finish_world_start).
func set_audio(am: Node) -> void:
	_audio = am


func _init(game_state: GameState) -> void:
	_gs = game_state
	if _gs != null and _gs.bus != null:
		_gs.bus.building_placed.connect(_on_building_placed)
		_gs.bus.unit_spawned.connect(_on_unit_spawned)
		_gs.bus.resource_changed.connect(_on_resource_changed)


## Late wiring to live world refs (selection, camera, hud). Safe to call
## with null — checks degrade gracefully (headless/tests).
func setup_world(world: Node) -> void:
	_world = world
	_build_overlay()


static func is_completed() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	return bool(cfg.get_value("tutorial", "completed", false))


static func mark_completed() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # keep any other keys
	cfg.set_value("tutorial", "completed", true)
	cfg.save(SAVE_PATH)


## Called from world.configure() for normal games. Arms the first-time
## player prompt; no-op when already completed, sandbox, or adventure.
func maybe_offer() -> void:
	if _finished or is_completed():
		return
	_offer_armed = true
	_offer_timer = OFFER_DELAY


func start() -> void:
	_hide_offer()
	_did_build = false
	_did_train = false
	_did_gather = false
	_res_last.clear()
	_active = true
	_finished = false
	_step = 0
	_enter_step(0)
	_show_banner(true)
	_start_tutorial_music()


## Jeremy's own track underscores the tutorial — slow cinematic fade from
## silence, or a seamless continuation if the boot intro already faded it
## in (the audio manager no-ops the replay: no gaps, no pops, no restarts).
func _start_tutorial_music() -> void:
	if _audio != null and _audio.has_method("play_tutorial_music"):
		_audio.play_tutorial_music()


func skip() -> void:
	_active = false
	_finished = true
	_show_banner(false)
	_hide_offer()
	_hide_ring()
	_hide_callout()
	mark_completed()


func is_active() -> bool:
	return _active


func step_id() -> String:
	if _step >= 0 and _step < STEPS.size():
		return String(STEPS[_step]["id"])
	return ""


func tick(delta: float) -> void:
	if _finished:
		return
	if _offer_armed and not _offer_shown and not _active:
		_offer_timer -= delta
		if _offer_timer <= 0.0:
			_offer_armed = false
			_show_offer()
		return
	if not _active:
		return
	_tick_ring(delta)
	if _check_step_done():
		_advance()


func _faction() -> String:
	if _gs == null:
		return ""
	return String(_gs.get("player_faction"))


func _enter_step(idx: int) -> void:
	_step = idx
	_cam_armed = false
	_update_banner()
	_update_callout()
	# Forgiving entry: if the player already did it, the tick check
	# completes the step immediately on the next tick.


func _advance() -> void:
	if _step + 1 >= STEPS.size():
		_finish_tour()
		return
	_enter_step(_step + 1)


func _finish_tour() -> void:
	_active = false
	_finished = true
	_show_banner(false)
	_hide_ring()
	_hide_callout()
	mark_completed()


func _check_step_done() -> bool:
	match step_id():
		"welcome":
			return false  # button only
		"camera":
			return _camera_moved()
		"select":
			return _unit_selected()
		"build":
			return _did_build
		"gather":
			return _did_gather
		"train":
			return _did_train
		"phone":
			return _phone_open()
		_:
			return false  # button-driven steps


func _camera_moved() -> bool:
	if _probe.has("camera_moved"):
		return bool(_probe["camera_moved"])
	if _world == null:
		return false
	var cam: Node = _world.get("camera")
	if cam == null:
		return false
	var pos: Vector2 = cam.get("position")
	if not _cam_armed:
		_cam_start = pos
		_cam_armed = true
		return false
	return pos.distance_to(_cam_start) >= CAMERA_MOVE_PX


func _unit_selected() -> bool:
	if _probe.has("selected"):
		return bool(_probe["selected"])
	if _world == null:
		return false
	var sel: Node = _world.get("selection")
	if sel == null:
		return false
	return sel.get("selected") != null


func _phone_open() -> bool:
	if _probe.has("phone_open"):
		return bool(_probe["phone_open"])
	if _world == null:
		return false
	var hud: Node = _world.get("hud")
	if hud == null:
		return false
	for child in hud.get_children():
		if child is PhoneUI and (child as CanvasItem).visible:
			return true
	return false


func _player_unit_pos() -> Vector2:
	if _gs == null:
		return Vector2.INF
	var f := _faction()
	for u in _gs.units:
		if u is Dictionary and bool(u.get("alive", false)) \
				and String(u.get("faction", "")) == f:
			return u.get("position", Vector2.INF)
	return Vector2.INF


func _on_building_placed(b: Dictionary) -> void:
	if _active and String(b.get("faction", "")) == _faction():
		_did_build = true


func _on_unit_spawned(u: Dictionary) -> void:
	if _active and String(u.get("faction", "")) == _faction():
		_did_train = true


func _on_resource_changed(faction: String, resource: String, new_amount: float) -> void:
	if not _active or faction != _faction():
		return
	var key := faction + ":" + resource
	var old: float = float(_res_last.get(key, new_amount))
	_res_last[key] = new_amount
	if new_amount > old + 0.001:
		_did_gather = true


# --- Callouts ---------------------------------------------------------------

## Resolve a step's callout target to a screen position. Returns Vector2.INF
## when the target can't be found (callout hides gracefully).
func _callout_pos(kind: String) -> Vector2:
	if _probe.has("callout_pos"):
		return _probe["callout_pos"]
	if _world == null:
		return Vector2.INF
	var hud: Node = _world.get("hud")
	if hud == null:
		return Vector2.INF
	match kind:
		"hud_phone", "hud_diplomacy":
			var tab := "phone" if kind == "hud_phone" else "diplomacy"
			var tabs: Dictionary = hud.get("_side_tabs")
			if tabs != null and tabs.has(tab):
				var b := tabs[tab] as Button
				if b != null and b.visible:
					return b.get_global_rect().get_center()
		"hud_build", "hud_army":
			var want := "Build" if kind == "hud_build" else "Army"
			var found := _find_button(hud, want)
			if found != null:
				return (found as Button).get_global_rect().get_center()
	return Vector2.INF


## Recursive search for a visible Button with the given text.
func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text \
			and (node as CanvasItem).visible:
		return node as Button
	for child in node.get_children():
		var hit := _find_button(child, text)
		if hit != null:
			return hit
	return null


func _update_callout() -> void:
	_hide_callout()
	if not _active or _step < 0 or _step >= STEPS.size():
		return
	var kind := String(STEPS[_step].get("callout", ""))
	if kind == "" or kind == "world_unit":
		return  # world_unit is handled by the map ring
	var pos := _callout_pos(kind)
	if pos == Vector2.INF:
		return
	_show_callout(pos)


func _show_callout(screen_pos: Vector2) -> void:
	if _callout == null or not is_instance_valid(_callout):
		return
	_callout.position = screen_pos
	_callout.visible = true


func _hide_callout() -> void:
	if _callout != null and is_instance_valid(_callout):
		_callout.visible = false


# --- Overlay ---------------------------------------------------------------

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 96
	_layer.name = "TutorialLayer"
	add_child(_layer)

	# Top-wide holder so the banner auto-sizes to its text height —
	# portrait phones wrap to more lines than landscape.
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_left = 12
	holder.offset_right = -12
	holder.add_theme_constant_override("separation", 0)
	_layer.add_child(holder)
	_holder = holder
	_refit_safe()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_refit_safe)

	_banner = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = WOOD
	sb.border_color = WOOD_BORDER
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_banner.add_theme_stylebox_override("panel", sb)
	_banner.visible = false
	holder.add_child(_banner)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_banner.add_child(vb)

	var top := HBoxContainer.new()
	vb.add_child(top)
	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 26)
	_title_lbl.add_theme_color_override("font_color", GOLD)
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title_lbl)
	_step_lbl = Label.new()
	_step_lbl.add_theme_font_size_override("font_size", 20)
	_step_lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	top.add_child(_step_lbl)

	_body_lbl = Label.new()
	_body_lbl.add_theme_font_size_override("font_size", 21)
	_body_lbl.add_theme_color_override("font_color", Color.WHITE)
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_body_lbl)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	brow.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(brow)
	var skip_btn := Button.new()
	skip_btn.text = "Skip tour"
	skip_btn.custom_minimum_size = Vector2(0, 56)
	skip_btn.pressed.connect(skip)
	brow.add_child(skip_btn)
	_action_btn = Button.new()
	_action_btn.custom_minimum_size = Vector2(190, 56)
	_action_btn.pressed.connect(_on_action)
	brow.add_child(_action_btn)

	_build_offer()

	_ring = Ring.new()
	_ring.visible = false
	_ring.z_index = 500

	_callout = Callout.new()
	_callout.visible = false
	_layer.add_child(_callout)


## Jeremy 2026-10-06 (launch readiness): keep the banner below the Dynamic
## Island / notch. Same OS-API pattern as hud.gd _safe_insets(); falls back
## to a conservative top inset on portrait phones when the OS reports none.
func _safe_top() -> float:
	var vp := get_viewport()
	if vp == null:
		return 64.0
	var vsz := vp.get_visible_rect().size
	if not DisplayServer.is_touchscreen_available() and vsz.x >= 1024.0:
		return 12.0
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0.0 and safe.size.y > 0.0:
		# Jeremy 2026-10-08 (graphics-hourly): the OS rect is in WINDOW units
		# (CSS px on web), but this offset is applied in stretch-expanded
		# VIEWPORT units — convert via window_get_size(), which shares the
		# safe rect's coordinate space.
		var winsz := Vector2(DisplayServer.window_get_size())
		if winsz.y > 0.0:
			return maxf(12.0, safe.position.y * (vsz.y / winsz.y))
		return maxf(12.0, safe.position.y)
	# Fallback: portrait phones need real clearance for the Island.
	if vsz.y > vsz.x:
		return 64.0
	return 24.0


func _refit_safe() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.offset_top = _safe_top()


## Jeremy 2026-10-11: the first-time player prompt. "Are you a first-time
## player?" — YES runs the full guided tour; "I know how, let me play
## dammit" skips straight into the game.
func _build_offer() -> void:
	_offer = CenterContainer.new()
	_offer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_offer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offer.visible = false
	_layer.add_child(_offer)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = WOOD
	sb.border_color = WOOD_BORDER
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	_offer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := Label.new()
	t.text = "Are you a first-time player?"
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var b := Label.new()
	b.text = "New rulers get a guided tour of the realm. Veterans go straight to the throne."
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var yes := Button.new()
	yes.text = "Yes, teach me"
	yes.custom_minimum_size = Vector2(220, 64)
	yes.pressed.connect(start)
	row.add_child(yes)
	var no := Button.new()
	no.text = "I know how, let me play dammit"
	no.custom_minimum_size = Vector2(340, 64)
	no.pressed.connect(skip)
	row.add_child(no)


func _show_offer() -> void:
	_offer_shown = true
	_offer.visible = true


func _hide_offer() -> void:
	_offer_shown = false
	if _offer != null:
		_offer.visible = false


func _show_banner(v: bool) -> void:
	if _banner != null:
		_banner.visible = v


func _update_banner() -> void:
	if _banner == null:
		return
	var s: Dictionary = STEPS[_step]
	_title_lbl.text = String(s["title"])
	_body_lbl.text = String(s["body"])
	_step_lbl.text = "%d / %d" % [_step + 1, STEPS.size()]
	var action := String(s["action"])
	_action_btn.visible = action != ""
	_action_btn.text = action


func _on_action() -> void:
	# Button-driven steps advance explicitly; auto-check steps complete
	# via their game-state checks on tick.
	_advance()


func _tick_ring(_delta: float) -> void:
	if step_id() == "select":
		var p := _player_unit_pos()
		if p != Vector2.INF:
			_show_ring(p)
			return
	_hide_ring()


func _show_ring(world_pos: Vector2) -> void:
	if _ring.get_parent() == null and _world != null:
		_world.add_child(_ring)
	_ring.position = world_pos
	_ring.visible = true


func _hide_ring() -> void:
	if _ring != null:
		_ring.visible = false
