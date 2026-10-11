extends SceneTree
## Cursing Gnomes — disaster arrival stinger tests (wake graphics-hourly
## 2026-10-07).
##
## Every named disaster used to arrive on the generic "boom". Each now gets
## its own signature sting (runtime-synthesized, zero assets). Pins:
##   - kind -> stinger mapping (DisasterSim.stinger_for_kind, pure)
##   - every stinger synthesizes to a real non-empty WAV, <= ~1.2s
##   - all ten stingers are acoustically distinct compositions
##   - a live spawn emits sfx_spatial with the disaster's own stinger
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_disaster_stingers.gd
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


func _initialize() -> void:
	print("=== Cursing Gnomes disaster stinger tests ===")
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


func _stinger(kind: String) -> String:
	return DisasterSim.stinger_for_kind(kind)


func _test_mapping() -> void:
	_check("karen -> karen_arrive", _stinger("hoa_karen") == "karen_arrive")
	_check("wizard -> wizard_arrive", _stinger("rogue_wizard") == "wizard_arrive")
	_check("bastard -> bastard_arrive", _stinger("count_bastard") == "bastard_arrive")
	_check("gig gnome -> gig_arrive", _stinger("gig_gnome") == "gig_arrive")
	_check("prophet -> prophet_arrive", _stinger("doom_prophet") == "prophet_arrive")
	_check("taxman -> taxman_arrive", _stinger("taxman") == "taxman_arrive")
	_check("ooze -> ooze_arrive", _stinger("booze_ooze") == "ooze_arrive")
	_check("gulls -> gull_arrive", _stinger("seagull_swarm") == "gull_arrive")
	_check("moose -> moose_arrive", _stinger("thicc_moose") == "moose_arrive")
	_check("jesus -> jesus_arrive", _stinger("jesus") == "jesus_arrive")
	_check("giant ass -> ass_arrive", _stinger("giant_ass") == "ass_arrive")
	_check("lizard -> lizard_arrive", _stinger("giant_lizard") == "lizard_arrive")
	_check("cardboard cat -> cat_arrive", _stinger("cardboard_cat") == "cat_arrive")
	_check("twister -> twister_arrive", _stinger("twister_sister") == "twister_arrive")
	# Pre-existing mappings preserved.
	_check("volcano -> explode", _stinger("volcano") == "explode")
	_check("bandit_raid -> war_horn", _stinger("bandit_raid") == "war_horn")
	_check("unknown -> boom", _stinger("nope_not_a_disaster") == "boom")


func _test_synthesis() -> void:
	var am := AudioManager.new()
	var names := ["karen_arrive", "wizard_arrive", "bastard_arrive",
		"gig_arrive", "prophet_arrive", "taxman_arrive", "ooze_arrive",
		"gull_arrive", "moose_arrive", "jesus_arrive",
		"ass_arrive", "lizard_arrive", "cat_arrive", "twister_arrive"]
	for n in names:
		var wav: AudioStreamWAV = am._synthesize_sfx(n)
		_check(n + ": synthesizes non-null", wav != null)
		if wav == null:
			continue
		_check(n + ": has frames", wav.data.size() > 0)
		var dur := float(wav.data.size()) / float(wav.mix_rate)
		_check(n + ": under 1.2s (%.2fs)" % dur, dur <= 1.2)
		_check(n + ": 8-bit mono", wav.format == AudioStreamWAV.FORMAT_8_BITS
			and not wav.stereo)
	am.queue_free()


func _test_distinct() -> void:
	# Fourteen stingers must be fourteen different compositions, not one
	# sting renamed.
	var am := AudioManager.new()
	var seen := {}
	var names := ["karen_arrive", "wizard_arrive", "bastard_arrive",
		"gig_arrive", "prophet_arrive", "taxman_arrive", "ooze_arrive",
		"gull_arrive", "moose_arrive", "jesus_arrive",
		"ass_arrive", "lizard_arrive", "cat_arrive", "twister_arrive"]
	for n in names:
		var wav: AudioStreamWAV = am._synthesize_sfx(n)
		seen[n] = _checksum(wav.data) if wav != null else -1
	var uniq := {}
	for n in names:
		uniq[seen[n]] = true
	_check("14 stingers, 14 distinct waveforms", uniq.size() == 14)
	am.queue_free()


func _on_sfx(name: String, _pos: Vector2, _vel: Vector2) -> void:
	_sfx_seen.append(name)


func _test_live_spawn() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves", "ogres", "gnomes", "undead"])
	var combat = SimCombat.new(gs)
	var d = DisasterSim.new(gs, combat)
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	_sfx_seen.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	var u: Dictionary = d.spawn("hoa_karen", Vector2(2000, 2000))
	_check("karen spawns", not u.is_empty())
	_check("karen arrival emits karen_arrive, not boom",
		_sfx_seen.has("karen_arrive") and not _sfx_seen.has("boom"))
	gs.bus.sfx_spatial.disconnect(_on_sfx)
	gs.queue_free()
