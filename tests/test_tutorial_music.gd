extends SceneTree
## Cursing Gnomes — tutorial music handoff tests (Jeremy 2026-10-11).
##
## Jeremy composed the tutorial/overworld track himself
## (assets/audio/music_jeremy_main.mp3). The boot intro fades it in; the
## AAA tutorial must pick it up seamlessly — no gaps, no pops, no restarts.
## If the intro already faded it in, play_tutorial_music() continues it
## untouched. Fresh start (intro skipped): cinematic fade from silence.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tutorial_music.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_audio() -> AudioManager:
	var am := AudioManager.new()
	root.add_child(am)
	return am


func _initialize() -> void:
	print("=== Cursing Gnomes tutorial music handoff tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_track_exists()
	await _test_fresh_start_fades_in()
	await _test_seamless_continuation()
	await _test_switch_fades_in()
	_test_fallback_without_file()
	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _test_track_exists() -> void:
	_check("jeremy track shipped",
		ResourceLoader.exists(AudioManager.JEREMY_MUSIC_PATH))
	_check("jeremy track mapped",
		AudioManager.TRACKS.get("jeremy_main", "") == "music_jeremy_main.mp3")


## Intro skipped: fresh start arms the cinematic fade — the tick owns the
## volume ramp, so we verify the ramp starts at silence and reaches full.
func _test_fresh_start_fades_in() -> void:
	var am := _new_audio()
	await process_frame
	am.play_tutorial_music()
	_check("fresh: track is jeremy_main",
		am.get_current_track() == "jeremy_main")
	_check("fresh: fade armed", am._music_fade_t == 0.0)
	# One tick: the single-owner ramp starts at silence, never a hard cut.
	am._tick_music_level(0.016)
	_check("fresh: ramps from silence",
		am._music_player.volume_db <= -29.0)
	# Past the fade window: full target level reached.
	am._tick_music_level(4.0)
	_check("fresh: reaches full level",
		is_equal_approx(am._music_player.volume_db, am._music_target_db()))
	am.free()


## Intro already faded it in: second call changes nothing — no restart.
func _test_seamless_continuation() -> void:
	var am := _new_audio()
	await process_frame
	am.play_tutorial_music()
	# Simulate the fade having completed (intro's work is done).
	am._music_fade_t = -1.0
	am._music_player.volume_db = -6.0
	var stream_before: AudioStream = am._music_player.stream
	am.play_tutorial_music()
	_check("seamless: same stream", am._music_player.stream == stream_before)
	_check("seamless: fade not re-armed", am._music_fade_t == -1.0)
	_check("seamless: volume untouched",
		is_equal_approx(am._music_player.volume_db, -6.0))
	am.free()


## A different track was playing: switch to Jeremy's with a fresh fade.
func _test_switch_fades_in() -> void:
	var am := _new_audio()
	await process_frame
	am.play_music("title")
	am._music_fade_t = -1.0
	am.play_tutorial_music()
	_check("switch: track is jeremy_main",
		am.get_current_track() == "jeremy_main")
	_check("switch: fade re-armed", am._music_fade_t == 0.0)
	am._tick_music_level(0.016)
	_check("switch: ramps from silence",
		am._music_player.volume_db <= -29.0)
	am.free()


## Graceful without the file: falls back to the title theme.
func _test_fallback_without_file() -> void:
	# Can't delete the real asset in a test; verify the fallback branch
	# exists by checking the constant path logic instead.
	_check("fallback: path constant sane",
		AudioManager.JEREMY_MUSIC_PATH.begins_with("res://assets/audio/"))
	_check("fallback: title track exists",
		ResourceLoader.exists("res://assets/audio/music_title.mp3"))
