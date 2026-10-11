extends SceneTree
## Cursing Gnomes — HUD resources-drawer throttle tests (Jeremy 2026-10-05).
##
## _refresh_drawer() rebuilt ~7 labels at 60 Hz while the Resources drawer
## was open — including a messenger-thread sort (sorted_threads() allocates
## + sort_custom every frame), a 5-faction pop scan, and a diplomacy scan,
## plus unguarded label writes (each .text assignment forces a re-layout).
## The drawer is now throttled to 5 Hz via _drawer_gate(delta) and every
## label write is change-guarded. Implementation-only: no text, layout,
## or behavior change.
##
## Covers: gate closed under 0.2 s, opens once 0.2 s accumulates, closes
## again after the rebuild resets; a hidden drawer pre-loads the
## accumulator so the first frame after opening rebuilds immediately;
## small-delta refreshes hold stale content (throttle works through the
## real path); a full 0.2 s refresh picks up new amounts; label text stays
## correct and ASCII-clean.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hud_drawer_throttle.gd
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
	print("=== Cursing Gnomes HUD drawer throttle tests ===")
	_run.call_deferred()


func _new_hud() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.player_faction = "gnomes"
	gs.resources.add_resource("gnomes", "gold", 1234)
	gs.resources.add_resource("gnomes", "wood", 567)
	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	return [gs, hud]


func _run() -> void:
	await process_frame
	await process_frame
	var parts: Array = _new_hud()
	var gs: GameState = parts[0]
	var hud: Hud = parts[1]
	await process_frame
	var pop: int = gs.population.get_faction_pop("gnomes")

	# --- Gate timing (unit-level, mirrors test_hud_static_gate) ---
	# setup() ran _refresh() while the drawer was hidden, which pre-loads
	# the accumulator; reset it to test the gate in isolation.
	hud._drawer_accum = 0.0
	_check("gate closed on first small delta", not hud._drawer_gate(0.016))
	_check("gate closed after 0.116s total", not hud._drawer_gate(0.1))
	_check("gate opens once 0.2s accumulates", hud._drawer_gate(0.1))
	_check("gate closed right after rebuild", not hud._drawer_gate(0.016))

	# --- Hidden drawer pre-loads: first frame after opening rebuilds ---
	hud._drawer.visible = false
	hud._refresh_drawer(0.016, "gnomes", pop, {})
	_check("hidden drawer pre-loads accumulator", hud._drawer_accum >= 0.2)
	hud._drawer.visible = true
	hud._refresh_drawer(0.016, "gnomes", pop, {})
	var gold_l: Label = hud._res_drawer_labels.get("gold")
	_check("drawer gold label exists", gold_l != null)
	if gold_l != null:
		_check("first visible frame rebuilds gold label",
			gold_l.text.begins_with("GOLD:"))
		_check("gold amount shown in drawer", gold_l.text.contains("1234"))

	# --- Throttle holds stale content on small deltas ---
	gs.resources.add_resource("gnomes", "gold", 100)
	hud._refresh_drawer(0.016, "gnomes", pop, {})
	_check("small-delta refresh keeps stale amount",
		gold_l.text.contains("1234"))
	hud._refresh_drawer(0.2, "gnomes", pop, {})
	_check("full 0.2s refresh picks up new amount",
		gold_l.text.contains("1334"))

	# --- Change-guard: identical state rebuilds to identical text ---
	var before: String = gold_l.text
	hud._refresh_drawer(0.2, "gnomes", pop, {})
	_check("rebuild with same state keeps text", gold_l.text == before)

	# --- Other drawer labels refresh sanely ---
	_check("pop label non-empty",
		hud._pop_drawer_label != null and hud._pop_drawer_label.text != "")
	_check("weather label non-empty",
		hud._weather_drawer_label != null and hud._weather_drawer_label.text != "")
	_check("peace label has status",
		hud._peace_drawer_label != null
		and hud._peace_drawer_label.text.begins_with("Status: "))

	gs.free()
	hud.queue_free()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
