extends SceneTree
## Cursing Gnomes — Prince Gnomba disaster tests (wake deep-work
## 2026-10-08, original content).
##
## Disaster #26: a Nigerian-prince email scammer in gnome form. 0 dmg; the
## weapon is CONFIDENCE. On arrival he DMs the ruler a 100%-legitimate
## treasury-unlock proposal; the Messenger thread gets inline
## [Send 500g] / [Block & Report] buttons (war-counsel pattern). While
## the con is pending, his aura skims "processing fees" off the town's
## treasury (capped 150/visit). Send the gold and he might double it —
## or rug. Blocked/deported/visa-expired/slain all file Gazette beats.
## Singleton. Own stinger (gnomba_arrive), own sprite + GnombaFX rig.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_prince_gnomba.gd
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
	print("=== Cursing Gnomes prince_gnomba tests ===")
	seed(20261008)
	_test_def()
	_test_label()
	_test_stinger_mapping()
	_test_stinger_synth()
	_test_spawn_singleton()
	_test_arrival_dm()
	_test_scam_send_poor()
	_test_scam_send_resolves()
	_test_scam_block()
	_test_scam_non_verdict()
	_test_scam_no_double_dip()
	_test_aura_skim()
	_test_aura_cap()
	_test_soldier_deport()
	_test_visa_expiry()
	_test_slain_story()
	_test_phone_reply_hook()
	_test_art()
	await _test_fx_rig()
	_test_unit_node_wiring()
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
	# Spawn + first tick: town picked, DM sent, scam pending.
	var u: Dictionary = d.spawn("prince_gnomba", Vector2(2000, 2000))
	u.erase("gnomba_center")
	d._tick_gnomba(u, 80.0, 1.0)
	return u


func _test_def() -> void:
	_check("def: prince_gnomba in MONSTERS", DisasterSim.MONSTERS.has("prince_gnomba"))
	var m: Dictionary = DisasterSim.MONSTERS.get("prince_gnomba", {})
	_check("def: hp 500", float(m.get("hp", 0.0)) == 500.0)
	_check("def: dmg 0", float(m.get("dmg", 0.0)) == 0.0)
	_check("def: speed 80", float(m.get("speed", 0.0)) == 80.0)
	_check("def: desc mentions prince", String(m.get("desc", "")).to_lower().contains("prince"))


func _test_label() -> void:
	var w := _make_world()
	var d = w[1]
	_check("label: Prince Gnomba", d._label_for("prince_gnomba") == "Prince Gnomba")


func _test_stinger_mapping() -> void:
	_check("stinger: gnomba_arrive mapped",
		DisasterSim.stinger_for_kind("prince_gnomba") == "gnomba_arrive")
	_check("stinger: distinct from influencer",
		DisasterSim.stinger_for_kind("prince_gnomba") != DisasterSim.stinger_for_kind("influencer_gnome"))


func _test_stinger_synth() -> void:
	var am = AudioManager.new()
	root.add_child(am)
	var segs: Array = am._disaster_stinger_segments("gnomba_arrive")
	_check("stinger: segments non-empty", not segs.is_empty())
	_check("stinger: first seg is a tone", String(segs[0].get("kind", "")) == "tone")
	var total := 0.0
	for s in segs:
		var sd: Dictionary = s
		total = maxf(total, float(sd.get("atk", 0.0)) + float(sd.get("dur", 0.0)))
	_check("stinger: under 1.2s (%.2fs)" % total, total <= 1.2)
	am.queue_free()


func _test_spawn_singleton() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u1: Dictionary = d.spawn("prince_gnomba", Vector2(2000, 2000))
	_check("spawn: prince created", not u1.is_empty())
	_check("spawn: job set", String(u1.get("job", "")) == "prince_gnomba")
	var u2: Dictionary = d.spawn("prince_gnomba", Vector2(2100, 2100))
	_check("spawn: singleton — second spawn refused", u2.is_empty())
	gs.units.erase(u1)


func _test_arrival_dm() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = _arrived(d, gs)
	_check("arrival: town picked", u.has("gnomba_center"))
	_check("arrival: scam pending", String(u.get("gnomba_scam", "")) == "pending")
	_check("arrival: visit timer armed", float(u.get("gnomba_visit_left", 0.0)) > 0.0)
	var ph = gs.phone_sys
	_check("arrival: DM sent to ruler", ph.dms.size() == 1)
	_check("arrival: DM is the pitch",
		String(ph.dms[0].get("text", "")).contains("PRINCE GNOMBA"))
	_check("arrival: scam pending via public seam",
		d.gnomba_scam_pending(int(u.get("id", 0))))
	_check("arrival: announce story filed",
		(gs.court_sys as _StubCourt).headlines().has("A PRINCE HAS ARRIVED"))
	gs.units.erase(u)


func _test_scam_send_poor() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_set_gold(gs, 100.0)
	var u: Dictionary = _arrived(d, gs)
	var before: float = gs.resources.get_amount("humans", "gold")
	var reply: String = d.gnomba_scam_reply(u, "send")
	_check("send-poor: insult reply", reply.to_lower().contains("insult"))
	_check("send-poor: scam still pending", String(u.get("gnomba_scam", "")) == "pending")
	_check("send-poor: no gold moved",
		gs.resources.get_amount("humans", "gold") == before)
	_check("send-poor: not leaving", not bool(u.get("leaving", false)))
	gs.units.erase(u)


func _test_scam_send_resolves() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_set_gold(gs, 1000.0)
	var u: Dictionary = _arrived(d, gs)
	var reply: String = d.gnomba_scam_reply(u, "send")
	var after: float = gs.resources.get_amount("humans", "gold")
	# Either doubled (1000 - 500 + 1000 = 1500) or rugged (1000 - 500).
	_check("send: gold resolved to payout or rug", after == 1500.0 or after == 500.0)
	_check("send: scam resolved", String(u.get("gnomba_scam", "")) == "resolved")
	_check("send: prince leaves", bool(u.get("leaving", false)))
	_check("send: reply is payout or rug",
		reply.contains("LEGITIMATE") or reply.contains("THANK YOU FOR YOUR GOLD"))
	var heads: Array = (gs.court_sys as _StubCourt).headlines()
	_check("send: Gazette filed payout or rug",
		heads.has("PRINCE GNOMBA PAYS OUT") or heads.has("RUGGED!"))
	gs.units.erase(u)


func _test_scam_block() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_set_gold(gs, 1000.0)
	var u: Dictionary = _arrived(d, gs)
	var before: float = gs.resources.get_amount("humans", "gold")
	var reply: String = d.gnomba_scam_reply(u, "block")
	_check("block: scam marked blocked", String(u.get("gnomba_scam", "")) == "blocked")
	_check("block: prince flees", bool(u.get("leaving", false)))
	_check("block: no gold moved", gs.resources.get_amount("humans", "gold") == before)
	_check("block: outrage reply", reply.contains("OUTRAGE"))
	_check("block: Gazette filed",
		(gs.court_sys as _StubCourt).headlines().has("WOULD-BE PRINCE BLOCKED"))
	_check("block: con no longer pending",
		not d.gnomba_scam_pending(int(u.get("id", 0))))
	gs.units.erase(u)


func _test_scam_non_verdict() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = _arrived(d, gs)
	_check("chat: 'nice crown' falls through to conversation",
		d.gnomba_scam_reply(u, "nice crown") == "")
	_check("chat: scam still pending", String(u.get("gnomba_scam", "")) == "pending")
	gs.units.erase(u)


func _test_scam_no_double_dip() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_set_gold(gs, 10000.0)
	var u: Dictionary = _arrived(d, gs)
	d.gnomba_scam_reply(u, "block")
	var after_block: float = gs.resources.get_amount("humans", "gold")
	_check("nodip: resolved scam ignores send", d.gnomba_scam_reply(u, "send") == "")
	_check("nodip: no gold moved after resolve",
		gs.resources.get_amount("humans", "gold") == after_block)
	gs.units.erase(u)


func _test_aura_skim() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_set_gold(gs, 1000.0)
	var u: Dictionary = d.spawn("prince_gnomba", Vector2(2000, 2000))
	u["gnomba_center"] = Vector2(2000, 2000)
	u["gnomba_faction"] = "humans"
	u["gnomba_scam"] = "pending"
	u["gnomba_skimmed"] = 0.0
	u["gnomba_visit_left"] = 240.0
	var near1 := _citizen(gs, Vector2(2050, 2000), "worker")
	var near2 := _citizen(gs, Vector2(2000, 2050), "worker")
	var guard := _citizen(gs, Vector2(2050, 2050), "soldier")
	var far := _citizen(gs, Vector2(3500, 3500), "worker")
	u["gnomba_aura_cd"] = 0.0
	d._gnomba_aura(u, Vector2(2000, 2000), 3.0)
	# 2 marks x 4g = 8g skimmed; soldier + far citizen untouched by skim.
	_check("aura: skimmed 8g", float(u.get("gnomba_skimmed", -1.0)) == 8.0)
	_check("aura: treasury down 8g", gs.resources.get_amount("humans", "gold") == 992.0)
	gs.units.erase(u)
	gs.units.erase(near1)
	gs.units.erase(near2)
	gs.units.erase(guard)
	gs.units.erase(far)


func _test_aura_cap() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_set_gold(gs, 10000.0)
	var u: Dictionary = d.spawn("prince_gnomba", Vector2(2000, 2000))
	u["gnomba_center"] = Vector2(2000, 2000)
	u["gnomba_faction"] = "humans"
	u["gnomba_scam"] = "pending"
	u["gnomba_skimmed"] = 148.0  # 2g from the cap
	u["gnomba_visit_left"] = 240.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	u["gnomba_aura_cd"] = 0.0
	d._gnomba_aura(u, Vector2(2000, 2000), 3.0)
	_check("cap: skimmed pinned at 150", float(u.get("gnomba_skimmed", 0.0)) == 150.0)
	_check("cap: Gazette filed fees story",
		(gs.court_sys as _StubCourt).headlines().has("PRINCE COLLECTS HIS FEES"))
	# At cap, the aura takes nothing more.
	var before: float = gs.resources.get_amount("humans", "gold")
	u["gnomba_aura_cd"] = 0.0
	d._gnomba_aura(u, Vector2(2000, 2000), 3.0)
	_check("cap: no further skim", gs.resources.get_amount("humans", "gold") == before)
	gs.units.erase(u)
	gs.units.erase(near)


func _test_soldier_deport() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("prince_gnomba", Vector2(2000, 2000))
	u["gnomba_center"] = Vector2(2000, 2000)
	u["gnomba_visit_left"] = 240.0
	u["gnomba_scam"] = "pending"
	var guard := _citizen(gs, Vector2(2050, 2000), "soldier")
	d._tick_gnomba(u, 80.0, 1.0)
	_check("deport: prince leaving", bool(u.get("leaving", false)))
	_check("deport: Gazette filed",
		(gs.court_sys as _StubCourt).headlines().has("PRINCE GNOMBA DEPORTED"))
	gs.units.erase(u)
	gs.units.erase(guard)


func _test_visa_expiry() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("prince_gnomba", Vector2(2000, 2000))
	u["gnomba_center"] = Vector2(2000, 2000)
	u["gnomba_visit_left"] = 0.5
	u["gnomba_scam"] = "pending"
	d._tick_gnomba(u, 80.0, 1.0)
	_check("visa: prince leaving", bool(u.get("leaving", false)))
	_check("visa: Gazette filed",
		(gs.court_sys as _StubCourt).headlines().has("PRINCE GNOMBA'S VISA EXPIRES"))
	gs.units.erase(u)


func _test_slain_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("prince_gnomba", Vector2(2000, 2000))
	u["alive"] = false
	d._check_dead_disaster(u)
	_check("slain: Gazette filed",
		(gs.court_sys as _StubCourt).headlines().has("PRINCE GNOMBA SLAIN"))
	gs.units.erase(u)


func _test_phone_reply_hook() -> void:
	# The real SimPhone._npc_reply routes scam verdicts through the
	# disaster sim before the conversation engine.
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	gs.phone_sys = SimPhone.new(gs)
	_set_gold(gs, 0.0)
	var u: Dictionary = d.spawn("prince_gnomba", Vector2(2000, 2000))
	u["gnomba_scam"] = "pending"
	var reply: String = gs.phone_sys._npc_reply(u, "send")
	_check("hook: _npc_reply routes to the con", reply.to_lower().contains("insult"))
	_check("hook: non-verdict falls through to chat",
		gs.phone_sys._npc_reply(u, "nice crown") != "")
	gs.units.erase(u)


func _test_art() -> void:
	var tex = Art.animal_texture("prince_gnomba")
	_check("art: texture resolves", tex != null)
	if tex != null:
		var img: Image = tex.get_image()
		var w: int = img.get_width()
		var h: int = img.get_height()
		var corners_ok := true
		for c in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
			if img.get_pixel(c.x, c.y).a > 0.05:
				corners_ok = false
		_check("art: corners transparent (white-keyed)", corners_ok)


func _test_fx_rig() -> void:
	var fx := GnombaFX.new()
	root.add_child(fx)
	await process_frame
	fx._process(1.0)
	_check("fx: coin cycle in 0..1",
		fx._coin_cycle(0) >= 0.0 and fx._coin_cycle(0) < 1.0)
	_check("fx: glint alpha in 0..1",
		fx._glint_alpha() >= 0.0 and fx._glint_alpha() <= 1.0)
	_check("fx: stage_h default sane", fx.stage_h == 64.0)
	fx.queue_free()


func _test_unit_node_wiring() -> void:
	_check("wiring: job registered",
		"prince_gnomba" in UnitNode._MONSTER_JOBS)
	var n := UnitNode.new()
	n.job = "prince_gnomba"
	_check("wiring: art texture resolves", n._monster_texture() != null)
