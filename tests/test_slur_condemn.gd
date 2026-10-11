extends SceneTree
## Cursing Gnomes — anti-racist hearsay condemnation tests (Jeremy 2026-10-04).
##
## When the REAL n-word is used in diplomacy, the hearsay system must condemn
## racism explicitly: every faction in their own voice (GAH FUCK RACISTS),
## even factions at war with each other. Rumors + Squabble + bystander
## rumor-join with real memories.
## (Speech-bubble visuals were removed 2026-10-05, and 2026-10-06 the
## bystander unit_said shouts were replaced with silent rumor joins —
## witnesses join the condemnation rumors as knowers with heard_rumor
## memories instead.)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_slur_condemn.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes slur condemnation tests ===")
	_test_condemn_lines_exist()
	_test_slur_incident_seeds_all_faction_rumors()
	_test_slur_incident_squabble_posts()
	_test_slur_incident_placeholders_filled()
	_test_slur_incident_condemnation_lines()
	_test_npc_offender_named_personally()
	_test_quote_never_repeated()
	_test_name_shame_lines_exist()
	_test_euphemisms_present()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	# Towns must exist for spawn_unit to work (check_spawn validates town_id).
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)
	return {"gs": gs, "mind": mind, "phone": phone}


func _spawn(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, "worker", 1, pos)
	mind.ensure(u)
	return u


func _test_condemn_lines_exist() -> void:
	# Every faction must have 10+ condemnation lines (Jeremy's spec).
	_check("ogres condemn lines >= 10", SimHearsay.SLUR_CONDEMN_OGRES.size() >= 10)
	_check("elves condemn lines >= 10", SimHearsay.SLUR_CONDEMN_ELVES.size() >= 10)
	_check("gnomes condemn lines >= 10", SimHearsay.SLUR_CONDEMN_GNOMES.size() >= 10)
	_check("humans condemn lines >= 10", SimHearsay.SLUR_CONDEMN_HUMANS.size() >= 10)
	_check("undead condemn lines >= 10", SimHearsay.SLUR_CONDEMN_UNDEAD.size() >= 10)
	_check("condemn posts >= 15", SimHearsay.SLUR_CONDEMN_POSTS.size() >= 15)
	_check("condemn replies >= 12", SimHearsay.SLUR_CONDEMN_REPLIES.size() >= 12)
	# Every pool must actually condemn — spot-check the message is present.
	for fname: String in ["ogres", "elves", "gnomes", "humans", "undead"]:
		var pool: Array = []
		match fname:
			"ogres":
				pool = SimHearsay.SLUR_CONDEMN_OGRES
			"elves":
				pool = SimHearsay.SLUR_CONDEMN_ELVES
			"gnomes":
				pool = SimHearsay.SLUR_CONDEMN_GNOMES
			"humans":
				pool = SimHearsay.SLUR_CONDEMN_HUMANS
			"undead":
				pool = SimHearsay.SLUR_CONDEMN_UNDEAD
		var joined: String = " ".join(pool).to_lower()
		_check(fname + " pool condemns racism",
			joined.contains("racist") or joined.contains("bigot"))


func _test_slur_incident_seeds_all_faction_rumors() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	# One NPC per faction so _random_citizen has authors.
	_spawn(w, "ogres", Vector2(10, 10))
	_spawn(w, "elves", Vector2(20, 20))
	_spawn(w, "gnomes", Vector2(30, 30))
	_spawn(w, "humans", Vector2(40, 40))
	_spawn(w, "undead", Vector2(50, 50))
	hear._on_slur_incident("ogres", "elves", "test quote", "")
	var slur_rumors: Array = []
	for r: Dictionary in hear.state["rumors"]:
		if String(r.get("kind", "")) == "slur":
			slur_rumors.append(r)
	# All five factions condemn — even ones at war with each other —
	# plus the name-and-shame rumor naming the racist directly. The two
	# shame seed calls merge into ONE rumor via the kind+subject dedupe
	# in seed_rumor (Jeremy 2026-10-06), so the live count is 6.
	_check("6 slur rumors seeded (5 faction + 1 merged name-shame)", slur_rumors.size() == 6)
	var subjects := {}
	for r: Dictionary in slur_rumors:
		subjects[String(r.get("subject", ""))] = true
		_check("slur rumor heat high", float(r.get("heat", 0.0)) >= 0.9)
	for f: String in ["ogres", "elves", "gnomes", "humans", "undead"]:
		_check("rumor from " + f, subjects.has(f))
	_check("name-shame rumors seeded", subjects.has("shame"))


func _test_slur_incident_squabble_posts() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	_spawn(w, "ogres", Vector2(10, 10))
	_spawn(w, "elves", Vector2(20, 20))
	_spawn(w, "gnomes", Vector2(30, 30))
	_spawn(w, "humans", Vector2(40, 40))
	_spawn(w, "undead", Vector2(50, 50))
	var before: int = (phone.state["posts"] as Array).size()
	hear._on_slur_incident("humans", "ogres", "test quote", "")
	var after: int = (phone.state["posts"] as Array).size()
	_check("condemnation posts created", after > before)
	# The platform condemns — posts mention racism/bigotry.
	var found := false
	for i: int in range(before, after):
		var p: Dictionary = (phone.state["posts"] as Array)[i]
		var t: String = String(p.get("text", "")).to_lower()
		if t.contains("racist") or t.contains("bigot"):
			found = true
			break
	_check("posts condemn racism explicitly", found)
	# Authors span factions — the whole realm unites.
	var factions := {}
	for i: int in range(before, after):
		var p: Dictionary = (phone.state["posts"] as Array)[i]
		factions[String(p.get("faction", ""))] = true
	_check("posts from multiple factions", factions.size() >= 3)


func _test_slur_incident_placeholders_filled() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	_spawn(w, "ogres", Vector2(10, 10))
	_spawn(w, "elves", Vector2(20, 20))
	hear._on_slur_incident("gnomes", "undead", "test quote", "")
	# No raw {ruler} placeholders may leak into rumors or posts.
	for r: Dictionary in hear.state["rumors"]:
		if String(r.get("kind", "")) == "slur":
			_check("rumor has no {ruler} placeholder",
				not String(r.get("text", "")).contains("{ruler}"))
	for p: Dictionary in phone.state["posts"]:
		_check("post has no {ruler} placeholder",
			not String(p.get("text", "")).contains("{ruler}"))
		for c: Dictionary in p.get("comments", []):
			_check("reply has no {ruler} placeholder",
				not String(c.get("text", "")).contains("{ruler}"))


## Jeremy 2026-10-05: speech bubbles removed. Jeremy 2026-10-06: bystander
## condemnations used to ride bus.unit_said, a no-op since the bubble ban —
## witnesses now join the condemnation rumors as knowers with real
## heard_rumor memories instead (hearsay.gd _on_slur_incident step 3).
func _test_slur_incident_condemnation_lines() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	# Many NPCs — 25% witness join chance each per incident; accumulate
	# across attempts so the sample is big enough to be a reliable signal.
	var spawned: Array = []
	for i: int in 12:
		spawned.append(_spawn(w, "humans", Vector2(10 + i * 5, 10)))
	for i: int in 5:
		hear._on_slur_incident("ogres", "humans", "test quote", "")
	var mem := SimMemories.new(gs)
	var joined := 0
	for u: Dictionary in spawned:
		for m: Dictionary in mem.ensure(u):
			if String(m.get("type", "")) == "heard_rumor" \
					and String(m.get("subject_name", "")) == "slur":
				joined += 1
				break
	_check("bystanders join slur condemnation rumors", joined >= 1)
	# Condemnation may be explicit ("racist"/"bigot") or euphemistic
	# ("THAT word", "won't repeat it") — both only exist in slur context.
	# The lines now reach bystanders as rumor texts, not spoken lines.
	var condemned := false
	for r: Dictionary in hear.state["rumors"]:
		if String(r.get("kind", "")) != "slur":
			continue
		var t: String = String(r.get("text", "")).to_lower()
		if t.contains("racist") or t.contains("bigot") \
			or t.contains("that word") or t.contains("won't repeat"):
			condemned = true
			break
	_check("condemnation rumor calls out racism", condemned)


func _test_npc_offender_named_personally() -> void:
	# Jeremy 2026-10-04: if a NAMED NPC uses the slur, the realm spreads
	# the word that THEY are racist — personally, not just their faction.
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	_spawn(w, "ogres", Vector2(10, 10))
	_spawn(w, "elves", Vector2(20, 20))
	_spawn(w, "gnomes", Vector2(30, 30))
	hear._on_slur_incident("ogres", "elves", "test quote", "Grak")
	var named := false
	for r: Dictionary in hear.state["rumors"]:
		if String(r.get("kind", "")) == "slur" \
				and String(r.get("text", "")).contains("Grak"):
			named = true
			break
	_check("NPC offender named personally in rumors", named)
	# The label helper itself.
	_check("offender label prefers NPC name",
		hear._offender_name("ogres", "Grak") == "Grak")
	_check("offender label falls back to title",
		hear._offender_name("undead", "").contains("ruler"))


func _test_quote_never_repeated() -> void:
	# Jeremy 2026-10-04: reporters euphemize — they NEVER quote the slur,
	# so they don't trigger the system on themselves. Feed a distinctive
	# token as the "quote" and assert it appears nowhere in hearsay output.
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	_spawn(w, "ogres", Vector2(10, 10))
	_spawn(w, "elves", Vector2(20, 20))
	_spawn(w, "gnomes", Vector2(30, 30))
	_spawn(w, "humans", Vector2(40, 40))
	_spawn(w, "undead", Vector2(50, 50))
	var token := "QUOTE_TOKEN_XYZ123"
	hear._on_slur_incident("ogres", "elves", token, "")
	var leaked := false
	for r: Dictionary in hear.state["rumors"]:
		if String(r.get("text", "")).contains(token):
			leaked = true
	for p: Dictionary in phone.state["posts"]:
		if String(p.get("text", "")).contains(token):
			leaked = true
		for c: Dictionary in p.get("comments", []):
			if String(c.get("text", "")).contains(token):
				leaked = true
	_check("exact quote never repeated in hearsay", not leaked)


func _test_name_shame_lines_exist() -> void:
	_check("name-shame lines >= 10",
		SimHearsay.SLUR_NAME_SHAME_LINES.size() >= 10)
	var joined: String = " ".join(SimHearsay.SLUR_NAME_SHAME_LINES).to_lower()
	_check("name-shame names the racist", joined.contains("is racist"))
	# Euphemisms present — reporters refuse to quote the word.
	_check("name-shame euphemizes the slur",
		joined.contains("won't repeat") or joined.contains("that word"))


func _test_euphemisms_present() -> void:
	# Every faction pool must contain explicit "won't repeat it" /
	# "THAT word" style euphemism lines (Jeremy 2026-10-04).
	var pools := {
		"ogres": SimHearsay.SLUR_CONDEMN_OGRES,
		"elves": SimHearsay.SLUR_CONDEMN_ELVES,
		"gnomes": SimHearsay.SLUR_CONDEMN_GNOMES,
		"humans": SimHearsay.SLUR_CONDEMN_HUMANS,
		"undead": SimHearsay.SLUR_CONDEMN_UNDEAD,
	}
	for fname: String in pools.keys():
		var joined: String = " ".join(pools[fname]).to_lower()
		_check(fname + " pool has euphemism lines",
			joined.contains("won't repeat") or joined.contains("that word"))
