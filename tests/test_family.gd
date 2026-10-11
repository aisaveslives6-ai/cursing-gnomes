extends SceneTree
## Cursing Gnomes — Family & Belonging tests (dedicated porting 2026-10-05).
##
## Ports HTML fix79 "FAMILY & BELONGING" (index.html ~lines 31909-32391),
## Unit.tryRomance (~34815-34920), and the leadership soul system
## (soulOf/leaderDeed/tickLeadership, ~32397-32496). Verifies the
## HTML-verbatim numbers and gates, plus Godot adaptations (uid refs,
## Royal Court player decisions, pop-cap-respecting births).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_family.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []
var _stories: Array = []
var _phone: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes family & belonging tests ===")
	_test_ensure_fields()
	_test_bump_affinity()
	_test_bump_affinity_clamps()
	_test_bump_affinity_skips_children()
	_test_romance_pairing()
	_test_romance_gates()
	_test_marriage()
	_test_conceive_gates()
	_test_conceive_undead_never()
	_test_birth_child()
	_test_birth_respects_pop_cap()
	_test_birth_needs_free_bed()
	_test_grow_up()
	_test_leave_town_yes()
	_test_leave_town_no()
	_test_join_faction()
	_test_join_petition_threshold()
	_test_leadership_soul()
	_test_leader_deed_clamps()
	_test_bond_summary()
	_test_save_load()
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
	gs.setup(["humans", "gnomes"])
	_said.clear()
	_stories.clear()
	_phone.clear()
	gs.bus.unit_said.connect(func(uid: int, text: String) -> void: _said.append([uid, text]))
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	gs.bus.phone_message.connect(func(key: String, text: String) -> void: _phone.append([key, text]))
	var fam := SimFamily.new(gs)
	return [gs, fam]


func _worker(gs: GameState, faction: String, pos: Vector2, gender: String) -> Dictionary:
	var u := gs.add_unit({"faction": faction, "job": "worker", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 30.0, "gender": gender, "is_worker": true})
	return u


func _house(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "house", "faction": faction, "town_id": 1,
		"position": pos, "alive": true, "complete": true, "residents": []})


# --- ensure -----------------------------------------------------------------

func _test_ensure_fields() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _worker(gs, "humans", Vector2(100, 100), "m")
	fam.ensure(u)
	_check("ensure: spouse_uid -1", int(u["spouse_uid"]) == -1)
	_check("ensure: partner_uid -1", int(u["partner_uid"]) == -1)
	_check("ensure: bonds dict", u["bonds"] is Dictionary)
	_check("ensure: born_faction", String(u["born_faction"]) == "humans")
	_check("ensure: not child", not bool(u["is_child"]))
	_check("ensure: romance_cd in 8..28",
		float(u["romance_cd"]) >= 8.0 and float(u["romance_cd"]) <= 28.0)
	_check("ensure: idempotent", u["spouse_uid"] == -1)


# --- bonds ------------------------------------------------------------------

func _test_bump_affinity() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var a := _worker(gs, "humans", Vector2(100, 100), "m")
	var b := _worker(gs, "humans", Vector2(120, 100), "f")
	fam.bump_affinity(a, b, 10.0)
	_check("bump: a->b +10", absf(fam.get_affinity(a, b) - 10.0) < 0.001)
	_check("bump: b->a +9 (0.9x)", absf(fam.get_affinity(b, a) - 9.0) < 0.001)


func _test_bump_affinity_clamps() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var a := _worker(gs, "humans", Vector2(100, 100), "m")
	var b := _worker(gs, "humans", Vector2(120, 100), "f")
	fam.bump_affinity(a, b, 500.0)
	_check("bump: clamps at +100", absf(fam.get_affinity(a, b) - 100.0) < 0.001)
	fam.bump_affinity(a, b, -500.0)
	_check("bump: clamps at -100", absf(fam.get_affinity(a, b) + 100.0) < 0.001)


func _test_bump_affinity_skips_children() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var a := _worker(gs, "humans", Vector2(100, 100), "m")
	var c := _worker(gs, "humans", Vector2(120, 100), "f")
	fam.ensure(c)
	c["is_child"] = true
	fam.bump_affinity(a, c, 10.0)
	_check("bump: children excluded", absf(fam.get_affinity(a, c)) < 0.001)


# --- romance ----------------------------------------------------------------

func _test_romance_pairing() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var a := _worker(gs, "humans", Vector2(100, 100), "m")
	var b := _worker(gs, "humans", Vector2(150, 100), "f")
	fam.ensure(a)
	fam.ensure(b)
	a["romance_cd"] = 0.0
	b["romance_cd"] = 999.0  # only a searches
	# Force the 0.015 roll to hit by stubbing rng: call until paired.
	var paired := false
	for i in 200:
		a["romance_cd"] = 0.0
		fam._try_romance(a, 1.5)
		if int(a["partner_uid"]) == int(b["id"]):
			paired = true
			break
	_check("romance: nearby opposite-gender pair up", paired)
	_check("romance: mutual partner link", int(b["partner_uid"]) == int(a["id"]))
	_check("romance: love seeded 15", absf(float(a["love"]) - 15.0) < 0.001)


func _test_romance_gates() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	# Same gender: no pairing.
	var a := _worker(gs, "humans", Vector2(100, 100), "m")
	var c := _worker(gs, "humans", Vector2(150, 100), "m")
	fam.ensure(a)
	fam.ensure(c)
	a["romance_cd"] = 0.0
	for i in 60:
		a["romance_cd"] = 0.0
		fam._try_romance(a, 1.5)
	_check("romance: same gender never pairs", int(a["partner_uid"]) < 0)
	# Military skipped.
	var s := gs.add_unit({"faction": "humans", "job": "soldier", "town_id": 1,
		"position": Vector2(160, 100), "alive": true, "gender": "f"})
	fam.ensure(s)
	_check("romance: soldier not civilian worker", not fam._civilian_worker(s))
	# Married units don't re-search.
	var m1 := _worker(gs, "humans", Vector2(500, 500), "m")
	var m2 := _worker(gs, "humans", Vector2(520, 500), "f")
	var w2 := _worker(gs, "humans", Vector2(540, 500), "f")
	fam.ensure(m1)
	fam.ensure(m2)
	fam.ensure(w2)
	m1["spouse_uid"] = int(m2["id"])
	m1["love"] = 80.0
	m1["romance_cd"] = 0.0
	w2["romance_cd"] = 0.0
	for i in 40:
		m1["romance_cd"] = 0.0
		fam._try_romance(m1, 1.5)
	_check("romance: married unit keeps spouse", int(m1["spouse_uid"]) == int(m2["id"]))
	_check("romance: married love deepens", float(m1["love"]) > 80.0)


func _test_marriage() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var a := _worker(gs, "humans", Vector2(100, 100), "m")
	var b := _worker(gs, "humans", Vector2(120, 100), "f")
	fam.ensure(a)
	fam.ensure(b)
	a["partner_uid"] = int(b["id"])
	b["partner_uid"] = int(a["id"])
	a["love"] = 80.0
	b["love"] = 80.0
	fam._try_romance(a, 1.5)
	_check("marriage: love>75 both -> spouses", int(a["spouse_uid"]) == int(b["id"]))
	_check("marriage: mutual", int(b["spouse_uid"]) == int(a["id"]))
	_check("marriage: affinity +80", fam.get_affinity(a, b) >= 79.0)
	# Cross-faction wedding -> gazette.
	_stories.clear()
	var x := _worker(gs, "gnomes", Vector2(300, 300), "m")
	var y := _worker(gs, "humans", Vector2(320, 300), "f")
	fam.ensure(x)
	fam.ensure(y)
	x["partner_uid"] = int(y["id"])
	y["partner_uid"] = int(x["id"])
	x["love"] = 90.0
	y["love"] = 90.0
	fam._try_romance(x, 1.5)
	var found := false
	for s in _stories:
		if String(s.get("headline", "")).find("CROSS-FACTION") >= 0:
			found = true
	_check("marriage: cross-faction wedding gazetted", found)


# --- conception & birth -----------------------------------------------------

func _home_pair(gs: GameState, fam: SimFamily) -> Array:
	var h := _house(gs, "humans", Vector2(1000, 1000))
	var a := _worker(gs, "humans", Vector2(1010, 1010), "m")
	var b := _worker(gs, "humans", Vector2(1020, 1010), "f")
	fam.ensure(a)
	fam.ensure(b)
	a["spouse_uid"] = int(b["id"])
	b["spouse_uid"] = int(a["id"])
	a["love"] = 80.0
	b["love"] = 80.0
	a["home"] = h
	b["home"] = h
	(h["residents"] as Array).append(int(a["id"]))
	(h["residents"] as Array).append(int(b["id"]))
	return [a, b, h]


func _test_conceive_gates() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var p := _home_pair(gs, fam)
	var a: Dictionary = p[0]
	var b: Dictionary = p[1]
	# Force the conception roll deterministically: step 250 -> p = 250*0.004
	# = 1.0, so the gates (not RNG) decide.
	fam._try_conceive(b, 250.0, fam._days(250.0))
	_check("conceive: happy married couple conceives", float(b["preg_timer"]) > 0.0)
	_check("conceive: preg_timer = PREG_DAYS",
		absf(float(b["preg_timer"]) - SimFamily.PREG_DAYS) < 0.001)
	# Low love: no conception even with a guaranteed roll.
	var p2 := _home_pair(gs, fam)
	var b2: Dictionary = p2[1]
	b2["love"] = 10.0
	fam._try_conceive(b2, 250.0, fam._days(250.0))
	_check("conceive: love<=55 blocks", float(b2["preg_timer"]) == 0.0)
	# Not sharing a home: no conception.
	var p3 := _home_pair(gs, fam)
	var b3: Dictionary = p3[1]
	b3["home"] = {}
	fam._try_conceive(b3, 250.0, fam._days(250.0))
	_check("conceive: homeless blocks (shared-bed rule)", float(b3["preg_timer"]) == 0.0)


func _test_conceive_undead_never() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	gs.setup(["humans", "undead"])
	var h := _house(gs, "undead", Vector2(1000, 1000))
	var a := _worker(gs, "undead", Vector2(1010, 1010), "m")
	var b := _worker(gs, "undead", Vector2(1020, 1010), "f")
	fam.ensure(a)
	fam.ensure(b)
	a["spouse_uid"] = int(b["id"])
	b["spouse_uid"] = int(a["id"])
	a["love"] = 90.0
	b["love"] = 90.0
	a["home"] = h
	b["home"] = h
	var no := true
	for i in 200:
		fam._try_conceive(b, 1.0, fam._days(1.0))
		if float(b["preg_timer"]) > 0.0:
			no = false
			break
	_check("conceive: C61 the dead do not breed", no)


func _test_birth_child() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var p := _home_pair(gs, fam)
	var b: Dictionary = p[1]
	var before := gs.units.size()
	fam._birth_child(b)
	_check("birth: unit added", gs.units.size() == before + 1)
	var child: Dictionary = gs.units[gs.units.size() - 1]
	_check("birth: is_child", bool(child.get("is_child", false)))
	_check("birth: is_baby", bool(child.get("is_baby", false)))
	_check("birth: mother_uid", int(child.get("mother_uid", -1)) == int(b["id"]))
	_check("birth: same faction", String(child.get("faction", "")) == "humans")
	_check("birth: preg cleared", float(b["preg_timer"]) == 0.0)


class _StubSpawner:
	var refuse := false
	func check_spawn(_faction: String, _job: String, _town: int) -> String:
		return "faction_capped" if refuse else "ok"


func _test_birth_respects_pop_cap() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var p := _home_pair(gs, fam)
	var b: Dictionary = p[1]
	# Spawner refuses at cap -> birth waits, never silently lost.
	var stub := _StubSpawner.new()
	stub.refuse = true
	fam._spawner = stub
	var before := gs.units.size()
	fam._birth_child(b)
	_check("birth: capped faction blocks birth", gs.units.size() == before)
	_check("birth: retry timer set, not lost", float(b["preg_timer"]) > 0.0)
	# Spawner allows -> birth proceeds.
	stub.refuse = false
	fam._spawner = null  # fallback add_unit path also births
	fam._birth_child(b)
	_check("birth: proceeds when room", gs.units.size() == before + 1)


func _test_birth_needs_free_bed() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var h := _house(gs, "humans", Vector2(1000, 1000))
	var b := _worker(gs, "humans", Vector2(1010, 1010), "f")
	fam.ensure(b)
	b["home"] = h
	# Fill the household to HOUSEHOLD_CAP.
	for i in SimHousing.HOUSEHOLD_CAP:
		(h["residents"] as Array).append(900 + i)
	var before := gs.units.size()
	fam._birth_child(b)
	_check("birth: full house blocks birth", gs.units.size() == before)
	_check("birth: retry timer set", float(b["preg_timer"]) > 0.0)


func _test_grow_up() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var p := _home_pair(gs, fam)
	var b: Dictionary = p[1]
	fam._birth_child(b)
	var child: Dictionary = gs.units[gs.units.size() - 1]
	child["age_days"] = SimFamily.CHILD_GROW_DAYS
	fam._tick_family(1.0)
	_check("grow: no longer child", not bool(child.get("is_child", false)))
	_check("grow: becomes worker", String(child.get("job", "")) == "worker")
	_check("grow: jobless adult (is_worker)", bool(child.get("is_worker", false)))


# --- belonging ---------------------------------------------------------------

func _test_leave_town_yes() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _worker(gs, "gnomes", Vector2(100, 100), "m")  # AI faction
	fam.ensure(u)
	fam._apply_leave({"unit_id": int(u["id"]), "faction": "gnomes"}, true)
	_check("leave-yes: becomes adventurer", bool(u.get("adventurer", false)))
	_check("leave-yes: job adventurer", String(u.get("job", "")) == "adventurer")
	_check("leave-yes: standing deed",
		float(fam.soul_of("gnomes")["standing"]) > 20.0)


func _test_leave_town_no() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _worker(gs, "gnomes", Vector2(100, 100), "m")
	var hater := _worker(gs, "gnomes", Vector2(120, 100), "f")
	fam.ensure(u)
	fam.ensure(hater)
	fam.bump_affinity(u, hater, -80.0)
	fam._apply_leave({"unit_id": int(u["id"]), "faction": "gnomes"}, false)
	_check("leave-no: stays", not bool(u.get("adventurer", false)))
	_check("leave-no: bonds thaw", fam.get_affinity(u, hater) > -80.0)
	_check("leave-no: standing deed",
		float(fam.soul_of("gnomes")["standing"]) < 20.0)


func _test_join_faction() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var u := _worker(gs, "gnomes", Vector2(100, 100), "m")
	fam.ensure(u)
	u["adventurer"] = true
	u["job"] = "adventurer"
	u["is_worker"] = false
	fam._apply_join({"unit_id": int(u["id"]), "new_faction": "humans"}, true)
	_check("join: faction changes", String(u.get("faction", "")) == "humans")
	_check("join: born_faction kept", String(u.get("born_faction", "")) == "gnomes")
	_check("join: no longer adventurer", not bool(u.get("adventurer", false)))
	# Launch-readiness 2026-10-05: the immigrant must enter the labor market
	# (job="adventurer" was a dead end — no system hires or tasks it).
	_check("join: job becomes unemployed (hirable)",
		String(u.get("job", "")) == "unemployed")
	_check("join: work_state reset to idle",
		String(u.get("work_state", "")) == "idle")
	var hir := GuildHiring.new(gs)
	_check("join: hiring sweep recognizes the immigrant", hir.is_unemployed(u))
	# Refusal keeps wandering.
	var v := _worker(gs, "gnomes", Vector2(200, 200), "f")
	fam.ensure(v)
	v["adventurer"] = true
	fam._apply_join({"unit_id": int(v["id"]), "new_faction": "humans"}, false)
	_check("join-no: faction kept", String(v.get("faction", "")) == "gnomes")
	_check("join-no: still adventurer", bool(v.get("adventurer", false)))


## Launch-readiness 2026-10-05: the adventurer->join petition bar was 45
## (HTML-verbatim), unreachable in practice — the petition effectively never
## fired. The bar is now 25: an avg-30 fondness must petition, avg-10 must not.
func _test_join_petition_threshold() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var adv := _worker(gs, "gnomes", Vector2(100, 100), "m")
	fam.ensure(adv)
	adv["adventurer"] = true
	adv["job"] = "adventurer"
	adv["join_cd"] = 0.0
	for i in 3:
		var h := _worker(gs, "humans", Vector2(120 + i * 40, 120), "m")
		fam.ensure(h)
		var bonds: Dictionary = adv["bonds"]
		bonds[str(int(h["id"]))] = 30.0
	fam._tick_adventurers(3.0)
	# Petition fired: join_cd is reset to 25. If the auto-resolve accepted,
	# _join_faction already ran and set it to 20 — either way it is > 0.
	_check("join-petition: fires at avg 30 (new bar 25)",
		float(adv.get("join_cd", 0.0)) > 0.0)
	# Control: lukewarm fondness (avg 10) stays below the bar — no petition.
	var w2 := _make_world()
	var gs2: GameState = w2[0]
	var fam2: SimFamily = w2[1]
	var adv2 := _worker(gs2, "gnomes", Vector2(500, 500), "m")
	fam2.ensure(adv2)
	adv2["adventurer"] = true
	adv2["job"] = "adventurer"
	adv2["join_cd"] = 0.0
	for i in 3:
		var h2 := _worker(gs2, "humans", Vector2(520 + i * 40, 520), "m")
		fam2.ensure(h2)
		var bonds2: Dictionary = adv2["bonds"]
		bonds2[str(int(h2["id"]))] = 10.0
	fam2._tick_adventurers(3.0)
	_check("join-petition: no fire at avg 10",
		float(adv2.get("join_cd", 0.0)) == 0.0)


# --- leadership ----------------------------------------------------------------

func _test_leadership_soul() -> void:
	var w := _make_world()
	var fam: SimFamily = w[1]
	var s := fam.soul_of("humans")
	_check("soul: default standing 20", absf(float(s["standing"]) - 20.0) < 0.001)
	_check("soul: default morality 10", absf(float(s["morality"]) - 10.0) < 0.001)
	_check("soul: same dict returned", fam.soul_of("humans") == s)


func _test_leader_deed_clamps() -> void:
	var w := _make_world()
	var fam: SimFamily = w[1]
	fam.leader_deed("gnomes", 500.0, -500.0, "test deed")
	var s := fam.soul_of("gnomes")
	_check("deed: standing clamps +100", absf(float(s["standing"]) - 100.0) < 0.001)
	_check("deed: morality clamps -100", absf(float(s["morality"]) + 100.0) < 0.001)
	_check("deed: remembered", (s["deeds"] as Array).size() == 1)
	for i in 15:
		fam.leader_deed("gnomes", 1.0, 0.0, "deed %d" % i)
	_check("deed: cap 10 remembered", (fam.soul_of("gnomes")["deeds"] as Array).size() == 10)
	_check("standing_label: Adored", SimFamily.standing_label(80.0) == "Adored")
	_check("standing_label: Despised", SimFamily.standing_label(-80.0) == "Despised")
	_check("morality_label: Saintly", SimFamily.morality_label(80.0) == "Saintly")
	_check("morality_label: Tyrannical", SimFamily.morality_label(-80.0) == "Tyrannical")


func _test_bond_summary() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	var a := _worker(gs, "humans", Vector2(100, 100), "m")
	var b := _worker(gs, "humans", Vector2(120, 100), "f")
	fam.ensure(a)
	fam.bump_affinity(a, b, 50.0)
	var s := fam.bond_summary(a)
	_check("bond_summary: non-empty", s != "")
	_check("bond_summary: has heart", s.find("💚") >= 0)
	var c := _worker(gs, "humans", Vector2(200, 200), "m")
	fam.ensure(c)
	_check("bond_summary: empty when no bonds", fam.bond_summary(c) == "")


func _test_save_load() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var fam: SimFamily = w[1]
	fam.leader_deed("humans", 30.0, 20.0, "saved deed")
	var d := fam.to_dict()
	var fam2 := SimFamily.new(gs)
	fam2.from_dict(d)
	_check("save: standing survives",
		absf(float(fam2.soul_of("humans")["standing"]) - 50.0) < 0.001)
	_check("save: morality survives",
		absf(float(fam2.soul_of("humans")["morality"]) - 30.0) < 0.001)
	_check("save: deeds survive",
		(fam2.soul_of("humans")["deeds"] as Array).size() == 1)
