class_name AudioManager
extends Node
## Cursing Gnomes — audio system (music + SFX).
##
## Jeremy's rule: "Music should play as soon as the game is opened."
## iOS Safari blocks autoplay until user interaction, so we try immediately
## and fall back to "tap anywhere for music" (same as the HTML version).
##
## Tracks (all by Jeremy via Suno, extracted from HTML v0930.59):
##   music_title.mp3 — "Title screen" (main menu, alternates with fifths)
##   music_fifths.mp3 — "Open Fifths" (main menu, alternates with title)
##   music_peace.mp3 — "Stewardship in Peace" (gameplay, low intensity)
##   music_march.mp3 — "Strategic March" (BATTLE MUSIC, high intensity)
##   music_war.mp3   — "World at war" (total war: at war with EVERYONE)
##
## Battle music logic (ported from HTML MusicManager):
##   - Menu mode: title music (alternating title/fifths)
##   - Game mode: intensity-driven crossfade
##     - Peace track fades in at intensity 0.12→0.35
##     - War track ("Strategic March") fades in at intensity 0.55→0.85
##     - World-war track takes the war slot when at war with everyone
##   - Intensity: player units in combat (+0.09), enemies near base (+0.07),
##     damaged buildings (+0.05). Attack fast (~2.5s), release slow (~9s).
##
## SFX: HTML used Web Audio API synthesis (no embedded SFX files).
## We synthesize simple SFX via AudioStreamWAV generated at runtime.

signal music_started
signal music_blocked  # iOS autoplay blocked — show tap hint

const AUDIO_DIR := "res://assets/audio/"
const TRACKS := {
	"title": "music_title.mp3",
	"fifths": "music_fifths.mp3",
	"peace": "music_peace.mp3",
	"march": "music_march.mp3",   # BATTLE MUSIC
	"war": "music_war.mp3",       # TOTAL WAR MUSIC
	"jeremy_main": "music_jeremy_main.mp3",  # JEREMY'S TRACK (see below)
	"jeremy_overworld": "music_jeremy_overworld.mp3",  # JEREMY'S OVERWORLD
}

## JEREMY'S MUSIC HOOK (2026-10-11) — Jeremy composed the main
## overworld/tutorial theme himself. ARRIVED 2026-10-11: his file lives at
##   assets/audio/music_jeremy_main.mp3
## (his original: ~/workspace/user/files/Tutorial.mp3). play_intro_music()
## picks it up automatically — it is the track that fades in during the
## boot intro (after the ambient beat) and the tutorial music bed.
## FUTURE TRACKS: drop another MP3 in assets/audio/, add a TRACKS entry,
## and call play_music("your_key") — same slot, no other changes needed.
## To force the old title bed even with his file present, call
## play_intro_music(true).
const JEREMY_MUSIC_FILE := "music_jeremy_main.mp3"
const JEREMY_MUSIC_PATH := "res://assets/audio/music_jeremy_main.mp3"

# HTML crossfade thresholds (from updateLayerGains)
const PEACE_FADE_START := 0.12
const PEACE_FADE_END := 0.35
const WAR_FADE_START := 0.55
const WAR_FADE_END := 0.85

# Intensity smoothing (HTML: attack ~2.5s rate 1.1, release ~9s rate 0.32)
const INTENSITY_ATTACK_RATE := 1.1
const INTENSITY_RELEASE_RATE := 0.32
const INTENSITY_TICK := 0.5  # seconds between intensity updates

var _music_player: AudioStreamPlayer      # menu/title music (single)
var _peace_player: AudioStreamPlayer     # game peace layer
var _war_player: AudioStreamPlayer        # game war/battle layer
## Dedicated music players (not pooled). Total concurrent voices =
## MUSIC_PLAYERS + SFX_POOL_SIZE + SFX2D_POOL_SIZE; must stay within
## GraphicsTiers.BUDGET_AUDIO_VOICES (iPhone 17 floor).
## 4 = music + crossfade partner (overworld rotation, 2026-10-11) +
## peace layer + war layer. The partner only sounds during 2.5s
## transitions; steady-state DSP load is unchanged.
const MUSIC_PLAYERS := 4
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index := 0
const SFX_POOL_SIZE := 8
# Spatial SFX pool (HTML playSpatial parity: distance vol + stereo pan + Doppler).
# Uses AudioStreamPlayer2D with engine panning; volume/doppler computed manually
# from the HTML formulas so the curves match exactly.
var _sfx2d_players: Array[AudioStreamPlayer2D] = []
var _sfx2d_index := 0
const SFX2D_POOL_SIZE := 16
## Weather ambience voices (rain bed, wind bed, thunder one-shot) +
## day/night nature beds (crickets at night, birdsong by day) +
## AAA boot intro bed (wind, leaves, birds — 2026-10-11; these stop when
## the menu arrives, so steady-state DSP load is unchanged).
const AMBIENCE_PLAYERS := 8

var music_enabled := true
var music_volume := 0.8  # 0.0 - 1.0
var sfx_volume := 0.8

var _music_unlocked := false  # True once audio actually plays
var _current_track := ""
var _hint_shown := false

# Battle music state
var _mode := "menu"  # "menu" or "game"
var _intensity := 0.0
var _intensity_target := 0.0
var _intensity_acc := 0.0
var _game: GameState = null       # set via bind_game()
var _player_faction := ""
var _title_alt := false  # alternate title/fifths on menu loop
var _combat_cooldown := 0.0  # seconds since last combat (for fade-back)
const COMBAT_FADEBACK_DELAY := 8.0  # HTML releases slowly (~9s)

# Weather ambience (Jeremy 2026-10-07 wake lane: "hear the weather").
# The dynamic weather was fully visual — storms flashed in total silence.
# Synthesized loop beds (rain patter, wind swell) crossfade with the
# weather; thunder claps are synced to lightning strikes with a random
# 0.4-2.2 s delay — the delay IS the distance illusion (flash now,
# rumble after a beat). Distant rumbles also roll on a background
# scheduler so storms breathe between visible strikes.
#
# Nature ambience (Jeremy 2026-10-07 wake lane: "hear the day/night").
# The 4-hour day/night cycle was silent — nights now get a cricket
# chorus (pulsed ~4.3 kHz chirps, fading in at dusk, out at dawn) and
# days get a birdsong bed with a dawn-chorus peak. Both follow the
# sim clock hour-for-hour (the 0.5x game-speed setting slows them too,
# since targets are recomputed from game_time every frame) and duck
# under bad weather — birds and crickets go quiet in rain and storms,
# birds thin out in snow.
# +5 voices = 32 total, exactly at GraphicsTiers.BUDGET_AUDIO_VOICES (32).
const RAIN_LOOP_SECS := 4.0
const WIND_LOOP_SECS := 6.0
const THUNDER_SECS := 2.4
const CRICKET_LOOP_SECS := 5.0
const BIRD_LOOP_SECS := 8.0
const WEATHER_XFADE_DB_PER_SEC := 12.0
const THUNDER_MIN_DELAY := 0.4  # nearest strike
const THUNDER_MAX_DELAY := 2.2  # farthest strike

var _rain_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _thunder_player: AudioStreamPlayer
var _rain_stream: AudioStreamWAV
var _wind_stream: AudioStreamWAV
var _thunder_stream: AudioStreamWAV
var _weather := "clear"  # "clear" | "rain" | "storm" | "snow"
var _rain_target := 0.0  # linear 0..1 mix targets
var _wind_target := 0.0
var _wind_pitch := 1.0  # snow gets a thinner cold whistle
var _thunder_delay := -1.0  # pending lightning-synced clap (sec), -1 = none
var _thunder_next := 0.0  # background distant-rumble scheduler

# Nature ambience state (day/night beds).
var _cricket_player: AudioStreamPlayer
var _bird_player: AudioStreamPlayer
var _cricket_stream: AudioStreamWAV
var _bird_stream: AudioStreamWAV
var _cricket_target := 0.0  # linear 0..1 mix targets
var _bird_target := 0.0

# Intro-ambience state (AAA boot intro, Jeremy 2026-10-11): the "standing
# in the world" moment — wind + rustling leaves + birds, synthesized loops
# like the weather beds, swelled in as the landscape reveals. Separate
# players from the weather/nature beds so to_menu_mode() never touches them.
const INTRO_LOOP_SECS := 7.0
var _intro_wind: AudioStreamPlayer
var _intro_leaves: AudioStreamPlayer
var _intro_birds: AudioStreamPlayer
var _intro_amb_level := 0.0   # 0..1 swell, driven in _process
var _intro_amb_target := 0.0  # 1 = swelling in, 0 = fading out
var _intro_amb_pending := false  # iOS: start on first tap if blocked
# Intro music fade-in (music swells over the ambience, never cuts in).
var _music_fade_t := -1.0  # >=0 = fading, seconds elapsed
const _MUSIC_FADE_SECS := 3.0

## MIX ARCHITECTURE (Jeremy 2026-10-11: "music is a bed, not the lead").
## The tutorial/intro music must NEVER overpower in-game sounds:
##   SFX/UI/chuckle ....... user sfx_volume            (the lead)
##   Ambience (wind/leaves/birds) .. sfx_volume -12/-15/-19 dB
##   Music bed ............ user music_volume + MUSIC_BED_OFFSET_DB
## At defaults (0.8/0.8): SFX -1.9 dB, wind -13.9, leaves -16.9,
## birds -20.9, music -15.9 dB — clearly under everything, and every
## layer still follows its own user volume setting. SFX additionally
## punches a brief duck in the music (MUSIC_DUCK_DB for MUSIC_DUCK_SECS)
## so the gnome chuckle and UI clicks always sit on top.
const MUSIC_BED_OFFSET_DB := -14.0
const MUSIC_DUCK_DB := 5.0
const MUSIC_DUCK_SECS := 1.2
var _duck_env := 0.0  # 1 = fully ducked, decays to 0

## OVERWORLD ROTATION (Jeremy 2026-10-11): Jeremy's second track
## (Eon_of_dreams.mp3 -> music_jeremy_overworld.mp3) joins a
## random-selection pool. Shuffle-bag: NEVER the same track twice in a
## row, cycles the WHOLE pool before any track repeats. Tracks crossfade
## cleanly; same bed mix (under SFX/ambience, follows music_volume).
## Pool = Jeremy's tracks + the title/fifths menu themes. Tutorial.mp3
## (jeremy_main) joins the pool once the tutorial hands off — the
## tutorial lane calls start_overworld_rotation() at that moment.
const OVERWORLD_POOL: Array[String] = [
	"jeremy_main", "jeremy_overworld", "title", "fifths",
]
var _ow_bag: Array[String] = []
var _ow_last := ""
var _overworld_mode := false
# Crossfade partner for the music player (clean track transitions).
var _music_x: AudioStreamPlayer
var _xfade_t := -1.0  # >=0 = crossfading, seconds elapsed
const _XFADE_SECS := 2.5


func _ready() -> void:
	# UI tap feedback (2026-10-09): every button press anywhere clicks.
	# The Events autoload is the global bus, so this works in the main menu
	# too, before any GameState exists. Fetched via get_node_or_null —
	# bare autoload identifiers don't resolve in headless -s script runs
	# (cf. world.gd's Game fetch). Guarded for test harnesses that
	# instantiate several AudioManagers.
	var bus := get_tree().root.get_node_or_null("Events") as EventBus
	if bus != null and not bus.ui_click.is_connected(play_ui_click):
		bus.ui_click.connect(play_ui_click)
	_ensure_core_players()


## Create the music/SFX player pool. Idempotent: safe to call from
## test harnesses where _ready hasn't fired yet (SceneTree -s scripts
## run _initialize before nodes get _ready).
func _ensure_core_players() -> void:
	if _music_player != null:
		return
	# Menu/title music player (single, loops, we alternate tracks manually)
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Master"
	add_child(_music_player)
	_music_player.finished.connect(_on_title_finished)
	# Crossfade partner (overworld rotation, Jeremy 2026-10-11): the new
	# track rises here while the old one falls on _music_player.
	_music_x = AudioStreamPlayer.new()
	_music_x.name = "MusicPlayerX"
	_music_x.bus = "Master"
	_music_x.volume_db = -80.0
	add_child(_music_x)
	_music_x.finished.connect(_on_title_finished)

	# Game peace layer
	_peace_player = AudioStreamPlayer.new()
	_peace_player.name = "PeacePlayer"
	_peace_player.bus = "Master"
	add_child(_peace_player)
	_peace_player.finished.connect(func() -> void: _peace_player.play())

	# Game war/battle layer
	_war_player = AudioStreamPlayer.new()
	_war_player.name = "WarPlayer"
	_war_player.bus = "Master"
	add_child(_war_player)
	_war_player.finished.connect(func() -> void: _war_player.play())

	# SFX pool (multiple one-shots)
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer%d" % i
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)

	# Spatial SFX pool (HTML playSpatial parity). The engine provides distance
	# attenuation + stereo panning from the 2D position vs the camera
	# listener; we set pitch_scale manually for the HTML Doppler formula.
	# max_distance matches HTML's "near-silent past ~3600+2000".
	for i in SFX2D_POOL_SIZE:
		var p2 := AudioStreamPlayer2D.new()
		p2.name = "SFX2DPlayer%d" % i
		p2.bus = "Master"
		p2.max_distance = 5600.0
		add_child(p2)
		_sfx2d_players.append(p2)

	# Weather ambience beds (synthesized, looped; thunder is one-shot).
	_make_ambience_players()

	_apply_volumes()


## Create the 5 ambience voices + synthesize their streams.
## Idempotent (set_weather / on_lightning_struck can call it before _ready
## in tests). Players start at -80 dB so the first crossfade rises cleanly.
func _make_ambience_players() -> void:
	if _rain_player != null:
		return
	_rain_player = AudioStreamPlayer.new()
	_rain_player.name = "RainPlayer"
	_rain_player.bus = "Master"
	_rain_player.volume_db = -80.0
	add_child(_rain_player)
	_wind_player = AudioStreamPlayer.new()
	_wind_player.name = "WindPlayer"
	_wind_player.bus = "Master"
	_wind_player.volume_db = -80.0
	add_child(_wind_player)
	_thunder_player = AudioStreamPlayer.new()
	_thunder_player.name = "ThunderPlayer"
	_thunder_player.bus = "Master"
	add_child(_thunder_player)
	_cricket_player = AudioStreamPlayer.new()
	_cricket_player.name = "CricketPlayer"
	_cricket_player.bus = "Master"
	_cricket_player.volume_db = -80.0
	add_child(_cricket_player)
	_bird_player = AudioStreamPlayer.new()
	_bird_player.name = "BirdPlayer"
	_bird_player.bus = "Master"
	_bird_player.volume_db = -80.0
	add_child(_bird_player)
	_rain_stream = _synth_rain_loop()
	_wind_stream = _synth_wind_loop()
	_thunder_stream = _synth_thunder()
	_cricket_stream = _synth_cricket_loop()
	_bird_stream = _synth_bird_loop()
	_rain_player.stream = _rain_stream
	_wind_player.stream = _wind_stream
	_thunder_player.stream = _thunder_stream
	_cricket_player.stream = _cricket_stream
	_bird_player.stream = _bird_stream


## Pack float samples into a seamless 16-bit loop WAV: the fade tail is
## crossfaded into the head so the loop point is click-free.
func _loop_wav(buf: PackedFloat32Array, frames: int, fade: int, rate: int) -> AudioStreamWAV:
	for i in fade:
		var k := float(i) / float(fade)
		buf[i] = buf[i] * k + buf[frames + i] * (1.0 - k)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	wav.data = data
	return wav


## Rain patter: lowpassed white noise + droplet flutter.
## The flutter LFO runs 3 integer cycles per loop so it tiles.
func _synth_rain_loop() -> AudioStreamWAV:
	var rate := 22050
	var secs := RAIN_LOOP_SECS
	var frames := int(secs * rate)
	var fade := int(0.5 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261007
	var buf := PackedFloat32Array()
	buf.resize(frames + fade)
	var lp := 0.0
	for i in frames + fade:
		var t := float(i) / rate
		var n := rng.randf() * 2.0 - 1.0
		lp += 0.22 * (n - lp)  # one-pole lowpass: patter body
		var flutter := 0.72 + 0.28 * sin(TAU * 3.0 * t / secs + 1.7)
		buf[i] = lp * flutter * 0.85
	return _loop_wav(buf, frames, fade, rate)


## Wind swell: brown-ish noise (leaky integrator) breathing on a slow
## 2-cycles-per-loop swell so it tiles.
func _synth_wind_loop() -> AudioStreamWAV:
	var rate := 22050
	var secs := WIND_LOOP_SECS
	var frames := int(secs * rate)
	var fade := int(0.5 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var buf := PackedFloat32Array()
	buf.resize(frames + fade)
	var y := 0.0
	for i in frames + fade:
		var t := float(i) / rate
		var n := rng.randf() * 2.0 - 1.0
		y = 0.985 * y + 0.015 * n
		var swell := 0.62 + 0.38 * sin(TAU * 2.0 * t / secs + 0.4)
		buf[i] = y * swell * 6.0
	return _loop_wav(buf, frames, fade, rate)


## Thunder: one-shot rumble — hard-lowpassed noise, fast attack, long
## tail, plus a 48 Hz sub thump at the crack. Not looped.
func _synth_thunder() -> AudioStreamWAV:
	var rate := 22050
	var frames := int(THUNDER_SECS * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var lp := 0.0
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / rate
		var n := rng.randf() * 2.0 - 1.0
		lp += 0.055 * (n - lp)
		var env := (1.0 - exp(-t / 0.05)) * exp(-1.9 * t)
		var thump := sin(TAU * 48.0 * t) * exp(-7.0 * t) * 0.55
		var s: float = (lp * 1.4 + thump) * env * 0.8
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


## Cricket chorus: three detuned crickets, each chirping an integer
## number of times per 5 s loop so the pattern tiles. A chirp is three
## pulses of a ~4.3 kHz carrier — field-cricket-like with zero audio
## assets, following the weather-ambience synthesis idiom.
func _synth_cricket_loop() -> AudioStreamWAV:
	var rate := 22050
	var secs := CRICKET_LOOP_SECS
	var frames := int(secs * rate)
	var fade := int(0.5 * rate)
	var carriers := [4100.0, 4375.0, 4650.0]
	var chirps := [6.0, 7.0, 8.0]
	var offsets := [0.0, 0.33, 0.61]
	var buf := PackedFloat32Array()
	buf.resize(frames + fade)
	for i in frames + fade:
		var t := float(i) / rate
		var s := 0.0
		for c in 3:
			var chirp_ph := fmod(t * chirps[c] / secs + offsets[c], 1.0)
			# Cubed window: brief chirp bursts with real gaps between them,
			# like a field cricket (not a continuous drone).
			var chirp_w := pow(clampf(sin(PI * chirp_ph), 0.0, 1.0), 3.0)
			var pulse := clampf(sin(TAU * 20.0 * t + offsets[c] * 40.0), 0.0, 1.0)
			s += sin(TAU * carriers[c] * t) * pulse * chirp_w
		buf[i] = s * 0.16
	return _loop_wav(buf, frames, fade, rate)


## Birdsong bed: three birds, each singing a motif that repeats every
## 2 s (4x per 8 s loop = tiles). Syllables are linear FM sweeps with
## vibrato and raised-cosine envelopes — a dawn-chorus bed, not a pet
## shop. Staggered offsets keep the birds from landing on each other.
const BIRD_MOTIFS := [
	{"base": 2900.0, "vib": [28.0, 0.010],
		"syl": [[0.10, 0.18, 1.15, 0.88], [0.34, 0.16, 1.05, 0.80]]},
	{"base": 3400.0, "vib": [35.0, 0.008],
		"syl": [[0.55, 0.07, 0.95, 1.20], [0.66, 0.07, 0.95, 1.22],
			[0.77, 0.09, 0.95, 1.18]]},
	{"base": 2500.0, "vib": [22.0, 0.014],
		"syl": [[1.15, 0.40, 0.95, 1.30]]},
]

func _synth_bird_loop() -> AudioStreamWAV:
	var rate := 22050
	var secs := BIRD_LOOP_SECS
	var frames := int(secs * rate)
	var fade := int(0.5 * rate)
	var buf := PackedFloat32Array()
	buf.resize(frames + fade)
	for i in frames + fade:
		var t := float(i) / rate
		var mp := fmod(t, 2.0)  # motif phase: 2 s window repeats
		var s := 0.0
		for b in BIRD_MOTIFS:
			var base: float = b["base"]
			var vib: Array = b["vib"]
			for syl in b["syl"]:
				var st: float = syl[0]
				var dur: float = syl[1]
				var lt := mp - st
				if lt < 0.0 or lt >= dur:
					continue
				var f0 := base * float(syl[2])
				var k := base * (float(syl[3]) - float(syl[2])) / dur
				var ph := TAU * (f0 * lt + 0.5 * k * lt * lt) \
					+ TAU * float(vib[1]) * sin(TAU * float(vib[0]) * lt)
				var env := smoothstep(0.0, 0.015, lt) \
					* (1.0 - smoothstep(dur - 0.015, dur, lt))
				s += sin(ph) * env
		buf[i] = s * 0.30
	return _loop_wav(buf, frames, fade, rate)


## Hour of the sim clock (0-24), or -1 when not in game mode (menu).
func _game_hour() -> float:
	if _mode != "game" or _game == null:
		return -1.0
	var phase := fmod(_game.game_time, Config.DAY_LENGTH_SECONDS) \
		/ Config.DAY_LENGTH_SECONDS
	return phase * 24.0


## Nature mix targets for a clock hour and weather kind. Returns
## Vector2(crickets, birds). Pure function — tests drive it directly.
func _nature_targets(hour: float, weather: String) -> Vector2:
	if hour < 0.0:
		return Vector2.ZERO
	# Night (HTML definition: hour < 5 or hour > 21): crickets fade in
	# across dusk (21-22), hold all night, fade out across dawn (4-5).
	var nightness := 0.0
	if hour >= 22.0 or hour < 4.0:
		nightness = 1.0
	elif hour >= 21.0:
		nightness = hour - 21.0
	elif hour < 5.0:
		nightness = 5.0 - hour
	# Birds: gentle bed through the day, ramping in after dawn (4.5-5.5)
	# and out at dusk (20-21), plus a dawn-chorus peak at ~6:30.
	var dayness := 0.0
	if hour >= 5.5 and hour < 20.0:
		dayness = 1.0
	elif hour >= 4.5 and hour < 5.5:
		dayness = hour - 4.5
	elif hour >= 20.0 and hour < 21.0:
		dayness = 21.0 - hour
	var dawn := clampf(1.0 - absf(hour - 6.5) / 2.0, 0.0, 1.0)
	var crickets := 0.30 * nightness
	var birds := 0.16 * dayness + 0.14 * dawn
	# Bad weather quiets the wildlife.
	match weather:
		"rain":
			crickets *= 0.4
			birds *= 0.25
		"storm":
			crickets *= 0.25
			birds *= 0.10
		"snow":
			crickets *= 0.3
			birds *= 0.3
	return Vector2(crickets, birds)


func _ensure_nature_playing() -> void:
	# iOS Safari blocks audio until first tap; _process self-heals once
	# unlocked, this covers the bind_game path.
	if _cricket_player == null or not _music_unlocked:
		return
	if _cricket_target > 0.001 and not _cricket_player.playing:
		_cricket_player.play()
	if _bird_target > 0.001 and not _bird_player.playing:
		_bird_player.play()


## Day/night nature beds follow the sim clock — targets recomputed every
## frame from game_time, so the 0.5x game-speed setting slows the
## wildlife too. Voice-freeing rides the shared _xfade_player helper.
func _update_nature_ambience(delta: float) -> void:
	if _cricket_player == null:
		return
	_ensure_nature_playing()
	var tg := _nature_targets(_game_hour(), _weather)
	_cricket_target = tg.x
	_bird_target = tg.y
	_xfade_player(_cricket_player, _cricket_target, delta)
	_xfade_player(_bird_player, _bird_target, delta)


## Weather changed (wired to WeatherFX.weather_changed in main.gd).
func set_weather(kind: String) -> void:
	_make_ambience_players()
	_weather = kind
	match kind:
		"rain":
			_rain_target = 0.50
			_wind_target = 0.15
			_wind_pitch = 1.0
		"storm":
			_rain_target = 0.75
			_wind_target = 0.40
			_wind_pitch = 1.0
			_thunder_next = randf_range(2.0, 6.0)  # first rumble comes soon
		"snow":
			_rain_target = 0.0
			_wind_target = 0.30
			_wind_pitch = 1.3  # thinner cold whistle
		_:
			_rain_target = 0.0
			_wind_target = 0.05  # faint breeze under the music
			_wind_pitch = 1.0
	_wind_player.pitch_scale = _wind_pitch
	_ensure_ambience_playing()


## Lightning struck (wired to WeatherFX.lightning_struck in main.gd).
## The clap is delayed 0.4-2.2 s: flash now, rumble after a beat —
## the delay IS the distance illusion.
func on_lightning_struck() -> void:
	if _weather != "storm":
		return
	_make_ambience_players()
	_thunder_delay = randf_range(THUNDER_MIN_DELAY, THUNDER_MAX_DELAY)


func _play_thunder(vol: float, pitch: float) -> void:
	if _thunder_player == null or not _music_unlocked:
		return
	_thunder_player.volume_db = _ambience_db(vol)
	_thunder_player.pitch_scale = pitch
	_thunder_player.play()


## Ambience mix (0..1) scaled by the SFX volume setting, as dB.
## Muting SFX silences the weather too.
func _ambience_db(mix: float) -> float:
	var v := mix * sfx_volume
	return linear_to_db(v) if v > 0.001 else -80.0


func _ensure_ambience_playing() -> void:
	# iOS Safari blocks audio until first tap; _process self-heals once
	# unlocked, this covers the set_weather path.
	if _rain_player == null or not _music_unlocked:
		return
	if _rain_target > 0.001 and not _rain_player.playing:
		_rain_player.play()
	if _wind_target > 0.001 and not _wind_player.playing:
		_wind_player.play()


func _update_weather_ambience(delta: float) -> void:
	if _rain_player == null:
		return
	_ensure_ambience_playing()
	_xfade_player(_rain_player, _rain_target, delta)
	_xfade_player(_wind_player, _wind_target, delta)
	# Thunder only ever fires in a storm.
	if _weather != "storm" or not _music_unlocked:
		_thunder_delay = -1.0
		return
	if _thunder_delay > 0.0:
		_thunder_delay -= delta
		if _thunder_delay <= 0.0:
			_thunder_delay = -1.0
			# Close crack or far rumble — the strike delay already sold
			# the distance; vary the body a little.
			_play_thunder(randf_range(0.55, 1.0), randf_range(0.75, 1.25))
	else:
		# Background scheduler: distant rumbles between visible strikes.
		_thunder_next -= delta
		if _thunder_next <= 0.0:
			_thunder_next = randf_range(8.0, 22.0)
			_play_thunder(randf_range(0.22, 0.45), randf_range(0.55, 0.8))


func _xfade_player(p: AudioStreamPlayer, target_mix: float, delta: float) -> void:
	var target_db := _ambience_db(target_mix)
	var cur: float = p.volume_db
	if cur < target_db:
		p.volume_db = minf(cur + WEATHER_XFADE_DB_PER_SEC * delta, target_db)
	elif cur > target_db:
		p.volume_db = maxf(cur - WEATHER_XFADE_DB_PER_SEC * delta, target_db)
	# Free the voice once fully faded out.
	if target_mix <= 0.001 and p.volume_db <= -79.5 and p.playing:
		p.stop()


func _process(delta: float) -> void:
	# Weather ambience ticks every frame (crossfades + thunder scheduler),
	# independent of the battle-music gate below. Nature beds ride the
	# same tick (sim-clock targets, shared crossfade helper).
	_update_weather_ambience(delta)
	_update_nature_ambience(delta)
	_tick_intro_ambience(delta)
	_tick_music_fade(delta)
	# Jeremy 2026-10-07: menu music fallback — the `finished` signal is
	# unreliable for MP3s on web export, so the second menu track never
	# played. If we're in menu mode with music on but the player stopped,
	# advance to the next track manually.
	if _mode == "menu" and music_enabled and _music_unlocked:
		if not _music_player.playing and _current_track != "":
			_on_title_finished()
			return
	# Intensity tick (HTML: every 0.5s in game mode)
	if _mode != "game" or not music_enabled or not _music_unlocked:
		return
	if _game == null:
		return
	_intensity_acc += delta
	if _intensity_acc < INTENSITY_TICK:
		return
	_intensity_acc = 0.0
	_update_intensity(INTENSITY_TICK)
	_update_battle_mix()


## Bind to game state for intensity computation. Call when entering game.
func bind_game(game: GameState, player_faction: String) -> void:
	_game = game
	_player_faction = player_faction
	_mode = "game"
	_intensity = 0.0
	_intensity_target = 0.0
	# Crossfade: menu music out, game layers in
	_fade_to_game()


## Return to menu mode (title music).
func to_menu_mode() -> void:
	_mode = "menu"
	_game = null
	# Stop game layers
	_peace_player.stop()
	_war_player.stop()
	# Silence the weather (no weather in the menu)
	_weather = "clear"
	_rain_target = 0.0
	_wind_target = 0.0
	_thunder_delay = -1.0
	if _rain_player != null:
		_rain_player.stop()
		_wind_player.stop()
		_thunder_player.stop()
	# Silence the nature beds (no wildlife in the menu)
	_cricket_target = 0.0
	_bird_target = 0.0
	if _cricket_player != null:
		_cricket_player.stop()
		_bird_player.stop()
	# Start title music
	if music_enabled and _music_unlocked and not _music_player.playing:
		_title_alt = false
		play_music("title")


## AAA boot intro ambience (Jeremy 2026-10-11): wind + rustling leaves +
## birds — the "you're standing in the world" bed. Synthesized 16-bit
## loops with crossfade tails (same idiom as the weather beds), swelled
## in over ~2.5s. iOS-safe: if audio is blocked pre-tap, the request is
## remembered and starts on unlock_on_tap().
func start_intro_ambience() -> void:
	_intro_amb_pending = true
	if not _music_unlocked and OS.has_feature("web"):
		return  # iOS Safari: wait for the first tap
	_start_intro_ambience_now()


func _start_intro_ambience_now() -> void:
	_intro_amb_pending = false
	if _intro_wind == null:
		_intro_wind = AudioStreamPlayer.new()
		_intro_wind.name = "IntroWind"
		_intro_wind.bus = "Master"
		_intro_wind.volume_db = -80.0
		_intro_wind.stream = _synth_wind_loop()
		add_child(_intro_wind)
		_intro_leaves = AudioStreamPlayer.new()
		_intro_leaves.name = "IntroLeaves"
		_intro_leaves.bus = "Master"
		_intro_leaves.volume_db = -80.0
		_intro_leaves.stream = _synth_leaf_rustle_loop()
		add_child(_intro_leaves)
		_intro_birds = AudioStreamPlayer.new()
		_intro_birds.name = "IntroBirds"
		_intro_birds.bus = "Master"
		_intro_birds.volume_db = -80.0
		_intro_birds.stream = _synth_bird_loop()
		add_child(_intro_birds)
	for p: AudioStreamPlayer in [_intro_wind, _intro_leaves, _intro_birds]:
		if not p.playing:
			p.play()
	_intro_amb_target = 1.0


## Fade the intro bed back out (called as the main menu arrives).
func stop_intro_ambience() -> void:
	_intro_amb_pending = false
	_intro_amb_target = 0.0


## Leaf-rustle loop: band-limited noise with slow gust swells (3 integer
## gust cycles per loop so it tiles) — trees breathing around you.
func _synth_leaf_rustle_loop() -> AudioStreamWAV:
	var rate := 22050
	var secs := INTRO_LOOP_SECS
	var frames := int(secs * rate)
	var fade := int(0.5 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	var buf := PackedFloat32Array()
	buf.resize(frames + fade)
	var lp := 0.0
	var hp := 0.0
	for i in frames + fade:
		var t := float(i) / rate
		var n := rng.randf() * 2.0 - 1.0
		lp += 0.35 * (n - lp)        # lowpass: body
		hp = 0.92 * hp + 0.08 * n    # highpass-ish shimmer
		var gust := 0.45 + 0.55 * (0.5 + 0.5 * sin(TAU * 3.0 * t / secs + 2.1))
		buf[i] = (lp * 0.7 + hp * 0.5) * gust * 0.55
	return _loop_wav(buf, frames, fade, rate)


## AAA boot intro music (Jeremy 2026-10-11): fades in OVER the ambience.
## Plays Jeremy's own track when assets/audio/music_jeremy_main.mp3 exists;
## otherwise the existing title theme. force_title=true skips his file.
func play_intro_music(force_title := false) -> void:
	var track := "title"
	if not force_title and ResourceLoader.exists(JEREMY_MUSIC_PATH):
		track = "jeremy_main"
	play_music(track)
	# Fade in from silence — never cut in over the ambience.
	_music_player.volume_db = -30.0
	_music_fade_t = 0.0


## Tutorial music bed (Jeremy 2026-10-11): his own track underscores the
## AAA tutorial. The tutorial lane calls this when the tutorial starts;
## the track loops until something else takes the music player.
## Seamless handoff: if the boot intro already faded this track in,
## play_music() no-ops and we touch nothing — no gaps, no pops, no
## restarts. Fresh start (intro skipped): cinematic fade in from silence.
func play_tutorial_music() -> void:
	var track := "jeremy_main"
	if not ResourceLoader.exists(JEREMY_MUSIC_PATH):
		track = "title"
	# Seamless handoff (tutorial lane, Jeremy 2026-10-11): already playing
	# this exact track — the boot intro faded it in — so touch nothing.
	# No gaps, no pops, no restarts.
	var stream := _load_track(track)
	if stream != null and _music_player.playing \
			and _music_player.stream == stream:
		return
	play_music(track)
	# Fresh start (intro skipped, or a different track was playing):
	# arm the cinematic fade-in from silence. _tick_music_level owns the
	# actual volume ramp — never write the player level directly.
	if _music_player.playing:
		_music_fade_t = 0.0


## Pool tracks whose files actually exist (a missing file never breaks
## the rotation — the bag just runs without it).
func _overworld_tracks() -> Array[String]:
	var out: Array[String] = []
	for t: String in OVERWORLD_POOL:
		var fn: String = TRACKS.get(t, "")
		if fn != "" and ResourceLoader.exists(AUDIO_DIR + fn):
			out.append(t)
	return out


## Refill the shuffle bag: whole pool, shuffled, never opening with the
## track that just played (no immediate repeat across refills).
func _refill_ow_bag() -> void:
	_ow_bag = _overworld_tracks()
	_ow_bag.shuffle()
	if _ow_bag.size() > 1 and _ow_bag.back() == _ow_last:
		var i := randi() % (_ow_bag.size() - 1)
		var tmp: String = _ow_bag[i]
		_ow_bag[i] = _ow_bag.back()
		_ow_bag[_ow_bag.size() - 1] = tmp


func _next_overworld_track() -> String:
	if _ow_bag.is_empty():
		_refill_ow_bag()
	if _ow_bag.is_empty():
		return ""
	var t: String = _ow_bag.pop_back()
	_ow_last = t
	return t


## Start the overworld rotation (call when the tutorial hands off).
## Takes the music slot: battle layers are silenced so two music
## sources never stack, and the first track fades in.
func start_overworld_rotation() -> void:
	_overworld_mode = true
	_ow_bag.clear()
	if _peace_player != null:
		_peace_player.stop()
	if _war_player != null:
		_war_player.stop()
	var t := _next_overworld_track()
	if t != "":
		play_music_crossfade(t)


## Stop the rotation (the next play_music/to_menu_mode owns the slot).
func stop_overworld_rotation() -> void:
	_overworld_mode = false
	_ow_bag.clear()


## Play a track with a clean crossfade: the new track rises on the
## partner player while the old one falls (2.5s, smoothstepped).
## Falls back to a plain fade-in start when nothing is playing.
func play_music_crossfade(track: String) -> void:
	if not music_enabled:
		_current_track = track
		return
	var stream := _load_track(track)
	if stream == null:
		push_warning("[Audio] Track not found: %s" % track)
		return
	if _current_track == track and _music_player.playing:
		return  # already on it
	_current_track = track
	_music_unlocked = true
	if not _music_player.playing or _music_x == null:
		_xfade_t = -1.0
		_music_player.stream = stream
		_music_player.play()
		_music_fade_t = 0.0  # fade in like the intro
		music_started.emit()
		return
	_music_x.stream = stream
	_music_x.play()
	_xfade_t = 0.0


func _tick_music_fade(delta: float) -> void:
	_tick_music_level(delta)


## Single owner of the music player's level: bed offset + intro fade-in
## + SFX ducking, all computed every frame from the user's music_volume
## setting (never a stale or fighting write).
func _tick_music_level(delta: float) -> void:
	if _music_player == null:
		return
	# Ducking envelope: SFX punches a brief hole in the bed.
	if _duck_env > 0.0:
		_duck_env = maxf(0.0, _duck_env - delta / MUSIC_DUCK_SECS)
	# Active crossfade: old falls on the live player, new rises on the
	# partner; at the end the partner becomes the live player.
	if _xfade_t >= 0.0:
		_xfade_t += delta
		var k := clampf(_xfade_t / _XFADE_SECS, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)  # smoothstep
		var xt := _music_target_db()
		_music_player.volume_db = lerpf(xt, -80.0, e)
		_music_x.volume_db = lerpf(-80.0, xt, e)
		if k >= 1.0:
			_music_player.stop()
			var tmp := _music_player
			_music_player = _music_x
			_music_x = tmp
			_xfade_t = -1.0
		return
	# Intro fade-in progress 0..1.
	var fade_k := 1.0
	if _music_fade_t >= 0.0:
		_music_fade_t += delta
		fade_k = clampf(_music_fade_t / _MUSIC_FADE_SECS, 0.0, 1.0)
		if fade_k >= 1.0:
			_music_fade_t = -1.0
	var target := _music_target_db()
	_music_player.volume_db = lerpf(-30.0, target, fade_k * fade_k)


## The music bed target: user's music_volume, pushed clearly under SFX
## and ambience, minus any active SFX duck. Always call this instead of
## writing the player's volume directly.
func _music_target_db() -> float:
	var base := linear_to_db(music_volume) if music_volume > 0.01 else -80.0
	return base + MUSIC_BED_OFFSET_DB - MUSIC_DUCK_DB * _duck_env


func _tick_intro_ambience(delta: float) -> void:
	if _intro_wind == null:
		return
	var rate := 2.5 / 12.0  # ~2.5s swell
	if _intro_amb_target > _intro_amb_level:
		_intro_amb_level = minf(1.0, _intro_amb_level + rate * delta)
	else:
		_intro_amb_level = maxf(0.0, _intro_amb_level - rate * 2.0 * delta)
	var a := _intro_amb_level * _intro_amb_level  # ease-in
	# Ambience follows the user's sfx_volume (like the weather beds),
	# sitting under SFX but over the music bed.
	var user_db := linear_to_db(sfx_volume) if sfx_volume > 0.01 else -80.0
	_intro_wind.volume_db = lerpf(-80.0, user_db - 12.0, a)
	_intro_leaves.volume_db = lerpf(-80.0, user_db - 15.0, a)
	_intro_birds.volume_db = lerpf(-80.0, user_db - 19.0, a)
	if _intro_amb_level <= 0.0 and _intro_amb_target <= 0.0:
		for p: AudioStreamPlayer in [_intro_wind, _intro_leaves, _intro_birds]:
			p.stop()


## Compute combat intensity from game state (ports HTML computeIntensityTarget).
func _update_intensity(step: float) -> void:
	var target := 0.0
	if _game != null:
		var units: Array = _game.units
		var buildings: Array = _game.buildings
		# Player building positions (for proximity checks)
		var pbx: Array[float] = []
		var pby: Array[float] = []
		for b in buildings:
			if b is Dictionary and b.get("alive", false) and b.get("faction", "") == _player_faction:
				pbx.append(float(b.get("x", 0)))
				pby.append(float(b.get("y", 0)))
				# Damaged player building → danger
				var max_hp := float(b.get("max_hp", 1))
				var hp := float(b.get("hp", max_hp))
				if max_hp > 0 and hp < max_hp * 0.92:
					target += 0.05
		var has_base := pbx.size() > 0
		for u in units:
			if not (u is Dictionary):
				continue
			if not bool(u.get("alive", false)):
				continue
			var faction: String = str(u.get("faction", ""))
			if faction == _player_faction:
				# Player unit in combat
				var tgt = u.get("target", null)
				if tgt != null:
					var t_alive := true
					if tgt is Dictionary:
						t_alive = bool(tgt.get("alive", true))
					if t_alive:
						target += 0.09
			elif has_base:
				# Enemy combat unit near player base
				var job: String = str(u.get("job", ""))
				if _is_combat_job(job):
					var ux := float(u.get("x", 0))
					var uy := float(u.get("y", 0))
					for k in pbx.size():
						var dx := ux - pbx[k]
						var dy := uy - pby[k]
						if dx * dx + dy * dy < 1600.0 * 1600.0:
							target += 0.07
							break
	target = minf(1.0, target)
	_intensity_target = target
	# Asymmetric smoothing (HTML: attack fast, release slow)
	var rate := INTENSITY_ATTACK_RATE if target > _intensity else INTENSITY_RELEASE_RATE
	_intensity += (target - _intensity) * minf(1.0, step * rate)
	if absf(target - _intensity) < 0.004:
		_intensity = target


func _is_combat_job(job: String) -> bool:
	return job in ["soldier", "archer", "mage", "guard", "knight", "cannoneer", "ranger", "warrior"]


## Check if player is at war with EVERYONE (for world-war track).
func _is_total_war() -> bool:
	if _game == null:
		return false
	var diplomacy = _game.get("diplomacy")
	if diplomacy == null:
		return false
	var factions: Array = Config.FACTIONS.keys()
	var others := 0
	var at_war := 0
	for f in factions:
		if f == _player_faction:
			continue
		others += 1
		if diplomacy.relation_state(_player_faction, f) == "war":
			at_war += 1
	return others > 0 and at_war >= others


## Update battle music crossfade volumes from intensity.
## Ports HTML updateLayerGains: peace 0.12→0.35, war 0.55→0.85.
func _update_battle_mix() -> void:
	var inten := _intensity
	# Peace mix: 0 at ≤0.12, 1 at ≥0.35
	var peace_mix := clampf((inten - PEACE_FADE_START) / (PEACE_FADE_END - PEACE_FADE_START), 0.0, 1.0)
	# War mix: 0 at ≤0.55, 1 at ≥0.85
	var war_mix := clampf((inten - WAR_FADE_START) / (WAR_FADE_END - WAR_FADE_START), 0.0, 1.0)
	# Total war: world-war track takes the war slot
	var total_war := _is_total_war()
	var war_vol := 0.0
	var worldwar_vol := 0.0
	if total_war:
		worldwar_vol = war_mix
	else:
		war_vol = war_mix

	_apply_battle_volumes(peace_mix, war_vol, worldwar_vol)


func _apply_battle_volumes(peace_mix: float, war_mix: float, worldwar_mix: float) -> void:
	var base_db := linear_to_db(music_volume) if music_volume > 0.01 else -80.0
	# Ensure players are running when their mix > 0
	_ensure_layer_playing(_peace_player, "peace", peace_mix)
	_ensure_layer_playing(_war_player, "march", war_mix)
	# World-war uses the war player with different track when active
	if worldwar_mix > 0.02:
		_ensure_layer_playing(_war_player, "war", worldwar_mix)
		_war_player.volume_db = base_db + linear_to_db(maxf(worldwar_mix, 0.001))
	elif war_mix > 0.02:
		_war_player.volume_db = base_db + linear_to_db(maxf(war_mix, 0.001))
	else:
		_war_player.volume_db = -80.0

	if peace_mix > 0.02:
		_peace_player.volume_db = base_db + linear_to_db(maxf(peace_mix, 0.001))
	else:
		_peace_player.volume_db = -80.0


func _ensure_layer_playing(player: AudioStreamPlayer, track: String, mix: float) -> void:
	if mix <= 0.02:
		return
	var stream := _load_track(track)
	if stream == null:
		return
	if not player.playing or player.stream != stream:
		player.stream = stream
		player.play()


func _fade_to_game() -> void:
	# Fade menu music out over ~5.5s (HTML CANDIDATE14 crossfade)
	# For simplicity: stop menu player, start game layers at 0 volume
	# The intensity system will bring them up naturally
	if _music_player.playing:
		# Quick fade via tween
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -80.0, 2.0)
		tween.tween_callback(_music_player.stop)
	# Start layers silent; intensity drives them up
	_ensure_layer_playing(_peace_player, "peace", 0.03)
	_ensure_layer_playing(_war_player, "march", 0.03)
	_peace_player.volume_db = -80.0
	_war_player.volume_db = -80.0
	_apply_volumes()  # restore menu player volume for next time


func _apply_volumes() -> void:
	# Convert 0-1 to dB (-80 to 0)
	var sfx_db := linear_to_db(sfx_volume) if sfx_volume > 0.01 else -80.0
	# NOTE: the music player's level is owned by _tick_music_level() in
	# _process (bed offset + fade-in + SFX ducking) — never written here,
	# so the mix can never be fought by a stale direct write.
	# Battle layers get their volume from _apply_battle_volumes; set base here
	# (they'll be overridden by mix on next tick)
	for p in _sfx_players:
		p.volume_db = sfx_db


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if not enabled:
		_music_player.stop()
		_peace_player.stop()
		_war_player.stop()
		_current_track = ""
	elif _music_unlocked:
		if _mode == "menu":
			# Random starting track (Jeremy 2026-10-03).
			play_music("title" if randf() < 0.5 else "fifths")
		# Game mode: layers resume on next intensity tick


func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_apply_volumes()


func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_apply_volumes()


## Try to start music immediately. On iOS Safari this will be blocked
## until user interaction — we emit music_blocked so the UI can show
## the "tap anywhere" hint.
func try_autoplay(track := "title") -> void:
	if not music_enabled:
		return
	play_music(track)
	# Check if it actually started (iOS blocks silently)
	# We use a deferred check — if still not playing after a frame, assume blocked
	await get_tree().process_frame
	await get_tree().process_frame
	if not _music_player.playing and not _music_unlocked:
		music_blocked.emit()
		_hint_shown = true


## Called on first user tap anywhere — unlocks iOS audio.
func unlock_on_tap() -> void:
	if _music_unlocked:
		return
	_music_unlocked = true
	if _intro_amb_pending:
		_start_intro_ambience_now()
	if music_enabled and _current_track != "":
		# Resume the track that was blocked
		var stream := _load_track(_current_track)
		if stream:
			_music_player.stream = stream
			_music_player.play()
			music_started.emit()
	elif music_enabled:
		# No track was set — start title
		play_music("title")


func play_music(track: String) -> void:
	if not music_enabled:
		_current_track = track  # Remember for when re-enabled
		return
	# In game mode, route through the battle system
	if _mode == "game" and track in ["peace", "march", "war"]:
		# Direct track override (for testing); normal flow uses intensity
		_current_track = track
		return
	_current_track = track
	var stream := _load_track(track)
	if stream == null:
		push_warning("[Audio] Track not found: %s" % track)
		return
	# Don't restart if already playing this track
	if _music_player.playing and _music_player.stream == stream:
		return
	# A hard play cancels any active crossfade (the new track owns it all).
	_xfade_t = -1.0
	if _music_x != null:
		_music_x.stop()
	_music_player.stream = stream
	_music_player.play()
	_music_unlocked = true
	music_started.emit()


func stop_music() -> void:
	_music_player.stop()
	if _music_x != null:
		_music_x.stop()
	_xfade_t = -1.0
	_overworld_mode = false
	_ow_bag.clear()
	if _peace_player != null:
		_peace_player.stop()
	if _war_player != null:
		_war_player.stop()
	_current_track = ""


func _load_track(track: String) -> AudioStream:
	var filename: String = TRACKS.get(track, "")
	if filename == "":
		return null
	var path := AUDIO_DIR + filename
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _on_title_finished() -> void:
	# Mid-crossfade: the incoming track owns the slot; ignore the
	# outgoing player's finished signal.
	if _xfade_t >= 0.0:
		return
	if not music_enabled or not _music_unlocked:
		return
	# 1. Overworld rotation (Jeremy 2026-10-11): shuffle-bag advance —
	# never the same track twice in a row, whole pool cycles first.
	if _overworld_mode:
		var t := _next_overworld_track()
		if t != "":
			play_music_crossfade(t)
		return
	# 2. Jeremy's own tracks loop while they own the slot (tutorial bed /
	# direct plays) — they never fall into the title/fifths pool.
	if _current_track == "jeremy_main" or _current_track == "jeremy_overworld":
		var js := _load_track(_current_track)
		if js:
			_music_player.stream = js
			_music_player.play()
		return
	# 3. Menu rotation: randomly pick between title and fifths
	# (Jeremy 2026-10-03: random, not alternating — less repetitive).
	# Avoid repeating the same track twice in a row.
	if _mode != "menu":
		return
	var next := "title" if randf() < 0.5 else "fifths"
	if next == _current_track:
		next = "fifths" if next == "title" else "title"
	var stream := _load_track(next)
	if stream:
		_current_track = next
		_music_player.stream = stream
		_music_player.play()


## Play a one-shot SFX. Name maps to synthesized sounds.
## (HTML used Web Audio synthesis; we do the same via generated WAV.)
func play_sfx(sfx_name: String) -> void:
	var stream := _get_sfx(sfx_name)
	if stream == null:
		return
	# Duck the music bed so UI/world sounds (incl. the gnome chuckle)
	# always sit on top of the music.
	if _music_player != null and _music_player.playing:
		_duck_env = 1.0
	var p := _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % SFX_POOL_SIZE
	p.stream = stream
	p.play()


## UI tap click — the answer side of Events.ui_click (see UITapSfx).
## Routes through play_sfx so the SFX pool + sfx_volume/mute apply.
func play_ui_click() -> void:
	play_sfx("click")


## Spatial SFX — HTML playSpatial() parity.
## Distance attenuation + stereo pan (engine 2D audio) + Doppler pitch from
## the HTML formula: doppler = 1 + clamp(radial/900, -0.25, 0.35),
## radial > 0 = approaching. velocity: source velocity for Doppler
## (e.g. projectile velocity). Sounds past ~5600 units are skipped,
## matching HTML's "near-silent past ~3500" + fade.
func play_spatial_sfx(sfx_name: String, world_pos: Vector2, velocity: Vector2 = Vector2.ZERO) -> void:
	var stream := _get_sfx(sfx_name)
	if stream == null:
		return
	var listener := _listener_pos()
	var d := world_pos - listener
	var dist := d.length()
	if dist > 5600.0:
		return  # too far (HTML: same cutoff)
	# HTML Doppler: pitch from radial velocity toward listener.
	var doppler := 1.0
	var speed := velocity.length()
	if speed > 1.0:
		var radial := ((velocity.x * -d.x) + (velocity.y * -d.y)) / (dist + 1.0)
		doppler = 1.0 + clampf(radial / 900.0, -0.25, 0.35)
	var p := _sfx2d_players[_sfx2d_index]
	_sfx2d_index = (_sfx2d_index + 1) % SFX2D_POOL_SIZE
	p.global_position = world_pos
	p.stream = stream
	p.volume_db = linear_to_db(sfx_volume)
	p.pitch_scale = doppler
	p.play()


## Camera world position (the audio listener). Falls back to origin headless.
func _listener_pos() -> Vector2:
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_2d()
		if cam != null and is_instance_valid(cam):
			return cam.get_screen_center_position()
	return Vector2.ZERO


var _sfx_cache := {}

func _get_sfx(sfx_name: String) -> AudioStreamWAV:
	if _sfx_cache.has(sfx_name):
		return _sfx_cache[sfx_name]
	var wav := _synthesize_sfx(sfx_name)
	if wav:
		_sfx_cache[sfx_name] = wav
	return wav


## HTML fix79 SFX parity (const SFX block, verbatim segment definitions).
## HTML's playSpatial plays a sound's segments SIMULTANEOUSLY; each segment
## is one of:
##   tone:  {kind="tone", wave, freq, slide (exp target, opt),
##           slide_linear (linear target, opt), dur, vol, atk, lp}
##   noise: {kind="noise", color=white|pink|brown, dur, vol, atk, lp}
## (atk/lp default like HTML: 0.008 / 12000.) Returns [] for non-HTML names.
func _html_sfx_segments(sfx_name: String) -> Array:
	match sfx_name:
		"bow":
			return [
				{"kind": "tone", "wave": "triangle", "freq": 190.0,
					"slide": 90.0, "dur": 0.09, "vol": 0.05, "atk": 0.005,
					"lp": 2500.0},
				{"kind": "noise", "color": "pink", "dur": 0.06, "vol": 0.035,
					"lp": 1800.0},
			]
		"arrow":
			return [
				{"kind": "tone", "wave": "triangle", "freq": 920.0,
					"slide": 280.0, "dur": 0.12, "vol": 0.04, "lp": 4000.0},
				{"kind": "noise", "color": "white", "dur": 0.07, "vol": 0.03,
					"lp": 3500.0},
			]
		"bullet":
			return [
				{"kind": "noise", "color": "white", "dur": 0.07, "vol": 0.14,
					"lp": 6000.0, "atk": 0.001},
				{"kind": "tone", "wave": "sawtooth", "freq": 120.0,
					"slide": 45.0, "dur": 0.1, "vol": 0.06, "lp": 900.0},
				{"kind": "tone", "wave": "square", "freq": 1800.0,
					"slide": 400.0, "dur": 0.04, "vol": 0.025, "lp": 5000.0},
			]
		"cannon":
			return [
				{"kind": "noise", "color": "brown", "dur": 0.45, "vol": 0.2,
					"lp": 700.0, "atk": 0.002},
				{"kind": "noise", "color": "white", "dur": 0.12, "vol": 0.12,
					"lp": 2200.0, "atk": 0.001},
				{"kind": "tone", "wave": "sine", "freq": 55.0, "slide": 28.0,
					"dur": 0.5, "vol": 0.12, "lp": 400.0},
				{"kind": "tone", "wave": "triangle", "freq": 90.0,
					"slide_linear": 40.0, "dur": 0.35, "vol": 0.06,
					"lp": 600.0},
			]
		"grape":
			return [
				{"kind": "noise", "color": "white", "dur": 0.22, "vol": 0.15,
					"lp": 2800.0, "atk": 0.001},
				{"kind": "noise", "color": "pink", "dur": 0.28, "vol": 0.08,
					"lp": 1200.0},
				{"kind": "tone", "wave": "sawtooth", "freq": 110.0,
					"slide": 50.0, "dur": 0.18, "vol": 0.05, "lp": 800.0},
			]
		"rocket":
			return [
				{"kind": "noise", "color": "pink", "dur": 0.2, "vol": 0.09,
					"lp": 2400.0, "atk": 0.01},
				{"kind": "tone", "wave": "sawtooth", "freq": 95.0,
					"slide": 55.0, "dur": 0.55, "vol": 0.07, "lp": 700.0},
				{"kind": "tone", "wave": "square", "freq": 48.0,
					"slide_linear": 32.0, "dur": 0.6, "vol": 0.05,
					"lp": 300.0},
				{"kind": "noise", "color": "white", "dur": 0.5, "vol": 0.06,
					"lp": 3500.0, "atk": 0.02},
			]
		"mortar":
			return [
				{"kind": "noise", "color": "brown", "dur": 0.25, "vol": 0.12,
					"lp": 600.0},
				{"kind": "tone", "wave": "triangle", "freq": 85.0,
					"slide": 40.0, "dur": 0.28, "vol": 0.07, "lp": 500.0},
				{"kind": "noise", "color": "white", "dur": 0.08, "vol": 0.06,
					"lp": 2000.0, "atk": 0.001},
			]
		"explode":
			return [
				{"kind": "noise", "color": "brown", "dur": 0.7, "vol": 0.22,
					"lp": 500.0, "atk": 0.001},
				{"kind": "noise", "color": "white", "dur": 0.2, "vol": 0.16,
					"lp": 2500.0, "atk": 0.001},
				{"kind": "tone", "wave": "sine", "freq": 48.0, "slide": 22.0,
					"dur": 0.75, "vol": 0.14, "lp": 250.0},
				{"kind": "tone", "wave": "triangle", "freq": 70.0,
					"slide_linear": 30.0, "dur": 0.5, "vol": 0.06,
					"lp": 400.0},
			]
		"hit":
			return [
				{"kind": "noise", "color": "white", "dur": 0.05, "vol": 0.07,
					"lp": 3000.0, "atk": 0.001},
				{"kind": "tone", "wave": "triangle", "freq": 180.0,
					"slide": 70.0, "dur": 0.08, "vol": 0.04, "lp": 1500.0},
			]
		"aa":
			return [
				{"kind": "tone", "wave": "square", "freq": 700.0,
					"slide": 1400.0, "dur": 0.08, "vol": 0.045, "lp": 5000.0},
				{"kind": "noise", "color": "white", "dur": 0.1, "vol": 0.05,
					"lp": 4000.0, "atk": 0.002},
			]
		"build":
			return [
				{"kind": "tone", "wave": "triangle", "freq": 320.0,
					"slide": 180.0, "dur": 0.06, "vol": 0.03, "lp": 2000.0},
			]
		"fire":
			return [
				{"kind": "noise", "color": "pink", "dur": 0.25, "vol": 0.04,
					"lp": 900.0, "atk": 0.03},
			]
		"rocketFlyby":
			return [
				{"kind": "noise", "color": "pink", "dur": 0.35, "vol": 0.05,
					"lp": 2800.0, "atk": 0.02},
				{"kind": "tone", "wave": "sawtooth", "freq": 110.0,
					"slide_linear": 70.0, "dur": 0.35, "vol": 0.035,
					"lp": 800.0},
			]
		"gateUp":
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 70.0,
					"slide": 135.0, "dur": 1.1, "vol": 0.05, "lp": 500.0,
					"atk": 0.15},
				{"kind": "tone", "wave": "triangle", "freq": 140.0,
					"slide": 225.0, "dur": 0.9, "vol": 0.03, "lp": 800.0,
					"atk": 0.2},
				{"kind": "noise", "color": "white", "dur": 0.9, "vol": 0.035,
					"lp": 3000.0, "atk": 0.1},
				{"kind": "noise", "color": "brown", "dur": 1.2, "vol": 0.08,
					"lp": 300.0, "atk": 0.2},
			]
		"gateDown":
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 120.0,
					"slide": 60.0, "dur": 0.8, "vol": 0.05, "lp": 500.0,
					"atk": 0.1},
				{"kind": "noise", "color": "brown", "dur": 0.9, "vol": 0.09,
					"lp": 350.0, "atk": 0.15},
				{"kind": "tone", "wave": "sine", "freq": 48.0, "slide": 30.0,
					"dur": 0.55, "vol": 0.13, "lp": 250.0, "atk": 0.5},
				{"kind": "noise", "color": "white", "dur": 0.12, "vol": 0.07,
					"lp": 1200.0, "atk": 0.58},
			]
		"splash":
			return [
				{"kind": "noise", "color": "white", "dur": 0.18, "vol": 0.06,
					"lp": 2600.0, "atk": 0.01},
				{"kind": "tone", "wave": "sine", "freq": 700.0,
					"slide": 240.0, "dur": 0.16, "vol": 0.035, "lp": 1800.0,
					"atk": 0.01},
			]
		"hose59":
			return [
				{"kind": "noise", "color": "white", "dur": 0.22, "vol": 0.05,
					"lp": 4200.0, "atk": 0.02},
			]
		"hiss59":
			return [
				{"kind": "noise", "color": "white", "dur": 0.6, "vol": 0.06,
					"lp": 6000.0, "atk": 0.01},
			]
		"shoot":
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 320.0,
					"slide": 130.0, "dur": 0.18, "vol": 0.045, "lp": 2400.0,
					"atk": 0.01},
				{"kind": "noise", "color": "pink", "dur": 0.15, "vol": 0.03,
					"lp": 1800.0, "atk": 0.01},
			]
	return []


## Mix HTML SFX segments into one AudioStreamWAV, playing them
## simultaneously like HTML's playSpatial layers. Envelope per segment:
## attack ramp over atk, then exponential decay to near-silence by
## max(atk+0.02, dur) (HTML: gain ramps to 0.0001 by max(atk+0.02, dec)).
## One-pole lowpass stands in for HTML's biquad (same trick as war horn).
func _mix_sfx_segments(segs: Array, sample_rate: int) -> AudioStreamWAV:
	var total := 0
	for s in segs:
		total = maxi(total, int(float(s.get("dur", 0.2)) * sample_rate))
	var mix := PackedFloat32Array()
	mix.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654  # deterministic so headless tests are stable
	for s in segs:
		_render_sfx_segment(mix, s, sample_rate, rng)
	# Soft normalize: keep the loudest mixed sample under full scale.
	var peak := 0.0
	for v in mix:
		peak = maxf(peak, absf(v))
	if peak > 0.98:
		var k := 0.98 / peak
		for i in mix.size():
			mix[i] *= k
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(total)
	for i in total:
		data[i] = int(clampf(128.0 + mix[i] * 127.0, 0.0, 255.0))
	wav.data = data
	return wav


func _render_sfx_segment(mix: PackedFloat32Array, s: Dictionary,
		sample_rate: int, rng: RandomNumberGenerator) -> void:
	var dur := float(s.get("dur", 0.2))
	var vol := float(s.get("vol", 0.08))
	var atk := float(s.get("atk", 0.008))
	var lp := float(s.get("lp", 12000.0))
	var frames := int(dur * sample_rate)
	var rc := 1.0 / (TAU * lp)
	var dt := 1.0 / sample_rate
	var alpha := dt / (rc + dt)
	var smooth := 0.0
	var phase := 0.0
	var end_t := maxf(atk + 0.02, dur)
	var brown := 0.0
	var pink_b := [0.0, 0.0, 0.0]
	var is_tone := String(s.get("kind", "tone")) == "tone"
	var wave := String(s.get("wave", "sine"))
	var f0 := float(s.get("freq", 200.0))
	var slide := float(s.get("slide", 0.0))
	var slide_lin := float(s.get("slide_linear", 0.0))
	var color := String(s.get("color", "white"))
	for i in frames:
		var t := float(i) * dt
		var raw := 0.0
		if is_tone:
			var f := f0
			if slide > 0.0:
				f = f0 * pow(slide / f0, t / dur)  # HTML exponentialRamp
			elif slide_lin > 0.0:
				f = lerpf(f0, slide_lin, t / dur)  # HTML linearRamp
			phase += f * dt
			var cyc: float = phase - floor(phase)
			match wave:
				"sine":
					raw = sin(TAU * cyc)
				"triangle":
					raw = 4.0 * absf(cyc - 0.5) - 1.0
				"sawtooth":
					raw = 2.0 * cyc - 1.0
				"square":
					raw = 1.0 if cyc < 0.5 else -1.0
		else:
			var w := rng.randf() * 2.0 - 1.0
			match color:
				"pink":
					pink_b[0] = 0.997 * pink_b[0] + 0.029591 * w
					pink_b[1] = 0.985 * pink_b[1] + 0.032534 * w
					pink_b[2] = 0.950 * pink_b[2] + 0.048056 * w
					raw = (pink_b[0] + pink_b[1] + pink_b[2]) * 0.25
				"brown":
					brown = (brown + 0.02 * w) / 1.02
					raw = brown * 3.5
				_:
					raw = w
		smooth += alpha * (raw - smooth)
		var env: float
		if t < atk:
			env = vol * (t / maxf(atk, 0.0001))
		else:
			env = vol * exp(-5.0 * (t - atk) / maxf(end_t - atk, 0.0001))
		mix[i] += smooth * env


## Jeremy 2026-10-07 (wake graphics-hourly): disaster arrival stingers.
## Every named disaster used to arrive on the generic "boom". Each now gets
## a short signature sting composed from the same segment vocabulary as the
## HTML SFX (tone waves + slides, noise colors, attack/decay envelopes) —
## runtime-synthesized 16-bit WAV, zero assets, same as the weather voices.
## All stingers stay under ~1.1s and modest volumes; the mixer soft-normalizes
## and the spatial pool handles distance attenuation.
func _disaster_stinger_segments(sfx_name: String) -> Array:
	match sfx_name:
		"karen_arrive":
			# Shrill double complaint: two-tone descending nag whine.
			return [
				{"kind": "tone", "wave": "square", "freq": 880.0,
					"slide": 520.0, "dur": 0.42, "vol": 0.055, "lp": 3200.0},
				{"kind": "tone", "wave": "square", "freq": 1174.0,
					"slide": 698.0, "dur": 0.42, "vol": 0.03, "lp": 3600.0,
					"atk": 0.02},
				{"kind": "noise", "color": "white", "dur": 0.05,
					"vol": 0.05, "lp": 5000.0, "atk": 0.001},
			]
		"wizard_arrive":
			# Arcane zap: rising saw swell, sparkle, fizzling tail.
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 150.0,
					"slide": 1400.0, "dur": 0.34, "vol": 0.06, "lp": 4500.0},
				{"kind": "noise", "color": "pink", "dur": 0.3,
					"vol": 0.04, "lp": 6000.0, "atk": 0.02},
				{"kind": "tone", "wave": "triangle", "freq": 1200.0,
					"slide": 400.0, "dur": 0.32, "vol": 0.035,
					"lp": 3800.0, "atk": 0.16},
			]
		"bastard_arrive":
			# Dark swell: dissonant low drones rising out of a rumble.
			return [
				{"kind": "tone", "wave": "sine", "freq": 55.0,
					"dur": 0.9, "vol": 0.11, "lp": 300.0, "atk": 0.3},
				{"kind": "tone", "wave": "triangle", "freq": 58.27,
					"dur": 0.9, "vol": 0.06, "lp": 400.0, "atk": 0.32},
				{"kind": "noise", "color": "brown", "dur": 0.9,
					"vol": 0.09, "lp": 350.0, "atk": 0.2},
			]
		"gig_arrive":
			# Slide-whistle up + comical honk: the gig economy arrives.
			return [
				{"kind": "tone", "wave": "sine", "freq": 500.0,
					"slide": 1200.0, "dur": 0.35, "vol": 0.07, "lp": 4000.0},
				{"kind": "tone", "wave": "square", "freq": 233.0,
					"dur": 0.24, "vol": 0.05, "lp": 1500.0, "atk": 0.1},
			]
		"prophet_arrive":
			# Doom bell: dissonant long-decay toll + sub drone.
			return [
				{"kind": "tone", "wave": "triangle", "freq": 196.0,
					"dur": 1.0, "vol": 0.08, "lp": 1800.0, "atk": 0.01},
				{"kind": "tone", "wave": "triangle", "freq": 207.65,
					"dur": 1.0, "vol": 0.05, "lp": 1800.0, "atk": 0.015},
				{"kind": "tone", "wave": "sine", "freq": 49.0,
					"dur": 1.0, "vol": 0.07, "lp": 250.0, "atk": 0.05},
			]
		"taxman_arrive":
			# Cha-ching: bright metallic double ping, second swells in.
			return [
				{"kind": "tone", "wave": "square", "freq": 1318.0,
					"dur": 0.12, "vol": 0.05, "lp": 7000.0, "atk": 0.002},
				{"kind": "tone", "wave": "square", "freq": 1760.0,
					"dur": 0.3, "vol": 0.055, "lp": 7500.0, "atk": 0.1},
			]
		"ooze_arrive":
			# Boozy glugs: low blubbing blips + gurgle wash.
			return [
				{"kind": "tone", "wave": "sine", "freq": 130.0,
					"slide": 65.0, "dur": 0.42, "vol": 0.09, "lp": 700.0},
				{"kind": "tone", "wave": "sine", "freq": 98.0,
					"slide": 55.0, "dur": 0.42, "vol": 0.07, "lp": 600.0,
					"atk": 0.13},
				{"kind": "noise", "color": "pink", "dur": 0.42,
					"vol": 0.05, "lp": 500.0, "atk": 0.03},
			]
		"gull_arrive":
			# Seagull screech: twin descending cries over a flap wash.
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 1500.0,
					"slide": 750.0, "dur": 0.3, "vol": 0.045, "lp": 6500.0},
				{"kind": "tone", "wave": "sawtooth", "freq": 1650.0,
					"slide": 820.0, "dur": 0.3, "vol": 0.035, "lp": 6500.0,
					"atk": 0.13},
				{"kind": "noise", "color": "white", "dur": 0.32,
					"vol": 0.025, "lp": 6000.0, "atk": 0.02},
			]
		"moose_arrive":
			# Thicc bellow: low saw drop + brown-noise body + sub thump.
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 95.0,
					"slide": 55.0, "dur": 0.7, "vol": 0.08, "lp": 600.0,
					"atk": 0.08},
				{"kind": "noise", "color": "brown", "dur": 0.7,
					"vol": 0.1, "lp": 400.0, "atk": 0.05},
				{"kind": "tone", "wave": "sine", "freq": 48.0,
					"dur": 0.7, "vol": 0.09, "lp": 220.0, "atk": 0.06},
			]
		"jesus_arrive":
			# Light shimmer: soft rising triad, gentle by design.
			return [
				{"kind": "tone", "wave": "triangle", "freq": 523.0,
					"dur": 0.55, "vol": 0.045, "lp": 5000.0, "atk": 0.03},
				{"kind": "tone", "wave": "triangle", "freq": 659.0,
					"dur": 0.55, "vol": 0.04, "lp": 5000.0, "atk": 0.09},
				{"kind": "tone", "wave": "triangle", "freq": 784.0,
					"dur": 0.65, "vol": 0.04, "lp": 5200.0, "atk": 0.17},
				{"kind": "noise", "color": "white", "dur": 0.5,
					"vol": 0.018, "lp": 8000.0, "atk": 0.06},
			]
		"ass_arrive":
			# The Giant Ass: a low comical wobble. The joke is the shape;
			# the sting is a tubby brown-noise puff, nothing cruder.
			return [
				{"kind": "tone", "wave": "sine", "freq": 70.0,
					"slide": 45.0, "dur": 0.5, "vol": 0.1, "lp": 350.0},
				{"kind": "noise", "color": "brown", "dur": 0.42,
					"vol": 0.09, "lp": 450.0, "atk": 0.04},
			]
		"lizard_arrive":
			# Giant lizard: reptilian hiss over a guttural rumble.
			return [
				{"kind": "noise", "color": "white", "dur": 0.35,
					"vol": 0.05, "lp": 2600.0, "atk": 0.01},
				{"kind": "tone", "wave": "sawtooth", "freq": 140.0,
					"slide": 90.0, "dur": 0.42, "vol": 0.06, "lp": 900.0,
					"atk": 0.05},
			]
		"cat_arrive":
			# Cardboard cat: papery rustle + an up-down box chirp.
			return [
				{"kind": "noise", "color": "pink", "dur": 0.26,
					"vol": 0.05, "lp": 4200.0, "atk": 0.01},
				{"kind": "tone", "wave": "triangle", "freq": 620.0,
					"slide": 940.0, "dur": 0.16, "vol": 0.045,
					"lp": 4500.0, "atk": 0.02},
				{"kind": "tone", "wave": "triangle", "freq": 940.0,
					"slide": 520.0, "dur": 0.2, "vol": 0.04,
					"lp": 4500.0, "atk": 0.16},
			]
		"twister_arrive":
			# Twister Sister: tornado-siren wail over a rising wind roar,
			# with a debris rattle on top. Glam metal meets weather.
			return [
				{"kind": "tone", "wave": "sine", "freq": 600.0,
					"slide": 900.0, "dur": 0.5, "vol": 0.05, "lp": 2400.0,
					"atk": 0.08},
				{"kind": "tone", "wave": "sine", "freq": 900.0,
					"slide": 600.0, "dur": 0.5, "vol": 0.04, "lp": 2400.0,
					"atk": 0.3},
				{"kind": "noise", "color": "pink", "dur": 0.9,
					"vol": 0.08, "lp": 1200.0, "atk": 0.25},
				{"kind": "noise", "color": "white", "dur": 0.2,
					"vol": 0.03, "lp": 5000.0, "atk": 0.4},
			]
		"karaoke_arrive":
			# Brax the Karaoke Barbarian: a power-ballad intro played
			# badly — a wobbly detuned vocal warble (flat on the high
			# note, obviously) over a strummed lute thump. The weapon
			# is his voice.
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 220.0,
					"slide": 330.0, "dur": 0.45, "vol": 0.05, "lp": 1800.0,
					"atk": 0.1},
				{"kind": "tone", "wave": "sawtooth", "freq": 330.0,
					"slide": 260.0, "dur": 0.6, "vol": 0.055, "lp": 1600.0,
					"atk": 0.4},
				{"kind": "tone", "wave": "triangle", "freq": 110.0,
					"slide": 0.0, "dur": 0.18, "vol": 0.06, "lp": 900.0,
					"atk": 0.01},
				{"kind": "tone", "wave": "triangle", "freq": 165.0,
					"slide": 0.0, "dur": 0.18, "vol": 0.06, "lp": 900.0,
					"atk": 0.35},
			]
		"gossip_arrive":
			# Yapper the Gossip Gnome: a flurry of stage whispers —
			# rapid hushed noise bursts (highpassed chatter) under a
			# conspiratorial low murmur. Shhh.
			return [
				{"kind": "noise", "color": "white", "dur": 0.12,
					"vol": 0.05, "lp": 2400.0, "atk": 0.03},
				{"kind": "noise", "color": "white", "dur": 0.1,
					"vol": 0.055, "lp": 2600.0, "atk": 0.02},
				{"kind": "noise", "color": "white", "dur": 0.14,
					"vol": 0.05, "lp": 2200.0, "atk": 0.03},
				{"kind": "tone", "wave": "sine", "freq": 140.0,
					"slide": 110.0, "dur": 0.5, "vol": 0.045,
					"lp": 700.0, "atk": 0.2},
			]
		"borg_arrive":
			# Bill the Borg Crab: sideways scuttle-clanks off riveted
			# shell plates, the low "WE ARE BILL" assimilation drone
			# swelling underneath, his eye-laser charging up — and the
			# tiny shell toaster popping at the very end. The toaster
			# will be assimilated.
			return [
				{"kind": "tone", "wave": "square", "freq": 620.0,
					"slide": 310.0, "dur": 0.16, "vol": 0.055,
					"lp": 2600.0, "atk": 0.005},
				{"kind": "tone", "wave": "square", "freq": 740.0,
					"slide": 370.0, "dur": 0.16, "vol": 0.05,
					"lp": 2800.0, "atk": 0.12},
				{"kind": "tone", "wave": "sine", "freq": 55.0,
					"slide": 110.0, "dur": 1.0, "vol": 0.075,
					"lp": 480.0, "atk": 0.3},
				{"kind": "tone", "wave": "sawtooth", "freq": 1800.0,
					"slide": 320.0, "dur": 0.32, "vol": 0.04,
					"lp": 4200.0, "atk": 0.45},
				{"kind": "tone", "wave": "triangle", "freq": 1568.0,
					"dur": 1.1, "vol": 0.05, "lp": 5200.0, "atk": 0.82},
			]
		"warranty_arrive":
			# Wally the Warranty Salesman: a doorbell ding-dong (he's at
			# your door), then the sleazy descending smooth-talk slide
			# and a cha-ching shimmer. Sign here. And here.
			return [
				{"kind": "tone", "wave": "triangle", "freq": 880.0,
					"dur": 0.18, "vol": 0.06, "lp": 5200.0, "atk": 0.005},
				{"kind": "tone", "wave": "triangle", "freq": 659.0,
					"dur": 0.28, "vol": 0.06, "lp": 5200.0, "atk": 0.16},
				{"kind": "tone", "wave": "sine", "freq": 1200.0,
					"slide": 420.0, "dur": 0.5, "vol": 0.05,
					"lp": 3600.0, "atk": 0.4},
				{"kind": "tone", "wave": "triangle", "freq": 2093.0,
					"dur": 0.22, "vol": 0.035, "lp": 7200.0, "atk": 0.72},
				{"kind": "tone", "wave": "triangle", "freq": 2637.0,
					"dur": 0.3, "vol": 0.03, "lp": 7600.0, "atk": 0.86},
			]
		"crossfit_arrive":
			# Kyle the CrossFit Gnome: an airhorn blast (the WOD has begun),
			# a coach's whistle, and a final protein-shaker rattle. NO REP.
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 740.0,
					"dur": 0.28, "vol": 0.07, "lp": 5200.0, "atk": 0.004},
				{"kind": "tone", "wave": "sawtooth", "freq": 740.0,
					"dur": 0.28, "vol": 0.06, "lp": 5200.0, "atk": 0.3},
				{"kind": "tone", "wave": "square", "freq": 2093.0,
					"dur": 0.12, "vol": 0.05, "lp": 7200.0, "atk": 0.6},
				{"kind": "noise", "color": "white", "dur": 0.22,
					"vol": 0.045, "lp": 4200.0, "atk": 0.75},
			]
		"influencer_arrive":
			# Vicky the Influencer: two bright notification pings (somebody
			# liked the post), a camera-shutter click, and a descending
			# sparkle slide into content despair. The ring light hums.
			return [
				{"kind": "tone", "wave": "triangle", "freq": 1568.0,
					"dur": 0.09, "vol": 0.055, "lp": 6800.0, "atk": 0.004},
				{"kind": "tone", "wave": "triangle", "freq": 2093.0,
					"dur": 0.1, "vol": 0.05, "lp": 7200.0, "atk": 0.12},
				{"kind": "noise", "color": "white", "dur": 0.06,
					"vol": 0.07, "lp": 9000.0, "atk": 0.2},
				{"kind": "tone", "wave": "sine", "freq": 1800.0,
					"slide": 700.0, "dur": 0.5, "vol": 0.05,
					"lp": 3600.0, "atk": 0.35},
			]
		"gnomba_arrive":
			# Prince Gnomba: a royal fanfare played on a kazoo (two
			# sawtooth blasts, slightly too loud) over a suspicious
			# slinky bassline sliding down, ending on a coin "cha-ching"
			# — the sound of a con starting.
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 523.0,
					"dur": 0.14, "vol": 0.05, "lp": 3200.0, "atk": 0.008},
				{"kind": "tone", "wave": "sawtooth", "freq": 659.0,
					"dur": 0.16, "vol": 0.05, "lp": 3400.0, "atk": 0.15},
				{"kind": "tone", "wave": "sine", "freq": 110.0,
					"slide": 82.0, "dur": 0.45, "vol": 0.06,
					"lp": 900.0, "atk": 0.3},
				{"kind": "tone", "wave": "triangle", "freq": 2093.0,
					"dur": 0.12, "vol": 0.055, "lp": 8000.0, "atk": 0.55},
			]
		"dj_arrive":
			# DJ Weddington: an airhorn blast (the set has started), a
			# record scratch (sawtooth dive), a four-on-the-floor kick
			# thump, and a second airhorn. FEEL THE DROP.
			return [
				{"kind": "tone", "wave": "sawtooth", "freq": 587.0,
					"dur": 0.22, "vol": 0.06, "lp": 5200.0, "atk": 0.004},
				{"kind": "tone", "wave": "sawtooth", "freq": 1400.0,
					"slide": 300.0, "dur": 0.18, "vol": 0.05,
					"lp": 6000.0, "atk": 0.24},
				{"kind": "tone", "wave": "sine", "freq": 160.0,
					"slide": 50.0, "dur": 0.28, "vol": 0.09,
					"lp": 900.0, "atk": 0.44},
				{"kind": "tone", "wave": "sawtooth", "freq": 587.0,
					"dur": 0.16, "vol": 0.05, "lp": 5200.0, "atk": 0.76},
			]
		"doom_arrive":
			# Milo the Doomscroller: three bright notification pings (the
			# hook — ding ding ding), then the sad descending slide into
			# screen-glow despair and a soft low thud. He's seen every
			# video. He remembers none of them.
			return [
				{"kind": "tone", "wave": "triangle", "freq": 1568.0,
					"dur": 0.09, "vol": 0.055, "lp": 6800.0, "atk": 0.004},
				{"kind": "tone", "wave": "triangle", "freq": 1568.0,
					"dur": 0.09, "vol": 0.05, "lp": 6800.0, "atk": 0.12},
				{"kind": "tone", "wave": "triangle", "freq": 1760.0,
					"dur": 0.1, "vol": 0.05, "lp": 7000.0, "atk": 0.24},
				{"kind": "tone", "wave": "sine", "freq": 620.0,
					"slide": 150.0, "dur": 0.55, "vol": 0.06,
					"lp": 1400.0, "atk": 0.38},
				{"kind": "tone", "wave": "sine", "freq": 82.0,
					"slide": 55.0, "dur": 0.4, "vol": 0.05,
					"lp": 400.0, "atk": 0.7},
			]
		"mlm_arrive":
			# Chad the MLM Bro: a sleazy ascending ka-ching arpeggio (the
			# hook — money money money), a smooth-talk slide, and a final
			# cash-register shimmer. It's NOT a pyramid scheme.
			return [
				{"kind": "tone", "wave": "triangle", "freq": 523.0,
					"dur": 0.1, "vol": 0.055, "lp": 6800.0, "atk": 0.004},
				{"kind": "tone", "wave": "triangle", "freq": 659.0,
					"dur": 0.1, "vol": 0.055, "lp": 7000.0, "atk": 0.12},
				{"kind": "tone", "wave": "triangle", "freq": 784.0,
					"dur": 0.1, "vol": 0.055, "lp": 7200.0, "atk": 0.24},
				{"kind": "tone", "wave": "triangle", "freq": 1047.0,
					"dur": 0.22, "vol": 0.06, "lp": 7600.0, "atk": 0.36},
				{"kind": "tone", "wave": "sine", "freq": 1200.0,
					"slide": 380.0, "dur": 0.5, "vol": 0.05,
					"lp": 3600.0, "atk": 0.6},
				{"kind": "tone", "wave": "triangle", "freq": 2093.0,
					"dur": 0.18, "vol": 0.035, "lp": 7200.0, "atk": 0.85},
				{"kind": "tone", "wave": "triangle", "freq": 2637.0,
					"dur": 0.26, "vol": 0.03, "lp": 7600.0, "atk": 0.92},
			]
		"repo_arrive":
			# Ricky the Repo Gnome: a tow truck backing up — three square
			# backup beeps, a hydraulic chain-clunk, and a sad descending
			# slide-whistle womp as your building's title transfers.
			return [
				{"kind": "tone", "wave": "square", "freq": 880.0,
					"dur": 0.09, "vol": 0.05, "lp": 5200.0, "atk": 0.004},
				{"kind": "tone", "wave": "square", "freq": 880.0,
					"dur": 0.09, "vol": 0.05, "lp": 5200.0, "atk": 0.12},
				{"kind": "tone", "wave": "square", "freq": 880.0,
					"dur": 0.09, "vol": 0.05, "lp": 5200.0, "atk": 0.24},
				{"kind": "tone", "wave": "sine", "freq": 140.0,
					"slide": 70.0, "dur": 0.22, "vol": 0.08,
					"lp": 700.0, "atk": 0.4},
				{"kind": "tone", "wave": "triangle", "freq": 660.0,
					"slide": 220.0, "dur": 0.5, "vol": 0.055,
					"lp": 3000.0, "atk": 0.62},
				]
		"podcast_arrive":
			# Milo the Podcast Bro: a terrible podcast intro — three
			# over-eager ukulele-ish plucks, a loud "WELCOME BACK" airhorn
			# blast, and a ring-light power-on hum. Smash that subscribe.
			return [
				{"kind": "tone", "wave": "triangle", "freq": 523.0,
					"dur": 0.11, "vol": 0.055, "lp": 3600.0, "atk": 0.004},
				{"kind": "tone", "wave": "triangle", "freq": 659.0,
					"dur": 0.11, "vol": 0.055, "lp": 3600.0, "atk": 0.13},
				{"kind": "tone", "wave": "triangle", "freq": 784.0,
					"dur": 0.14, "vol": 0.06, "lp": 3800.0, "atk": 0.26},
				{"kind": "tone", "wave": "sawtooth", "freq": 220.0,
					"dur": 0.5, "vol": 0.07, "lp": 1800.0, "atk": 0.42},
				{"kind": "tone", "wave": "sine", "freq": 120.0,
					"dur": 0.6, "vol": 0.045, "lp": 500.0, "atk": 0.95},
				]
		"dmv_arrive":
			# Dave the DMV Clerk: dreary hold music — a slow descending
			# minor arpeggio on warbly sine (your call is important to us),
			# a bureaucratic stamp thud, and a final flatline "now serving"
			# beep that resolves to nothing. Please hold.
			return [
				{"kind": "tone", "wave": "sine", "freq": 440.0,
					"slide": -12.0, "dur": 0.4, "vol": 0.05,
					"lp": 2400.0, "atk": 0.004},
				{"kind": "tone", "wave": "sine", "freq": 349.0,
					"slide": -10.0, "dur": 0.4, "vol": 0.05,
					"lp": 2200.0, "atk": 0.36},
				{"kind": "tone", "wave": "sine", "freq": 294.0,
					"slide": -8.0, "dur": 0.4, "vol": 0.05,
					"lp": 2000.0, "atk": 0.72},
				{"kind": "tone", "wave": "sine", "freq": 220.0,
					"dur": 0.5, "vol": 0.05, "lp": 1800.0, "atk": 1.08},
				{"kind": "tone", "wave": "square", "freq": 90.0,
					"dur": 0.12, "vol": 0.07, "lp": 500.0, "atk": 1.62},
				{"kind": "tone", "wave": "sine", "freq": 880.0,
					"dur": 0.15, "vol": 0.03, "lp": 3200.0, "atk": 1.78},
			]
	return []


## Synthesize simple SFX (matching HTML's Web Audio approach).
func _synthesize_sfx(sfx_name: String) -> AudioStreamWAV:
	var sample_rate := 22050
	# HTML fix79 SFX names first (verbatim segment definitions).
	var html_segs := _html_sfx_segments(sfx_name)
	if not html_segs.is_empty():
		return _mix_sfx_segments(html_segs, sample_rate)
	# Disaster arrival stingers (original compositions, same segment idiom).
	var sting_segs := _disaster_stinger_segments(sfx_name)
	if not sting_segs.is_empty():
		return _mix_sfx_segments(sting_segs, sample_rate)
	# "launch" (nuke launch, world.gd): HTML has no SFX arm under this name
	# (its rocket-launch sites all used SFX.rocket), so alias the verbatim
	# HTML rocket segments rather than falling silent (null) or inventing
	# new synthesis.
	if sfx_name == "launch":
		return _mix_sfx_segments(_html_sfx_segments("rocket"), sample_rate)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false

	var data := PackedByteArray()
	match sfx_name:
		"click":
			# Short blip: 800Hz for 0.05s
			_append_tone(data, 800.0, 0.05, sample_rate, 0.5)
		"place":
			# Thunk: 200Hz for 0.15s with decay
			_append_tone(data, 200.0, 0.15, sample_rate, 0.7)
		"coin":
			# Coin: 1200Hz then 1600Hz
			_append_tone(data, 1200.0, 0.08, sample_rate, 0.5)
			_append_tone(data, 1600.0, 0.12, sample_rate, 0.5)
		"harvest":
			# Jeremy 2026-10-07 wake lane ("the food economy talks back"):
			# crisp two-tone crop pluck — basket-fill chirp, soft enough
			# to sit under a busy farm at the 4/s throttle.
			_append_tone(data, 520.0, 0.06, sample_rate, 0.35)
			_append_tone(data, 780.0, 0.09, sample_rate, 0.35)
		"error":
			# Buzz: 150Hz for 0.2s
			_append_tone(data, 150.0, 0.2, sample_rate, 0.5)
		"whoosh":
			# Projectile launch: noise sweep 0.25s (Doppler pitch applied at play)
			_append_noise(data, 0.25, sample_rate, 0.45)
		"boom":
			# Cannon: low thud 90Hz 0.4s + noise burst
			_append_tone(data, 90.0, 0.4, sample_rate, 0.8)
			_append_noise(data, 0.3, sample_rate, 0.5)
		"zap":
			# Spell: 900Hz -> 1400Hz sweep 0.2s
			_append_tone(data, 900.0, 0.1, sample_rate, 0.5)
			_append_tone(data, 1400.0, 0.1, sample_rate, 0.5)
		"war_horn":
			# War horn stinger (HTML playWarHorn — combat begins):
			# sawtooth 98 -> 146.8 Hz over 0.7 s, attack 0.25 s, decay
			# to 1.6 s, one-pole smoothing stands in for the 500 Hz lowpass.
			_append_war_horn(data, sample_rate)
		"gnome_chuckle":
			# Mischievous gnome laugh (AAA boot intro, Jeremy 2026-10-11):
			# "he-he-he-HEE!" — quick descending blips with vibrato,
			# ending on a higher uptick. Same 8-bit idiom as the rest.
			_append_chuckle(data, sample_rate)
		_:
			return null

	wav.data = data
	return wav


## Gnome chuckle: 5 voiced blips, pitch falling then kicking up at the
## end, with a fast wobble so it reads as a laugh, not beeps.
func _append_chuckle(data: PackedByteArray, sample_rate: int) -> void:
	var freqs := [470.0, 430.0, 395.0, 360.0, 520.0]
	var blip := 0.085
	for bi in freqs.size():
		var f0: float = freqs[bi]
		var frames := int(blip * sample_rate)
		var start := data.size()
		data.resize(start + frames)
		for i in frames:
			var t := float(i) / sample_rate
			var k := float(i) / float(frames)
			# Vibrato + pitch droop inside each blip.
			var f := f0 * (1.0 - 0.18 * k) * (1.0 + 0.06 * sin(TAU * 28.0 * t))
			var env := sin(PI * k)  # smooth in/out, no clicks
			var sample := sin(TAU * f * t) * 0.6 * env
			data[start + i] = int(128 + sample * 127)


func _append_tone(data: PackedByteArray, freq: float, duration: float, sample_rate: int, amplitude: float) -> void:
	var frames := int(duration * sample_rate)
	var start := data.size()
	data.resize(start + frames)
	for i in frames:
		var t := float(i) / sample_rate
		# Sine with exponential decay
		var envelope := exp(-3.0 * t / duration)
		var sample := sin(TAU * freq * t) * amplitude * envelope
		# 8-bit: 0-255, center 128
		data[start + i] = int(128 + sample * 127)


func _append_noise(data: PackedByteArray, duration: float, sample_rate: int, amplitude: float) -> void:
	var frames := int(duration * sample_rate)
	var start := data.size()
	data.resize(start + frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in frames:
		var t := float(i) / duration
		var envelope := exp(-5.0 * t)
		var sample := (rng.randf() * 2.0 - 1.0) * amplitude * envelope
		data[start + i] = int(128 + sample * 127)


func _append_war_horn(data: PackedByteArray, sample_rate: int) -> void:
	var duration := 1.7
	var frames := int(duration * sample_rate)
	var start := data.size()
	data.resize(start + frames)
	var phase := 0.0
	var smooth := 0.0
	for i in frames:
		var t := float(i) / sample_rate
		# Frequency ramp: 98 -> 146.8 Hz over the first 0.7 s.
		var freq := 98.0 + (146.8 - 98.0) * minf(t / 0.7, 1.0)
		phase += freq / sample_rate
		var saw: float = 2.0 * (phase - floor(phase + 0.5))
		# One-pole lowpass (~500 Hz stand-in for HTML's biquad).
		smooth += 0.14 * (saw - smooth)
		var env: float
		if t < 0.25:
			env = 0.30 * (t / 0.25)
		else:
			env = 0.30 * exp(-3.0 * (t - 0.25) / 1.35)
		data[start + i] = int(128 + smooth * env * 127)


## For headless testing
func is_music_playing() -> bool:
	return _music_player.playing or _peace_player.playing or _war_player.playing


func get_current_track() -> String:
	return _current_track


func get_intensity() -> float:
	return _intensity


func get_mode() -> String:
	return _mode
