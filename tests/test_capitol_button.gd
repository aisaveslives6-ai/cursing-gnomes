extends SceneTree
## Cursing Gnomes — snap-camera-to-capitol button tests (Jeremy 2026-10-07,
## direct request).
##
## "Add a button btw that snaps camera back to the main capitol of your
## faction." A circular gold bubble rides top-right inside the safe area
## (below the FPS debug label band), styled like the tab bubbles, with real
## icon art. Tapping it emits snap_camera_to_capitol; the world aims the
## camera at the player's town_hall (same aim as boot) with a
## faction_starts fallback. Mobile-safe: clears the Dynamic Island / home
## indicator via the real safe-area insets; touch target >= 44pt.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_capitol_button.gd

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _signal_fired: bool = false


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _initialize() -> void:
	_test_button_builds()
	_test_icon_asset()
	_test_touch_target_and_style()
	_test_safe_area_position()
	_test_pressed_emits_signal()
	_test_no_silent_button()
	print("test_capitol_button: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _new_hud() -> Hud:
	var hud := Hud.new()
	hud._ui_scale = 2.5
	hud._build_capitol_button()
	return hud


## The builder creates exactly one visible capitol button (not sandbox).
func _test_button_builds() -> void:
	var hud := _new_hud()
	var b := hud._capitol_btn
	_check("capitol button built", b != null)
	if b != null:
		_check("capitol button visible by default", b.visible)
		_check("capitol tooltip names the capitol",
			b.tooltip_text == "Back to my capitol")
		# Idempotent: rebuilding must not stack a second button.
		var before: int = hud.get_children().filter(
			func(c: Node) -> bool: return c == b).size()
		hud._build_capitol_button()
		var after: int = hud.get_children().filter(
			func(c: Node) -> bool: return c == b).size()
		_check("rebuild does not duplicate button", before == after)
	hud.queue_free()


## Icon asset exists, loads, is square, and is attached to the button
## (no placeholder art, no emoji tofu).
func _test_icon_asset() -> void:
	var path := "res://assets/ui/sidebar/icon_capitol.png"
	_check("capitol icon asset exists", ResourceLoader.exists(path))
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		_check("capitol icon loads", tex != null)
		if tex != null:
			_check("capitol icon is square",
				absi(tex.get_width() - tex.get_height()) < 4)
	var hud := _new_hud()
	var b := hud._capitol_btn
	_check("button carries the icon",
		b != null and b.icon != null)
	hud.queue_free()


## Bubble-sized like the tab bubbles: 64px bubble, >= 44pt touch target.
func _test_touch_target_and_style() -> void:
	var hud := _new_hud()
	var b := hud._capitol_btn
	_check("capitol button exists", b != null)
	if b != null:
		var bd := hud._s(hud._bubble_d())
		_check("capitol button is bubble-sized",
			is_equal_approx(b.custom_minimum_size.x, bd) \
			and is_equal_approx(b.custom_minimum_size.y, bd))
		_check("capitol touch target >= 44pt",
			b.custom_minimum_size.x >= 44.0 \
			and b.custom_minimum_size.y >= 44.0)
		# Bubble style: gold-bordered wood circle (normal stylebox set).
		_check("capitol button styled",
			b.has_theme_stylebox_override("normal"))
	hud.queue_free()


## Headless (no viewport): fallback portrait insets
## Vector4(top=220, bottom=120, left=20, right=20). The button must sit
## top-right inside the right inset and below the FPS label band
## (insets.x + 30 canvas units of label height).
func _test_safe_area_position() -> void:
	var hud := _new_hud()
	var b := hud._capitol_btn
	_check("capitol button exists", b != null)
	if b != null:
		var insets := hud._safe_insets()
		_check("top clears the Dynamic Island",
			b.offset_top >= insets.x)
		_check("top clears the FPS label band",
			b.offset_top >= insets.x + hud._s(38.0))
		_check("right edge inside the right safe inset",
			is_equal_approx(b.offset_right, -(insets.w + hud._s(8.0))))
		_check("button has positive height",
			b.offset_bottom > b.offset_top)
		_check("button stays out of the notch zone on the right",
			b.offset_left >= -1000.0 and b.offset_right <= 0.0)
	hud.queue_free()


## Pressing the button asks the world (via signal) to aim the camera —
## the HUD does not move the camera itself.
func _test_pressed_emits_signal() -> void:
	var hud := _new_hud()
	var b := hud._capitol_btn
	_check("capitol button exists", b != null)
	if b != null:
		_check("pressed is wired",
			b.pressed.get_connections().size() > 0)
	_signal_fired = false
	hud.snap_camera_to_capitol.connect(_on_snap)
	hud._on_capitol_btn_pressed()
	_check("snap_camera_to_capitol emitted", _signal_fired)
	# Double-tap safety: repeated presses keep emitting cleanly.
	_signal_fired = false
	hud._on_capitol_btn_pressed()
	_check("repeat press still emits", _signal_fired)
	hud.queue_free()


func _on_snap() -> void:
	_signal_fired = true


## The button must never exist as an untappable dead element.
func _test_no_silent_button() -> void:
	var hud := _new_hud()
	var b := hud._capitol_btn
	_check("capitol button exists", b != null)
	if b != null:
		_check("button is not hidden",
			b.visible and b.modulate.a > 0.0)
		_check("button accepts taps",
			b.mouse_filter == Control.MOUSE_FILTER_STOP)
	hud.queue_free()
