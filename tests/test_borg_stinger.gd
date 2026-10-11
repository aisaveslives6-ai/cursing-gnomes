extends SceneTree
## Cursing Gnomes — Bill the Borg Crab arrival stinger tests
## (wake dedicated-porting 2026-10-08).
##
## Bill was the only named disaster arriving in silence: every other
## "*_arrive" stinger had a _disaster_stinger_segments arm, but
## "borg_arrive" fell through _synthesize_sfx to null, so
## play_spatial_sfx skipped it quietly. Bill now gets his own signature
## sting — scuttle-clanks, the "WE ARE BILL" assimilation drone, his
## eye-laser charging, and the tiny shell toaster popping at the end.
##
## Pins:
##   - kind -> stinger mapping (DisasterSim.stinger_for_kind, pure)
##   - borg_arrive synthesizes to a real non-empty WAV, <= ~1.2s
##   - borg_arrive is acoustically distinct from all 17 other stingers
##   - a live spawn emits sfx_spatial with borg_arrive, not boom
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_borg_stinger.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no audio output.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _sfx_seen: Array = []


## FNV-1a 32-bit checksum: PackedByteArray has no md5 in Godot 4.
static func _checksum(data: PackedByteArray) -> int:
	var h := 2166136261
	for b in data:
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


const _OTHER_STINGERS: Array[String] = [
	"karen_arrive", "wizard_arrive", "bastard_arrive", "gig_arrive",
	"prophet_arrive", "taxman_arrive", "ooze_arrive", "gull_arrive",
	"moose_arrive", "jesus_arrive", "ass_arrive", "lizard_arrive",
	"cat_arrive", "twister_arrive", "karaoke_arrive", "gossip_arrive",
	# Non-disaster named SFX Bill must also not collide with.
	"boom", "explode", "war_horn",
]


func _initialize() -> void:
	print("=== Cursing Gnomes borg stinger tests ===")
	_run.call_deferred()


func _run() -> void:
	_test_mapping()
	_test_synthesis()
	_test_distinct()
	_test_live_spawn()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves", "ogres", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	return [gs, combat, d]


func _test_mapping() -> void:
	_check("borg crab -> borg_arrive",
		DisasterSim.stinger_for_kind("borg_crab_bill") == "borg_arrive")
	# Pre-existing mappings preserved.
	_check("volcano -> explode",
		DisasterSim.stinger_for_kind("volcano") == "explode")
	_check("unknown -> boom",
		DisasterSim.stinger_for_kind("nope_not_a_disaster") == "boom")


func _test_synthesis() -> void:
	var am := AudioManager.new()
	var wav: AudioStreamWAV = am._synthesize_sfx("borg_arrive")
	_check("borg_arrive: synthesizes non-null", wav != null)
	if wav == null:
		am.queue_free()
		return
	_check("borg_arrive: has frames", wav.data.size() > 0)
	var dur := float(wav.data.size()) / float(wav.mix_rate)
	_check("borg_arrive: under 1.2s (%.2fs)" % dur, dur <= 1.2)
	_check("borg_arrive: 8-bit mono",
		wav.format == AudioStreamWAV.FORMAT_8_BITS and not wav.stereo)
	# The mix must actually make sound, not a flat line.
	var peak := 0
	for b in wav.data:
		peak = maxi(peak, abs(int(b) - 128))
	_check("borg_arrive: audible peak (%d)" % peak, peak > 8)
	am.queue_free()


func _test_distinct() -> void:
	# Bill's sting must be its own composition, not a renamed sibling.
	var am := AudioManager.new()
	var mine: AudioStreamWAV = am._synthesize_sfx("borg_arrive")
	_check("borg_arrive: synthesizes for distinctness", mine != null)
	if mine == null:
		am.queue_free()
		return
	var mine_sum := _checksum(mine.data)
	var dupes: Array[String] = []
	for n in _OTHER_STINGERS:
		var wav: AudioStreamWAV = am._synthesize_sfx(n)
		if wav != null and _checksum(wav.data) == mine_sum:
			dupes.append(n)
	_check("borg_arrive: distinct from %d other stingers" % _OTHER_STINGERS.size(),
		dupes.is_empty())
	for n in dupes:
		print("  DUP: borg_arrive == ", n)
	am.queue_free()


func _on_sfx(name: String, _pos: Vector2, _vel: Vector2) -> void:
	_sfx_seen.append(name)


func _test_live_spawn() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_sfx_seen.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	var u: Dictionary = d.spawn("borg_crab_bill", Vector2(60, 2000))
	_check("borg crab spawns", not u.is_empty())
	_check("arrival emits borg_arrive, not boom",
		_sfx_seen.has("borg_arrive") and not _sfx_seen.has("boom"))
	gs.bus.sfx_spatial.disconnect(_on_sfx)
	gs.queue_free()
