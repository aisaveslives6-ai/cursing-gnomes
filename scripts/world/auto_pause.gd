class_name WorldAutoPause
extends RefCounted
## Cursing Gnomes — auto-pause policy when the app leaves the foreground.
##
## Jeremy 2026-10-07 (thermal bug: "iPhone runs hot"): when the browser tab /
## app goes to the background (tab switch, app switch, screen lock), the
## 60 Hz sim + render loop keeps burning for nobody. Auto-pause kills that
## waste and also stops the sim from running away while Jeremy isn't looking.
##
## Rules:
##   - Only pauses when the tree is NOT already paused (never steals a
##     manual pause, never double-pauses).
##   - Only auto-RESUMES when WE did the pausing (_auto_paused). A manual
##     pause stays paused across a background/foreground cycle.
##   - Null tree / null hud: no-op (safe during scene setup/teardown).
##   - Pure policy object so tests can drive it without booting a World.
##     World._notification (NOTIFICATION_WM_WINDOW_FOCUS_OUT/IN) delegates here.


var _auto_paused := false


## True while an auto-pause we issued is still in effect.
func is_auto_paused() -> bool:
	return _auto_paused


## Window lost focus (tab hidden / app backgrounded). Pauses the tree and
## raises the HUD "Paused" badge. Returns true when it actually paused.
func on_focus_out(tree: SceneTree, hud: Hud) -> bool:
	if tree == null or tree.paused:
		return false
	if hud == null or not is_instance_valid(hud):
		return false
	_auto_paused = true
	tree.paused = true
	hud.set_paused(true)
	hud.flash_hint("Auto-paused (app in background).")
	return true


## Window regained focus. Resumes ONLY when our auto-pause is in effect and
## the tree is still paused (the player may have resumed manually, or paused
## manually before backgrounding — both are left alone). Returns true when
## it actually resumed.
func on_focus_in(tree: SceneTree, hud: Hud) -> bool:
	if not _auto_paused:
		return false
	_auto_paused = false
	if tree == null or not tree.paused:
		return false
	tree.paused = false
	if hud != null and is_instance_valid(hud):
		hud.set_paused(false)
		hud.flash_hint("Resumed.")
	return true
