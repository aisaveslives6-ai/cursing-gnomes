extends SceneTree
## Cursing Gnomes — notification queue cap tests
## (Jeremy 2026-10-10, POLISH MODE menu-scroll audit / polish).
##
## Polish finding: PhoneUI._notif_queue was unbounded — a war + disaster
## + petition burst could stack minutes of banners (each holds ~3.75s).
## Fix: pending banners are capped at MAX_PENDING_NOTIFICATIONS (5);
## newest wins, the oldest pending notification drops.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_notif_queue_cap.gd
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
	print("=== Cursing Gnomes notification queue cap tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	await process_frame

	_test_cap(ui)
	_test_newest_wins(ui)
	_test_drain_still_works(ui)

	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		ui.queue_free()
		gs.queue_free()
		quit(1)
	else:
		ui.queue_free()
		gs.queue_free()
		quit(0)


## A 9-notification burst: first shows immediately, 5 queue, rest drop.
func _test_cap(ui: PhoneUI) -> void:
	_check("cap constant is 5", ui.MAX_PENDING_NOTIFICATIONS == 5)
	for i in 9:
		ui.show_notification("N%d" % i, "body %d" % i, "")
	_check("first banner shows immediately", ui._notif_current != null)
	_check("queue capped at 5 (got %d)" % ui._notif_queue.size(),
		ui._notif_queue.size() == 5)
	ui._dismiss_notification()
	for i in 6:
		ui._dismiss_notification()


## Newest wins: the oldest pending notifications are the ones dropped.
func _test_newest_wins(ui: PhoneUI) -> void:
	for i in 9:
		ui.show_notification("N%d" % i, "body %d" % i, "")
	# Showing: N0. Queued: N4..N8 (N1..N3 dropped as oldest pending).
	_check("queue holds the newest pending (front=N4)",
		String(ui._notif_queue[0]["title"]) == "N4")
	_check("queue holds the newest pending (back=N8)",
		String(ui._notif_queue[4]["title"]) == "N8")
	ui._dismiss_notification()  # N0 done -> N4 shows
	_check("next banner is the newest survivor (N4)",
		ui._notif_queue.size() == 4
		and String(ui._notif_queue[0]["title"]) == "N5")
	for i in 6:
		ui._dismiss_notification()
	_check("queue fully drains", ui._notif_queue.is_empty()
		and ui._notif_current == null)


## The cap must not break the normal show/dismiss cycle.
func _test_drain_still_works(ui: PhoneUI) -> void:
	ui.show_notification("Solo", "lone banner", "")
	_check("single banner shows", ui._notif_current != null)
	_check("no queue for a single banner", ui._notif_queue.is_empty())
	ui._dismiss_notification()
	_check("single banner dismisses clean", ui._notif_current == null)
