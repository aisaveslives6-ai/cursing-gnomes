class_name SimDialogue
extends RefCounted
## Cursing Gnomes — offline/scripted NPC dialogue (Milestone 5: minds).
##
## HARD RULE: 100% offline. No LLM, no network calls, no web requests
## anywhere in this file or anything it touches. Every line is a hand-written
## scripted template picked deterministically from the unit id + game clock.
##
## Line tables reflect the NPC's urges, emotion, job, and personality.
## {ruler} is replaced with the ruler's name VERBATIM — never trimmed,
## never baked, never eaten (Jeremy's naming law). NPCs roasting the
## ruler's name is the game's charm; "ass" gets what "ass" deserves.
##
## Pure logic — no rendering, no input, no audio, no network.


## Ruler name-roasts. {ruler} is substituted verbatim. Keep them coming —
## the roast table is the soul of the game.
const ROAST_RULER: Array[String] = [
	"All hail {ruler}! ...I'm sorry, I can't keep a straight face.",
	"Our glorious ruler {ruler}. Glorious. Yep.",
	"Long live {ruler}! Long! Live! {ruler}! ...snrk.",
	"I named my mule {ruler}. Stubborn ass, both of 'em.",
	"{ruler} decrees it! ...wait, that's OUR ruler? Oh no.",
	"Hail {ruler}, first of their name, last of good names.",
	"They call 'em {ruler} 'cause 'your majesty' wouldn't fit on the coin.",
	"All kneel for {ruler}! ...I'll stand, thanks.",
	"{ruler}?! That's a NAME? My kid could do better. My kid's three.",
	"I'd die for {ruler}. ...okay, I'd mildly inconvenience myself for {ruler}.",
	"Our ruler {ruler} has a plan. Nobody knows what it is. Including {ruler}.",
	"Shh! The walls have ears. And {ruler} has... well. You know.",
	"All hail {ruler}, finest cheeks in the five kingdoms!",
	"{ruler} the Magnificent. The Magnificent... uh... what were we talking about?",
	"They crowned {ruler}. The crown's still recovering.",
	"I'd follow {ruler} into battle. Right behind the supply cart. Way behind.",
	"{ruler}? Sounds like a sneeze with a title.",
	"Our ruler {ruler} once tried to knight a goose. The goose declined.",
	"Hail {ruler}! May their reign be long and their speeches short.",
	"{ruler}'s royal portrait hangs in the privy. Most fitting place, honestly.",
	"They say {ruler} was born under a lucky star. The star has filed a complaint.",
	"All bow for {ruler}, the only monarch whose crown fits better on a turnip.",
	"{ruler} commands and the realm obeys. Mostly the realm just pretends.",
	"I carved {ruler}'s likeness in a turnip. The turnip protested.",
	"Long may {ruler} reign! The healers need the job security.",
	"{ruler}'s wisdom is like their war chest: rumored, never seen.",
	"Hail {ruler}, whose royal decrees smell faintly of turnips and regret.",
	"Our liege {ruler}: proof that crowns are cheaper than competence.",
	"{ruler} once held court for six hours. Six. The throne still bears the mark.",
	"Praise {ruler}! The bravest ruler to ever hide behind their own guards.",
]

## Nasty Monastery-grade disaster reactions. Picked with context "disaster".
const DISASTER_REACT: Array[String] = [
	"The monastery's brewing AGAIN? Lock the outhouses, hide the novices!",
	"A disaster in the Nasty Monastery? On a TUESDAY? So traditional.",
	"Smells like burnt sin and cheap incense. The monks are at it again.",
	"The monastery bells are ringing backwards. That's never good.",
	"Another 'holy' flood from the monastery. Holy my left buttock.",
	"The monks blessed the well again. Now it tastes like regret.",
	"Disaster struck! The Nasty Monastery ran out of... never mind, it's worse than you think.",
	"The abbot sneezed during vespers. Half the choir is now bald. Pray for them.",
	"Holy water, my foot -- that's why the river's on fire again.",
	"The monks found a new relic. It's sticky. Everything they find is sticky.",
	"Another monastery mishap! This one's going in the Nasty Ledger. Page forty.",
	"The Nasty Monastery choir hit a new note. The windows disagreed. Violently.",
]

## In-game Squabble feed posts. Picked with context "squabble_post".
const SQUABBLE_POST: Array[String] = [
	"Just saw the royal procession. The horse had better posture than the guards. #royalty",
	"Turnip prices are UP again. This is fine. This is all fine.",
	"Unpopular opinion: the outhouse behind the tavern is the real seat of power.",
	"Day 47 of asking the guards when the war ends. They laughed. I laughed. We cried.",
	"The elves released a new ballad. Three hours long. My ears have unionized.",
	"Someone's goat ate my laundry again. If it's yours, it now owes me a shirt.",
	"Brew pits are hiring! Must love heat, noise, and questionable decisions.",
	"The ogre blacksmith sneezed and my sword got sharper. 10/10 would recommend.",
	"Lost: one dignity, near the throne room. Reward if returned, no questions asked.",
	"PSA: the 'haunted' well is just Old Marn snoring. Stop throwing coins in it.",
	"The gnome engineers built a bridge. It goes nowhere. Bold. Visionary.",
	"Mood: watching the tax collector count MY coins with MY abacus.",
	"The war effort needs volunteers! Perks include: glory, mud, and more mud.",
	"Just traded three chickens for a 'magic' bean. Updates to follow. Send help.",
	"The human quarter's new fountain is gorgeous. The pigeons have claimed it. It's theirs now.",
	"Rating the tavern stews, thread: the brown one is a war crime. The green one's a war hero.",
]

## Dark crystal / undead corruption whispers. Picked with context "wicked".
const WICKED_WHISPER: Array[String] = [
	"The crystal sings at night. It knows your name. It knows ALL the names.",
	"Do not touch the black crystal. It touched back last time.",
	"The dead do not sleep here. They wait. They are very patient.",
	"I saw my reflection in the crystal. It was smiling. I was not.",
	"The corruption spreads like frost on a window. Pretty. Wrong.",
	"Something whispers from the dark stones. It sounds like... singing. Old singing.",
	"The undead king remembers every grave. He visits. He counts.",
	"The crystal's glow is violet now. It used to be blue. Do not ask what changed.",
	"I buried my brother twice. The crystal gave him back. Wrong. All wrong.",
	"At midnight the stones breathe. In. Out. In. Pray it never holds its breath.",
	"The corrupted ones smile too wide. Count their teeth. There are too many.",
	"Darkness pools where the crystal weeps. Do not drink the shadows.",
	"The old king's crown is fused to the crystal now. He is still wearing it. He is still ruling.",
	"Listen. The ground hums. That is not the ground. That is hunger.",
]

const HUNGRY: Array[String] = [
	"My stomach's filing a formal complaint.",
	"Is that stew? Tell me that's stew.",
	"I'd trade my boots for a sandwich. My GOOD boots.",
	"Hunger is the best spice. ...it's a terrible spice. Feed me.",
	"My belly thinks my throat's been cut.",
]

const EATING: Array[String] = [
	"Pass the gravy, ya beautiful muppet!",
	"This stew SLAPS. Who made this? ...Me? I made this.",
	"Mama's recipe again. Never gets old.",
	"Seconds? Don't mind if I DO.",
	"I grew this carrot MYSELF. Respect the carrot.",
	"Slow down, you'll choke! ...worth it.",
]

const TIRED: Array[String] = [
	"My eyelids are staging a coup.",
	"Five more minutes... just five...",
	"I've been awake since the last ice age, I swear.",
	"My bed is calling. Can you hear it? It's calling.",
]

const SCARED: Array[String] = [
	"NOPE. Nope nope nope nope.",
	"I didn't sign up for THIS!",
	"Somebody hold me. Somebody ARMED, preferably.",
	"My courage just left the building.",
	"I'm too pretty to die!",
]

const FLEE: Array[String] = [
	"RUN AWAY!",
	"Every gnome for themselves!",
	"Tactical retreat! Very tactical! Very fast!",
	"I'll avenge you all from over HERE.",
]

const ANGRY: Array[String] = [
	"Oh, it's ON now.",
	"You want some?! I'LL GIVE YOU SOME.",
	"My grandma hits harder than you. She's dead. Still hits harder.",
	"Come here and say that to my FACE.",
]

const HAPPY: Array[String] = [
	"Today is a GOOD day!",
	"I love you guys. Pass the bread.",
	"Everything's coming up {name}!",
	"Nothing can ruin this mood. NOTHING.",
]

const WORK: Array[String] = [
	"Another day, another denarius.",
	"Back to the grind. The grind pays for stew.",
	"Work work work. Somebody's gotta do it.",
	"My back hurts. My back ALWAYS hurts.",
]

const BUILD: Array[String] = [
	"Measure twice, cut once, swear repeatedly.",
	"This wall's gonna be LEGENDARY.",
	"Hold this beam. No, the OTHER beam.",
	"If this falls on me, avenge me.",
]

const HEAL: Array[String] = [
	"Hold still. This won't hurt. Much.",
	"Walk it off? No? Fine, lie down.",
	"I'm a doctor, not a miracle worker. ...okay, a little of both.",
	"Say 'ah'. No, don't actually, just hold still.",
]

const GREET: Array[String] = [
	"Well met, friend!",
	"Ho there! Fine day, innit?",
	"Oh! Hello! Didn't see you there.",
	"Sup.",
]

const TAUNT: Array[String] = [
	"Is that a sword or are you just happy to see me?",
	"My granny fights better! And she's a pacifist!",
	"Come on then! I've got stew waiting!",
	"You fight like a dairy farmer!",
]

const SOCIAL: Array[String] = [
	"Heard the gossip? ...I'll tell you anyway.",
	"You ever notice the elves smell like pine? Suspicious.",
	"So I said to the ogre — the OGRE — 'that's MY turnip.'",
	"Remember when dinner was a raw turnip? We've come so far.",
]


## Picks a line for a unit in a context. Deterministic: same unit + same
## clock = same line (no RNG state to save). {ruler} -> raw ruler name,
## {name} -> NPC's display name.
static func line_for(gs: GameState, unit: Dictionary, context: String) -> String:
	# CHEESE MANIA (Jeremy 2026-09-28, HTML npcChatter parity): humans
	# are comically obsessed with cheese — 38% of idle chatter is a
	# cheese line, upgrading to SCREAMS near a restaurant. Other
	# factions get food pride 8% of the time. The one non-deterministic
	# chatter path (ambient flavor only).
	if context == "chatter":
		var cheese := _cheese_chatter(gs, unit)
		if cheese != "":
			return _fill(gs, unit, cheese)
	var table: Array[String] = _table_for(gs, unit, context)
	if table.is_empty():
		return ""
	var uid: int = int(unit.get("id", 0))
	var idx: int = absi(uid * 31 + int(gs.game_time) + gs.day_number * 7) % table.size()
	return _fill(gs, unit, table[idx])


## CHEESE MANIA ambient hook (see line_for).
static func _cheese_chatter(gs: GameState, unit: Dictionary) -> String:
	var race: String = SimChatxMood.race_of(String(unit.get("faction", "gnome")))
	if race == "human":
		if randf() >= 0.38:
			return ""
		var pool: Array = ChatxMoodLines.CHEESE_SCREAMS \
			if _near_restaurant(gs, unit) else ChatxMoodLines.CHEESE_LINES
		if pool.is_empty():
			return ""
		return String(pool[randi() % pool.size()])
	if randf() < 0.08:
		var pride: Array = ChatxMoodLines.FOOD_PRIDE.get(race, [])
		if pride.is_empty():
			return ""
		return String(pride[randi() % pride.size()])
	return ""


static func _near_restaurant(gs: GameState, unit: Dictionary) -> bool:
	var upos: Vector2 = unit.get("position", Vector2.ZERO)
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "restaurant" \
				and bool(b.get("alive", true)):
			var bpos: Vector2 = b.get("position", Vector2.ZERO)
			if upos.distance_squared_to(bpos) < 360.0 * 360.0:
				return true
	return false


## Picks the table: explicit context wins, otherwise the NPC's current
## state (critical urge > emotion > job) decides.
static func _table_for(gs: GameState, unit: Dictionary, context: String) -> Array[String]:
	match context:
		"roast_ruler":
			return ROAST_RULER
		"squabble_post":
			return SQUABBLE_POST
		"disaster":
			return DISASTER_REACT
		"wicked":
			return WICKED_WHISPER
		"hungry":
			return HUNGRY
		"eating":
			return EATING
		"tired":
			return TIRED
		"scared":
			return SCARED
		"flee":
			return FLEE
		"angry":
			return ANGRY
		"happy":
			return HAPPY
		"greet":
			return GREET
		"taunt":
			return TAUNT
		"work":
			return WORK
		"build":
			return BUILD
		"heal":
			return HEAL
		"social":
			return SOCIAL
	# "chatter": read the NPC's state.
	var mind: Dictionary = unit.get("mind", {})
	var crit: String = String(mind.get("critical_urge", ""))
	match crit:
		"hunger":
			return HUNGRY
		"energy":
			return TIRED
		_:
			pass  # bladder/hygiene/social/mood chatter falls through to emotion/job
	var emo: String = String((unit.get("emotion", {}) as Dictionary).get("name", "neutral"))
	match emo:
		"scared":
			return SCARED
		"angry":
			return ANGRY
		"happy", "proud":
			return HAPPY
	var job: String = String(unit.get("job", ""))
	if job == "builder":
		return BUILD
	if job == "doctor":
		return HEAL
	if JobDefs.is_military(job):
		return TAUNT
	if SimPersonality.trait_of(unit, "friendly") >= 0.6:
		return SOCIAL
	return WORK


## Token fill. {ruler} is the RAW ruler name — verbatim, never trimmed.
static func _fill(gs: GameState, unit: Dictionary, line: String) -> String:
	var out: String = line.replace("{ruler}", gs.ruler_name)
	out = out.replace("{name}", SimPersonality.display_name(unit))
	return out
