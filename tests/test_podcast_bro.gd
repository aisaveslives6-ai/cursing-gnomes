extends SceneTree
## Cursing Gnomes — Milo the Podcast Bro disaster tests (rapid-iteration
## 2026-10-08, Disaster #29).
##
## Disaster #29: a chibi podcast bro with a backwards cap, headphones, a
## giant mic and a ring light. 0 dmg; the weapon is ENGAGEMENT — citizens
## in range stop working to queue as guests (podcasting flag, honored by
## WorkerAI), feeding the download counter (cap 10k). Interactive like
## Prince Gnomba (#26): he DMs the ruler a sponsor pitch — [Sponsor 300g]
## hypes the town and he leaves to "edit"; [Unplug] cancels the podcast.
## A soldier who closes in confiscates the mics (deplatformed); the 240s
## visit timer ends the episode. Singleton. Own stinger (podcast_arrive),
## own sprite + PodcastFX rig.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_podcast_bro.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no audio output.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class _StubCourt:
	var stories: Array = []
	func publish_story(headline: String, body: String, _kind: String) -> void:
		stories.append({"headline": headline, "body": body})
	func headlines() -> Array:
		var out: Array = []
		for s in stories:
			out.append(String(s.get("headline", "")))
		return out


class _StubPhone:
	var dms: Array = []
	func npc_message(unit_id: int, text: String) -> void:
		dms.append({"unit_id": unit_id, "text": text})
	func is_blocked(_uid: int) -> bool:
		return false


func _initialize() -> void:
	print("=== Cursing Gnomes podcast_bro tests ===")
	seed(20261008)
	_test_def()
	_test_label()
	_test_stinger_mapping()
	_test_stinger_synth()
	_test_spawn_gating()
	_test_spawn_singleton()
	_test_arrival()
	_test_arrival_dm()
	_test_aura_guests()
	_test_aura_excludes_military()
	_test_downloads_cap()
	_test_soldier_deplatform()
	_test_timer_wrap()
	_test_offer_sponsor_poor()
	_test_offer_sponsor_resolves()
	_test_offer_unplug()
	_test_offer_nondirect()
	_test_offer_resolved_ignores()
	_test_phone_hook()
	_test_slain()
	await _test_fx_rig()
	_test_unit_node_wiring()
	_test_art_file()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	var combat = SimCombat.new(gs)
	var d = DisasterSim.new(gs, combat)
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	gs.disasters = d
	gs.court_sys = _StubCourt.new()
	gs.phone_sys = _StubPhone.new()
	return [gs, d]


func _make_town(gs: GameState, tid: int, pos: Vector2, pop: int) -> void:
	gs.towns[tid] = {"id": tid, "faction": "humans", "name": "T%d" % tid,
		"position": pos, "population": pop}


func _citizen(gs: GameState, pos: Vector2, job: String) -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"work_state": "gathering", "stress": 0.0,
	})


func _set_gold(gs: GameState, amount: float) -> void:
	var have: float = gs.resources.get_amount("humans", "gold")
	gs.resources.add_resource("humans", "gold", amount - have, true)


func _arrived(d, gs: GameState) -> Dictionary:
	# Spawn + first tick: town picked, DM sent, offer pending.
	var u: Dictionary = d.spawn("podcast_bro", Vector2(2000, 2000))
	u.erase("podcast_center")
	d._tick_podcast(u, 75.0, 1.0)
	return u


func _at_square(d, gs: GameState, u: Dictionary) -> void:
	# Park Milo in the square so the recording branch runs. Reset the aura
	# cooldown so one tick is enough for the guest sweep to fire.
	var center: Vector2 = u.get("podcast_center", Vector2(2000, 2000))
	u["position"] = center
	u["podcast_aura_cd"] = 0.0
	d._tick_podcast(u, 75.0, 1.0)


func _test_def() -> void:
	_check("def: podcast_bro in MONSTERS", DisasterSim.MONSTERS.has("podcast_bro"))
	var m: Dictionary = DisasterSim.MONSTERS.get("podcast_bro", {})
	_check("def: hp 450", float(m.get("hp", 0.0)) == 450.0)
	_check("def: dmg 0", float(m.get("dmg", 0.0)) == 0.0)
	_check("def: speed 75", float(m.get("speed", 0.0)) == 75.0)
	_check("def: desc mentions subscribe",
		String(m.get("desc", "")).to_lower().contains("subscribe"))


func _test_label() -> void:
	var w := _make_world()
	var d = w[1]
	_check("label: Milo the Podcast Bro",
		d._label_for("podcast_bro") == "Milo the Podcast Bro")


func _test_stinger_mapping() -> void:
	_check("stinger: podcast_arrive mapped",
		DisasterSim.stinger_for_kind("podcast_bro") == "podcast_arrive")


func _test_stinger_synth() -> void:
	var am = AudioManager.new()
	root.add_child(am)
	var segs: Array = am._disaster_stinger_segments("podcast_arrive")
	_check("stinger: segments non-empty", not segs.is_empty())
	_check("stinger: first seg is a tone",
		String(segs[0].get("kind", "")) == "tone")
	var wav = am._synthesize_sfx("podcast_arrive")
	_check("stinger: synthesizes to a stream", wav != null)
	am.queue_free()


func _test_spawn_gating() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	gs.day_number = 5
	d._podcast_day = -1
	var before := gs.units.size()
	d._maybe_spawn_podcast()
	_check("spawn: gated before min day", gs.units.size() == before)
	gs.day_number = 50
	var fired := false
	for i in 60:
		d._podcast_day = -1
		d._maybe_spawn_podcast()
		if gs.units.size() > before:
			fired = true
			break
	_check("spawn: roll runs after min day", fired)


func _test_spawn_singleton() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u1: Dictionary = d.spawn("podcast_bro", Vector2(2000, 2000))
	_check("spawn: milo created", not u1.is_empty())
	_check("spawn: job set", String(u1.get("job", "")) == "podcast_bro")
	var u2: Dictionary = d.spawn("podcast_bro", Vector2(2100, 2100))
	_check("spawn: singleton — second spawn refused", u2.is_empty())
	gs.units.erase(u1)


func _test_arrival() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(1000, 1000), 4)
	_make_town(gs, 2, Vector2(3000, 3000), 12)
	var u: Dictionary = _arrived(d, gs)
	_check("arrival: town picked", u.has("podcast_center"))
	_check("arrival: most populous town chosen",
		String(u.get("podcast_town_name", "")) == "T2")
	_check("arrival: offer pending", String(u.get("podcast_offer", "")) == "pending")
	_check("arrival: visit timer armed", float(u.get("podcast_visit_left", 0.0)) > 0.0)
	_check("arrival: announce story filed",
		(gs.court_sys as _StubCourt).headlines().has("A PODCAST HAS STARTED"))
	gs.units.erase(u)


func _test_arrival_dm() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(1000, 1000), 6)
	var u: Dictionary = _arrived(d, gs)
	var ph = gs.phone_sys
	_check("arrival: DM sent to ruler", ph.dms.size() == 1)
	_check("arrival: DM is the pitch",
		String(ph.dms[0].get("text", "")).contains("MILO EXPERIENCE"))
	_check("arrival: offer pending via public seam",
		d.podcast_offer_pending(int(u.get("id", 0))))
	gs.units.erase(u)


func _test_aura_guests() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	var c: Dictionary = _citizen(gs, Vector2(2050, 2000), "worker")
	_at_square(d, gs, u)
	_check("aura: citizen becomes guest", bool(c.get("podcasting", false)))
	_check("aura: guest work_state idled", String(c.get("work_state", "")) == "idle")
	gs.units.erase(u)
	gs.units.erase(c)


func _test_aura_excludes_military() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	var s: Dictionary = _citizen(gs, Vector2(2050, 2000), "soldier")
	_at_square(d, gs, u)
	_check("aura: soldiers don't go on pods", not bool(s.get("podcasting", false)))
	gs.units.erase(u)
	gs.units.erase(s)


func _test_downloads_cap() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	_citizen(gs, Vector2(2050, 2000), "worker")
	_citizen(gs, Vector2(1950, 2000), "worker")
	u["podcast_aura_cd"] = 0.0
	_at_square(d, gs, u)
	var dl := float(u.get("podcast_downloads", 0.0))
	_check("aura: downloads accrue", dl > 0.0)
	u["podcast_downloads"] = 9990.0
	u["podcast_aura_cd"] = 0.0
	_at_square(d, gs, u)
	_check("aura: downloads capped at 10k",
		float(u.get("podcast_downloads", 0.0)) == 10000.0)
	_check("aura: viral story filed",
		(gs.court_sys as _StubCourt).headlines().has("MILO GOES VIRAL"))
	gs.units.erase(u)


func _test_soldier_deplatform() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	var c: Dictionary = _citizen(gs, Vector2(2050, 2000), "worker")
	_at_square(d, gs, u)
	_check("deplatform: guest seated before", bool(c.get("podcasting", false)))
	var s: Dictionary = _citizen(gs, Vector2(2060, 2000), "soldier")
	_at_square(d, gs, u)
	_check("deplatform: leaving", bool(u.get("leaving", false)))
	_check("deplatform: guests cleared", not bool(c.get("podcasting", false)))
	_check("deplatform: story filed",
		(gs.court_sys as _StubCourt).headlines().has("MILO GOT DEPLATFORMED"))
	gs.units.erase(u)
	gs.units.erase(c)
	gs.units.erase(s)


func _test_timer_wrap() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	_at_square(d, gs, u)
	u["podcast_visit_left"] = 0.5
	d._tick_podcast(u, 75.0, 1.0)
	_check("wrap: leaving", bool(u.get("leaving", false)))
	_check("wrap: story filed",
		(gs.court_sys as _StubCourt).headlines().has("THAT'S A WRAP"))
	gs.units.erase(u)


func _test_offer_sponsor_poor() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	_set_gold(gs, 100.0)
	var u: Dictionary = _arrived(d, gs)
	var before: float = gs.resources.get_amount("humans", "gold")
	var reply: String = d.podcast_offer_reply(u, "sponsor")
	_check("sponsor-poor: broke reply", reply.to_lower().contains("empty"))
	_check("sponsor-poor: offer still pending",
		String(u.get("podcast_offer", "")) == "pending")
	_check("sponsor-poor: no gold moved",
		gs.resources.get_amount("humans", "gold") == before)
	_check("sponsor-poor: not leaving", not bool(u.get("leaving", false)))
	gs.units.erase(u)


func _test_offer_sponsor_resolves() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	_set_gold(gs, 1000.0)
	var u: Dictionary = _arrived(d, gs)
	var before: float = gs.resources.get_amount("humans", "gold")
	var reply: String = d.podcast_offer_reply(u, "sponsor")
	_check("sponsor: hype reply", reply.contains("ALPHA"))
	_check("sponsor: 300g moved",
		before - gs.resources.get_amount("humans", "gold") == 300.0)
	_check("sponsor: leaving", bool(u.get("leaving", false)))
	_check("sponsor: story filed",
		(gs.court_sys as _StubCourt).headlines().has(
			"RULER SPONSORS THE MILO EXPERIENCE"))
	_check("sponsor: offer no longer pending",
		not d.podcast_offer_pending(int(u.get("id", 0))))
	gs.units.erase(u)


func _test_offer_unplug() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	var c: Dictionary = _citizen(gs, Vector2(2050, 2000), "worker")
	_at_square(d, gs, u)
	var reply: String = d.podcast_offer_reply(u, "unplug")
	_check("unplug: censored reply", reply.to_lower().contains("censored"))
	_check("unplug: leaving", bool(u.get("leaving", false)))
	_check("unplug: guests cleared", not bool(c.get("podcasting", false)))
	_check("unplug: story filed",
		(gs.court_sys as _StubCourt).headlines().has("PODCAST CANCELED"))
	gs.units.erase(u)
	gs.units.erase(c)


func _test_offer_nondirect() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	_check("nondirect: chat falls through",
		d.podcast_offer_reply(u, "nice ring light") == "")
	_check("nondirect: offer still pending",
		String(u.get("podcast_offer", "")) == "pending")
	gs.units.erase(u)


func _test_offer_resolved_ignores() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	d.podcast_offer_reply(u, "unplug")
	_check("resolved: later verdict ignored",
		d.podcast_offer_reply(u, "sponsor") == "")
	gs.units.erase(u)


func _test_phone_hook() -> void:
	# SimPhone._npc_reply routes the offer verdict through the disaster
	# sim before the conversation engine (mirrors the Gnomba hook).
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	gs.phone_sys = SimPhone.new(gs)
	gs.player_faction = "humans"
	var reply: String = gs.phone_sys._npc_reply(u, "unplug")
	_check("phone: unplug resolves via hook", reply.to_lower().contains("censored"))
	_check("phone: chat falls through",
		gs.phone_sys._npc_reply(u, "nice ring light") != "")
	gs.units.erase(u)


func _test_slain() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(2000, 2000), 8)
	var u: Dictionary = _arrived(d, gs)
	var c: Dictionary = _citizen(gs, Vector2(2050, 2000), "worker")
	_at_square(d, gs, u)
	u["alive"] = false
	d._check_dead_disaster(u)
	_check("slain: canceled-permanently story",
		(gs.court_sys as _StubCourt).headlines().has(
			"PODCAST CANCELED (PERMANENTLY)"))
	_check("slain: guests cleared", not bool(c.get("podcasting", false)))
	gs.units.erase(u)
	gs.units.erase(c)


func _test_fx_rig() -> void:
	var fx := PodcastFX.new()
	root.add_child(fx)
	await process_frame
	fx._process(1.0)
	_check("fx: mic cycle in 0..1",
		fx._mic_cycle(0) >= 0.0 and fx._mic_cycle(0) < 1.0)
	_check("fx: wave cycle in 0..1",
		fx._wave_cycle(0) >= 0.0 and fx._wave_cycle(0) < 1.0)
	_check("fx: sign glow in 0..1",
		fx._sign_glow() >= 0.0 and fx._sign_glow() <= 1.0)
	_check("fx: stage_h default sane", fx.stage_h == 64.0)
	fx.queue_free()


func _test_unit_node_wiring() -> void:
	_check("wiring: job registered",
		"podcast_bro" in UnitNode._MONSTER_JOBS)
	var n := UnitNode.new()
	n.job = "podcast_bro"
	_check("wiring: art texture resolves", n._monster_texture() != null)
	n.queue_free()


func _test_art_file() -> void:
	# The bespoke chibi art exists and is white-keyed (same artifact
	# definition as test_art_whitesweep.gd).
	var path := "assets/art/animals/podcast_bro.png"
	_check("art: file exists", FileAccess.file_exists(path))
	var img := Image.load_from_file(path)
	_check("art: loads", img != null)
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	var border_opaque := 0
	for x in w:
		for y in [0, h - 1]:
			if img.get_pixel(x, y).a > 0.78:
				border_opaque += 1
	for y in h:
		for x in [0, w - 1]:
			if img.get_pixel(x, y).a > 0.78:
				border_opaque += 1
	_check("art: zero opaque border pixels", border_opaque == 0)
