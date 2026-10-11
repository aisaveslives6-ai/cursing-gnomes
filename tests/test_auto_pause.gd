extends SceneTree
## Regression tests for Jeremy 2026-10-07 thermal bug ("iPhone runs hot"):
## auto-pause when the app leaves the foreground.
##
## When the browser tab / app backgrounds (tab switch, app switch, screen
## lock), the 60 Hz sim + render loop kept burning for nobody. World now
## routes NOTIFICATION_WM_WINDOW_FOCUS_OUT/IN through WorldAutoPause:
## backgrounding pauses, foregrounding resumes ONLY when we auto-paused —
## a manual pause is never stolen and never auto-resumed.
##
## Run: Godot --headless --path . -s res://tests/test_auto_pause.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("FAIL: ", name)


func _initialize() -> void:
	_test_focus_out_pauses()
	_test_focus_in_resumes_only_ours()
	_test_manual_pause_never_stolen()
	_test_manual_pause_stays_paused()
	_test_null_safety()
	_test_idempotent()
	print("test_auto_pause: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _new_hud() -> Hud:
	var hud := Hud.new()
	root.add_child(hud)
	return hud


## Backgrounding a running game pauses the tree, raises the HUD badge, and
## marks the auto-pause flag.
func _test_focus_out_pauses() -> void:
	var hud := _new_hud()
	var ap := WorldAutoPause.new()
	self.paused = false
	var did := ap.on_focus_out(self, hud)
	_check("focus-out pauses a running tree", did and self.paused)
	_check("auto-paused flag set", ap.is_auto_paused())
	self.paused = false
	hud.queue_free()


## Foregrounding resumes when (and only when) our auto-pause is in effect.
func _test_focus_in_resumes_only_ours() -> void:
	var hud := _new_hud()
	var ap := WorldAutoPause.new()
	self.paused = false
	ap.on_focus_out(self, hud)
	var did := ap.on_focus_in(self, hud)
	_check("focus-in resumes our auto-pause", did and not self.paused)
	_check("auto-paused flag cleared", not ap.is_auto_paused())
	# Foreground with no auto-pause outstanding: no-op.
	self.paused = false
	var ap2 := WorldAutoPause.new()
	_check("focus-in without auto-pause is a no-op", not ap2.on_focus_in(self, hud))
	_check("tree untouched", not self.paused)
	hud.queue_free()


## A manual pause is never stolen: backgrounding while manually paused does
## not flip the auto-pause flag.
func _test_manual_pause_never_stolen() -> void:
	var hud := _new_hud()
	var ap := WorldAutoPause.new()
	self.paused = true  # Jeremy paused via the drawer menu
	var did := ap.on_focus_out(self, hud)
	_check("focus-out does not steal a manual pause", not did)
	_check("auto-paused flag stays clear", not ap.is_auto_paused())
	self.paused = false
	hud.queue_free()


## Manual pause stays paused across a background/foreground cycle: if the
## player paused, backgrounded, and foregrounded, the game must NOT resume.
func _test_manual_pause_stays_paused() -> void:
	var hud := _new_hud()
	var ap := WorldAutoPause.new()
	self.paused = true  # manual pause first
	ap.on_focus_out(self, hud)  # then background (no-op: already paused)
	var did := ap.on_focus_in(self, hud)  # then foreground
	_check("foreground does not resume a manual pause", not did and self.paused)
	self.paused = false
	hud.queue_free()


## Null tree / null hud are safe no-ops (scene setup/teardown).
func _test_null_safety() -> void:
	var hud := _new_hud()
	var ap := WorldAutoPause.new()
	_check("null tree focus-out is a no-op", not ap.on_focus_out(null, hud))
	_check("null hud focus-out is a no-op", not ap.on_focus_out(self, null))
	_check("flag clear after null no-ops", not ap.is_auto_paused())
	_check("null tree focus-in is a no-op", not ap.on_focus_in(null, hud))
	hud.queue_free()


## Double background events don't double-pause; a resume after the player
## already resumed manually leaves the tree alone.
func _test_idempotent() -> void:
	var hud := _new_hud()
	var ap := WorldAutoPause.new()
	self.paused = false
	ap.on_focus_out(self, hud)
	_check("second focus-out is a no-op (already paused)",
		not ap.on_focus_out(self, hud))
	# Player resumes manually via the drawer while backgrounded...
	self.paused = false
	var did := ap.on_focus_in(self, hud)
	_check("foreground after manual resume leaves tree alone",
		not did and not self.paused)
	_check("flag cleared even when tree already resumed",
		not ap.is_auto_paused())
	hud.queue_free()
