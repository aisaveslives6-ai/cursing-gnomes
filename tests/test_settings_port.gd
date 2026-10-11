extends SceneTree
## Cursing Gnomes — settings port tests (headless).
##
## Covers the settings gaps ported from the HTML build:
##   1. AI Aggression setting exists in UI defaults + storage (HTML parity:
##      the HTML stored it but never consumed it — same here, no invented
##      mechanics).
##   2. Share Diagnostics setting exists (opt-in, consent-gated queue,
##      manual share — no auto-upload).
##   3. Graphics / labels / tree sway settings actually apply their effects:
##      tier resolution + knobs, particle budgets, tree draw budget, unit
##      sync cadence, label visibility rule, sway toggle, ground-detail
##      grass gate.


var _passed := 0
var _failed := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + name)


func _init() -> void:
	_test_tier_resolution()
	_test_tier_knobs()
	_test_ground_detail()
	_test_settings_file_roundtrip()
	# Node tests need the tree settled — defer one frame.
	_test_nodes.call_deferred()


func _test_nodes() -> void:
	await process_frame
	_test_diagnostics()
	_test_sway()
	_test_weather_particles()
	_test_grass_gate()
	_test_menu_defaults()


func _finish() -> void:
	print("test_settings_port: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ------------------------------------------------------- tier resolution

func _test_tier_resolution() -> void:
	_check(GraphicsTiers.resolve("low") == "low", "manual low passes through")
	_check(GraphicsTiers.resolve("medium") == "medium", "manual medium passes through")
	_check(GraphicsTiers.resolve("high") == "high", "manual high passes through")
	_check(GraphicsTiers.resolve("ultra") == "ultra", "manual ultra passes through")
	_check(GraphicsTiers.resolve("ULTRA") == "ultra", "tier normalized to lowercase")
	_check(GraphicsTiers.resolve("bogus") == "medium", "invalid tier falls back to medium")
	var auto_tier := GraphicsTiers.resolve("auto")
	_check(auto_tier in GraphicsTiers.TIERS, "auto resolves to a real tier")
	_check(GraphicsTiers.resolve("") in GraphicsTiers.TIERS, "blank resolves to a real tier")
	# Jeremy's rule: graphics default to Auto everywhere.
	_check(GraphicsTiers.read_user_settings() is Dictionary, "settings file reader returns dict")


func _test_tier_knobs() -> void:
	# HTML applyGraphicsTier numbers, verbatim.
	var ultra := GraphicsTiers.knobs("ultra")
	_check(float(ultra["particle_mul"]) == 0.9, "ultra particleMul 0.9")
	_check(int(ultra["unit_sync_every"]) == 1, "ultra unitUpdateEvery 1")
	_check(float(ultra["tree_draw_frac"]) == 1.0, "ultra tree frac 1.0")
	var high := GraphicsTiers.knobs("high")
	_check(float(high["particle_mul"]) == 0.75, "high particleMul 0.75")
	_check(int(high["unit_sync_every"]) == 1, "high unitUpdateEvery 1")
	_check(float(high["tree_draw_frac"]) == 0.4375, "high tree frac 0.4375")
	var medium := GraphicsTiers.knobs("medium")
	_check(float(medium["particle_mul"]) == 0.5, "medium particleMul 0.5")
	_check(int(medium["unit_sync_every"]) == 2, "medium unitUpdateEvery 2")
	_check(float(medium["tree_draw_frac"]) == 0.275, "medium tree frac 0.275")
	var low := GraphicsTiers.knobs("low")
	_check(float(low["particle_mul"]) == 0.15, "low particleMul 0.15")
	_check(int(low["unit_sync_every"]) == 4, "low unitUpdateEvery 4")
	_check(float(low["tree_draw_frac"]) == 0.1, "low tree frac 0.1")
	_check(float(GraphicsTiers.knobs("bogus")["particle_mul"]) == 0.15,
		"unknown tier falls back to low knobs")


func _test_ground_detail() -> void:
	# HTML effGroundDetail: auto follows the tier.
	_check(GraphicsTiers.eff_ground_detail("auto", "ultra") == "high",
		"ground auto on ultra -> high")
	_check(GraphicsTiers.eff_ground_detail("auto", "high") == "high",
		"ground auto on high -> high")
	_check(GraphicsTiers.eff_ground_detail("auto", "medium") == "medium",
		"ground auto on medium -> medium")
	_check(GraphicsTiers.eff_ground_detail("auto", "low") == "low",
		"ground auto on low -> low")
	_check(GraphicsTiers.eff_ground_detail("low", "ultra") == "low",
		"manual ground detail respected")
	_check(GraphicsTiers.eff_ground_detail("bogus", "ultra") == "medium",
		"invalid ground detail falls back to medium")


func _test_settings_file_roundtrip() -> void:
	# read_user_settings never throws, even with no file.
	var s := GraphicsTiers.read_user_settings()
	_check(s is Dictionary, "settings read returns dict without file")


# ------------------------------------------------------------- diagnostics

func _test_diagnostics() -> void:
	var d := Diagnostics.new()
	root.add_child(d)
	# Disabled by default: nothing collected, nothing sent.
	_check(not d.enabled, "diagnostics disabled by default")
	d.record("crash", "boom")
	d.enqueue("perf-aggregate", {"fps_avg": 60.0})
	_check(d.load_queue().is_empty(), "no collection while disabled")
	_check(d.send_now() == "", "send_now refuses while disabled")
	# UUID shape: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx.
	var uuid := Diagnostics.make_uuid()
	var parts := uuid.split("-")
	_check(parts.size() == 5, "uuid has 5 groups")
	_check(parts[0].length() == 8 and parts[1].length() == 4
		and parts[2].length() == 4 and parts[3].length() == 4
		and parts[4].length() == 12, "uuid group lengths")
	_check(parts[2].begins_with("4"), "uuid v4 marker")
	_check(parts[3].substr(0, 1) in ["8", "9", "a", "b"], "uuid variant marker")
	# Enabled: bounded queue (HTML MAX_QUEUE = 10).
	d.configure(true)
	_check(d.enabled, "diagnostics enables")
	for i in 15:
		d.enqueue("note", {"i": i})
	var q := d.load_queue()
	_check(q.size() == Diagnostics.MAX_QUEUE, "queue bounded at MAX_QUEUE")
	_check(int((q[q.size() - 1] as Dictionary).get("i", -1)) == 14,
		"queue keeps newest reports")
	_check((q[0] as Dictionary).has("player_id"), "reports carry anonymous player id")
	_check((q[0] as Dictionary).has("hw"), "reports carry hardware info")
	# Report envelope shape (HTML baseReport parity).
	var rep := d.collect_report("manual")
	_check(rep.has("type") and rep.has("at") and rep.has("build")
		and rep.has("player_id") and rep.has("hw") and rep.has("tier")
		and rep.has("fps"), "report envelope has all fields")
	var hw := Diagnostics.hardware_info()
	_check(hw.has("os") and hw.has("processors") and hw.has("engine"),
		"hardware info has os/processors/engine")
	# Share text is human-readable and states the privacy model.
	var text := d.build_share_text()
	_check("Cursing Gnomes diagnostics" in text, "share text header")
	_check("no personal data" in text, "share text states no personal data")
	# Opt-out clears the queue (HTML parity).
	d.configure(false)
	_check(d.load_queue().is_empty(), "opt-out clears the queue")
	d.queue_free()


# ------------------------------------------------------------------- sway

func _test_sway() -> void:
	# Static toggle defaults on (HTML treeSwayOn = true).
	_check(MapProp.sway_enabled, "sway enabled by default")
	var prop := MapProp.new()
	root.add_child(prop)
	prop.setup("tree", Vector2(100, 200))
	MapProp.sway_enabled = false
	MapProp.sway_zoom_ok = true
	prop.rotation = 0.3
	prop._process(0.016)
	_check(prop.rotation == 0.0, "sway off -> perfectly still")
	MapProp.sway_enabled = true
	MapProp.sway_zoom_ok = false
	prop._process(0.016)
	_check(prop.rotation == 0.0, "sway zoom gate holds trees still")
	MapProp.sway_zoom_ok = true
	# Perf 2026-10-04: sway updates are throttled to every 4th frame with a
	# per-tree stagger. Force this tree's bucket onto the current frame so
	# the direct _process call below takes the update path.
	prop._sway_bucket = Engine.get_process_frames() % 4
	prop._process(0.016)
	_check(prop.rotation != 0.0, "sway on -> tree rotates")
	_check(absf(prop.rotation) <= 0.02, "sway amplitude small (HTML 0.014)")
	# Value parity: the throttled pose is exactly what the unthrottled
	# formula computes at this moment (wall-clock sampling, no drift).
	var expect := sin(MapProp.sway_time() * MapProp.SWAY_SPEED \
		+ prop._sway_phase) * MapProp.SWAY_AMP
	_check(is_equal_approx(prop.rotation, expect),
		"sway value matches unthrottled formula")
	# sway_time() is cached per frame: one native call, not one per tree.
	_check(MapProp.sway_time() == MapProp.sway_time(),
		"sway_time cached within a frame")
	# Visibility gating: hidden trees stop _process entirely (tier budget /
	# paper-map LOD), and resume when shown again.
	prop.visible = false
	_check(not prop.is_processing(), "hidden tree stops processing")
	prop.visible = true
	_check(prop.is_processing(), "reshown tree resumes processing")
	# Resource diamonds never sway and never process.
	var rock := MapProp.new()
	root.add_child(rock)
	rock.setup("res_gold", Vector2(300, 400))
	rock._process(0.016)
	_check(rock.rotation == 0.0, "resource props never sway")
	_check(not rock.is_processing(), "resource props never process")
	MapProp.sway_enabled = true
	MapProp.sway_zoom_ok = true
	prop.queue_free()
	rock.queue_free()


# ------------------------------------------------------ weather particles

func _test_weather_particles() -> void:
	var w := WeatherFX.new()
	root.add_child(w)
	w._rng.seed = 1
	w._build_pools()
	_check(w.particle_mul == 1.0, "particle mul defaults to 1.0")
	w.set_particle_mul(0.5)
	_check(w.particle_mul == 0.5, "particle mul sets")
	w.set_particle_mul(99.0)
	_check(w.particle_mul == 1.0, "particle mul clamps high")
	w.set_particle_mul(-1.0)
	_check(w.particle_mul == 0.05, "particle mul clamps low")
	w.set_particle_mul(0.5)
	w.force_weather("rain")
	w._update_particles(0.016)
	var active := 0
	for dr in w._rain:
		if (dr as Line2D).visible:
			active += 1
	_check(active == int(WeatherFX.RAIN_DROPS * 0.5),
		"rain pool scaled by particle mul")
	w.queue_free()


# ------------------------------------------------------------- grass gate

func _test_grass_gate() -> void:
	var g := GrassTufts.new()
	root.add_child(g)
	var cam := Camera2D.new()
	root.add_child(cam)
	g.setup(Rect2(0, 0, 4000, 4000), cam, "high")
	# Zoomed out: hidden.
	cam.zoom = Vector2(0.5, 0.5)
	g.refresh(cam, "high", false)
	_check(not g.visible, "grass hidden when zoomed out")
	# Zoomed in, high detail, not winter: shown.
	cam.zoom = Vector2(1.0, 1.0)
	g.refresh(cam, "high", false)
	_check(g.visible, "grass shown zoomed in on high")
	# Winter: hidden.
	g.refresh(cam, "high", true)
	_check(not g.visible, "grass hidden in winter")
	# Low detail: hidden even zoomed in.
	g.refresh(cam, "low", false)
	_check(not g.visible, "grass hidden on low detail")
	# Ultra detail counts as high-or-better.
	g.refresh(cam, "ultra", false)
	_check(g.visible, "grass shown on ultra detail")
	g.queue_free()
	cam.queue_free()


# --------------------------------------------------------- menu defaults

func _test_menu_defaults() -> void:
	var menu := MainMenu.new()
	root.add_child(menu)
	# _load_settings runs in _ready; force it for the headless check.
	menu._load_settings()
	_check(String(menu.get_setting("ai_aggression", "")) == "normal",
		"AI aggression defaults to normal")
	_check(menu.get_setting("share_diagnostics", true) == false,
		"share diagnostics defaults OFF (opt-in)")
	_check(String(menu.get_setting("graphics", "")) == "auto",
		"graphics defaults to Auto (Jeremy's rule)")
	menu.queue_free()
	_finish()
