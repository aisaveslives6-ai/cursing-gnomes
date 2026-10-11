extends SceneTree
## Cursing Gnomes — day/night nature ambience audio tests (Jeremy 2026-10-07
## wake lane: "hear the day/night" — the 4-hour day/night cycle was silent;
## nights now get a cricket chorus, days a birdsong bed with a dawn peak).
##
## Covers:
##   - 2 new ambience voices created; total voice count within budget (32)
##   - cricket/bird loops: 16-bit, LOOP_FORWARD, seamless loop point,
##     audible, and pulsed (chirps/syllables, not flat tones)
##   - _nature_targets: night -> crickets, day -> birds, dawn chorus peak,
##     dusk/dawn ramps, menu hour (-1) -> silence
##   - weather suppression: rain/storm/snow quiet the wildlife
##   - integration: bound GameState at 2am fades crickets in, at noon birds
##   - faded-out voice frees; SFX mute silences; menu mode stops both
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_nature_ambience.gd
##
## Exit code 0 = all passed, 1 = any failure.

var _pass := 0
var _fail := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		push_error("[FAIL] " + name)


func _new_audio() -> AudioManager:
	var am := AudioManager.new()
	root.add_child(am)
	am._music_unlocked = true  # pretend iOS tap already happened
	return am


## Windowed peaks (100 ms) — proves the loop pulses (chirps/syllables with
## gaps) instead of droning at constant level.
func _window_peaks(data: PackedByteArray, frames: int) -> Array:
	var peaks: Array = []
	var win := 2205  # 100 ms at 22050 Hz
	var i := 0
	while i < frames:
		var p := 0
		var j := i
		while j < mini(i + win, frames):
			p = maxi(p, absi(data.decode_s16(j * 2)))
			j += 1
		peaks.append(p)
		i += win
	return peaks


func _init() -> void:
	await process_frame
	await process_frame
	var am := _new_audio()

	# --- voices created, within budget ---
	_check(am.get_node_or_null("CricketPlayer") != null, "CricketPlayer exists")
	_check(am.get_node_or_null("BirdPlayer") != null, "BirdPlayer exists")
	_check(am.get_child_count() <= GraphicsTiers.BUDGET_AUDIO_VOICES,
		"voice count within budget (got %d, budget %d)"
		% [am.get_child_count(), GraphicsTiers.BUDGET_AUDIO_VOICES])

	# --- cricket loop stream ---
	var cr: AudioStreamWAV = am._cricket_stream
	_check(cr != null, "cricket stream synthesized")
	_check(cr.format == AudioStreamWAV.FORMAT_16_BITS, "cricket is 16-bit")
	_check(cr.mix_rate == 22050, "cricket 22050 Hz")
	_check(not cr.stereo, "cricket mono")
	_check(cr.loop_mode == AudioStreamWAV.LOOP_FORWARD, "cricket loops forward")
	var cr_frames := int(5.0 * 22050)
	_check(cr.loop_end == cr_frames, "cricket loop_end == frames")
	_check(cr.data.size() == cr_frames * 2, "cricket data size matches")

	# --- bird loop stream ---
	var bd: AudioStreamWAV = am._bird_stream
	_check(bd != null, "bird stream synthesized")
	_check(bd.format == AudioStreamWAV.FORMAT_16_BITS, "bird is 16-bit")
	_check(bd.mix_rate == 22050, "bird 22050 Hz")
	_check(not bd.stereo, "bird mono")
	_check(bd.loop_mode == AudioStreamWAV.LOOP_FORWARD, "bird loops forward")
	var bd_frames := int(8.0 * 22050)
	_check(bd.loop_end == bd_frames, "bird loop_end == frames")
	_check(bd.data.size() == bd_frames * 2, "bird data size matches")

	# --- seamless loop points ---
	for tag in [["cricket", cr, cr_frames], ["bird", bd, bd_frames]]:
		var nm: String = tag[0]
		var wav: AudioStreamWAV = tag[1]
		var fr: int = tag[2]
		var seam := absi(wav.data.decode_s16(0) - wav.data.decode_s16((fr - 1) * 2))
		var tex := 0
		for k in range(1, 4000):
			tex = maxi(tex, absi(wav.data.decode_s16(k * 2) - wav.data.decode_s16((k - 1) * 2)))
		_check(seam <= maxi(int(tex * 1.5), 64),
			"%s loop point seamless (seam %d, texture %d)" % [nm, seam, tex])

	# --- audible + pulsed (chirps/syllables, not flat tones) ---
	for tag in [["cricket", cr, cr_frames], ["bird", bd, bd_frames]]:
		var nm: String = tag[0]
		var wav: AudioStreamWAV = tag[1]
		var fr: int = tag[2]
		var peaks := _window_peaks(wav.data, fr)
		var mx := 0
		var mn := 1 << 30
		for p in peaks:
			mx = maxi(mx, p)
			mn = mini(mn, p)
		_check(mx > 3000, "%s audible (window peak %d)" % [nm, mx])
		_check(mn < 1500, "%s pulsed, not droning (quietest window %d)" % [nm, mn])

	# --- target curves ---
	var t := am._nature_targets(2.0, "clear")
	_check(is_equal_approx(t.x, 0.30), "2am: crickets 0.30")
	_check(is_equal_approx(t.y, 0.0), "2am: birds 0")
	t = am._nature_targets(12.0, "clear")
	_check(is_equal_approx(t.x, 0.0), "noon: crickets 0")
	_check(is_equal_approx(t.y, 0.16), "noon: birds 0.16")
	t = am._nature_targets(6.5, "clear")
	_check(is_equal_approx(t.y, 0.30), "6:30am: dawn chorus peak 0.30")
	_check(is_equal_approx(t.x, 0.0), "6:30am: crickets 0")
	t = am._nature_targets(21.5, "clear")
	_check(is_equal_approx(t.x, 0.15), "9:30pm: crickets ramping in (0.15)")
	t = am._nature_targets(4.5, "clear")
	_check(is_equal_approx(t.x, 0.15), "4:30am: crickets ramping out (0.15)")
	t = am._nature_targets(-1.0, "clear")
	_check(t == Vector2.ZERO, "menu hour: silence")

	# --- weather suppression ---
	t = am._nature_targets(2.0, "rain")
	_check(is_equal_approx(t.x, 0.12), "rain: crickets ducked (0.12)")
	t = am._nature_targets(12.0, "rain")
	_check(is_equal_approx(t.y, 0.04), "rain: birds ducked (0.04)")
	t = am._nature_targets(12.0, "storm")
	_check(is_equal_approx(t.y, 0.016), "storm: birds near-silent (0.016)")
	t = am._nature_targets(12.0, "snow")
	_check(is_equal_approx(t.y, 0.048), "snow: birds thinned (0.048)")

	# --- integration: bound GameState at 2am -> crickets fade in ---
	var gs := GameState.new()
	gs.game_time = (2.0 / 24.0) * Config.DAY_LENGTH_SECONDS
	am.bind_game(gs, "humans")
	for i in 20:
		am._process(0.5)
	var want_db := am._ambience_db(0.30)
	_check(absf(am._cricket_player.volume_db - want_db) < 1.5,
		"2am: cricket crossfade converges (got %.1f dB, want %.1f)"
		% [am._cricket_player.volume_db, want_db])
	_check(am._cricket_player.playing, "2am: cricket voice playing")
	_check(am._bird_player.volume_db <= -79.5, "2am: bird voice silent")

	# --- noon: birds fade in, crickets free their voice ---
	gs.game_time = (12.0 / 24.0) * Config.DAY_LENGTH_SECONDS
	for i in 40:
		am._process(0.5)
	want_db = am._ambience_db(0.16)
	_check(absf(am._bird_player.volume_db - want_db) < 1.5,
		"noon: bird crossfade converges (got %.1f dB, want %.1f)"
		% [am._bird_player.volume_db, want_db])
	_check(not am._cricket_player.playing, "noon: cricket voice freed")

	# --- SFX mute silences nature ---
	am.set_sfx_volume(0.0)
	_check(am._ambience_db(0.30) == -80.0, "muted: nature target -80 dB")
	am.set_sfx_volume(0.8)  # restore

	# --- menu mode stops both ---
	am.to_menu_mode()
	_check(is_equal_approx(am._cricket_target, 0.0), "menu: cricket target 0")
	_check(is_equal_approx(am._bird_target, 0.0), "menu: bird target 0")
	_check(not am._cricket_player.playing, "menu: cricket stopped")
	_check(not am._bird_player.playing, "menu: bird stopped")
	am.queue_free()
	gs.free()

	print("=== test_nature_ambience: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
