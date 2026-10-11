extends SceneTree
## Cursing Gnomes — AAA title entrance tests.
##
## Jeremy 2026-10-10 (AAA boot experience): the title screen needs a bold
## entrance — the logo drops in with an overshoot while the tagline, splash,
## buttons, and footer cascade with a staggered fade. Contract:
##  1. The logo starts faded + shrunk and eases to full (TRANS_BACK overshoot).
##  2. Tagline/splash/buttons/footer stagger in (alpha 0 -> 1, delayed).
##  3. The logo shimmer composes on self_modulate.a — no fight with the fade.
##  4. A screen change kills the entrance choreography (no leaked tweens).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_title_entrance.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed := 0
var _failed := 0
var _menu: MainMenu = null


func _check(cond: bool, test_name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + test_name)


func _collect(n: Node, out: Array) -> void:
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		out.append(x)
		for c in x.get_children():
			stack.push_back(c)


func _logo_node() -> Control:
	if is_instance_valid(_menu._logo_rect):
		return _menu._logo_rect
	var all: Array = []
	_collect(_menu, all)
	for x in all:
		if x is Label and (x as Label).text == "Cursing Gnomes":
			return x as Control
	return null


func _init() -> void:
	_menu = MainMenu.new()
	root.add_child(_menu)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_check(_menu._screen == "title", "boots to title screen")
	_test_entrance_starts()
	_test_tweens_registered()
	# Choreography is done by ~1.1s (logo 0.65s, last cascade delay ~0.8s);
	# 2.8s leaves headless scheduling plenty of headroom.
	await create_timer(2.8).timeout
	_test_entrance_settles()
	_test_screen_change_kills()
	_done()


func _test_entrance_starts() -> void:
	var logo := _logo_node()
	_check(logo != null, "entrance: logo node found")
	if logo == null:
		return
	_check(logo.modulate.a < 0.5, "entrance: logo starts faded (alpha in progress)")
	_check(logo.scale.x < 1.0, "entrance: logo starts shrunk (overshoot pending)")
	var all: Array = []
	_collect(_menu, all)
	var faded := 0
	for x in all:
		if x is Control and (x as Control).modulate.a < 0.05:
			faded += 1
	# Tag, splash wrap, 5 buttons, row2, footer (+ logo) all start at alpha 0.
	_check(faded >= 6, "entrance: cascade nodes start hidden (%d)" % faded)


func _test_tweens_registered() -> void:
	_check(_menu._tweens.size() >= 11,
		"entrance: choreography tweens registered (%d)" % _menu._tweens.size())
	for t in _menu._tweens:
		if not is_instance_valid(t):
			_check(false, "entrance: all registered tweens valid")
			return
	_check(true, "entrance: all registered tweens valid")


func _test_entrance_settles() -> void:
	var logo := _logo_node()
	if logo != null:
		_check(logo.modulate.a > 0.99,
			"entrance: logo fade completes (modulate.a=%.2f)" % logo.modulate.a)
		_check(absf(logo.scale.x - 1.0) < 0.01,
			"entrance: logo scale settles at 1.0")
		if is_instance_valid(_menu._logo_rect):
			var sh := _menu._logo_rect.self_modulate.a
			_check(sh > 0.85 and sh <= 1.0,
				"entrance: shimmer rides self_modulate (%.2f)" % sh)
	var all: Array = []
	_collect(_menu, all)
	var lit := 0
	for x in all:
		if x is Control and (x as Control).modulate.a > 0.99:
			lit += 1
	_check(lit >= 6, "entrance: cascade completes, nodes fully lit (%d)" % lit)


func _test_screen_change_kills() -> void:
	_menu._show_settings()
	await process_frame
	_check(_menu._tweens.is_empty(),
		"entrance: screen change kills choreography tweens")


func _done() -> void:
	print("test_title_entrance: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
