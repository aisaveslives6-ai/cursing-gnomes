extends Node2D
## Cursing Gnomes — entry point (Milestone 7: polish & ship).
##
## Boots to the main menu first (matching the HTML version's flow).
## New Game / Continue / Sandbox / Adventure instantiate the world scene;
## the menu stays alive underneath so Back returns to it.


const WORLD_SCENE := "res://scenes/world/world.tscn"
## Preloaded (not class_name) so it resolves before the editor class cache rebuilds.
const _UITapSfxScript := preload("res://scripts/audio/ui_tap_sfx.gd")
const _LoadingScreenScript := preload("res://scripts/ui/loading_screen.gd")

var _menu: MainMenu
var _world: Node = null
var _weather: WeatherFX = null
var _snow: SnowBlanket = null
var _audio: AudioManager
var _music_hint: Label = null
var _diagnostics: Diagnostics = null
## Re-entrancy guard: one world boot at a time (double-taps can't stack boots).
var _booting := false


func _ready() -> void:
	print("[Cursing Gnomes] Main scene ready. Godot %s" % Engine.get_version_info().string)
	print("[Cursing Gnomes] Factions: ", Config.FACTIONS.keys())
	# Audio first (Jeremy: "Music should play as soon as the game is opened.")
	_audio = AudioManager.new()
	_audio.name = "AudioManager"
	add_child(_audio)
	_audio.music_blocked.connect(_on_music_blocked)
	_audio.music_started.connect(_on_music_started)
	# Global UI tap sounds (2026-10-09): every Button press clicks.
	var tap: Node = _UITapSfxScript.new()
	tap.name = "UITapSfx"
	add_child(tap)
	# AAA first-boot intro (Jeremy 2026-10-11): skippable cinematic
	# (Ethos Games presents -> logo + chuckle -> living world w/ ambience
	# -> music fade-in) BEFORE the main menu. The menu appears when it ends.
	var intro: LoadingScreen = _LoadingScreenScript.new()
	intro.name = "BootIntro"
	intro.set_audio(_audio)
	add_child(intro)
	intro.intro_finished.connect(_show_menu)
	intro.play_first_boot_intro()
	# Try autoplay; iOS Safari will block until first tap (the intro's own
	# beats start audio on tap too, and unlock_on_tap resumes the track).
	_audio.try_autoplay("title")


func _input(event: InputEvent) -> void:
	# iOS audio unlock: first tap anywhere starts the music.
	if event is InputEventScreenTouch and event.pressed:
		_audio.unlock_on_tap()
	elif event is InputEventMouseButton and event.pressed:
		_audio.unlock_on_tap()


func _on_music_blocked() -> void:
	# iOS Safari blocked autoplay — show "tap anywhere for music" (like HTML).
	if _music_hint != null:
		return
	_music_hint = Label.new()
	# iPhone-safe plain text (Godot web font lacks emoji; Jeremy 2026-10-03).
	_music_hint.text = "tap anywhere for music"
	_music_hint.add_theme_font_size_override("font_size", 22)
	_music_hint.add_theme_color_override("font_color", Color(0.8, 0.72, 0.5, 0.9))
	# Top-right, above everything (CanvasLayer)
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "MusicHintLayer"
	layer.add_child(_music_hint)
	_music_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_music_hint.position = Vector2(-260, 12)
	add_child(layer)
	_music_hint.name = "MusicHint"


func _on_music_started() -> void:
	# Hide the hint once music is playing.
	if _music_hint != null and is_instance_valid(_music_hint):
		var layer := _music_hint.get_parent()
		_music_hint.queue_free()
		_music_hint = null
		if layer != null and is_instance_valid(layer):
			layer.queue_free()


func _show_menu(screen := "") -> void:
	_clear_world()
	if _audio != null:
		_audio.to_menu_mode()
	if _menu == null:
		_menu = MainMenu.new()
		_menu.name = "MainMenu"
		add_child(_menu)
		_menu.new_game_requested.connect(_on_new_game)
		_menu.continue_requested.connect(_on_continue)
		_menu.sandbox_requested.connect(_on_sandbox)
		_menu.adventure_start_requested.connect(_on_adventure_start)
		_menu.world_game_requested.connect(_on_world_game)
		_menu.settings_changed.connect(_on_settings_changed)
		# Apply saved audio settings immediately
		_apply_audio_settings(_menu.get_setting("music", true), _menu.get_setting("music_volume", 80), _menu.get_setting("sfx_volume", 80))
	# Opt-in diagnostics (HTML WATCHDOG-77 telemetry parity): consent-gated,
	# nothing collected until the player turns it on in Settings.
	if _diagnostics == null:
		_diagnostics = Diagnostics.new()
		_diagnostics.name = "Diagnostics"
		add_child(_diagnostics)
	_sync_diagnostics()
	_menu.visible = true
	_menu.set_process(true)
	if screen == "worlds" and _menu.has_method("show_worlds"):
		_menu.show_worlds()
	elif _menu.has_method("show_title"):
		# Dismiss clears the screen (frees worldsetup CanvasLayer etc.), so
		# rebuild the title screen on return — never a blank menu.
		_menu.show_title()


func _clear_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	if _weather != null and is_instance_valid(_weather):
		_weather.queue_free()
	_weather = null
	if _snow != null and is_instance_valid(_snow):
		_snow.queue_free()
	_snow = null


func _start_world(player_faction: String, ruler_name: String) -> void:
	_menu.dismiss()
	_clear_world()
	var world: World = await _boot_world_with_loading()
	if world == null or not is_instance_valid(world):
		return
	_world = world
	_finish_world_start(world, player_faction, ruler_name)


## Jeremy 2026-10-10: animated loading screen. Boots the world scene in
## stages while the screen paints REAL progress — never a fake timer:
## threaded asset load (0-18%), World's staged boot stages (18-88%),
## post-boot wiring (88-100%). Returns the booted world, or null if the
## boot failed/was superseded. The caller wires the world, then lets
## _loading_screen_done() fade the screen out over the live world.
func _boot_world_with_loading() -> World:
	if _booting:
		return null
	_booting = true
	var screen: LoadingScreen = _LoadingScreenScript.new()
	screen.name = "LoadingScreen"
	add_child(screen)
	screen.set_progress(0.0, "Loading world assets…")
	# Paint the screen once before the heavy work begins.
	await get_tree().process_frame
	await get_tree().process_frame
	# Stage 1: real asset progress from the threaded loader.
	var packed: PackedScene = null
	ResourceLoader.load_threaded_request(WORLD_SCENE)
	var deadline := Time.get_ticks_msec() + 90000
	while true:
		var prog: Array = []
		var st := ResourceLoader.load_threaded_get_status(WORLD_SCENE, prog)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			packed = ResourceLoader.load_threaded_get(WORLD_SCENE) as PackedScene
			break
		if st == ResourceLoader.THREAD_LOAD_FAILED \
				or Time.get_ticks_msec() > deadline:
			break
		var p := 0.0
		if not prog.is_empty():
			p = clampf(float(prog[0]), 0.0, 1.0)
		screen.set_progress(0.18 * p, "Loading world assets…")
		await get_tree().process_frame
	if packed == null:
		# Threaded path failed — honest synchronous fallback.
		packed = load(WORLD_SCENE) as PackedScene
	if packed == null:
		screen.finish()
		_booting = false
		return null
	var world: World = packed.instantiate() as World
	if world == null:
		screen.finish()
		_booting = false
		return null
	# Poll backup: the screen reads world.boot_frac/boot_label every frame,
	# so a missed or reordered boot_progress signal can never strand the bar.
	screen.bind_world(world)
	# Stage 2: World's _ready yields a frame per boot stage and emits real
	# stage progress; the screen maps it onto the bar. Connected before
	# add_child so no stage can be missed. The world freezes the tree while
	# it boots (the screen animates through it on PROCESS_MODE_ALWAYS).
	world.staged_boot = true
	world.boot_progress.connect(_on_world_boot_progress.bind(screen))
	add_child(world)
	# Watchdog: if the staged boot ever hangs or errors mid-build, unfreeze
	# and walk back to the menu instead of stranding the player on a
	# frozen loading screen. No-op on a healthy boot (create_timer runs on
	# process_always, so it fires even while the tree is frozen).
	var watchdog := get_tree().create_timer(180.0)
	watchdog.timeout.connect(_on_boot_watchdog.bind(world, screen))
	await world.boot_finished
	# Defensive: the world unpauses itself on success; never leave the
	# tree frozen if the signal path changed.
	get_tree().paused = false
	world.quit_to_menu_requested.connect(_on_quit_to_menu)
	# The bar sits at the last world stage ("Ready", 88%) while the quick
	# post-boot wiring runs; _loading_screen_done() takes it to 100%.
	world.set_meta("cg_loading_screen", screen)
	_booting = false
	return world


## Watchdog for the staged world boot: if the boot hangs or errors before
## boot_finished, unfreeze the tree, fade the loading screen, and walk back
## to the menu instead of stranding the player on a frozen screen. Healthy
## boots hit boot_finished long before the timer and this is a no-op.
func _on_boot_watchdog(world: World, screen: LoadingScreen) -> void:
	if is_instance_valid(world) and bool(world.get("booted")):
		return
	get_tree().paused = false
	_booting = false
	# The hung world was added to the tree but never assigned to _world,
	# so free it directly before walking back to the menu.
	if is_instance_valid(world):
		world.queue_free()
	if is_instance_valid(screen):
		screen.set_progress(0.0, "The world failed to load.")
		screen.finish()
	_show_menu()
	_menu.flash_notice("The world failed to load. Your saves are untouched.")


## Maps World boot-stage progress (0..1 across its heavy stages) onto the
## loading bar's world-boot band (18-88%).
func _on_world_boot_progress(frac: float, label: String, screen: LoadingScreen) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	screen.set_progress(0.18 + clampf(frac, 0.0, 1.0) * 0.70, label)


## Post-boot wiring shared by the new/sandbox/adventure/world-game paths:
## configure, menu settings, audio, weather, snow — then fade the loading
## screen out over the live world.
func _finish_world_start(world: World, player_faction: String, ruler_name: String) -> void:
	# World._ready() ran staged on add_child and set up all factions.
	# Configure the player's faction + ruler name verbatim afterwards.
	world.configure(player_faction, ruler_name)
	# Push player preferences (AI aggression etc.) into the sim.
	var game: GameState = world.get("game") as GameState
	_push_menu_settings(game)
	# Battle music: bind audio to game state for intensity-driven crossfade.
	if _audio != null and game != null:
		_audio.bind_game(game, player_faction)
		_wire_sfx_bus(game)
	# Jeremy 2026-10-11: tutorial music bed — wire the AudioManager so the
	# first-time tour fades Jeremy's track in (or continues it seamlessly
	# from the boot intro). The 2s offer delay guarantees this lands before
	# the player can start the tour.
	var tut = world.get("tutorial")
	if tut != null and tut.has_method("set_audio"):
		tut.set_audio(_audio)
	# Weather + day/night polish layer.
	_weather = WeatherFX.new()
	_weather.name = "WeatherFX"
	world.add_child(_weather)
	_weather.setup(world.get("game") as GameState)
	_apply_weather_graphics()
	_wire_weather_audio()
	# Seasonal snow blanket (winter whitens the world).
	_snow = SnowBlanket.new()
	_snow.name = "SnowBlanket"
	world.add_child(_snow)
	_snow.setup(game)
	await _loading_screen_done(world)


## Fades the loading screen out over the finished world. Lets the full bar
## paint for a beat first so the handoff never looks cut off.
func _loading_screen_done(world: Node) -> void:
	var screen: LoadingScreen = world.get_meta("cg_loading_screen", null) as LoadingScreen
	if screen == null or not is_instance_valid(screen):
		return
	screen.set_progress(1.0, "Ready")
	await get_tree().process_frame
	await get_tree().process_frame
	screen.finish()


## Graphics-tier particle budget for the weather layer (world owns the
## resolved tier; WeatherFX is added here, after world._ready).
func _apply_weather_graphics() -> void:
	if _weather == null or _world == null:
		return
	var tier := "medium"
	if _world.has_method("get_graphics_tier"):
		tier = String(_world.get_graphics_tier())
	_weather.set_particle_mul(float(GraphicsTiers.knobs(tier)["particle_mul"]))


## Connect weather -> audio: ambience beds follow weather_changed, thunder
## claps sync to lightning strikes (flash now, rumble after a beat).
func _wire_weather_audio() -> void:
	if _weather == null or _audio == null:
		return
	if not _weather.weather_changed.is_connected(_audio.set_weather):
		_weather.weather_changed.connect(_audio.set_weather)
	if not _weather.lightning_struck.is_connected(_audio.on_lightning_struck):
		_weather.lightning_struck.connect(_audio.on_lightning_struck)


## Connect the game's spatial-SFX bus to the audio manager (HTML playSpatial parity).
func _wire_sfx_bus(game: GameState) -> void:
	if game == null or game.bus == null:
		return
	if not game.bus.sfx_spatial.is_connected(_audio.play_spatial_sfx):
		game.bus.sfx_spatial.connect(_audio.play_spatial_sfx)


func _on_new_game(faction: String, ruler_name: String) -> void:
	# All 5 factions are always active in the sim (Jeremy's "no limits"
	# rule). The player picks their faction; the world runs all five.
	_start_world(faction, ruler_name)


func _on_continue(slot: int) -> void:
	var data := SaveSystem.load_slot(slot)
	if data.is_empty():
		return
	_menu.dismiss()
	_clear_world()
	var world: World = await _boot_world_with_loading()
	if world == null or not is_instance_valid(world):
		return
	_world = world
	# World._ready() builds the demo; load_from_data replaces it with the save.
	if not _world.load_from_data(data):
		# Jeremy 2026-10-06 (launch readiness): a corrupt or incompatible
		# save must NEVER strand the player in a silent demo world. Back
		# out to the menu with a visible notice; the slot file is untouched.
		var reason := SaveSystem.last_reject_reason()
		var msg := "That save couldn't be loaded"
		if reason == "newer_build":
			msg += " — it was made by a newer build."
		else:
			msg += " — the file is damaged."
		msg += " Your other saves are untouched."
		await _loading_screen_done(world)
		_show_menu()
		_menu.flash_notice(msg)
		return
	var game: GameState = _world.get("game") as GameState
	# Settings are live preferences (not per-save): re-push the menu's
	# current snapshot even on continue.
	_push_menu_settings(game)
	if _audio != null and game != null:
		_audio.bind_game(game, str(data.get("player_faction", "humans")))
		_wire_sfx_bus(game)
	_weather = WeatherFX.new()
	_weather.name = "WeatherFX"
	_world.add_child(_weather)
	_weather.setup(game)
	_apply_weather_graphics()
	_wire_weather_audio()
	# Seasonal snow blanket (winter whitens the world).
	_snow = SnowBlanket.new()
	_snow.name = "SnowBlanket"
	_world.add_child(_snow)
	_snow.setup(game)
	await _loading_screen_done(world)


func _on_sandbox() -> void:
	# Sandbox: all factions, NO player faction — pure observe-only
	# autonomous sim (HTML sandboxMode: playerRace = null). An empty
	# player faction arms the SimSandbox director in world.configure().
	_start_world("", "")


## The in-game drawer asked to return to the menu (autosave already ran).
func _on_quit_to_menu(target_screen: String = "") -> void:
	get_tree().paused = false
	_show_menu(target_screen)


func _on_adventure_start(faction: String, ruler_name: String,
		hero_name: String, hero_job: String, hero_gender: String = "male") -> void:
	# Adventure mode: the living world boots normally, then the hero RPG
	# layer (quests, dungeons, gear) attaches on top of it.
	get_tree().set_meta("cg_hero_gender", hero_gender)
	await _start_world(faction, ruler_name)
	if _world != null and _world.has_method("start_adventure"):
		_world.start_adventure(hero_name, hero_job, hero_gender)


## "Forge Your World" setup screen confirmed: stash worldgen options on the
## SceneTree so World._ready() can read them, then boot normally.
func _on_world_game(faction: String, ruler_name: String, wtype: String,
		size_key: String, opts: Dictionary, seed: int) -> void:
	get_tree().set_meta("cg_worldgen", {
		"type": wtype, "size": size_key, "opts": opts, "seed": seed})
	# Debug overlay flag: menu setting -> tree meta (URL ?debug=1 overrides).
	if _menu != null:
		get_tree().set_meta("cg_debug_overlay",
			bool(_menu.get_setting("debug_overlay", false)))
	_start_world(faction, ruler_name)


func _on_settings_changed(settings: Dictionary) -> void:
	_apply_audio_settings(settings.get("music", true), settings.get("music_volume", 80), settings.get("sfx_volume", 80))
	_sync_diagnostics()
	# Push live preferences into the running game so sim systems (AI
	# aggression, ...) react without a restart.
	if _world != null and is_instance_valid(_world):
		var game: GameState = _world.get("game") as GameState
		if game != null:
			game.settings = settings.duplicate()


## Push the menu's settings snapshot into a GameState so the sim can
## consume player preferences (AI aggression, ...).
func _push_menu_settings(game: GameState) -> void:
	if game == null or _menu == null:
		return
	game.settings = _menu.get_settings_snapshot()


## Push the Share Diagnostics opt-in into the Diagnostics node (and make
## sure the anonymous player ID is persisted + visible to the menu).
func _sync_diagnostics() -> void:
	if _diagnostics == null or _menu == null:
		return
	var on := bool(_menu.get_setting("share_diagnostics", false))
	_diagnostics.configure(on)
	if on:
		_menu.set_setting("diagnostics_id", Diagnostics.ensure_player_id())


func _apply_audio_settings(music_on: bool, music_vol: int, sfx_vol: int = 80) -> void:
	if _audio == null:
		return
	_audio.set_music_enabled(bool(music_on))
	_audio.set_music_volume(float(music_vol) / 100.0)
	_audio.set_sfx_volume(float(sfx_vol) / 100.0)


func _process(_delta: float) -> void:
	pass
