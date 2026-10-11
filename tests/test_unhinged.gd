extends SceneTree
## Cursing Gnomes — unhinged trait tests (Jeremy 2026-10-06).
##
## Proves: unhinged trait distribution (minority, faction-weighted),
## determinism, legacy safety, persona assignment, per-voice pool sizes
## >= 100, without-replacement sampling (100 unique cuss-outs per NPC),
## furious+unhinged -> cuss-out + spam effect, furious+stable -> normal,
## calm+unhinged -> normal, apology de-escalation, slot substitution.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_unhinged.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


const PROFANITY := ["shit", "damn", "hell", "ass", "bastard", "piss",
	"crap", "fuck", "screw", "arse"]


func _initialize() -> void:
	print("=== Cursing Gnomes unhinged-trait tests ===")
	_test_distribution()
	_test_determinism()
	_test_legacy_safe()
	_test_persona()
	_test_pool_sizes()
	_test_voice_mapping()
	_test_sampling_no_repeat()
	_test_should_cuss_out()
	_test_cuss_out_reply()
	_test_profanity_and_slots()
	_test_tiers()
	_test_apology_bump()
	_test_phone_spam_queue()
	_test_blocked_silence()
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


func _rate(faction: String, n: int = 500) -> float:
	var c := 0
	for i in range(1, n + 1):
		var t: Dictionary = SimPersonality.traits_for(i, faction)
		if float(t.get("unhinged", 0.0)) >= 0.5:
			c += 1
	return float(c) / float(n)


func _test_distribution() -> void:
	# Minority overall, weighted: ogres/monster snap easiest, elves rarely.
	var ogres := _rate("ogres")
	var elves := _rate("elves")
	var humans := _rate("humans")
	_check("ogres unhinged minority", ogres < 0.45)
	_check("ogres unhinged meaningful", ogres > 0.20)
	_check("elves rarely unhinged", elves < 0.15)
	_check("ogres > elves", ogres > elves)
	_check("humans between", humans > elves and humans < ogres)
	var total := 0.0
	for f in ["humans", "ogres", "elves", "gnomes", "undead"]:
		total += _rate(f)
	_check("overall minority", total / 5.0 < 0.30)


func _test_determinism() -> void:
	for i in [1, 42, 777, 9001]:
		var a: Dictionary = SimPersonality.traits_for(i, "ogres")
		var b: Dictionary = SimPersonality.traits_for(i, "ogres")
		_check("deterministic unhinged %d" % i,
			a["unhinged"] == b["unhinged"])
		_check("deterministic persona %d" % i,
			String(a["persona"]) == String(b["persona"]))
	# Pre-existing rolls unchanged: brave is the first roll.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 * 7919 + 13
	var t: Dictionary = SimPersonality.traits_for(7, "humans")
	_check("legacy brave roll unchanged",
		abs(float(t["brave"]) - rng.randf()) < 0.000001)


func _test_legacy_safe() -> void:
	# Units saved before the trait existed have no "unhinged" key.
	var legacy := {"id": 5, "faction": "ogres",
		"mind": {"traits": {"brave": 0.9}, "name": "Old"}}
	_check("legacy not unhinged",
		not SimPersonality.is_unhinged(legacy))
	_check("legacy persona default",
		SimPersonality.persona_of(legacy) == "pragmatic")
	var forced := {"id": 5, "faction": "ogres",
		"mind": {"traits": {"unhinged": 1.0}, "name": "Mad"}}
	_check("forced unhinged", SimPersonality.is_unhinged(forced))


func _test_persona() -> void:
	for i in [3, 55, 918]:
		for f in ["humans", "ogres", "elves", "gnomes", "undead"]:
			var t: Dictionary = SimPersonality.traits_for(i, f)
			var p := String(t["persona"])
			_check("persona valid %d/%s" % [i, f],
				p in SimPersonality.PERSONAS)


func _test_pool_sizes() -> void:
	for v in SimCussouts.voices():
		_check("pool >= 100: %s" % v, SimCussouts.pool_size(v) >= 100)
		for t in SimCussouts.TIERS:
			_check("tier non-empty %s/%s" % [v, t],
				SimCussouts.tier_size(v, t) > 0)


func _test_voice_mapping() -> void:
	var elf := {"id": 1, "faction": "elves",
		"mind": {"traits": {"persona": "honorable"}, "name": "E"}}
	_check("elves elegant", SimUnhinged.voice_for(elf) == "elegant")
	for p in ["blunt", "grizzled"]:
		var u := {"id": 1, "faction": "ogres",
			"mind": {"traits": {"persona": p}, "name": "O"}}
		_check("persona %s -> blunt" % p,
			SimUnhinged.voice_for(u) == "blunt")
	for p in ["scheming", "oily"]:
		var u := {"id": 1, "faction": "gnomes",
			"mind": {"traits": {"persona": p}, "name": "G"}}
		_check("persona %s -> mischievous" % p,
			SimUnhinged.voice_for(u) == "mischievous")
	for p in ["proud", "haughty"]:
		var u := {"id": 1, "faction": "undead",
			"mind": {"traits": {"persona": p}, "name": "U"}}
		_check("persona %s -> cold" % p,
			SimUnhinged.voice_for(u) == "cold")
	for p in ["honorable", "earnest", "loyal"]:
		var u := {"id": 1, "faction": "humans",
			"mind": {"traits": {"persona": p}, "name": "H"}}
		_check("persona %s -> diplomatic" % p,
			SimUnhinged.voice_for(u) == "diplomatic")
	var n := {"id": 1, "faction": "humans",
		"mind": {"traits": {"persona": "jolly"}, "name": "J"}}
	_check("jolly -> neutral", SimUnhinged.voice_for(n) == "neutral")


func _unhinged_unit(uid: int, faction: String, persona: String) -> Dictionary:
	var traits: Dictionary = SimPersonality.traits_for(uid, faction)
	traits["unhinged"] = 1.0
	traits["persona"] = persona
	return {"id": uid, "faction": faction,
		"mind": {"traits": traits, "name": "Testy%d" % uid}}


func _stable_unit(uid: int, faction: String) -> Dictionary:
	var traits: Dictionary = SimPersonality.traits_for(uid, faction)
	traits["unhinged"] = 0.0
	return {"id": uid, "faction": faction,
		"mind": {"traits": traits, "name": "Calm%d" % uid}}


func _test_sampling_no_repeat() -> void:
	var uh := SimUnhinged.new()
	var seen := {}
	for i in range(100):
		var line: String = uh._draw(4242, "blunt", "heated", "ass",
			"Snag", "ogres")
		_check("line %d non-empty" % i, line != "")
		seen[line] = true
	_check("100 unique cuss-outs", seen.size() == 100)
	_check("used tracks 100", uh.used_total(4242, "blunt") == 100)
	_check("heated tier exhausted first",
		uh.used_count(4242, "blunt", "heated")
		== SimCussouts.tier_size("blunt", "heated"))
	# Exhaustion of the whole voice pool reshuffles instead of failing.
	var uh2 := SimUnhinged.new()
	var pool := SimCussouts.pool_size("blunt")
	for i in range(pool):
		uh2._draw(5555, "blunt", "heated", "ass", "Snag", "ogres")
	_check("full voice pool unique", uh2.used_total(5555, "blunt") == pool)
	var more: String = uh2._draw(5555, "blunt", "heated", "ass",
		"Snag", "ogres")
	_check("reshuffle after exhaust", more != "")
	_check("reshuffle resets used", uh2.used_total(5555, "blunt") == 1)


func _test_should_cuss_out() -> void:
	var conv := SimConversation.new()
	var uh_unit := _unhinged_unit(9001, "ogres", "blunt")
	var st_unit := _stable_unit(9002, "ogres")
	conv.set_ruler_mood(9001, -85.0)
	conv.set_ruler_mood(9002, -85.0)
	_check("furious+unhinged cusses",
		SimUnhinged.should_cuss_out(conv, uh_unit))
	_check("furious+stable silent",
		not SimUnhinged.should_cuss_out(conv, st_unit))
	conv.set_ruler_mood(9001, -10.0)
	_check("calm+unhinged silent",
		not SimUnhinged.should_cuss_out(conv, uh_unit))
	conv.set_ruler_mood(9001, -60.0)
	_check("threshold -60 cusses",
		SimUnhinged.should_cuss_out(conv, uh_unit))
	conv.set_ruler_mood(9001, -59.9)
	_check("above threshold silent",
		not SimUnhinged.should_cuss_out(conv, uh_unit))


func _test_cuss_out_reply() -> void:
	var conv := SimConversation.new()
	var uh_unit := _unhinged_unit(9003, "ogres", "blunt")
	conv.set_ruler_mood(9003, -85.0)
	var gs := {"ruler_name": "ass"}
	var res: Dictionary = conv.reply(uh_unit, "you suck", gs)
	_check("cussout intent", String(res.get("intent", "")) == "unhinged_cussout")
	_check("cussout text non-empty", String(res.get("text", "")) != "")
	var effect: Dictionary = res.get("effect", {})
	_check("spam effect", String(effect.get("type", "")) == "unhinged_spam")
	var extras: Array = effect.get("extras", [])
	_check("3 spam extras", extras.size() == 3)
	for e in extras:
		_check("extra non-empty", String(e) != "")
	# Stable NPC at same fury: normal engine, no cuss-out. Full engine
	# needs a real GameState (mirrors test_conversation_integration).
	var gs2: GameState = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs2.setup(farr)
	gs2.player_faction = "gnomes"
	gs2.set_ruler_name("ass")
	gs2.lexicon = load("res://scripts/sim/lexicon.gd").new(gs2)
	var conv2 := SimConversation.new()
	conv2.lexicon = gs2.lexicon
	var st_unit := _stable_unit(9004, "ogres")
	conv2.set_ruler_mood(9004, -85.0)
	var res2: Dictionary = conv2.reply(st_unit, "you suck", gs2)
	_check("stable not cussout",
		String(res2.get("intent", "")) != "unhinged_cussout")
	_check("stable no spam",
		String((res2.get("effect", {}) as Dictionary).get("type", "")) != "unhinged_spam")


func _test_profanity_and_slots() -> void:
	var conv := SimConversation.new()
	var uh_unit := _unhinged_unit(9005, "undead", "proud")
	conv.set_ruler_mood(9005, -95.0)
	var gs := {"ruler_name": "ass"}
	var res: Dictionary = conv.reply(uh_unit, "hello", gs)
	# Profanity is a pool-level design property, checked DETERMINISTICALLY.
	# A single random draw can legitimately land on one of the menacing-but-
	# clean lines (probed 2026-10-08: pools are 61-97% profane, e.g. cold is
	# 80%), so asserting one draw is profane is a ~1-in-5 flake. Instead,
	# assert every voice pool is majority-profane after slots are filled
	# exactly as the live path does (ruler "ass", like this test's reply).
	for voice in SimCussouts.voices():
		var v: Dictionary = SimCussouts.POOLS.get(voice, {})
		var total := 0
		var profane := 0
		for t in SimCussouts.TIERS:
			for line in (v.get(t, []) as Array):
				total += 1
				var filled: String = SimCussouts.fill(
					String(line), "ass", "Snag", "ogres").to_lower()
				for w in PROFANITY:
					if filled.contains(w):
						profane += 1
						break
		_check("pool %s majority profane (%d/%d)" % [voice, profane, total],
			total > 0 and profane * 2 >= total)
	_check("no raw {ruler} slot", not String(res.get("text", "")).contains("{ruler}"))
	_check("no raw {name} slot", not String(res.get("text", "")).contains("{name}"))
	# Ruler name actually lands in the line pool (spot check across draws).
	var uh := SimUnhinged.new()
	var found := false
	for i in range(40):
		var line: String = uh._draw(9006, "blunt", "furious", "ass",
			"Snag", "ogres")
		if line.contains("ass"):
			found = true
	_check("ruler name substituted", found)


func _test_tiers() -> void:
	_check("heated tier", SimUnhinged.tier_for(-65.0) == "heated")
	_check("furious tier", SimUnhinged.tier_for(-80.0) == "furious")
	_check("unhinged tier", SimUnhinged.tier_for(-95.0) == "unhinged")
	# Tier lines come from the right pool: unhinged tier has meltdown flavor.
	var uh := SimUnhinged.new()
	var line: String = uh._draw(9007, "neutral", "unhinged", "ass",
		"Nib", "gnomes")
	_check("tier draw non-empty", line != "")


func _test_apology_bump() -> void:
	var conv := SimConversation.new()
	var uh_unit := _unhinged_unit(9008, "humans", "pragmatic")
	conv.set_ruler_mood(9008, -65.0)
	var gs := {"ruler_name": "ass"}
	var res: Dictionary = conv.reply(uh_unit, "I'm sorry", gs)
	_check("apology still cusses (still furious)",
		String(res.get("intent", "")) == "unhinged_cussout")
	_check("apology bumps mood",
		abs(conv.ruler_mood(9008) - (-55.0)) < 0.001)
	# After enough apologies, de-escalates out of the cuss-out zone.
	for i in range(5):
		conv.reply(uh_unit, "sorry", gs)
	_check("de-escalated", conv.ruler_mood(9008) > -60.0)
	_check("no longer cusses",
		not SimUnhinged.should_cuss_out(conv, uh_unit))


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)
	return {"gs": gs, "mind": mind, "phone": phone}


func _spawn_unhinged(w: Dictionary, uid_seed: int) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit("ogres", "gatherer", -1,
		Vector2(100, 100))
	mind.ensure(u)
	var traits: Dictionary = u["mind"]["traits"]
	traits["unhinged"] = 1.0
	traits["persona"] = "blunt"
	return u


func _test_phone_spam_queue() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, 0)
	var uid := int(u["id"])
	phone.conversation.set_ruler_mood(uid, -85.0)
	phone.send_message(uid, "you suck")
	# 1 main cuss-out + 3 spam extras queued, each with typing indicators.
	_check("spam queued 4 pending", phone._pending.size() == 4)
	# Fast-forward past every delivery, then tick the queue.
	gs.game_time += 120.0
	phone.tick(0.0)
	var th: Dictionary = phone._thread(phone._key_for(uid))
	var npc_msgs := 0
	for m in th["messages"]:
		if String(m.get("from", "")) == "npc":
			npc_msgs += 1
	_check("4 npc messages arrived", npc_msgs == 4)
	_check("queue drained", phone._pending.is_empty())


func _test_blocked_silence() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, 0)
	var uid := int(u["id"])
	phone.conversation.set_ruler_mood(uid, -95.0)
	_check("block succeeds", phone.block_citizen(uid))
	phone.send_message(uid, "you suck")
	_check("blocked: nothing queued", phone._pending.is_empty())
	gs.game_time += 120.0
	phone.tick(0.0)
	var th: Dictionary = phone._thread(phone._key_for(uid))
	var npc_msgs := 0
	for m in th["messages"]:
		if String(m.get("from", "")) == "npc":
			npc_msgs += 1
	_check("blocked: no npc messages", npc_msgs == 0)
