extends SceneTree
## Cursing Gnomes — paused-badge tests (2026-10-03).
##
## Pausing the game used to show only a transient flash hint (whose fade
## tween also stalls while the tree is paused): a paused game showed no
## persistent indicator. The HUD now keeps a top-center "Paused" badge
## visible for as long as the tree is paused, via Hud.set_paused(bool).
## Every pause-toggle path must call it:
##   - world.gd drawer action "pause" (normal play)
##   - hud.gd _on_sb_pause (sandbox director HUD)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_paused_badge.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


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


static func _has_glyph(s: String) -> bool:
	for i in range(s.length()):
		if s.unicode_at(i) > 0x2500:
			return true
	return false


## Scan a script for non-comment lines containing `marker`.
static func _scan_lines(path: String, marker: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.strip_edges().begins_with("#"):
			continue
		if line.find(marker) >= 0:
			out.append(line.strip_edges().left(120))
	f.close()
	return out


func _initialize() -> void:
	print("=== Cursing Gnomes paused-badge tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.player_faction = "gnomes"

	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	await process_frame

	# The badge exists, says "Paused", is hidden at start, and the text
	# is plain (no glyph/tofu risk on iPhone).
	_check("paused badge label built", hud._paused_label != null)
	_check("paused badge text is 'Paused'", hud._paused_label.text == "Paused")
	_check("paused badge hidden by default", not hud._paused_label.visible)
	_check("paused badge text has no glyphs", not _has_glyph(hud._paused_label.text))

	# set_paused toggles visibility both ways.
	hud.set_paused(true)
	_check("set_paused(true) shows badge", hud._paused_label.visible)
	hud.set_paused(false)
	_check("set_paused(false) hides badge", not hud._paused_label.visible)

	# Every pause-toggle path wires the badge.
	var world_calls := _scan_lines("res://scripts/world/world.gd", "hud.set_paused(")
	_check("world.gd pause handler calls hud.set_paused", world_calls.size() >= 1)
	var sb_calls := _scan_lines("res://scripts/ui/hud.gd", "set_paused(get_tree().paused)")
	_check("sandbox _on_sb_pause calls set_paused", sb_calls.size() >= 1)

	# The flash-hint fade tween must keep processing while the tree is
	# paused — otherwise hints stall mid-fade during pause and pile up.
	var tween_lines := _scan_lines("res://scripts/ui/hud.gd", "TWEEN_PAUSE_PROCESS")
	_check("flash_hint tween uses TWEEN_PAUSE_PROCESS", tween_lines.size() >= 1)

	print("--- paused badge: %d passed, %d failed ---" % [_passed, _failed])
	if not _failures.is_empty():
		print("FAILURES: ", _failures)
	quit(1 if _failed > 0 else 0)
