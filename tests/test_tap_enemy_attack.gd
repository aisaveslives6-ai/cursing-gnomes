extends SceneTree
## Cursing Gnomes — tap-enemy-attack tests (Jeremy 2026-10-09).
##
## The audit's flagged follow-up: tapping an ENEMY (a faction at war with
## the player, or monsters) opens the command menu in attack-target mode
## (Attack-Move button relabeled "Attack Target"), so the entire military
## can engage the tapped enemy. Neutral/allied/own taps keep the info
## panel ONLY — attacking them would START a war, and war is never
## declared by accident (2026-10-04 diplomacy rule).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tap_enemy_attack.gd
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
	print("=== Cursing Gnomes tap-enemy-attack tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_war_faction_opens_attack_menu()
	_test_monster_opens_attack_menu()
	_test_neutral_tap_stays_info_panel()
	_test_allied_tap_stays_info_panel()
	_test_own_faction_tap_stays_info_panel()
	_test_no_military_tap_stays_info_panel()
	_test_empty_faction_tap_stays_info_panel()
	_test_relation_case_sensitive_war_only()
	_test_hud_attack_button_relabel()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## A faction at war with the player -> attack-target menu opens.
func _test_war_faction_opens_attack_menu() -> void:
	_check("war: enemy tap opens attack menu",
		World.enemy_tap_decision("ogres", "humans", "war", 5))


## Monsters are always hostile -> attack-target menu opens.
func _test_monster_opens_attack_menu() -> void:
	_check("monster: enemy tap opens attack menu even in peacetime",
		World.enemy_tap_decision("monster", "humans", "neutral", 3))


## Neutral faction -> info panel only (attacking would start a war).
func _test_neutral_tap_stays_info_panel() -> void:
	_check("neutral: tap keeps info panel only",
		not World.enemy_tap_decision("elves", "humans", "neutral", 5))
	_check("neutral (blank relation): tap keeps info panel only",
		not World.enemy_tap_decision("elves", "humans", "", 5))


## Allied faction -> info panel only.
func _test_allied_tap_stays_info_panel() -> void:
	_check("allied: tap keeps info panel only",
		not World.enemy_tap_decision("dwarves", "humans", "allied", 5))


## Own faction units -> info panel only (own selection behavior).
func _test_own_faction_tap_stays_info_panel() -> void:
	_check("own faction: tap keeps info panel only",
		not World.enemy_tap_decision("humans", "humans", "allied", 5))


## No military under command -> no attack menu even on a real enemy.
func _test_no_military_tap_stays_info_panel() -> void:
	_check("war but no military: tap keeps info panel only",
		not World.enemy_tap_decision("ogres", "humans", "war", 0))


## Unresolvable target faction (no unit_id/building_id) -> no menu.
func _test_empty_faction_tap_stays_info_panel() -> void:
	_check("empty faction: tap keeps info panel only",
		not World.enemy_tap_decision("", "humans", "war", 5))


## Only the exact "war" relation arms the menu — "tense"/"rival" do not.
func _test_relation_case_sensitive_war_only() -> void:
	_check("tense: tap keeps info panel only",
		not World.enemy_tap_decision("ogres", "humans", "tense", 5))
	_check("rival: tap keeps info panel only",
		not World.enemy_tap_decision("ogres", "humans", "rival", 5))


## HUD menu: enemy_target mode relabels the attack button and subtitle;
## normal mode keeps the classic "Attack-Move Here" wording.
func _test_hud_attack_button_relabel() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	gs.player_faction = "humans"
	gs.set("combat", SimCombat.new(gs))
	gs.set("tap_command", SimTapCommand.new(gs))
	# One commandable soldier so the menu gate (n > 0) passes.
	gs.spawner.spawn_unit("humans", "soldier", -1, Vector2(100, 100))
	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	# setup() builds the UI synchronously; frames already passed.
	hud.show_command_menu(Vector2(100, 100), -1, false)
	_check("normal mode: attack button keeps Attack-Move Here",
		hud._cmd_attack_btn.text == "Attack-Move Here")
	_check("normal mode: subtitle is the march line",
		hud._cmd_sub.text.begins_with("Tap an order"))
	hud.show_command_menu(Vector2(200, 200), -1, true)
	_check("enemy mode: attack button relabeled Attack Target",
		hud._cmd_attack_btn.text == "Attack Target")
	_check("enemy mode: subtitle names the enemy engagement",
		hud._cmd_sub.text.begins_with("An enemy is marked"))
	# Enemy mode resets back to normal labels on the next ground tap.
	hud.show_command_menu(Vector2(300, 300), -1, false)
	_check("labels reset to normal mode on next open",
		hud._cmd_attack_btn.text == "Attack-Move Here")
	hud.queue_free()
	gs.queue_free()
