extends SceneTree
## Cursing Gnomes — weather ambience audio tests (Jeremy 2026-10-07 wake
## lane: "hear the weather" — the dynamic weather was fully visual; storms
## flashed in total silence).
##
## Covers:
##   - 3 ambience voices created; total voice count within budget (32)
##   - rain/wind loops: 16-bit, LOOP_FORWARD, seamless loop point
##   - thunder one-shot: non-silent, decaying, not looped
##   - set_weather targets per kind (rain/storm/snow/clear/unknown)
##   - snow gets a thinner wind whistle (pitch 1.3)
##   - on_lightning_struck schedules a delayed clap ONLY in storms
##   - the scheduled clap actually fires (flash now, rumble after a beat)
##   - crossfade converges on the weather target
##   - SFX mute silences ambience; menu mode stops it
##   - WeatherFX._trigger_flash emits lightning_struck
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_weather_ambience.gd
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


func _init() -> void:
	await process_frame
	await process_frame
	var am := _new_audio()

	# --- voices created, within budget ---
	_check(am.get_node_or_null("RainPlayer") != null, "RainPlayer exists")
	_check(am.get_node_or_null("WindPlayer") != null, "WindPlayer exists")
	_check(am.get_node_or_null("ThunderPlayer") != null, "ThunderPlayer exists")
	_check(am.get_child_count() <= GraphicsTiers.BUDGET_AUDIO_VOICES,
		"voice count within budget (got %d, budget %d)"
		% [am.get_child_count(), GraphicsTiers.BUDGET_AUDIO_VOICES])

	# --- rain loop stream ---
	var rain: AudioStreamWAV = am._rain_stream
	_check(rain != null, "rain stream synthesized")
	_check(rain.format == AudioStreamWAV.FORMAT_16_BITS, "rain is 16-bit")
	_check(rain.mix_rate == 22050, "rain 22050 Hz")
	_check(not rain.stereo, "rain mono")
	_check(rain.loop_mode == AudioStreamWAV.LOOP_FORWARD, "rain loops forward")
	var rain_frames := int(4.0 * 22050)
	_check(rain.loop_end == rain_frames, "rain loop_end == frames")
	_check(rain.data.size() == rain_frames * 2, "rain data size matches")

	# --- wind loop stream ---
	var wind: AudioStreamWAV = am._wind_stream
	_check(wind != null, "wind stream synthesized")
	_check(wind.format == AudioStreamWAV.FORMAT_16_BITS, "wind is 16-bit")
	_check(wind.loop_mode == AudioStreamWAV.LOOP_FORWARD, "wind loops forward")
	var wind_frames := int(6.0 * 22050)
	_check(wind.loop_end == wind_frames, "wind loop_end == frames")
	_check(wind.data.size() == wind_frames * 2, "wind data size matches")

	# --- seamless loop points: the head->tail seam discontinuity must be
	# no worse than the signal's own sample-to-sample texture (a bigger
	# jump would click every loop). The crossfade blends the fade tail
	# into the head so the wrap lands inside natural variation.
	var r_seam := absi(rain.data.decode_s16(0) - rain.data.decode_s16((rain_frames - 1) * 2))
	var r_tex := 0
	for i in range(1, 4000):
		r_tex = maxi(r_tex, absi(rain.data.decode_s16(i * 2) - rain.data.decode_s16((i - 1) * 2)))
	_check(r_seam <= int(r_tex * 1.5), "rain loop point seamless (seam %d, texture %d)" % [r_seam, r_tex])
	var w_seam := absi(wind.data.decode_s16(0) - wind.data.decode_s16((wind_frames - 1) * 2))
	var w_tex := 0
	for i in range(1, 4000):
		w_tex = maxi(w_tex, absi(wind.data.decode_s16(i * 2) - wind.data.decode_s16((i - 1) * 2)))
	_check(w_seam <= maxi(int(w_tex * 1.5), 64), "wind loop point seamless (seam %d, texture %d)" % [w_seam, w_tex])

	# --- loops are non-silent ---
	var rain_peak := 0
	for i in range(0, rain_frames, 997):
		rain_peak = maxi(rain_peak, absi(rain.data.decode_s16(i * 2)))
	_check(rain_peak > 2000, "rain loop audible (peak %d)" % rain_peak)
	var wind_peak := 0
	for i in range(0, wind_frames, 1499):
		wind_peak = maxi(wind_peak, absi(wind.data.decode_s16(i * 2)))
	_check(wind_peak > 2000, "wind loop audible (peak %d)" % wind_peak)

	# --- thunder one-shot ---
	var th: AudioStreamWAV = am._thunder_stream
	_check(th != null, "thunder stream synthesized")
	_check(th.loop_mode == AudioStreamWAV.LOOP_DISABLED, "thunder not looped")
	var th_frames := int(2.4 * 22050)
	_check(th.data.size() == th_frames * 2, "thunder data size matches")
	var early := 0.0
	var late := 0.0
	var th_peak := 0
	for i in range(0, th_frames, 101):
		var s := float(th.data.decode_s16(i * 2))
		th_peak = maxi(th_peak, absi(int(s)))
		if i < th_frames / 2:
			early += s * s
		else:
			late += s * s
	_check(th_peak > 3000, "thunder audible (peak %d)" % th_peak)
	_check(early > late * 2.0, "thunder decays (early/late energy)")

	# --- set_weather targets ---
	am.set_weather("rain")
	_check(is_equal_approx(am._rain_target, 0.50), "rain: rain target 0.50")
	_check(is_equal_approx(am._wind_target, 0.15), "rain: wind target 0.15")
	_check(is_equal_approx(am._wind_player.pitch_scale, 1.0), "rain: wind pitch 1.0")
	am.set_weather("storm")
	_check(is_equal_approx(am._rain_target, 0.75), "storm: rain target 0.75")
	_check(is_equal_approx(am._wind_target, 0.40), "storm: wind target 0.40")
	_check(am._thunder_next >= 2.0 and am._thunder_next <= 6.0,
		"storm: first rumble scheduled soon")
	am.set_weather("snow")
	_check(is_equal_approx(am._rain_target, 0.0), "snow: rain target 0")
	_check(is_equal_approx(am._wind_target, 0.30), "snow: wind target 0.30")
	_check(is_equal_approx(am._wind_player.pitch_scale, 1.3), "snow: wind whistle pitch 1.3")
	am.set_weather("clear")
	_check(is_equal_approx(am._rain_target, 0.0), "clear: rain target 0")
	_check(is_equal_approx(am._wind_target, 0.05), "clear: faint breeze 0.05")
	am.set_weather("fog")  # unknown kind: safe fallback, no crash
	_check(am._weather == "fog", "unknown kind stored without crash")
	_check(is_equal_approx(am._wind_target, 0.05), "unknown kind: breeze fallback")

	# --- lightning-synced thunder: storm only ---
	am.set_weather("storm")
	am.on_lightning_struck()
	_check(am._thunder_delay >= 0.4 and am._thunder_delay <= 2.2,
		"storm strike schedules delayed clap (got %.2f)" % am._thunder_delay)
	am.set_weather("rain")
	am._thunder_delay = -1.0
	am.on_lightning_struck()
	_check(am._thunder_delay < 0.0, "rain strike: no clap scheduled")
	am.set_weather("clear")
	am.on_lightning_struck()
	_check(am._thunder_delay < 0.0, "clear strike: no clap scheduled")

	# --- the scheduled clap actually fires ---
	am.set_weather("storm")
	am.on_lightning_struck()
	var ticks := 0
	while am._thunder_delay > 0.0 and ticks < 60:
		am._process(0.1)
		ticks += 1
	_check(am._thunder_delay < 0.0, "scheduled clap fired")
	_check(am._thunder_player.stream == th, "thunder player has thunder stream")
	_check(am._thunder_player.volume_db > -80.0, "thunder player audible at clap")

	# --- crossfade converges on target ---
	am.set_weather("rain")
	for i in 12:
		am._process(0.5)
	var want_db := am._ambience_db(0.50)
	_check(absf(am._rain_player.volume_db - want_db) < 1.5,
		"rain crossfade converges (got %.1f dB, want %.1f)"
		% [am._rain_player.volume_db, want_db])

	# --- rain voice frees when faded out (snow has no rain) ---
	am.set_weather("snow")
	for i in 40:
		am._process(0.5)
	_check(not am._rain_player.playing, "rain voice freed after fade-out")

	# --- SFX mute silences ambience ---
	am.set_sfx_volume(0.0)
	_check(am._ambience_db(0.75) == -80.0, "muted: ambience target -80 dB")
	am.set_sfx_volume(0.8)  # restore

	# --- menu mode stops everything ---
	am.set_weather("storm")
	for i in 4:
		am._process(0.5)
	am.to_menu_mode()
	_check(am._weather == "clear", "menu: weather reset")
	_check(is_equal_approx(am._rain_target, 0.0), "menu: rain target 0")
	_check(not am._rain_player.playing, "menu: rain stopped")
	_check(not am._wind_player.playing, "menu: wind stopped")

	# --- WeatherFX emits lightning_struck on every bolt ---
	var wfx := WeatherFX.new()
	root.add_child(wfx)
	var strikes := [0]
	wfx.lightning_struck.connect(func() -> void: strikes[0] += 1)
	wfx._trigger_flash(Vector2(800, 600))
	_check(strikes[0] == 1, "lightning_struck emitted on bolt")
	_check(wfx._flash_alpha > 0.0, "bolt sets flash alpha")
	_check(wfx._bolt.size() > 1, "bolt polyline generated")
	wfx.queue_free()

	print("=== test_weather_ambience: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
