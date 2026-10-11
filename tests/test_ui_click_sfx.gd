extends SceneTree
## Cursing Gnomes — UI tap feedback tests (2026-10-09 rapid-iteration).
##
## Every button press anywhere (menu, phone, HUD, dialogs, keyboard keys)
## must click: UITapSfx wires each Button's `pressed` to the Events
## autoload's ui_click signal, and AudioManager answers with the
## synthesized "click" (which sat in the synth registry with zero callers
## per the 2026-10-09 SFX audit).
##
## Frame-safety: in -s SceneTree scripts, add_child during _initialize
## DEFERS _ready to the first frame, so every _ready-dependent assertion
## runs in _process at frame >= 2 (probed 2026-10-09). The Events autoload
## is fetched via get_node_or_null — bare autoload identifiers don't
## resolve in headless -s runs (cf. world.gd's Game fetch).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ui_click_sfx.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


const TapScript := preload("res://scripts/audio/ui_tap_sfx.gd")


class ClickSpy:
	extends AudioManager
	var played: Array[String] = []

	func play_sfx(sfx_name: String) -> void:
		played.append(sfx_name)


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _hits: int = 0
var _frame: int = 0
var _bus: EventBus = null
var _spy: ClickSpy = null


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	print("=== Cursing Gnomes ui-click-sfx tests ===")
	_bus = root.get_node_or_null("Events") as EventBus
	_check("bus: Events autoload present", _bus != null)
	_check("bus: ui_click signal exists",
		_bus != null and _bus.has_signal("ui_click"))
	if _bus != null:
		_bus.ui_click.connect(func() -> void: _hits += 1)
	_test_click_sound_synthesized()
	# The spy's _ready (bus connect) runs on frame 1; routing asserts on frame 2.
	_spy = ClickSpy.new()
	root.add_child(_spy)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_run_ready_asserts()
		print("=== %d passed, %d failed ===" % [_passed, _failed])
		for f: String in _failures:
			print("  FAIL: ", f)
		return true  # quit the tree
	return false


func _test_click_sound_synthesized() -> void:
	# _get_sfx is _ready-independent (lazy synth + cache); no add_child needed.
	var am := AudioManager.new()
	var wav: AudioStreamWAV = am._get_sfx("click")
	_check("sfx: click synthesizes a stream", wav != null)
	if wav != null:
		_check("sfx: click stream has samples", wav.data.size() > 0)
	# Cached on second fetch (no re-synth).
	_check("sfx: click cached", am._get_sfx("click") == wav)
	am.free()


func _run_ready_asserts() -> void:
	_test_routing()
	_test_guard_single_connect()
	_test_tap_wiring()


func _test_routing() -> void:
	_spy.play_ui_click()
	_check("audio: play_ui_click plays click",
		_spy.played.size() == 1 and _spy.played[0] == "click")
	_bus.ui_click.emit()
	_check("audio: bus ui_click reaches play_ui_click",
		_spy.played.size() == 2 and _spy.played[1] == "click")


func _test_guard_single_connect() -> void:
	# Spy is still connected here; disconnect + remove it so later emits
	# don't reach a half-freed manager (playback ERROR noise).
	if _bus.ui_click.is_connected(_spy.play_ui_click):
		_bus.ui_click.disconnect(_spy.play_ui_click)
	root.remove_child(_spy)
	_spy.queue_free()
	_spy = null
	var before := _bus.ui_click.get_connections().size()
	var am := AudioManager.new()
	root.add_child(am)  # _ready runs synchronously: tree is live in _process
	var after := _bus.ui_click.get_connections().size()
	_check("audio: one ui_click connection per manager", after == before + 1)
	if _bus.ui_click.is_connected(am.play_ui_click):
		_bus.ui_click.disconnect(am.play_ui_click)
	root.remove_child(am)
	am.queue_free()


func _test_tap_wiring() -> void:
	# Tree is live in _process: add_child runs _ready synchronously.
	var tap: Node = TapScript.new()
	var pre := Button.new()
	root.add_child(pre)  # pre-existing button: caught by the _ready sweep
	root.add_child(tap)
	_hits = 0
	pre.pressed.emit()
	_check("tap: pre-existing button clicks", _hits == 1)
	_check("tap: button carries wire meta", pre.has_meta("_cg_click_wired"))

	var late := Button.new()
	root.add_child(late)  # late button: caught by node_added
	late.pressed.emit()
	_check("tap: late-added button clicks", _hits == 2)

	pre.pressed.emit()
	late.pressed.emit()
	_check("tap: exactly one click per press", _hits == 4)

	root.remove_child(late)
	root.add_child(late)  # re-add: meta guard must prevent double-wiring
	late.pressed.emit()
	_check("tap: re-added button still single-wired", _hits == 5)

	var lab := Label.new()
	root.add_child(lab)
	_check("tap: non-Button controls untouched",
		not lab.has_meta("_cg_click_wired"))

	root.remove_child(tap)
	tap.queue_free()
	pre.queue_free()
	late.queue_free()
	lab.queue_free()
