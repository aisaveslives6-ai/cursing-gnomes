extends SceneTree
## Cursing Gnomes — HUD static-selection gate tests (Jeremy 2026-10-05).
##
## _refresh_selection() rebuilt building / monastery / crystal info text
## every frame at 60 Hz — including a linear _building_by_id scan over ALL
## buildings per frame. The static branches are now throttled to 5 Hz via
## _sel_static_gate(delta, n): rebuild on selection change, or after 0.2 s
## of accumulated delta, otherwise skip. Implementation-only: no text,
## layout, or behavior change.
##
## Covers: gate opens on first call / new node, stays closed for small
## deltas under 0.2 s, opens once 0.2 s accumulates, and stays closed again
## after the rebuild resets the accumulator.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hud_static_gate.gd
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


func _initialize() -> void:
	print("=== Cursing Gnomes HUD static-selection gate tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.player_faction = "gnomes"

	var hud = Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	await process_frame

	var node_a: Node = Node.new()
	var node_b: Node = Node.new()

	# First call for a node: gate open (immediate rebuild).
	_check("gate opens on first call", hud._sel_static_gate(0.016, node_a))
	# Same node, tiny delta: gate closed.
	_check("gate closed under 0.2s", not hud._sel_static_gate(0.016, node_a))
	_check("gate closed after 0.1s total", not hud._sel_static_gate(0.084, node_a))
	# Crossing 0.2 s: gate opens once, then closes again.
	_check("gate opens after 0.2s accumulates", hud._sel_static_gate(0.1, node_a))
	_check("gate closed right after rebuild", not hud._sel_static_gate(0.016, node_a))
	# New node: gate opens immediately regardless of accumulator.
	_check("gate opens on node change", hud._sel_static_gate(0.001, node_b))
	_check("gate closed for new node on next frame", not hud._sel_static_gate(0.016, node_b))

	node_a.free()
	node_b.free()
	gs.free()
	hud.queue_free()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
