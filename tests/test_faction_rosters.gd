extends SceneTree
## Cursing Gnomes — faction military roster tests (humans/ogres/elves/gnomes).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_faction_rosters.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
##
## Numbers asserted here are the HTML build's verbatim mechanics (fix79):
## RACES bases, the Unit job-branch stat multipliers, COSTS, TRAIN_TIME,
## Building.canTrain gates, and the C61 faction-unique abilities
## (cleric smite/heal/cure, warlord aura, blunderbuss cone, treant siege,
## saboteur wall-shred, spellweaver snare, warlock summons, knight charge,
## mage rotating spells).


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes faction roster tests ===")
	_test_roster_tables()
	_test_apply_faction_stats()
	_test_train_gates()
	_test_jobs_military()
	_test_warlock_summon()
	_test_warlord_aura()
	_test_snare()
	_test_cleric_smite_and_medic()
	_test_knight_charge()
	_test_blunderbuss_cone()
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


## Fresh game + combat + factions systems.
func _new_world(faction_ids: Array) -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var typed: Array[String] = []
	typed.assign(faction_ids)
	gs.setup(typed)
	var combat := SimCombat.new(gs)
	var fac := SimFactions.new(gs)
	gs.factions = fac
	return {"gs": gs, "combat": combat, "factions": fac}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


## Perf R19: SimFactions.tick processes every 3rd call (20Hz). One _step
## drives a full stagger cadence with the same simulated time: three
## fac.tick(total/3) calls, the third of which processes with d3 = total.
func _step(fac: SimFactions, total_delta: float) -> void:
	fac.tick(total_delta / 3.0)
	fac.tick(total_delta / 3.0)
	fac.tick(total_delta / 3.0)


func _spawn(w: Dictionary, faction: String, job: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


## --- roster tables (HTML verbatim) -------------------------------------------


func _test_roster_tables() -> void:
	var r: Dictionary = SimFactions.FACTION_ROSTERS
	# Humans (race hp 200, dmg 9).
	_check("roster: human 4 jobs", (r["humans"] as Dictionary).size() == 4)
	_check("roster: swordsman hp x1.0",
		float(r["humans"]["swordsman"]["hp_mul"]) == 1.0)
	_check("roster: swordsman dmg x1.05",
		float(r["humans"]["swordsman"]["dmg_mul"]) == 1.05)
	_check("roster: swordsman speed 95",
		float(r["humans"]["swordsman"]["speed"]) == 95.0)
	_check("roster: swordsman ar 0.42",
		float(r["humans"]["swordsman"]["attack_rate"]) == 0.42)
	_check("roster: archer hp x0.85",
		float(r["humans"]["archer"]["hp_mul"]) == 0.85)
	_check("roster: archer range 115",
		float(r["humans"]["archer"]["range"]) == 115.0)
	_check("roster: knight hp x1.55",
		float(r["humans"]["knight"]["hp_mul"]) == 1.55)
	_check("roster: knight ar 0.22",
		float(r["humans"]["knight"]["attack_rate"]) == 0.22)
	_check("roster: knight range 48",
		float(r["humans"]["knight"]["range"]) == 48.0)
	_check("roster: knight charge", bool(r["humans"]["knight"]["charge"]))
	_check("roster: cleric smite+medic",
		bool(r["humans"]["cleric"]["smite"]) and bool(r["humans"]["cleric"]["medic"]))
	_check("roster: cleric cost 70g/30w",
		r["humans"]["cleric"]["cost"] == {"gold": 70.0, "wood": 30.0})
	_check("roster: cleric train 7",
		float(r["humans"]["cleric"]["train_time"]) == 7.0)
	# Ogres (race hp 550, dmg 38).
	_check("roster: ogre 6 jobs", (r["ogres"] as Dictionary).size() == 6)
	_check("roster: clubber dmg x1.1",
		float(r["ogres"]["clubber"]["dmg_mul"]) == 1.1)
	_check("roster: clubber speed 137",
		float(r["ogres"]["clubber"]["speed"]) == 137.0)
	_check("roster: musketeer range 210",
		float(r["ogres"]["musketeer"]["range"]) == 210.0)
	_check("roster: berserker hp x1.45",
		float(r["ogres"]["berserker"]["hp_mul"]) == 1.45)
	_check("roster: berserker splash 72/0.55",
		float(r["ogres"]["berserker"]["splash"]) == 72.0
		and float(r["ogres"]["berserker"]["splash_mul"]) == 0.55)
	_check("roster: berserker speed 236",
		float(r["ogres"]["berserker"]["speed"]) == 236.0)
	_check("roster: warlord hp x2.2",
		float(r["ogres"]["warlord"]["hp_mul"]) == 2.2)
	_check("roster: warlord aura", bool(r["ogres"]["warlord"]["aura_buff"]))
	_check("roster: warlord train 20",
		float(r["ogres"]["warlord"]["train_time"]) == 20.0)
	_check("roster: warlord cost 160g/60w",
		r["ogres"]["warlord"]["cost"] == {"gold": 160.0, "wood": 60.0})
	_check("roster: blunderbuss pellets",
		bool(r["ogres"]["blunderbuss"]["pellets"]))
	_check("roster: blunderbuss range 95",
		float(r["ogres"]["blunderbuss"]["range"]) == 95.0)
	_check("roster: cannoneer splash 90/0.7",
		float(r["ogres"]["cannoneer"]["splash"]) == 90.0
		and float(r["ogres"]["cannoneer"]["splash_mul"]) == 0.7)
	# Gnomes (race hp 160, dmg 14).
	_check("roster: gnome 4 jobs", (r["gnomes"] as Dictionary).size() == 4)
	_check("roster: mage dmg x2.8",
		float(r["gnomes"]["mage"]["dmg_mul"]) == 2.8)
	_check("roster: mage splash 120/0.85",
		float(r["gnomes"]["mage"]["splash"]) == 120.0
		and float(r["gnomes"]["mage"]["splash_mul"]) == 0.85)
	_check("roster: mage spells", bool(r["gnomes"]["mage"]["spells"]))
	_check("roster: mage trains at barracks+mage_spire",
		"barracks" in r["gnomes"]["mage"]["trained_at"]
		and "mage_spire" in r["gnomes"]["mage"]["trained_at"])
	_check("roster: tinker_mech hp x3.2",
		float(r["gnomes"]["tinker_mech"]["hp_mul"]) == 3.2)
	_check("roster: tinker_mech train 16",
		float(r["gnomes"]["tinker_mech"]["train_time"]) == 16.0)
	_check("roster: saboteur wall_shred",
		bool(r["gnomes"]["saboteur"]["wall_shred"]))
	_check("roster: saboteur speed 192",
		float(r["gnomes"]["saboteur"]["speed"]) == 192.0)
	# Elves (race hp 180, dmg 11).
	_check("roster: elf 4 jobs", (r["elves"] as Dictionary).size() == 4)
	_check("roster: warlock summoner",
		bool(r["elves"]["warlock"]["summoner"]))
	_check("roster: warlock range 125",
		float(r["elves"]["warlock"]["range"]) == 125.0)
	_check("roster: treant hp x4.0",
		float(r["elves"]["treant"]["hp_mul"]) == 4.0)
	_check("roster: treant siege", bool(r["elves"]["treant"]["siege"]))
	_check("roster: treant speed 68",
		float(r["elves"]["treant"]["speed"]) == 68.0)
	_check("roster: spellweaver snare",
		bool(r["elves"]["spellweaver"]["snare"]))
	_check("roster: spellweaver range 230",
		float(r["elves"]["spellweaver"]["range"]) == 230.0)
	# Ability constants (HTML verbatim).
	_check("const: smite x1.6", SimFactions.CLERIC_SMITE_MUL == 1.6)
	_check("const: siege x2", SimFactions.SIEGE_BUILDING_MUL == 2.0)
	_check("const: wall shred x1.5", SimFactions.SABOTEUR_WALL_MUL == 1.5)
	_check("const: aura radius 320", SimFactions.WARLORD_AURA_RADIUS == 320.0)
	_check("const: aura x1.25", SimFactions.WARLORD_AURA_MUL == 1.25)
	_check("const: snare x0.5/6s",
		SimFactions.SNARE_MUL == 0.5 and SimFactions.SNARE_TIME == 6.0)
	_check("const: charge x2.2", SimFactions.KNIGHT_CHARGE_MUL == 2.2)
	_check("const: pellets 5 x0.16",
		SimFactions.BLUNDER_PELLETS == 5
		and SimFactions.BLUNDER_SPREAD == 0.16)


## --- apply_faction_stats -------------------------------------------------------


func _test_apply_faction_stats() -> void:
	var w: Dictionary = _new_world(["humans", "ogres", "elves", "gnomes"])
	var fac: SimFactions = w["factions"]
	# Note: use raw dicts, not _spawn() — the spawner auto-applies faction
	# stats, which would double-apply here. This tests apply_faction_stats
	# in isolation.
	# Ogre clubber: race hp 550, dmg floor(38*1.1)=41.
	var c: Dictionary = {"faction": "ogres", "job": "clubber", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(c)
	_check("stats: clubber hp 550", float(c["hp"]) == 550.0)
	_check("stats: clubber dmg 41", float(c["dmg"]) == 41.0)
	_check("stats: clubber speed 137", float(c["speed"]) == 137.0)
	_check("stats: clubber ar 0.55", float(c["attack_rate"]) == 0.55)
	# Human knight: hp floor(200*1.55)=310, dmg floor(9*1.35)=12.
	var k: Dictionary = {"faction": "humans", "job": "knight", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(k)
	_check("stats: knight hp 310", float(k["hp"]) == 310.0)
	_check("stats: knight dmg 12", float(k["dmg"]) == 12.0)
	_check("stats: knight speed 119", float(k["speed"]) == 119.0)
	_check("stats: knight charge flag", bool(k.get("charge", false)))
	# Human archer: hp floor(200*0.85)=170, dmg floor(9*0.95)=8.
	var a: Dictionary = {"faction": "humans", "job": "archer", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(a)
	_check("stats: archer hp 170", float(a["hp"]) == 170.0)
	_check("stats: archer dmg 8", float(a["dmg"]) == 8.0)
	_check("stats: archer range 115", float(a["range"]) == 115.0)
	# Human cleric: hp 220, dmg 8, smite + medic.
	var cl: Dictionary = {"faction": "humans", "job": "cleric", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(cl)
	_check("stats: cleric hp 220", float(cl["hp"]) == 220.0)
	_check("stats: cleric smite flag", bool(cl.get("smite", false)))
	_check("stats: cleric medic flag", bool(cl.get("medic", false)))
	# Ogre warlord: hp floor(550*2.2)=1210, dmg floor(38*1.8)=68.
	var wl: Dictionary = {"faction": "ogres", "job": "warlord", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(wl)
	_check("stats: warlord hp 1210", float(wl["hp"]) == 1210.0)
	_check("stats: warlord dmg 68", float(wl["dmg"]) == 68.0)
	_check("stats: warlord aura flag", bool(wl.get("aura_buff", false)))
	# Ogre musketeer: hp floor(550*0.85)=467, dmg floor(38*1.35)=51.
	var mu: Dictionary = {"faction": "ogres", "job": "musketeer", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(mu)
	_check("stats: musketeer hp 467", float(mu["hp"]) == 467.0)
	_check("stats: musketeer dmg 51", float(mu["dmg"]) == 51.0)
	_check("stats: musketeer range 210", float(mu["range"]) == 210.0)
	# Ogre blunderbuss: hp floor(550*1.3)=715, dmg 41, pellets.
	var bb: Dictionary = {"faction": "ogres", "job": "blunderbuss", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(bb)
	_check("stats: blunderbuss hp 715", float(bb["hp"]) == 715.0)
	_check("stats: blunderbuss pellets flag", bool(bb.get("pellets", false)))
	# Gnome mage: hp floor(160*0.9)=144, dmg floor(14*2.8)=39.
	var mg: Dictionary = {"faction": "gnomes", "job": "mage", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(mg)
	_check("stats: mage hp 144", float(mg["hp"]) == 144.0)
	_check("stats: mage dmg 39", float(mg["dmg"]) == 39.0)
	_check("stats: mage splash 120", float(mg.get("splash", 0.0)) == 120.0)
	# Gnome tinker_mech: hp floor(160*3.2)=512, dmg floor(14*2.2)=30.
	var tm: Dictionary = {"faction": "gnomes", "job": "tinker_mech", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(tm)
	_check("stats: tinker_mech hp 512", float(tm["hp"]) == 512.0)
	_check("stats: tinker_mech dmg 30", float(tm["dmg"]) == 30.0)
	# Gnome saboteur: hp floor(160*0.8)=128, wall_shred.
	var sb: Dictionary = {"faction": "gnomes", "job": "saboteur", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(sb)
	_check("stats: saboteur hp 128", float(sb["hp"]) == 128.0)
	_check("stats: saboteur wall_shred", bool(sb.get("wall_shred", false)))
	# Elf warlock: hp floor(180*1.05)=189, dmg floor(11*2.2)=24.
	var wk: Dictionary = {"faction": "elves", "job": "warlock", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(wk)
	_check("stats: warlock hp 189", float(wk["hp"]) == 189.0)
	_check("stats: warlock dmg 24", float(wk["dmg"]) == 24.0)
	_check("stats: warlock summoner", bool(wk.get("summoner", false)))
	# Elf treant: hp floor(180*4.0)=720, dmg floor(11*2.6)=28, siege.
	var tr: Dictionary = {"faction": "elves", "job": "treant", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(tr)
	_check("stats: treant hp 720", float(tr["hp"]) == 720.0)
	_check("stats: treant dmg 28", float(tr["dmg"]) == 28.0)
	_check("stats: treant siege flag", bool(tr.get("siege", false)))
	# Elf spellweaver: dmg floor(11*1.1)=12, range 230, snare.
	var sw: Dictionary = {"faction": "elves", "job": "spellweaver", "hp": 0.0, "dmg": 0.0}
	fac.apply_faction_stats(sw)
	_check("stats: spellweaver dmg 12", float(sw["dmg"]) == 12.0)
	_check("stats: spellweaver snare flag", bool(sw.get("snare", false)))
	# Unknown job: untouched.
	var s: Dictionary = {"faction": "humans", "job": "soldier", "hp": 0.0, "dmg": 0.0}
	var hp_before: float = float(s["hp"])
	fac.apply_faction_stats(s)
	_check("stats: soldier untouched", float(s["hp"]) == hp_before)
	_free_world(w)


## --- training gates (HTML Building.canTrain) -------------------------------------


func _test_train_gates() -> void:
	_check("gate: human barracks swordsman",
		SimFactions.can_train_gate("humans", "barracks", "swordsman"))
	_check("gate: human barracks archer",
		SimFactions.can_train_gate("humans", "barracks", "archer"))
	_check("gate: human barracks cleric",
		SimFactions.can_train_gate("humans", "barracks", "cleric"))
	_check("gate: human barracks NOT knight",
		not SimFactions.can_train_gate("humans", "barracks", "knight"))
	_check("gate: knights_castle knight",
		SimFactions.can_train_gate("humans", "knights_castle", "knight"))
	_check("gate: ogre barracks clubber/musketeer/blunderbuss",
		SimFactions.can_train_gate("ogres", "barracks", "clubber")
		and SimFactions.can_train_gate("ogres", "barracks", "musketeer")
		and SimFactions.can_train_gate("ogres", "barracks", "blunderbuss"))
	_check("gate: ogre barracks NOT berserker",
		not SimFactions.can_train_gate("ogres", "barracks", "berserker"))
	_check("gate: war_hut berserker/cannoneer/warlord",
		SimFactions.can_train_gate("ogres", "war_hut", "berserker")
		and SimFactions.can_train_gate("ogres", "war_hut", "cannoneer")
		and SimFactions.can_train_gate("ogres", "war_hut", "warlord"))
	_check("gate: gnome barracks axeman/mage/saboteur",
		SimFactions.can_train_gate("gnomes", "barracks", "axeman")
		and SimFactions.can_train_gate("gnomes", "barracks", "mage")
		and SimFactions.can_train_gate("gnomes", "barracks", "saboteur"))
	_check("gate: mage_spire mage/tinker_mech",
		SimFactions.can_train_gate("gnomes", "mage_spire", "mage")
		and SimFactions.can_train_gate("gnomes", "mage_spire", "tinker_mech"))
	_check("gate: elf barracks ranger/treant",
		SimFactions.can_train_gate("elves", "barracks", "ranger")
		and SimFactions.can_train_gate("elves", "barracks", "treant"))
	_check("gate: elf barracks NOT warlock",
		not SimFactions.can_train_gate("elves", "barracks", "warlock"))
	_check("gate: tome_library warlock/spellweaver",
		SimFactions.can_train_gate("elves", "tome_library", "warlock")
		and SimFactions.can_train_gate("elves", "tome_library", "spellweaver"))
	_check("gate: undead barracks skeleton/zombie/ghoul",
		SimFactions.can_train_gate("undead", "barracks", "skeleton")
		and SimFactions.can_train_gate("undead", "barracks", "zombie")
		and SimFactions.can_train_gate("undead", "barracks", "ghoul"))
	_check("gate: necropolis elite line",
		SimFactions.can_train_gate("undead", "necropolis", "necromancer")
		and SimFactions.can_train_gate("undead", "necropolis", "wraith")
		and SimFactions.can_train_gate("undead", "necropolis", "plaguebearer")
		and SimFactions.can_train_gate("undead", "necropolis", "bone_golem"))


## --- jobs registry -----------------------------------------------------------------


func _test_jobs_military() -> void:
	for job: String in ["swordsman", "knight", "cleric", "clubber",
			"musketeer", "berserker", "warlord", "blunderbuss", "axeman",
			"tinker_mech", "saboteur", "warlock", "treant", "spellweaver"]:
		_check("jobs: %s is military" % job, JobDefs.is_military(job))


## --- warlock summons -----------------------------------------------------------------


func _test_warlock_summon() -> void:
	var w: Dictionary = _new_world(["elves"])
	var gs: GameState = w["gs"]
	var fac: SimFactions = w["factions"]
	var wk: Dictionary = _spawn(w, "elves", "warlock", Vector2(0, 0))
	wk["combat_state"] = "attacking"
	wk["summon_cd"] = 0.0
	var before: int = gs.units.size()
	# 30 simulated seconds at 35%/s -> virtually certain to summon.
	for i: int in range(60):
		_step(fac, 0.5)
		var found := false
		for u: Dictionary in gs.units:
			if bool(u.get("is_summon", false)):
				found = true
				break
		if found:
			break  # check the cooldown before it ticks away
	var spirits: Array[Dictionary] = []
	for u: Dictionary in gs.units:
		if bool(u.get("is_summon", false)):
			spirits.append(u)
	_check("summon: spirit summoned", not spirits.is_empty())
	if not spirits.is_empty():
		var s: Dictionary = spirits[0]
		_check("summon: hp 40", float(s["hp"]) == 40.0)
		_check("summon: dmg 12", float(s["dmg"]) == 12.0)
		_check("summon: range 40", float(s["range"]) == 40.0)
		_check("summon: name Spirit", String(s.get("name", "")) == "Spirit")
		_check("summon: warlock on cooldown",
			float(wk.get("summon_cd", 0.0)) > 0.0)
		# Spirits expire after 18 s.
		s["summon_life"] = 0.05
		_step(fac, 0.1)
		_check("summon: spirit expires",
			not (s as Dictionary).get("alive", true))
	_check("summon: pop grew", gs.units.size() >= before)
	_free_world(w)


## --- warlord aura ---------------------------------------------------------------------


func _test_warlord_aura() -> void:
	var w: Dictionary = _new_world(["ogres", "humans"])
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var fac: SimFactions = w["factions"]
	var wl: Dictionary = _spawn(w, "ogres", "warlord", Vector2(0, 0))
	var ally: Dictionary = _spawn(w, "ogres", "clubber", Vector2(100, 0))
	var foe: Dictionary = _spawn(w, "humans", "worker", Vector2(100, 0))
	_step(fac, 1.1)  # aura pulse fires; the same step decays by 1.1 s
	_check("aura: ally marked",
		absf(float(ally.get("aura61", 0.0)) - 1.9) < 0.01)
	_check("aura: warlord not self-marked",
		float(wl.get("aura61", 0.0)) == 0.0)
	_check("aura: foe not marked", float(foe.get("aura61", 0.0)) == 0.0)
	# Aura damage: clubber (soldier fallback 15 x ogre 1.9 = 28.5) x 1.25.
	var tgt: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	var hp0: float = float(tgt["hp"])
	ally["position"] = Vector2(0, 0)
	combat._attack(ally, tgt, SimCombat.MILITARY_STATS["soldier"])
	var dealt_aura: float = hp0 - float(tgt["hp"])
	_check("aura: damage x1.25",
		absf(dealt_aura - 28.5 * 1.25) < 0.01)
	# Aura decays; without it the hit is the plain 28.5.
	_step(fac, 3.1)
	_check("aura: decayed", float(ally.get("aura61", 0.0)) == 0.0)
	tgt["hp"] = hp0
	combat._attack(ally, tgt, SimCombat.MILITARY_STATS["soldier"])
	_check("aura: plain damage after decay",
		absf((hp0 - float(tgt["hp"])) - 28.5) < 0.01)
	_free_world(w)


## --- spellweaver snare ------------------------------------------------------------------


func _test_snare() -> void:
	var w: Dictionary = _new_world(["elves", "humans"])
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var fac: SimFactions = w["factions"]
	var sw: Dictionary = _spawn(w, "elves", "spellweaver", Vector2(0, 0))
	var tgt: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	tgt["speed"] = 130.0
	_check("snare: hook fires",
		fac.maybe_snare_on_hit(sw, tgt))
	_check("snare: speed halved", float(tgt["speed"]) == 65.0)
	_check("snare: 6 s timer", float(tgt["snare_t"]) == 6.0)
	# Non-spellweaver attackers don't snare.
	var k: Dictionary = {"faction": "humans", "job": "knight", "hp": 0.0, "dmg": 0.0}
	tgt["speed"] = 130.0
	tgt.erase("snare_t")
	_check("snare: knight does not snare",
		not fac.maybe_snare_on_hit(k, tgt))
	# Via the combat damage hook.
	tgt["speed"] = 130.0
	combat.damage_unit(int(tgt["id"]), 5.0, "elves", int(sw["id"]))
	_check("snare: via damage_unit", float(tgt["speed"]) == 65.0)
	# Snare wears off and the base speed is restored.
	_step(fac, 6.1)
	_check("snare: expires", not tgt.has("snare_t"))
	_check("snare: speed restored", float(tgt["speed"]) == 130.0)
	_free_world(w)


## --- cleric smite + medic -----------------------------------------------------------------


func _test_cleric_smite_and_medic() -> void:
	var w: Dictionary = _new_world(["humans", "undead"])
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var cl: Dictionary = _spawn(w, "humans", "cleric", Vector2(0, 0))
	# Smite: cleric (soldier fallback 15 dmg) vs undead -> floor(15*1.6)=24.
	var zed: Dictionary = _spawn(w, "undead", "worker", Vector2(10, 0))
	var hp0: float = float(zed["hp"])
	combat._attack(cl, zed, SimCombat.MILITARY_STATS["soldier"])
	_check("smite: 24 vs undead", absf((hp0 - float(zed["hp"])) - 24.0) < 0.01)
	# Same cleric vs a living target: plain 15.
	var civ: Dictionary = _spawn(w, "humans", "worker", Vector2(10, 0))
	var hp1: float = float(civ["hp"])
	combat._attack(cl, civ, SimCombat.MILITARY_STATS["soldier"])
	_check("smite: 15 vs living", absf((hp1 - float(civ["hp"])) - 15.0) < 0.01)
	# Clerics revive the downed like doctors (HTML MEDIC_JOBS).
	var down: Dictionary = _spawn(w, "humans", "worker", Vector2(20, 0))
	down["downed"] = true
	down["downed_timer"] = 60.0
	down["hp"] = 0.0
	cl["position"] = Vector2(20, 0)
	combat.tick_medics(0.1)
	_check("medic: cleric revives", not bool(down.get("downed", true)))
	# A cleric's revive purges the zombie plague (one patient per call).
	var plagued: Dictionary = _spawn(w, "humans", "worker", Vector2(20, 0))
	plagued["downed"] = true
	plagued["downed_timer"] = 60.0
	plagued["hp"] = 0.0
	plagued["infected"] = {"t": 5.0, "src": "zombie"}
	combat.tick_medics(0.1)
	_check("medic: cleric cures plague",
		not bool(plagued.get("downed", true)) and not plagued.has("infected"))
	_free_world(w)


## --- knight charge --------------------------------------------------------------------------


func _test_knight_charge() -> void:
	var w: Dictionary = _new_world(["humans"])
	var combat: SimCombat = w["combat"]
	var k: Dictionary = {"faction": "humans", "job": "knight", "hp": 0.0, "dmg": 0.0}
	k["firearm"] = "basic"
	# Long approach (>200 px): floor(15*2.2) = 33.
	var far: Dictionary = _spawn(w, "humans", "worker", Vector2(300, 0))
	var hp0: float = float(far["hp"])
	combat._attack(k, far, SimCombat.MILITARY_STATS["soldier"])
	_check("charge: 33 after long approach",
		absf((hp0 - float(far["hp"])) - 33.0) < 0.01)
	# Short approach: plain 15.
	var near: Dictionary = _spawn(w, "humans", "worker", Vector2(30, 0))
	var hp1: float = float(near["hp"])
	combat._attack(k, near, SimCombat.MILITARY_STATS["soldier"])
	_check("charge: 15 up close",
		absf((hp1 - float(near["hp"])) - 15.0) < 0.01)
	_free_world(w)


## --- blunderbuss cone ----------------------------------------------------------------------------


func _test_blunderbuss_cone() -> void:
	var w: Dictionary = _new_world(["ogres", "humans"])
	var combat: SimCombat = w["combat"]
	var bb: Dictionary = {"faction": "ogres", "job": "blunderbuss", "hp": 0.0, "dmg": 0.0}
	bb["firearm"] = "basic"  # deterministic: no shotgun tier mult
	var tgt: Dictionary = _spawn(w, "humans", "worker", Vector2(80, 0))
	combat.projectiles.clear()
	combat._attack(bb, tgt, SimCombat.MILITARY_STATS["soldier"])
	_check("cone: 5 pellets", combat.projectiles.size() == 5)
	var ok := true
	# dmg = 15 x ogre 1.9 = 28.5; pellet = floor(28.5*0.55) = 15.
	for p: Dictionary in combat.projectiles:
		if float(p.get("dmg", 0.0)) != 15.0:
			ok = false
		if float(p.get("splash", 0.0)) != 32.0:
			ok = false
		if String(p.get("kind", "")) != "shotgun":
			ok = false
	_check("cone: pellet dmg 15, splash 32, shotgun kind", ok)
	# Pellets spread: distinct impact points.
	var pts := {}
	for p: Dictionary in combat.projectiles:
		var tp: Vector2 = p.get("target_pos", Vector2.ZERO)
		pts["%d|%d" % [int(tp.x), int(tp.y)]] = true
	_check("cone: pellets spread", pts.size() == 5)
	_free_world(w)
