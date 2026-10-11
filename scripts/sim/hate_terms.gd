class_name HateTerms
extends RefCounted
## Cursing Gnomes — racist language patterns (DATA FILE).
##
## Two tiers (Jeremy 2026-10-02):
##   HARD_R_PATTERNS — the hard-r n-word. THE line. If the PLAYER says this,
##     every faction declares war on the player (SimRacistOutrage).
##   OTHER_PATTERNS — other racial slurs and racist phrases. War trash-talk
##     tier: factions at war may sling these at each other; no realm-wide
##     consequences. Detected by SimHateSpeech.is_racist() (informational).
##
## Patterns are regex fragments matched case-insensitively. Word boundaries
## are baked in so "sniggered" or "spicy" never match.
##
## NOTE: this list exists so the game can punish in-character racism with
## in-character consequences. NPC lines never repeat these terms.
##
## Jeremy 2026-10-06: ANTI_LGBTQ_PATTERNS — anti-LGBTQ slurs. Same
## detection-only convention. When the PLAYER uses any of these (or any
## racial slur), it is the same hard line as the hard-r: the full
## SimRacistOutrage cascade (instant war from everyone, Gazette scandal,
## furious DMs, hearsay condemnation). Nobody ever finds them funny.

## The hard-r n-word, including its plural and hard-r compound slurs.
const HARD_R_PATTERNS: Array[String] = [
	"\\bniggers?\\b",
	"\\bsandniggers?\\b",
]

## Other racial slurs / racist phrases (trash-talk tier — no cascade).
const OTHER_PATTERNS: Array[String] = [
	"\\bniggas?\\b",
	"\\bnig\\b",
	"\\bchinks?\\b",
	"\\bgooks?\\b",
	"\\bspics?\\b",
	"\\bwetbacks?\\b",
	"\\bbeaners?\\b",
	"\\bkikes?\\b",
	"\\byids?\\b",
	"\\bragheads?\\b",
	"\\btowelheads?\\b",
	"\\bredskins?\\b",
	"\\bhonk(?:ey|eys|ies)\\b",
	"\\bwhiteys?\\b",
	"\\bpakis?\\b",
	"\\bjaps?\\b",
	"\\bwhite\\s*power\\b",
	"\\bmaster\\s*race\\b",
	"\\bkkk\\b",
	"\\bheil\\s+hitler\\b",
	"\\binferior\\s*race\\b",
	"\\bgo\\s*back\\s*to\\s*(where\\s*you\\s*came\\s*from|your\\s*country|africa|mexico|china)\\b",
	"\\bching\\s*chong\\b",
]

## Anti-LGBTQ slurs (Jeremy 2026-10-06). Detection-only, same as above:
## the PLAYER using any of these triggers the full outrage cascade.
## NPC lines never repeat these terms.
const ANTI_LGBTQ_PATTERNS: Array[String] = [
	"\\bfaggots?\\b",
	"\\bfags?\\b",
	"\\bdykes?\\b",
	"\\btrann(?:y|ies)\\b",
	"\\bhomos?\\b",
]
