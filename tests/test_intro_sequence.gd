extends SceneTree
## Cursing Gnomes — AAA first-boot intro sequence tests (Jeremy 2026-10-11).
## Spec: skippable intro BEFORE the main menu —
##   "Ethos Games presents" (fade in/out) ->
##   Cursing Gnomes logo (fade in/out + gnome chuckle) ->
##   AAA ambient environment (wind/leaves/birds, synthesized loops) ->
##   music fades in over the ambience -> menu.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_intro_sequence.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

const _LS := preload("res://scripts/ui/loading_screen.gd")

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


func _initialize() -> void:
	print("=== Cursing Gnomes intro-sequence tests ===")
	_run_sync_tests()
	print("passed=%d failed=%d" % [_passed, _failed])
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _run_sync_tests() -> void:
	var scr: LoadingScreen = _LS.new()
	root.add_child(scr)

	# 1. Dev team name is ETHOS GAMES (Jeremy 2026-10-11 — decided).
	_check("studio name is ETHOS GAMES",
		LoadingScreen.STUDIO_NAME == "ETHOS GAMES")

	# 2. Beat order matches Jeremy's spec, times strictly increasing.
	var beats: Array = LoadingScreen._INTRO_BEATS
	_check("four beats", beats.size() == 4)
	var kinds: Array[String] = []
	var prev_t0 := -1.0
	var ordered := true
	for b: Dictionary in beats:
		kinds.append(str(b["kind"]))
		var t0 := float(b["t0"])
		if t0 <= prev_t0:
			ordered = false
		prev_t0 = t0
		_check("beat has t0<t1", float(b["t0"]) < float(b["t1"]))
	_check("beat order studio/logo/world/music",
		kinds == ["studio", "logo", "world", "music"])
	_check("beat times strictly increasing", ordered)

	# 3. Intro API: starts in beat 0, skip_ahead walks the beats in order.
	scr.play_first_boot_intro()
	_check("intro mode on", scr._intro_mode)
	_check("starts at beat 0", scr._intro_beat == 0)
	_check("skip 1 -> logo beat", scr.skip_ahead() == 1)
	_check("skip 2 -> world beat", scr.skip_ahead() == 2)
	_check("skip 3 -> music beat", scr.skip_ahead() == 3)

	# 4. Final skip finishes: intro_finished fires, screen frees itself.
	var finished := [false]
	scr.intro_finished.connect(func() -> void: finished[0] = true)
	scr.skip_ahead()  # beat 3 (last) -> _finish_intro()
	_check("intro_finished emitted", finished[0])
	_check("screen queued for free after finish", scr.is_queued_for_deletion())

	# 5. Beat envelopes: alpha 0 at beat edges, 1 mid-beat.
	var scr2: LoadingScreen = _LS.new()
	root.add_child(scr2)
	scr2.play_first_boot_intro()
	scr2._t = 0.0
	_check("studio alpha 0 at t=0", scr2._intro_beat_alpha(0) < 0.01)
	scr2._t = 1.9  # mid studio beat (0.0-3.8)
	_check("studio alpha 1 mid-beat", scr2._intro_beat_alpha(0) > 0.99)
	scr2._t = 3.79
	_check("studio alpha ~0 at beat end", scr2._intro_beat_alpha(0) < 0.05)
	scr2.queue_free()

	# 6. Natural rollover: _process_intro advances beats without taps.
	var scr3: LoadingScreen = _LS.new()
	root.add_child(scr3)
	scr3.play_first_boot_intro()
	scr3._process_intro(4.0, Vector2(800, 600))  # past studio beat end
	_check("natural rollover to logo", scr3._intro_beat == 1)
	scr3._process_intro(4.0, Vector2(800, 600))  # past logo beat end
	_check("natural rollover to world", scr3._intro_beat == 2)
	# Chuckle fires once the logo beat is reached.
	_check("chuckle fired on logo beat", scr3._chuckle_fired)
	scr3.queue_free()

	# 7. Audio hook surface (AudioManager): everything the intro needs.
	var am := AudioManager.new()
	_check("has play_intro_music", am.has_method("play_intro_music"))
	_check("has start_intro_ambience", am.has_method("start_intro_ambience"))
	_check("has stop_intro_ambience", am.has_method("stop_intro_ambience"))
	_check("jeremy track in TRACKS", AudioManager.TRACKS.has("jeremy_main"))
	_check("jeremy music path const",
		AudioManager.JEREMY_MUSIC_PATH == "res://assets/audio/music_jeremy_main.mp3")
	_check("chuckle sfx synthesizes",
		am._synthesize_sfx("gnome_chuckle") != null)
	_check("leaf rustle loop synthesizes",
		am._synth_leaf_rustle_loop() != null)
	_check("leaf loop is 16-bit loop",
		am._synth_leaf_rustle_loop().loop_mode == AudioStreamWAV.LOOP_FORWARD)
	am.queue_free()

	# 8. finish() during a world boot is untouched by intro state.
	var scr4: LoadingScreen = _LS.new()
	root.add_child(scr4)
	scr4.set_progress(0.5, "half")
	scr4.finish()
	_check("world-boot finish still idempotent", scr4._finishing)
	scr4.finish()
	_check("world-boot finish stays finished", scr4._finishing)
	scr4.queue_free()
