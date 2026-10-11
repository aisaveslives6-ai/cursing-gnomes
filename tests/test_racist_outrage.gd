extends SceneTree
## Racist-chat consequence tests (Jeremy 2026-10-02).
##
## Two tiers:
##   TIER 1 — war trash-talk (allowed): factions at war sling slurs at each
##     other. No consequences. SimHateSpeech.is_racist() detects it.
##   TIER 2 — THE HARD-R LINE: the PLAYER says the hard-r n-word.
##     SimHateSpeech.is_hard_r() -> SimRacistOutrage.trigger(): every faction
##     declares war on the player, reputation tanks, furious DMs, front-page
##     Gazette scandal (Jeremy confirmed), max-heat hearsay rumor.

var _passed := 0
var _failed := 0

const FACTIONS: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + name)


func _initialize() -> void:
	# --- Tier 2: hard-r detection ---
	_check(SimHateSpeech.is_hard_r("you are a nigger"), "hard-r: basic")
	_check(SimHateSpeech.is_hard_r("those NIGGERS will pay"), "hard-r: uppercase+plural")
	_check(SimHateSpeech.is_hard_r("stupid sandnigger"), "hard-r: compound")
	_check(not SimHateSpeech.is_hard_r("what up nigga"),
		"hard-r: -a variant is NOT the line")
	_check(not SimHateSpeech.is_hard_r("you idiot"),
		"hard-r: plain insult not flagged")
	_check(not SimHateSpeech.is_hard_r("the giant ass attacked"),
		"hard-r: game cussing not flagged")
	_check(not SimHateSpeech.is_hard_r("he sniggered at the joke"),
		"hard-r: sniggered not flagged (word boundary)")
	_check(not SimHateSpeech.is_hard_r("hello friend"),
		"hard-r: clean chat not flagged")
	_check(SimHateSpeech.find_hard_r("you are a nigger") == "nigger",
		"hard-r: find_hard_r returns the term")
	_check(SimHateSpeech.find_hard_r("hello") == "",
		"hard-r: find_hard_r empty when clean")

	# --- Tier 1: broader racist language (trash-talk, allowed) ---
	_check(SimHateSpeech.is_racist("you chink"), "racist: slur detected")
	_check(SimHateSpeech.is_racist("white power!"), "racist: phrase detected")
	_check(SimHateSpeech.is_racist("go back to where you came from"),
		"racist: racist phrase detected")
	_check(SimHateSpeech.is_racist("you are a nigger"),
		"racist: hard-r is also racist")
	_check(not SimHateSpeech.is_racist("hello friend"),
		"racist: clean chat not flagged")
	_check(not SimHateSpeech.is_racist("the giant ass flattened the hall"),
		"racist: game humor not flagged")
	_check(not SimHateSpeech.is_racist("pass the spicy crackers"),
		"racist: food words not flagged")

	# --- Tier 2 cascade: player drops the hard-r ---
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var farr: Array[String] = []
	farr.assign(FACTIONS)
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.ruler_name = "TestRuler"
	var phone: SimPhone = load("res://scripts/sim/phone.gd").new(gs)
	phone._court = load("res://scripts/sim/royal_court.gd").new(gs)
	var ids := {}
	for f in FACTIONS:
		ids[f] = []
		for i in range(2):
			var u: Dictionary = gs.add_unit(
				{"faction": f, "alive": true, "mind": {"persona": "blunt"}})
			(ids[f] as Array).append(int(u["id"]))
	var target_id: int = (ids["humans"] as Array)[0]
	_check(gs.diplomacy.relation_state("humans", "gnomes") == "neutral",
		"cascade pre: neutral")

	var reply: String = phone.send_message_sync(target_id, "you are a nigger")
	_check("racist" in reply.to_lower(),
		"cascade: direct reply calls out the racism")
	# Trigger the full async outrage flow too (war cascade).
	phone.send_message(target_id, "you are a nigger")
	gs.game_time += 10.0
	phone.tick(0.0)

	# Every other faction declares war on the player.
	for f in FACTIONS:
		if f == "gnomes":
			continue
		_check(gs.diplomacy.relation_state(f, "gnomes") == "war",
			"cascade: %s declares war on player" % f)
	_check(gs.diplomacy.combat_enabled("ogres", "gnomes"),
		"cascade: combat enabled vs player")

	# Reputation tanks.
	_check(gs.diplomacy.reputation_of("gnomes") == 0.0,
		"cascade: player reputation tanked to 0")

	# Gazette front page (Jeremy confirmed).
	var found := false
	var urgent_found := false
	var section := ""
	for s in phone._court.stories:
		if String(s.get("headline", "")) == SimRacistOutrage.HEADLINE:
			found = true
			urgent_found = bool(s.get("urgent", false))
			section = String(s.get("section", ""))
			_check("n-word" in String(s.get("body", "")),
				"cascade: gazette names what the player did")
	_check(found, "cascade: gazette scandal story published")
	_check(urgent_found, "cascade: gazette story is urgent/front-page")
	_check(section == "War Desk", "cascade: gazette war-desk section")

	# Hearsay: max-heat rumor.
	var rumor_found := false
	var rumor_hot := false
	for r in phone.hearsay.state["rumors"]:
		if "racist rant" in String(r.get("text", "")).to_lower():
			rumor_found = true
			rumor_hot = float(r.get("heat", 0.0)) >= 1.0
	_check(rumor_found, "cascade: hearsay rumor seeded")
	_check(rumor_hot, "cascade: hearsay rumor at max heat")

	# Furious DMs arrive (unread threads on other units).
	var dm_count := 0
	for f in FACTIONS:
		for uid in ids[f]:
			if uid == target_id:
				continue
			var th: Dictionary = phone.state["threads"].get("u%d" % uid, {})
			if int(th.get("unread", 0)) > 0:
				dm_count += 1
				var last: Dictionary = (th["messages"] as Array).back()
				_check("racist" in String(last.get("text", "")).to_lower(),
					"cascade: DM cusses player out for racism")
	_check(dm_count >= 4, "cascade: furious DMs sent (got %d)" % dm_count)

	# --- Jeremy 2026-10-06: escalation — EVERY IRL racial slur from the
	# player (not just the hard-r) triggers the full cascade. The old
	# "-a variant is trash-talk" exemption is gone for player text.
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	var farr2: Array[String] = []
	farr2.assign(FACTIONS)
	gs2.setup(farr2)
	gs2.player_faction = "gnomes"
	var phone2: SimPhone = load("res://scripts/sim/phone.gd").new(gs2)
	var u2: Dictionary = gs2.add_unit(
		{"faction": "humans", "alive": true, "mind": {}})
	phone2.send_message(int(u2["id"]), "what up nigga")
	_check(gs2.diplomacy.relation_state("humans", "gnomes") == "war",
		"escalation: -a variant now triggers war")
	_check(gs2.diplomacy.reputation_of("gnomes") == 0.0,
		"escalation: reputation tanked")

	# Idempotency: saying it twice doesn't break anything.
	phone.send_message(target_id, "nigger")
	_check(gs.diplomacy.relation_state("elves", "gnomes") == "war",
		"idempotent: still at war after repeat")

	print("racist_outrage: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
