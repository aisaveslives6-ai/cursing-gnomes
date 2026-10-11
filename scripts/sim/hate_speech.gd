class_name SimHateSpeech
extends RefCounted
## Cursing Gnomes — two-tier racist language detection for player chat.
##
## Jeremy 2026-10-02 (refined):
##   TIER 1 — WAR TRASH-TALK (allowed): factions at war sling slurs at each
##     other. Normal. No consequences. Detected by is_racist().
##   TIER 2 — THE HARD-R LINE: the PLAYER says the hard-r n-word.
##     Detected by is_hard_r(). Triggers SimRacistOutrage: every faction
##     declares war on the player, Gazette scandal, hearsay, furious DMs.
##
## Pure logic, no game state. Patterns live in HateTerms (data file).

static var _hard_r_rx: RegEx = null
static var _other_rx: RegEx = null
static var _lgbtq_rx: RegEx = null


static func _hard_r() -> RegEx:
	if _hard_r_rx == null:
		_hard_r_rx = RegEx.new()
		_hard_r_rx.compile("(?i)(?:" + "|".join(PackedStringArray(HateTerms.HARD_R_PATTERNS)) + ")")
	return _hard_r_rx


static func _other() -> RegEx:
	if _other_rx == null:
		_other_rx = RegEx.new()
		_other_rx.compile("(?i)(?:" + "|".join(PackedStringArray(HateTerms.OTHER_PATTERNS)) + ")")
	return _other_rx


## Jeremy 2026-10-06: anti-LGBTQ slur patterns (HateTerms.ANTI_LGBTQ_PATTERNS).
static func _lgbtq() -> RegEx:
	if _lgbtq_rx == null:
		_lgbtq_rx = RegEx.new()
		_lgbtq_rx.compile("(?i)(?:" + "|".join(PackedStringArray(HateTerms.ANTI_LGBTQ_PATTERNS)) + ")")
	return _lgbtq_rx


## True when the text contains the hard-r n-word. THE line.
static func is_hard_r(text: String) -> bool:
	return _hard_r().search(text) != null


## True for ANY racist language (hard-r or trash-talk tier). Informational:
## war trash-talk between factions is allowed and carries no consequences.
static func is_racist(text: String) -> bool:
	if is_hard_r(text):
		return true
	return _other().search(text) != null


## Jeremy 2026-10-06: THE line for player text — true when the text
## contains ANY IRL hate slur: the hard-r n-word, any other IRL racial
## slur, or any anti-LGBTQ slur. Single source of truth for both the
## phone-DM outrage cascade and the smear-pipeline "never funny"
## guardrail. NPC war trash-talk is NOT gated by this (that stays
## informational via is_racist); only player text goes through here.
static func is_hate_slur(text: String) -> bool:
	if text.is_empty():
		return false
	if is_hard_r(text):
		return true
	if _other().search(text) != null:
		return true
	return _lgbtq().search(text) != null


## Returns the matched hard-r term, or "" when none (for incident reports).
static func find_hard_r(text: String) -> String:
	var m: RegExMatch = _hard_r().search(text)
	return m.get_string() if m != null else ""
