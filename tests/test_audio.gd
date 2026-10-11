extends SceneTree
## Cursing Gnomes — audio system tests (headless).
##
## Verifies:
##   - AudioManager initializes without errors
##   - All 5 Jeremy-chosen tracks resolve to real files
##   - Track→moment mapping matches HTML (battle = Strategic March, etc.)
##   - Volume settings work
##   - Mode switching (menu/game) works
##   - Intensity computation responds to combat
##   - iOS unlock logic works
##   - SFX synthesis works

var _pass := 0
var _fail := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		push_error("[FAIL] " + name)


func _init() -> void:
	# --- Track files exist ---
	var tracks := {
		"title": "music_title.mp3",
		"fifths": "music_fifths.mp3",
		"peace": "music_peace.mp3",
		"march": "music_march.mp3",
		"war": "music_war.mp3",
	}
	for key in tracks:
		var path: String = "res://assets/audio/" + tracks[key]
		_check(ResourceLoader.exists(path), "track file exists: " + key + " (" + tracks[key] + ")")

	# --- AudioManager initializes ---
	var am := AudioManager.new()
	root.add_child(am)
	# _ready runs on add_child; wait a frame for deferred init
	await process_frame
	await process_frame

	_check(am != null, "AudioManager created")
	_check(am.get_mode() == "menu", "default mode is menu")
	_check(am.get_current_track() == "", "no track playing initially")

	# --- Track mapping (Jeremy's 5 tracks, correct moments) ---
	_check(AudioManager.TRACKS["title"] == "music_title.mp3", "title track mapped")
	_check(AudioManager.TRACKS["fifths"] == "music_fifths.mp3", "fifths track mapped")
	_check(AudioManager.TRACKS["peace"] == "music_peace.mp3", "peace track mapped")
	_check(AudioManager.TRACKS["march"] == "music_march.mp3", "BATTLE track = Strategic March (march)")
	_check(AudioManager.TRACKS["war"] == "music_war.mp3", "total-war track = World at war (war)")

	# --- Volume settings ---
	am.set_music_volume(0.5)
	_check(is_equal_approx(am.music_volume, 0.5), "music volume set")
	am.set_music_volume(1.5)
	_check(is_equal_approx(am.music_volume, 1.0), "music volume clamped high")
	am.set_music_volume(-0.5)
	_check(is_equal_approx(am.music_volume, 0.0), "music volume clamped low")
	am.set_music_volume(0.8)  # restore

	am.set_sfx_volume(0.3)
	_check(is_equal_approx(am.sfx_volume, 0.3), "sfx volume set")

	# --- Music enable/disable ---
	am.set_music_enabled(false)
	_check(not am.music_enabled, "music disabled")
	_check(not am.is_music_playing(), "music stopped when disabled")
	am.set_music_enabled(true)
	_check(am.music_enabled, "music re-enabled")

	# --- iOS unlock logic ---
	# Simulate blocked autoplay: not unlocked, no track
	am._music_unlocked = false
	am._current_track = "title"
	am.unlock_on_tap()
	_check(am._music_unlocked, "unlock_on_tap sets unlocked")
	# Second call is no-op
	am.unlock_on_tap()
	_check(am._music_unlocked, "unlock_on_tap idempotent")

	# --- Mode switching ---
	# bind_game with null-ish state (use a real GameState)
	var gs := GameState.new()
	am.bind_game(gs, "humans")
	_check(am.get_mode() == "game", "bind_game switches to game mode")
	am.to_menu_mode()
	_check(am.get_mode() == "menu", "to_menu_mode switches back")

	# --- Intensity computation ---
	am.bind_game(gs, "humans")
	# Empty state → zero intensity
	am._update_intensity(0.5)
	_check(is_equal_approx(am.get_intensity(), 0.0), "empty game = zero intensity")

	# Add a player unit in combat → intensity rises
	gs.units.append({
		"alive": true, "faction": "humans", "job": "soldier",
		"x": 100.0, "y": 100.0,
		"target": {"alive": true},
	})
	am._update_intensity(0.5)
	_check(am.get_intensity() > 0.0, "player unit in combat raises intensity")
	var combat_intensity: float = am.get_intensity()

	# Add many more → intensity climbs toward war threshold
	for i in 8:
		gs.units.append({
			"alive": true, "faction": "humans", "job": "soldier",
			"x": 100.0, "y": 100.0,
			"target": {"alive": true},
		})
	for i in 10:
		am._update_intensity(0.5)
	var high_intensity: float = am.get_intensity()
	_check(high_intensity > combat_intensity, "more combat = higher intensity")
	_check(high_intensity >= 0.55, "heavy combat reaches war threshold (0.55)")

	# Clear combat → intensity decays (slow release)
	gs.units.clear()
	var before_decay: float = am.get_intensity()
	for i in 20:
		am._update_intensity(0.5)
	_check(am.get_intensity() < before_decay, "intensity decays when combat ends")
	_check(am.get_intensity() < 0.12, "intensity returns to peace range after combat ends")

	# --- Battle mix thresholds (HTML: peace 0.12→0.35, war 0.55→0.85) ---
	_check(is_equal_approx(AudioManager.PEACE_FADE_START, 0.12), "peace fade start = 0.12 (HTML)")
	_check(is_equal_approx(AudioManager.PEACE_FADE_END, 0.35), "peace fade end = 0.35 (HTML)")
	_check(is_equal_approx(AudioManager.WAR_FADE_START, 0.55), "war fade start = 0.55 (HTML)")
	_check(is_equal_approx(AudioManager.WAR_FADE_END, 0.85), "war fade end = 0.85 (HTML)")

	# --- SFX synthesis ---
	var sfx_click: AudioStreamWAV = am._get_sfx("click")
	_check(sfx_click != null, "click SFX synthesized")
	var sfx_place: AudioStreamWAV = am._get_sfx("place")
	_check(sfx_place != null, "place SFX synthesized")
	var sfx_hit: AudioStreamWAV = am._get_sfx("hit")
	_check(sfx_hit != null, "hit SFX synthesized")
	var sfx_build: AudioStreamWAV = am._get_sfx("build")
	_check(sfx_build != null, "build SFX synthesized")
	var sfx_coin: AudioStreamWAV = am._get_sfx("coin")
	_check(sfx_coin != null, "coin SFX synthesized")
	var sfx_error: AudioStreamWAV = am._get_sfx("error")
	_check(sfx_error != null, "error SFX synthesized")
	var sfx_bogus: AudioStreamWAV = am._get_sfx("nonexistent_sfx_xyz")
	_check(sfx_bogus == null, "unknown SFX returns null")
	# play_sfx should not crash (headless: no audio server, but no error)
	am.play_sfx("click")
	_check(true, "play_sfx does not crash headless")

	# --- Spatial SFX (HTML playSpatial parity: Doppler + distance) ---
	# New synth types exist
	_check(am._get_sfx("whoosh") != null, "whoosh SFX synthesized")
	_check(am._get_sfx("boom") != null, "boom SFX synthesized")
	_check(am._get_sfx("zap") != null, "zap SFX synthesized")
	# Spatial pool created
	_check(am._sfx2d_players.size() == 16, "spatial SFX pool has 16 players")
	# play_spatial_sfx does not crash headless (no camera = origin listener)
	am.play_spatial_sfx("hit", Vector2(100, 100), Vector2.ZERO)
	_check(true, "play_spatial_sfx no-velocity does not crash")
	am.play_spatial_sfx("whoosh", Vector2(500, 0), Vector2(400, 0))
	_check(true, "play_spatial_sfx with velocity does not crash")
	# Far away = skipped silently (beyond 5600)
	am.play_spatial_sfx("hit", Vector2(100000, 100000), Vector2.ZERO)
	_check(true, "play_spatial_sfx far away skipped without crash")
	# Doppler formula sanity: approaching projectile → pitch > 1
	# (verified via code inspection; headless has no audio server to read pitch)

	# --- Total war detection ---
	# Without diplomacy bound, should be false (no crash)
	_check(not am._is_total_war(), "no diplomacy = not total war")

	# --- HTML SFX parity (fix79 const SFX block, verbatim segments) ---
	var html_names := ["bow", "arrow", "bullet", "cannon", "grape", "rocket",
		"mortar", "explode", "hit", "aa", "build", "fire", "rocketFlyby",
		"gateUp", "gateDown", "splash", "hose59", "hiss59", "shoot"]
	for n in html_names:
		var w: AudioStreamWAV = am._get_sfx(n)
		_check(w != null, "HTML SFX synthesized: " + n)
	# explode is the longest combat SFX (HTML: 0.75 s max layer)
	var sfx_explode: AudioStreamWAV = am._get_sfx("explode")
	_check(sfx_explode.data.size() == int(0.75 * 22050),
		"explode duration = 0.75s (HTML max layer)")
	# hit is short (HTML: 0.08 s max layer)
	var sfx_hit2: AudioStreamWAV = am._get_sfx("hit")
	_check(sfx_hit2.data.size() == int(0.08 * 22050),
		"hit duration = 0.08s (HTML max layer)")
	# mixed layers are non-silent
	var peak := 0
	for i in sfx_explode.data.size():
		peak = maxi(peak, abs(int(sfx_explode.data[i]) - 128))
	_check(peak > 10, "explode is non-silent (mixed layers)")
	# gateUp is the longest SFX overall (HTML: 1.2 s max layer)
	var sfx_gate: AudioStreamWAV = am._get_sfx("gateUp")
	_check(sfx_gate.data.size() == int(1.2 * 22050),
		"gateUp duration = 1.2s (HTML max layer)")
	# spatial play path handles the new names headless
	am.play_spatial_sfx("cannon", Vector2(100, 100), Vector2.ZERO)
	_check(true, "play_spatial_sfx cannon does not crash")
	am.play_spatial_sfx("explode", Vector2(100, 100), Vector2.ZERO)
	_check(true, "play_spatial_sfx explode does not crash")

	# --- SFX trigger wiring (2026-10-06) ---
	# "launch" (nuke launch) previously fell through to null and played
	# silently; it now aliases the verbatim HTML rocket segments.
	var sfx_launch: AudioStreamWAV = am._get_sfx("launch")
	_check(sfx_launch != null, "launch SFX synthesized (no longer silent)")
	var sfx_rocket: AudioStreamWAV = am._get_sfx("rocket")
	_check(sfx_launch.data.size() == sfx_rocket.data.size(),
		"launch aliases HTML rocket segments (same duration)")
	var launch_peak := 0
	for i in sfx_launch.data.size():
		launch_peak = maxi(launch_peak, abs(int(sfx_launch.data[i]) - 128))
	_check(launch_peak > 10, "launch is non-silent")
	am.play_spatial_sfx("launch", Vector2(100, 100), Vector2.ZERO)
	_check(true, "play_spatial_sfx launch does not crash")
	# Names mapped by the projectile launch/impact wiring synthesize too
	for n in ["bullet", "grape", "mortar", "aa", "rocketFlyby"]:
		_check(am._get_sfx(n) != null, "mapped SFX synthesized: " + n)
	am.play_spatial_sfx("rocketFlyby", Vector2(500, 0), Vector2(400, 0))
	_check(true, "play_spatial_sfx rocketFlyby with velocity does not crash")

	# --- Cleanup ---
	am.queue_free()

	print("[test_audio] %d passed, %d failed" % [_pass, _fail])
	if _fail > 0:
		quit(1)
	else:
		quit(0)
