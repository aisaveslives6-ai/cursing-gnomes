class_name MainMenu
extends CanvasLayer
## Cursing Gnomes — main menu.
##
## Visual parity with the HTML title screen (Jeremy 2026-10-02: "use the
## original game and cross reference everything and recreate it exactly as
## it was"). All styling tokens below are copied from
## ~/workspace/build-staging/fix79/index.html:
##   screen bg  : radial-gradient(#3a2818 -> #1a120c)
##   logo       : assets/ui/cg_logo.png (extracted from HTML --logo-url)
##   tagline    : 0.78rem, letter-spacing 0.18em, #e8dcc8
##   build splash: #ffff54, 900, rotated -3deg, pulsing
##   update banner: purple gradient, 1.5px rgba(178,102,255,0.55) border,
##     16px radius, THE CLIFFS UPDATE / The mountains rise / 5 bullets /
##     "tap to continue"
##   menu cards : bg rgba(18,15,22,0.78), 1px rgba(201,162,39,0.45) border,
##     16px radius; primary cards get the gold gradient + #ffd54f border
##   footer     : "Autosaves while you play • save v5"
##   music hint : "tap anywhere for music" top-right, pulsing
## Faction screen copies #faction-row / .faction-card / .menu-btn exactly,
## plus the ACTIVE FACTIONS toggle box (buildFactionPicker61).
##
## Screens: title / faction / worlds / settings / credits / hearsay.
## Signals the host (main.gd) instead of managing scenes itself.


signal new_game_requested(faction: String, ruler_name: String)
signal continue_requested(slot: int)
signal sandbox_requested()
signal settings_changed(settings: Dictionary)
signal adventure_start_requested(faction: String, ruler_name: String,
	hero_name: String, hero_job: String, hero_gender: String)
## World-setup flow: faction screen -> Forge Your World -> world boots with
## the chosen type/size/shaping/seed. Connected by main.gd (see HOOKS).
signal world_game_requested(faction: String, ruler_name: String,
	wtype: String, size_key: String, opts: Dictionary, seed: int)


## Hero job picker follows the selected faction (HTML setupCharCreate
## parity): each faction offers its own unique jobs. SimAdventure owns the
## canonical per-faction table + labels; this just renders it.
func _hero_job_ids() -> Array[String]:
	return SimAdventure.hero_jobs_for(_selected_faction)


## Rebuild the job OptionButton for the currently selected faction.
## Keeps the first job selected (HTML: heroCreate.job = list[0][0]).
func _refresh_hero_jobs() -> void:
	if _hero_job == null or not is_instance_valid(_hero_job):
		return
	_hero_job.clear()
	for jid in _hero_job_ids():
		_hero_job.add_item(
			String(SimAdventure.HERO_JOB_NAMES.get(jid, jid.capitalize())))
	_hero_job.select(0)

const FACTION_INFO := {
	# "icon" is a short ASCII label — emoji render as tofu boxes in the
	# web-export font (Jeremy 2026-10-03), so UI chrome uses text only.
	"humans": {"icon": "HUM", "name": "HUMANS", "desc": "Balanced builders. Sturdy towns, steady armies, honest wages.", "atk": 3, "def": 3, "spd": 3},
	"ogres": {"icon": "OGR", "name": "OGRES", "desc": "Tanky brutes. Hit like a siege engine, shrug off the pain.", "atk": 5, "def": 4, "spd": 2},
	"elves": {"icon": "ELV", "name": "ELVES", "desc": "Nature's warlocks. Swift, arcane, and quietly lethal.", "atk": 4, "def": 2, "spd": 5},
	"gnomes": {"icon": "GNM", "name": "GNOMES", "desc": "Fast and foul. Cunning tricks and cursed contraptions.", "atk": 3, "def": 2, "spd": 4},
	"undead": {"icon": "UND", "name": "UNDEAD", "desc": "No farms, no births. Corpses and soul essence feed the horde.", "atk": 3, "def": 4, "spd": 2},
}
const FACTION_ORDER := ["humans", "ogres", "elves", "gnomes", "undead"]
# Faction badge colors, extracted from the HTML (data-race --fac vars).
const FACTION_COLORS := {
	"humans": Color(0.506, 0.831, 0.980),   # #81d4fa
	"ogres": Color(0.647, 0.839, 0.655),    # #a5d6a7
	"elves": Color(0.400, 0.733, 0.416),    # #66bb6a
	"gnomes": Color(0.882, 0.745, 0.906),   # #e1bee7
	"undead": Color(0.565, 0.643, 0.682),   # #90a4ae
}
# Initial-letter badges (Godot's web font lacks emoji — tofu boxes on iPhone).
const FACTION_INITIALS := {
	"humans": "H", "ogres": "O", "elves": "E", "gnomes": "G", "undead": "U",
}

const TITLE := "Cursing Gnomes"
const TAGLINE := "CITIES • HOUSING • JOBS • AUTONOMY"
const SPLASHES := [
	"100% Gnome-Free*",
	"*may contain gnomes",
	"Now with 20% more cursing!",
	"Thicc moose approved!",
	"Giant ass not included!",
	"As seen on itch.io!",
	"Built by Ethos!",
	"No microtransactions!",
	"No bullshit!",
	"Now with extra pixels!",
	"Chibi-tested, Jeremy-approved!",
	"Allison says hi!",
	"Claw was here!",
	"Ethos is co-owner now!",
	"Shenzhen or bust!",
	"Powered by spite!",
	"Contains trace amounts of whimsy!",
	"Now 93MB lighter!",
	"Runs on a potato!",
	"Certified gnome-free zone!",
	"Warning: may cause giggling!",
	"Undead need love too!",
	"Skeletons do the heavy lifting!",
	"Watch out for Count Bastard!",
	"Captain Funky Pants was here!",
	"Your advisor has opinions!",
	"16 per town, no more, no less!",
	"240 souls, one continent!",
	"Star forts not included!",
	"Rivers carve, roads follow!",
	"Waterfalls go brrr!",
	"Your gnomes are judging you!",
	"Ogres lift, elves judge!",
	"Gnomes curse, undead persist!",
	"Five factions, one grudge!",
]

static func random_splash() -> String:
	return SPLASHES[randi() % SPLASHES.size()]
const MENU_FOOT := "Autosaves while you play • save v5"

const UB_TITLE := "THE CLIFFS UPDATE"
const UB_SUB := "The mountains rise"
const UB_LINES := [
	"Climbable stepped mountains",
	"Visible cliff faces",
	"High-ground combat edge",
	"Slope-aware pathfinding",
	"Height shading on maps",
]

# HTML palette.
const C_GOLD := Color(0.788, 0.635, 0.153)        # #c9a227
const C_GOLD_BRIGHT := Color(1.0, 0.835, 0.310)   # #ffd54f
const C_GOLD_DARK := Color(0.545, 0.412, 0.078)   # #8b6914
const C_CREAM := Color(0.941, 0.902, 0.784)       # #f0e6c8
const C_CREAM_BRIGHT := Color(1.0, 0.953, 0.839)  # #fff3d6
const C_MUTED := Color(0.796, 0.725, 0.541)       # #cbb98a
const C_DIM := Color(0.627, 0.565, 0.439)         # #a09070
const C_FOOT := Color(0.553, 0.486, 0.361)        # #8d7c5c
const C_PURPLE := Color(0.851, 0.702, 1.0)        # #d9b3ff
const C_PURPLE_DIM := Color(0.702, 0.616, 0.859)  # #b39ddb
const C_UB_LINE := Color(0.910, 0.875, 0.961)     # #e8dff5
const C_TAGLINE := Color(0.910, 0.863, 0.784)     # #e8dcc8
const C_SPLASH := Color(1.0, 1.0, 0.329)          # #ffff54
const C_HINT_GOLD := Color(0.788, 0.659, 0.416)   # #c9a86a
const C_MUSIC_HINT := Color(0.796, 0.722, 0.498)  # #cbb87f
const C_CARD_BG := Color(0.071, 0.059, 0.086, 0.78)
const C_CARD_BORDER := Color(0.788, 0.635, 0.153, 0.45)
const C_PRIMARY_BG := Color(0.235, 0.165, 0.094, 0.92)  # ~(74,52,32)->(38,26,16)
const C_BANNER_BG := Color(0.082, 0.051, 0.102, 0.92)   # ~(30,18,38)->(12,8,18)
const C_BANNER_BORDER := Color(0.698, 0.4, 1.0, 0.55)
const C_FCARD_BG := Color(0.129, 0.086, 0.055)    # ~(42,28,18)->(26,18,12)
const C_BTN_BG := Color(0.239, 0.165, 0.098)      # ~(74,52,32)->(46,32,20)
const C_PANEL_BG := Color(0.078, 0.063, 0.047, 0.85)
const C_PANEL_BORDER := Color(0.361, 0.263, 0.157)  # #5c4328
const C_INPUT_BG := Color(0.102, 0.078, 0.063)    # #1a1410
const C_CHEV := Color(0.545, 0.412, 0.078)        # #8b6914
const C_ICON_BG := Color(1.0, 0.835, 0.310, 0.12)
const C_ICON_BORDER := Color(0.788, 0.635, 0.153, 0.4)
const C_TIP := Color(0.820, 0.749, 0.553)          # muted gold for the tips line
## Jeremy 2026-10-07 (wake routine): rotating main-menu tips. Gameplay hints
## plus credits for shipped community ideas (standing rule: credit the author
## in the Gazette or a loading-screen tip where natural). ASCII ONLY — the
## menu glyph-walk smoke test trips on anything above U+2500 (iPhone tofu).
const MENU_TIPS: Array[String] = [
	"TIP: Tap the crown button to snap the camera back to your capitol. (Jeremy's idea)",
	"TIP: Beware the Stinky Gizmundo. It smells worse than it fights. (Jeremy's idea)",
	"TIP: Deny a build petition and your advisers will not ask again for 3 days.",
	"TIP: Open the Realm menu to slow time to 0.25x turtle speed and savor the battle.",
	"TIP: Losing a war? Your War Advisor pleads in Messenger. Tap Accept or Deny.",
	"TIP: Talk to your cabinet in Messenger. Try: build 3 farms.",
	"TIP: Monasteries are the true prize of war. Hold one and the land is yours.",
	"TIP: Idle fighters spend their own coins on weapon upgrades at the smith.",
	"TIP: Starving? Rival factions yank workers onto berry duty. Your adviser only warns you.",
	"TIP: The Gazette Chronicle keeps every story. The toast is just the headline.",
	"TIP: Tap outside any popup to close it.",
	"TIP: Peace is signed in the diplomacy tab. The tabs are big now. No accidental wars.",
	"TIP: A doom prophet preaching in your town? March a soldier at him. He will flee.",
	"TIP: A gig gnome circling your town and skimming delivery fees? March a soldier at him. He will mark your order 'delivered' and speed off.",
	"TIP: Firefighters ride real trucks now — they mount up at the station lot, drive to the fire, and drive back.",
	"TIP: Roads are built in stages: surveyed, graded, paved. Traffic reroutes around the work zone.",
	"TIP: Buildings rise in stages — foundation, frame, walls, roof. Battle damage walks the ladder back down.",
	"TIP: Your AI rivals pave real road networks: town hall to farms, mines, shops, and town to town.",
	"TIP: Citizens buy their own wagons at the dealership. Soldiers draw theirs from the motor pool.",
	"TIP: Nothing builds on water — bridges excepted. A house in a lake is a bug, not a feature.",
	"TIP: Tap the map to command your ENTIRE military at once. Attack-move chews through whatever is nearest.",
]
## Loading-screen tips (Jeremy 2026-10-08): the rotating title-screen tips
## were removed for the SC1-style clean menu — no clutter on the title.
## Jeremy then asked "Tips?" — so ONE thin overlay line is back on the
## title (see _title_tip_label), and the full rotation still serves
## loading screens via random_tip().
static func random_tip() -> String:
	if MENU_TIPS.is_empty():
		return ""
	return MENU_TIPS[randi() % MENU_TIPS.size()]

var _screen := "title"
var _root: Control
## Active world-setup screen (CanvasLayer added directly to self, NOT _root).
## Tracked so screen changes can free it — otherwise it lingers over/under
## other screens (Jeremy 2026-10-02: world gen "bolts itself on top of the
## factions selection screen").
var _worldsetup: WorldSetupScreen = null
var _selected_faction := "gnomes"
var _active_factions: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
var _ruler_input: RulerNameField
## Ruler name cache (Jeremy 2026-10-03): the custom keyboard writes the
## field directly, and the field is freed on screen rebuilds — the cache
## keeps the verbatim name across the faction -> worldsetup transition.
var _ruler_name_cache: String = ""
## Custom in-game keyboard overlay (child of the CanvasLayer, not _root).
var _ruler_kb: RulerKeyboard = null
var _hero_input: LineEdit
var _hero_job: OptionButton
## Hero gender (adventure mode): "male" | "female". HTML defaults male
## when unset (hero.gender = heroCreate.gender || 'male').
var _hero_gender := "male"
var _hero_gender_btns: Array[Button] = []
var _adventure_setup := false
var _continue_btn: Button
var _settings := {}
var _tweens: Array = []
## Jeremy 2026-10-08 (wake rapid-iteration): his "Tips?" — the SC1 clean
## title dropped the rotating tips and he asked for them back. ONE thin
## overlay line at the very bottom under the buttons: floats above the
## background, reserves NO layout space (2026-10-07 lesson — reserving
## space clipped the third button on iPhone). Rotates in _process.
var _title_tip_label: Label = null
var _title_tip_timer := 0.0
var _title_tip_idx := 0
const TITLE_TIP_ROTATE_SECS := 8.0
var _banner: PanelContainer
## Update-banner overlay wrapper (dim + centered panel). Tracked so
## _dismiss_banner can free the whole overlay, not just the panel.
var _banner_overlay: Control
## _tweens watermark: tweens appended while the banner builds belong to
## the banner — _dismiss_banner kills only those (never splash/hint).
var _banner_tw_mark := 0
## Title logo (SC1-style): slow shimmer applied in _tick_menu_atmosphere.
var _logo_rect: TextureRect
var _race_count_lbl: Label
## Jeremy 2026-10-06 (launch readiness): one-shot notice shown on the title
## screen (e.g. "that save couldn't be loaded"). Set by flash_notice(),
## rendered once by _show_title(), then cleared.
var _pending_notice := ""
# Canvas units per CSS px. On web the Godot viewport (e.g. 1278 units wide in
# the itch.io iframe) is much wider than the CSS viewport (390px), so fixed
# pixel sizes render tiny. Scaling every menu size by _ui_scale makes the menu
# match the HTML's CSS-px layout (min(94vw,430px) column, rem fonts).
# Jeremy 2026-10-02: "Holy fuck why is it so tiny".
var _ui_scale := 1.0
# Width-only scale (units per CSS px), never boosted. Column width and other
# horizontal sizes use this so boosted fonts can't overflow the column.
var _ui_scale_w := 1.0
# Vertical fill multiplier. Measured per screen: if the built column is much
# shorter than the viewport, every font/height/separation scales up so the
# menu fills the screen instead of floating in dead space.
# Jeremy 2026-10-02: "Menu should scale with screen".
var _fill_boost := 1.0
# True while the fill-refit rebuild is running (prevents loops/resets).
var _refitting := false
# Current screen column; stale deferred refits (from a previous screen) bail.
var _refit_vbox: VBoxContainer
# Test hook: when > 0, _new_screen uses this instead of the live computation.
var _ui_scale_forced := 0.0
# Jeremy 2026-10-04: orientation/device detection for responsive menu scaling.
# "portrait" = tall phone, "landscape" = wide phone, "desktop" = large
# non-touch viewport. Detected per screen build from the live viewport.
var _orientation := "portrait"
## Jeremy 2026-10-06 (launch readiness): aspect bucket for PC layouts.
## "widescreen" (16:9 and wider, ratio >= 1.5) vs "standard" (~4:3).
## Orthogonal to _orientation: phones are portrait/landscape, desktops get
## a desktop orientation + one of these aspect buckets.
var _aspect := "widescreen"
var _is_desktop := false
# Scrolling menu background (Jeremy 2026-10-02: "Scrolling beautiful
# landscape in the background"). One shared layer built in _new_screen for
# every screen; panned in _process. Ping-pong pan — seamless, no jump cut.
var _bg_tex: Texture2D
var _bg_rect: TextureRect
var _bg_fit_vp := Vector2.ZERO
var _bg_pan := 0.0
var _bg_dir := 1.0
## Jeremy 2026-10-08: which of the 5 backgrounds is active (0=forest,
## 1=desert, 2=snow, 3=coast, 4=terraced) — atmosphere themes particles
## per scene (fireflies/embers/snow/mist/leaves) so the bg feels alive.
var _bg_index := 0
const BG_PAN_SPEED := 14.0  # canvas units/sec before UI scale (slow drift)
## Ken Burns zoom: slow breathe 1.0 -> 1.07 -> 1.0 over ~50s, layered
## with the horizontal pan so the menu bg feels like video, not wallpaper.
const BG_ZOOM_PERIOD := 50.0
const BG_ZOOM_AMOUNT := 0.07
# Menu atmosphere (graphics-hourly 2026-10-03): living layers over the
# landscape — HTML's animated scenic backdrop had twinkling stars, a moon
# halo, chimney smoke and fireflies; ours is a golden-day scene, so it gets
# god rays, drifting pollen motes and distant birds instead. Purely visual,
# additive/soft, cheap enough for phones. Built in _build_menu_atmosphere
# (between bg and dim overlay), animated in _tick_menu_atmosphere.
var _bg_rays: Array = []        # TextureRect light shafts (shared ADD material)
var _bg_ray_material: CanvasItemMaterial
var _bg_ray_phases: Array = []  # per-ray pulse phases
var _bg_pollen: GPUParticles2D  # golden dust motes, tier-scaled amount
## Jeremy 2026-10-08: scene-themed particle layer (fireflies/embers/snow/
## mist/leaves per background) — the "living video" menu background.
var _bg_theme_fx: GPUParticles2D
var _bg_bird_layer: Node2D       # distant birds
var _bg_birds: Array = []        # [Node2D, Polygon2D, speed, phase]
var _bg_time := 0.0              # animation clock for rays/birds
const BG_RAY_COUNT := 4
const BG_BIRD_COUNT := 5
const BG_POLLEN_BASE := 72       # scaled by tier particle_mul (HTML parity)
# Faction rows in the ACTIVE FACTIONS box (fid -> [row Button, box PanelContainer, check Label]).
var _faction_rows := {}
## 3D trading-card carousel state.
var _carousel3d_cards: Array = []
var _carousel3d_view: Control
var _carousel3d_angle := 0.0
var _carousel3d_target := 0.0
var _carousel3d_dragging := false
var _carousel3d_press_x := 0.0
var _carousel3d_press_y := 0.0
var _carousel3d_last_x := 0.0
var _carousel3d_moved := false



## Custom in-game keyboard for the ruler name (Jeremy 2026-10-03:
## "Why not build a built in keyboard?"). Tapping the field opens a native
## Godot QWERTY keyboard instead of the OS virtual keyboard, which
## permanently sidesteps iOS Safari's focus-zoom and the hidden-input
## backspace desync (upstream godot#72969 class of bug). The name is stored
## VERBATIM — never trimmed, never case-mangled (Jeremy's law).
class RulerNameField:
	extends PanelContainer

	signal tapped
	signal text_changed(new_text: String)

	const F_BG := Color(0.102, 0.078, 0.063)      # C_INPUT_BG #1a1410
	const F_GOLD := Color(0.788, 0.635, 0.153)    # C_GOLD #c9a227
	const F_CREAM := Color(0.941, 0.902, 0.784)   # C_CREAM #f0e6c8
	const F_DIM := Color(0.627, 0.565, 0.439)     # C_DIM #a09070

	var text: String = "":
		set(v):
			text = v
			text_changed.emit(v)
			_refresh()
	var placeholder_text: String = "":
		set(v):
			placeholder_text = v
			_refresh()
	var max_length: int = 24
	var _label: Label = null
	var _font_size: int = 20


	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := StyleBoxFlat.new()
		sb.bg_color = F_BG
		sb.border_color = F_GOLD
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		add_theme_stylebox_override("panel", sb)
		_label = Label.new()
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", _font_size)
		_label.add_theme_color_override("font_color", F_CREAM)
		_label.clip_text = true
		add_child(_label)
		_refresh()

	func set_font_size(px: int) -> void:
		_font_size = px
		if _label != null:
			_label.add_theme_font_size_override("font_size", px)

	func _refresh() -> void:
		if _label == null:
			return
		if text == "":
			_label.text = placeholder_text
			_label.add_theme_color_override("font_color", F_DIM)
		else:
			_label.text = text
			_label.add_theme_color_override("font_color", F_CREAM)

	func _gui_input(event: InputEvent) -> void:
		var tapped_now := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			tapped_now = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			tapped_now = (event as InputEventScreenTouch).pressed
		if tapped_now:
			accept_event()
			tapped.emit()


## Bottom-sheet QWERTY keyboard for RulerNameField. Pure Godot controls —
## identical on iOS, Android and PC. Backspace is our own logic, so it
## cannot desync; no HTML input exists, so iOS cannot focus-zoom.
## UI chrome uses ASCII labels only (no glyphs — iPhone tofu rule).
class RulerKeyboard:
	extends Control

	const K_BG := Color(0.078, 0.059, 0.047)
	const K_KEY := Color(0.165, 0.125, 0.094)
	const K_KEY_FN := Color(0.208, 0.157, 0.110)
	const K_GOLD := Color(0.788, 0.635, 0.153)
	const K_CREAM := Color(0.941, 0.902, 0.784)
	const K_DONE_BG := Color(0.788, 0.635, 0.153)
	const K_DONE_FG := Color(0.102, 0.078, 0.063)

	var _field: RulerNameField = null
	var _scale := 1.0
	var _shift := false
	var _caps := false
	var _display: Label = null
	var _count_lbl: Label = null
	var _blink := 0.0
	var _letter_btns: Dictionary = {}
	var _shift_btn: Button = null
	var _bs_timer: Timer = null

	func _s(v: float) -> float:
		return v * _scale

	func _si(v: int) -> int:
		return maxi(1, int(round(float(v) * _scale)))

	func open_for(field: RulerNameField, ui_scale: float) -> void:
		_field = field
		_scale = ui_scale
		_shift = false
		_caps = false
		if _bs_timer == null:
			_bs_timer = Timer.new()
			_bs_timer.one_shot = true
			_bs_timer.timeout.connect(_on_bs_tick)
			add_child(_bs_timer)
		_rebuild()
		visible = true

	func close() -> void:
		visible = false
		if _bs_timer != null:
			_bs_timer.stop()
		_field = null

	func _process(delta: float) -> void:
		if not visible or _display == null:
			return
		_blink += delta
		var cur := "|" if fmod(_blink, 1.0) < 0.55 else " "
		var t := _field.text if _field != null else ""
		_display.text = t + cur
		# Live char count: key inserts silently stop at max_length (HTML
		# parity: fix79 maxlength 24) — the counter shows why. ASCII only.
		if is_instance_valid(_count_lbl):
			var cap: int = _field.max_length if _field != null else 24
			_count_lbl.text = "%d/%d" % [t.length(), cap]

	func _rebuild() -> void:
		for c in get_children():
			if c != _bs_timer:
				c.queue_free()
		_letter_btns.clear()
		# Jeremy 2026-10-03: set anchors AND offsets explicitly. The keyboard is
		# already in the tree (added by _open_ruler_keyboard), and in Godot 4.7
		# set_anchors_preset() "keeps" the current zero size via negative
		# offsets whether keep_offsets is true OR false (verified) — the whole
		# keyboard rendered 0x0 and taps showed nothing. Explicit zeroes make
		# it truly fill the screen.
		anchor_left = 0.0
		anchor_top = 0.0
		anchor_right = 1.0
		anchor_bottom = 1.0
		offset_left = 0.0
		offset_top = 0.0
		offset_right = 0.0
		offset_bottom = 0.0
		mouse_filter = Control.MOUSE_FILTER_STOP
		# Dim: tap anywhere outside the keys to dismiss (text is saved live).
		var dim := ColorRect.new()
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.color = Color(0, 0, 0, 0.62)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		dim.gui_input.connect(func(event: InputEvent) -> void:
			var dismiss := false
			if event is InputEventMouseButton:
				var mb := event as InputEventMouseButton
				dismiss = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
			elif event is InputEventScreenTouch:
				dismiss = (event as InputEventScreenTouch).pressed
			if dismiss:
				close()
		)
		add_child(dim)
		# Bottom sheet panel.
		var panel := PanelContainer.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = K_BG
		psb.border_color = K_GOLD
		psb.border_width_top = _si(2)
		psb.content_margin_left = _s(10)
		psb.content_margin_right = _s(10)
		psb.content_margin_top = _s(10)
		psb.content_margin_bottom = _s(14)
		panel.add_theme_stylebox_override("panel", psb)
		panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		var key_h := _s(62)
		var disp_h := _s(54)
		var total_h := disp_h + key_h * 4.0 + _s(8) * 5.0 + _s(24)
		panel.offset_top = -total_h
		panel.offset_bottom = 0
		add_child(panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", _si(8))
		panel.add_child(v)
		_display = Label.new()
		_display.custom_minimum_size = Vector2(0, disp_h)
		_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_display.add_theme_font_size_override("font_size", _si(24))
		_display.add_theme_color_override("font_color", K_CREAM)
		_display.clip_text = true
		# Counter row: typing area + live "N/24" count at the right edge.
		var disp_row := HBoxContainer.new()
		disp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disp_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		disp_row.add_theme_constant_override("separation", _si(8))
		disp_row.add_child(_display)
		_count_lbl = Label.new()
		_count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_count_lbl.add_theme_font_size_override("font_size", _si(13))
		_count_lbl.add_theme_color_override("font_color", Color(0.627, 0.565, 0.439))
		_count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _field != null:
			_count_lbl.text = "%d/%d" % [_field.text.length(), _field.max_length]
		disp_row.add_child(_count_lbl)
		v.add_child(disp_row)
		_blink = 0.0
		v.add_child(_key_row("qwertyuiop"))
		v.add_child(_key_row("asdfghjkl"))
		v.add_child(_fn_row())
		v.add_child(_bottom_row())

	func _make_key(label_text: String, bg: Color, fg: Color, wide := 1.5) -> Button:
		var b := Button.new()
		b.text = label_text
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, _s(62))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = wide
		b.add_theme_font_size_override("font_size", _si(20))
		b.add_theme_color_override("font_color", fg)
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = K_GOLD
		sb.set_border_width_all(_si(1))
		sb.set_corner_radius_all(_si(8))
		b.add_theme_stylebox_override("normal", sb)
		var sb_h := sb.duplicate() as StyleBoxFlat
		sb_h.bg_color = bg.lightened(0.12)
		b.add_theme_stylebox_override("hover", sb_h)
		var sb_p := sb.duplicate() as StyleBoxFlat
		sb_p.bg_color = bg.darkened(0.15)
		b.add_theme_stylebox_override("pressed", sb_p)
		return b

	func _key_row(letters: String) -> HBoxContainer:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", _si(6))
		for i in letters.length():
			var ch := letters[i]
			var b := _make_key(ch.to_upper(), K_KEY, K_CREAM)
			_letter_btns[ch] = b
			b.pressed.connect(_insert_letter.bind(ch))
			row.add_child(b)
		return row

	func _fn_row() -> HBoxContainer:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", _si(6))
		_shift_btn = _make_key("SHIFT", K_KEY_FN, K_CREAM, 2.2)
		_shift_btn.pressed.connect(_toggle_shift)
		row.add_child(_shift_btn)
		for i in "zxcvbnm".length():
			var ch := "zxcvbnm"[i]
			var b := _make_key(ch.to_upper(), K_KEY, K_CREAM)
			_letter_btns[ch] = b
			b.pressed.connect(_insert_letter.bind(ch))
			row.add_child(b)
		var bs := _make_key("BKSP", K_KEY_FN, K_CREAM, 2.2)
		bs.button_down.connect(_on_bs_down)
		bs.button_up.connect(_on_bs_up)
		row.add_child(bs)
		_refresh_shift_btn()
		return row

	func _bottom_row() -> HBoxContainer:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", _si(6))
		var sp := _make_key("SPACE", K_KEY, K_CREAM, 6.0)
		sp.pressed.connect(func() -> void: _insert_raw(" "))
		row.add_child(sp)
		var ap := _make_key("'", K_KEY, K_CREAM, 1.5)
		ap.pressed.connect(func() -> void: _insert_raw("'"))
		row.add_child(ap)
		var done := _make_key("DONE", K_DONE_BG, K_DONE_FG, 2.6)
		done.pressed.connect(close)
		row.add_child(done)
		return row

	func _insert_letter(ch: String) -> void:
		var c := ch.to_upper() if (_shift or _caps) else ch.to_lower()
		_insert_raw(c)
		if _shift and not _caps:
			_shift = false
			_refresh_key_labels()
			_refresh_shift_btn()

	func _insert_raw(c: String) -> void:
		if _field == null:
			return
		if _field.text.length() >= _field.max_length:
			return
		_field.text = _field.text + c

	func _backspace() -> void:
		if _field == null:
			return
		var t := _field.text
		if t.length() > 0:
			_field.text = t.substr(0, t.length() - 1)

	func _toggle_shift() -> void:
		if _caps:
			_caps = false
			_shift = false
		elif _shift:
			_shift = false
			_caps = true
		else:
			_shift = true
		_refresh_key_labels()
		_refresh_shift_btn()

	func _refresh_key_labels() -> void:
		var upper := _shift or _caps
		for ch in _letter_btns:
			var b := _letter_btns[ch] as Button
			if b != null:
				b.text = (ch as String).to_upper() if upper else (ch as String).to_lower()

	func _refresh_shift_btn() -> void:
		if _shift_btn == null:
			return
		_shift_btn.text = "CAPS" if _caps else "SHIFT"
		_shift_btn.modulate = Color(1.0, 0.85, 0.45) if (_shift or _caps) else Color.WHITE

	func _on_bs_down() -> void:
		_backspace()
		if _bs_timer != null:
			_bs_timer.start(0.45)

	func _on_bs_up() -> void:
		if _bs_timer != null:
			_bs_timer.stop()

	func _on_bs_tick() -> void:
		_backspace()
		if _bs_timer != null and visible:
			_bs_timer.start(0.07)


func _ready() -> void:
	_load_settings()
	# Scrolling menu landscape (shared across all screens). Headless runs
	# have no import cache, so this may be null — _new_screen falls back
	# to the warm radial gradient in that case.
	# Jeremy 2026-10-04: 5 rotating menu backgrounds — misty forest valley,
	# desert canyon at sunset, snowy mountain pass, coastal cliffside, plus
	# the original terraced valley. Picked once per game load.
	var _bg_paths := [
		"res://assets/ui/menu_landscape_bg.webp",
		"res://assets/ui/menu_landscape_bg2.webp",
		"res://assets/ui/menu_landscape_bg3.webp",
		"res://assets/ui/menu_landscape_bg4.webp",
		"res://assets/ui/menu_landscape_bg5.webp",
	]
	# Jeremy 2026-10-08: remember WHICH bg is active so the atmosphere can
	# theme its particles (fireflies/embers/snow/mist/leaves per scene).
	_bg_index = randi() % _bg_paths.size()
	_bg_tex = load(_bg_paths[_bg_index]) as Texture2D
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	set_process(true)
	_show_title()


# ---------------------------------------------------------------- settings

func _settings_path() -> String:
	return "user://settings.json"


func _load_settings() -> void:
	_settings = {
		"ai_aggression": "normal",  # low | normal | high (HTML parity; stored)
		"graphics": "auto",
		"ground_detail": "auto",
		"life_decisions": true,
		"tree_sway": true,
		"music": true,
		"music_volume": 80,
		"sfx_volume": 80,  # 2026-10-06 launch readiness: SFX had no volume
		# control at all (platform audit's thinnest settings gap) — 0 mutes.
		"share_diagnostics": false,  # opt-in; HTML consent-gated telemetry
		"diagnostics_id": "",  # anonymous UUID, generated on opt-in
		"debug_overlay": false,  # OFF by default — Jeremy 2026-10-02
		"autosave": true,  # periodic autosave — web can't catch tab close
		"autosave_minutes": 5,
		# Jeremy 2026-10-07: game-speed preference — 0.5x is his thermal
		# slowdown ask (2026-10-08: 0.25x turtle added, he asked to slow
		# in-game time FURTHER; 2026-10-09: 0.125x deep turtle, further
		# again); restored by the HUD on every world entry.
		"game_speed": 1.0,
	}
	if FileAccess.file_exists(_settings_path()):
		var f := FileAccess.open(_settings_path(), FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				for k in parsed.keys():
					_settings[k] = parsed[k]
	get_tree().set_meta("cg_debug_overlay", bool(_settings.get("debug_overlay", false)))


func _save_settings() -> void:
	# Merge over the on-disk file: other writers (Diagnostics' anonymous ID)
	# must not be clobbered by this in-memory dict.
	var disk := GraphicsTiers.read_user_settings()
	for k in _settings.keys():
		disk[k] = _settings[k]
	_settings = disk
	var f := FileAccess.open(_settings_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_settings))
		f.close()
	get_tree().set_meta("cg_debug_overlay", bool(_settings.get("debug_overlay", false)))
	settings_changed.emit(_settings.duplicate())


func get_setting(key: String, fallback = null):
	return _settings.get(key, fallback)


## Full settings snapshot for systems outside the menu (main.gd pushes this
## into GameState.settings so the sim can consume player preferences).
func get_settings_snapshot() -> Dictionary:
	return _settings.duplicate()


## Update one in-memory setting without saving (for values another system
## already persisted, e.g. the diagnostics anonymous ID).
func set_setting(key: String, value) -> void:
	_settings[key] = value


# ------------------------------------------------------------------ chrome
## Screen scaffold: radial-gradient bg + scrollable centered column.
## Returns the VBox to fill. Matches .screen / .menu-content.

## Clear the current screen: kill tweens, free _root children, and free any
## lingering world-setup CanvasLayer. Called by _new_screen and _show_worldsetup.
func _clear_screen() -> void:
	_close_ruler_keyboard()
	for t in _tweens:
		if is_instance_valid(t):
			(t as Tween).kill()
	_tweens.clear()
	_breathe.clear()
	for c in _root.get_children():
		c.queue_free()
	if _worldsetup != null and is_instance_valid(_worldsetup):
		_worldsetup.queue_free()
	_worldsetup = null
	_banner = null
	_banner_overlay = null
	_logo_rect = null


## iPhone safe-area insets as Vector4(top, bottom, left, right) in canvas
## units. Fixed conservative values — no viewport math (Jeremy 2026-10-04).
## Portrait: Dynamic Island top, home indicator bottom. Landscape: Island
## on the side, home indicator bottom. Desktop: no insets.
func _safe_insets() -> Vector4:
	# Jeremy 2026-10-04: use the REAL OS-reported safe area, not hardcoded guesses.
	if _is_desktop:
		return Vector4.ZERO
	var vp := get_viewport()
	if vp != null:
		var vsz := vp.get_visible_rect().size
		var safe := DisplayServer.get_display_safe_area()
		if safe.size.x > 0 and safe.size.y > 0:
			# Jeremy 2026-10-08 (graphics-hourly): the OS rect is in WINDOW
			# units (CSS px on web), but vsz is in stretch-expanded VIEWPORT
			# units — mixing them produced garbage insets (title tip pinned
			# mid-screen: bottom = 1794 - 701). Convert the rect to viewport
			# units first via window_get_size(), which shares the safe rect's
			# coordinate space.
			var winsz := Vector2(DisplayServer.window_get_size())
			if winsz.x > 0.0 and winsz.y > 0.0:
				var k := vsz / winsz
				var top := safe.position.y * k.y
				var left := safe.position.x * k.x
				var bottom := vsz.y - (safe.position.y + safe.size.y) * k.y
				var right := vsz.x - (safe.position.x + safe.size.x) * k.x
				return Vector4(maxf(top, 0.0), maxf(bottom, 0.0), maxf(left, 0.0), maxf(right, 0.0))
	if _orientation == "landscape":
		return Vector4(20.0, 60.0, 120.0, 120.0)
	# Portrait (default).
	return Vector4(220.0, 120.0, 20.0, 20.0)

## Title-screen tips: Jeremy 2026-10-08 asked "Tips?" after the SC1 clean
## menu dropped them — ONE thin overlay line is back (see _show_title /
## _title_tip_label). The MENU_TIPS lines also serve loading screens
## via random_tip().


func _new_screen(col_sep := 10) -> VBoxContainer:
	_clear_screen()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_detect_orientation(vp)
	# Jeremy 2026-10-04: fixed 2.5x for iPhone 17. No viewport math.
	_ui_scale_w = 2.5
	_ui_scale = 2.5
	# Background: scrolling fantasy landscape (shared across all screens),
	# dimmed so cards and text stay readable on top. Pan advances in
	# _process with a ping-pong — a seamless loop with no jump cut.
	var bg := TextureRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _bg_tex != null:
		bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.texture = _bg_tex
		_root.add_child(bg)
		_bg_rect = bg
		_fit_menu_bg()
	else:
		# Headless fallback (no import cache): warm radial gradient.
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		var grad := GradientTexture2D.new()
		grad.fill = GradientTexture2D.FILL_RADIAL
		grad.fill_from = Vector2(0.5, 0.42)
		grad.fill_to = Vector2(1.0, 0.42)
		var g := Gradient.new()
		g.set_color(0, Color(0.227, 0.157, 0.094))
		g.set_color(1, Color(0.102, 0.071, 0.047))
		grad.gradient = g
		grad.width = 256
		grad.height = 256
		bg.texture = grad
		_root.add_child(bg)
		_bg_rect = null
	# Menu atmosphere: god rays + pollen motes + distant birds between the
	# landscape and the dim overlay, so they read as part of the scene.
	_build_menu_atmosphere()
	_fit_menu_atmosphere()
	# Dim overlay: keeps the faction cards and text readable over the art.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.02, 0.012, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Jeremy 2026-10-04: iPhone safe areas — Dynamic Island (top), home
	# indicator (bottom), rounded corners. Inset the scroll area on mobile
	# so no menu content hides under the Island or home bar. Desktop: none.
	var insets := _safe_insets()
	scroll.offset_top = insets.x
	# Jeremy 2026-10-07: tips band is a true overlay at the bottom — it does
	# NOT reserve layout space. The menu was designed to fill the screen;
	# reserving 84px clipped the third button on iPhone (Jeremy 2026-10-07:
	# "Title screen is busted"). Tips float above the dim background.
	scroll.offset_bottom = -insets.y
	scroll.offset_left = insets.z
	scroll.offset_right = -insets.w
	_root.add_child(scroll)
	# Outer box: at least viewport-sized (short menus center vertically),
	# grows taller when content overflows (ScrollContainer then scrolls).
	# Replaces CenterContainer, which does NOT expand for taller children —
	# content overflowed with no scroll (Jeremy 2026-10-04: "menu is bigger
	# than the screen and has no scroll").
	var outer := VBoxContainer.new()
	outer.custom_minimum_size = vp
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(outer)
	var v := VBoxContainer.new()
	# HTML parity: .menu-content { width: min(94vw, 430px) }.
	# Design pixels — Godot's stretch mode handles the rest.
	v.custom_minimum_size = Vector2(minf(vp.x * 0.94, 860.0), 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", _pxi(col_sep))
	outer.add_child(v)
	# The inner content column other systems (and tests) address directly.
	_refit_vbox = v
	# Jeremy 2026-10-04 (polish): subtle fade-in on screen change — the
	# menu feels like it transitions instead of hard-cutting.
	v.modulate.a = 0.0
	var ftw := v.create_tween()
	ftw.tween_property(v, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_LINEAR)
	return v


## Size the landscape bg to cover the viewport height; the pan offset is
## applied in _process. Called per screen (fresh viewport size each time).
func _fit_menu_bg() -> void:
	if _bg_rect == null or not is_instance_valid(_bg_rect) or _bg_tex == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var th := float(_bg_tex.get_height())
	if th <= 0.0:
		return
	var sc := vp.y / th
	_bg_rect.size = Vector2(float(_bg_tex.get_width()) * sc, vp.y)
	_bg_rect.position = Vector2(-_bg_pan, 0)
	# Ken Burns pivot: zoom breathes around the frame center.
	_bg_rect.pivot_offset = _bg_rect.size * 0.5
	_bg_fit_vp = vp


## Shared additive material for god rays and pollen (built once per screen).
func _bg_add_material() -> CanvasItemMaterial:
	if _bg_ray_material == null or not is_instance_valid(_bg_ray_material):
		_bg_ray_material = CanvasItemMaterial.new()
		_bg_ray_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _bg_ray_material


## Soft round dot for pollen motes, generated procedurally (no asset needed).
static var _pollen_tex: Texture2D
static func _pollen_dot_texture() -> Texture2D:
	if _pollen_tex != null:
		return _pollen_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a *= a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_pollen_tex = ImageTexture.create_from_image(img)
	return _pollen_tex


## Build the living menu layers: diagonal god rays slanting from the sun's
## direction, golden pollen motes drifting up through the light, and distant
## birds crossing the sky. Children of _root (below the dim overlay); pure
## eye candy — no sim state, no input.
func _build_menu_atmosphere() -> void:
	_bg_rays.clear()
	_bg_ray_phases.clear()
	_bg_birds.clear()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# --- God rays: soft diagonal shafts, additive so they glow. ---
	var ray_grad := GradientTexture2D.new()
	ray_grad.fill = GradientTexture2D.FILL_LINEAR
	ray_grad.fill_from = Vector2(0.5, 0.0)
	ray_grad.fill_to = Vector2(0.5, 1.0)
	var rg := Gradient.new()
	rg.set_color(0, Color(1.0, 0.96, 0.82, 0.55))
	rg.set_color(1, Color(1.0, 0.96, 0.82, 0.0))
	ray_grad.gradient = rg
	ray_grad.width = 64
	ray_grad.height = 256
	for i in range(BG_RAY_COUNT):
		var ray := TextureRect.new()
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ray.stretch_mode = TextureRect.STRETCH_SCALE
		ray.texture = ray_grad
		ray.material = _bg_add_material()
		ray.modulate.a = 0.55
		_root.add_child(ray)
		_bg_rays.append(ray)
		_bg_ray_phases.append(TAU * float(i) / float(BG_RAY_COUNT))
	# --- Pollen motes: golden dust drifting upward in the sunlight. ---
	var tier := GraphicsTiers.resolve(String(_settings.get("graphics", "auto")))
	var mul: float = float(GraphicsTiers.knobs(tier).get("particle_mul", 0.5))
	var pollen := GPUParticles2D.new()
	pollen.amount = maxi(8, int(float(BG_POLLEN_BASE) * mul))
	pollen.lifetime = 8.0
	pollen.preprocess = 8.0
	pollen.texture = _pollen_dot_texture()
	pollen.material = _bg_add_material()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(vp.x * 0.5, vp.y * 0.5, 1.0)
	pm.direction = Vector3(0.35, -1.0, 0.0)
	pm.spread = 20.0
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3(0.0, -2.0, 0.0)
	pm.damping_min = 0.0
	pm.damping_max = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.92, 0.70, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.92, 0.70, 0.85))
	ramp.add_point(0.85, Color(1.0, 0.92, 0.70, 0.85))
	ramp.set_color(1, Color(1.0, 0.92, 0.70, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	pollen.process_material = pm
	pollen.position = vp * 0.5
	_root.add_child(pollen)
	_bg_pollen = pollen
	# --- Scene-themed particles (Jeremy 2026-10-08): a second drifting
	# layer themed to the active background so the menu feels like video:
	# forest=fireflies, desert=embers, snow=snowfall, coast=sea mist,
	# terraced=drifting leaves. Built from the same soft-dot texture.
	_build_theme_particles(vp, mul)
	# --- Distant birds: slow dark chevrons crossing the sky. ---
	var layer := Node2D.new()
	_root.add_child(layer)
	_bg_bird_layer = layer
	var chev := PackedVector2Array([
		Vector2(-18, 3), Vector2(-7, -6), Vector2(0, -2), Vector2(7, -6),
		Vector2(18, 3), Vector2(18, 6), Vector2(7, -3), Vector2(0, 1),
		Vector2(-7, -3), Vector2(-18, 6),
	])
	for i in range(BG_BIRD_COUNT):
		var b := Node2D.new()
		var poly := Polygon2D.new()
		poly.polygon = chev
		poly.color = Color(0.10, 0.09, 0.08, 0.55)
		b.add_child(poly)
		var frac := float(i) / float(maxi(1, BG_BIRD_COUNT - 1))
		b.position = Vector2(vp.x * frac, vp.y * (0.10 + 0.045 * float(i % 3)))
		layer.add_child(b)
		var speed := 18.0 + 7.0 * float((i * 37) % 5) / 4.0
		var phase := TAU * float((i * 53) % 7) / 7.0
		_bg_birds.append([b, poly, speed, phase])


## Scene-themed drifting particles for the "living video" menu background.
## Returns theme params for the active background index.
func _theme_particle_params() -> Dictionary:
	match _bg_index:
		1:  # desert canyon at sunset: rising embers
			return {"color": Color(1.0, 0.55, 0.20), "amount": 26,
				"lifetime": 6.0, "dir": Vector3(0.15, -1.0, 0.0),
				"vmin": 22.0, "vmax": 45.0, "grav": Vector3(0.0, -6.0, 0.0),
				"smin": 0.5, "smax": 1.1, "alpha": 0.9}
		2:  # snowy mountain pass: falling snow
			return {"color": Color(0.93, 0.95, 1.0), "amount": 90,
				"lifetime": 9.0, "dir": Vector3(0.25, 1.0, 0.0),
				"vmin": 30.0, "vmax": 70.0, "grav": Vector3(0.0, 12.0, 0.0),
				"smin": 0.5, "smax": 1.2, "alpha": 0.85}
		3:  # coastal cliffside: drifting sea mist
			return {"color": Color(0.78, 0.88, 0.94), "amount": 40,
				"lifetime": 10.0, "dir": Vector3(1.0, -0.08, 0.0),
				"vmin": 14.0, "vmax": 30.0, "grav": Vector3(0.0, 0.0, 0.0),
				"smin": 1.6, "smax": 3.2, "alpha": 0.5}
		4:  # terraced valley: drifting leaves
			return {"color": Color(0.62, 0.85, 0.42), "amount": 34,
				"lifetime": 11.0, "dir": Vector3(0.45, 1.0, 0.0),
				"vmin": 16.0, "vmax": 34.0, "grav": Vector3(0.0, 8.0, 0.0),
				"smin": 0.7, "smax": 1.4, "alpha": 0.8}
		_:  # misty forest valley: fireflies
			return {"color": Color(0.68, 1.0, 0.42), "amount": 30,
				"lifetime": 7.0, "dir": Vector3(0.3, -0.25, 0.0),
				"vmin": 8.0, "vmax": 20.0, "grav": Vector3(0.0, 0.0, 0.0),
				"smin": 0.6, "smax": 1.3, "alpha": 0.95}


func _build_theme_particles(vp: Vector2, mul: float) -> void:
	_bg_theme_fx = null
	var p := _theme_particle_params()
	var fx := GPUParticles2D.new()
	fx.amount = maxi(10, int(float(p["amount"]) * mul))
	fx.lifetime = float(p["lifetime"])
	fx.preprocess = float(p["lifetime"])
	fx.texture = _pollen_dot_texture()
	fx.material = _bg_add_material()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(vp.x * 0.5, vp.y * 0.5, 1.0)
	pm.direction = p["dir"]
	pm.spread = 28.0
	pm.initial_velocity_min = float(p["vmin"])
	pm.initial_velocity_max = float(p["vmax"])
	pm.gravity = p["grav"]
	pm.damping_min = 2.0
	pm.damping_max = 8.0
	pm.scale_min = float(p["smin"])
	pm.scale_max = float(p["smax"])
	var col: Color = p["color"]
	var a := float(p["alpha"])
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.0))
	ramp.add_point(0.18, Color(col.r, col.g, col.b, a))
	ramp.add_point(0.82, Color(col.r, col.g, col.b, a))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	fx.process_material = pm
	fx.position = vp * 0.5
	_root.add_child(fx)
	_bg_theme_fx = fx


## Size/position the atmosphere layers for the current viewport.
func _fit_menu_atmosphere() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	for i in range(_bg_rays.size()):
		var ray: TextureRect = _bg_rays[i]
		if not is_instance_valid(ray):
			continue
		ray.size = Vector2(vp.x * 0.16, vp.y * 1.6)
		ray.pivot_offset = ray.size * 0.5
		# Shafts fan out from the bright upper area, slanting down-right.
		ray.position = Vector2(vp.x * (0.22 + 0.15 * float(i)) - ray.size.x * 0.5,
			vp.y * 0.45 - ray.size.y * 0.5)
		ray.rotation_degrees = 22.0 + 3.0 * float(i)
	if is_instance_valid(_bg_pollen):
		var pm := _bg_pollen.process_material as ParticleProcessMaterial
		if pm != null:
			pm.emission_box_extents = Vector3(vp.x * 0.5, vp.y * 0.5, 1.0)
		_bg_pollen.position = vp * 0.5
	if is_instance_valid(_bg_theme_fx):
		var tpm := _bg_theme_fx.process_material as ParticleProcessMaterial
		if tpm != null:
			tpm.emission_box_extents = Vector3(vp.x * 0.5, vp.y * 0.5, 1.0)
		_bg_theme_fx.position = vp * 0.5
	if is_instance_valid(_bg_bird_layer):
		_bg_bird_layer.set_meta("vp_w", vp.x)


## Animate the atmosphere: ray alpha pulse, bird flap + drift with wrap.
func _tick_menu_atmosphere(delta: float) -> void:
	if not visible:
		return
	_bg_time += delta
	# SC1-style title logo shimmer: slow, subtle brightness breathe.
	# (2026-10-10 AAA title entrance): shimmer rides self_modulate.a so it
	# composes with the entrance fade, which owns modulate.a.
	if _screen == "title" and is_instance_valid(_logo_rect):
		_logo_rect.self_modulate.a = 0.93 + 0.07 * sin(_bg_time * 0.9)
	for i in range(_bg_rays.size()):
		var ray: TextureRect = _bg_rays[i]
		if is_instance_valid(ray):
			ray.modulate.a = 0.55 + 0.30 * sin(_bg_time * 0.6 + float(_bg_ray_phases[i]))
	if is_instance_valid(_bg_bird_layer):
		var vp_w := float(_bg_bird_layer.get_meta("vp_w", 1280.0))
		for entry in _bg_birds:
			var b: Node2D = entry[0]
			var poly: Polygon2D = entry[1]
			if not is_instance_valid(b) or not is_instance_valid(poly):
				continue
			var speed: float = entry[2]
			var phase: float = entry[3]
			b.position.x += speed * delta
			if b.position.x > vp_w + 40.0:
				b.position.x = -40.0
			poly.scale.y = 1.0 - 0.55 * absf(sin(_bg_time * 5.0 + phase))


## Slow horizontal drift of the menu landscape (ping-pong = seamless loop).
func _process(delta: float) -> void:
	# Menu atmosphere animates even when the bg texture is missing
	# (headless fallback gradient), so tick it before the bg guards.
	_tick_menu_atmosphere(delta)
	# Title tips line: rotate every few seconds while on the title screen.
	# (Guarded: the label is freed with the screen on navigation.)
	if _screen == "title" and _title_tip_label != null \
			and is_instance_valid(_title_tip_label) and MENU_TIPS.size() > 1:
		_title_tip_timer += delta
		if _title_tip_timer >= TITLE_TIP_ROTATE_SECS:
			_title_tip_timer = 0.0
			_title_tip_idx = (_title_tip_idx + 1) % MENU_TIPS.size()
			_title_tip_label.text = MENU_TIPS[_title_tip_idx]
	# 3D carousel: ease rotation toward target, re-layout every frame.
	if not _carousel3d_cards.is_empty() and is_instance_valid(_carousel3d_view):
		if not _carousel3d_dragging:
			var diff: float = _carousel3d_target - _carousel3d_angle
			# Shortest wrap-around.
			while diff > PI:
				diff -= TAU
			while diff < -PI:
				diff += TAU
			if absf(diff) > 0.0005:
				_carousel3d_angle += diff * minf(1.0, delta * 10.0)
			else:
				_carousel3d_angle = _carousel3d_target
		_carousel3d_layout()
	if _bg_rect == null or not is_instance_valid(_bg_rect) or _bg_tex == null:
		return
	if not visible:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Jeremy 2026-10-04: re-fit the bg when the viewport changes (rotation /
	# window resize) so it stays full-bleed edge-to-edge.
	if vp != _bg_fit_vp:
		_fit_menu_bg()
		_fit_menu_atmosphere()
	var th := float(_bg_tex.get_height())
	if th <= 0.0:
		return
	var max_pan := maxf(0.0, float(_bg_tex.get_width()) * (vp.y / th) - vp.x)
	if max_pan <= 0.0:
		_bg_rect.position = Vector2.ZERO
		return
	_bg_pan += _bg_dir * BG_PAN_SPEED * _ui_scale * delta
	if _bg_pan >= max_pan:
		_bg_pan = max_pan
		_bg_dir = -1.0
	elif _bg_pan <= 0.0:
		_bg_pan = 0.0
		_bg_dir = 1.0
	_bg_rect.position = Vector2(-_bg_pan, 0)
	# Ken Burns zoom (Jeremy 2026-10-08): slow 50s breathe layered with
	# the pan — the menu background should feel like video, not wallpaper.
	var _zoom_phase := _bg_time * TAU / BG_ZOOM_PERIOD
	var _z := 1.0 + BG_ZOOM_AMOUNT * (0.5 + 0.5 * sin(_zoom_phase))
	_bg_rect.scale = Vector2(_z, _z)


## Canvas units per CSS px on web (1.0 elsewhere). Lets every menu size below
## match the HTML's CSS-px layout exactly, whatever the stretch viewport is.
## Jeremy 2026-10-04: orientation/device detection for responsive scaling.
## Returns "portrait" (tall phone), "landscape" (wide phone/tablet), or
## "desktop" (large viewport, no touch). Sets _orientation and _is_desktop.
## Jeremy 2026-10-06: also sets _aspect ("widescreen" for 16:9+, "standard"
## for ~4:3) so PC layouts can branch on aspect ratio, not just size.
## Jeremy 2026-10-08 (16:9 / landscape UI compat): the bucket rule now comes
## from Hud.layout_mode_for and touch detection from
## Hud.touchscreen_available, shared with the in-game HUD — menu and HUD can
## no longer disagree (they previously used different landscape thresholds:
## 1.0x here vs 1.2x in the HUD). Near-square viewports now read "portrait"
## in both places.
## The touchscreen parameter is injectable for tests; the default is the
## unified helper (headless Godot reports a touchscreen as available, which
## hides the desktop branch — pinned in test_aspect_layouts.gd).
func _detect_orientation(vp: Vector2, touchscreen: bool = Hud.touchscreen_available()) -> String:
	_is_desktop = not touchscreen and vp.x >= 1024.0 and vp.y >= 600.0
	var ratio := vp.x / maxf(vp.y, 1.0)
	_aspect = "widescreen" if ratio >= 1.5 else "standard"
	_orientation = Hud.layout_mode_for(vp, touchscreen)
	return _orientation


## Jeremy 2026-10-06 (launch readiness): aspect-aware faction-carousel height,
## split out of _show_faction so tests can pin the 16:9 vs 4:3 branch without
## building the screen. Base px (x2.5 scale); the card is 280 base tall.
static func carousel_h_for(orientation: String, aspect: String) -> float:
	match orientation:
		"landscape":
			return 300.0
		"desktop":
			# 4:3 ("standard") is relatively taller than 16:9, so the
			# carousel gets more vertical room there.
			return 380.0 if aspect == "widescreen" else 430.0
	return 330.0


func _compute_ui_scale(vp: Vector2) -> float:
	# Jeremy 2026-10-04: viewport reports DEVICE pixels on iPhone (1170-1290
	# wide), not CSS pixels (390). Old 400px baseline made everything 3x too
	# big. Baseline 1200 = device pixels: phones get ~1.0, desktop ~1.6.
	var k := vp.x / 1200.0
	return clampf(k, 0.7, 2.0)


## Vertical fill factor: how much to scale menu sizes so the column fills
## ~94% of the viewport height. 1.0 when content already fills (or needs
## scrolling). Pure function of measured heights — unit-independent.
static func _fill_boost_for(content_h: float, vp_h: float) -> float:
	# Jeremy 2026-10-03: menu still too small at 1.3x. Bump to 1.6x.
	if content_h <= 0.0 or vp_h <= 0.0:
		return 1.0
	var target := vp_h * 0.94
	if content_h >= target:
		return 1.0
	return minf(target / content_h, 1.6)


## Deferred one frame after a screen builds: measure the column against the
## viewport and, if there's dead space, rebuild once with a fill boost.
## Jeremy 2026-10-04: the boost is now width-aware — it never scales content
## wider than the column (the old vertical-only boost overflowed on iPhone).
func _refit_to_screen(v: VBoxContainer) -> void:
	if _refitting or v != _refit_vbox or not is_instance_valid(v):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var boost := _fill_boost_for(v.get_combined_minimum_size().y, vp.y)
	# Width cap: the widest fixed content (title at 44px, cards at 240px)
	# must fit within 94% of the viewport even after boosting.
	# Title "Choose Your Side" ~16 chars at 44px * 0.6 width factor.
	# Jeremy 2026-10-04: viewport is device pixels; 430 CSS px cap becomes
	# 1290 device px (x3 for iPhone DPR).
	var col_w := minf(vp.x * 0.94, 1290.0 * _ui_scale_w)
	var title_w_1x := 16.0 * 44.0 * 0.6 * _ui_scale_w
	var card_w_1x := 240.0 * _ui_scale_w
	var widest_1x := maxf(title_w_1x, card_w_1x)
	if widest_1x > 0.0:
		var width_boost := col_w / widest_1x
		boost = minf(boost, maxf(width_boost, 1.0))
	if boost <= 1.03:
		return
	_fill_boost = boost
	_refitting = true
	match _screen:
		"title":
			_show_title()
		"faction":
			_show_faction(_adventure_setup)
		"worlds":
			_show_worlds()
		"settings":
			_show_settings()
		"credits":
			_show_credits()
		"hearsay":
			_show_hearsay()
		"worldsetup":
			_show_worldsetup()
	_refitting = false


func _px(v: float) -> float:
	return v * _ui_scale


## Width-only px: horizontal sizes that must never exceed the column
## (inputs, fixed-width rows). Uses the unboosted width scale.
func _px_w(v: float) -> float:
	return v * _ui_scale_w


func _pxi(v: int) -> int:
	return maxi(1, int(round(float(v) * _ui_scale)))


func _lbl(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER,
		shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", _pxi(size))
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("shadow_offset_x", _pxi(1))
		l.add_theme_constant_override("shadow_offset_y", _pxi(1))
	return l


func _big_shadow(l: Control, px := 2) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("shadow_offset_x", _pxi(px))
	l.add_theme_constant_override("shadow_offset_y", _pxi(px))


func _spaced(l: Label, px: int) -> void:
	# Letter-spacing like CSS `letter-spacing` (tagline / hints).
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.spacing_glyph = _pxi(px)
	l.add_theme_font_override("font", fv)


func _flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(_pxi(bw))
	sb.border_color = border
	sb.set_corner_radius_all(_pxi(radius))
	sb.content_margin_left = _px(14)
	sb.content_margin_right = _px(14)
	sb.content_margin_top = _px(8)
	sb.content_margin_bottom = _px(8)
	return sb


func _pulse_alpha(node: CanvasItem, dur: float, lo := 0.45, hi := 0.95) -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(node, "modulate:a", hi, dur * 0.5).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "modulate:a", lo, dur * 0.5).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tw)


func _pulse_scale(node: Control, dur: float, amt := 0.05) -> void:
	node.pivot_offset = node.size / 2.0
	var tw := create_tween().set_loops()
	tw.tween_property(node, "scale", Vector2(1.0 + amt, 1.0 + amt), dur * 0.5).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, dur * 0.5).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tw)


## Menu card button: icon box + title/sub + chevron. Matches .menu-card.
func _menu_card(kind: String, title: String, sub: String, primary := false,
		compact := false) -> Button:
	var b := Button.new()
	b.text = ""
	# Jeremy 2026-10-05: compact cards stack icon+label vertically, so they
	# need more height than the 60px row cards (34px icon + label + padding).
	b.custom_minimum_size = Vector2(0, _px(84 if compact else 60))
	var bg: Color = C_PRIMARY_BG if primary else C_CARD_BG
	var bw := 2 if primary else 1
	var bc: Color = C_GOLD_BRIGHT if primary else C_CARD_BORDER
	b.add_theme_stylebox_override("normal", _flat(bg, bc, bw, 16))
	b.add_theme_stylebox_override("hover", _flat(bg.lightened(0.06), bc, bw, 16))
	b.add_theme_stylebox_override("pressed", _flat(bg.darkened(0.08), bc, bw, 16))
	b.add_theme_stylebox_override("focus", _flat(bg, C_GOLD_BRIGHT, bw, 16))
	# Jeremy 2026-10-05: compact cards (Settings/Credits/Hearsay row) are
	# ~110px wide on iPhone — a side-by-side icon+label only leaves ~36px
	# for the text, so "Settings" clipped to "Sett". Compact cards stack
	# vertically: icon centered on top, label centered below, full width
	# for the text.
	if compact:
		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = _px(8)
		vb.offset_right = _px(-8)
		vb.offset_top = _px(8)
		vb.offset_bottom = _px(-8)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", _pxi(4))
		b.add_child(vb)
		var ibox_c := PanelContainer.new()
		ibox_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ibox_c.custom_minimum_size = Vector2(_px(34), _px(34))
		ibox_c.add_theme_stylebox_override("panel", _flat(C_ICON_BG, C_ICON_BORDER, 1, 12))
		var ic_c := DrawnMenuIcon.new(kind, C_CREAM_BRIGHT, _pxi(3))
		ic_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic_c.set_anchors_preset(Control.PRESET_FULL_RECT)
		ibox_c.add_child(ic_c)
		var ic_wrap := CenterContainer.new()
		ic_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic_wrap.add_child(ibox_c)
		vb.add_child(ic_wrap)
		var t_c := _lbl(title, 13, C_CREAM_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
		_big_shadow(t_c, 1)
		t_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(t_c)
		return b
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = _px(16)
	hb.offset_right = _px(-12)
	hb.offset_top = _px(10)
	hb.offset_bottom = _px(-10)
	# Jeremy 2026-10-05: compact cards (Settings/Credits/Hearsay row) are
	# ~110px wide on iPhone — tighter spacing so the title fits its button.
	hb.add_theme_constant_override("separation", _pxi(10 if compact else 14))
	hb.alignment = BoxContainer.ALIGNMENT_BEGIN
	b.add_child(hb)
	# Icon box: DRAWN icons (Jeremy 2026-10-05 polish) — the old emoji
	# icons are gone entirely. Emoji rendered as tofu boxes in the web
	# export (Jeremy 2026-10-02: "all the buttons are missing symbols"),
	# so the box was hidden as a workaround; now DrawnMenuIcon draws
	# pure vector icons, no font glyphs, no textures. Always visible.
	var ibox := PanelContainer.new()
	ibox.visible = true
	ibox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_px := 36 if compact else 44
	ibox.custom_minimum_size = Vector2(_px(icon_px), _px(icon_px))
	ibox.add_theme_stylebox_override("panel", _flat(C_ICON_BG, C_ICON_BORDER, 1, 12))
	var ic := DrawnMenuIcon.new(kind, C_CREAM_BRIGHT, _pxi(3))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ibox.add_child(ic)
	hb.add_child(ibox)
	var tx := VBoxContainer.new()
	tx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tx.alignment = BoxContainer.ALIGNMENT_CENTER
	tx.add_theme_constant_override("separation", _pxi(2))
	tx.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(tx)
	var t := _lbl(title, 14 if compact else 16, C_CREAM_BRIGHT, HORIZONTAL_ALIGNMENT_LEFT)
	_big_shadow(t, 1)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Jeremy 2026-10-05: clip the title inside its button — unclipped text
	# spilled over the neighboring cards on iPhone ("text is off tabs").
	t.clip_text = true
	tx.add_child(t)
	if sub != "":
		var s := _lbl(sub, 18, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.clip_text = true
		tx.add_child(s)

	if not compact:
		var chev := _lbl("›", 28, C_CHEV, HORIZONTAL_ALIGNMENT_RIGHT, false)
		chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chev.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(chev)
	return b


## SC1-style cel-shaded stylebox: flat solid colors, bold outline, hard
## offset drop shadow (no blur, no gradients — Borderlands-meets-Warcraft).
func _sc1_style(bg: Color, border: Color, bw := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(_pxi(bw))
	sb.border_color = border
	sb.set_corner_radius_all(_pxi(6))
	sb.shadow_color = Color(0, 0, 0, 0.9)
	sb.shadow_size = _pxi(3)
	sb.shadow_offset = Vector2(0, _pxi(3))
	sb.content_margin_left = _px(16)
	sb.content_margin_right = _px(16)
	sb.content_margin_top = _px(8)
	sb.content_margin_bottom = _px(8)
	return sb


## Hover breathe tweens, keyed by button instance id.
var _breathe := {}


func _kill_breathe(b: Button) -> void:
	var key := b.get_instance_id()
	if _breathe.has(key):
		var tw: Tween = _breathe[key]
		if is_instance_valid(tw):
			tw.kill()
		_breathe.erase(key)
	if is_instance_valid(b):
		b.scale = Vector2.ONE


## SC1 hover: gentle breathe (scale 1.0 <-> 1.025 loop) while hovered.
func _on_sc1_hover(b: Button, hovering: bool) -> void:
	_kill_breathe(b)
	if hovering and is_instance_valid(b):
		b.pivot_offset = b.size * 0.5
		var tw := create_tween().set_loops()
		tw.tween_property(b, "scale", Vector2(1.025, 1.025), 0.55)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "scale", Vector2.ONE, 0.55)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_breathe[b.get_instance_id()] = tw
		_tweens.append(tw)


## StarCraft-1-style menu button (Jeremy 2026-10-08): wide rectangular
## beveled-look button, dark iron + gold border, centered cream text.
## Cel-shaded: flat colors, bold outline, hard shadow. Text-only, no icons.
func _sc1_button(title: String, small := false) -> Button:
	var b := Button.new()
	b.text = title
	b.custom_minimum_size = Vector2(0, _px(46 if small else 58))
	b.add_theme_font_size_override("font_size", _pxi(15 if small else 22))
	b.add_theme_color_override("font_color", C_CREAM)
	b.add_theme_color_override("font_hover_color", C_GOLD_BRIGHT)
	b.add_theme_color_override("font_pressed_color", C_GOLD)
	_big_shadow(b, 2)
	var bg_n := Color(0.160, 0.145, 0.155)   # dark iron
	var bg_h := Color(0.235, 0.205, 0.215)   # hover lift
	var bg_p := Color(0.100, 0.095, 0.105)   # pressed
	b.add_theme_stylebox_override("normal", _sc1_style(bg_n, C_GOLD))
	b.add_theme_stylebox_override("hover", _sc1_style(bg_h, C_GOLD_BRIGHT))
	b.add_theme_stylebox_override("pressed", _sc1_style(bg_p, C_GOLD))
	b.add_theme_stylebox_override("focus", _sc1_style(bg_h, C_GOLD_BRIGHT))
	b.mouse_entered.connect(_on_sc1_hover.bind(b, true))
	b.mouse_exited.connect(_on_sc1_hover.bind(b, false))
	return b


## Gold .menu-btn (CHOOSE WORLD etc.): 3px gold border, radius 2.
func _gold_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, _px(60))
	b.add_theme_font_size_override("font_size", _pxi(24))
	b.add_theme_color_override("font_color", C_CREAM)
	b.add_theme_color_override("font_hover_color", C_GOLD_BRIGHT)
	_big_shadow(b, 1)
	b.add_theme_stylebox_override("normal", _flat(C_BTN_BG, C_GOLD, 3, 2))
	b.add_theme_stylebox_override("hover", _flat(C_BTN_BG.lightened(0.08), C_GOLD_BRIGHT, 3, 2))
	b.add_theme_stylebox_override("pressed", _flat(C_BTN_BG.darkened(0.1), C_GOLD, 3, 2))
	return b


func _secondary_button(text: String) -> Button:
	var b := _gold_button(text)
	b.add_theme_stylebox_override("normal", _flat(C_BTN_BG.darkened(0.05), C_GOLD_DARK, 2, 2))
	b.add_theme_stylebox_override("hover", _flat(C_BTN_BG, C_GOLD, 2, 2))
	b.add_theme_stylebox_override("pressed", _flat(C_BTN_BG.darkened(0.12), C_GOLD_DARK, 2, 2))
	return b


func _h1(text: String, size := 44) -> Label:
	# .menu-h1: serif 1.9rem 900 #ffd54f, heavy shadow + gold glow.
	# Jeremy 2026-10-04: optional size — the faction screen uses a smaller
	# title (36) so everything fits on one iPhone screen without scrolling.
	var l := _lbl(text, size, C_GOLD_BRIGHT)
	_big_shadow(l, 2)
	# Jeremy 2026-10-04: constrain to viewport width in fullscreen —
	# title was getting cut off on the right on iPhone.
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _mdesc(text: String, size := 20) -> Label:
	# Jeremy 2026-10-04: optional size — the faction screen uses 18 so the
	# whole screen fits on iPhone without scrolling. Other screens keep 20.
	var l := _lbl(text, size, Color(0.831, 0.769, 0.659))  # #d4c4a8
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Jeremy 2026-10-04: fill width instead of fixed minimum — the 360px
	# minimum was forcing the label too wide in fullscreen on iPhone.
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Open the custom in-game keyboard for the ruler name (Jeremy 2026-10-03).
## The keyboard is a child of the CanvasLayer (not _root), so it survives
## screen rebuilds; _clear_screen closes it.
func _open_ruler_keyboard() -> void:
	if _ruler_input == null or not is_instance_valid(_ruler_input):
		return
	if _ruler_kb == null or not is_instance_valid(_ruler_kb):
		_ruler_kb = RulerKeyboard.new()
		_ruler_kb.visible = false
		add_child(_ruler_kb)
	_ruler_kb.open_for(_ruler_input, _ui_scale)


func _close_ruler_keyboard() -> void:
	if _ruler_kb != null and is_instance_valid(_ruler_kb):
		_ruler_kb.close()


## Note (Jeremy 2026-10-03): the ruler name no longer uses this — it has the
## custom in-game keyboard. The hero name field still uses a LineEdit.
func _styled_input() -> LineEdit:
	var le := LineEdit.new()
	le.custom_minimum_size = Vector2(_px_w(220), _px(88))
	le.add_theme_font_size_override("font_size", _pxi(24))
	le.add_theme_color_override("font_color", C_CREAM)
	le.add_theme_color_override("font_placeholder_color", C_DIM)
	var sb := _flat(C_INPUT_BG, C_GOLD, 2, 8)
	sb.content_margin_left = _px(12)
	le.add_theme_stylebox_override("normal", sb)
	le.add_theme_stylebox_override("focus", _flat(C_INPUT_BG, C_GOLD_BRIGHT, 2, 8))
	le.max_length = 24
	# iOS Safari keyboard fix (Jeremy 2026-10-02): explicitly show the virtual
	# keyboard when the LineEdit gains focus. Godot 4 web should do this
	# automatically, but iOS Safari needs the explicit call.
	# Jeremy 2026-10-03: pass le.text (NOT "") — Godot seeds its hidden
	# virtual-keyboard input with this string, and ALL mobile editing flows
	# through that input's events. Seeding "" while the LineEdit holds text
	# desyncs the OS buffer: iOS backspace then changes nothing, no input
	# event fires, and delete silently does nothing (upstream
	# godotengine/godot#72969 class of bug). Re-sync on every show.
	le.focus_mode = Control.FOCUS_ALL
	le.focus_entered.connect(func() -> void:
		DisplayServer.virtual_keyboard_show(le.text))
	le.focus_exited.connect(func() -> void:
		DisplayServer.virtual_keyboard_hide())
	# Also handle gui_input for touch: ensure focus is grabbed on tap.
	le.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch and event.pressed:
			le.grab_focus()
			DisplayServer.virtual_keyboard_show(le.text))
	return le


# ------------------------------------------------------------------- title

## Public entry: show the title screen (called from main.gd on quit-to-menu).
func show_title() -> void:
	_show_title()


func _show_title() -> void:
	# Jeremy 2026-10-08: StarCraft-1-style title screen. Massive logo,
	# vertically stacked beveled buttons (big actions first), clean —
	# no banner, no clutter. One thin tips line floats at the very
	# bottom (his "Tips?"). The living background (Ken Burns
	# + themed particles + rays + birds) is the show behind it.
	_screen = "title"
	if not _refitting:
		_fill_boost = 1.0
	var v := _new_screen(8)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Extra drama dim over the living background (SC1's menu is dark).
	var scroll_idx := -1
	for i in range(_root.get_child_count()):
		if _root.get_child(i) is ScrollContainer:
			scroll_idx = i
			break
	if scroll_idx >= 0:
		var extra := ColorRect.new()
		extra.color = Color(0.02, 0.015, 0.01, 0.22)
		extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
		extra.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.add_child(extra)
		_root.move_child(extra, scroll_idx)
	# Music hint: absolute top-right, pulsing (matches #music-unlock-hint).
	var hint := _lbl("tap anywhere for music", 12, C_MUSIC_HINT, HORIZONTAL_ALIGNMENT_RIGHT, false)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = _px(-240)
	hint.offset_right = _px(-12)
	# Jeremy 2026-10-04 safe areas (graphics-hourly 2026-10-11): pin below
	# the Dynamic Island — the old hard-coded 10px parked the hint under it.
	hint.offset_top = _safe_insets().x + _px(10)
	_root.add_child(hint)
	_pulse_alpha(hint, 2.2)
	# Logo: MASSIVE (SC1's STARCRAFT dominates the top). Slow shimmer
	# applied in _tick_menu_atmosphere via _logo_rect.
	# (2026-10-10 AAA entrance): the logo sits in a plain wrapper, NOT
	# directly in the VBox — containers reset child scale to 1.0 on layout,
	# which would kill the entrance overshoot. The wrapper holds the layout
	# slot (same geometry as before); the logo inside is free to scale.
	var logo_node: Control = null
	var logo_w := minf(vp.x * 0.98, 1000.0)
	var logo_h := logo_w * 133.0 / 400.0
	var logo_wrap := Control.new()
	logo_wrap.custom_minimum_size = Vector2(logo_w, logo_h)
	logo_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(logo_wrap)
	var logo_tex := load("res://assets/ui/cg_logo.png") as Texture2D
	if logo_tex != null:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.set_anchors_preset(Control.PRESET_FULL_RECT)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo_wrap.add_child(logo)
		_logo_rect = logo
		logo_node = logo
	else:
		# Headless test runs have no import cache; fall back to styled text.
		var fallback := _lbl(TITLE, 64, C_GOLD_BRIGHT)
		_big_shadow(fallback, 3)
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo_wrap.add_child(fallback)
		logo_node = fallback
	# Tagline: letter-spaced, #e8dcc8.
	var tag := _lbl(TAGLINE, 13, C_TAGLINE)
	_spaced(tag, 2)
	v.add_child(tag)
	# Jeremy 2026-10-06 (launch readiness): one-shot notice (e.g. corrupt
	# save). Rendered once under the tagline, then cleared — a later screen
	# rebuild must not resurrect a stale notice.
	var notice_panel: Control = null
	if _pending_notice != "":
		notice_panel = _notice_panel(_pending_notice)
		v.add_child(notice_panel)
		_pending_notice = ""
	# Build splash: yellow, rotated -3deg, pulsing (matches .build-splash).
	var splash_wrap := CenterContainer.new()
	var splash := _lbl(random_splash(), 17, C_SPLASH)
	splash.add_theme_color_override("font_shadow_color", Color(0.25, 0.25, 0.0, 0.9))
	splash.add_theme_constant_override("shadow_offset_x", _pxi(2))
	splash.add_theme_constant_override("shadow_offset_y", _pxi(2))
	splash.rotation = deg_to_rad(-3.0)
	splash_wrap.add_child(splash)
	v.add_child(splash_wrap)
	_pulse_scale(splash, 1.1)
	# SC1 button stack: big primary actions first, centered, text-only.
	var b_new := _sc1_button("New Game")
	b_new.pressed.connect(func() -> void: _show_faction())
	v.add_child(b_new)
	_continue_btn = _sc1_button("Continue")
	_continue_btn.pressed.connect(_on_continue_pressed)
	v.add_child(_continue_btn)
	_refresh_continue()
	var b_worlds := _sc1_button("Saved Worlds")
	b_worlds.pressed.connect(func() -> void: _show_worlds())
	v.add_child(b_worlds)
	var b_sandbox := _sc1_button("Sandbox Observe")
	b_sandbox.pressed.connect(func() -> void: sandbox_requested.emit())
	v.add_child(b_sandbox)
	var b_adv := _sc1_button("Adventure Mode")
	b_adv.pressed.connect(func() -> void: _show_faction(true))
	v.add_child(b_adv)
	# Smaller row: Settings / Credits / Hearsay.
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", _pxi(10))
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row2)
	var b_set := _sc1_button("Settings", true)
	b_set.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_set.pressed.connect(func() -> void: _show_settings())
	row2.add_child(b_set)
	var b_cred := _sc1_button("Credits", true)
	b_cred.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_cred.pressed.connect(func() -> void: _show_credits())
	row2.add_child(b_cred)
	var b_hear := _sc1_button("Hearsay", true)
	b_hear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_hear.pressed.connect(func() -> void: _show_hearsay())
	row2.add_child(b_hear)
	# Footer: version/copyright, small and dim (SC1 has this at the bottom).
	var footer := _lbl(MENU_FOOT, 11, C_FOOT)
	v.add_child(footer)
	# Jeremy 2026-10-08 ("Tips?"): ONE thin tips line back on the title.
	# Overlay pinned to the very bottom — floats above the background,
	# reserves NO layout space (the 2026-10-07 "Title screen is busted"
	# lesson). MOUSE_FILTER_IGNORE so it never eats taps; single line,
	# clipped, kept inside the horizontal safe area.
	if not MENU_TIPS.is_empty():
		var insets := _safe_insets()
		_title_tip_idx = randi() % MENU_TIPS.size()
		_title_tip_label = _lbl(MENU_TIPS[_title_tip_idx], 12, C_TIP)
		_title_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_tip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_title_tip_label.clip_text = true
		_title_tip_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_title_tip_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_title_tip_label.offset_left = insets.z + _px(24)
		_title_tip_label.offset_right = -(insets.w + _px(24))
		_title_tip_label.offset_top = -(insets.y + _px(30))
		_title_tip_label.offset_bottom = -(insets.y + _px(8))
		_root.add_child(_title_tip_label)
		_title_tip_timer = 0.0
	else:
		_title_tip_label = null
	# Update banner: overlay modal on version change only — never inline,
	# never pushing the layout (Jeremy 2026-10-08).
	_maybe_show_banner_overlay()
	# AAA boot (Jeremy 2026-10-10): bold title entrance — the logo drops in
	# with an overshoot while tagline/splash/buttons cascade. Runs after the
	# banner so a first-run modal never sits under the animation.
	var cascade: Array = [tag]
	if notice_panel != null:
		cascade.append(notice_panel)
	cascade.append_array([splash_wrap, b_new, _continue_btn, b_worlds, b_sandbox, b_adv, row2, footer])
	_title_entrance(logo_node, cascade)


## AAA boot (Jeremy 2026-10-10): bold "CURSING GNOMES" title entrance. The
## logo drops in with an overshoot (TRANS_BACK) while the tagline, splash,
## buttons, and footer cascade with a staggered fade. Pure presentation —
## no layout or input changes. Every tween is registered in _tweens, so a
## screen change kills the choreography with everything else (no leaks).
## The logo shimmer in _tick_menu_atmosphere rides self_modulate.a, so it
## composes with the entrance fade on modulate.a instead of fighting it.
func _title_entrance(logo_node: Control, cascade: Array) -> void:
	if logo_node != null and is_instance_valid(logo_node):
		logo_node.modulate.a = 0.0
		logo_node.scale = Vector2(0.7, 0.7)
		logo_node.pivot_offset = logo_node.size * 0.5
		# Re-center the pivot once the container lays the logo out (size is
		# zero at build time); entrance scale then grows from the true center.
		logo_node.resized.connect(_recenter_pivot.bind(logo_node))
		var ltw := create_tween()
		ltw.set_parallel()
		ltw.tween_property(logo_node, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)
		ltw.tween_property(logo_node, "scale", Vector2.ONE, 0.65) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tweens.append(ltw)
	var delay := 0.16
	for n in cascade:
		if n == null or not is_instance_valid(n):
			continue
		(n as Control).modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(n, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)
		_tweens.append(tw)
		delay += 0.07


func _recenter_pivot(n: Control) -> void:
	if is_instance_valid(n):
		n.pivot_offset = n.size * 0.5


## Update-banner overlay (Jeremy 2026-10-08): the banner no longer lives in
## the title VBox (it ate the menu). It appears once per version as a
## centered modal over a dim, tap-outside or X to dismiss, dismissal saved.
func _maybe_show_banner_overlay() -> void:
	if get_setting("dismissed_banner", "") == UB_TITLE:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	_banner_tw_mark = _tweens.size()
	var panel := _update_banner()
	panel.custom_minimum_size = Vector2(minf(vp.x * 0.92, 640.0), 0)
	center.add_child(panel)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_dismiss_banner()
		elif event is InputEventScreenTouch:
			if (event as InputEventScreenTouch).pressed:
				_dismiss_banner())
	_banner_overlay = overlay


func _update_banner() -> PanelContainer:
	# .update-banner: purple gradient, 1.5px purple border, 16px radius.
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(C_BANNER_BG, C_BANNER_BORDER, 2, 16))
	_banner = p
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _pxi(4))
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _pxi(12))
	head.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_child(head)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", _pxi(1))
	head.add_child(titles)
	var ut := _lbl(UB_TITLE, 18, C_PURPLE, HORIZONTAL_ALIGNMENT_LEFT)
	_big_shadow(ut, 2)
	titles.add_child(ut)
	var us := _lbl(UB_SUB, 12, C_PURPLE_DIM, HORIZONTAL_ALIGNMENT_LEFT, false)
	titles.add_child(us)
	for line in UB_LINES:
		vb.add_child(_lbl("•  " + line, 13, C_UB_LINE, HORIZONTAL_ALIGNMENT_LEFT, false))
	var uh := _lbl("TAP TO CONTINUE ›", 12, C_HINT_GOLD, HORIZONTAL_ALIGNMENT_CENTER, false)
	_spaced(uh, 2)
	vb.add_child(uh)
	_pulse_alpha(uh, 1.6)
	# Dismiss X top-right (matches .ub-dismiss). Jeremy 2026-10-04:
	# drawn X, never a text glyph — the "×" text button rendered as
	# tofu on iPhone (back-button rule: no text X buttons in the UI).
	# Placed in the header HBox (right-aligned via spacer) so the
	# PanelContainer layout doesn't shove it over the text.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var dis := Button.new()
	dis.text = ""
	dis.custom_minimum_size = Vector2(_px(32), _px(32))
	var xmark := DrawnX.new(C_PURPLE, _pxi(3))
	xmark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dis.add_child(xmark)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.698, 0.4, 1.0, 0.18)
	dsb.set_corner_radius_all(_pxi(8))
	dis.add_theme_stylebox_override("normal", dsb)
	dis.pressed.connect(_dismiss_banner)
	head.add_child(dis)
	# Tap banner body to dismiss (HTML: "tap to continue").
	# Jeremy 2026-10-02: re-added after removing — the freeze was from
	# queue_free during the pulse tween, not from the tap itself.
	# _dismiss_banner now only hides, so this is safe.
	p.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_dismiss_banner()
		elif event is InputEventScreenTouch and event.pressed:
			_dismiss_banner()
	)
	return p


func _dismiss_banner() -> void:
	# Jeremy 2026-10-02: tapping banner froze the game. Root cause: the
	# "TAP TO CONTINUE" label has a pulse tween — queue_free()ing the banner
	# while the tween runs hangs. Fix: hide (don't free); the node is cleaned
	# up with the menu. Null the ref so dismiss is idempotent.
	# Jeremy 2026-10-08: the banner is now an overlay modal (not inline),
	# so the whole overlay — dim + centered panel — goes away on dismiss.
	# Dismissal persists per version so it only appears on version change.
	set_setting("dismissed_banner", UB_TITLE)
	# Kill only the banner's own tweens (its "TAP TO CONTINUE" pulse):
	# freeing the panel mid-tween hangs the game (Jeremy 2026-10-02),
	# but the splash/hint pulses must keep running.
	for i in range(_banner_tw_mark, _tweens.size()):
		var t = _tweens[i]
		if is_instance_valid(t):
			(t as Tween).kill()
	_tweens = _tweens.slice(0, _banner_tw_mark)
	if _banner != null and is_instance_valid(_banner):
		_banner.visible = false
	_banner = null
	if _banner_overlay != null and is_instance_valid(_banner_overlay):
		_banner_overlay.queue_free()
	_banner_overlay = null


## Jeremy 2026-10-06 (launch readiness): show a one-shot notice on the title
## screen (e.g. corrupt-save notice after backing out of _on_continue).
## Goes through show_title() so it lands inside the built screen and survives
## nothing stale — _show_title() consumes and clears it on render.
func flash_notice(text: String) -> void:
	_pending_notice = text
	show_title()


## Notice panel for _pending_notice: warm red-tinted panel, tap-to-dismiss,
## like the update banner. Rendered at the top of the title screen.
func _notice_panel(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(
		Color(0.32, 0.10, 0.08, 0.94), Color(0.85, 0.35, 0.25, 0.65), 2, 12))
	var l := _lbl(text, 14, Color(1.0, 0.82, 0.72),
		HORIZONTAL_ALIGNMENT_CENTER, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	# Tap anywhere on the panel to dismiss (matches the banner rule).
	p.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			p.visible = false
		elif event is InputEventScreenTouch and event.pressed:
			p.visible = false
	)
	return p


func _refresh_continue() -> void:
	var slots := SaveSystem.list_slots()
	var has := false
	for s in slots:
		if not bool(s.get("empty", true)):
			has = true
			break
	_continue_btn.visible = has


func _on_continue_pressed() -> void:
	var slots := SaveSystem.list_slots()
	for i in range(slots.size() - 1, -1, -1):
		if not bool(slots[i].get("empty", true)):
			continue_requested.emit(int(slots[i]["slot"]))
			return


# ------------------------------------------------------------------ faction

func _show_faction(adventure_mode := false) -> void:
	_screen = "faction"
	if not _refitting:
		_fill_boost = 1.0
	_adventure_setup = adventure_mode
	# Jeremy 2026-10-04: tighter column separation (8->6) — every pixel
	# counts toward fitting title + carousel + factions + name + start on
	# one iPhone 17 portrait screen with no scrolling.
	var v := _new_screen(6)
	v.add_child(_h1("Choose Your Side" if not adventure_mode else "Choose Your Hero's Homeland", 36))
	if adventure_mode:
		v.add_child(_mdesc("Your hero hails from this faction's lands. The world still runs all five factions — you just lead one legend through it: quests, dungeons, gear, glory.", 18))
	else:
		v.add_child(_mdesc("Civilizations name their cities, build houses for citizens, barracks for soldiers, and roads. Everything runs autonomously. Destroy the enemy Hall to win.", 18))
	# Faction cards: 3D TRADING-CARD CAROUSEL (Jeremy 2026-10-03).
	# Cards rotate around an elliptical track with depth scaling —
	# front card is full-size, back cards shrink and dim. Drag to spin,
	# release snaps to the nearest card, tap a card to bring it front.
	var carousel := Control.new()
	# Jeremy 2026-10-04: carousel height adapts to orientation; 2026-10-06:
	# desktop branches on the 16:9 vs 4:3 aspect bucket (carousel_h_for).
	# Card is 280 base tall (700 final); carousel must fit it plus padding.
	# Shrunk from 420 (2026-10-04: Jeremy wants the whole faction screen —
	# title to START button — on one iPhone screen).
	var carousel_h := carousel_h_for(_orientation, _aspect)
	carousel.custom_minimum_size = Vector2(0, _px(carousel_h))
	carousel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carousel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Jeremy 2026-10-04: clip side cards to carousel bounds so they never
	# cause horizontal overflow on iPhone. Partially-visible side cards are
	# by design; cutoff at the screen edge is not.
	carousel.clip_contents = true
	v.add_child(carousel)
	_carousel3d_cards.clear()
	_carousel3d_view = carousel
	_carousel3d_angle = 0.0
	_carousel3d_target = 0.0
	_carousel3d_dragging = false
	for fid in FACTION_ORDER:
		var card := _trading_card(fid)
		carousel.add_child(card)
		_carousel3d_cards.append({"fid": fid, "node": card})
	# Select the default faction's card to front.
	_carousel3d_snap_to(_selected_faction, true)
	carousel.gui_input.connect(_on_carousel3d_input)
	carousel.resized.connect(_on_carousel3d_resized)
	# ACTIVE FACTIONS toggle box (matches buildFactionPicker61).
	v.add_child(_active_factions_box())
	# Ruler name — stored VERBATIM, never trimmed (Jeremy's law).
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", _pxi(10))
	var name_lbl := _lbl("YOUR ROYAL NAME", 16, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)
	name_row.add_child(name_lbl)
	_ruler_input = RulerNameField.new()
	# Jeremy 2026-10-04: shorter input (88->64 base) — the faction screen
	# must fit on one iPhone screen; the field stays plenty tappable.
	_ruler_input.custom_minimum_size = Vector2(_px_w(280), _px(64))
	_ruler_input.set_font_size(_pxi(20))
	# Jeremy 2026-10-03: custom in-game keyboard ("Why not build a built in
	# keyboard?") — no OS virtual keyboard, so no iOS focus-zoom and no
	# hidden-input backspace desync. Name restores from cache when returning
	# to this screen; blank on first visit (Jeremy 2026-10-02).
	_ruler_input.text = _ruler_name_cache
	_ruler_input.placeholder_text = "Enter your royal name"
	_ruler_input.tapped.connect(_open_ruler_keyboard)
	_ruler_input.text_changed.connect(func(t: String) -> void: _ruler_name_cache = t)
	name_row.add_child(_ruler_input)
	v.add_child(name_row)
	if adventure_mode:
		var hero_row := HBoxContainer.new()
		hero_row.alignment = BoxContainer.ALIGNMENT_CENTER
		hero_row.add_theme_constant_override("separation", _pxi(10))
		hero_row.add_child(_lbl("Hero name:", 16, C_CREAM, HORIZONTAL_ALIGNMENT_RIGHT, false))
		_hero_input = _styled_input()
		_hero_input.text = ""
		_hero_input.placeholder_text = "Name your legend"
		hero_row.add_child(_hero_input)
		v.add_child(hero_row)
		var job_row := HBoxContainer.new()
		job_row.alignment = BoxContainer.ALIGNMENT_CENTER
		job_row.add_theme_constant_override("separation", _pxi(10))
		job_row.add_child(_lbl("Hero class:", 16, C_CREAM, HORIZONTAL_ALIGNMENT_RIGHT, false))
		_hero_job = OptionButton.new()
		for jid in _hero_job_ids():
			_hero_job.add_item(
				String(SimAdventure.HERO_JOB_NAMES.get(jid, jid.capitalize())))
		_hero_job.custom_minimum_size = Vector2(_px_w(300), _px(88))
		job_row.add_child(_hero_job)
		# Default hero name: faction name + number (HTML setupCharCreate
		# parity) — only when the field is empty, never clobbering input.
		if _hero_input != null and _hero_input.text == "":
			var _fname := str((FACTION_INFO.get(_selected_faction, {}) \
				as Dictionary).get("name", "Hero")).capitalize()
			_hero_input.text = "%s%d" % [_fname, randi_range(10, 99)]
		v.add_child(job_row)
		# Hero gender picker (HTML screen-charcreate parity: Male / Female
		# toggle buttons; plain text labels — no emoji font dependency).
		var gender_row := HBoxContainer.new()
		gender_row.alignment = BoxContainer.ALIGNMENT_CENTER
		gender_row.add_theme_constant_override("separation", _pxi(10))
		gender_row.add_child(_lbl("Hero gender:", 16, C_CREAM,
			HORIZONTAL_ALIGNMENT_RIGHT, false))
		_hero_gender_btns.clear()
		for gd in [["male", "Male"], ["female", "Female"]]:
			var gb := _secondary_button(gd[1])
			gb.toggle_mode = true
			gb.custom_minimum_size = Vector2(_px_w(120), _px(88))
			gb.set_pressed_no_signal(gd[0] == _hero_gender)
			gb.pressed.connect(_on_hero_gender.bind(gd[0]))
			gender_row.add_child(gb)
			_hero_gender_btns.append(gb)
		v.add_child(gender_row)
	# No emoji on the buttons: Godot's web font lacks 🗡️/🌍 (tofu on iPhone).
	var b_start := _gold_button("START ADVENTURE" if adventure_mode else "CHOOSE WORLD")
	b_start.pressed.connect(_on_start_game)
	v.add_child(b_start)
	var b_back := _secondary_button("‹ BACK")
	b_back.pressed.connect(func() -> void: _show_title())
	v.add_child(b_back)


## Adventure hero gender toggle (HTML .hero-gender parity).
func _on_hero_gender(g: String) -> void:
	_hero_gender = g
	for i in _hero_gender_btns.size():
		_hero_gender_btns[i].set_pressed_no_signal(
			["male", "female"][i] == g)


func _trading_card(fid: String) -> Button:
	# Trading card: uses generated card art (assets/ui/factions/cards/<fid>.webp).
	# The image is a complete trading card with ornate border and character.
	# We overlay the faction name (top) and stat strip (bottom) since the
	# art has no baked-in text. Acts as a Button; carousel handles taps.
	# Jeremy 2026-10-03: "make them like real trading cards" — using the
	# image-tool generated art.
	var info: Dictionary = FACTION_INFO[fid]
	var fac_col: Color = FACTION_COLORS.get(fid, C_GOLD)
	var b := Button.new()
	b.toggle_mode = true
	b.text = ""
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Jeremy 2026-10-04: shrunk 240x340 -> 200x280 base — the carousel art
	# is untouched, just smaller, so title + factions + name + START all fit
	# on one iPhone 17 portrait screen. The elliptical track in
	# _carousel3d_layout() is fully adaptive to card/view size.
	b.custom_minimum_size = Vector2(_px(200), _px(280))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.set_pressed_no_signal(fid == _selected_faction)
	# Card frame: subtle dark border (the art has its own ornate border).
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.05, 0.04, 0.03, 1.0)
	frame.set_border_width_all(_pxi(2))
	frame.border_color = Color(0.2, 0.15, 0.1)
	frame.set_corner_radius_all(_pxi(10))
	frame.shadow_color = Color(0, 0, 0, 0.65)
	frame.shadow_size = _pxi(14)
	frame.shadow_offset = Vector2(0, _pxi(4))
	b.add_theme_stylebox_override("normal", frame)
	var frame_sel := frame.duplicate() as StyleBoxFlat
	frame_sel.border_color = Color(1.0, 0.88, 0.45)
	frame_sel.set_border_width_all(_pxi(4))
	frame_sel.shadow_color = Color(fac_col.r, fac_col.g, fac_col.b, 0.5)
	frame_sel.shadow_size = _pxi(22)
	b.add_theme_stylebox_override("pressed", frame_sel)
	b.add_theme_stylebox_override("hover", frame)
	b.add_theme_stylebox_override("focus", frame_sel)
	# Card art (full bleed).
	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var card_tex := load("res://assets/ui/factions/cards/%s.webp" % fid) as Texture2D
	if card_tex != null:
		art.texture = card_tex
	else:
		# Fallback to old portrait if card art missing.
		var ptex := load("res://assets/ui/factions/%s.png" % fid) as Texture2D
		if ptex != null:
			art.texture = ptex
	b.add_child(art)
	# Name banner (top, semi-transparent dark).
	var name_bg := ColorRect.new()
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bg.color = Color(0, 0, 0, 0.55)
	name_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_bg.offset_bottom = _px(44)
	b.add_child(name_bg)
	var nm := _lbl(str(info["name"]).capitalize(), 22, fac_col,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	_big_shadow(nm, 2)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.set_anchors_preset(Control.PRESET_TOP_WIDE)
	nm.offset_bottom = _px(44)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(nm)
	# Stat strip (bottom, semi-transparent dark banner).
	var stat_bg := ColorRect.new()
	stat_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_bg.color = Color(0, 0, 0, 0.60)
	stat_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	stat_bg.offset_top = -_px(52)
	b.add_child(stat_bg)
	var strip := HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", _pxi(10))
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -_px(52)
	strip.offset_bottom = 0
	b.add_child(strip)
	for sk in ["atk", "def", "spd"]:
		var box := _stat_box(sk.to_upper(), int(info[sk]), fac_col)
		# Compact stat boxes for the overlay.
		box.custom_minimum_size = Vector2(_px(56), _px(44))
		strip.add_child(box)
	_add_card_effects(b, fac_col)
	return b


## God-rays shader material (shared across cards).
var _godrays_mat: ShaderMaterial


func _get_godrays_mat() -> ShaderMaterial:
	if _godrays_mat == null or not is_instance_valid(_godrays_mat):
		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;
uniform vec4 ray_color : source_color = vec4(1.0, 0.88, 0.55, 1.0);
uniform float ray_count = 14.0;
uniform float rotation_speed = 0.25;
uniform float intensity = 0.4;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 2.0;
	float angle = atan(uv.y, uv.x);
	float rays = 0.5 + 0.5 * sin(angle * ray_count + TIME * rotation_speed * 6.28318);
	rays = pow(rays, 2.5);
	float fade = smoothstep(1.0, 0.05, dist);
	float center_fade = smoothstep(0.05, 0.4, dist);
	COLOR = vec4(ray_color.rgb, rays * fade * center_fade * intensity * ray_color.a);
}
"""
		_godrays_mat = ShaderMaterial.new()
		_godrays_mat.shader = sh
	return _godrays_mat


## Soft round particle texture (procedural radial gradient).
func _soft_particle_tex() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.85))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	# Mid-point soft falloff.
	grad.add_point(0.4, Color(1, 1, 1, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


## Attach smoke + god-rays to a trading card. Effects start hidden;
## _carousel3d_layout enables them on the front card.
func _add_card_effects(card: Button, accent: Color) -> void:
	# God-rays: large rect behind the card, slowly rotating beams.
	var rays := TextureRect.new()
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Oversize so beams extend past the card edges.
	rays.anchor_left = -0.6
	rays.anchor_right = 1.6
	rays.anchor_top = -0.6
	rays.anchor_bottom = 1.6
	rays.offset_left = 0
	rays.offset_right = 0
	rays.offset_top = 0
	rays.offset_bottom = 0
	rays.material = _get_godrays_mat()
	rays.modulate = Color(accent.r, accent.g, accent.b, 0.55)
	rays.visible = false
	rays.name = "GodRays"
	# Insert behind card content (card is a Button; add as sibling via parent
	# would break layout — instead add as first child so it draws under).
	card.add_child(rays)
	card.move_child(rays, 0)
	# Smoke: CPUParticles2D rising from the card's base.
	var smoke := CPUParticles2D.new()
	smoke.name = "Smoke"
	# No mouse_filter: CPUParticles2D is not a Control (assignment throws a
	# script error). Node2D children of the card Button never take GUI
	# input anyway.
	smoke.amount = 24
	smoke.lifetime = 2.4
	smoke.preprocess = 1.2
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = _px(70)
	smoke.direction = Vector2(0, -1)
	smoke.spread = 28.0
	smoke.initial_velocity_min = _px(28)
	smoke.initial_velocity_max = _px(55)
	smoke.gravity = Vector2.ZERO
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.1
	smoke.scale_amount_curve = _smoke_scale_curve()
	smoke.color_ramp = _smoke_color_ramp(accent)
	smoke.texture = _soft_particle_tex()
	# Anchor to bottom-center of the card.
	smoke.position = Vector2(card.size.x * 0.5, card.size.y * 0.92)
	smoke.visible = false
	smoke.emitting = false
	card.add_child(smoke)


## Smoke grows then fades: scale curve.
func _smoke_scale_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(0.5, 1.0))
	c.add_point(Vector2(1, 1.6))
	return c


## Smoke color: accent-tinted white fading to transparent.
func _smoke_color_ramp(accent: Color) -> Gradient:
	var g := Gradient.new()
	var tint := Color(
		lerpf(1.0, accent.r, 0.45),
		lerpf(1.0, accent.g, 0.45),
		lerpf(1.0, accent.b, 0.45), 0.0)
	g.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	g.add_point(0.25, Color(tint.r, tint.g, tint.b, 0.5))
	g.add_point(0.7, Color(tint.r, tint.g, tint.b, 0.28))
	g.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	return g


## Small stat box for the trading card strip.
func _stat_box(label_text: String, val: int, accent: Color) -> PanelContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(_px(56), _px(52))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.11, 0.07, 1.0)
	sb.set_border_width_all(_pxi(2))
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	sb.set_corner_radius_all(_pxi(6))
	box.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	box.add_child(vb)
	var l := _lbl(label_text, 11, Color(0.7, 0.64, 0.52),
		HORIZONTAL_ALIGNMENT_CENTER, false)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l)
	var v := _lbl(str(val), 18, Color(1.0, 0.9, 0.6),
		HORIZONTAL_ALIGNMENT_CENTER, false)
	_big_shadow(v, 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(v)
	return box




## 3D carousel input: drag to spin, release snaps, tap selects.
## Direction lock (Jeremy 2026-10-05): a clearly-vertical drag is a page
## scroll — the press is handed back to the ScrollContainer and the
## release must NOT fire a tap. Before this, scrolling the faction screen
## from the carousel area reselected whichever card the finger lifted
## over. Mirrors world_setup's _car_try_lock for the worldgen carousels.
func _carousel3d_vertical_cancel(pos: Vector2) -> bool:
	var dx_total: float = pos.x - _carousel3d_press_x
	var dy_total: float = pos.y - _carousel3d_press_y
	if absf(dy_total) > 8.0 and absf(dy_total) > absf(dx_total):
		_carousel3d_dragging = false
		return true
	return false


func _on_carousel3d_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_carousel3d_dragging = true
				_carousel3d_moved = false
				_carousel3d_press_x = mb.position.x
				_carousel3d_press_y = mb.position.y
				_carousel3d_last_x = mb.position.x
			else:
				# Tap (no drag): _tap_at already snapped to the tapped
				# card — do NOT _snap_nearest() here; it recomputes from
				# the unmoved angle and would undo the tap (Jeremy
				# 2026-10-05: tap-to-select was silently dead).
				if _carousel3d_dragging and not _carousel3d_moved:
					_carousel3d_tap_at(mb.position)
				else:
					_carousel3d_snap_nearest()
				_carousel3d_dragging = false
			_carousel3d_view.accept_event()
	elif event is InputEventMouseMotion and _carousel3d_dragging:
		var mm := event as InputEventMouseMotion
		if not _carousel3d_moved and _carousel3d_vertical_cancel(mm.position):
			return  # vertical scroll: the ScrollContainer owns the gesture
		var dx: float = mm.position.x - _carousel3d_last_x
		_carousel3d_last_x = mm.position.x
		if absf(mm.position.x - _carousel3d_press_x) > 8.0:
			_carousel3d_moved = true
		_carousel3d_angle += dx / _carousel3d_radius()
		_carousel3d_target = _carousel3d_angle
		_carousel3d_view.accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_carousel3d_dragging = true
			_carousel3d_moved = false
			_carousel3d_press_x = st.position.x
			_carousel3d_press_y = st.position.y
			_carousel3d_last_x = st.position.x
		else:
			# Tap (no drag): _tap_at already snapped to the tapped card —
			# do NOT _snap_nearest() here (see mouse branch above).
			if _carousel3d_dragging and not _carousel3d_moved:
				_carousel3d_tap_at(st.position)
			else:
				_carousel3d_snap_nearest()
			_carousel3d_dragging = false
		_carousel3d_view.accept_event()
	elif event is InputEventScreenDrag and _carousel3d_dragging:
		var sd := event as InputEventScreenDrag
		if not _carousel3d_moved and _carousel3d_vertical_cancel(sd.position):
			return  # vertical scroll: the ScrollContainer owns the gesture
		var dx2: float = sd.position.x - _carousel3d_last_x
		_carousel3d_last_x = sd.position.x
		if absf(sd.position.x - _carousel3d_press_x) > 8.0:
			_carousel3d_moved = true
		_carousel3d_angle += dx2 / _carousel3d_radius()
		_carousel3d_target = _carousel3d_angle
		_carousel3d_view.accept_event()


## Carousel track radius in px (half the view width, clamped).
func _carousel3d_radius() -> float:
	if not is_instance_valid(_carousel3d_view):
		return 200.0
	return clampf(_carousel3d_view.size.x * 0.38, 120.0, 320.0)


## Layout every card on the elliptical track for the current angle.
func _carousel3d_layout() -> void:
	if not is_instance_valid(_carousel3d_view) or _carousel3d_cards.is_empty():
		return
	var n: int = _carousel3d_cards.size()
	var cx: float = _carousel3d_view.size.x * 0.5
	var cy: float = _carousel3d_view.size.y * 0.52
	var rx: float = _carousel3d_radius()
	var ry: float = rx * 0.22
	var step: float = TAU / float(n)
	for i in n:
		var entry: Dictionary = _carousel3d_cards[i]
		var card: Control = entry["node"]
		if not is_instance_valid(card):
			continue
		var a: float = _carousel3d_angle + float(i) * step
		# Depth: cos(a) = 1 at front, -1 at back.
		var depth: float = 0.5 + 0.5 * cos(a)
		var px: float = cx + rx * sin(a)
		var py: float = cy + ry * sin(a) * 0.5 - (1.0 - depth) * ry * 0.6
		var s: float = 0.55 + 0.45 * depth
		card.scale = Vector2(s, s)
		card.position = Vector2(px, py) - card.size * s * 0.5
		# Back cards dim and fade; front card pops.
		var dim: float = 0.45 + 0.55 * depth
		card.modulate = Color(dim, dim, dim, 0.55 + 0.45 * depth)
		# z_index: front card on top.
		card.z_index = int(depth * 100.0)
		# Pivot at center so scale grows outward evenly.
		card.pivot_offset = card.size * 0.5
		# Effects only on the front card (depth ~1).
		var is_front: bool = depth > 0.92
		var rays := card.get_node_or_null("GodRays")
		if rays != null:
			rays.visible = is_front
		var smoke := card.get_node_or_null("Smoke") as CPUParticles2D
		if smoke != null:
			smoke.visible = is_front
			smoke.emitting = is_front
			# Emitter rides the card's bottom-center as it scales.
			smoke.position = card.pivot_offset + Vector2(0, card.size.y * 0.42)


## Snap rotation so the nearest card lands front-center.
func _carousel3d_snap_nearest() -> void:
	var n: int = _carousel3d_cards.size()
	if n == 0:
		return
	var step: float = TAU / float(n)
	# Front-center means card angle a = 0 (mod TAU).
	var k: float = round(_carousel3d_angle / step)
	_carousel3d_target = k * step
	# The card now at front becomes the selection.
	var front_idx: int = int(posmod(-k, n))
	if front_idx >= 0 and front_idx < n:
		_selected_faction = str(_carousel3d_cards[front_idx]["fid"])
		_refresh_card_selection()


## Snap directly to a faction (used on open).
func _carousel3d_snap_to(fid: String, instant := false) -> void:
	var n: int = _carousel3d_cards.size()
	if n == 0:
		return
	var idx := -1
	for i in n:
		if str(_carousel3d_cards[i]["fid"]) == fid:
			idx = i
			break
	if idx < 0:
		return
	var step: float = TAU / float(n)
	# Card i sits at angle + i*step; put it at front (angle 0).
	_carousel3d_target = -float(idx) * step
	if instant:
		_carousel3d_angle = _carousel3d_target
	_selected_faction = fid
	_refresh_card_selection()


## Tap (no drag): pick the front-most card under the touch point.
func _carousel3d_tap_at(pos: Vector2) -> void:
	var best_fid := ""
	var best_depth := -1.0
	var n: int = _carousel3d_cards.size()
	var step: float = TAU / float(n) if n > 0 else TAU
	for i in n:
		var entry: Dictionary = _carousel3d_cards[i]
		var card: Control = entry["node"]
		if not is_instance_valid(card):
			continue
		# Card rect in carousel space (position is top-left, size scaled).
		var rect := Rect2(card.position, card.size * card.scale)
		if rect.has_point(pos):
			var a: float = _carousel3d_angle + float(i) * step
			var depth: float = 0.5 + 0.5 * cos(a)
			if depth > best_depth:
				best_depth = depth
				best_fid = str(entry["fid"])
	if best_fid != "":
		_carousel3d_snap_to(best_fid)


## Refresh pressed highlight on all trading cards.
func _refresh_card_selection() -> void:
	for entry in _carousel3d_cards:
		var card: Button = entry["node"]
		if is_instance_valid(card):
			card.set_pressed_no_signal(str(entry["fid"]) == _selected_faction)
	# The hero job picker follows the selected faction (adventure mode).
	_refresh_hero_jobs()


## Carousel view resized — re-layout the track.
func _on_carousel3d_resized() -> void:
	_carousel3d_layout()


func _active_factions_box() -> PanelContainer:
	# Matches the JS-generated race-toggles61 box. Custom toggle rows
	# (GoldToggle checkmark, drawn — no font dependency) instead of the
	# platform CheckBox, matching the settings screen's chrome.
	# Glow-up 2026-10-02 (Jeremy): larger text and toggles, easier to tap.
	# Jeremy 2026-10-04: compact layout — the old tall rows + loose spacing
	# made this panel a giant dead-space box on iPhone. Rows are now short
	# and flow 2-per-row; header/count share one tight line.
	# 2026-10-04 (later): tightened AGAIN — Jeremy wants title + carousel +
	# factions + name + START on ONE iPhone screen with no scrolling.
	var p := PanelContainer.new()
	var sb := _flat(C_PANEL_BG, C_PANEL_BORDER, 2, 6)
	sb.content_margin_left = _px(8)
	sb.content_margin_right = _px(8)
	sb.content_margin_top = _px(8)
	sb.content_margin_bottom = _px(8)
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _pxi(4))
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _pxi(8))
	head.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_child(head)
	var head_title := _lbl("ACTIVE FACTIONS", 16, C_CREAM, HORIZONTAL_ALIGNMENT_LEFT, false)
	head_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_title)
	# Jeremy 2026-10-04: the count label used to get squeezed to zero width
	# in the HBox and autowrap per-character (vertical "5/5 factions
	# enabled" jank). Fixed min width + no wrapping + right align.
	_race_count_lbl = _lbl("", 16, Color(0.541, 0.478, 0.353), HORIZONTAL_ALIGNMENT_RIGHT, false)
	_race_count_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_race_count_lbl.custom_minimum_size = Vector2(_px(210), 0)
	_race_count_lbl.clip_text = true
	head.add_child(_race_count_lbl)
	_refresh_race_count()
	# Jeremy 2026-10-04: one short line — the old two-line explainer ate
	# vertical space Jeremy needs for the START button.
	var note := _lbl("Disabling factions reduces lag. Min 2.",
		13, Color(0.541, 0.478, 0.353), HORIZONTAL_ALIGNMENT_LEFT, false)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	var rows := HFlowContainer.new()
	rows.add_theme_constant_override("h_separation", _pxi(6))
	rows.add_theme_constant_override("v_separation", _pxi(6))
	rows.alignment = FlowContainer.ALIGNMENT_BEGIN
	vb.add_child(rows)
	_faction_rows.clear()
	for fid in FACTION_ORDER:
		rows.add_child(_faction_toggle_row(fid))
	_refresh_faction_rows()
	return p


## One faction toggle row: toggle Button + gold box with a drawn checkmark.
func _faction_toggle_row(fid: String) -> Button:
	var row := Button.new()
	row.toggle_mode = true
	row.text = ""
	row.focus_mode = Control.FOCUS_NONE
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.custom_minimum_size = Vector2(_px_w(160), _px(46))
	row.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0.25), C_GOLD_DARK, 1, 6))
	row.add_theme_stylebox_override("hover", _flat(Color(0, 0, 0, 0.35), C_GOLD_DARK, 1, 6))
	row.add_theme_stylebox_override("pressed", _flat(Color(0.23, 0.16, 0.07, 0.85), C_GOLD, 2, 6))
	row.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0.25), C_GOLD_DARK, 1, 6))
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = _px(8)
	hb.offset_right = _px(-8)
	hb.alignment = BoxContainer.ALIGNMENT_BEGIN
	hb.add_theme_constant_override("separation", _pxi(10))
	row.add_child(hb)
	# Check box: gold-bordered square, checkmark drawn by GoldToggle
	# (vector lines — always renders, unlike emoji/font glyphs).
	# Jeremy 2026-10-04: SHRINK_CENTER so the box stays a square instead
	# of stretching to the full row height (it rendered as a tall strip).
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(_px(36), _px(36))
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(box)
	var tick := GoldToggle.new()
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tick.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tick)
	var lbl := _lbl(str(FACTION_INFO[fid]["name"]).capitalize(), 16, C_CREAM,
		HORIZONTAL_ALIGNMENT_LEFT, false)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(lbl)
	row.set_pressed_no_signal(_active_factions.has(fid))
	row.toggled.connect(_on_faction_row_toggled.bind(fid))
	_faction_rows[fid] = [box, tick, row]
	return row


## Row toggle -> core faction logic (kept separate so tests can drive
## _on_faction_toggle directly with a plain button).
func _on_faction_row_toggled(on: bool, fid: String) -> void:
	var parts: Array = _faction_rows.get(fid, [])
	var btn: BaseButton = parts[2] if parts.size() > 2 else null
	_on_faction_toggle(btn, fid, on)


## Sync every faction row's box/tick visuals to _active_factions.
func _refresh_faction_rows() -> void:
	for fid in _faction_rows:
		var parts: Array = _faction_rows[fid]
		var box: PanelContainer = parts[0]
		var tick: GoldToggle = parts[1]
		var on: bool = _active_factions.has(fid)
		# set_pressed_no_signal doesn't emit toggled, so redraw explicitly.
		tick.set_pressed_no_signal(on)
		tick.queue_redraw()
		# Jeremy 2026-10-04: _flat() bakes in 14px content margins — inside
		# a 90px checkbox that left ~20px for the checkmark, which drew as
		# a "/" sliver (the "scrunched checkbox" jank). Zero them so the
		# tick fills the box and draws a real checkmark.
		var bsb := _flat(
			Color(0.10, 0.07, 0.03, 0.9) if on else Color(0, 0, 0, 0.45),
			C_GOLD if on else C_GOLD_DARK, 2, 6)
		bsb.content_margin_left = 0.0
		bsb.content_margin_right = 0.0
		bsb.content_margin_top = 0.0
		bsb.content_margin_bottom = 0.0
		box.add_theme_stylebox_override("panel", bsb)


func _on_faction_toggle(cb: BaseButton, fid: String, on: bool) -> void:
	if not on and _active_factions.size() <= 2:
		# Min 2, like the HTML.
		if cb != null:
			cb.set_pressed_no_signal(true)
		return
	if on and not _active_factions.has(fid):
		_active_factions.append(fid)
	elif not on:
		_active_factions.erase(fid)
	_refresh_race_count()
	_refresh_faction_rows()


func _refresh_race_count() -> void:
	if _race_count_lbl != null and is_instance_valid(_race_count_lbl):
		_race_count_lbl.text = "%d/%d factions enabled" % [_active_factions.size(), FACTION_ORDER.size()]


func _on_start_game() -> void:
	# Ruler name stored VERBATIM — no trim, no sanitize (Jeremy's law).
	# Read from the cache: the faction screen (and its field) is freed on the
	# way to world setup, so the field itself may be gone by confirm time.
	var ruler: String = _ruler_name_cache
	if _adventure_setup:
		var hero_name: String = _hero_input.text if _hero_input else ""
		var job_ids := _hero_job_ids()
		var hero_job: String = SimAdventure.default_hero_job(_selected_faction)
		if _hero_job != null and is_instance_valid(_hero_job) \
				and _hero_job.selected >= 0 \
				and _hero_job.selected < job_ids.size():
			hero_job = job_ids[_hero_job.selected]
		adventure_start_requested.emit(_selected_faction, ruler,
			hero_name, hero_job, _hero_gender)
		return
	# Standard flow: faction -> Forge Your World -> START GAME.
	_show_worldsetup()


## "Forge Your World" setup screen (HTML screen-worldsetup parity).
## START GAME emits world_game_requested with the chosen type/size/opts/seed.
func _show_worldsetup() -> void:
	_screen = "worldsetup"
	if not _refitting:
		_fill_boost = 1.0
	# Dedicated screen: clear the faction screen first so world gen never
	# overlaps it (Jeremy 2026-10-02: "World Gen is all fucked up... it just
	# bolts itself on top of the factions selection screen").
	_clear_screen()
	var ws := WorldSetupScreen.new()
	_worldsetup = ws
	ws.setup(_active_factions.duplicate(), _selected_faction)
	ws.world_confirmed.connect(_on_world_confirmed)
	ws.back_pressed.connect(func() -> void: _show_faction(_adventure_setup))
	add_child(ws)


func _on_world_confirmed(wtype: String, size_key: String, opts: Dictionary,
		seed: int) -> void:
	# Verbatim from the cache (see _on_start_game).
	var ruler: String = _ruler_name_cache
	world_game_requested.emit(_selected_faction, ruler, wtype, size_key,
		opts, seed)


# ------------------------------------------------------------------- worlds

## Public entry: show the Saved Worlds screen (called from main.gd).
func show_worlds() -> void:
	_show_worlds()


func _show_worlds() -> void:
	_screen = "worlds"
	if not _refitting:
		_fill_boost = 1.0
	var v := _new_screen(8)
	v.add_child(_h1("Saved Worlds"))
	var slots := SaveSystem.list_slots()
	for s in slots:
		var i: int = s["slot"]
		if bool(s.get("empty", true)):
			v.add_child(_lbl("Slot %d — empty" % (i + 1), 13, C_DIM))
		else:
			var hb := HBoxContainer.new()
			hb.alignment = BoxContainer.ALIGNMENT_CENTER
			hb.add_theme_constant_override("separation", _pxi(8))
			var facs: Array = s.get("factions", [])
			var lbl := _lbl("Slot %d — Day %d, ruler “%s” (%s)" % [
				i + 1, int(s.get("day", 1)), str(s.get("ruler", "?")),
				", ".join(facs)], 13, C_CREAM, HORIZONTAL_ALIGNMENT_LEFT, false)
			hb.add_child(lbl)
			var b_load := _gold_button("Load")
			b_load.custom_minimum_size = Vector2(_px_w(90), _px(72))
			b_load.pressed.connect(func() -> void: continue_requested.emit(i))
			hb.add_child(b_load)
			var b_del := _secondary_button("Delete")
			b_del.custom_minimum_size = Vector2(_px_w(90), _px(72))
			b_del.pressed.connect(func() -> void:
				SaveSystem.delete_slot(i)
				_show_worlds())
			hb.add_child(b_del)
			v.add_child(hb)
	var bb := _secondary_button("‹ BACK")
	bb.pressed.connect(func() -> void: _show_title())
	v.add_child(bb)


# ----------------------------------------------------------------- settings

## Custom graphical toggle for the settings screen (Jeremy 2026-10-02:
## "check boxes need to be larger and more graphical custom").
## Godot's default web font has no checkmark glyph (U+2713 missing), so the
## check is drawn with lines. 52px+ touch target, gold on gold-dark.
class GoldToggle:
	extends Button
	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		text = ""
	func _ready() -> void:
		toggled.connect(queue_redraw)
	func _draw() -> void:
		if not button_pressed:
			return
		var w := size.x
		var h := size.y
		var col := Color(1.0, 0.835, 0.310)  # #ffd54f gold
		var lw := maxf(3.0, w / 11.0)
		# Checkmark: short leg, then long leg.
		draw_line(Vector2(w * 0.26, h * 0.54), Vector2(w * 0.44, h * 0.70),
			col, lw, true)
		draw_line(Vector2(w * 0.44, h * 0.70), Vector2(w * 0.74, h * 0.30),
			col, lw, true)

func _show_settings() -> void:
	_screen = "settings"
	if not _refitting:
		_fill_boost = 1.0
	var v := _new_screen(10)
	# No emoji icon: Godot's web font lacks ⚙️ (tofu boxes on iPhone).
	v.add_child(_h1("Settings"))
	v.add_child(_mdesc("Tune the game to your device. Changes save instantly."))
	v.add_child(_setting_select("AI Aggression",
		["low", "normal", "high"], "ai_aggression",
		{"low": "Low", "normal": "Normal", "high": "High"}))
	v.add_child(_setting_select("Graphics Preset",
		["auto", "low", "medium", "high", "ultra"], "graphics",
		{"auto": "Auto (device scan)", "low": "Low", "medium": "Medium",
		 "high": "High", "ultra": "Ultra"}))
	# Jeremy 2026-10-07: persistent game-speed preference — he asked to
	# slow in-game time (thermal relief). Applies on every world entry;
	# the in-game Speed button cycles AND updates this setting.
	v.add_child(_setting_select("Game Speed",
		[1.0, 0.5, 0.25, 0.125, 2.0], "game_speed",
		{1.0: "1x — normal", 0.5: "0.5x — slower, cooler phone",
		 0.25: "0.25x — turtle, cooler still",
		 0.125: "0.125x — deep turtle, coolest phone", 2.0: "2x — fast"}))
	v.add_child(_setting_select("Ground Detail",
		["auto", "low", "medium", "high", "ultra"], "ground_detail",
		{"auto": "Auto", "low": "Low", "medium": "Medium",
		 "high": "High", "ultra": "Ultra"}))
	v.add_child(_setting_select("Share Diagnostics",
		[false, true], "share_diagnostics",
		{false: "Off", true: "On — help fix bugs"}))
	v.add_child(_mdesc("Crash logs, FPS samples, and hardware info. You choose where it goes. No personal data."))
	v.add_child(_diagnostics_send_row())
	v.add_child(_setting_check("Life Decisions — ask before townsfolk leave, wander off, or join another faction", "life_decisions"))
	v.add_child(_setting_check("Tree Sway — gentle breeze animation on trees", "tree_sway"))
	v.add_child(_setting_check("Music — title theme + dynamic soundtrack", "music"))
	v.add_child(_setting_slider("Music Volume", "music_volume", 0, 100))
	v.add_child(_setting_slider("SFX Volume — swords, horns, coin, spellfire (0 = mute)", "sfx_volume", 0, 100))
	v.add_child(_setting_check("Debug Overlay — FPS, tick timings, entity counts", "debug_overlay"))
	v.add_child(_setting_check("Autosave — periodic save while playing (web exports can't catch tab close)", "autosave"))
	v.add_child(_setting_select("Autosave Every",
		[2, 5, 10, 15, 30], "autosave_minutes",
		{2: "2 minutes", 5: "5 minutes", 10: "10 minutes",
		 15: "15 minutes", 30: "30 minutes"}))
	var bb := _secondary_button("‹ BACK")
	bb.pressed.connect(func() -> void: _show_title())
	v.add_child(bb)


## Card wrapper: every setting row lives in a gold-bordered card, matching
## the main menu's .menu-card chrome.
func _setting_card_wrap(hb: HBoxContainer) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD_BG
	sb.set_border_width_all(_pxi(1))
	sb.border_color = C_CARD_BORDER
	sb.set_corner_radius_all(_pxi(12))
	sb.content_margin_left = _px(18)
	sb.content_margin_right = _px(18)
	sb.content_margin_top = _px(14)
	sb.content_margin_bottom = _px(14)
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(hb)
	return pc


func _setting_row(label_text: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", _pxi(16))
	var lbl := _lbl(label_text, 26, C_CREAM, HORIZONTAL_ALIGNMENT_LEFT, false)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(lbl)
	return hb


func _setting_check(label_text: String, key: String) -> PanelContainer:
	var hb := _setting_row(label_text)
	var tg := GoldToggle.new()
	tg.custom_minimum_size = Vector2(_px(88), _px(88))
	tg.set_pressed_no_signal(bool(_settings.get(key, false)))
	tg.add_theme_stylebox_override("normal",
		_flat(C_INPUT_BG, C_GOLD_DARK, 2, 10))
	tg.add_theme_stylebox_override("hover",
		_flat(C_INPUT_BG.lightened(0.06), C_GOLD, 2, 10))
	tg.add_theme_stylebox_override("pressed",
		_flat(Color(0.32, 0.235, 0.11), C_GOLD_BRIGHT, 2, 10))
	tg.add_theme_stylebox_override("focus",
		_flat(C_INPUT_BG, C_GOLD_BRIGHT, 2, 10))
	tg.toggled.connect(func(on: bool) -> void:
		_settings[key] = on
		_save_settings())
	hb.add_child(tg)
	return _setting_card_wrap(hb)


func _setting_select(label_text: String, options: Array, key: String, labels: Dictionary) -> PanelContainer:
	var hb := _setting_row(label_text)
	var ob := OptionButton.new()
	for o in options:
		ob.add_item(str(labels.get(o, o)), options.find(o))
	var cur: String = str(_settings.get(key, options[0]))
	var sel := 0
	for i in options.size():
		if str(options[i]) == cur:
			sel = i
			break
	ob.selected = sel
	ob.custom_minimum_size = Vector2(_px_w(200), _px(88))
	ob.add_theme_font_size_override("font_size", _pxi(24))
	ob.add_theme_color_override("font_color", C_CREAM)
	ob.add_theme_color_override("font_hover_color", C_GOLD_BRIGHT)
	ob.add_theme_color_override("font_pressed_color", C_GOLD_BRIGHT)
	ob.add_theme_stylebox_override("normal",
		_flat(C_INPUT_BG, C_GOLD_DARK, 2, 10))
	ob.add_theme_stylebox_override("hover",
		_flat(C_INPUT_BG.lightened(0.06), C_GOLD, 2, 10))
	ob.add_theme_stylebox_override("pressed",
		_flat(C_INPUT_BG.darkened(0.06), C_GOLD, 2, 10))
	ob.add_theme_stylebox_override("focus",
		_flat(C_INPUT_BG, C_GOLD_BRIGHT, 2, 10))
	# Style the dropdown popup to match.
	var pop := ob.get_popup()
	pop.add_theme_font_size_override("font_size", _pxi(24))
	pop.add_theme_color_override("font_color", C_CREAM)
	pop.add_theme_color_override("font_hover_color", C_GOLD_BRIGHT)
	ob.item_selected.connect(func(idx: int) -> void:
		_settings[key] = options[idx]
		_save_settings())
	hb.add_child(ob)
	return _setting_card_wrap(hb)


func _setting_slider(label_text: String, key: String, minv: int, maxv: int) -> PanelContainer:
	var hb := _setting_row(label_text)
	var sl := HSlider.new()
	sl.min_value = minv
	sl.max_value = maxv
	sl.step = 1
	sl.value = float(_settings.get(key, maxv))
	sl.custom_minimum_size = Vector2(_px_w(200), _px(72))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Gold track styling.
	var track := StyleBoxFlat.new()
	track.bg_color = C_INPUT_BG
	track.set_corner_radius_all(_pxi(8))
	sl.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.545, 0.412, 0.078, 0.85)  # gold-dark fill
	fill.set_corner_radius_all(_pxi(8))
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	var val := _lbl(str(int(sl.value)), 28, C_GOLD_BRIGHT,
		HORIZONTAL_ALIGNMENT_RIGHT, false)
	val.custom_minimum_size = Vector2(_px(72), 0)
	sl.value_changed.connect(func(vv: float) -> void:
		_settings[key] = int(vv)
		val.text = str(int(vv))
		_save_settings())
	hb.add_child(sl)
	hb.add_child(val)
	return _setting_card_wrap(hb)


## Send Diagnostics row: manual export (HTML btn-send-diagnostics parity).
## On web exports this opens the OS share sheet (the player chooses where
## the report goes); elsewhere the report is copied to the clipboard.
## Requires the Share Diagnostics opt-in first.
func _diagnostics_send_row() -> PanelContainer:
	var hb := _setting_row("Send Diagnostics — share crash logs, FPS samples, and hardware info")
	var btn := _secondary_button("SEND")
	btn.custom_minimum_size = Vector2(_px_w(150), _px(88))
	var note := _lbl("", 20, C_GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_LEFT, false)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# NOTE: the handler is a var-held lambda, not inline in connect(): a
	# multiline lambda inside a call's parens can't dedent-terminate.
	var on_press := func() -> void:
		var diag := get_tree().get_first_node_in_group("cg_diagnostics")
		if diag == null or not diag.has_method("send_now"):
			note.text = "Diagnostics unavailable right now."
			return
		if not bool(_settings.get("share_diagnostics", false)):
			note.text = "Turn Share Diagnostics ON first — nothing is collected until you opt in."
			return
		var method := String(diag.send_now())
		match method:
			"share":
				note.text = "Share sheet opened — you choose where it goes. Thanks!"
			"clipboard":
				note.text = "Diagnostics copied to clipboard — paste it anywhere. Thanks!"
			_:
				note.text = "Couldn't prepare diagnostics."
	btn.pressed.connect(on_press)
	hb.add_child(btn)
	var wrap := _setting_card_wrap(hb)
	# Result note sits under the card.
	var vb := VBoxContainer.new()
	vb.add_child(wrap)
	vb.add_child(note)
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	outer.add_child(vb)
	return outer


# ------------------------------------------------------------------ credits

func _show_credits() -> void:
	_screen = "credits"
	if not _refitting:
		_fill_boost = 1.0
	var v := _new_screen(8)
	v.add_child(_h1("Credits"))
	# HTML screen-credits parity: "Created & led by Ethos", co-lead Jeremy
	# Baker, "A studio of two." — Ethos credited BY NAME, no Meta attribution
	# anywhere in the game (Jeremy's standing rule).
	var c1 := _lbl("Created & led by", 17, Color(0.8, 0.75, 0.6))
	v.add_child(c1)
	var c_ethos := _lbl("Ethos", 30, C_GOLD_BRIGHT)
	_big_shadow(c_ethos, 2)
	v.add_child(c_ethos)
	var c2 := _lbl("Co-lead", 15, Color(0.8, 0.75, 0.6))
	v.add_child(c2)
	v.add_child(_lbl("Jeremy Baker", 21, C_CREAM))
	var t := _lbl("A studio of two.\nCities rise, houses fill, roads are laid.\nDestroy the Hall. Win the war.\n\nNever stop discovering more.\n\nNo microtransactions. No bullshit.", 16,
		Color(0.8, 0.75, 0.6))
	v.add_child(t)
	# Jeremy 2026-10-06: wordfreq attribution (CC BY-SA 4.0) — the lexicon's
	# known-word list is built from Rob Speer's wordfreq English word list.
	var wfl := _lbl("Word list: wordfreq by Rob Speer (CC BY-SA 4.0).", 13,
		Color(0.55, 0.52, 0.45))
	v.add_child(wfl)
	var bb := _secondary_button("‹ BACK")
	bb.pressed.connect(func() -> void: _show_title())
	v.add_child(bb)


# ------------------------------------------------------------------ hearsay

func _show_hearsay() -> void:
	_screen = "hearsay"
	if not _refitting:
		_fill_boost = 1.0
	var v := _new_screen(8)
	v.add_child(_h1("Hearsay"))
	# Jeremy 2026-10-03: explain what hearsay IS, not just show rumors.
	# From HTML source: Hearsay is the chatterbox brain behind every NPC conversation.
	var expl := _lbl("Every loudmouth in this kingdom runs on Hearsay — the chatterbox brain behind every conversation. It's how a gnome thane haggles, a brew matron sasses you, and an elf stays dramatic about absolutely everything.\n\nWhen you talk, Hearsay figures out what you actually meant — sarcasm, lies, insults and all. Each NPC answers in their own personality and current mood, remembers what's happened between you two, and sometimes just brings up a memory out of nowhere.\n\nAll of it happens right on your device. No internet, no cloud — nothing you say ever leaves your phone. Just a very chatty little kingdom.", 15, Color(0.65, 0.6, 0.5))
	expl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	expl.custom_minimum_size = Vector2(_px_w(360), 0)
	v.add_child(expl)
	# Live gossip from the last session when available; static jokes as fallback.
	var body := "Rumor has it the Giant Ass only appears\nwhen the kingdom's morale is lowest.\n\nThe Thicc Moose has never lost a staring contest.\n\nNobody knows what the undead eat.\nNobody wants to ask."
	if not _hearsay_lines.is_empty():
		body = "Whispers from the realm:\n\n" + "\n\n".join(_hearsay_lines)
	var t := _lbl(body, 16, Color(0.75, 0.7, 0.58))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(_px_w(360), 0)
	v.add_child(t)
	var bb := _secondary_button("‹ BACK")
	bb.pressed.connect(func() -> void: _show_title())
	v.add_child(bb)


## Feed live gossip lines (from a save's hearsay) into the menu screen.
var _hearsay_lines: Array[String] = []
func set_hearsay_lines(lines: Array[String]) -> void:
	_hearsay_lines = lines


## Hide the menu (called when the game starts).
func dismiss() -> void:
	# Jeremy 2026-10-02: world gen "bolted to the damn screen even after the
	# game launched". Root cause: WorldSetupScreen is a CanvasLayer, which
	# does NOT inherit visibility from its parent Control — hiding the menu
	# left the CanvasLayer on screen over the running game. Free it here.
	_clear_screen()
	visible = false
	set_process(false)
