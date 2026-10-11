extends SceneTree
## Cursing Gnomes — overworld music rotation + mix discipline tests
## (Jeremy 2026-10-11: Eon_of_dreams.mp3 overworld track; tutorial music
## must not overpower SFX — music is a bed, not the lead).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_music_rotation.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no real audio.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _am: AudioManager = null
var _did_playback := false


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	print("=== Cursing Gnomes music-rotation + mix tests ===")
	_am = AudioManager.new()
	root.add_child(_am)
	_run_sync_tests()


## Playback-touching checks run on the first real frame, when nodes are
## fully inside the tree (AudioStreamPlayer.play() requires it).
func _process(_delta: float) -> bool:
	if not _did_playback:
		_did_playback = true
		_run_playback_tests()
		_finish()
	return false


func _finish() -> void:
	print("passed=%d failed=%d" % [_passed, _failed])
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _run_sync_tests() -> void:
	var am := _am  # already in the tree from _initialize
	am._ensure_core_players()

	# 1. Jeremy's tracks are valid, loadable MP3s in the project.
	var t_main: AudioStream = am._load_track("jeremy_main")
	var t_ow: AudioStream = am._load_track("jeremy_overworld")
	_check("jeremy_main loads", t_main != null)
	_check("jeremy_overworld loads", t_ow != null)
	_check("jeremy_main in TRACKS", AudioManager.TRACKS.has("jeremy_main"))
	_check("jeremy_overworld in TRACKS", AudioManager.TRACKS.has("jeremy_overworld"))

	# 2. Rotation API surface.
	_check("has play_music_crossfade", am.has_method("play_music_crossfade"))
	_check("has start_overworld_rotation",
		am.has_method("start_overworld_rotation"))
	_check("has stop_overworld_rotation",
		am.has_method("stop_overworld_rotation"))
	_check("has play_tutorial_music", am.has_method("play_tutorial_music"))

	# 3. Pool contains both Jeremy tracks (+ title/fifths if present).
	var pool: Array[String] = am._overworld_tracks()
	_check("pool has jeremy_main", pool.has("jeremy_main"))
	_check("pool has jeremy_overworld", pool.has("jeremy_overworld"))
	_check("pool has title", pool.has("title"))
	_check("pool has fifths", pool.has("fifths"))
	var psize := pool.size()
	_check("pool size 4", psize == 4)

	# 4. Shuffle-bag: never the same track twice in a row, and every
	# block of P draws is a full permutation (whole pool cycles first).
	am._ow_bag.clear()
	am._ow_last = ""
	var draws: Array[String] = []
	for i in 3 * psize:
		draws.append(am._next_overworld_track())
	var no_repeat := true
	for i in range(1, draws.size()):
		if draws[i] == draws[i - 1]:
			no_repeat = false
	_check("no consecutive repeats over 3 cycles", no_repeat)
	var full_cycles := true
	for c in 3:
		# slice end is exclusive: block = 4 consecutive draws.
		var block := draws.slice(c * psize, (c + 1) * psize)
		var seen := {}
		for t: String in block:
			seen[t] = true
		if seen.size() != psize:
			full_cycles = false
	_check("each cycle is a full permutation", full_cycles)

	# 5. Bag refill never opens with the track that just played.
	var refill_ok := true
	for r in 20:
		am._ow_bag.clear()
		am._ow_last = "jeremy_main"
		am._refill_ow_bag()
		if am._ow_bag.back() == "jeremy_main":
			refill_ok = false
	_check("refill never opens with last-played", refill_ok)

	# 6. MIX DISCIPLINE: music bed clearly under SFX and ambience,
	# following the user's own volume settings.
	am.music_volume = 0.8
	am.sfx_volume = 0.8
	am._duck_env = 0.0
	var music_db := am._music_target_db()
	var sfx_db := linear_to_db(0.8)
	_check("music under sfx by >= 10 dB", music_db <= sfx_db - 10.0)
	_check("music bed offset is -14 dB",
		AudioManager.MUSIC_BED_OFFSET_DB == -14.0)
	# Ambience sits between: wind = sfx - 12, i.e. over the music bed.
	_check("wind over music bed", (sfx_db - 12.0) > music_db)
	# Ducking: full duck dips the bed another MUSIC_DUCK_DB.
	am._duck_env = 1.0
	var ducked := am._music_target_db()
	_check("duck dips music by duck amount",
		absf((music_db - ducked) - AudioManager.MUSIC_DUCK_DB) < 0.01)
	am._duck_env = 0.0
	# Music muted by user setting -> silent bed.
	am.music_volume = 0.0
	_check("music_volume 0 silences bed", am._music_target_db() <= -79.0)
	am.music_volume = 0.8

	# 8. Tutorial bed resolves to Jeremy's track (file present).
	_check("tutorial hook path exists",
		ResourceLoader.exists(AudioManager.JEREMY_MUSIC_PATH))


func _run_playback_tests() -> void:
	var am := _am
	# 7. Rotation start/stop state (needs live tree for player.play()).
	am.start_overworld_rotation()
	_check("rotation mode on", am._overworld_mode)
	_check("rotation picks a pool track",
		AudioManager.OVERWORLD_POOL.has(am._current_track))
	_check("rotation music playing", am._music_player.playing)
	# Crossfade path: start a second track while the first plays.
	var first := am._current_track
	var other := "title" if first != "title" else "fifths"
	am.play_music_crossfade(other)
	_check("crossfade armed", am._xfade_t >= 0.0)
	# Drive the crossfade to completion headlessly.
	for i in 200:
		am._tick_music_level(0.05)
	_check("crossfade completes", am._xfade_t < 0.0)
	_check("crossfade lands on new track", am._current_track == other)
	am.stop_overworld_rotation()
	_check("rotation mode off", not am._overworld_mode)
	_check("bag cleared on stop", am._ow_bag.is_empty())
	am.stop_music()
	am.queue_free()
