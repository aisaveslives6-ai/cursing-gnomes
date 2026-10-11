class_name SimHearsay
extends RefCounted
## Cursing Gnomes — gossip propagation engine (Milestone 6+).
##
## How rumors work (ported from the HTML build's gossip/chatter mechanics,
## overhauled 2026-10-06):
##   - SPAWN: real sim events seed rumors — Gazette stories, wars, disasters
##     (wildfires included — one shared rumor per outbreak), crimes,
##     festivals (rich named-town rumors via bus.festival_event, not the
##     thin Gazette story — the realm celebrates, mourns cancellations,
##     and basks in wind-downs), court decisions and filings, deeds, deaths of
##     notables, construction/destruction, monastery captures, trade,
##     tribute (paid AND refused), and relation shifts. Nothing invented.
##     Famines (2026-10-09): the AI director's food-emergency alarms were
##     Gazette-only — the mill never heard them. Now the mill reads the
##     same granary ledgers and seeds rich named-faction starvation
##     rumors (shortage AND critical), with a relief rumor when the
##     granaries fill again.
##     Strategic proposals (2026-10-09): the proposal grapevine was
##     half-dead in live play — bus.strategic_proposal only fires for the
##     PLAYER's faction while the handler ignores the player, so AI war
##     plots and troop buildups never gossiped. AI factions decide
##     synchronously inside propose(), so the decided signal is now the
##     grapevine's hook: approved buildups seed "mass troops" talk
##     (scout-quest eligible), and DENIED sue-for-peace proposals seed
##     peace-feeler gossip (the beaten faction debated begging and said
##     no). Approved peace feelers need no rumor — the surrender offer
##     lands the same tick via _on_surrender_offered.
##     Nuclear (2026-10-09): the sun-bomb had no voice of its own — a
##     detonation rode the generic disaster path ("A nuke rampages
##     through {town}!", war-rivals LAUGHING at a sun-bomb) while its
##     own Gazette story double-seeded a thin twin rumor, and a launch
##     seeded a faceless war line. Now: the detonation story folds into
##     the rich blast rumor (no twin), the launch gets its own rich
##     rumor (nuke_launch=true, launcher named, truth TRUE — every
##     court felt the tremor), blasts record hit town + launcher, the
##     stricken despair in terror, the launcher's people rally grimly,
##     war-rivals feel DREAD instead of mockery (even the enemy falls
##     silent), and everyone else stands in awe. Nukes join the slur /
##     famine witnessed-fact club (no doubt dent, no distortion dent)
##     and cross every border like war news — the flash was visible
##     realm-wide.
##     Court filings (2026-10-09): the crown's RULING gossiped since
##     10-08, but a petition being FILED — a courtier standing up to ask
##     — was a deaf thread. Now the ask seeds its own rumor (subject
##     "petition_filed:<id>", disjoint from the verdict's "petition:<id>"):
##     the petitioner feels pride and hope, their folk take an interest,
##     friends drum up support, rivals mock the ask, and a war-shaped
##     plea filed against your people lands as dread, not gossip. Hot
##     filings (threat/betrayal/raids/drafts) reach the crown's ear as a
##     DM; routine pleas stay below the ruler's bar.
##   - DEDUP: a live rumor with the same kind+subject refreshes instead of
##     duplicating (war stories used to double-seed).
##   - SPREAD: each day, knowers tell others (same faction preferred;
##     blocked NPCs are excluded). Tell caps are per-knower — happy/angry
##     NPCs are loudmouths, sad/scared ones withdraw, and UNHINGED NPCs
##     are super-spreaders (wider caps, louder rolls). Spread zeal is
##     relationship-driven: amused tellers push a smear about a disliked
##     target harder, reluctant ones barely whisper dirt about a friend,
##     and slur/scandal condemnation is contagious. THE BORDER-CROSSING
##     GRAPEVINE (2026-10-08): every knower also gets one cross-faction
##     tell attempt per day, routed by kind and relationship — war news
##     reaches the other recorded side (plots reach the would-be target,
##     conquests reach the loser's/taker's kin), slur/scandal condemnation
##     and diplomacy news travel to allied realms, everything else
##     trickles across open borders. Only war news crosses a war border.
##     Receivers run a
##     BELIEF check (faction loyalty, wariness of enemy tellers): believers
##     join as knowers, skeptics doubt and don't spread.
##   - RECEPTION: every new knower actually HEARS the rumor — a real memory
##     plus an emotion by kind — so NPCs understand the news and the
##     conversation engine can reference it. Witnesses of events (disasters,
##     moonings, priest bursts) join the rumor directly with memories,
##     replacing the old speech-bubble shouts (no-ops since the bubble ban).
##     War news gets a full reaction matrix: the attacked side fears the
##     drums, the attacking side rallies, surrender news moves morale —
##     no dead-end rumors nobody cares about.
##     Conquest/betrayal news gets the same treatment: captures record
##     BOTH sides (holder_old/holder_new) — the side that LOST a monastery,
##     crystal, or town feels shame and fury, the takers feel pride;
##     treaty-breakers and the betrayed react in character (defiance vs
##     outrage); tribute refusers stand defiant while the demander seethes.
##     Buildings record their lost holder too, so a fallen hall is mourned,
##     not just noted.
##     Disaster rumors record the stricken town (hit_faction/hit_town):
##     the victims panic, war-rivals laugh at the misery (schadenfreude),
##     and allies grieve — wildfires name their town the same way.
##     Nuclear blasts are NOT weather (2026-10-09): the stricken despair
##     in terror and awe, the launcher's people rally grimly, war-rivals
##     feel DREAD instead of mockery (even the enemy falls silent at a
##     sun-bomb), and everyone else stands in awe. A loosed sun-spear
##     (nuke_launch) fills the whole realm with dread — nobody knows
##     where it lands.
##     A disaster that struck the wilds is just news (generic reception).
##     Famines (2026-10-09): the starving faction's hunger is witnessed
##     fact — its people despair, war-rivals cackle at the empty pots
##     (schadenfreude), and everyone else grieves a little. A lifted
##     famine becomes a relief rumor: the recovered faction celebrates.
##     Deaths of notables record the dead's faction (dead_faction): their
##     own faction mourns, war-rivals cackle at the loss, everyone else
##     pays respects — obituaries with no recorded faction stay generic.
##     War PLOTS (2026-10-08): a declare-war proposal records BOTH sides
##     (side_a = the plotter, side_b = the target) plus war_plot=true —
##     the TARGET's people fear the looming drums (brave ones get angry
##     instead of cowering, stands_ground parity), the plotter's people
##     grimly anticipate the fight. A denied plot flips to tavern comedy
##     (plot_denied=true): the would-be target breathes relief, the
##     plotters get roasted by name, everyone else laughs. Plot rumors
##     with no recorded target (old saves) stay generic.
##     Denied peace feelers (2026-10-09) get their own matrix: the proud
##     burn with shame at the begging talk, hawks stand defiant, doves
##     despair that the war grinds on, the would-be recipients gloat,
##     and war-rivals cackle.
##     Gossip (2026-10-08): Yapper-grade tavern talk about a named
##     citizen — the victim is mortified, rivals cackle, friends defend,
##     neutrals are mildly amused, and the town remembers who laughed
##     and who stood up (HTML p13CitizenMemoryLine parity). The victim
##     id rides the subject ("gossip:<unit_id>") — no cross-file edits.
##     Crime (2026-10-08): the crime systems emit bus.crime_committed
##     with the parties BEFORE the Gazette story publishes, so the mill
##     seeds a named crime rumor and dedups the party-less story seed.
##     The victim is outraged (grudge aimed at the crook), the named
##     thief is caught out (unhinged ones brag), the town feels unsafe,
##     rivals mock the thief, and the crook's friends are disappointed —
##     and the thief's reputation bleeds with every hearer. An UNSEEN
##     thief (live-path spot check failed) still outrages the victim but
##     can't be named, mocked, or shamed: no name, no shame.
##
## Rumor schema: {id, text, text_orig, kind, subject, day, heat (0..1),
##   knowers: Array[int], reached_ruler: bool, distortions: int,
##   side_a/side_b (war: declarer/defender), loser/winner (surrenders),
##   war_plot (declare-war proposal: unconfirmed plot), plot_denied,
##   peace_feeler (denied sue-for-peace: the beaten faction's council
##     debated begging and said no — side_a = would-be beggars, side_b =
##     would-be recipients),
##   holder_old/holder_new (conquest: loser/taker), betrayer/betrayed,
##   refuser/demander (tribute refused), lost_holder (building destroyed),
##   hit_faction/hit_town (disaster: stricken town),
##   dead_faction (death: dead notable's faction),
##   crook_id/victim_id/crime_kind (crime: the thief, the robbed, the kind)
##   fest_event/fest_town/fest_faction/fest_joy (festival: held|cancelled|
##   wound_down, the celebrating town, host faction, joy granted)}
##   famine_faction (famine: the starving faction), famine_critical,
##   relief (famine: the hunger lifted — a happy-news rumor)
##   petitioner_id/petitioner_name/petitioner_faction (court: the asker),
##   petition_verdict (court RULING), petition_filing/petition_hot
##   (court FILING: the ask, hot = war-shaped)
##   - DOUBT (2026-10-07): "doubters" — unit IDs that heard and didn't buy
##     it. Doubt is contagious: a rumor the town already scoffs at is
##     believed less (capped dent, never a kill). Proud skeptics scoff
##     publicly ("scoffed_at_rumor" memory). Slur incidents are witnessed
##     fact — the realm never doubts them down (the hard line holds); the
##     deniable kinds (smears, misc) take the full hit.
##   - DIP (diplomacy subtype, 2026-10-07): "news"-kind rumors carry
##     dip/side_a/side_b (peace, alliance, trade, hostile), payer/receiver
##     (tribute paid), or founder (town founded) — the diplomacy reaction
##     matrix keys off it; rumors without it get the generic reception.
##   - DEAD (death subtype, 2026-10-07): "death"-kind rumors carry
##     dead_faction — the dead notable's faction — keyed off by the death
##     reaction matrix; facet-less obituaries get the generic reception.
##   - FALSE SMEARS (2026-10-08): invented tavern lies are the ONLY
##     rumors seeded untrue — a citizen who dislikes someone sometimes
##     makes one up about them (truth "false", liar recorded as
##     source_id). NPC-sourced smears get their own reaction: the target
##     is furious at the LIAR (never the crown — only player smears
##     blame the player). Debunking a false smear rehabilitates the
##     target (the reputation the lie took is given back) and leaves its
##     believers sheepish; verifying a true rumor vindicates believers.
##   - DISTORTION: telephone game — spread rumors can mutate a little
##     (capped at MAX_DISTORTIONS = 3), so gossip degrades with distance.
##     Original kept in text_orig. A twice-told tale is less credible:
##     each hop dents _belief a little.
##   - DECAY: rumor heat fades daily; cold rumors die out.
##   - REACH THE RULER: hot rumors (heat >= 0.6) reach the crown as a DM
##     from a named citizen — the realm's gossip, delivered.
##   - SQUABBLE: major events also become NPC posts (HTML sqbGenDeeds /
##     sqbOnWarDeclared parity): wars, disasters, famines, notable deaths,
##     treaties.
##
## All lines are offline/scripted. No network, no LLM, ever.

const MAX_RUMORS := 40
const SPREAD_HEAT := 0.2
const RULER_HEAT := 0.6
const DECAY := 0.82
## Jeremy 2026-10-06 (hearsay flesh-out): the rumor mill feeds the press.
## A rumor hot enough (PRESS_HEAT) and talked-about enough
## (PRESS_MIN_KNOWERS) earns Gazette coverage — the front page reports the
## realm's talk AS talk (rumors don't cite sources), honestly labeled.
## One story per day max; ambient life/misc chatter never qualifies, and
## Gazette-born stories are never re-printed (no ping-pong).
const PRESS_HEAT := 0.85
const PRESS_MIN_KNOWERS := 1
const PRESS_EXCLUDE_KINDS: Array[String] = ["life", "misc",
	# Jeremy 2026-10-08 (hearsay flesh-out): the front page covers war,
	# scandal, and realm-shaking talk — not who lost an argument with a
	# chicken. Yapper's tavern gossip never qualifies for print.
	"gossip",
	# Jeremy 2026-10-09 (hearsay flesh-out): the calendar turning is
	# tavern talk, not news — winter comes every year, it needs no
	# front page.
	"season",
	# Jeremy 2026-10-10 (hearsay flesh-out): weather arrivals are
	# tavern talk too — the sky changes every day, it needs no front
	# page.
	"weather",
	# Jeremy 2026-10-10 (hearsay flesh-out): brigade rollouts are tavern
	# talk too — the engine rolls most fires, it needs no front page.
	"brigade",
	# Jeremy 2026-10-11 (hearsay flesh-out): dealership talk is tavern
	# talk too — a new wagon is gossip, not a headline.
	"vehicle"]

## Jeremy 2026-10-06 (lane 6: investigation + reputation + rumor quests).
## A rumor this hot can spawn an advisor proposal (scout the buildup,
## investigate the cache). Debunked rumors never qualify for anything.
const QUEST_HEAT := 0.7
## How many NPCs the crown's investigators ask per investigation.
const INVESTIGATE_N := 3
## Reputation: per-NPC 0..100 (50 = nobody's heard of them). Believed
## rumors move the needle; caps keep one rumor from nuking a life.
const REP_DEFAULT := 50.0
const REP_SMEAR_HIT := 2.0    # per believer, against the smear target
const REP_SMEAR_CAP := 30.0   # total NPC shift one rumor may cause
# Jeremy 2026-10-08 (hearsay flesh-out): a NAMED thief's reputation bleeds
# with every hearer — the town remembers who stole from whom. Capped per
# rumor so one whisper can't end a career; unseen thieves dodge it (no
# name, no shame).
const REP_CRIME_HIT := 1.5    # per hearer, against the named crook
const REP_CRIME_CAP := 20.0   # total NPC shift one crime rumor may cause
const REP_FACTION_SMEAR := -2.0
const REP_FACTION_DEED_GOOD := 1.0
const REP_FACTION_DEED_BAD := -1.5
const REP_SLUR_FACTION := -20.0
## Jeremy 2026-10-10 (hearsay flesh-out): rumor-borne fury feeds the
## conversation grudge ledger. The smeared target's public shaming lands
## like a direct insult (SimConversation.GRUDGE_PTS "insult" parity);
## defenders and told-targets carry half weight (it wasn't said about
## them / came second-hand).
const SMEAR_GRUDGE_TARGET := 8.0
const SMEAR_GRUDGE_SECONDARY := 4.0
## Belief depth (hearsay flesh-out, 2026-10-06): first-hand witnesses make
## a rumor harder to dismiss, and the teller's own reputation colors
## their word. Both feed _belief — see the weights below.
const WITNESS_BELIEF_EACH := 0.06  # +belief per first-hand witness
const WITNESS_BELIEF_CAP := 0.30   # five eyewitnesses maxes it out
const TELLER_TRUST_WEIGHT := 0.15  # Beloved teller +0.15, Despised -0.15
## Belief depth (hearsay flesh-out, 2026-10-07): a twice-told tale is less
## credible — each telephone-game hop dents belief a little. And doubt is
## contagious: a rumor the town already scoffs at is believed less (the
## dent is capped — doubt can slow a hot rumor, never kill one outright).
## The doubters list is bounded so the 240-unit cap never grows it.
const DISTORT_BELIEF_EACH := 0.08  # per distortion hop, max 3
const DOUBT_BELIEF_EACH := 0.04    # per recorded doubter
const DOUBT_BELIEF_CAP := 0.20     # total doubt dent per rumor
const DOUBT_TRACK_CAP := 24        # bound the doubters list
## Rumor truth: "true" (a real sim event seeded it), "false" (disproven),
## "unknown" (tavern talk nobody can verify). Only false rumors can be
## debunked — investigators bury claims they can disprove, nothing else.
## SLUR rumors are always "true" (the incident really happened) and can
## NEVER be debunked — the hard line holds in the investigation path too.
const TRUTH_TRUE := "true"
const TRUTH_FALSE := "false"
const TRUTH_UNKNOWN := "unknown"

## Gossip DM openers (HTML citizen-chatter flavor).
const GOSSIP_OPENERS: Array[String] = [
	"Psst… word on the street: {t}",
	"Have you heard? {t}",
	"Between you and me, sire: {t}",
	"The taverns are buzzing — {t}",
]
## Jeremy 2026-10-04: moods in hearsay — HOW an NPC tells a rumor is
## colored by their mood. The teller's mood picks the opener pool.
const MOOD_GOSSIP_OPENERS := {
	"happy": [
		"Oh, you'll LOVE this: {t} — isn't that great!",
		"Best news ever!! {t}",
		"Guess what guess what — {t}! Wonderful, right?",
		"Hehe, wait till you hear this: {t}",
	],
	"sad": [
		"I heard {t}... it's just depressing.",
		"More bad news, I'm afraid: {t}",
		"Sigh. {t}. Everything's awful.",
		"Don't shoot the messenger... {t}",
	],
	"angry": [
		"Have you heard about {t}? I'm FURIOUS.",
		"You're NOT going to believe this: {t}. Unbelievable!",
		"Listen up: {t}. Somebody's going to pay.",
		"This is outrageous: {t}!",
	],
	"scared": [
		"Um... I heard {t}. Should we be worried?",
		"Please don't panic, but... {t}",
		"I-I heard something scary: {t}",
		"Is it true that {t}? I'm frightened.",
	],
	"proud": [
		"As someone of discernment, I report: {t}",
		"I have it on excellent authority: {t}",
		"Mark my words: {t}. I called it.",
		"A little bird told ME first: {t}",
	],
	"disgusted": [
		"Ugh, you'll want to sit down: {t}. Filthy business.",
		"I can barely bring myself to repeat this: {t}",
		"Disgusting news, sire: {t}",
		"Hold your nose: {t}",
	],
	"neutral": [
		"Psst… word on the street: {t}",
		"Have you heard? {t}",
		"Between you and me, sire: {t}",
		"The taverns are buzzing — {t}",
	],
}
## Squabble war lines (HTML SQB_WAR).
const WAR_LINES: Array[String] = [
	"WAR with the {f}! Finally, a use for all these pointy sticks. ⚔",
	"The {f} picked a fight with US? Bold. Stupid, but bold. See you at the border. ⚔",
	"War economy time, baby. Blacksmiths are booked solid till spring. 💰⚔",
	"They say the {f} want war. Fine. I've been sharpening this axe since breakfast.",
	"WAR! Hide your pies, kiss your sweetheart, and for gods' sake oil your boots.",
	"The {f} declared war and my first thought was 'there goes my nap schedule'.",
	"To arms! The {f} come, and they shall find us... mostly annoyed about it.",
	"War with the {f}. My grandmother predicted this. She predicts everything, but still.",
	"Breaking: {f} wants a fight. Developing: we're going to give them one.",
	"They picked the wrong week to mess with us. Harvest is in and the pitchforks are sharp.",
	"WAR. Again. Does anyone else feel like we do this every other Tuesday?",
	"The {f} think we're soft. Cute. Wait till they meet the tax collectors.",
]
## Jeremy 2026-10-05: faction-voiced war lines — ogres blunt, elves elegant,
## gnomes mischievous, undead cold, humans diplomatic.
const WAR_LINES_FACTION := {
	"ogres": [
		"WAR! {f} die now! Me already sharpening! 💪",
		"{f} want fight? HA! Me eat their champions for breakfast!",
		"Finally! Talking time over! Smashing time NOW!",
		"Me hear {f} coming. Good. Me bored.",
	],
	"elves": [
	"The {f} have chosen the path of blades. We shall walk it with grace, and end it swiftly. 🏹",
	"War with the {f}. A tragedy in three acts, and we intend to write the ending.",
	"The {f} mistake our patience for weakness. They will learn the difference.",
	"We did not want this war with the {f}. But we have wanted for nothing in a thousand years — we shall want for victory neither.",
	],
	"gnomes": [
	"WAR with the {f}! Great news for my weapons dealership! Terrible news for everyone else! 💰",
	"Psst. {f} war bonds, going cheap. This is definitely not insider trading.",
	"The {f} want war? I've already sold helmets to both sides. Business is business!",
	"War! Quick, someone start a rumor that {f} gold is cursed so prices crash and I can buy low!",
	],
	"undead": [
	"The {f} declare war. How... temporary of them. 💀",
	"War with the {f}. We have waited centuries. We can wait out their siege too.",
	"The {f} bring war to the deathless. Amusing.",
	"More bodies for the cause. Thank you, {f}, for your contribution.",
	],
	"humans": [
	"The {f} have forced our hand. We go to war with heavy hearts and full granaries.",
	"War with the {f} is declared. The crown asks for courage; the crown will get it.",
	"We tried peace with the {f}. Peace declined the invitation.",
	"To every citizen: the {f} test us now. We have never failed such a test.",
	],
}
## Squabble disaster lines (HTML SQB_DISASTER).
const DISASTER_LINES: Array[String] = [
	"A {d} just hit {t} and the council's response was 'thoughts and prayers'. Classic governance. 💀",
	"{d} in {t}! The rebuild starts Monday. Or whenever the screaming stops. 🏚",
	"Well, {t} is having a day. A {d} kind of day. Send help and pies.",
	"Breaking: {d} devastates {t}. The seers claim they 'saw it coming'. Sure you did.",
	"{t} just got hit by a {d}. Property values are about to crater.",
	"A {d} in {t}! My cousin lives there. He says it's 'fine'. It's not fine.",
	"Pray for {t}, they just met a {d} up close and personal. 🏚",
	"The {d} spared no one in {t}. Except the tax office. Figures.",
]
## Jeremy 2026-10-09 (hearsay flesh-out): the sun-bomb gets its own voice.
## A nuclear blast is not weather — the realm doesn't gossip about the
## sky catching fire like it's a hailstorm. Detonation lines (awe and
## horror, never tavern comedy) and launch lines (the spear is climbing
## and nobody knows where it lands).
const NUKE_LINES: Array[String] = [
	"A second sun just died over {t}. I saw the flash from three valleys away. My beard is still standing up. ☀💀",
	"{t} is gone. Not 'damaged'. GONE. The crater glows green. Send nothing — there's nothing to send it to.",
	"They say the sky caught fire over {t}. THE SKY. CAUGHT. FIRE.",
	"Pray for {t}. Actually pray for all of us — whoever did this has MORE of them. ☢",
	"{l} just rearranged the map. {t} is a nightlight now.",
	"The seers felt it too. Every one of them went quiet at once. That's never happened.",
]
const NUKE_LAUNCH_LINES: Array[String] = [
	"A bright spear just climbed out of {f} territory. Every court felt the ground tremble. Gods help whoever it's aimed at. 🚀",
	"{f} loosed a sun-spear. If you see a second sunrise today, it's already too late.",
	"The {f} silos are OPEN. Repeat: the silos are OPEN.",
	"Something just left {f} airspace straight UP. The birds all went silent. Make of that what you will.",
]
## Jeremy 2026-10-06 (hearsay flesh-out): wildfire Squabble lines.
## Fires never emitted disaster_spawned, so the grapevine was deaf to
## them — these give the realm its scared-flavored fire chatter.
const FIRE_LINES: Array[String] = [
	"FIRE! Smoke on the horizon and the wind is NOT helping. 🔥",
	"Wildfire past the treeline — my whole street smells like a campfire and nobody's camping. 🔥",
	"The sky went orange. Either sunset's early or the forest is on fire. It's the forest. 🔥",
	"Word is the wildfire's spreading. Pack a bucket, a shovel, and your least-flammable cousin.",
	"Beasts are fleeing the treeline ahead of the flames — when the deer panic, I panic. 🔥",
	"Another wildfire. The forest has been 'due for a controlled burn' since my grandfather's day. 🔥",
	"Smoke so thick you could chew it. Stay inside, soak your roof, pray to whoever's listening. 🔥",
	"They say the wildfire jumped the creek. Nothing jumps creeks except trouble and salmon. 🔥",
]
## Jeremy 2026-10-09 (hearsay flesh-out): storm-omen Squabble lines —
## lightning striking a dark crystal. {god} = crystal display name,
## {owner} = holding faction's display name (or "no faction").
const CRYSTAL_STRIKE_LINES: Array[String] = [
	"Saw lightning hit {god} with my own eyes. The hum is still in my teeth. ⚡",
	"{god} just ate a lightning bolt and hummed like a struck bell. Tell me that's not an omen.",
	"The sky split over {god} — {owner} hold it, and I'd be sleeping with one eye open.",
	"Lightning struck {god} AGAIN. Either the gods are fighting or the weather's showing off.",
	"Whole tavern went quiet when the flash hit {god}. Even the dice stopped rolling. ⚡",
	"{god} flared purple-white when the bolt landed. My ale rippled. MY ALE.",
	"Priest says the strike on {god} means the rogue gods are restless. Priest also says my aura's cloudy, so.",
	"If I held {god} I'd be reading that lightning as a performance review. {owner}, take note.",
	"Third strike I've counted on {god} this storm. Somebody up there has opinions.",
	"{god} got smote and all I got was this ringing in my ears. ⚡",
]
## Jeremy 2026-10-10 (hearsay flesh-out): trespass Squabble lines —
## someone was seen slipping into somebody else's house. {snoop} =
## the trespasser's display name, {owner} = the house owner's.
const TRESPASS_LINES: Array[String] = [
	"{snoop} was seen slipping into {owner}'s house. Broad daylight and everything — bold or stupid, you decide. 👀",
	"{snoop} crept into {owner}'s house after dark, and somebody SAW. The tavern is already placing bets on why. 👀",
	"Word is someone slipped into {owner}'s house last night. Nobody admits seeing it, but EVERYBODY's heard about it.",
	"Lock your doors, people — {snoop} was caught coming out of {owner}'s place with a story nobody believes. 👀",
	"{owner} found {snoop} INSIDE their house. The shouting could be heard three streets over.",
	"New tavern game: guess what {snoop} was doing in {owner}'s house. Wrong answers only.",
	"{snoop} says they were 'just visiting' {owner}'s house. At midnight. Through the back. Sure.",
	"Somebody's been sneaking into {owner}'s house — the whole street's talking and {snoop}'s name keeps coming up. 👀",
	"{owner} changed their locks today. Wonder what {snoop} did. 👀",
	"Caught red-handed: {snoop}, {owner}'s house, no good explanation. The mill demands details.",
]
## Jeremy 2026-10-10 (hearsay flesh-out): beastloss Squabble lines —
## {faction} = the herd's faction display name, {beast} = the animal type.
const BEASTLOSS_STARVED_LINES: Array[String] = [
	"The {faction} herd lost another {beast} to an empty feed trough. Somebody's getting mocked at the tavern tonight. 🐄",
	"Breaking: {beast} starves while the {faction} granaries sit empty. The tavern has already picked who's to blame. 🐄",
	"RIP to the {faction} {beast}. Died of hunger surrounded by farmers. You hate to see it. 🐄",
	"The {faction} pastures are looking thin — another {beast} dropped. Feed your animals, people! 🐄",
	"Tavern poll: worst herdsman in the {faction} lands? The late {beast} casts the deciding vote. 🐄",
]
const BEASTLOSS_SLAIN_LINES: Array[String] = [
	"Wolves took a {beast} in the wilds last night. The shepherds are furious and the pups are fat. 🐺",
	"A {beast} went into the treeline and didn't come back. Pour one out. Then grab a spear. 🐺",
	"The wolves are eating better than half the realm — another {beast} gone. 🐺",
	"Heard the howling last night? That was somebody's {beast}. Sleep tight. 🐺",
	"Wolf count: up. {beast} count: down. The wilds remain undefeated. 🐺",
]
## Jeremy 2026-10-10 (hearsay flesh-out): bumper/lean harvest Squabble
## lines — {faction} = the harvest's faction display name,
## {food} = the haul in food units (rounded at post time).
const HARVEST_BUMPER_LINES: Array[String] = [
	"BUMPER CROP in the {faction} lands — {food} food off one harvest! The farmers are insufferable and the tavern is pouring doubles. 🌾",
	"The {faction} fields just dropped {food} food in a single harvest. Somebody's soil has been showing off. 🌾",
	"{food} food. ONE harvest. The {faction} farmers won't stop smiling and honestly neither would I. 🌾",
	"Word is the {faction} granaries are bursting — {food} food off the last cut. The bakers are already drunk. 🌾",
	"The {faction} turnips came in HUGE this season — {food} food and the farmer won't shut up about it. Fair play. 🌾",
]
const HARVEST_LEAN_LINES: Array[String] = [
	"Oof. The {faction} harvest came in at {food} food. The tavern is taking bets on whose field that was. 🌾",
	"{food} food off a whole harvest in the {faction} lands? The scarecrow's doing a better job than the farmer. 🌾",
	"Somewhere in the {faction} fields a farmer is staring at {food} food and questioning every life choice. 🌾",
	"The {faction} granary echo is audible from the tavern — {food} food. That's a snack, not a harvest. 🌾",
]
## Jeremy 2026-10-10 (hearsay flesh-out): fire-brigade rollout Squabble
## lines — {faction} = the brigade's faction display name. The station's
## engine rolling out with crew aboard is the realm's favorite spectacle:
## somebody else's emergency, with bells.
const BRIGADE_LINES: Array[String] = [
	"Bells ringing — the {faction} fire brigade just rolled out of the station, crew aboard! Somebody's barn is having a very bad day. 🔥",
	"There goes the {faction} fire wagon, crew hanging off the sides like heroes. Hope they remembered the water. 🔥",
	"The {faction} brigade rolled out so fast the station doors are still swinging. Nothing draws a crowd like somebody else's emergency. 🔥",
	"Heard the bells? That's the {faction} engine rolling — full crew, full speed, straight for the smoke. The tavern is already taking bets on the barn. 🔥",
	"The {faction} firefighters just mounted up and rolled. Say what you want about taxes — when YOUR roof's on fire, those are your favorite people alive. 🔥",
]
## Monthly disaster forecast (HTML generateDisasterCalendar /
## processCalendarDisasters systemMsg parity): the realm gossips when the
## seers post the calendar, and again when a forecast event fires.
const FORECAST_LINES: Array[String] = [
	"The seers posted this month's disaster forecast: {e}. Mark your calendars. 📅",
	"📅 Disaster forecast is up — {e}. Sleep tight, everyone.",
	"New month, new disasters: {e}. The seers love their drama. 📅",
	"📅 Forecast says {e}. I'm stocking the cellar.",
]
const FORECAST_FIRED_LINES: Array[String] = [
	"📅 FORECAST EVENT: {l}! It was on the calendar and everything.",
	"Called it! The forecast said {l} and here it is. 📅",
	"The seers were RIGHT about {l}. Someone buy those weirdos a drink.",
]
const PEACE_LINES: Array[String] = [
	"PEACE with the {f}! Put away the pointy sticks, break out the pies. 🕊",
	"The war with the {f} is OVER. Widows on both sides weep with relief.",
	"Peace with the {f}! I already forgot what we were fighting about.",
	"The {f} war is done. Time to pretend we always liked them. 🕊",
	"PEACE! The {f} and us, friends at last. Someone tell the blacksmiths — they're going to cry.",
	"War with the {f} over. My axe is going back on the wall. For now.",
]
## Jeremy 2026-10-06 (hearsay gap coverage): the white flag finally gets
## its own gossip. Surrender offers flew with zero grapevine presence —
## no rumor, no post — while acceptances only surfaced via the generic
## peace_made rumor. The realm now talks about both.
const SURRENDER_OFFER_LINES: Array[String] = [
	"WHITE FLAG! The {l} just offered to surrender to the {w}. Someone fetch the good surrender parchment. 🏳",
	"The {l} want OUT — they offered surrender to the {w}. The war might actually end before my lunch does.",
	"Surrender offer on the table: the {l} bend the knee to the {w}. Bold strategy, let's see if it pays off.",
	"Word is the {l} raised the white flag to the {w}. Their soldiers are already practicing their 'we lost' faces. 🏳",
	"The {l} offered surrender — they yield to the {w}! Losers pay reparations, winners get bragging rights forever.",
]
const SURRENDER_ACCEPT_LINES: Array[String] = [
	"IT'S OVER! The {w} ACCEPTED the {l} surrender. War's done, send the bards. 🏳",
	"The {l} laid down their arms — the {w} accepted. Reparations paid, grudges... pending.",
	"Surrender accepted! The {l} yield to the {w}. Somewhere a tax collector just smiled.",
	"The {w} accepted the {l} surrender. The white flag worked! Somewhere a general is furious. 🏳",
]
## Jeremy 2026-10-06 (hearsay gap coverage): towns were founded in total
## silence — no rumor, no Squabble post. The realm hears about new towns.
const TOWN_FOUNDED_LINES: Array[String] = [
	"New town on the map: {t}, founded by the {f}! Fresh plots, fresh gossip, fresh taxes. 🏘",
	"The {f} founded {t}! Housewarming gifts accepted — preferably gold, but pie works.",
	"{t} is officially a town now, courtesy of the {f}. The tavern opens Thursday. 🏘",
	"Breaking: {t} exists now. The {f} built it. Property values already suspicious.",
]
## Jeremy 2026-10-06 (hearsay gap coverage): proposal DECISIONS were deaf
## to the grapevine — only the proposal itself gossiped. A denied war
## proposal is tavern comedy: the drums beat, the council blinked.
const WAR_CHICKEN_LINES: Array[String] = [
	"The {f} talked big about war and then... didn't. The war drums are now decorative. 🐔",
	"Remember when the {f} were totally going to invade someone? Yeah, their council chickened out. Awkward.",
	"The {f} war council met, puffed their chests, and chickened out. The realm salutes their cowardice. 🐔",
	"War with the {f}? Cancelled — their own rulers vetoed it. Somewhere a blacksmith cries into his anvil.",
]
## Jeremy 2026-10-09 (hearsay flesh-out): peace feelers were the last
## deaf proposal — a losing faction's council debated begging for peace
## and said NO. The realm hears about the begging that wasn't.
const PEACE_FEELER_LINES: Array[String] = [
	"The {f} actually talked about BEGGING the {t} for peace. Their own council said no. The war grinds on. 🕊➡⚔",
	"Peace feeler DENIED: the {f} debated surrendering to the {t} and chickened out of chickening out. Bold.",
	"Word is the {f} were *this* close to begging the {t} for mercy. Their council vetoed it — pride before the fall.",
	"The {f} considered suing the {t} for peace. Considered! Then pride won. Someone tell the widows.",
]
## Jeremy 2026-10-06 (hearsay gap coverage): fires raged in the grapevine
## but died in silence — no burnout follow-up. The realm hears when the
## flames go out, and when the floodwaters recede.
const FIRE_OUT_LINES: Array[String] = [
	"The wildfire's OUT! Rain, buckets, or sheer spite — whatever worked, thank you. 🔥➡💧",
	"Fire's out, folks. The forest is singed, the firefighters are heroes, and my roof is soaked.",
	"They finally killed the wildfire — it's OUT. The smoke's clearing and the beasts are coming home. 🔥",
	"Wildfire: extinguished. Somewhere a firefighter is sleeping for a week. 💧",
]
const FLOOD_OUT_LINES: Array[String] = [
	"The floodwaters receded! Mop up, dry out, and pretend the basement was always that color. 🌊",
	"Flood's over — the waters went back where they came from. My boots may never recover. 🌊",
]
const ALLIANCE_LINES: Array[String] = [
	"ALLIANCE with the {f}! Their spears beside ours. History turns. 🤝",
	"The {f} are our allies now. Try not to stare at their weird customs. 🤝",
	"Allied with the {f}! Combined armies, combined feasts, combined headaches.",
	"🤝 {f} alliance sealed. The map just got a lot more interesting.",
]
const TREATY_BREAK_LINES: Array[String] = [
	"The {f} broke their word! Oathbreakers, the lot of them. Remember this. 💔",
	"{f} tore up the treaty. Their word is worth less than a goblin's promise. 💔",
	"So much for the {f} alliance. Oathbreakers! Tell the bards — this needs a sad song.",
	"The {f} broke faith. Never trust a {f} negotiator again. 💔",
]
const TRIBUTE_LINES: Array[String] = [
	"Tribute paid to the {f} — {a} gold for their patience. For now. 💰",
	"Sent {a} gold to the {f}. Call it diplomacy. I call it extortion with extra steps. 💰",
	"The {f} got their tribute: {a} gold. We're buying time, not friendship.",
	"{a} gold to the {f}. The treasury weeps. The kingdom survives. For now.",
]
const DEATH_LINES: Array[String] = [
	"We lost {n}, our {r}. The bells toll. 🕯",
	"{n} ({r}) is gone. Raise a mug tonight. 🍻",
	"Rest easy, {n}. The realm's {r} has fallen. 🕯",
	"{n} is gone. Pour one out for our {r}. 🍻",
	"The bells ring for {n}, {r} of the realm. Gone too soon.",
]
## Jeremy 2026-10-08 (hearsay flesh-out): who-killed-whom rumor lines.
## {v} = victim name, {vf} = victim faction, {kf} = killer faction.
## Wartime slayings read as battle news; peacetime ones read as scandal
## (HTML assassin-headline parity: major, mood-shaking, urgent).
const KILL_LINES: Array[String] = [
	"{v} of the {vf} was slain by {kf} blades. The taverns want answers.",
	"Word is {kf} steel killed {v} of the {vf}. Say it louder in the back.",
	"{v} ({vf}) is dead — {kf} did it. That's the rumor. That's the whole rumor.",
	"The {kf} slew {v} of the {vf}. Grief in one hall, questions in every other.",
	"Heard it straight: {kf} blades, {v}'s blood. The {vf} will not forget.",
	"{v} of the {vf} fell to {kf} hands. War or murder? The mill is deciding.",
]
## Jeremy 2026-10-04: thicc moose mooning reactions (HTML moonGrossOut /
## scareNearby port). Faction-specific: ogres laugh, elves horrified,
## gnomes hysterical, humans embarrassed, undead unimpressed.
const MOOSE_REACT_OGRES: Array[String] = [
	"HA! Moose got BALLS!",
	"Me like moose style!",
	"Do it again! Do it again!",
	"Best thing me see all week!",
	"Moose is my hero now.",
	"HAHA! Show them, moose!",
	"That take guts. And butt.",
	"Me cheering! WOO!",
	"Moose for chieftain!",
	"Now THAT'S how you make entrance!",
	"Moose butt big. Me impressed.",
]
const MOOSE_REACT_ELVES: Array[String] = [
	"By the ancient groves... my eyes!",
	"This is an abomination of nature!",
	"Someone shield the children!",
	"I shall never unsee this horror.",
	"The forest weeps tonight.",
	"How DARE it expose itself?!",
	"My delicate sensibilities are RUINED.",
	"Banish this indecent beast!",
	"Nature has gone too far this time.",
	"Avert thy gaze, kin!",
	"This is not the wild I signed up for.",
]
const MOOSE_REACT_GNOMES: Array[String] = [
	"BAHAHA! Did you SEE that?!",
	"Someone write this down! Write it down!",
	"That's going in the history books!",
	"I gotta try that at the next festival!",
	"Ten out of ten! Encore!",
	"My sides hurt! My SIDES!",
	"Best prank EVER!",
	"I'm taking notes for my act!",
	"The AUDACITY! I love it!",
	"Legend! Absolute legend!",
	"What the absolute fuck is that arse?!",
]
const MOOSE_REACT_HUMANS: Array[String] = [
	"Oh god, don't look, don't look...",
	"This is so embarrassing...",
	"Why here? Why now?",
	"I... I need to sit down.",
	"My poor innocent eyes...",
	"Can we please pretend this didn't happen?",
	"Mother would faint...",
	"I feel violated just watching.",
	"Someone make it stop!",
	"I'm scarred. Scarred for life.",
	"Fetch the militia — and bleach!",
]
const MOOSE_REACT_UNDEAD: Array[String] = [
	"...",
	"I've seen worse. Much worse.",
	"Flesh. How... temporary.",
	"Wake me when it's over.",
	"Is that supposed to frighten us?",
	"We have no eyes to offend. Lucky us.",
	"How... biological.",
	"The living are so strange.",
	"Noted. Moving on.",
	"Death was less disturbing than this.",
]
## Generic mooning lines (HTML moonGrossOut port) for any faction.
const MOOSE_REACT_GENERIC: Array[String] = [
	"IT MOONED US!",
	"MY INNOCENCE!",
	"THAT ASS THO-",
	"BURN IT WITH FIRE!",
	"WHY IS IT WIGGLING?!",
	"I QUIT THIS TOWN!",
	"WHAT THE FUCK!?",
	"MY EYES!!",
	"Why is it showing us its butt?!",
	"Someone call animal control!!",
]
## Jeremy 2026-10-04: anti-racist condemnation lines. When the REAL n-word
## is used, every faction condemns racism explicitly — each in their own
## voice. Even factions at war with each other unite on this. The game
## takes a clear stance: GAH FUCK RACISTS. {ruler} = offending faction.
const SLUR_CONDEMN_OGRES: Array[String] = [
	"That racist bastard! We smash skulls, not dignity — FUCK RACISTS!",
	"The {ruler} ruler speaks filth! Even WE don't stand for that shit!",
	"Racist scum! Come say that to MY face, coward!",
	"We ogres fight fair. Racism ain't fighting — it's just being trash.",
	"Did the {ruler} dog just say THAT? Someone hold my club.",
	"Filthy racist! My grandmother would smash you for that word!",
	"We don't care what color your skin is — we smash everyone equal!",
	"That word is poison. The {ruler} ruler is poison. Fuck racists!",
	"Ogres respect strength, not bigotry. That racist is WEAK.",
	"I've eaten goblins with more honor than that {ruler} racist.",
	"Racism? In MY realm? Not while I breathe!",
	"The {ruler} ruler just declared war on decency. We answer!",
	"The {ruler} dog used THAT word. You know the one. I won't repeat it.",
	"{offender} said something so racist I won't even quote it. That's how bad it was.",
]
const SLUR_CONDEMN_ELVES: Array[String] = [
	"That word is poison, and the {ruler} ruler has drunk deeply of it. We condemn them utterly.",
	"A thousand years of civilization, and the {ruler} still speak like beasts. Shame upon them.",
	"Racism is the refuge of small minds and smaller souls. The {ruler} ruler has neither.",
	"We have seen empires fall for lesser bigotries. Let the {ruler} fall too.",
	"The {ruler} ruler's tongue is a weapon against the innocent. We will not suffer it.",
	"Even the ancient trees recoil from such hatred. Fuck racists, in every tongue.",
	"Dignity is owed to all thinking beings. The {ruler} ruler understands nothing.",
	"That slur stains the very air. The {ruler} court should be ashamed.",
	"We elves remember every cruelty. This one we will not forget.",
	"Bigotry is a rot, and the {ruler} ruler spreads it. Cut it out.",
	"No crown excuses racism. The {ruler} ruler is no ruler of ours.",
	"Let history record: when the {ruler} spoke hatred, the elves stood against them.",
	"The {ruler} ruler uttered the slur — you know the one. I shall not repeat it.",
	"{offender} dropped the hard-r in open court. We will not dignify it by quoting.",
]
const SLUR_CONDEMN_GNOMES: Array[String] = [
	"Even WE know that's fucked up! And we joke about EVERYTHING!",
	"The {ruler} ruler said the quiet part out loud. Loud. Racist loud.",
	"We prank, we roast, we mock — but racism? That's not funny, that's just evil.",
	"Fuck racists! The {ruler} ruler can eat our entire mushroom harvest!",
	"You know it's bad when the GNOMES stop laughing. That was BAD.",
	"The {ruler} ruler just speedran becoming the villain. Impressive. Disgusting.",
	"Racism isn't a joke, it's a disease. Quarantine the {ruler}!",
	"We'd rather kiss a troll than stand with a racist. Fuck the {ruler}!",
	"That word has no punchline. The {ruler} ruler has no honor.",
	"Bigots get no pranks from us — just pitchforks. Tiny, sharp pitchforks.",
	"The {ruler} ruler's racism is the only thing smaller than our stature.",
	"Newsflash, {ruler}: hating people for their skin is clown behavior. And WE'RE the clowns.",
	"The {ruler} ruler said the quiet slur out loud. I'm not repeating it. Nobody should.",
	"{offender} went full racist in court. Quoting them would make ME the villain. Pass.",
]
const SLUR_CONDEMN_HUMANS: Array[String] = [
	"Not in our town! The {ruler} ruler's racism has no home here!",
	"We may be plain folk, but we know right from wrong. That was WRONG.",
	"Fuck racists! The {ruler} ruler just made an enemy of every decent human!",
	"My gran always said: judge folks by their deeds. The {ruler}'s deeds are filth.",
	"That word doesn't belong in our realm. The {ruler} ruler doesn't either.",
	"We work beside all kinds in the fields. Racism is a weed — pull it out.",
	"The {ruler} ruler shamed themselves today. We won't forget it.",
	"Decent humans don't talk like that. The {ruler} ruler ain't decent.",
	"Racism is for cowards. The {ruler} ruler is a coward. Fuck racists!",
	"Our town stands with the victims, not the {ruler} bigot!",
	"That slur is a disgrace to every human with a conscience.",
	"The {ruler} ruler wants hate? They'll get war. From ALL of us.",
	"The {ruler} ruler said THAT word in front of everyone. I won't repeat it. Ever.",
	"{offender} is the racist. That's the story. The word itself stays buried.",
]
const SLUR_CONDEMN_UNDEAD: Array[String] = [
	"In death, all are equal. The {ruler} ruler's bigotry is... inefficient. And contemptible.",
	"We have watched a thousand racists rot. The {ruler} ruler will rot too.",
	"Hatred of the living for their skin? Even WE find that small-minded.",
	"The dead do not discriminate. The {ruler} ruler should learn from corpses.",
	"Bigotry is a mortal disease. The {ruler} ruler is terminal.",
	"We remember when the {ruler}'s ancestors were dust. Dust does not judge dust.",
	"Fuck racists. Even in death, we condemn them.",
	"The {ruler} ruler's hatred will outlive nothing. Not even themselves.",
	"Eternity teaches patience. It also teaches contempt for bigots.",
	"Skin rots. Bones bleach. Hatred is the only thing the {ruler} ruler keeps.",
	"The grave takes all kinds. The {ruler} ruler's racism takes only their honor.",
	"We have no blood left to boil, but the {ruler} ruler tests even that.",
	"The {ruler} ruler spoke the unspeakable. We won't repeat it. The condemnation stands.",
	"{offender} uttered a slur so vile that even the dead flinch. We won't repeat it here.",
]
## Squabble posts condemning the racist incident — the whole platform unites.
const SLUR_CONDEMN_POSTS: Array[String] = [
	"Fuck racists. The {ruler} ruler just showed their true colors and they're UGLY. #NoRacists",
	"I don't care what faction you're from — racism is racism, and racists are done. The {ruler} ruler is cancelled. FOREVER.",
	"The {ruler} ruler said THAT word and every faction — EVERY faction — said nah. United against bigotry.",
	"Racism has no faction and no excuse. The {ruler} ruler stands alone in their filth — a racist with no friends.",
	"My ogre neighbor and my elf neighbor agree on ONE thing today: fuck the {ruler} racist.",
	"The {ruler} ruler really thought they could drop a racist slur and walk away?? Not in this realm.",
	"Teaching my kids today: that word is evil, racists are cowards, and the {ruler} ruler is both.",
	"War with the {ruler} isn't about territory anymore. It's about decency. #FuckRacists",
	"Even the undead are disgusted by that racist filth and they literally have no feelings. Let that sink in.",
	"The gnomes stopped joking. THE GNOMES. That's how racist the {ruler} ruler's mouth is.",
	"Racists get no peace, no trade, no mercy. The {ruler} ruler chose this.",
	"Today the realm learned the {ruler} ruler's true face: racist. We reject it. Completely.",
	"Bigotry is weakness. The {ruler} ruler is the weakest ruler in history.",
	"Ogres, elves, gnomes, humans, undead — all saying the same thing: FUCK RACISTS.",
	"The {ruler} ruler's racism united five warring factions. Congratulations on the achievement, bigot.",
	"No crown, no army, no gold excuses racism. The {ruler} ruler is a racist and they're done.",
	"He said the word. THE word. I'm not typing it. {offender} is racist and that's all you need. #FuckRacists",
	"Not repeating what racist {offender} said, but WOW. Banned from decency forever.",
]
## Replies amplifying the anti-racist message.
const SLUR_CONDEMN_REPLIES: Array[String] = [
	"SAY IT LOUDER",
	"Fuck racists, all my homies hate racists",
	"This is the one thing we all agree on",
	"The {ruler} ruler is finished. Good riddance.",
	"Preach! Racism has no place here!",
	"Even my war-hungry uncle agrees and he agrees with NOTHING",
	"Resquabbling this a thousand times",
	"The realm stands united. Against the {ruler}.",
	"This post. This is the one.",
	"Bigots get the wall. Metaphorically. Mostly.",
	"My faction hates your faction but we BOTH hate racists more",
	"The {ruler} ruler picked the wrong word on the wrong day",
]
## Squabble posts about the mooning (HTML sqbGenDeeds parity).
const MOOSE_SQB_LINES: Array[String] = [
	"The thicc moose just mooned our town hall! I saw EVERYTHING. 🍑",
	"BREAKING: Local moose exposes butt to entire village. More at 11.",
	"I was just trying to buy bread and now I'm traumatized. Thanks, moose.",
	"That moose has NO shame and honestly? Respect. 🍑✨",
	"My children saw the moose butt. How do I explain this?",
	"The moose mooned THREE halls today. THREE. It's on a rampage.",
	"New fear unlocked: moose butt. 😱",
	"To the moose that mooned us: we will never forget. Or forgive. Or unsee.",
	"The council is holding an emergency meeting about the moose situation.",
	"I laughed. I'm not proud, but I laughed. 🍑",
	"That moose wiggled its butt AT me. Personally. I feel violated.",
	"Moose butt so thicc it has its own gravitational pull.",
	"The tavern will be talking about this for YEARS.",
	"I came for the market day, I stayed for the moose mooning.",
	"Someone's gotta stop that moose. But also... encore?",
	"🌙 MOONED! The thicc moose strikes again!",
]
const MOOSE_SQB_REPLIES: Array[String] = [
	"I was there! The horror! THE HORROR!",
	"Pics or it didn't happen. (Please don't.)",
	"This is why we can't have nice things.",
	"The moose did WHAT now?",
	"I'm telling the grandkids about this one.",
	"That's the third time this month!",
	"We need moose-proof pants for our halls.",
	"I laughed so hard I cried. No regrets.",
	"My therapist will hear about this.",
	"The audacity of this moose knows no bounds.",
	"New town motto: 'Mooned but unbroken.'",
	"I paid 5 gold for front-row seats. Worth it.",
]
## Jeremy 2026-10-04: disaster spawn reactions (HTML scareNearby port).
## kind -> reaction lines for nearby NPC speech bubbles.
const DISASTER_REACT_LINES := {
	"giant_ass": [
		"WHAT IS THAT?!",
		"Run! RUN!",
		"It's HUGE!",
		"Someone call the army!",
		"My god, the size of it!",
	],
	"giant_lizard": [
		"A giant lizard! Everyone inside!",
		"Did it just... talk?",
		"Bar the doors!",
		"Not the livestock! Not again!",
	],
	"rogue_wizard": [
		"A rogue wizard! Take cover!",
		"His eyes are glowing!",
		"Someone fetch the archers!",
		"Magic! DARK magic!",
	],
	"bandit_raid": [
		"Bandits! BANDITS!",
		"Hide the gold!",
		"To arms! To arms!",
		"They're raiding the storehouse!",
	],
	"cardboard_cat": [
		"...is that a cat? In a box?",
		"Why is it just... sitting there?",
		"It's watching us. I can feel it.",
		"Menacing. Deeply menacing.",
	],
	"count_bastard": [
		"Oh no. HIM.",
		"Everyone act natural. Don't make eye contact.",
		"He's going to insult us all, isn't he.",
		"My self-esteem wasn't ready.",
	],
	# Jeremy 2026-10-04: THE NASTY MONASTERY — a priest moved in. Seems fine.
	"nasty_priest": [
		"A new priest? How nice.",
		"Finally, some spiritual guidance.",
		"He seems... normal. Probably.",
		"What could possibly go wrong?",
	],
}
const DISASTER_REACT_GENERIC: Array[String] = [
	"What's happening?!",
	"Everyone stay calm!",
	"Get inside!",
	"Sound the alarm!",
]
const DEED_PRAISE: Array[String] = [
	"Word is {k} {t} — say what you want, the realm notices. 👑",
	"Credit where it's due: {k} {t}. The crown's doing alright. ✨",
]
const DEED_GRUMBLE: Array[String] = [
	"{k} {t}?? Bold. We'll see how THAT ages. 😒",
	"So {k} {t}. Great. Fantastic. My taxes at work, everyone. 🙄",
]
const NPC_LIFE_LINES: Array[String] = [
	"Day {d} of being a {j} in {t}. The pay is bad, the gossip is excellent. Would not trade it. (Would trade it.)",
	"Just a {f} trying to get by in {t}. The crown does politics; I do laundry. Guess whose job matters. 🧺",
]
## Jeremy 2026-10-06 (lane 6): hidden-cache rumors — tavern talk about
## stashes, hoards, and lost war chests. Hot ones spawn an advisor
## proposal to send scouts after them (see _quest_tick).
const CACHE_LINES: Array[String] = [
	"They say a bandit cache is buried out in the wilds. Gold, gear, the works.",
	"Old-timer at the tavern swears there's a hidden cache in the hills. Marked with a red stone.",
	"Word is a supply cache from the last war never got picked up. Still out there, waiting.",
	"A smuggler's stash, that's what they're whispering about. Chests of it, apparently.",
]
## Jeremy 2026-10-08 (hearsay flesh-out): invented tavern lies — the
## ONLY rumors seeded untrue. A citizen who dislikes someone sometimes
## makes up a smear about them (truth "false", source recorded), and the
## crown's investigators can debunk it. Fantasy tavern talk only — an
## IRL hate slur can never ride this pipeline (guarded at seed).
const FALSE_SMEAR_LINES: Array[String] = [
	"They say {t} cheats at dice. Loaded bones, marked cards, the works.",
	"Word is {t} stole from the guild till. The coins never added up, did they?",
	"Heard {t} waters down the tavern ale. Wouldn't put it past them.",
	"They say {t} owes the moneylenders big. Big enough to skip town over.",
	"Word is {t} got caught stealing pies. Again. Third time, apparently.",
	"Heard {t} faked a limp to dodge militia duty. Coward's move.",
	"They say {t} sells 'genuine' dragon scales that are just painted rocks.",
	"Word is {t} bribed the pie judge at the last festival. The crust was rigged.",
	"Heard {t} talks to their turnips. The turnips talk back, allegedly.",
	"They say {t} snores so loud the neighbors petitioned the crown about it.",
]
## Jeremy 2026-10-06 (lane 6): investigation answers — what NPCs say when
## the crown asks about a rumor. Confirms/denies follow what the NPC
## actually knows and whether the claim is true; shrugs are honest
## ignorance. Slur answers are ALWAYS condemnation (hard line: the
## incident really happened, nobody finds it funny, nobody softens it).
const INVEST_CONFIRM: Array[String] = [
	"It's true, sire — I heard it myself. {t}",
	"Aye, that's no tavern tale. {t}",
	"True as I'm standing here. {t}",
	"I'd stake my boots on it: {t}",
]
const INVEST_DENY: Array[String] = [
	"Nah, sire — that's tavern nonsense. {t} Never happened.",
	"I asked around. Nobody credible believes that one. {t}",
	"Someone's spinning tales, sire. {t}",
	"False as a wooden coin. I looked into it. {t}",
]
const INVEST_SHRUG: Array[String] = [
	"Haven't heard that one, sire. I'll keep an ear out.",
	"First I'm hearing of it. Can't say either way.",
	"Not my corner of the tavern, sire. Sorry.",
]
const INVEST_HEARD_UNSURE: Array[String] = [
	"Heard it too, sire, but I couldn't swear to it.",
	"It's going around, aye — whether it's true, who can say.",
	"Everyone's repeating it. Nobody's proving it.",
]
const INVEST_SLUR_CONDEMN: Array[String] = [
	"It's true and it's vile, sire. I won't repeat the word. It happened.",
	"Aye, it happened — and the whole tavern's furious about it. As they should be.",
	"True, sire. Disgusting, but true. Nobody's laughing about that one.",
	"I was there when the word spread. Nobody found it funny. Nobody.",
]
## Jeremy 2026-10-08 (hearsay flesh-out): crime-rumor investigation —
## witnesses name the thief (HTML "THIEF! I SAW THE WHOLE THING!" parity).
## Unseen thieves get their own pool: the crime is confirmed, the crook
## is not.
const INVEST_CRIME_CONFIRM: Array[String] = [
	"THIEF! I SAW THE WHOLE THING! {t}",
	"Aye, it happened — right in the street. {t}",
	"True, sire. The whole market saw it. {t}",
	"Saw it with my own eyes, sire. {t}",
]
const INVEST_CRIME_UNSEEN: Array[String] = [
	"Aye, it happened — but nobody saw who did it. {t}",
	"True, sire, but the thief vanished. No face, no name. {t}",
	"Happened right under our noses. Nobody caught a glimpse. {t}",
]
## Jeremy 2026-10-06: hearsay overhaul — what an NPC FEELS when a rumor
## reaches them, by rumor kind. Maps to SimEmotion event names; kinds
## absent here get no emotion nudge. This is how NPCs "understand" news.
const KIND_EMOTION := {
	"war": "disaster", "battle": "disaster", "disaster": "disaster",
	"forecast": "disaster", "monster": "monster",
	"festival": "helped", "peace": "helped", "news": "helped",
	"alliance": "praised", "deed": "praised", "building": "praised",
	"death": "friend_died", "crime": "insulted", "slur": "insulted",
	# Jeremy 2026-10-08 (hearsay flesh-out): slain-by-a-known-faction
	# news lands as dread — the realm just learned who holds the blade.
	"kill": "disaster",
	"moose_moon": "helped", "nasty_priest": "grossed_out",
	"treaty": "insulted", "tribute": "mocked",
	"assface": "helped",
	# Jeremy 2026-10-08 (hearsay flesh-out): caravan talk is happy
	# news — market-day buzz, not scandal.
	"trade": "helped",
	# Jeremy 2026-10-09 (hearsay flesh-out): a coronation is happy news —
	# the realm celebrates (or sneers, in character, via the matrix).
	"founding": "helped",
	"cache": "helped", "scout": "helped",
	# Jeremy 2026-10-09 (hearsay flesh-out): a wall raising is civic
	# news — the realm notes it, in character, via the matrix.
	"wall": "helped",
	# Jeremy 2026-10-09 (hearsay flesh-out): a lightning strike on a
	# dark crystal lands as dread — the sky just smote a god's seat.
	"crystal": "disaster",
	# Jeremy 2026-10-10 (hearsay flesh-out): trespass gossip is
	# tavern mockery — the mill laughs AT the caught snoop.
	"trespass": "mocked",
	# Jeremy 2026-10-10 (hearsay flesh-out): beastloss gossip is tavern
	# mockery too — the mill laughs at whoever starved the herd.
	"beastloss": "mocked",
	# Jeremy 2026-10-10 (hearsay flesh-out): weather arrivals land as
	# unease by default — a storm overhead puts the realm on edge.
	"weather": "dismayed",
	# Jeremy 2026-10-10 (hearsay flesh-out): bumper harvests land as
	# happy news — the realm eats, and pride does the talking.
	"harvest": "helped",
	# Jeremy 2026-10-10 (hearsay flesh-out): the brigade rolling out lands
	# as hopeful news — the cavalry's coming, somebody's getting saved.
	"brigade": "helped",
	# Jeremy 2026-10-11 (hearsay flesh-out): dealership talk is happy
	# commerce news — new wheels in town, somebody's showing off.
	"vehicle": "helped",
}
## How strongly a heard rumor sticks in memory, by kind (0..1.2).
const KIND_MEM_STRENGTH := {
	"war": 1.0, "battle": 0.9, "slur": 1.0, "disaster": 0.9,
	"death": 0.8, "nasty_priest": 0.8, "crime": 0.7, "treaty": 0.7,
	# Jeremy 2026-10-08 (hearsay flesh-out): a named slaying sticks
	# harder than a plain obituary — the realm remembers WHO did it.
	"kill": 0.85,
	"peace": 0.6, "alliance": 0.6, "news": 0.5, "forecast": 0.5,
	"deed": 0.5, "building": 0.4, "festival": 0.4, "moose_moon": 0.4,
	"life": 0.25, "misc": 0.25, "tribute": 0.3, "assface": 0.8,
	"cache": 0.5, "scout": 0.5,
	# Jeremy 2026-10-08 (hearsay flesh-out): tavern talk about a named
	# citizen sticks harder than ambient chatter — it's about SOMEONE.
	"gossip": 0.45,
	# Jeremy 2026-10-08 (hearsay flesh-out): caravan talk sticks like a
	# festival — happy news the whole town remembers.
	"trade": 0.5,
	# Jeremy 2026-10-09 (hearsay flesh-out): a coronation sticks like a
	# festival — happy news the whole realm remembers.
	"founding": 0.5,
	# Jeremy 2026-10-09 (hearsay flesh-out): wall talk sticks like
	# tavern talk about a named citizen — civic news with a place.
	"wall": 0.45,
	# Jeremy 2026-10-09 (hearsay flesh-out): an omen sticks — the realm
	# remembers the day the sky struck the crystal.
	"crystal": 0.7,
	# Jeremy 2026-10-10 (hearsay flesh-out): trespass talk sticks like
	# named-citizen gossip with teeth — it's about specific people and
	# everybody knows whose house it was.
	"trespass": 0.55,
	# Jeremy 2026-10-10 (hearsay flesh-out): beastloss talk sticks like
	# named-citizen gossip — it's about somebody's herd, and the tavern
	# remembers whose animals keep dropping.
	"beastloss": 0.45,
	# Jeremy 2026-10-10 (hearsay flesh-out): weather talk sticks like
	# season talk — the realm remembers the storm that broke at dawn.
	"weather": 0.4,
	# Jeremy 2026-10-10 (hearsay flesh-out): bumper-harvest talk sticks
	# like festival news — happy news the whole town remembers, and the
	# lean ones stick as the joke everyone repeats.
	"harvest": 0.4,
	# Jeremy 2026-10-10 (hearsay flesh-out): brigade talk sticks like
	# weather talk — the realm remembers the day the engine rolled.
	"brigade": 0.4,
	# Jeremy 2026-10-11 (hearsay flesh-out): show-off talk sticks like
	# tavern talk about a named citizen — it's about SOMEONE's wheels.
	"vehicle": 0.45,
}
## Jeremy 2026-10-06: telephone-game distortion. Each hop of a rumor has
## a chance to mutate the text a little — gossip degrades with distance.
## Capped at MAX_DISTORTIONS per rumor; the original is kept in text_orig.
const MAX_DISTORTIONS := 3
const DISTORT_SUFFIX: Array[String] = [
	" — allegedly.", " — or so I heard.", " — you didn't hear it from me.",
	" — take it with a grain of salt.", " — that's what they're saying, anyway.",
	" — well, that's the tavern version.",
]
const DISTORT_SWAPS: Array = [
	["rampages", "rampages MIGHTILY"],
	["big", "HUGE"], ["scary", "TERRIFYING"], ["angry", "FURIOUS"],
	["said", "DECLARED"], ["broke", "SHATTERED"],
	["a ", "a whole "], ["the ", "the infamous "],
]

var state: Dictionary
var _gs: GameState
var phone = null  # SimPhone (duck-typed)
## Jeremy 2026-10-06: track recently used post lines to avoid duplicates
## in the Squabble feed (same line posted twice looks broken).
var _recent_lines: Array[String] = []
## Jeremy 2026-10-09 (hearsay flesh-out): stashed by _on_story when the
## Gazette's "NUCLEAR DETONATION" story publishes — the firing faction,
## reverse-mapped from the body. Read and cleared by _on_nuke_detonation
## (publish_or_emit runs before disaster_spawned.emit in detonate_nuke,
## so the story always lands first). Transient, same-tick only.
var _pending_nuke_launcher: String = ""
## Jeremy 2026-10-06: hearsay overhaul — shared helpers so NPC reception
## (memory + emotion on hearing a rumor) doesn't allocate per call.
var _mem: SimMemories
var _emo: SimEmotion
var _mood: SimMood


func _init(game_state: GameState, sim_phone = null) -> void:
	_gs = game_state
	phone = sim_phone
	state = {"rumors": [], "seq": 1, "last_press_day": 0,
		"npc_rep": {}, "pending_caches": [], "holders": {}}
	# Jeremy 2026-10-07 (hearsay flesh-out): the conquest reaction matrix
	# needs to know WHO lost a monastery/crystal — but the bus signals only
	# carry the new holder. Hearsay keeps its own god_id -> holder snapshot
	# ("holders"), built once the sims exist (see _snapshot_holders) and
	# updated on every capture. Never touches the sims' own files.
	_gs.bus.gazette_story.connect(_on_story)
	_gs.bus.day_changed.connect(_on_day)
	_gs.bus.war_declared.connect(_on_war_declared)
	_gs.bus.disaster_spawned.connect(_on_disaster)
	# Jeremy 2026-10-06 (hearsay flesh-out): wildfires never emitted
	# disaster_spawned — they only opened a DisasterLog record — so fires
	# raged with zero grapevine presence. The realm now gossips about them.
	_gs.bus.fire_started.connect(_on_fire_started)
	# Jeremy 2026-10-10 (hearsay flesh-out): the brigade rolling out is a
	# separate spectacle from the fire itself — bells, crew, a speeding
	# engine. The grapevine hears it as its own story beat.
	_gs.bus.fire_brigade_rolled.connect(_on_fire_brigade_rolled)
	# Jeremy 2026-10-11 (hearsay flesh-out): wagon-dealership sales.
	_gs.bus.vehicle_bought.connect(_on_vehicle_bought)
	_gs.bus.moose_mooned.connect(_on_moose_mooned)
	# Jeremy 2026-10-04: THE NASTY MONASTERY — Father Filthwick's outbursts
	# trigger NPC reactions, Squabble posts, and rumors.
	_gs.bus.priest_burst.connect(_on_priest_burst)
	# Jeremy 2026-10-04: the realm condemns racism explicitly — hearsay
	# seeds anti-racist rumors + Squabble posts from every faction.
	_gs.bus.slur_incident.connect(_on_slur_incident)
	_gs.bus.unit_died.connect(_on_unit_died)
	# Jeremy 2026-10-08 (hearsay flesh-out): the mill never learned WHO
	# did the killing — unit_killed carries the killer's faction, so
	# assassinations and battlefield slayings seed whodunit rumors.
	_gs.bus.unit_killed.connect(_on_unit_killed)
	_gs.bus.peace_made.connect(_on_peace)
	_gs.bus.alliance_signed.connect(_on_alliance)
	_gs.bus.treaty_broken.connect(_on_treaty_broken)
	_gs.bus.tribute_paid.connect(_on_tribute)
	# Jeremy 2026-10-04: the monthly disaster forecast posted/fired with
	# nobody listening — the realm gossips about it (HTML
	# generateDisasterCalendar / processCalendarDisasters systemMsg parity).
	_gs.bus.disaster_forecast_posted.connect(_on_forecast_posted)
	_gs.bus.disaster_forecast_fired.connect(_on_forecast_fired)
	# Jeremy 2026-10-06: hearsay overhaul — the grapevine was deaf to half
	# the sim. Deeds, construction, destruction, monastery captures, trade,
	# refused tribute, and relation shifts now all feed the rumor mill.
	_gs.bus.adventure_deed.connect(_on_deed)
	# Jeremy 2026-10-08 (hearsay flesh-out): quest outcomes were the last
	# deaf thread in the sim — the grapevine only ever heard the thin
	# adventure_deed toast ("Completed quest: X.") while the hero's name,
	# the giver, and the stakes never entered the rumor mill. The realm
	# now gossips about quest completions, failures, and the hero's own
	# fate (see _on_quest_completed and friends below), and acceptances —
	# the tavern buzzes when the hero takes up a quest, before the
	# outcome is known (see _on_quest_accepted).
	_gs.bus.adventure_quest_completed.connect(_on_quest_completed)
	_gs.bus.adventure_quest_failed.connect(_on_quest_failed)
	_gs.bus.adventure_quest_accepted.connect(_on_quest_accepted)
	_gs.bus.adventure_won.connect(_on_adventure_won)
	_gs.bus.adventure_lost.connect(_on_adventure_lost)
	_gs.bus.building_placed.connect(_on_building_placed)
	_gs.bus.building_destroyed.connect(_on_building_destroyed)
	_gs.bus.monastery_captured.connect(_on_monastery_captured)
	_gs.bus.crystal_captured.connect(_on_crystal_captured)
	# Jeremy 2026-10-09 (hearsay flesh-out): storm omens were a deaf
	# thread — lightning visibly hammers the rogue gods' dark crystals
	# every storm and the mill heard nothing. Strikes now seed rich
	# omen rumors (see _on_crystal_struck).
	_gs.bus.crystal_struck.connect(_on_crystal_struck)
	# Jeremy 2026-10-10 (hearsay flesh-out): trespass gossip — "seen
	# slipping into X's house". bus.interior_entered fires on every
	# building entry, so the handler gates hard (houses with a living
	# owner, non-resident entrant, night or a real witness); see
	# _on_interior_entered.
	_gs.bus.interior_entered.connect(_on_interior_entered)
	# Jeremy 2026-10-10 (hearsay flesh-out): beastloss gossip — "the
	# miller's cow starved". bus.animal_died fires on every animal death;
	# the handler gates hard (farm starvations = faction neglect worth
	# mocking, wild predator kills = shared wolf-drama; wild starvations
	# and unknown causes stay quiet); see _on_animal_died.
	_gs.bus.animal_died.connect(_on_animal_died)
	# Jeremy 2026-10-10 (hearsay flesh-out): bumper/lean harvest gossip —
	# "the {faction} fields just dropped {food} food". bus.farm_harvested
	# fires on every tile harvest; the handler gates hard (only bumper
	# hauls >= 85 and lean hauls < 55 are newsworthy — a normal 60-100
	# haul is farm business, not gossip); see _on_farm_harvested.
	_gs.bus.farm_harvested.connect(_on_farm_harvested)
	# Jeremy 2026-10-06: Command Posts — town captures seed rumors too.
	_gs.bus.command_post_captured.connect(_on_command_post_captured)
	_gs.bus.trade_signed.connect(_on_trade_signed)
	_gs.bus.tribute_refused.connect(_on_tribute_refused)
	_gs.bus.relation_changed.connect(_on_relation_changed)
	# Jeremy 2026-10-06 (lane 6): enemy buildups and war authorizations
	# are worth gossiping about — non-player strategic proposals seed
	# buildup rumors the player can then investigate or scout.
	_gs.bus.strategic_proposal.connect(_on_strategic_proposal)
	# Jeremy 2026-10-06 (hearsay gap coverage): surrender offers flew with
	# zero grapevine presence; town foundings, proposal decisions, and
	# fire/flood endings were all deaf threads. The mill hears them now.
	_gs.bus.surrender_offered.connect(_on_surrender_offered)
	_gs.bus.surrender_accepted.connect(_on_surrender_accepted)
	_gs.bus.town_founded.connect(_on_town_founded)
	# Jeremy 2026-10-09 (hearsay flesh-out): border-wall gossip — the
	# crown's Raise/Skip verdict on a named region's walls was a deaf
	# thread. The realm now gossips about raised walls AND refused ones.
	_gs.bus.wall_answer.connect(_on_wall_answer)
	_gs.bus.strategic_proposal_decided.connect(_on_strategic_proposal_decided)
	_gs.bus.fire_out.connect(_on_fire_out)
	_gs.bus.disaster_left.connect(_on_disaster_left)
	# Jeremy 2026-10-08 (hearsay flesh-out): court rulings were a deaf
	# thread — petitions granted or denied flew with zero grapevine
	# presence. The realm now gossips about the crown's rulings, and the
	# tavern judges the ruler's mercy (HTML court-gossip parity).
	_gs.bus.petition_decided.connect(_on_petition_decided)
	# Jeremy 2026-10-09 (hearsay flesh-out): court FILINGS were a deaf
	# thread — the crown's rulings gossiped since 10-08, but a courtier
	# standing up to ASK never reached the mill. Now the filing seeds
	# its own rumor and the tavern reacts to the ask, not just the
	# ruling (see _on_petition_opened).
	_gs.bus.petition_opened.connect(_on_petition_opened)
	# Jeremy 2026-10-08 (hearsay flesh-out): crimes were a deaf thread —
	# the Gazette blotted them with no parties, so victims, thieves, and
	# townsfolk all shrugged through the generic path. The crime systems
	# now emit the parties on bus.crime_committed; the mill seeds a named
	# crime rumor and the realm reacts in character (HTML "THIEF! I SAW
	# THE WHOLE THING!" parity).
	_gs.bus.crime_committed.connect(_on_crime_committed)
	# Jeremy 2026-10-08 (hearsay flesh-out): Captain Funky Pants'
	# caravan visits were a dead-end rumor — the Gazette story seeded
	# thin talk (kind "trade", heat 0.5, no reactions, nobody cared).
	# The mill now hears the caravan directly: arrival seeds a rich
	# visit rumor with the town attached, completed deals get recorded
	# on it, and departure folds in as a last-call rush.
	_gs.bus.trader_arrived.connect(_on_trader_arrived)
	_gs.bus.trader_left.connect(_on_trader_left)
	_gs.bus.trade_done.connect(_on_trade_done)
	# Jeremy 2026-10-08 (hearsay flesh-out): festivals were a deaf thread —
	# the mill only ever heard the thin court Gazette story (no town, no
	# reactions) about the biggest party in the realm. policies.gd now
	# emits bus.festival_event with the town, host faction, and joy BEFORE
	# the Gazette story publishes, so the mill seeds a rich named rumor
	# and the realm reacts in character (HTML Gazette "Society Pages"
	# parity — festivals are news the whole realm talks about).
	_gs.bus.festival_event.connect(_on_festival_event)
	# Jeremy 2026-10-09 (hearsay flesh-out): the founding beat was a deaf
	# thread — the mill only ever heard the thin "A KINGDOM RISES" court
	# Gazette story (no town, no faction, no reactions) about the realm's
	# own birth. founding.gd now emits bus.kingdom_founded with the town,
	# faction, and ruler attached BEFORE the Gazette story publishes, so
	# the mill seeds a rich named rumor and the realm reacts in character.
	_gs.bus.kingdom_founded.connect(_on_kingdom_founded)
	# Jeremy 2026-10-09 (hearsay flesh-out): the turning seasons were a deaf
	# thread — the realm's biggest shared experience (everyone feels winter
	# come) never reached the rumor mill. seasons.gd emits
	# bus.season_changed on every turnover, so the mill seeds a rich named
	# rumor and the realm reacts in character.
	_gs.bus.season_changed.connect(_on_season_changed)
	# Jeremy 2026-10-10 (hearsay flesh-out): weather arrivals were a
	# deaf thread — storms broke and snow fell while the mill heard
	# nothing. bus.weather_changed carries every transition, so the
	# mill seeds a rich named rumor and the realm reacts in character.
	_gs.bus.weather_changed.connect(_on_weather_changed)
	_mem = SimMemories.new(_gs)
	_emo = SimEmotion.new()
	_mood = SimMood.new()
	# Jeremy 2026-10-04: hearsay cold-start fix — Day 1 had zero rumors
	# (rumors only seeded by sim events that haven't happened yet), so NPCs
	# had nothing to gossip about. Seed ambient town gossip at game start.
	_seed_ambient_rumors()


## Seeds ambient Day-1 rumors so NPCs have gossip before sim events occur.
## (Jeremy 2026-10-04: hearsay cold-start fix.)
func _seed_ambient_rumors() -> void:
	var ambient: Array[String] = [
		"Heard the tavern keeper waters down the ale. Wouldn't surprise me.",
		"Someone's been stealing pies off windowsills again. Third time this month.",
		"The old well's been tasting funny. Probably nothing. Probably.",
		"They say the miller's been up all night. Wonder what he's hiding.",
		"Newcomer arrived yesterday with more luggage than sense. Keep an eye out.",
	]
	for line in ambient:
		seed_rumor(line, "life", "", 0.45, -1)


## --- rumor core ---------------------------------------------------------------

## Seeds a rumor. knower_id (-1 = nobody yet) is the first NPC who knows.
## Jeremy 2026-10-06: dedup — a live rumor with the same kind+subject
## gets its heat refreshed instead of spawning a duplicate (war_declared
## and gazette war stories used to double-seed "WAR with X").
## from_gazette marks rumors born from Gazette stories — the press pass
## skips them (the paper doesn't re-print its own stories).
## truth: "true" for rumors seeded by real sim events (they happened),
## "false" for disproven claims, "unknown" for tavern talk nobody can
## verify. Only "false" rumors can be debunked by investigation.
func seed_rumor(text: String, kind: String = "misc", subject: String = "",
		heat: float = 0.7, knower_id: int = -1,
		from_gazette: bool = false,
		truth: String = TRUTH_UNKNOWN) -> Dictionary:
	# Jeremy 2026-10-04: guard _gs.day_number — _init() seeding runs before
	# GameState is fully ready (game wouldn't start).
	var day_num := 1
	if _gs != null and _gs.get("day_number") != null:
		day_num = int(_gs.day_number)
	if subject != "":
		for r2: Dictionary in state["rumors"]:
			if String(r2.get("kind", "")) == kind \
					and String(r2.get("subject", "")) == subject:
				r2["heat"] = maxf(float(r2.get("heat", 0.0)),
					clampf(heat, 0.0, 1.0))
				# Jeremy 2026-10-06 (lane 6): a real event confirming
				# existing tavern talk upgrades the rumor's truth —
				# investigators can then verify what the realm now knows.
				if truth == TRUTH_TRUE and String(
						r2.get("truth", TRUTH_UNKNOWN)) == TRUTH_UNKNOWN:
					r2["truth"] = TRUTH_TRUE
				if knower_id > 0 and not (r2["knowers"] as Array).has(knower_id):
					(r2["knowers"] as Array).append(knower_id)
					var ku2: Dictionary = _gs.get_unit(knower_id)
					if not ku2.is_empty():
						_on_heard(ku2, r2, {})
				return r2
	var r: Dictionary = {
		"id": int(state["seq"]),
		"text": text,
		"text_orig": text,
		"kind": kind,
		"subject": subject,
		"day": day_num,
		"heat": clampf(heat, 0.0, 1.0),
		"knowers": [knower_id] if knower_id > 0 else [],
		# Jeremy 2026-10-06 (hearsay flesh-out): first-hand witnesses —
		# unit IDs that SAW the event happen (see _witness). Weighed in
		# _belief: eyewitness testimony beats second-hand retelling.
		"witnesses": [],
		# Jeremy 2026-10-07 (hearsay flesh-out): doubters — unit IDs that
		# heard the rumor and didn't buy it. Weighed in _belief: doubt is
		# contagious, so a scoffed-at tale spreads slower.
		"doubters": [],
		"reached_ruler": false,
		"distortions": 0,
		"from_gazette": from_gazette,
		"published": false,
		"truth": truth,
		"debunked": false,
		"verified": false,
		"quest_spawned": false,
	}
	state["seq"] = int(state["seq"]) + 1
	(state["rumors"] as Array).append(r)
	_trim()
	if knower_id > 0:
		var ku: Dictionary = _gs.get_unit(knower_id)
		if not ku.is_empty():
			_on_heard(ku, r, {})
	return r


func _trim() -> void:
	var arr: Array = state["rumors"]
	while arr.size() > MAX_RUMORS:
		# Drop the coldest rumor.
		var cold: int = 0
		var cold_heat: float = 2.0
		for i: int in arr.size():
			var h: float = float((arr[i] as Dictionary).get("heat", 0.0))
			if h < cold_heat:
				cold_heat = h
				cold = i
		arr.remove_at(cold)


## Jeremy 2026-10-06: player smear pipeline — the player trash-talked a
## third party in a DM ("Grak smells like ass"). Seeds a REAL rumor with
## the player as source; the hearer (conversation partner) is the first
## knower. Dedup is per target (kind+subject): a rant refreshes heat
## instead of spawning 50 rumors.
##
## JEREMY'S HARD LINE: if the player's words contain an IRL hate slur,
## this NEVER becomes a smear and NOBODY finds it funny — it routes to
## universal condemnation via bus.slur_incident (the same pipeline as the
## phone-DM outrage cascade). No exceptions.
func seed_player_smear(target: Dictionary, insult_text: String,
		insult_word: String, hearer_id: int) -> Dictionary:
	if SimHateSpeech.is_hate_slur(insult_text):
		if _gs != null:
			var pf := String(_gs.player_faction)
			var ruler := "the ruler"
			var rv = _gs.get("ruler_name")
			if rv != null:
				ruler = String(rv)
			_gs.bus.slur_incident.emit(pf, String(target.get("faction", "")),
				insult_text, ruler)
		return {}
	var tname := String(target.get("name", "someone"))
	var phrase := String(target.get("phrase", ""))
	if phrase == "":
		if insult_word != "" and insult_word != "hated" \
				and insult_word != "stinks":
			phrase = "is a " + insult_word
		elif insult_word == "hated":
			phrase = "is hated by the crown"
		else:
			phrase = "was trash-talked by the crown"
	var line := "Word from the crown itself: the ruler says %s %s." \
		% [tname, phrase]
	var r := seed_rumor(line, "smear", String(target.get("key", tname)),
		0.8, -1)
	# Jeremy 2026-10-06 (lane 6): a believed smear stains the target's
	# faction standing once (the per-NPC drip comes via _rep_tick as the
	# rumor spreads). Dedup keeps the flag — no double stain.
	if not bool(r.get("rep_faction_applied", false)):
		r["rep_faction_applied"] = true
		_faction_rep(String(target.get("faction", "")), REP_FACTION_SMEAR)
	r["player_sourced"] = true
	r["target_id"] = int(target.get("id", 0))
	r["target_name"] = tname
	r["target_faction"] = String(target.get("faction", ""))
	r["target_is_leader"] = bool(target.get("is_leader", false))
	# The hearer heard it — recorded AFTER the target fields are set so
	# _rep_tick sees the target on the very first hear.
	if hearer_id > 0:
		var hu: Dictionary = _gs.get_unit(hearer_id)
		if not hu.is_empty():
			var hk: Array = r["knowers"]
			if not hk.has(hearer_id):
				hk.append(hearer_id)
			_on_heard(hu, r, {})
	return r


## Gazette stories become rumors (heat by story kind).
## Jeremy 2026-10-06 (hearsay flesh-out): anti-loop — a story the press
## printed FROM a rumor (same headline as a published rumor) must not seed
## a new rumor about itself. Gazette-born rumors are flagged so the press
## pass never re-prints the paper's own stories.
func _on_story(story: Dictionary) -> void:
	var headline := String(story.get("headline", ""))
	if headline != "":
		for r: Dictionary in state["rumors"]:
			if bool(r.get("published", false)) \
					and headline == _press_headline(r):
				return
	# Jeremy 2026-10-08 (hearsay flesh-out): festival stories arrive with
	# parties attached via bus.festival_event BEFORE the story publishes —
	# if the rich rumor already names this town, the thin story seed would
	# double the tavern talk. Town matching is by substring: the story
	# body names the town verbatim. Stories with no rich rumor (old
	# saves) still seed the generic happy-news line below.
	if headline == "GRAND FESTIVAL!" \
			or headline == "FESTIVAL CALLED OFF" \
			or headline == "FESTIVAL WINDS DOWN":
		var fev := "held"
		if headline == "FESTIVAL CALLED OFF":
			fev = "cancelled"
		elif headline == "FESTIVAL WINDS DOWN":
			fev = "wound_down"
		var body := String(story.get("body", ""))
		for r: Dictionary in state["rumors"]:
			var ftown := String(r.get("fest_town", ""))
			if String(r.get("kind", "")) == "festival" \
					and String(r.get("fest_event", "")) == fev \
					and ftown != "" and body.contains(ftown):
				return
	# Jeremy 2026-10-09 (hearsay flesh-out): the AI director's famine
	# alarms arrive as thin Gazette seeds ("The Elves are starving —
	# bellies empty, tempers short") — route them into the rich
	# named-faction famine rumor instead (the starving become witnesses,
	# the realm reacts in character). The faction reverse-maps from the
	# body; unparseable bodies (old saves) keep the thin seed below.
	if headline == "FAMINE!" or headline == "FOOD SHORTAGE":
		var fbody := String(story.get("body", ""))
		for f: String in Config.FACTIONS.keys():
			if fbody.contains(_faction_name(f)):
				_seed_famine_rumor(f, headline == "FAMINE!")
				return
	# Jeremy 2026-10-09 (hearsay flesh-out): the founding story arrives
	# with the crowned town named in the body — bus.kingdom_founded fires
	# BEFORE the story publishes, so if the rich rumor already names this
	# town the thin story seed would double the coronation talk. Stories
	# with no rich rumor (old saves) still seed the generic proclamation
	# below.
	if headline == "A KINGDOM RISES":
		var tbody := String(story.get("body", ""))
		for r: Dictionary in state["rumors"]:
			var ftown := String(r.get("founding_town", ""))
			if String(r.get("kind", "")) == "founding" \
					and ftown != "" and tbody.contains(ftown):
				return
	# Jeremy 2026-10-09 (hearsay flesh-out): the crown's wall order
	# arrives as a Gazette story ("The crown orders walls raised around
	# %s.") — bus.wall_answer fires first in live play, so the rich
	# rumor usually exists and the story folds into it (no thin twin).
	# If the story arrives first (old saves, unusual connect order), the
	# rich rumor is seeded right here instead of the generic court line
	# below. Unparseable bodies fall through to the thin seed.
	if headline.contains("ROYAL WORKS"):
		var wbody := String(story.get("body", ""))
		var wregion := wbody.trim_prefix(
			"The crown orders walls raised around ").trim_suffix(".")
		if wregion != "" and wregion != wbody:
			for r: Dictionary in state["rumors"]:
				if String(r.get("kind", "")) == "wall" \
						and String(r.get("wall_region", "")) == wregion \
						and String(r.get("wall_event", "")) == "raised":
					return
			_on_wall_answer(wregion, true)
			return
	# Jeremy 2026-10-09 (hearsay flesh-out): the sun-bomb gets its own
	# voice. A launch story ("X launches a nuclear missile") seeds a RICH
	# rumor (nuke_launch=true, launcher named, truth TRUE — every court
	# felt the tremor) instead of a faceless thin war seed. The
	# detonation story ("NUCLEAR DETONATION — fallout incoming") stashes
	# the firing faction (reverse-mapped from the body, like the famine
	# path) and seeds NOTHING — the rich blast rumor lands moments later
	# via disaster_spawned, so the taverns never gossip the same blast
	# twice. (detonate_nuke always publishes before it emits
	# disaster_spawned, same tick.) Unparseable launch stories (old
	# saves) keep the thin seed below.
	if headline.contains("launch") \
			and headline.contains("nuclear missile"):
		for f: String in Config.FACTIONS.keys():
			if headline.contains(_faction_name(f)):
				_seed_nuke_launch(f)
				return
	if headline == "NUCLEAR DETONATION — fallout incoming":
		var dbody := String(story.get("body", ""))
		for f2: String in Config.FACTIONS.keys():
			if dbody.contains(_faction_name(f2)):
				_pending_nuke_launcher = f2
				break
		return
	var kind: String = String(story.get("kind", "default"))
	var heat: float = 0.5
	match kind:
		"war", "battle":
			heat = 1.0
		"disaster":
			heat = 0.85
		"court":
			heat = 0.7
		"crime":
			# Jeremy 2026-10-08 (hearsay flesh-out): crime stories arrive
			# through bus.crime_committed with parties attached BEFORE the
			# Gazette story publishes — if the rich rumor already carries
			# this headline, don't seed a second, party-less one. Stories
			# with no rich counterpart (arrests, trials, old saves) still
			# seed the generic blotter line.
			for r: Dictionary in state["rumors"]:
				if String(r.get("kind", "")) == "crime" \
						and String(r.get("text", "")) == headline:
					return
			heat = 0.6
		"festival":
			heat = 0.6
		"death":
			heat = 0.7
		"trade":
			# Jeremy 2026-10-08 (hearsay flesh-out): the caravan's own
			# arrival story must not double-seed the rich visit rumor
			# _on_trader_arrived planted moments earlier (identical
			# headline, town and parties attached). The departure story
			# ("packs up") folds into the live visit rumor as a last-call
			# rush instead of seeding a second, thinner rumor.
			for r: Dictionary in state["rumors"]:
				if String(r.get("kind", "")) == "trade" \
						and bool(r.get("trader_visit", false)):
					if String(r.get("text", "")) == headline:
						return
					if headline.contains("packs up"):
						return
			heat = 0.6
	seed_rumor(headline, kind, "", heat, -1, true)


func _on_day(_day: int, _is_night: bool) -> void:
	# Jeremy 2026-10-07 (hearsay flesh-out): the holder snapshot can't be
	# built in _init — the monasteries/crystals sims wire up after the
	# phone (and hearsay) is created. First day tick is early enough: no
	# capture can realistically happen before the realm wakes up.
	if (state.get("holders", {}) as Dictionary).is_empty():
		_snapshot_holders()
	# Jeremy 2026-10-09 (hearsay flesh-out): the famine watch reads the
	# granary ledgers before the day's gossip — hunger seeds its own
	# rumors, not just Gazette stories.
	_famine_tick()
	daily_tick()


## Records who currently holds each monastery and dark crystal, so the
## conquest matrix knows the LOSER when a capture lands. Null-guarded —
## bare-sim tests have no monasteries at all. Called on the first day
## tick and on save-load backfill; capture handlers keep it live after.
func _snapshot_holders() -> void:
	var holders: Dictionary = state.get("holders", {})
	var mons = _gs.get("monasteries")
	if mons != null and mons.get("monasteries") != null:
		for m: Dictionary in mons.get("monasteries"):
			holders["monastery:" + String(m.get("god_id", ""))] = \
				String(m.get("owner", ""))
	var crys = _gs.get("crystals")
	if crys != null and crys.get("crystals") != null:
		for c: Dictionary in crys.get("crystals"):
			holders["crystal:" + String(c.get("god_id", ""))] = \
				String(c.get("owner", ""))
	state["holders"] = holders


## One day of gossip: spread, ruler DMs, the press pass, then decay.
## Jeremy 2026-10-06 (hearsay flesh-out): spread/reach/press run on
## pre-decay heat — decay-first meant a 0.7 rumor decayed to 0.574 and could
## NEVER reach the 0.6 ruler bar the header promises, and the 0.85 press
## bar was unreachable for same-day big news. Overnight cooling now
## happens after the day's gossip, as it should.
func daily_tick() -> void:
	for r: Dictionary in state["rumors"]:
		_spread(r)
		_maybe_reach_ruler(r)
	# The press pass — the hottest rumor earns Gazette coverage.
	_press_tick()
	# Jeremy 2026-10-06 (lane 6): hot rumors become advisor proposals,
	# and approved cache expeditions come home.
	_quest_tick()
	_resolve_pending_caches()
	var dead: Array = []
	for r: Dictionary in state["rumors"]:
		r["heat"] = float(r.get("heat", 0.0)) * DECAY
		if float(r.get("heat", 0.0)) < 0.08:
			dead.append(r)
	for r: Dictionary in dead:
		(state["rumors"] as Array).erase(r)
	# Ambient NPC-life chatter (HTML sqbGenNpcLife flavor).
	if randf() < 0.35:
		_seed_npc_life()


## Jeremy 2026-10-06 (hearsay flesh-out): the press pass. Once per day,
## the hottest press-worthy rumor becomes a Gazette story via the real
## Gazette system (SimRoyalCourt.publish_story — lands in the Chronicle
## archive, sections/reporters/cartoons, glyph-sanitized). The story is
## honestly labeled as tavern talk, never confirmed fact. Being in the
## paper amplifies the rumor (heat bump) and Gazette readers join the
## grapevine as knowers. Guards for bare-sim tests (no court).
func _press_tick() -> void:
	var court = _gs.court_sys
	if court == null or not court.has_method("publish_story"):
		return
	var day_num := 1
	if _gs != null and _gs.get("day_number") != null:
		day_num = int(_gs.day_number)
	if int(state.get("last_press_day", 0)) == day_num:
		return  # front page carries one rumor story a day
	var best: Dictionary = {}
	var best_heat := -1.0
	for r: Dictionary in state["rumors"]:
		if not _press_eligible(r):
			continue
		var h := float(r.get("heat", 0.0))
		if h > best_heat:
			best_heat = h
			best = r
	if best.is_empty():
		return
	state["last_press_day"] = day_num
	best["published"] = true
	# Front-page amplification: print makes the talk hotter.
	best["heat"] = maxf(float(best.get("heat", 0.0)), 0.95)
	var kind := String(best.get("kind", "misc"))
	var story_kind: String = {"slur": "court"}.get(kind, kind)
	court.publish_story(_press_headline(best), _press_body(best),
		story_kind)
	# Gazette readers join the grapevine — print spreads the word.
	for i in 2:
		var reader: Dictionary = _random_citizen("")
		if reader.is_empty():
			break
		_witness(reader, best)


## A rumor earns press coverage: hot, talked-about, not ambient chatter,
## not already in print, and not born from the Gazette itself.
func _press_eligible(r: Dictionary) -> bool:
	if bool(r.get("published", false)):
		return false
	if bool(r.get("debunked", false)):
		return false  # buried by investigators — never printed
	if bool(r.get("from_gazette", false)):
		return false
	if String(r.get("kind", "misc")) in PRESS_EXCLUDE_KINDS:
		return false
	if float(r.get("heat", 0.0)) < PRESS_HEAT:
		return false
	if (r.get("knowers", []) as Array).size() < PRESS_MIN_KNOWERS:
		return false
	# Jeremy 2026-10-06 (hearsay gap coverage): confirmed news the Gazette
	# already printed (e.g. accepted surrenders via diplomacy._report) is
	# never re-printed as a rumor story — no double front pages.
	if not bool(r.get("press_ok", true)):
		return false
	return true


## The press prints the rumor's undistorted core claim, honestly labeled
## as tavern talk — the HTML's rule holds: rumors don't cite sources.
func _press_headline(r: Dictionary) -> String:
	var claim := String(r.get("text_orig", r.get("text", ""))).strip_edges()
	if claim.length() > 96:
		claim = claim.left(93) + "..."
	return "RUMOR MILL: %s" % claim


func _press_body(r: Dictionary) -> String:
	var claim := String(r.get("text_orig", r.get("text", ""))).strip_edges()
	var n := (r.get("knowers", []) as Array).size()
	return "Word on the street: \"%s\" %d citizens claim to have heard it, and the talk only grows. The Gazette prints the realm's gossip as gossip — believe it at your own risk." % [claim, n]


## A knower tells up to 2 others (same faction preferred). Blocked NPCs
## neither hear nor tell — they are cut out of the grapevine entirely.
## Jeremy 2026-10-06: overhaul — the tell cap is now PER knower (it was
## accidentally global, so one knower's cap throttled the whole day's
## spread and mood-based loudmouths never mattered). Receivers now run a
## BELIEF check (faction loyalty, wariness of enemy tellers): skeptics
## doubt instead of spreading. Successful tells can DISTORT the rumor
## (telephone game), and every new knower actually HEARS it — memory +
## emotion — instead of the ID just sitting in a list.
func _spread(r: Dictionary) -> void:
	if float(r.get("heat", 0.0)) < SPREAD_HEAT:
		return
	var knowers: Array = r["knowers"]
	if knowers.is_empty():
		# Nobody knows yet — a random citizen picks it up.
		var first: Dictionary = _random_citizen("")
		if not first.is_empty():
			var fid0 := int(first.get("id", 0))
			knowers.append(fid0)
			_on_heard(first, r, {})
		return
	# Jeremy 2026-10-04: dead-knower leak fix — collect dead IDs during the
	# spread loop and erase them after, so knowers doesn't accumulate
	# dead unit IDs forever.
	var dead_ids: Array = []
	for kid: Variant in knowers.duplicate():
		var ku: Dictionary = _gs.get_unit(int(kid))
		if ku.is_empty():
			dead_ids.append(kid)
			continue
		# Jeremy 2026-10-04: moods in hearsay — happy and angry NPCs are
		# loudmouths who spread gossip wider; sad and scared NPCs are
		# withdrawn and barely tell anyone.
		# Jeremy 2026-10-06 (hearsay flesh-out): spread ZEAL — how much an
		# NPC wants to tell a rumor varies by who they are and what the
		# rumor is about. Unhinged NPCs are SUPER-SPREADERS: the realm's
		# chaos agents tell EVERYONE, louder and wider. And relationship
		# motivation shapes the telling — see _spread_motivation.
		var told := 0
		var told_cap := 2
		var roll_heat: float = float(r.get("heat", 0.0))
		match _mood.dominant(ku):
			"happy", "angry":
				told_cap = 3
			"sad", "scared":
				told_cap = 1
		if SimUnhinged.is_unhinged(ku):
			told_cap += 2
			roll_heat = minf(1.0, roll_heat + 0.2)
		var mot: Dictionary = _spread_motivation(ku, r)
		told_cap = maxi(1, told_cap + int(mot.get("cap_delta", 0)))
		roll_heat = clampf(roll_heat + float(mot.get("heat_delta", 0.0)),
			0.05, 1.0)
		while told < told_cap and randf() < roll_heat:
			var friend: Dictionary = _random_citizen(String(ku.get("faction", "")))
			if friend.is_empty():
				break
			var fid: int = int(friend.get("id", 0))
			if knowers.has(fid):
				break  # already knows — stop fishing for this knower
			if randf() < _belief(ku, friend, r):
				knowers.append(fid)
				told += 1
				_on_heard(friend, r, ku)
				# Jeremy 2026-10-11: visible gossip chains — record who
				# told whom (capped; rendered by SimSocialLife).
				var _sl_chain: Array = r.get("chain", [])
				if _sl_chain.size() < 12:
					_sl_chain.append({"t": int(ku.get("id", 0)), "f": fid,
						"day": int(_gs.day_number)})
					r["chain"] = _sl_chain
				_maybe_distort(r)
			else:
				_on_doubted(friend, r, ku)
				told += 1  # a rebuff still costs the teller effort
		# Jeremy 2026-10-08 (hearsay flesh-out): the border-crossing
		# grapevine — one cross-faction tell attempt per knower per day,
		# routed by kind and relationship (see _cross_tell).
		_cross_tell(ku, r)
	# Prune dead knowers collected above.
	for dead_id in dead_ids:
		knowers.erase(dead_id)


## How much the hearer believes the teller's rumor (0..1). Same-faction
## tellers are trusted; tellers from a faction you're at war with are
## doubted. Heat is the base — hot news is just more believable.
## First-hand witnesses make it harder to dismiss ("I saw it myself"),
## and the teller's own reputation colors their word (a Beloved citizen
## is trusted, a Despised one doubted).
func _belief(teller: Dictionary, hearer: Dictionary, r: Dictionary) -> float:
	var b: float = float(r.get("heat", 0.5))
	var tf: String = String(teller.get("faction", ""))
	var hf: String = String(hearer.get("faction", ""))
	if tf == hf:
		b += 0.2
	elif _gs.diplomacy != null:
		if String(_gs.diplomacy.relation_state(tf, hf)) == "war":
			b -= 0.35
	# Jeremy 2026-10-06 (hearsay flesh-out): first-hand witnesses make a
	# tale harder to dismiss — "I saw it myself" beats "someone told me".
	var wits: Array = r.get("witnesses", [])
	b += minf(float(wits.size()) * WITNESS_BELIEF_EACH, WITNESS_BELIEF_CAP)
	# The teller's own name colors their word: a Beloved citizen is
	# trusted, a Despised one is doubted. Nameless tellers ({}, e.g. the
	# seed/witness path) skip this — nobody's word is on the line.
	var tell_id := int(teller.get("id", 0))
	if tell_id > 0:
		b += (reputation_of(tell_id) - REP_DEFAULT) / REP_DEFAULT \
			* TELLER_TRUST_WEIGHT
	# Jeremy 2026-10-07: player-sourced smears — the hearer also weighs the
	# PLAYER as ultimate source. The player's own faction trusts the crown's
	# word more; factions at war with the player doubt it.
	if bool(r.get("player_sourced", false)) and _gs != null:
		var pf := String(_gs.player_faction)
		if hf == pf:
			b += 0.15
		elif _gs.diplomacy != null \
				and String(_gs.diplomacy.relation_state(pf, hf)) == "war":
			b -= 0.2
	# Jeremy 2026-10-09 (hearsay flesh-out): famine is witnessed fact —
	# an empty belly doesn't lie. The starving believe hunger talk
	# readily (their own stomachs corroborate it).
	if String(r.get("kind", "misc")) == "famine" \
			and hf == String(r.get("famine_faction", "")):
		b += 0.25
	# Jeremy 2026-10-07 (hearsay flesh-out): a twice-told tale is less
	# credible — each telephone-game hop dents belief. And doubt is
	# contagious: a rumor the town already scoffs at is believed less
	# (capped — doubt can slow a hot rumor, never kill one). Slur
	# incidents are witnessed fact and never get doubted down: the realm
	# condemns them, it doesn't question whether they happened (the
	# hard line holds). Famine rumors (2026-10-09) join that club — the
	# granaries are visibly empty, so doubt can't dent hunger. Nukes
	# (2026-10-09) join it too: the sky burned and the tremor was felt
	# realm-wide — nobody doubts a sun-bomb down. Seasons (2026-10-09)
	# join the club too: the snow is on the ground — nobody doubts winter
	# arrived. Weather arrivals (2026-10-10) join it too: the storm
	# broke overhead — everybody saw the sky. Brigade rollouts
	# (2026-10-10) join it too: the engine rolled through town with the
	# bells ringing — nobody doubts a spectacle. The deniable kinds
	# (smears, misc) take the full hit.
	if String(r.get("kind", "misc")) != "slur" \
			and String(r.get("kind", "misc")) != "famine" \
			and String(r.get("kind", "misc")) != "season" \
			and String(r.get("kind", "misc")) != "weather" \
			and String(r.get("kind", "misc")) != "brigade" \
			and String(r.get("kind", "misc")) != "vehicle" \
			and not bool(r.get("nuke", false)) \
			and not bool(r.get("nuke_launch", false)):
		b -= float(int(r.get("distortions", 0))) * DISTORT_BELIEF_EACH
		var doubters: Array = r.get("doubters", [])
		b -= minf(float(doubters.size()) * DOUBT_BELIEF_EACH,
				DOUBT_BELIEF_CAP)
	return clampf(b, 0.05, 1.0)


## Jeremy 2026-10-06 (hearsay flesh-out): relationship-driven spread
## motivation. Returns {cap_delta, heat_delta} shaping how eagerly a knower
## tells a given rumor:
##   - smear about someone they DISLIKE (stance <= -0.3): amused — they
##     spread it faster and wider, cackling all the way.
##   - smear about someone they LIKE (stance >= 0.3): reluctant — they
##     barely whisper dirt about a friend.
##   - slur/scandal: condemnation is contagious — everyone pushes the
##     outrage (heat is already maxed by the cascade; zeal adds reach).
## Everything else: neutral telling. Pure logic — no RNG, no state.
func _spread_motivation(ku: Dictionary, r: Dictionary) -> Dictionary:
	var kind := String(r.get("kind", "misc"))
	match kind:
		"war":
			# Jeremy 2026-10-09 (hearsay flesh-out): a loosed sun-spear
			# is dread gossip — the launcher's people boast the spear's
			# flight, everyone else warns their neighbors. The mill
			# shouts this one.
			if bool(r.get("nuke_launch", false)):
				var nlf := String(r.get("nuke_launcher", ""))
				if String(ku.get("faction", "")) == nlf and nlf != "":
					return {"cap_delta": 2, "heat_delta": 0.1}
				return {"cap_delta": 1, "heat_delta": 0.1}
			# Jeremy 2026-10-09 (hearsay flesh-out): a denied peace
			# feeler is shameful gossip — the would-be beggars bury it,
			# the would-be recipients gloat-spread it, and war-rivals of
			# the beggars push it gleefully. Other war news spreads
			# straight; the mill tells it as-is.
			if not bool(r.get("peace_feeler", false)):
				return {"cap_delta": 0, "heat_delta": 0.0}
			var pfa := String(r.get("side_a", ""))
			var pfb := String(r.get("side_b", ""))
			var wuf := String(ku.get("faction", ""))
			if wuf == pfa:
				return {"cap_delta": -1, "heat_delta": -0.1}
			if wuf == pfb:
				return {"cap_delta": 1, "heat_delta": 0.05}
			if _rival_of(wuf, pfa):
				return {"cap_delta": 1, "heat_delta": 0.1}
		"smear":
			var tid := int(r.get("target_id", 0))
			if tid <= 0:
				return {"cap_delta": 0, "heat_delta": 0.0}
			var target := {"id": tid, "name": String(r.get("target_name", "")),
				"faction": String(r.get("target_faction", "")),
				"is_leader": bool(r.get("target_is_leader", false))}
			var stance := SimLikesDislikes.npc_stance(ku, target, _gs)
			if stance <= -0.3:
				return {"cap_delta": 1, "heat_delta": 0.1}
			if stance >= 0.3:
				return {"cap_delta": -1, "heat_delta": -0.2}
		"slur", "scandal":
			return {"cap_delta": 1, "heat_delta": 0.0}
		"gossip":
			# Jeremy 2026-10-08 (hearsay flesh-out): tavern talk about a
			# named citizen — rivals spread it gleefully, friends try to
			# kill it. Silly talk, small deltas: this is teasing, not war.
			var vid := _gossip_victim_id(r)
			if vid <= 0:
				return {"cap_delta": 0, "heat_delta": 0.0}
			var victim: Dictionary = _gs.get_unit(vid)
			if victim.is_empty():
				return {"cap_delta": 0, "heat_delta": 0.0}
			var gstance := SimLikesDislikes.npc_stance(ku, victim, _gs)
			if gstance <= -0.3:
				return {"cap_delta": 1, "heat_delta": 0.05}
			if gstance >= 0.3:
				return {"cap_delta": -1, "heat_delta": -0.15}
		"news":
			# Jeremy 2026-10-09 (hearsay flesh-out): a court FILING is
			# campaign gossip — the petitioner's friends drum up support
			# for the live plea (+1), their rivals mock-spread it around
			# the tavern (+1, hotter). Both sides TALK; the mill loves a
			# plea that hasn't been answered yet.
			if String(r.get("petition_filing", "")) != "":
				var fid := int(r.get("petitioner_id", 0))
				if fid <= 0:
					return {"cap_delta": 0, "heat_delta": 0.0}
				var filer: Dictionary = _gs.get_unit(fid)
				if filer.is_empty():
					return {"cap_delta": 0, "heat_delta": 0.0}
				var fstance := SimLikesDislikes.npc_stance(ku, filer, _gs)
				if fstance >= 0.3:
					return {"cap_delta": 1, "heat_delta": 0.05}
				if fstance <= -0.3:
					return {"cap_delta": 1, "heat_delta": 0.1}
				return {"cap_delta": 0, "heat_delta": 0.0}
			# Jeremy 2026-10-08 (hearsay flesh-out): a DENIED plea is
			# schadenfreude gossip — rivals of the petitioner push it
			# gleefully, friends try to bury it. Granted pleas and other
			# news are just news; the mill moves on.
			if String(r.get("petition_verdict", "")) != "denied":
				return {"cap_delta": 0, "heat_delta": 0.0}
			var qid := int(r.get("petitioner_id", 0))
			if qid <= 0:
				return {"cap_delta": 0, "heat_delta": 0.0}
			var pet: Dictionary = _gs.get_unit(qid)
			if pet.is_empty():
				return {"cap_delta": 0, "heat_delta": 0.0}
			var pstance := SimLikesDislikes.npc_stance(ku, pet, _gs)
			if pstance <= -0.3:
				return {"cap_delta": 1, "heat_delta": 0.05}
			if pstance >= 0.3:
				return {"cap_delta": -1, "heat_delta": -0.15}
		"wall":
			# Jeremy 2026-10-09 (hearsay flesh-out): border-wall zeal —
			# the crown's people boast the raising, rivals sneer-spread
			# it; a REFUSAL is shameful gossip the crown's people bury
			# while rivals cackle-spread it. Neutrals tell it straight.
			var wfact := String(r.get("wall_faction", ""))
			var wuf := String(ku.get("faction", ""))
			var raised := String(r.get("wall_event", "")) == "raised"
			if wfact != "" and wuf == wfact:
				if raised:
					return {"cap_delta": 1, "heat_delta": 0.05}
				return {"cap_delta": -1, "heat_delta": -0.1}
			if wfact != "" and _rival_of(wuf, wfact):
				if raised:
					return {"cap_delta": 1, "heat_delta": 0.05}
				return {"cap_delta": 1, "heat_delta": 0.1}
			return {"cap_delta": 0, "heat_delta": 0.0}
		"crystal":
			# Jeremy 2026-10-09 (hearsay flesh-out): a bad omen about your
			# own crystal gets buried at home, gloat-spread by war-rivals,
			# and told straight by everyone else.
			var cofact := String(r.get("crystal_owner", ""))
			var cuf := String(ku.get("faction", ""))
			if cofact != "" and cuf == cofact:
				return {"cap_delta": -1, "heat_delta": -0.1}
			if cofact != "" and _rival_of(cuf, cofact):
				return {"cap_delta": 1, "heat_delta": 0.1}
			return {"cap_delta": 0, "heat_delta": 0.0}
		"trespass":
			# Jeremy 2026-10-10 (hearsay flesh-out): the snoop buries it,
			# the owner and household name-and-shame it, the snoop's rivals
			# gloat-spread it, the snoop's friends help bury it. Everyone
			# else tells it straight — the tavern loves a caught snoop.
			var tsid := int(r.get("trespass_snoop_id", 0))
			var tuid := int(ku.get("id", 0))
			if tsid > 0 and tuid == tsid:
				return {"cap_delta": -1, "heat_delta": -0.1}
			var thb := _gs.get_building(int(r.get("trespass_house", 0)))
			if not thb.is_empty() and tuid in (thb.get("residents", []) as Array):
				return {"cap_delta": 1, "heat_delta": 0.1}
			var tsnoop: Dictionary = _gs.get_unit(tsid)
			if not tsnoop.is_empty():
				var tstance := SimLikesDislikes.npc_stance(ku, tsnoop, _gs)
				if tstance <= -0.3:
					return {"cap_delta": 1, "heat_delta": 0.1}
				if tstance >= 0.3:
					return {"cap_delta": -1, "heat_delta": -0.1}
			return {"cap_delta": 0, "heat_delta": 0.0}
		"beastloss":
			# Jeremy 2026-10-10 (hearsay flesh-out): the shamed faction
			# buries its hungry-herd gossip, rivals gloat-spread it, wolf
			# news travels straight — the wilds scare everyone equally.
			var bcause := String(r.get("beastloss_cause", ""))
			var bfact := String(r.get("beastloss_faction", ""))
			var kuf := String(ku.get("faction", ""))
			if bcause == "starved" and bfact != "":
				if kuf == bfact:
					return {"cap_delta": -1, "heat_delta": -0.1}
				if _rival_of(kuf, bfact):
					return {"cap_delta": 1, "heat_delta": 0.1}
			return {"cap_delta": 0, "heat_delta": 0.0}
		"harvest":
			# Jeremy 2026-10-10 (hearsay flesh-out): the faction with the
			# lean harvest buries it, rivals gloat-spread it; a bumper crop
			# gets brag-spread by its own people and told straight by
			# everyone else (rivals downplay nothing — the mill heard).
			var htype := String(r.get("harvest_type", ""))
			var hfact := String(r.get("harvest_faction", ""))
			var kuf2 := String(ku.get("faction", ""))
			if hfact != "":
				if htype == "lean":
					if kuf2 == hfact:
						return {"cap_delta": -1, "heat_delta": -0.1}
					if _rival_of(kuf2, hfact):
						return {"cap_delta": 1, "heat_delta": 0.1}
					return {"cap_delta": 0, "heat_delta": 0.0}
				if htype == "bumper":
					if kuf2 == hfact:
						return {"cap_delta": 1, "heat_delta": 0.1}
					return {"cap_delta": 0, "heat_delta": 0.0}
			return {"cap_delta": 0, "heat_delta": 0.0}
		"brigade":
			# Jeremy 2026-10-10 (hearsay flesh-out): the brigade's own
			# people brag-spread the rollout, rivals mock-spread it
			# ("all those bells and the barn burns anyway"), everyone else
			# tells it straight — a rolling fire engine is news.
			var brfact := String(r.get("brigade_faction", ""))
			var kuf3 := String(ku.get("faction", ""))
			if brfact != "":
				if kuf3 == brfact:
					return {"cap_delta": 1, "heat_delta": 0.1}
				if _rival_of(kuf3, brfact):
					return {"cap_delta": 1, "heat_delta": 0.1}
			return {"cap_delta": 0, "heat_delta": 0.0}
		"vehicle":
			# Jeremy 2026-10-11 (hearsay flesh-out): the buyer
			# brag-spreads their new wheels, their faction admires
			# (envy spreads too — "guess who can't afford a wagon"),
			# rivals mock-spread the show-off, everyone else tells it
			# straight. Dealer openings are plain commerce news.
			var vvkind := String(r.get("vehicle_kind", ""))
			if vvkind == "opened":
				return {"cap_delta": 0, "heat_delta": 0.0}
			var vfact2 := String(r.get("vehicle_faction", ""))
			var vkuf := String(ku.get("faction", ""))
			if vfact2 != "":
				if int(ku.get("id", 0)) == int(r.get("vehicle_buyer", 0)):
					return {"cap_delta": 2, "heat_delta": 0.1}
				if vkuf == vfact2:
					return {"cap_delta": 1, "heat_delta": 0.05}
				if _rival_of(vkuf, vfact2):
					return {"cap_delta": 1, "heat_delta": 0.1}
			return {"cap_delta": 0, "heat_delta": 0.0}
		"crime":
			# Jeremy 2026-10-08 (hearsay flesh-out): name-and-shame
			# dynamics — the victim and the crook's rivals push it, the
			# crook's friends try to bury it. An unseen thief is just
			# news; the mill tells it straight.
			var ccid := int(r.get("crook_id", 0))
			if ccid <= 0:
				return {"cap_delta": 0, "heat_delta": 0.0}
			if int(ku.get("id", 0)) == int(r.get("victim_id", 0)):
				return {"cap_delta": 1, "heat_delta": 0.1}
			var ccrook: Dictionary = _gs.get_unit(ccid)
			if ccrook.is_empty():
				return {"cap_delta": 0, "heat_delta": 0.0}
			var cstance := SimLikesDislikes.npc_stance(ku, ccrook, _gs)
			if cstance <= -0.3:
				return {"cap_delta": 1, "heat_delta": 0.1}
			if cstance >= 0.3:
				return {"cap_delta": -1, "heat_delta": -0.1}
		"kill":
			# Jeremy 2026-10-08 (hearsay flesh-out): slaying talk spreads
			# by side — the victim's kin push it in outrage, the killer's
			# kin boast in war and try to bury it in peace, everyone else
			# just gossips. Small deltas; grief, not war.
			var kkf := String(r.get("killer_faction", ""))
			var kvf := String(r.get("victim_faction", ""))
			if kkf == "" or kvf == "":
				return {"cap_delta": 0, "heat_delta": 0.0}
			var kuf := String(ku.get("faction", ""))
			if kuf == kvf:
				return {"cap_delta": 1, "heat_delta": 0.1}
			if kuf == kkf:
				if _rival_of(kkf, kvf):
					return {"cap_delta": 1, "heat_delta": 0.05}
				return {"cap_delta": -1, "heat_delta": -0.1}
		"trade":
			# Jeremy 2026-10-08 (hearsay flesh-out): caravan news is happy
			# news — the host town's citizens push it eagerly (market-day
			# pride); everyone else just gossips. Small deltas; this is a
			# market, not a war.
			if bool(r.get("trader_visit", false)) \
					and String(r.get("trader_faction", "")) != "" \
					and String(ku.get("faction", "")) == String(
						r.get("trader_faction", "")):
				return {"cap_delta": 1, "heat_delta": 0.05}
		"quest":
			# Jeremy 2026-10-08 (hearsay flesh-out): triumph talk — the
			# hero's own faction boasts it everywhere; failures get buried
			# at home and gloated over across a war border; a legend is
			# retold by everyone, loudest at home.
			var qhf := String(r.get("hero_faction", ""))
			if qhf == "":
				return {"cap_delta": 0, "heat_delta": 0.0}
			var qo := String(r.get("quest_outcome", "done"))
			var quf := String(ku.get("faction", ""))
			if qo == "legend":
				if quf == qhf:
					return {"cap_delta": 2, "heat_delta": 0.1}
				return {"cap_delta": 1, "heat_delta": 0.05}
			if qo == "failed":
				if quf == qhf:
					return {"cap_delta": -1, "heat_delta": -0.15}
				if _rival_of(quf, qhf):
					return {"cap_delta": 1, "heat_delta": 0.1}
				return {"cap_delta": 0, "heat_delta": 0.0}
			if qo == "fell":
				if _rival_of(quf, qhf):
					return {"cap_delta": 1, "heat_delta": 0.1}
				return {"cap_delta": 0, "heat_delta": 0.0}
			if qo == "taken":
				# Jeremy 2026-10-09 (hearsay flesh-out): a quest taken up
				# is exciting tavern talk — the hero's faction boasts it,
				# war-rivals mock the fool's errand, and neutrals just
				# gossip about the odds.
				if quf == qhf:
					return {"cap_delta": 1, "heat_delta": 0.1}
				if _rival_of(quf, qhf):
					return {"cap_delta": 1, "heat_delta": 0.05}
				return {"cap_delta": 0, "heat_delta": 0.0}
			if quf == qhf:
				return {"cap_delta": 1, "heat_delta": 0.1}
		"festival":
			# Jeremy 2026-10-08 (hearsay flesh-out): festival talk is
			# happy news — the host faction's citizens boast it loudly;
			# war-rivals bury the triumph but gloat over a cancellation.
			# Wind-downs are pleasant small talk; the mill moves on.
			var ff := String(r.get("fest_faction", ""))
			if ff == "":
				return {"cap_delta": 0, "heat_delta": 0.0}
			var fuf := String(ku.get("faction", ""))
			if String(r.get("fest_event", "held")) == "cancelled":
				if _rival_of(fuf, ff):
					return {"cap_delta": 1, "heat_delta": 0.1}
				if fuf == ff:
					return {"cap_delta": -1, "heat_delta": -0.15}
				return {"cap_delta": 0, "heat_delta": 0.0}
			if fuf == ff:
				return {"cap_delta": 1, "heat_delta": 0.1}
			if _rival_of(fuf, ff):
				return {"cap_delta": -1, "heat_delta": -0.1}
		"famine":
			# Jeremy 2026-10-09 (hearsay flesh-out): hunger talk spreads
			# by whose belly is empty. The starving spread it URGENTLY
			# ("we need help"); war-rivals spread it mockingly
			# (schadenfreude travels fast); factions ALLIED with the
			# starving try to bury a friend's shame. Everyone else just
			# gossips.
			var famf := String(r.get("famine_faction", ""))
			if famf == "":
				return {"cap_delta": 0, "heat_delta": 0.0}
			var fuf2 := String(ku.get("faction", ""))
			if fuf2 == famf:
				return {"cap_delta": 1, "heat_delta": 0.05}
			if _rival_of(fuf2, famf):
				return {"cap_delta": 1, "heat_delta": 0.1}
			if _gs.diplomacy != null and String(
					_gs.diplomacy.relation_state(fuf2, famf)) == "allied":
				return {"cap_delta": -1, "heat_delta": -0.15}
		"founding":
			# Jeremy 2026-10-09 (hearsay flesh-out): coronation talk — the
			# home faction boasts it everywhere; war-rivals sneer-spread
			# it; everyone else just gossips. Small deltas; this is a
			# party, not a war.
			var fhf := String(r.get("founding_faction", ""))
			if fhf == "":
				return {"cap_delta": 0, "heat_delta": 0.0}
			var fhuf := String(ku.get("faction", ""))
			if fhuf == fhf:
				return {"cap_delta": 1, "heat_delta": 0.05}
			if _rival_of(fhuf, fhf):
				return {"cap_delta": 1, "heat_delta": 0.05}
		"disaster":
			# Jeremy 2026-10-09 (hearsay flesh-out): a sun-bomb is the
			# loudest news in the realm. Survivors of the stricken
			# faction spread the horror urgently; the launcher's people
			# boast the spear's aim; everyone else retells the awe.
			# Ordinary weather just gossips.
			if not bool(r.get("nuke", false)):
				return {"cap_delta": 0, "heat_delta": 0.0}
			var dhit := String(r.get("hit_faction", ""))
			var dln := String(r.get("nuke_launcher", ""))
			var duf := String(ku.get("faction", ""))
			if dhit != "" and duf == dhit:
				return {"cap_delta": 2, "heat_delta": 0.1}
			if dln != "" and duf == dln:
				return {"cap_delta": 1, "heat_delta": 0.1}
			return {"cap_delta": 1, "heat_delta": 0.05}
		"season":
			# Jeremy 2026-10-09 (hearsay flesh-out): winter warnings are
			# neighborly duty — everyone tells everyone to stock the
			# cellar. Spring's hope spreads gladly; summer and autumn are
			# idle small talk. Small deltas; this is weather, not war.
			var sn := String(r.get("season", ""))
			if sn == "Winter":
				return {"cap_delta": 1, "heat_delta": 0.05}
			if sn == "Spring":
				return {"cap_delta": 1, "heat_delta": 0.0}
		"weather":
			# Jeremy 2026-10-10 (hearsay flesh-out): storm warnings are
			# neighborly duty too — batten the shutters, mind the crops.
			# Snow talk travels like winter talk; rain is idle sky-talk.
			# Everybody already saw the sky, so this is eagerness to TALK,
			# not to inform — small deltas.
			var wk := String(r.get("weather_kind", ""))
			if wk == "storm":
				return {"cap_delta": 1, "heat_delta": 0.05}
			if wk == "snow":
				return {"cap_delta": 1, "heat_delta": 0.0}
	return {"cap_delta": 0, "heat_delta": 0.0}


## Jeremy 2026-10-08 (hearsay flesh-out): the border-crossing grapevine.
## Tellers used to pick same-faction hearers only (the _random_citizen
## fallback only kicks in when the whole faction is dead or blocked), so
## a rumor seeded in one faction circulated there forever — the attacked
## side of a war often never heard the drums via the mill, and the
## cross-faction sides of _war_reaction plus the war-doubt branch of
## _belief sat nearly dead. Now every knower gets ONE cross-faction tell
## attempt per day, routed by kind and relationship:
##   - war news: the OTHER recorded side must hear it — enemy boasts and
##     fleeing refugees carry the drums across the border. A war PLOT
##     (live or denied) reaches the would-be target's taverns; a
##     conquest reaches the loser's kin (shame and fury) or the taker's
##     kin (pride), depending which side the teller stands on.
##   - slur/scandal: outrage is universal — condemnation crosses into
##     allied realms.
##   - diplomacy news: merchant caravans carry peace/trade/tribute word
##     to allied realms.
##   - disaster/death: allies hear the hard news.
##   - everything else: a trickle of trader gossip into non-war realms.
## War borders stay closed to trader gossip — only war news crosses a war
## border, because that IS the war news. Blocked and dead citizens stay
## out (via _random_citizen); the belief check still gates every tell.
## One extra _random_citizen scan per knower per day — cheap at the
## 240-unit cap; no state, no save schema changes.
func _cross_tell(ku: Dictionary, r: Dictionary) -> void:
	var target: Dictionary = _cross_target(ku, r)
	var tf: String = String(target.get("faction", ""))
	if tf == "" or randf() >= float(target.get("chance", 0.0)):
		return
	var hearer: Dictionary = _random_citizen(tf)
	if hearer.is_empty():
		return
	var hid: int = int(hearer.get("id", 0))
	var knowers: Array = r["knowers"]
	if knowers.has(hid):
		return
	if randf() < _belief(ku, hearer, r):
		knowers.append(hid)
		_on_heard(hearer, r, ku)
		_maybe_distort(r)
	else:
		_on_doubted(hearer, r, ku)


## Where a cross-faction tell goes: {faction, chance}. Pure routing —
## the randf roll happens in _cross_tell so tests can read the route.
func _cross_target(ku: Dictionary, r: Dictionary) -> Dictionary:
	var kf: String = String(ku.get("faction", ""))
	var kind: String = String(r.get("kind", "misc"))
	match kind:
		"war":
			var sa: String = String(r.get("side_a", ""))
			var sb: String = String(r.get("side_b", ""))
			# Jeremy 2026-10-09 (hearsay flesh-out): a loosed sun-spear
			# crosses every border — every court felt the tremor, and the
			# dread travels outward from whoever carries it.
			if bool(r.get("nuke_launch", false)):
				return {"faction": _open_faction(kf), "chance": 0.3}
			# War plots (live or denied) reach the would-be target.
			if bool(r.get("war_plot", false)) \
					or bool(r.get("plot_denied", false)):
				if sb != "" and sb != kf:
					return {"faction": sb, "chance": 0.5}
				return {"faction": "", "chance": 0.0}
			# Jeremy 2026-10-09 (hearsay flesh-out): a denied peace
			# feeler reaches the would-be recipients — the laughed-at
			# faction hears the beggars balked, and gloats accordingly.
			if bool(r.get("peace_feeler", false)):
				if sb != "" and sb != kf:
					return {"faction": sb, "chance": 0.4}
				return {"faction": "", "chance": 0.0}
			# Conquests carry holder_old/holder_new, not side_a/side_b:
			# the loser's kin hear of the shame, the taker's of the pride.
			var ho: String = String(r.get("holder_old", ""))
			var hn: String = String(r.get("holder_new", ""))
			if ho != "" and hn != "":
				if kf == hn:
					return {"faction": ho, "chance": 0.4}
				if kf == ho:
					return {"faction": hn, "chance": 0.4}
				return {"faction": ho, "chance": 0.4}
			# Declared wars: the other recorded side hears the drums. A
			# third-party teller carries it to the attacked side.
			if sa == "" or sb == "":
				return {"faction": "", "chance": 0.0}
			if kf == sa:
				return {"faction": sb, "chance": 0.5}
			if kf == sb:
				return {"faction": sa, "chance": 0.5}
			return {"faction": sb, "chance": 0.5}
		"slur", "scandal":
			return {"faction": _allied_faction(kf), "chance": 0.15}
		"news":
			if r.has("dip"):
				return {"faction": _allied_faction(kf), "chance": 0.15}
			return {"faction": _open_faction(kf), "chance": 0.04}
		"disaster", "death":
			# Jeremy 2026-10-09 (hearsay flesh-out): a sun-bomb crosses
			# every border — the flash was visible realm-wide. The
			# stricken faction's tale travels fast; a blast with no town
			# in range still rides the open-border trickle, faster than
			# weather.
			if kind == "disaster" and bool(r.get("nuke", false)):
				var nhit := String(r.get("hit_faction", ""))
				if nhit != "" and nhit != kf:
					return {"faction": nhit, "chance": 0.4}
				return {"faction": _open_faction(kf), "chance": 0.25}
			return {"faction": _allied_faction(kf), "chance": 0.08}
		"kill":
			# Jeremy 2026-10-08 (hearsay flesh-out): a slaying crosses
			# like war news with a named other side — the victim's kin
			# hear of the shame, the killer's kin hear of the pride, and
			# a third-party teller carries it to the victim's halls.
			var kkf := String(r.get("killer_faction", ""))
			var kvf := String(r.get("victim_faction", ""))
			if kkf == "" or kvf == "":
				return {"faction": _open_faction(kf), "chance": 0.04}
			if kf == kkf:
				return {"faction": kvf, "chance": 0.4}
			if kf == kvf:
				return {"faction": kkf, "chance": 0.4}
			return {"faction": kvf, "chance": 0.3}
		"famine":
			# Jeremy 2026-10-09 (hearsay flesh-out): hunger is
			# schadenfreude fuel — war-rivals hear of an enemy's empty
			# pots fast (a foe of the starving faction, 0.35), allies
			# hear it with grief, everyone else gets the open-border
			# trickle.
			var fam := String(r.get("famine_faction", ""))
			if fam == "":
				return {"faction": _open_faction(kf), "chance": 0.04}
			var foes: Array[String] = []
			for f2: String in Config.FACTIONS.keys():
				if f2 == kf or f2 == fam:
					continue
				if _rival_of(f2, fam):
					foes.append(f2)
			if not foes.is_empty():
				return {"faction": foes[randi() % foes.size()],
					"chance": 0.35}
			return {"faction": _allied_faction(kf), "chance": 0.12}
		"season":
			# Jeremy 2026-10-09 (hearsay flesh-out): the season turns for
			# every realm at once — the snow doesn't stop at the border.
			# Carry the talk to any open realm eagerly.
			return {"faction": _open_faction(kf), "chance": 0.6}
		"weather":
			# Jeremy 2026-10-10 (hearsay flesh-out): weather arrives
			# realm-wide — the storm doesn't stop at the border either.
			# Carry the talk to any open realm eagerly.
			return {"faction": _open_faction(kf), "chance": 0.6}
	return {"faction": _open_faction(kf), "chance": 0.04}


## A random faction allied with (or friendly to) kf, or "" if none.
func _allied_faction(kf: String) -> String:
	if _gs.diplomacy == null:
		return ""
	var cands: Array[String] = []
	for f: String in Config.FACTIONS.keys():
		if f == kf:
			continue
		var st := String(_gs.diplomacy.relation_state(kf, f))
		if st == "allied" or st == "friendly":
			cands.append(f)
	if cands.is_empty():
		return ""
	return cands[randi() % cands.size()]


## A random faction not at war with kf, or "" if the realm is all war.
func _open_faction(kf: String) -> String:
	if _gs.diplomacy == null:
		return ""
	var cands: Array[String] = []
	for f: String in Config.FACTIONS.keys():
		if f == kf:
			continue
		if String(_gs.diplomacy.relation_state(kf, f)) != "war":
			cands.append(f)
	if cands.is_empty():
		return ""
	return cands[randi() % cands.size()]


## An NPC heard a rumor: they remember it (grounded — the rumor really
## reached them) and feel something about it by kind. This is what makes
## NPCs "understand" the news instead of IDs sitting in a list.
func _on_heard(u: Dictionary, r: Dictionary, teller: Dictionary) -> void:
	if _mem == null:
		return
	# Jeremy 2026-10-06 (lane 6): believed rumors move reputations — the
	# hearer is one more citizen who carries the talk.
	_rep_tick(u, r)
	var kind := String(r.get("kind", "misc"))
	# Jeremy 2026-10-06: player smears get the full relationship reaction
	# matrix (defend / laugh / furious) instead of the generic handling.
	# Jeremy 2026-10-08 (hearsay flesh-out): NPC-invented smears are lies
	# told by a fellow citizen, not the crown — they get their own
	# reaction (the target's fury lands on the liar, never the player).
	if kind == "smear":
		if bool(r.get("player_sourced", false)):
			_smear_reaction(u, r)
		else:
			_npc_smear_reaction(u, r)
		return
	# Jeremy 2026-10-07 (hearsay flesh-out): diplomatic rumors were seeded
	# with no character reactions — dead-end news nobody cared about. Any
	# rumor carrying the diplomacy subtype now routes to the reaction
	# matrix (see _news_reaction): peace, alliance, trade, tribute paid,
	# hostile turns, town foundings.
	if r.has("dip"):
		_news_reaction(u, r)
		return
	# Jeremy 2026-10-06: ASSFACE prank-spree rumors — amusement/mockery,
	# never anger at Assface (he's a lovable menace, not a villain).
	if kind == "assface":
		_assface_reaction(u, r)
		return
	# Jeremy 2026-10-08 (hearsay flesh-out): gossip-kind tavern talk
	# (Yapper's citizen rumors) was the last dead-end rumor — seeded,
	# spread, and felt by NOBODY (no emotion, default-strength memory).
	# It now routes to the gossip reaction matrix (see _gossip_reaction):
	# the victim is mortified, rivals cackle, friends defend, and the
	# town remembers who laughed and who stood up.
	if kind == "gossip":
		_gossip_reaction(u, r)
		return
	# Jeremy 2026-10-08 (hearsay flesh-out): crime rumors now carry the
	# criminal, the victim, and the town — the realm reacts in character
	# instead of shrugging at a Gazette blotter line. The victim is
	# outraged, the named crook is caught out (unhinged ones brag), the
	# town feels unsafe, rivals mock the thief, and the crook's friends
	# are disappointed. Crimes with no recorded parties (arrests, trials,
	# old saves) stay on the generic reception path.
	if kind == "crime" and r.has("crime_kind"):
		_crime_reaction(u, r)
		return
	# Jeremy 2026-10-07 (hearsay flesh-out): war news is the opposite of
	# a dead-end rumor — the realm REACTS. The attacked side fears the
	# drums, the attacking side rallies, surrender news moves morale.
	# Conquest news (captures) carries its own matrix — the side that LOST
	# the post feels shame and fury, the takers feel pride. A capture with
	# no recorded loser (unclaimed post, old save) is just news.
	if kind == "war":
		# Jeremy 2026-10-09 (hearsay flesh-out): a loosed sun-spear is not
		# a declared war — the whole realm dreads the inbound spear (see
		# _nuke_launch_reaction) instead of rallying to / fearing the
		# drums.
		if bool(r.get("nuke_launch", false)):
			_nuke_launch_reaction(u, r)
			return
		# Jeremy 2026-10-09 (hearsay flesh-out): denied peace feelers
		# carry their own matrix — a beaten faction's council debated
		# begging and said no. The realm reacts in character (see
		# _peace_feeler_reaction) instead of shrugging at war news.
		if bool(r.get("peace_feeler", false)):
			_peace_feeler_reaction(u, r)
			return
		if r.has("holder_new") \
				and String(r.get("holder_old", "")) != "":
			_conquest_reaction(u, r)
			return
		# Jeremy 2026-10-08 (hearsay flesh-out): war PLOTS get their own
		# matrix — a plotter with a named target is not a declared war.
		if bool(r.get("war_plot", false)):
			_war_plot_reaction(u, r)
			return
		_war_reaction(u, r)
		return
	# Jeremy 2026-10-07 (hearsay flesh-out): disaster rumors now record
	# the stricken town — victims panic, war-rivals laugh at the misery,
	# allies grieve. A disaster with no town in range (deep wilds, old
	# saves) is just news — the generic reception path.
	if kind == "disaster":
		_disaster_reaction(u, r)
		return
	# Jeremy 2026-10-08 (hearsay flesh-out): slain-by-a-known-faction
	# killings carry the killer — the realm doesn't just mourn, it wants
	# answers (see _kill_reaction). Upgraded obituaries (kind "death" +
	# killer_faction) route here too, ahead of the plain-death branch.
	if kind == "kill" or (kind == "death" \
			and String(r.get("killer_faction", "")) != ""):
		_kill_reaction(u, r)
		return
	# Jeremy 2026-10-07 (hearsay flesh-out): deaths of notables record
	# the dead's faction at seed — their own faction mourns, war-rivals
	# cackle at the loss, everyone else pays respects. Facet-less
	# obituaries (old saves, Gazette-seeded death stories) fall through
	# to the generic reception path.
	if kind == "death" and String(r.get("dead_faction", "")) != "":
		_death_reaction(u, r)
		return
	# Jeremy 2026-10-08 (hearsay flesh-out): adventure quest rumors —
	# triumphs, failures, legends, and fallen heroes. The realm REACTS
	# to the hero's story in character (see _quest_reaction) instead of
	# shrugging through the generic path.
	if kind == "quest":
		_quest_reaction(u, r)
		return
	# Jeremy 2026-10-08 (hearsay flesh-out): festival rumors now carry
	# the host town and faction — the realm REACTS in character (see
	# _festival_reaction): the host town celebrates, rivals sneer or
	# cackle, everyone else enjoys the news. Festival Gazette stories
	# with no rich rumor attached (old saves) fall through to the
	# generic path — still happy news, just faceless.
	if kind == "festival" and String(r.get("fest_event", "")) != "":
		_festival_reaction(u, r)
		return
	# Jeremy 2026-10-09 (hearsay flesh-out): founding rumors carry the
	# crowned town and faction — the realm REACTS in character (see
	# _founding_reaction): the home faction celebrates, war-rivals sneer,
	# allies congratulate, everyone else hears hopeful news. Thin founding
	# stories with no rich rumor attached (old saves) fall through to the
	# generic path — still news, just faceless.
	if kind == "founding" and String(r.get("founding_faction", "")) != "":
		_founding_reaction(u, r)
		return
	# Jeremy 2026-10-09 (hearsay flesh-out): famine rumors carry the
	# starving faction — its people despair, war-rivals cackle at the
	# empty pots, everyone else grieves a little. Relief rumors (the
	# famine lifted) route here too.
	if kind == "famine" and String(r.get("famine_faction", "")) != "":
		_famine_reaction(u, r)
		return
	# Jeremy 2026-10-07 (hearsay flesh-out): betrayal and tribute-refusal
	# rumors now record both sides at seed — the betrayed rage, the
	# breakers stand defiant; refusers puff up while the demander seethes.
	# Jeremy 2026-10-09 (hearsay flesh-out): court-FILING rumors carry
	# their own reaction matrix (see _petition_filing_reaction) — the
	# tavern reacts to the ASK, not just the ruling. Checked ahead of
	# the verdict branch; a filing never carries a verdict.
	if kind == "news" and String(r.get("petition_filing", "")) != "":
		_petition_filing_reaction(u, r)
		return
	# Jeremy 2026-10-08 (hearsay flesh-out): court-ruling rumors carry
	# their own reaction matrix (see _petition_reaction) — the tavern
	# judges the crown's mercy. Checked before the betrayer/refuser
	# news branch; those carry no petition verdict.
	if kind == "news" and String(r.get("petition_verdict", "")) != "":
		_petition_reaction(u, r)
		return
	if kind == "news":
		if r.has("betrayer"):
			_betrayal_reaction(u, r)
			return
		if r.has("refuser"):
			_tribute_refusal_reaction(u, r)
			return
	# Jeremy 2026-10-07 (hearsay flesh-out): a destroyed building records
	# whose hall fell — the owning faction mourns it, not just notes it.
	if kind == "building" and String(r.get("lost_holder", "")) != "":
		_building_loss_reaction(u, r)
		return
	# Jeremy 2026-10-08 (hearsay flesh-out): the caravan visit was the
	# last dead-end rumor — seeded thin with no character reactions. A
	# visit rumor now routes to the trader matrix: the host town buzzes,
	# dealers brag, latecomers regret, the proud sniff. Diplomatic trade
	# PACTS (kind "news", dip="trade") keep their own matrix above.
	if kind == "trade" and bool(r.get("trader_visit", false)):
		_trader_reaction(u, r)
		return
	# Jeremy 2026-10-09 (hearsay flesh-out): the turning seasons were a
	# deaf thread — the realm's biggest shared experience never reached
	# the mill. Season rumors carry the season name; the realm reacts in
	# character (see _season_reaction): winter dreads, spring hopes,
	# summer basks, autumn counts the harvest. Thin season rumors with no
	# season attached (old saves) fall through to the generic path.
	if kind == "season" and String(r.get("season", "")) != "":
		_season_reaction(u, r)
		return
	# Jeremy 2026-10-10 (hearsay flesh-out): weather arrivals were a
	# deaf thread — storms broke and nobody talked. Rich weather rumors
	# carry weather_kind; the realm reacts in character (see
	# _weather_reaction): storms dread, rain blesses the fields, snow
	# puts the realm on edge. Anything without a kind (can't happen
	# today — this kind is new) falls through to the generic path.
	if kind == "weather" and String(r.get("weather_kind", "")) != "":
		_weather_reaction(u, r)
		return
	# Jeremy 2026-10-09 (hearsay flesh-out): border-wall gossip — the
	# crown's Raise/Skip verdict on a named region. The realm REACTS in
	# character (see _wall_reaction): the crown's people swell with
	# pride (or split over a refusal), war-rivals sneer or cackle,
	# everyone else reads the stones. Wall rumors without an event
	# attached (old saves) fall through to the generic path.
	if kind == "wall" and String(r.get("wall_event", "")) != "":
		_wall_reaction(u, r)
		return
	# Jeremy 2026-10-09 (hearsay flesh-out): lightning strikes on dark
	# crystals are omens, not small talk — the realm reacts in character
	# (see _crystal_reaction): the holder's people read dread, rivals
	# gloat, everyone else feels the sky's mood.
	if kind == "crystal":
		_crystal_reaction(u, r)
		return
	# Jeremy 2026-10-10 (hearsay flesh-out): trespass gossip — the realm
	# reacts in character (see _trespass_reaction): the house owner is
	# furious, the household is uneasy, the snoop is shamed (or defiant,
	# if unhinged), rivals cackle, friends go quiet, everyone else is
	# entertained. Rich rumors carry trespass_snoop_id; anything without
	# it (old saves) falls through to the generic path.
	if kind == "trespass" and int(r.get("trespass_snoop_id", 0)) > 0:
		_trespass_reaction(u, r)
		return
	# Jeremy 2026-10-10 (hearsay flesh-out): beastloss gossip — the
	# realm reacts in character (see _beastloss_reaction): the hungry
	# herd's faction is shamed, rivals gloat, wolf news makes everyone
	# wary (the unhinged find it hilarious). Rich rumors carry
	# beastloss_cause; anything without it (old saves) falls through
	# to the generic path.
	if kind == "beastloss" and String(r.get("beastloss_cause", "")) != "":
		_beastloss_reaction(u, r)
		return
	# Jeremy 2026-10-10 (hearsay flesh-out): harvest gossip — the realm
	# reacts in character (see _harvest_reaction): the bumper faction is
	# proud, rivals are envious, the lean faction is embarrassed and the
	# mill mocks it. Rich rumors carry harvest_type; anything without it
	# (old saves) falls through to the generic path.
	if kind == "harvest" and String(r.get("harvest_type", "")) != "":
		_harvest_reaction(u, r)
		return
	# Jeremy 2026-10-10 (hearsay flesh-out): brigade gossip — the realm
	# reacts in character (see _brigade_reaction): the brigade's faction
	# swells with pride, the burning town feels hope, rivals mock the
	# bells, the unhinged thrill at the spectacle. Rich rumors carry
	# brigade_faction; anything without it (old saves) falls through to
	# the generic path.
	if kind == "brigade" and String(r.get("brigade_faction", "")) != "":
		_brigade_reaction(u, r)
		return
	# Jeremy 2026-10-11 (hearsay flesh-out): dealership gossip — the
	# realm reacts in character (see _vehicle_reaction): the buyer
	# brags, their faction admires (or envies), rivals mock the
	# show-off, the unhinged covet the wheels. Rich rumors carry
	# vehicle_kind ("opened"/"bought"); anything without it (old saves)
	# falls through to the generic path.
	if kind == "vehicle" and String(r.get("vehicle_kind", "")) != "":
		_vehicle_reaction(u, r)
		return
	_generic_heard(u, r)


## The generic reception path: a real memory of hearing the rumor plus an
## emotion by kind, so NPCs understand the news and the conversation
## engine can reference it later.
func _generic_heard(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var kind := String(r.get("kind", "misc"))
	var strength: float = float(KIND_MEM_STRENGTH.get(kind, 0.3))
	_mem.remember(u, "heard_rumor", int(r.get("id", 0)), kind,
		String(u.get("faction", "")), strength)
	if _emo != null and KIND_EMOTION.has(kind):
		_emo.notify(u, String(KIND_EMOTION[kind]))


## Jeremy 2026-10-07 (hearsay flesh-out): the war-news reaction matrix.
## NPCs hear who declared on whom and react in character:
##   - hearer in the ATTACKED faction -> fear the drums (brave NPCs get
##     angry instead of scared — emotion.gd stands_ground parity), mood
##     drops, and the attack is remembered by attacker.
##   - hearer in the ATTACKING faction -> rally round the war drums:
##     proud, mood up, the declaration remembered by defender.
##   - surrender news (subject "surrender:*"/"surrendered:*") -> the
##     losers are demoralized (proud ones take it as anger, mocked
##     parity), the winners celebrate; a mere OFFER only rattles.
##   - anyone else, or rumors with no recorded sides (old saves,
##     Gazette-seeded) -> the generic reception path.
## Unhinged NPCs feel it 1.5x in whichever direction they lean, matching
## the smear path. Everything persists as memories + ruler-mood, so
## grudges and war-fear surface in later dialogue.
func _war_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var subject := String(r.get("subject", ""))
	if subject.begins_with("surrender:") \
			or subject.begins_with("surrendered:"):
		_surrender_reaction(u, r)
		return
	var ufaction := String(u.get("faction", ""))
	var side_a := String(r.get("side_a", ""))  # declarer / attacker
	var side_b := String(r.get("side_b", ""))  # defender
	if side_a == "" or side_b == "":
		_generic_heard(u, r)
		return
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if ufaction == side_b:
		_mem.remember(u, "war_on_us", int(r.get("id", 0)), side_a,
			ufaction, 0.9)
		_react_apply(u, -10.0 * mult, 0.0, "attacked")
	elif ufaction == side_a:
		_mem.remember(u, "war_declared_by_us", int(r.get("id", 0)), side_b,
			ufaction, 0.8)
		_react_apply(u, 8.0 * mult, 0.0, "victory")
	else:
		_generic_heard(u, r)


## Jeremy 2026-10-08 (hearsay flesh-out): the war-PLOT reaction matrix.
## A declare-war proposal is closed-council gossip — the target is named
## but the war hasn't happened. The realm reacts in character anyway:
##   - LIVE plot: the TARGET's people fear the looming drums (mood down,
##     "attacked" emotion — brave NPCs get angry via stands_ground
##     parity, same as the war path); the PLOTTER's people grimly
##     anticipate the fight (mood up, they like the news).
##   - DENIED plot (plot_denied): tavern comedy. The would-be target
##     breathes relief (mood up); the plotters' own people are
##     embarrassed by the chickening-out (mood down, "mocked"); the rest
##     of the realm just laughs.
##   - anyone else, or a plot with no recorded target (old saves) ->
##     the generic reception path.
## Unhinged NPCs feel it 1.5x in whichever direction they lean, matching
## the war path. Everything persists as memories + ruler-mood.
func _war_plot_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var ufaction := String(u.get("faction", ""))
	var side_a := String(r.get("side_a", ""))  # plotter
	var side_b := String(r.get("side_b", ""))  # target
	if side_a == "" or side_b == "":
		_generic_heard(u, r)
		return
	var rid := int(r.get("id", 0))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if bool(r.get("plot_denied", false)):
		if ufaction == side_b:
			_mem.remember(u, "war_plot_dead", rid, side_a, ufaction, 0.6)
			_react_apply(u, 6.0 * mult, 0.0, "victory")
		elif ufaction == side_a:
			_mem.remember(u, "war_plot_chickened", rid, side_b, ufaction,
				0.8)
			_react_apply(u, -6.0 * mult, 0.0, "mocked")
		else:
			_mem.remember(u, "heard_war_plot", rid, side_a, ufaction, 0.4)
			_react_apply(u, 3.0 * mult, 0.0, "mocked")
		return
	if ufaction == side_b:
		_mem.remember(u, "war_plotted_on_us", rid, side_a, ufaction, 0.85)
		_react_apply(u, -8.0 * mult, 0.0, "attacked")
	elif ufaction == side_a:
		_mem.remember(u, "war_plotting", rid, side_b, ufaction, 0.7)
		_react_apply(u, 4.0 * mult, 0.0, "liked_topic")
	else:
		_generic_heard(u, r)


## Jeremy 2026-10-09 (hearsay flesh-out): the denied-peace-feeler
## reaction matrix. A beaten faction's council debated begging for
## peace and said no — the realm reacts in character:
##   - the FEELER's own people (side_a): proud/haughty NPCs burn with
##     shame at the begging talk (mood down, angry); hawks stand
##     defiant — rather fight than beg (mood up, proud); doves despair
##     that the war grinds on (mood down, sad).
##   - the TARGET's people (side_b): gloating (mood up, mocked).
##   - war-rivals of the feeler: schadenfreude (mood up, mocked).
##   - allies of the feeler: sympathy for a friend's shame (mood down
##     a little, sad).
##   - everyone else: mild amusement at the tavern comedy.
## Unhinged NPCs feel it 1.5x, matching the other matrices. Everything
## persists as memories + ruler-mood.
func _peace_feeler_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var ufaction := String(u.get("faction", ""))
	var side_a := String(r.get("side_a", ""))  # would-be beggars
	var side_b := String(r.get("side_b", ""))  # would-be recipients
	if side_a == "":
		_generic_heard(u, r)
		return
	var rid := int(r.get("id", 0))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if ufaction == side_a:
		var persona := SimPersonality.persona_of(u)
		var stuffy := persona == "proud" or persona == "haughty" \
			or SimPersonality.trait_of(u, "proud") >= 0.6
		if stuffy:
			# "We don't BEG." — shame curdles into fury at the doves.
			_mem.remember(u, "peace_feeler_shame", rid, side_b, ufaction,
				0.8)
			_react_apply(u, -8.0 * mult, 0.0, "insulted")
		elif SimPersonality.trait_of(u, "brave") >= 0.6 \
				or persona == "brave":
			# Hawks: rather fight than beg.
			_mem.remember(u, "peace_feeler_defiant", rid, side_b,
				ufaction, 0.7)
			_react_apply(u, 5.0 * mult, 0.0, "victory")
		else:
			# Doves: the war grinds on, and the taverns are laughing.
			_mem.remember(u, "peace_feeler_despair", rid, side_b,
				ufaction, 0.7)
			_react_apply(u, -6.0 * mult, 0.0, "dismayed")
	elif ufaction == side_b:
		_mem.remember(u, "peace_feeler_gloated", rid, side_a, ufaction,
			0.8)
		_react_apply(u, 7.0 * mult, 0.0, "mocked")
	elif _rival_of(ufaction, side_a):
		_mem.remember(u, "peace_feeler_mocked", rid, side_a, ufaction,
			0.6)
		_react_apply(u, 5.0 * mult, 0.0, "mocked")
	elif _gs.diplomacy != null and String(
			_gs.diplomacy.relation_state(ufaction, side_a)) == "allied":
		_mem.remember(u, "heard_peace_feeler", rid, side_a, ufaction,
			0.4)
		_react_apply(u, -2.0 * mult, 0.0, "dismayed")
	else:
		_mem.remember(u, "heard_peace_feeler", rid, side_a, ufaction,
			0.3)
		_react_apply(u, 2.0 * mult, 0.0, "mocked")


## Jeremy 2026-10-07 (hearsay flesh-out): the conquest reaction matrix.
## Captures record BOTH sides (holder_old = the loser, holder_new = the
## taker), so the realm reacts in character instead of shrugging:
##   - hearer in the faction that LOST the post -> shame and fury at the
##     taker (mood down, "attacked" emotion — brave NPCs get angry via
##     stands_ground parity, same as the war path), remembered by taker.
##   - hearer in the TAKING faction -> pride: the banner flies over a new
##     hall (mood up, "victory"), remembered by loser.
##   - anyone else -> the generic reception path.
## Unhinged NPCs feel it 1.5x, matching the war/smear paths. Everything
## persists as memories + ruler-mood, so grudges surface in later talk.
func _conquest_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var ufaction := String(u.get("faction", ""))
	var old_holder := String(r.get("holder_old", ""))
	var new_holder := String(r.get("holder_new", ""))
	if old_holder == "" or new_holder == "":
		_generic_heard(u, r)
		return
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var rid := int(r.get("id", 0))
	if ufaction == old_holder:
		_mem.remember(u, "lost_post", rid, new_holder, ufaction, 0.9)
		_react_apply(u, -10.0 * mult, 0.0, "attacked")
	elif ufaction == new_holder:
		_mem.remember(u, "took_post", rid, old_holder, ufaction, 0.8)
		_react_apply(u, 8.0 * mult, 0.0, "victory")
	else:
		_generic_heard(u, r)


## Jeremy 2026-10-07 (hearsay flesh-out): the betrayal reaction matrix.
## Treaty breaks record betrayer AND betrayed:
##   - the BETRAYED side -> outrage at the oathbreakers (mood down,
##     "insulted" anger), remembered by betrayer — this is grudge fuel.
##   - the BETRAYER's own side -> defiant pride (mood up, "victory"):
##     their crown played the strong hand.
##   - anyone else -> generic reception.
func _betrayal_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var ufaction := String(u.get("faction", ""))
	var betrayer := String(r.get("betrayer", ""))
	var betrayed := String(r.get("betrayed", ""))
	if betrayer == "" or betrayed == "":
		_generic_heard(u, r)
		return
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var rid := int(r.get("id", 0))
	if ufaction == betrayed:
		_mem.remember(u, "betrayed_by", rid, betrayer, ufaction, 0.9)
		_react_apply(u, -10.0 * mult, 0.0, "insulted")
	elif ufaction == betrayer:
		_mem.remember(u, "broke_treaty", rid, betrayed, ufaction, 0.6)
		_react_apply(u, 5.0 * mult, 0.0, "victory")
	else:
		_generic_heard(u, r)


## Jeremy 2026-10-07 (hearsay flesh-out): the tribute-refusal matrix.
## "Bold. Dangerous. Bold." — and the realm has opinions:
##   - the REFUSER's side -> defiant pride (mood up, "victory"): nobody
##     shakes US down.
##   - the DEMANDER's side -> humiliated fury (mood down, "insulted"):
##     their demand was spat back in their face.
##   - anyone else -> generic reception.
func _tribute_refusal_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var ufaction := String(u.get("faction", ""))
	var refuser := String(r.get("refuser", ""))
	var demander := String(r.get("demander", ""))
	if refuser == "" or demander == "":
		_generic_heard(u, r)
		return
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var rid := int(r.get("id", 0))
	if ufaction == refuser:
		_mem.remember(u, "refused_tribute", rid, demander, ufaction, 0.7)
		_react_apply(u, 6.0 * mult, 0.0, "victory")
	elif ufaction == demander:
		_mem.remember(u, "tribute_refused_us", rid, refuser, ufaction, 0.8)
		_react_apply(u, -8.0 * mult, 0.0, "insulted")
	else:
		_generic_heard(u, r)


## Rival check for the diplomacy matrix: a faction at war or openly
## hostile with the other side. Null-safe — no diplomacy sim yet (unit
## tests boot GameState directly) means nobody is anyone's rival.
func _rival_of(f: String, other: String) -> bool:
	if _gs == null or _gs.diplomacy == null:
		return false
	var st := String(_gs.diplomacy.relation_state(f, other))
	return st == "war" or st == "hostile"


## Jeremy 2026-10-07 (hearsay flesh-out): the diplomatic-news reaction
## matrix. Peace treaties, alliances, trade pacts, tribute payments,
## hostile turns, and town foundings all seeded rumors but produced NO
## character reactions — dead-end news nobody cared about. Now:
##   - peace: the peacemakers breathe easier (mood up, "helped").
##   - alliance: the allies swell with pride ("victory"); factions
##     hostile with either side grow uneasy ("attacked" — brave NPCs get
##     angry instead of scared via stands_ground parity, same as war).
##   - trade: the traders are content ("helped"); their enemies sneer
##     ("mocked" — proud sneerers double down, emotion.gd parity).
##   - tribute: the payer feels the sting ("insulted"), the receiver
##     feels smug ("victory").
##   - hostile: both sides brace for trouble ("attacked" — stands_ground
##     parity); everyone else just watches.
##   - town: the founding faction celebrates ("victory").
## Missing/empty sides (old saves, Gazette-seeded news) fall back to the
## generic reception. Unhinged NPCs feel it 1.5x, matching the other
## matrices. Everything persists as memories + ruler-mood so relief,
## pride, and grudges surface in later talk.
func _news_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var ufaction := String(u.get("faction", ""))
	var rid := int(r.get("id", 0))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var sa := String(r.get("side_a", ""))
	var sb := String(r.get("side_b", ""))
	match String(r.get("dip", "")):
		"peace", "alliance", "trade", "hostile":
			if sa == "" or sb == "":
				_generic_heard(u, r)
				return
			var sides := sa + "|" + sb
			if ufaction == sa or ufaction == sb:
				match String(r.get("dip", "")):
					"peace":
						_mem.remember(u, "heard_peace", rid, sides, ufaction, 0.7)
						_react_apply(u, 5.0 * mult, 0.0, "helped")
					"alliance":
						_mem.remember(u, "heard_alliance", rid, sides, ufaction, 0.7)
						_react_apply(u, 4.0 * mult, 0.0, "victory")
					"trade":
						_mem.remember(u, "heard_trade", rid, sides, ufaction, 0.6)
						_react_apply(u, 2.0 * mult, 0.0, "helped")
					"hostile":
						_mem.remember(u, "heard_hostile", rid, sides, ufaction, 0.7)
						_react_apply(u, -4.0 * mult, 0.0, "attacked")
			elif _rival_of(ufaction, sa) or _rival_of(ufaction, sb):
				match String(r.get("dip", "")):
					"alliance":
						_mem.remember(u, "enemy_alliance", rid, sides, ufaction, 0.7)
						_react_apply(u, -4.0 * mult, 0.0, "attacked")
					"trade":
						_mem.remember(u, "rival_trade", rid, sides, ufaction, 0.5)
						_react_apply(u, -2.0 * mult, 0.0, "mocked")
					_:
						_generic_heard(u, r)
			else:
				_generic_heard(u, r)
		"tribute":
			var payer := String(r.get("payer", ""))
			var receiver := String(r.get("receiver", ""))
			if payer == "" or receiver == "":
				_generic_heard(u, r)
				return
			if ufaction == payer:
				_mem.remember(u, "paid_tribute", rid, receiver, ufaction, 0.7)
				_react_apply(u, -6.0 * mult, 0.0, "insulted")
			elif ufaction == receiver:
				_mem.remember(u, "tribute_won", rid, payer, ufaction, 0.6)
				_react_apply(u, 5.0 * mult, 0.0, "victory")
			else:
				_generic_heard(u, r)
		"town":
			var founder := String(r.get("founder", ""))
			if founder == "":
				_generic_heard(u, r)
				return
			if ufaction == founder:
				_mem.remember(u, "town_founded_us", rid,
					String(r.get("subject", "")), ufaction, 0.6)
				_react_apply(u, 3.0 * mult, 0.0, "victory")
			else:
				_generic_heard(u, r)
		_:
			_generic_heard(u, r)


## Jeremy 2026-10-07 (hearsay flesh-out): a destroyed building records
## whose hall fell — the owning faction mourns it (mood down, "disaster"
## grief, remembered), everyone else gets the generic reception.
func _building_loss_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var ufaction := String(u.get("faction", ""))
	var lost_holder := String(r.get("lost_holder", ""))
	if lost_holder == "":
		_generic_heard(u, r)
		return
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if ufaction == lost_holder:
		_mem.remember(u, "building_lost", int(r.get("id", 0)),
			String(r.get("subject", "")), ufaction, 0.7)
		_react_apply(u, -6.0 * mult, 0.0, "disaster")
	else:
		_generic_heard(u, r)


## Jeremy 2026-10-07 (hearsay flesh-out): the disaster reaction matrix.
## Disaster rumors record the stricken town (hit_faction/hit_town), so
## the realm reacts in character instead of a uniform shrug:
##   - hearer in the STRICKEN faction -> panic at the devastation
##     (mood down, "disaster").
##   - hearer in a faction at war/hostile with the stricken one ->
##     schadenfreude: the enemy's pain is funny (mood up, "mocked" —
##     proud sneerers double down, emotion.gd parity).
##   - anyone else -> sympathy for the afflicted (mood down a little,
##     "helped").
## A disaster that struck the wilds (no town in range, old saves, or
## rumors seeded before towns existed) falls back to the generic
## reception. Unhinged NPCs feel it 1.5x, matching the other matrices.
## Everything persists as memories + ruler-mood.
func _disaster_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	# Jeremy 2026-10-09 (hearsay flesh-out): a nuclear blast is not
	# weather — even the enemy falls silent (see _nuke_blast_reaction).
	if bool(r.get("nuke", false)):
		_nuke_blast_reaction(u, r)
		return
	var hit := String(r.get("hit_faction", ""))
	if hit == "":
		_generic_heard(u, r)
		return
	var ufaction := String(u.get("faction", ""))
	var rid := int(r.get("id", 0))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if ufaction == hit:
		_mem.remember(u, "disaster_hit_us", rid, hit, ufaction, 0.9)
		_react_apply(u, -10.0 * mult, 0.0, "disaster")
	elif _rival_of(ufaction, hit):
		_mem.remember(u, "rival_disaster", rid, hit, ufaction, 0.7)
		_react_apply(u, 6.0 * mult, 0.0, "mocked")
	else:
		_mem.remember(u, "ally_disaster", rid, hit, ufaction, 0.6)
		_react_apply(u, -4.0 * mult, 0.0, "helped")


## Surrender news, split by whether the flag was merely offered or the
## yield accepted. Losers sink, winners rise; offers only rattle.
## Jeremy 2026-10-07 (hearsay flesh-out): the death-of-a-notable reaction
## matrix. Obituaries used to be dead-end news — every hearer got the same
## generic "friend_died" beat no matter whose notable died. Now:
##   - hearer in the dead notable's faction -> mourning: the bells toll
##     for US (mood down hard, "friend_died", "mourned_our_dead").
##   - hearer at war/hostile with the dead's faction -> schadenfreude: the
##     enemy's spymaster is dead — drinks all round ("mocked",
##     "rival_dead", mood up).
##   - everyone else -> respects: a notable of the realm has fallen
##     ("heard_dead_other", mild mood dip).
## Facet-less obituaries (old saves, Gazette-seeded death stories) fall
## through to the generic reception. Unhinged NPCs feel it 1.5x, matching
## the other matrices. Everything persists as memories + ruler-mood so
## grief and gloating surface in later talk.
func _death_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var dfaction := String(r.get("dead_faction", ""))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if ufaction == dfaction:
		_mem.remember(u, "mourned_our_dead", rid, "death", dfaction, 0.85)
		_react_apply(u, -8.0 * mult, 0.0, "friend_died")
	elif _rival_of(ufaction, dfaction):
		_mem.remember(u, "rival_dead", rid, "death", dfaction, 0.7)
		_react_apply(u, 6.0 * mult, 0.0, "mocked")
	else:
		_mem.remember(u, "heard_dead_other", rid, "death", dfaction, 0.5)
		_react_apply(u, -2.0 * mult, 0.0, "friend_died")


## Jeremy 2026-10-08 (hearsay flesh-out): the who-killed-whom reaction
## matrix. A killing with a NAMED killer faction is not a plain death —
## the realm reacts to the blade, not just the grave:
##   - hearer in the VICTIM's faction -> grief in war ("friend_died"),
##     OUTRAGE in peace ("insulted" — this was murder, not battle);
##     the killer faction is remembered by name (grudge fuel).
##   - hearer in the KILLER's faction -> pride in war ("victory", our
##     blades slew the enemy); dread in peace ("disaster" — did we just
##     start a war?); unhinged ones brag either way.
##   - third parties -> in war: rivals of the killer mock, rivals of the
##     victim grieve-by-proxy, everyone else just hears it; in peace:
##     the whole realm is shocked (HTML assassin-headline parity: -6).
## Notable victims hit 1.25x — the realm feels a fallen leader harder.
## Everything persists as memories + ruler-mood so the grudge against
## the killer faction surfaces in later dialogue.
func _kill_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var kfaction := String(r.get("killer_faction", ""))
	var vfaction := String(r.get("victim_faction", ""))
	var vname := String(r.get("victim_name", "the slain"))
	if kfaction == "" or vfaction == "":
		_generic_heard(u, r)
		return
	var at_war := _rival_of(kfaction, vfaction)
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var nudge := 1.25 if bool(r.get("victim_notable", false)) else 1.0
	if ufaction == vfaction:
		_mem.remember(u, "kin_slain_by", rid, kfaction, ufaction,
			0.9 * nudge)
		if at_war:
			_react_apply(u, -8.0 * mult * nudge, 0.0, "friend_died")
		else:
			_react_apply(u, -12.0 * mult * nudge, 0.0, "insulted")
	elif ufaction == kfaction:
		_mem.remember(u, "our_blades_slew", rid, vfaction, ufaction, 0.8)
		if at_war:
			_react_apply(u, 6.0 * mult, 0.0, "victory")
		elif SimUnhinged.is_unhinged(u):
			# Chaos agents brag about the murder.
			_react_apply(u, 4.0 * mult, 0.0, "praised")
		else:
			_react_apply(u, -5.0 * mult, 0.0, "disaster")
	elif not at_war:
		_mem.remember(u, "heard_assassination", rid, vname, ufaction,
			0.8 * nudge)
		_react_apply(u, -6.0 * mult * nudge, 0.0, "disaster")
	elif _rival_of(ufaction, kfaction):
		_mem.remember(u, "heard_assassination", rid, vname, ufaction, 0.6)
		_react_apply(u, 4.0 * mult, 0.0, "mocked")
	elif _rival_of(ufaction, vfaction):
		_mem.remember(u, "heard_assassination", rid, vname, ufaction, 0.6)
		_react_apply(u, -4.0 * mult, 0.0, "disaster")
	else:
		_generic_heard(u, r)


## Jeremy 2026-10-08 (hearsay flesh-out): the adventure quest reaction
## matrix. The hero's story is not dead-end news — the realm reacts in
## character, and everything persists as memories + ruler-mood:
##   - hero's own faction: triumphs bring pride ("praised", the tavern
##     roars); failures bring grief ("disaster"); a legend is ecstasy
##     (+8, "heard_legend"); a fallen hero is mourned hard
##     ("friend_died", "heard_hero_fell").
##   - factions at war with the hero's faction: a failure is drinks all
##     round (rivals remember mocking it — "mocked_quest_fail"); a new
##     legend is terrifying (fear, or defiance for brave NPCs — the
##     legend fights for the enemy); a fallen hero is quiet satisfaction
##     ("mocked").
##   - everyone else: admiration for a triumph or legend, sympathy for
##     a failure or a fall.
## Unhinged NPCs feel it 1.5x, matching the other matrices.
func _quest_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var hfaction := String(r.get("hero_faction", ""))
	var hname := String(r.get("hero_name", "the hero"))
	var outcome := String(r.get("quest_outcome", "done"))
	var title := String(r.get("quest_title", "a quest"))
	if hfaction == "":
		_generic_heard(u, r)
		return
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var at_war := _rival_of(ufaction, hfaction)
	if outcome == "legend":
		if ufaction == hfaction:
			_mem.remember(u, "heard_legend", rid, hname, ufaction, 1.0)
			_react_apply(u, 8.0 * mult, 0.0, "praised")
		elif at_war:
			_mem.remember(u, "heard_legend", rid, hname, ufaction, 0.7)
			_react_apply(u, -6.0 * mult, 0.0, "attacked")
		else:
			_mem.remember(u, "heard_legend", rid, hname, ufaction, 0.6)
			_react_apply(u, 2.0 * mult, 0.0, "praised")
		return
	if outcome == "fell":
		if ufaction == hfaction:
			_mem.remember(u, "heard_hero_fell", rid, hname, ufaction, 1.0)
			_react_apply(u, -10.0 * mult, 0.0, "friend_died")
		elif at_war:
			_mem.remember(u, "heard_hero_fell", rid, hname, ufaction, 0.6)
			_react_apply(u, 4.0 * mult, 0.0, "mocked")
		else:
			_mem.remember(u, "heard_hero_fell", rid, hname, ufaction, 0.6)
			_react_apply(u, -4.0 * mult, 0.0, "friend_died")
		return
	if outcome == "failed":
		if ufaction == hfaction:
			_mem.remember(u, "heard_quest_failed", rid, title, ufaction, 0.9)
			_react_apply(u, -6.0 * mult, 0.0, "disaster")
		elif at_war:
			_mem.remember(u, "mocked_quest_fail", rid, title, ufaction, 0.7)
			_react_apply(u, 4.0 * mult, 0.0, "mocked")
		else:
			_mem.remember(u, "heard_quest_failed", rid, title, ufaction, 0.5)
			_react_apply(u, -2.0 * mult, 0.0, "disaster")
		return
	# outcome == "taken": the tavern buzzes BEFORE the outcome — hope at
	# home (the hero might pull it off), mockery across a war border
	# (rivals bet on failure — and remember mocking it when the outcome
	# lands), and wagers everywhere else. Smaller stakes than an
	# outcome: +3/-2-ish moods.
	if outcome == "taken":
		if ufaction == hfaction:
			_mem.remember(u, "heard_quest_taken", rid, title, ufaction, 0.7)
			_react_apply(u, 3.0 * mult, 0.0, "hopeful")
		elif at_war:
			_mem.remember(u, "mocked_quest_take", rid, title, ufaction, 0.6)
			_react_apply(u, 2.0 * mult, 0.0, "mocked")
		else:
			_mem.remember(u, "heard_quest_taken", rid, title, ufaction, 0.4)
			_react_apply(u, 1.0 * mult, 0.0, "hopeful")
		return
	# outcome == "done": the tavern roars at home, grumbles across the
	# border, admires everywhere else.
	if ufaction == hfaction:
		_mem.remember(u, "heard_quest_done", rid, title, ufaction, 0.8)
		_react_apply(u, 5.0 * mult, 0.0, "praised")
	elif at_war:
		_mem.remember(u, "heard_quest_done", rid, title, ufaction, 0.6)
		_react_apply(u, -2.0 * mult, 0.0, "insulted")
	else:
		_mem.remember(u, "heard_quest_done", rid, title, ufaction, 0.5)
		_react_apply(u, 2.0 * mult, 0.0, "praised")


func _surrender_reaction(u: Dictionary, r: Dictionary) -> void:
	var ufaction := String(u.get("faction", ""))
	var loser := String(r.get("loser", ""))
	var winner := String(r.get("winner", ""))
	if loser == "" or winner == "":
		_generic_heard(u, r)
		return
	var done := bool(String(r.get("subject", "")).begins_with("surrendered:"))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var rid := int(r.get("id", 0))
	if ufaction == loser:
		if done:
			_mem.remember(u, "we_surrendered", rid, winner, ufaction, 0.9)
			_react_apply(u, -12.0 * mult, 0.0, "mocked")
		else:
			_mem.remember(u, "surrender_offered", rid, winner, ufaction, 0.7)
			_react_apply(u, -5.0 * mult, 0.0, "attacked")
	elif ufaction == winner:
		if done:
			_mem.remember(u, "enemy_surrendered", rid, loser, ufaction, 0.8)
			_react_apply(u, 12.0 * mult, 0.0, "victory")
		else:
			_mem.remember(u, "surrender_offered_us", rid, loser,
				ufaction, 0.6)
			_react_apply(u, 5.0 * mult, 0.0, "victory")
	else:
		_generic_heard(u, r)


## Jeremy 2026-10-06: the core of the smear pipeline — a hearer reacts to
## a player-sourced smear based on how THEY feel about the TARGET:
##   - hearer IS the target -> furious at the player (strongest reaction)
##   - likes the target -> enraged at the player, may run tell the target
##   - dislikes the target -> amused: likes the player more, spreads faster
##   - neutral -> mild, normal spread
## Unhinged NPCs feel it 1.5x in whichever direction they lean.
## Everything writes real memories + ruler-mood/affection through the
## conversation engine, so grudges persist and surface in later dialogue.
func _smear_reaction(u: Dictionary, r: Dictionary) -> void:
	var uid := int(u.get("id", 0))
	var tid := int(r.get("target_id", 0))
	var tname := String(r.get("target_name", "someone"))
	var tfaction := String(r.get("target_faction", ""))
	var ufaction := String(u.get("faction", ""))
	# The target themselves hears what the player said — furious.
	if tid > 0 and uid == tid:
		_mem.remember(u, "player_smeared_me", tid, tname, ufaction, 1.0)
		_smear_apply(u, -25.0, -15.0, "insulted")
		_smear_grudge(tid, SMEAR_GRUDGE_TARGET)
		return
	var target := {"id": tid, "name": tname, "faction": tfaction,
		"is_leader": bool(r.get("target_is_leader", false))}
	var stance := SimLikesDislikes.npc_stance(u, target, _gs)
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if stance >= 0.3:
		# Defends the target — enraged at the player.
		_mem.remember(u, "player_smeared_friend", tid, tname, ufaction, 0.9)
		_smear_apply(u, -18.0 * mult, -10.0 * mult, "insulted")
		_smear_grudge(uid, SMEAR_GRUDGE_SECONDARY)
		# May run and tell the target directly — then the target knows too.
		if tid > 0 and randf() < 0.35:
			var tu: Dictionary = _gs.get_unit(tid)
			if not tu.is_empty() and bool(tu.get("alive", true)):
				_mem.remember(tu, "player_smeared_me", tid, tname,
					String(tu.get("faction", "")), 0.8)
				_smear_apply(tu, -12.0, -8.0, "insulted")
				_smear_grudge(tid, SMEAR_GRUDGE_SECONDARY)
	elif stance <= -0.3:
		# Finds it funny — warms to the player, spreads it faster/farther.
		_mem.remember(u, "player_roasted_enemy", tid, tname, ufaction, 0.7)
		_smear_apply(u, 10.0 * mult, 8.0 * mult, "liked_topic")
		r["heat"] = minf(1.0, float(r.get("heat", 0.0)) + 0.1)
	else:
		# Neutral on the target — mild, normal spread.
		_mem.remember(u, "heard_rumor", int(r.get("id", 0)), "smear",
			ufaction, 0.4)


## Apply a rumor reaction: persistent ruler-mood + player-affection via
## the conversation engine (the same scales dialogue reads), plus a raw
## emotion. Guarded for bare-sim tests without a phone.
func _react_apply(u: Dictionary, mood_delta: float, aff_delta: float,
		emotion: String) -> void:
	if phone != null:
		var conv = phone.get("conversation")
		if conv != null and conv.has_method("bump_ruler_mood"):
			conv.bump_ruler_mood(int(u.get("id", 0)), mood_delta)
			conv.bump_affection(int(u.get("id", 0)), aff_delta)
	if _emo != null:
		_emo.notify(u, emotion)


## The smear path's mood/affection application — now a thin wrapper over
## the generic reaction applier (war news uses the same engine).
func _smear_apply(u: Dictionary, mood_delta: float, aff_delta: float,
		emotion: String) -> void:
	_react_apply(u, mood_delta, aff_delta, emotion)


## Jeremy 2026-10-10 (hearsay flesh-out): rumor-borne fury feeds the
## conversation grudge ledger — the emotional arc completes: smear ->
## grudge -> apology -> forgiveness. The ledger's decay and apology
## thresholds then apply to rumor offenses exactly as they do to chat
## insults, and the grudge persists through save/load. Guarded for
## bare-sim tests without a phone.
func _smear_grudge(unit_id: int, pts: float) -> void:
	if phone == null:
		return
	var conv = phone.get("conversation")
	if conv != null and conv.has_method("add_grudge"):
		conv.add_grudge(unit_id, pts, _gs)


## Jeremy 2026-10-08 (hearsay flesh-out): the NPC-sourced smear reaction.
## A lie invented by a fellow citizen — the target is furious at the LIAR
## (named in the memory; taverns always know who started it — grudge
## fuel for later dialogue), everyone else just gossips. The player is
## never blamed: only player_sourced smears route to _smear_reaction.
func _npc_smear_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var uid := int(u.get("id", 0))
	var tid := int(r.get("target_id", 0))
	if tid > 0 and uid == tid:
		var sname := String(r.get("source_name", ""))
		if sname == "":
			sname = "someone"
		_mem.remember(u, "npc_smeared_me", tid, sname,
			String(u.get("faction", "")), 1.0)
		if _emo != null:
			_emo.notify(u, "insulted")
		return
	_generic_heard(u, r)


## Jeremy 2026-10-08 (hearsay flesh-out): the gossip reaction matrix.
## Yapper-grade tavern talk names a citizen ("gossip:<unit_id>" subject
## — parsed here, so the mill never touches disasters.gd). The victim
## is mortified (proud NPCs take mockery as anger, via SimEmotion), a
## rival cackles at the laughingstock, a friend defends them and takes
## offense on their behalf, and neutrals are just mildly amused by the
## tavern talk. Laughers and defenders are remembered BY VICTIM, so the
## town's social temperature toward them shifts (see REL_WEIGHT) and the
## conversation engine can quote it back ("Remember when they gossiped
## about you? I hated it." — HTML p13CitizenMemoryLine parity). An
## unparsable subject (old saves) falls back to the generic reception.
func _gossip_victim_id(r: Dictionary) -> int:
	var subj := String(r.get("subject", ""))
	if subj.begins_with("gossip:"):
		return int(subj.get_slice(":", 1))
	return 0


func _gossip_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var uid := int(u.get("id", 0))
	var vid := _gossip_victim_id(r)
	if vid <= 0:
		_generic_heard(u, r)
		return
	var victim: Dictionary = _gs.get_unit(vid)
	var vname := "someone"
	var vfact := ""
	if not victim.is_empty():
		vname = SimPersonality.display_name(victim)
		if vname == "":
			vname = String(victim.get("name", "someone"))
		vfact = String(victim.get("faction", ""))
	var rid := int(r.get("id", 0))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if uid == vid:
		# The talk is about YOU — mortified in front of the whole town.
		_mem.remember(u, "gossiped_about_me", vid, vname,
			String(u.get("faction", "")), 1.0)
		_react_apply(u, -12.0 * mult, 0.0, "mocked")
		return
	var stance := 0.0
	if not victim.is_empty():
		stance = SimLikesDislikes.npc_stance(u, victim, _gs)
	if stance >= 0.3:
		# A friend is the laughingstock — defend them, offended on
		# their behalf. The town remembers who stood up.
		_mem.remember(u, "defended_gossip_victim", vid, vname, vfact, 0.8)
		_react_apply(u, -6.0 * mult, 0.0, "insulted")
	elif stance <= -0.3:
		# A rival is the laughingstock — cackle. The town remembers
		# who laughed, and thinks a little less of the victim for it.
		_mem.remember(u, "mocked_gossip_victim", vid, vname, vfact, 0.7)
		_react_apply(u, 8.0 * mult, 0.0, "liked_topic")
	else:
		# Neutral — tavern talk is just fun. Mild memory, mild mood.
		_mem.remember(u, "heard_rumor", rid, "gossip",
			String(u.get("faction", "")), 0.45)
		_react_apply(u, 3.0 * mult, 0.0, "")


## Jeremy 2026-10-06: ASSFACE aftermath reaction — everyone finds the
## prank spree funny (amused, mocking). Proud/haughty NPCs are scandalized
## instead, for comedy. Never anger at Assface, no ruler-mood changes.
func _assface_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var persona := SimPersonality.persona_of(u)
	var stuffy := persona == "proud" or persona == "haughty" \
		or SimPersonality.trait_of(u, "proud") >= 0.6
	if stuffy:
		_mem.remember(u, "assface_scandalized", rid, "assface", ufaction, 0.7)
	else:
		_mem.remember(u, "heard_rumor", rid, "assface", ufaction, 0.8)
	if _emo != null:
		_emo.notify(u, "grossed_out" if stuffy else "helped")


## An NPC doubted a rumor: they remember their skepticism (the
## conversation engine can surface "I don't believe a word of it"), and
## their doubt is RECORDED — doubt is contagious, so future hearers
## believe a scoffed-at rumor a little less (see _belief). Proud skeptics
## scoff publicly instead of doubting quietly.
func _on_doubted(u: Dictionary, r: Dictionary, teller: Dictionary) -> void:
	if _mem == null:
		return
	var uid := int(u.get("id", 0))
	var doubters: Array = r.get("doubters", [])
	if uid > 0 and not doubters.has(uid) and doubters.size() < DOUBT_TRACK_CAP:
		doubters.append(uid)
		r["doubters"] = doubters
	var persona := SimPersonality.persona_of(u)
	var stuffy := persona == "proud" or persona == "haughty" \
		or SimPersonality.trait_of(u, "proud") >= 0.6
	if stuffy:
		_mem.remember(u, "scoffed_at_rumor", int(r.get("id", 0)),
			String(r.get("kind", "misc")), String(u.get("faction", "")), 0.7)
	else:
		_mem.remember(u, "doubted_rumor", int(r.get("id", 0)),
			String(r.get("kind", "misc")), String(u.get("faction", "")), 0.5)


## An NPC witnessed an event firsthand: they join the rumor as a knower
## immediately (no waiting for the grapevine) with a memory of it.
## Replaces the old bus.unit_said reaction shouts, which became no-ops
## when speech bubbles were removed — witnessing keeps the sim honest.
func _witness(u: Dictionary, r: Dictionary) -> void:
	var uid := int(u.get("id", 0))
	var knowers: Array = r["knowers"]
	if not knowers.has(uid):
		knowers.append(uid)
		_on_heard(u, r, {})
	# Jeremy 2026-10-06 (hearsay flesh-out): a witness SAW it happen —
	# tracked separately from second-hand knowers so _belief can weigh
	# first-hand testimony. Witnesses remember it as something they saw,
	# not just something they heard.
	var wits: Array = r.get("witnesses", [])
	if not wits.has(uid):
		wits.append(uid)
		r["witnesses"] = wits
		if _mem != null:
			_mem.remember(u, "witnessed_rumor", int(r.get("id", 0)),
				String(r.get("kind", "misc")),
				String(u.get("faction", "")), 0.9)


## Telephone game: a spread rumor may mutate a little. Capped per rumor.
func _maybe_distort(r: Dictionary) -> void:
	if int(r.get("distortions", 0)) >= MAX_DISTORTIONS:
		return
	if randf() > 0.25:
		return
	var text := String(r.get("text", ""))
	var mutated := _distort_text(text)
	if mutated != text:
		r["text"] = mutated
		r["distortions"] = int(r.get("distortions", 0)) + 1


## One distortion step: first matching swap wins (never re-applies an
## already-present replacement), else a tavern-style suffix.
func _distort_text(text: String) -> String:
	for pair in DISTORT_SWAPS:
		var find := String(pair[0])
		var repl := String(pair[1])
		if text.contains(find) and not text.contains(repl):
			return text.replace(find, repl)
	return text + String(DISTORT_SUFFIX[randi() % DISTORT_SUFFIX.size()])


## Hot rumors reach the crown as a DM from a named citizen.
## Jeremy 2026-10-06: conversation-system integration — the rumor mill
## shares Living Lexicon state with Messenger/Squabble. Returns a random
## player-taught word {word, meaning} for tellers to show off, or {}.
func _lexicon_showoff_word() -> Dictionary:
	var lx = _gs.get("lexicon")
	if lx == null:
		return {}
	var fresh: Array = []
	for w: Dictionary in lx.taught_words():
		if not bool(w.get("seed", false)) \
				and String(w.get("word", "")) != "":
			fresh.append(w)
	if fresh.is_empty():
		return {}
	return fresh[randi() % fresh.size()]


func _maybe_reach_ruler(r: Dictionary) -> void:
	if bool(r.get("reached_ruler", false)):
		return
	if float(r.get("heat", 0.0)) < RULER_HEAT:
		return
	if phone == null or not phone.has_method("npc_message"):
		return
	var knowers: Array = r["knowers"]
	var teller: Dictionary = {}
	for kid: Variant in knowers:
		var u: Dictionary = _gs.get_unit(int(kid))
		if u.is_empty():
			continue
		if phone.has_method("is_blocked") and bool(phone.is_blocked(int(u.get("id", 0)))):
			continue
		teller = u
		break
	if teller.is_empty():
		return
	r["reached_ruler"] = true
	# Jeremy 2026-10-04: moods in hearsay — the teller's mood colors
	# HOW they deliver the rumor, and the DM notes their mood:
	# "[Name] (angry) says: ...".
	var teller_mood := SimMood.new().dominant(teller)
	var mood_pool: Array = MOOD_GOSSIP_OPENERS.get(teller_mood,
		MOOD_GOSSIP_OPENERS["neutral"])
	var opener: String = mood_pool[randi() % mood_pool.size()]
	var teller_name := SimPersonality.display_name(teller)
	var msg: String = "[%s] (%s) says: %s" % [teller_name, teller_mood,
		opener.replace("{t}", String(r.get("text", "")))]
	# Jeremy 2026-10-06: gossip carries Living Lexicon state — the teller
	# shows off a player-taught word while delivering the rumor, so the
	# rumor mill visibly shares vocabulary with Messenger and Squabble.
	var sw := _lexicon_showoff_word()
	if not sw.is_empty() and randf() < 0.5:
		var sw_mean := String(sw.get("meaning", "")).left(50)
		if sw_mean == "":
			sw_mean = "something clever"
		msg += " Oh, and get this — I learned the word '%s'. It means '%s'!" \
			% [String(sw.get("word", "")), sw_mean]
	phone.npc_message(int(teller.get("id", 0)), msg)


## Hottest-first, for the 🔮 Hearsay view.
func live_rumors(limit: int = 12) -> Array:
	var arr: Array = (state["rumors"] as Array).duplicate()
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("heat", 0.0)) > float(b.get("heat", 0.0)))
	return arr.slice(0, limit)


## Display lines for the Hearsay screen (flavor + freshness).
func hearsay_lines(limit: int = 8) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in live_rumors(limit):
		var heat: float = float(r.get("heat", 0.0))
		var mark: String = "🔥" if heat >= 0.7 else ("👂" if heat >= 0.4 else "💭")
		var suffix := ""
		if bool(r.get("debunked", false)):
			suffix = " (debunked)"
		elif bool(r.get("verified", false)):
			suffix = " (confirmed)"
		out.append("%s %s%s" % [mark, String(r.get("text", "")), suffix])
	return out


## Jeremy 2026-10-08 (hearsay flesh-out): a citizen invents a malicious
## lie about someone they dislike. Returns true when a lie was seeded.
## Lies need motive (stance <= -0.3) and a live target; one live lie per
## target (dedup on the subject). Seeded UNTRUE — the only rumors the
## crown's investigators can debunk. HARD LINE: the invented text is
## fantasy tavern talk, and the final line is hate-slur guarded anyway.
func _seed_malicious_smear() -> bool:
	var liar: Dictionary = _random_citizen("")
	if liar.is_empty():
		return false
	var lid := int(liar.get("id", 0))
	if lid <= 0:
		return false
	var target: Dictionary = {}
	for i in 12:
		var cand: Dictionary = _random_citizen("")
		if cand.is_empty() or int(cand.get("id", 0)) == lid:
			continue
		if SimLikesDislikes.npc_stance(liar, cand, _gs) <= -0.3:
			target = cand
			break
	if target.is_empty():
		return false
	var tid := int(target.get("id", 0))
	var tname := SimPersonality.display_name(target)
	if tname == "":
		return false
	var line: String = String(
		FALSE_SMEAR_LINES[randi() % FALSE_SMEAR_LINES.size()])
	line = line.replace("{t}", tname)
	if SimHateSpeech.is_hate_slur(line):
		return false
	var subject := "smear:%d" % tid
	var existed := not _live_rumor("smear", subject).is_empty()
	# Knower-less seed (the seed_player_smear pattern): the target
	# fields must be stamped before the first _on_heard, or _rep_tick
	# can't see the target on the very first hear.
	var r := seed_rumor(line, "smear", subject, 0.65, -1, false,
		TRUTH_FALSE)
	if not existed:
		r["player_sourced"] = false
		r["source_id"] = lid
		r["source_name"] = SimPersonality.display_name(liar)
		r["target_id"] = tid
		r["target_name"] = tname
		r["target_faction"] = String(target.get("faction", ""))
		r["target_is_leader"] = bool(target.get("is_leader", false))
	# The liar heard their own lie — firsthand.
	var liar_u: Dictionary = _gs.get_unit(lid)
	if not liar_u.is_empty():
		var hk: Array = r["knowers"]
		if not hk.has(lid):
			hk.append(lid)
		_on_heard(liar_u, r, {})
	return true


func _seed_npc_life() -> void:
	var u: Dictionary = _random_citizen("")
	if u.is_empty():
		return
	# Jeremy 2026-10-08 (hearsay flesh-out): once in a while the tavern
	# talk isn't idle chatter — someone invents a lie about a rival.
	if randf() < 0.10 and _seed_malicious_smear():
		return
	var pf: String = _gs.player_faction
	var town: String = "the realm"
	var tid: int = int(u.get("town_id", -1))
	if _gs.towns.has(tid):
		town = String((_gs.towns[tid] as Dictionary).get("name", town))
	var line: String = NPC_LIFE_LINES[randi() % NPC_LIFE_LINES.size()]
	line = line.replace("{d}", str(_gs.day_number))
	line = line.replace("{j}", String(u.get("job", "peasant")))
	line = line.replace("{t}", town)
	line = line.replace("{f}", String(u.get("faction", "folk")).capitalize())
	# Jeremy 2026-10-06 (lane 6): sometimes the tavern talk is about a
	# hidden cache instead — those rumors can spawn an expedition.
	if randf() < 0.12:
		var cline: String = CACHE_LINES[randi() % CACHE_LINES.size()]
		seed_rumor(cline, "cache", "", 0.55, int(u.get("id", 0)))
		return
	seed_rumor(line, "life", "", 0.45, int(u.get("id", 0)))

## --- sim-event -> Squabble posts (HTML sqbGenDeeds / sqbOnWarDeclared) ---------

func _random_author() -> Dictionary:
	var pf: String = _gs.player_faction
	var cands: Array = []
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == pf:
			cands.append(u)
	if cands.is_empty():
		for u2: Dictionary in _gs.units:
			if u2.get("alive", false):
				cands.append(u2)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


func _random_citizen(prefer_faction: String) -> Dictionary:
	var cands: Array = []
	var fallback: Array = []
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if phone != null and phone.has_method("is_blocked") \
				and bool(phone.is_blocked(int(u.get("id", 0)))):
			continue  # blocked citizens are out of the grapevine
		if prefer_faction != "" and String(u.get("faction", "")) == prefer_faction:
			cands.append(u)
		else:
			fallback.append(u)
	if not cands.is_empty():
		return cands[randi() % cands.size()]
	if not fallback.is_empty():
		return fallback[randi() % fallback.size()]
	return {}


func _event_post(lines: Array, kind: String, fill: Dictionary,
		faction_lines: Dictionary = {}) -> void:
	if phone == null or not phone.has_method("npc_post"):
		return
	var author: Dictionary = _random_author()
	if author.is_empty():
		return
	# Jeremy 2026-10-05: prefer the author's faction voice when available.
	var pool: Array = lines
	var af: String = String(author.get("faction", ""))
	if not faction_lines.is_empty() and faction_lines.has(af):
		var fl: Array = faction_lines[af]
		if not fl.is_empty() and randf() < 0.65:
			pool = fl
	# Jeremy 2026-10-06: avoid posting the same line twice in a row —
	# try up to 8 picks to find a fresh one.
	var line: String = ""
	for attempt in 8:
		var candidate: String = String(pool[randi() % pool.size()])
		for k: String in fill.keys():
			candidate = candidate.replace("{%s}" % k, String(fill[k]))
		if not candidate in _recent_lines:
			line = candidate
			break
		line = candidate  # fallback: use last pick if all are recent
	if line == "":
		return
	_recent_lines.append(line)
	if _recent_lines.size() > 12:
		_recent_lines.pop_front()
	phone.npc_post(author, line, kind)


func _faction_name(f: String) -> String:
	return String(Config.FACTIONS.get(f, {}).get("name", f))


## HTML sqbOnWarDeclared: a ruler-voice post the moment war breaks out.
func _on_war_declared(faction_a: String, faction_b: String) -> void:
	var other: String = faction_b if faction_a == _gs.player_faction else faction_a
	_event_post(WAR_LINES, "war", {"f": _faction_name(other)}, WAR_LINES_FACTION)
	var r := seed_rumor("WAR with the %s! The drums beat day and night." % _faction_name(other),
		"war", other, 1.0, -1, false, TRUTH_TRUE)
	# Jeremy 2026-10-07 (hearsay flesh-out): the grapevine must know WHO
	# declared on WHOM — faction_a declared war on faction_b — so hearers
	# react in character (attacked side fears, attacking side rallies).
	# Dedup refreshes keep the newest declaration's sides.
	r["side_a"] = faction_a
	r["side_b"] = faction_b
	# Jeremy 2026-10-08 (hearsay flesh-out): the war is real now — retire
	# the plot rumor. On the merge path (same subject) just clear the
	# plot flags so hearers route to the full war matrix; on the split
	# path (war ON the player — subject is the player's faction) cool
	# the stale plot rumor so taverns stop plotting a war that's begun.
	r["war_plot"] = false
	r["plot_denied"] = false
	var stale: Dictionary = _live_rumor("war", faction_a)
	if not stale.is_empty() \
			and bool(stale.get("war_plot", false)) \
			and int(stale.get("id", -1)) != int(r.get("id", -2)):
		stale["war_plot"] = false
		stale["plot_denied"] = false
		stale["heat"] = minf(float(stale.get("heat", 0.0)), 0.3)


func _on_disaster(kind: String, _pos: Vector2) -> void:
	# Jeremy 2026-10-04: THE NASTY MONASTERY gets its own arrival fanfare.
	if kind == "nasty_priest":
		_on_priest_arrival(_pos)
		return
	# Jeremy 2026-10-09 (hearsay flesh-out): a nuclear blast is not
	# weather — it gets its own rumor shape (hit town + launcher named,
	# realm-wide awe, dread instead of mockery) instead of the generic
	# "A nuke rampages through {town}!" line.
	if kind == "nuke":
		_on_nuke_detonation(_pos)
		return
	var dname: String = kind.replace("_", " ")
	# Jeremy 2026-10-07 (hearsay flesh-out): disasters name their victim —
	# the town under the impact is recorded so hearers react in character
	# (victims panic, war-rivals laugh, allies grieve) instead of every
	# NPC getting the same generic scare. Dedup refreshes update the
	# fields: the taverns name the NEWEST stricken town.
	var hit := _town_at(_pos)
	var hit_name := String(hit.get("name", "the realm"))
	_event_post(DISASTER_LINES, "disaster",
		{"d": "a " + dname, "t": hit_name})
	var dr: Dictionary = seed_rumor("A %s rampages through %s!" % [dname, hit_name],
		"disaster", kind, 0.85, -1, false, TRUTH_TRUE)
	if not hit.is_empty():
		dr["hit_faction"] = String(hit.get("faction", ""))
		dr["hit_town"] = hit_name
		dr["text"] = "A %s rampages through %s!" % [dname, hit_name]
		dr["text_orig"] = String(dr["text"])
	# Jeremy 2026-10-04: nearby NPCs are scared when a disaster spawns
	# (HTML scareNearby parity). The moose gets its own handler below.
	if kind == "thicc_moose":
		return  # mooning reactions handled by _on_moose_mooned
	# Jeremy 2026-10-06: the spoken reactions used to ride bus.unit_said,
	# which has been a no-op since the 2026-10-05 bubble ban — nearby NPCs'
	# terror silently vanished. Witnesses now join the rumor as knowers
	# with a real memory instead of shouting into the void.
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if upos.distance_to(_pos) > 300.0:
			continue
		_witness(u, dr)


## Jeremy 2026-10-09 (hearsay flesh-out): the sun-bomb's own detonation
## rumor. Records the stricken town AND the firing faction (stashed from
## the Gazette story that published moments earlier — old saves get a
## launcher-less blast, still awe-struck). Heat 0.95: press-eligible and
## ruler-reaching — a sun-bomb is front-page news. Truth TRUE: the sky
## burned, nobody debates it. Survivors of the hit faction within 1500px
## join as witnesses (the flash was visible realm-wide); the blast
## radius is 720 and the dead don't gossip.
func _on_nuke_detonation(pos: Vector2) -> void:
	var hit := _town_at(pos)
	var hit_name := String(hit.get("name", "the realm"))
	var hit_faction := String(hit.get("faction", ""))
	var launcher := _pending_nuke_launcher
	_pending_nuke_launcher = ""
	var r: Dictionary = seed_rumor(
		"A second sun died screaming over %s!" % hit_name,
		"disaster", "nuke", 0.95, -1, false, TRUTH_TRUE)
	if not hit.is_empty():
		r["hit_faction"] = hit_faction
		r["hit_town"] = hit_name
		r["text"] = "A second sun died screaming over %s!" % hit_name
		r["text_orig"] = String(r["text"])
	r["nuke"] = true
	# Always stamp — a launcher-less blast (old saves, story-less paths)
	# clears a stale launcher from a refreshed rumor rather than
	# inheriting it.
	r["nuke_launcher"] = launcher
	for u2: Dictionary in _gs.units:
		if not bool(u2.get("alive", false)):
			continue
		if hit_faction == "" \
				or String(u2.get("faction", "")) != hit_faction:
			continue
		var upos2: Vector2 = u2.get("position", Vector2.ZERO)
		if upos2.distance_to(pos) > 1500.0:
			continue
		_witness(u2, r)
	_nuke_squabble_posts(hit_name, launcher)


## Jeremy 2026-10-09 (hearsay flesh-out): the loosed sun-spear's own
## rumor. The launcher is named, truth is TRUE (every court felt the
## tremor), heat 1.0: the whole realm dreads the climbing spear — nobody
## knows where it lands. Dedup by launcher: a second launch refreshes
## the dread instead of doubling it.
func _seed_nuke_launch(faction: String) -> void:
	var fname := _faction_name(faction)
	var r: Dictionary = seed_rumor(
		"The %s have loosed a sun-spear — every court felt the ground tremble." % fname,
		"war", "nuke_launch:" + faction, 1.0, -1, false, TRUTH_TRUE)
	r["nuke_launch"] = true
	r["nuke_launcher"] = faction
	r["text_orig"] = String(r["text"])
	_event_post(NUKE_LAUNCH_LINES, "war", {"f": fname})


## Squabble posts about the blast (HTML sqbGenDeeds parity — the realm
## posts its awe and horror, never tavern comedy about a sun-bomb).
func _nuke_squabble_posts(hit_name: String, launcher: String) -> void:
	var lname := _faction_name(launcher) if launcher != "" else "someone"
	_event_post(NUKE_LINES, "disaster",
		{"t": hit_name, "l": lname})


## Jeremy 2026-10-09 (hearsay flesh-out): the sun-bomb reaction matrix.
## A nuke is not weather — even the enemy falls silent:
##   - hearer in the HIT faction -> terror + awe: the sky caught fire
##     over OUR town (mood -12x, "disaster", "nuke_hit_us").
##   - hearer in the LAUNCHER's faction -> grim pride: our spear flew
##     true (+4x, "victory", "nuke_our_spear").
##   - hearer at war/hostile with the hit faction -> DREAD, not mockery:
##     a sun-bomb does not amuse; it warns (-4x, "disaster",
##     "nuke_dread").
##   - everyone else -> awe-horror: they watched the second sun die
##     (-3x, "disaster", "saw_sun_die").
## A blast with no town in range still awes the realm. Unhinged NPCs
## feel it 1.5x, matching the other matrices. Persists as memories +
## ruler-mood so the dread surfaces in later talk.
func _nuke_blast_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var hit := String(r.get("hit_faction", ""))
	var launcher := String(r.get("nuke_launcher", ""))
	var ufaction := String(u.get("faction", ""))
	var rid := int(r.get("id", 0))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if hit != "" and ufaction == hit:
		_mem.remember(u, "nuke_hit_us", rid, hit, ufaction, 1.0)
		_react_apply(u, -12.0 * mult, 0.0, "disaster")
	elif launcher != "" and ufaction == launcher:
		_mem.remember(u, "nuke_our_spear", rid, launcher, ufaction, 0.8)
		_react_apply(u, 4.0 * mult, 0.0, "victory")
	elif hit != "" and _rival_of(ufaction, hit):
		_mem.remember(u, "nuke_dread", rid, hit, ufaction, 0.8)
		_react_apply(u, -4.0 * mult, 0.0, "disaster")
	else:
		_mem.remember(u, "saw_sun_die", rid, hit, ufaction, 0.7)
		_react_apply(u, -3.0 * mult, 0.0, "disaster")


## Jeremy 2026-10-09 (hearsay flesh-out): the sun-spear launch matrix.
## Nobody knows where the spear lands — the whole realm dreads it:
##   - hearer in the LAUNCHER's faction -> grim anticipation: our spear
##     flies (+3x, "victory", "nuke_our_spear").
##   - everyone else -> dread: a sun-spear is climbing and it is not
##     aimed at the launcher (-6x, "disaster", "nuke_spear_inbound").
## Unhinged 1.5x. Persists as memories + ruler-mood.
func _nuke_launch_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var launcher := String(r.get("nuke_launcher", ""))
	var ufaction := String(u.get("faction", ""))
	var rid := int(r.get("id", 0))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if launcher != "" and ufaction == launcher:
		_mem.remember(u, "nuke_our_spear", rid, launcher, ufaction, 0.8)
		_react_apply(u, 3.0 * mult, 0.0, "victory")
	else:
		_mem.remember(u, "nuke_spear_inbound", rid, launcher, ufaction, 0.9)
		_react_apply(u, -6.0 * mult, 0.0, "disaster")


## A still-warm rumor by kind+subject, or {} — lets event handlers share
## one rumor across a whole outbreak instead of re-seeding per ignition.
func _live_rumor(kind: String, subject: String) -> Dictionary:
	for r2: Dictionary in state["rumors"]:
		if String(r2.get("kind", "")) == kind \
				and String(r2.get("subject", "")) == subject:
			return r2
	return {}


## Jeremy 2026-10-07 (hearsay flesh-out): the town a disaster/wildfire
## struck, if any — the nearest town record within 700px of the impact.
## Lane-pure (no towns-sim changes): reads _gs.towns directly, which is
## always populated by the time disasters fire. Towns are ~15 at most,
## so the linear scan is trivially cheap at the 240-unit cap.
func _town_at(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 700.0
	if _gs == null:
		return best
	for tid in _gs.towns.keys():
		var t: Dictionary = _gs.towns[tid]
		var d: float = pos.distance_to(t.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = t
	return best


## Jeremy 2026-10-06 (hearsay flesh-out): wildfires were the weakest
## hearsay thread — a disaster-class event with zero grapevine presence
## (no disaster_spawned bus emit, only a DisasterLog record). Fires now
## seed a real rumor: Squabble posts, first-hand witnesses near the
## flames, full reception (memory + scared emotion) for every knower.
## Ignitions within one outbreak share a single ("disaster",
## "wildfire") rumor — a spreading fire refreshes the talk instead of
## spamming it, and fresh witnesses still join the shared rumor.
func _on_fire_started(f: Dictionary) -> void:
	var pos: Vector2 = f.get("position", Vector2.ZERO)
	var fr: Dictionary = _live_rumor("disaster", "wildfire")
	# Jeremy 2026-10-07 (hearsay flesh-out): wildfires name their victim
	# too — record the stricken town on the shared outbreak rumor so the
	# reaction matrix can panic/laugh/grieve in character.
	var hit := _town_at(pos)
	var hit_faction := String(hit.get("faction", ""))
	var hit_name := String(hit.get("name", ""))
	if fr.is_empty():
		_event_post(FIRE_LINES, "disaster", {})
		var ftext := "A wildfire rages through the realm — smoke on the horizon, beasts fleeing ahead of the flames!"
		if hit_name != "":
			ftext = "A wildfire rages through %s — smoke on the horizon, beasts fleeing ahead of the flames!" % hit_name
		fr = seed_rumor(ftext, "disaster", "wildfire", 0.85, -1, false, TRUTH_TRUE)
	else:
		# The outbreak is already the talk of the taverns — fresh smoke
		# just keeps it hot. seed_rumor's dedup would do the same, but
		# this also skips a second Squabble post for the same fire.
		fr["heat"] = maxf(float(fr.get("heat", 0.0)), 0.85)
		if hit_name != "":
			fr["text"] = "A wildfire rages through %s — smoke on the horizon, beasts fleeing ahead of the flames!" % hit_name
			fr["text_orig"] = String(fr["text"])
	if hit_faction != "":
		fr["hit_faction"] = hit_faction
		fr["hit_town"] = hit_name
	# Nearby NPCs see the flames with their own eyes — first-hand
	# witnesses (the same 300px terror radius as disaster_spawned).
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if upos.distance_to(pos) > 300.0:
			continue
		_witness(u, fr)


## Monthly disaster forecast posted (HTML: '📅 Monthly disaster forecast
## posted on the calendar.'). The realm gossips about what's coming.
func _on_forecast_posted(entries: Dictionary) -> void:
	if entries.is_empty():
		return
	var days: Array = entries.keys()
	days.sort()
	var bits: Array[String] = []
	for d in days:
		var e: Dictionary = entries[d]
		bits.append("%s on day %d" % [String(e.get("label", "?")), int(d)])
	var summary: String = ", ".join(bits)
	_event_post(FORECAST_LINES, "forecast", {"e": summary})
	seed_rumor("The seers foretell: %s." % summary, "forecast", "", 0.6, -1, false, TRUTH_TRUE)


## A forecast disaster fired mid-day (HTML: '📅 FORECAST EVENT: ' + label).
func _on_forecast_fired(label: String) -> void:
	_event_post(FORECAST_FIRED_LINES, "forecast", {"l": label})
	seed_rumor("The forecast came true: %s!" % label, "forecast", "", 0.7, -1, false, TRUTH_TRUE)


## Jeremy 2026-10-04: THE NASTY MONASTERY — Father Filthwick opens his
## monastery. The town is cautiously optimistic. For now.
func _on_priest_arrival(pos: Vector2) -> void:
	var town_name := "the realm"
	var best_d2 := 1e18
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = pos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			town_name = String(td.get("name", town_name))
	var line: String = NastyPriestData.ARRIVAL_LINES[
		randi() % NastyPriestData.ARRIVAL_LINES.size()]
	line = line.replace("{t}", town_name)
	_event_post([line], "disaster", {})
	seed_rumor("Father Filthwick opened a monastery in %s." % town_name,
		"nasty_priest", "nasty_priest", 0.7, -1, false, TRUTH_TRUE)


## Jeremy 2026-10-04: THE NASTY MONASTERY — Father Filthwick bursts out
## screaming. Nearby NPCs react with panic and disgust, it hits Squabble,
## and it becomes a rumor the realm remembers.
func _on_priest_burst(priest_id: int, pos: Vector2, outburst: String) -> void:
	# Seed first so witnesses can join as knowers (dedup keeps one
	# rumor per visit — the grapevine doesn't need six copies).
	var pr: Dictionary = seed_rumor(
		"Father Filthwick burst out of his monastery screaming \"%s\"! The town is traumatized." % outburst,
		"nasty_priest", "nasty_priest", 0.9, -1, false, TRUTH_TRUE)
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if int(u.get("id", -1)) == priest_id:
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if upos.distance_to(pos) > 320.0:
			continue
		# Panic or disgust, roughly fifty-fifty.
		if randf() < 0.5:
			_emo.notify(u, "disaster")       # scared = panic
		else:
			_emo.notify(u, "grossed_out")    # disgusted
		# They remember him. Oh, they remember him.
		_mem.remember(u, "harassed_by", priest_id,
			NastyPriestData.PRIEST_NAME, "monster", 0.9)
		# Jeremy 2026-10-06: the old 45% bubble shouts are no-ops since
		# the bubble ban — witnesses join the rumor instead.
		if randf() < 0.45:
			_witness(u, pr)
	_priest_squabble_posts(pos, outburst)


## Squabble posts about the latest outburst + NPC replies.
func _priest_squabble_posts(pos: Vector2, outburst: String) -> void:
	if phone == null or not phone.has_method("npc_post"):
		return
	var author: Dictionary = _random_author()
	if author.is_empty():
		return
	var town_name := "the realm"
	var best_d2 := 1e18
	for t: Variant in _gs.towns.values():
		var td: Dictionary = t
		var d2: float = pos.distance_squared_to(
			td.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			town_name = String(td.get("name", town_name))
	var line: String = NastyPriestData.SQB_LINES[
		randi() % NastyPriestData.SQB_LINES.size()]
	line = line.replace("{t}", town_name)
	line = line.replace("{d}", str(_gs.day_number))
	line = line.replace("{q}", outburst.left(60))
	var post: Dictionary = phone.npc_post(author, line, "disaster")
	var post_id: int = int(post.get("id", -1))
	if post_id >= 0 and phone.has_method("npc_comment"):
		var replies: int = 2 + randi() % 2
		for i: int in replies:
			var replier: Dictionary = _random_author()
			if replier.is_empty():
				continue
			var rline: String = NastyPriestData.SQB_REPLIES[
				randi() % NastyPriestData.SQB_REPLIES.size()]
			phone.npc_comment(post_id, replier, rline)


## Jeremy 2026-10-04: thicc moose mooning reactions (HTML moonGrossOut /
## scareNearby port). Nearby NPCs react with faction-appropriate lines and
## emotions, it hits Squabble, and it becomes a rumor.
func _on_moose_mooned(hall: Dictionary) -> void:
	var hpos: Vector2 = hall.get("position", Vector2.ZERO)
	var town_name: String = String(hall.get("name", "the town hall"))
	# 3. Rumor: the mooning becomes gossip. (Seeded first so witnesses
	# can join it as knowers below.)
	var mr: Dictionary = seed_rumor(
		"The thicc moose mooned %s! Half the town saw its butt." % town_name,
		"moose_moon", town_name, 0.9, -1, false, TRUTH_TRUE)
	# 1. Nearby NPCs react (HTML: 240 range). The old 55% bubble shouts
	# are no-ops since the bubble ban — witnesses instead join the rumor
	# with faction-appropriate emotion and a real memory (Jeremy 2026-10-06).
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if upos.distance_to(hpos) > 240.0:
			continue
		var faction: String = String(u.get("faction", ""))
		# Faction-appropriate emotion (Jeremy 2026-10-04 spec).
		match faction:
			"ogres", "gnomes":
				_emo.notify(u, "helped")  # laughed -> happy
			"elves":
				_emo.notify(u, "disaster")  # horrified -> scared
			"humans":
				_emo.notify(u, "mocked")  # embarrassed -> sad
			_:
				pass  # undead: unimpressed, no strong emotion
		if randf() < 0.55:
			_witness(u, mr)
	# 2. Squabble: NPCs post about it, then reply to each other.
	_moose_squabble_posts(town_name)


## Faction-specific mooning reaction lines.
func _moose_react_lines(faction: String) -> Array:
	match faction:
		"ogres":
			return MOOSE_REACT_OGRES
		"elves":
			return MOOSE_REACT_ELVES
		"gnomes":
			return MOOSE_REACT_GNOMES
		"humans":
			return MOOSE_REACT_HUMANS
		"undead":
			return MOOSE_REACT_UNDEAD
	return MOOSE_REACT_GENERIC


## Disaster-specific reaction line for a speech bubble.
func _disaster_react_line(kind: String) -> String:
	var lines: Array = DISASTER_REACT_LINES.get(kind, DISASTER_REACT_GENERIC)
	return String(lines[randi() % lines.size()])


## Squabble posts about the mooning + NPC replies (HTML sqbGenDeeds parity).
func _moose_squabble_posts(town_name: String) -> void:
	if phone == null or not phone.has_method("npc_post"):
		return
	# Main post from a random NPC.
	var author: Dictionary = _random_author()
	if author.is_empty():
		return
	var line: String = String(MOOSE_SQB_LINES[randi() % MOOSE_SQB_LINES.size()])
	line = line.replace("{t}", town_name)
	var post: Dictionary = phone.npc_post(author, line, "moose")
	# 2-3 NPCs reply to each other's posts.
	var post_id: int = int(post.get("id", -1))
	if post_id >= 0 and phone.has_method("npc_comment"):
		var replies: int = 2 + randi() % 2
		for i: int in replies:
			var replier: Dictionary = _random_author()
			if replier.is_empty():
				continue
			var rline: String = String(MOOSE_SQB_REPLIES[randi() % MOOSE_SQB_REPLIES.size()])
			phone.npc_comment(post_id, replier, rline)


## Jeremy 2026-10-04: when the REAL n-word is used, the whole realm
## condemns racism explicitly — every faction in their own voice, even
## factions at war with each other. Rumors + Squabble + speech bubbles.
## The game takes a clear stance: GAH FUCK RACISTS.
## Jeremy 2026-10-04: the offender is NAMED — the realm spreads the word
## that [X] is racist (player king by name, or the NPC personally).
## Reporters NEVER quote the slur itself (euphemize: "THAT word",
## "won't repeat it") so they don't trigger the system on themselves —
## the exact quote (text) is deliberately ignored here.
func _on_slur_incident(insulter: String, _target: String, _text: String,
		offender_name: String) -> void:
	var ruler := _faction_name(insulter)
	var offender := _offender_name(insulter, offender_name)
	# 1. Rumors: one condemnation per faction, max heat — this dominates
	# the grapevine. Blocked citizens are excluded via _random_citizen.
	var pools := {
		"ogres": SLUR_CONDEMN_OGRES,
		"elves": SLUR_CONDEMN_ELVES,
		"gnomes": SLUR_CONDEMN_GNOMES,
		"humans": SLUR_CONDEMN_HUMANS,
		"undead": SLUR_CONDEMN_UNDEAD,
	}
	for faction: String in pools.keys():
		var lines: Array = pools[faction]
		var line: String = String(lines[randi() % lines.size()])
		line = line.replace("{ruler}", ruler)
		line = line.replace("{offender}", offender)
		var knower: Dictionary = _random_citizen(faction)
		var kid: int = int(knower.get("id", -1)) if not knower.is_empty() else -1
		seed_rumor(line, "slur", faction, 0.95, kid, false, TRUTH_TRUE)
	# 1b. Name-and-shame: the realm spreads the word that [X] is racist.
	for i: int in 2:
		var shame: String = String(
			SLUR_NAME_SHAME_LINES[randi() % SLUR_NAME_SHAME_LINES.size()])
		shame = shame.replace("{ruler}", ruler)
		shame = shame.replace("{offender}", offender)
		seed_rumor(shame, "slur", "shame", 0.95, -1, false, TRUTH_TRUE)
	# 1c. Jeremy 2026-10-06 (lane 6): the offender's reputation is
	# destroyed — a NAMED npc offender tanks to 0 personally, and the
	# offender's whole faction takes a standing hit. HARD LINE: this is
	# never softened, never joked about, never debunked.
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("name", "")) == offender:
			(state["npc_rep"] as Dictionary)[str(int(u.get("id", 0)))] = 0.0
	if _gs.diplomacy != null \
			and _gs.diplomacy.has_method("tarnish_reputation"):
		_gs.diplomacy.tarnish_reputation(insulter, REP_SLUR_FACTION)
	# 2. Squabble: NPCs from ALL factions condemn — the platform unites.
	if phone != null and phone.has_method("npc_post"):
		var posted: Array = []
		var used: Array = []
		for faction: String in pools.keys():
			var author: Dictionary = _random_citizen(faction)
			if author.is_empty():
				continue
			var template: String = String(
				SLUR_CONDEMN_POSTS[randi() % SLUR_CONDEMN_POSTS.size()])
			var guard := 0
			while template in used and guard < 10:
				template = String(
					SLUR_CONDEMN_POSTS[randi() % SLUR_CONDEMN_POSTS.size()])
				guard += 1
			used.append(template)
			template = template.replace("{ruler}", ruler)
			template = template.replace("{offender}", offender)
			posted.append(phone.npc_post(author, template, "news"))
		# Replies amplify the message.
		for post: Dictionary in posted:
			var pid: int = int(post.get("id", -1))
			if pid < 0 or not phone.has_method("npc_comment"):
				continue
			for i: int in 2:
				var replier: Dictionary = _random_author()
				if replier.is_empty():
					continue
				var rline: String = String(
					SLUR_CONDEMN_REPLIES[randi() % SLUR_CONDEMN_REPLIES.size()])
				rline = rline.replace("{ruler}", ruler)
				rline = rline.replace("{offender}", offender)
				phone.npc_comment(pid, replier, rline)
			for k: int in randi_range(4, 14):
				phone.like_post(pid)
			for k: int in randi_range(2, 6):
				phone.resquabble(pid)
	# 3. Jeremy 2026-10-06: bystander condemnations used to ride
	# bus.unit_said, a no-op since the bubble ban — witnesses now join
	# the condemnation rumors as knowers with real memories instead.
	var condemn_rumors: Array = []
	for r: Dictionary in state["rumors"]:
		if String(r.get("kind", "")) == "slur":
			condemn_rumors.append(r)
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if randf() < 0.25 and not condemn_rumors.is_empty():
			var cr: Dictionary = condemn_rumors[randi() % condemn_rumors.size()]
			_witness(u, cr)


## Names the racist personally for the grapevine: a named NPC offender
## ("Grak"), the offending king by name ("ass"), or the title fallback
## ("the Ogres ruler"). Used in {offender} slots; {ruler} stays the faction.
func _offender_name(insulter: String, offender_name: String) -> String:
	if not offender_name.strip_edges().is_empty():
		return offender_name.strip_edges()
	var king := String(_gs.ruler_name).strip_edges()
	if insulter == _gs.player_faction and not king.is_empty():
		return king
	return "the %s ruler" % _faction_name(insulter)


## Jeremy 2026-10-04: "spread the word that X is racist" — direct
## name-and-shame lines. {offender} = personal name/label, {ruler} = faction.
## Reporters euphemize the slur itself ("THAT word", "won't repeat it") so
## they never quote it and never trigger the system on themselves.
const SLUR_NAME_SHAME_LINES: Array[String] = [
	"Spread the word: {offender} is racist. Don't let them forget it.",
	"{offender} said THAT word. Remember the name: {offender}.",
	"Just so everyone's clear: {offender} is a racist.",
	"The taverns are saying it: {offender} is racist.",
	"Tell your neighbors: {offender} used the slur. The unforgivable one.",
	"{offender} dropped the hard-r in court. I won't repeat it. But remember who said it.",
	"New entry in the book of grudges: {offender}, racist.",
	"If you see {offender}, know what they are: a racist.",
	"{offender} showed their true colors. Ugly colors. Racist colors.",
	"The whole realm knows now: {offender} is racist.",
	"{offender} said the word. THAT word. I'm not typing it.",
	"Heard it straight: {offender} is racist. Pass it on.",
	"They say {offender} used language so vile I won't repeat it. Believe them.",
	"{offender}, racist. That's the whole rumor. That's enough.",
]


func _on_unit_died(unit_id: int, faction: String) -> void:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return
	var role: String = String((u.get("mind", {}) as Dictionary).get("gov_role", ""))
	if role == "":
		return  # only notables get obituaries — no spam
	var rname: String = role.replace("_", " ").capitalize()
	var uname: String = SimPersonality.display_name(u)
	_event_post(DEATH_LINES, "death",
		{"n": uname, "r": rname})
	# Jeremy 2026-10-07 (hearsay flesh-out): the obituary records WHOSE
	# notable died — the signal carries the faction and the reaction
	# matrix needs it (own faction mourns, war-rivals cackle). The subject
	# is per-notable so two dead advisors never collapse into one rumor.
	var dfaction: String = faction
	if dfaction == "":
		dfaction = String(u.get("faction", ""))
	var text: String
	if dfaction != "":
		text = "%s, %s of the %s, has died." % [
			uname, rname, _faction_name(dfaction)]
	else:
		text = "%s, %s of the realm, has died." % [uname, rname]
	var r: Dictionary = seed_rumor(text, "death",
		"death:" + str(unit_id), 0.7, -1, false, TRUTH_TRUE)
	r["dead_faction"] = dfaction


## Jeremy 2026-10-08 (hearsay flesh-out): WHO KILLED WHOM. bus.unit_killed
## carries the killer's faction — the one fact unit_died never has — so
## assassinations and battlefield slayings seed whodunit rumors instead
## of vanishing into the grapevine's blind spot (HTML assassin-headline
## parity: major urgent news, realm mood -6 in peace).
##   - unknown killer or same-faction killing: skipped — the obituary
##     (notables) and crime-justice (JUSTICE SERVED) paths own those.
##   - wartime soldier-vs-soldier: skipped — the war drums already cover
##     routine battlefield deaths; notables, civilians, and peacetime
##     slayings are the news.
##   - a notable's existing obituary is UPGRADED in place (text, heat,
##     killer fields) — one developing story, not two rumors crowding
##     the cap. Everyone else seeds a fresh "kill" rumor, truth TRUE
##     (the sim saw it happen — investigators can verify it).
##   - first knower: the killer's kin boast in war; the victim's kin
##     find the body in peace.
##   - a peacetime murder dents the killer faction's standing once, at
##     seed (realm thinks less of murderers); war is war.
func _on_unit_killed(unit_id: int, source_faction: String) -> void:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return
	var kfaction := String(source_faction)
	var vfaction := String(u.get("faction", ""))
	if kfaction == "" or vfaction == "" or kfaction == vfaction:
		return
	var at_war := _rival_of(kfaction, vfaction)
	var role: String = String(
		(u.get("mind", {}) as Dictionary).get("gov_role", ""))
	var notable := role != ""
	if at_war and not notable \
			and JobDefs.is_military(String(u.get("job", ""))):
		return
	var vname := SimPersonality.display_name(u)
	var line: String = String(
		KILL_LINES[randi() % KILL_LINES.size()])
	line = line.replace("{v}", vname)
	line = line.replace("{vf}", _faction_name(vfaction))
	line = line.replace("{kf}", _faction_name(kfaction))
	var heat := 0.75
	if notable:
		heat += 0.1
	if not at_war:
		heat += 0.1
	heat = minf(heat, 0.95)
	var r := _live_rumor("death", "death:" + str(unit_id))
	if r.is_empty():
		r = seed_rumor(line, "kill", "kill:" + str(unit_id), heat,
			-1, false, TRUTH_TRUE)
	else:
		# The obituary becomes a murder report: same story, new facts.
		r["text"] = line
		r["text_orig"] = line
		r["heat"] = maxf(float(r.get("heat", 0.0)), heat)
	r["killer_faction"] = kfaction
	r["victim_faction"] = vfaction
	r["victim_id"] = unit_id
	r["victim_name"] = vname
	r["victim_notable"] = notable
	# First knower: the killer's kin boast in war; the victim's kin find
	# the body in peace. (Upgraded obituaries may already have knowers —
	# the mill found the death before the blade was named.)
	if (r["knowers"] as Array).is_empty():
		var first: Dictionary = _random_citizen(
			kfaction if at_war else vfaction)
		if not first.is_empty():
			var fid := int(first.get("id", 0))
			(r["knowers"] as Array).append(fid)
			_on_heard(first, r, {})
	if not at_war:
		_faction_rep(kfaction, REP_FACTION_DEED_BAD)
	# Notables and peacetime slayings earn a Squabble post — the realm
	# talks about this one out loud.
	if notable or not at_war:
		_event_post(KILL_LINES, "kill",
			{"v": vname, "vf": _faction_name(vfaction),
				"kf": _faction_name(kfaction)})


func _on_peace(faction_a: String, faction_b: String) -> void:
	var other: String = faction_b if faction_a == _gs.player_faction else faction_a
	_event_post(PEACE_LINES, "news", {"f": _faction_name(other)})
	var r: Dictionary = seed_rumor("Peace with the %s! The banners of war come down." % _faction_name(other),
		"news", other, 0.7, -1, false, TRUTH_TRUE)
	# Jeremy 2026-10-07 (hearsay flesh-out): record both sides so the
	# diplomacy reaction matrix can breathe easier with the peacemakers.
	r["dip"] = "peace"
	r["side_a"] = faction_a
	r["side_b"] = faction_b


## Jeremy 2026-10-06 (hearsay gap coverage): the white flag finally gets
## its own gossip. Surrender OFFERS flew with zero grapevine presence —
## no rumor, no Squabble post. The realm now talks when a faction begs
## off a war. (Offers publish no Gazette story, so the rumor may earn
## press coverage. quest_spawned is set: confirmed news, not a scout
## lead — the quest tick only understands faction-id subjects.)
func _on_surrender_offered(loser: String, winner: String) -> void:
	var lf := _faction_name(loser)
	var wf := _faction_name(winner)
	_event_post(SURRENDER_OFFER_LINES, "war", {"l": lf, "w": wf})
	var r: Dictionary = seed_rumor(
		"The %s offered surrender to the %s — the white flag flies!" % [lf, wf],
		"war", "surrender:" + loser, 0.9, -1, false, TRUTH_TRUE)
	r["quest_spawned"] = true
	# Jeremy 2026-10-07 (hearsay flesh-out): record both sides so hearers
	# react in character — the losers dread, the winners anticipate.
	r["loser"] = loser
	r["winner"] = winner


## The flag was ACCEPTED: they yield, reparations flow. (The peace_made
## that follows seeds its own peace rumor — different subject, no clash.
## press_ok is false: diplomacy._report already printed the official
## Gazette story, so the rumor never double-prints the front page.)
func _on_surrender_accepted(loser: String, winner: String) -> void:
	var lf := _faction_name(loser)
	var wf := _faction_name(winner)
	_event_post(SURRENDER_ACCEPT_LINES, "war", {"l": lf, "w": wf})
	var r: Dictionary = seed_rumor(
		"The %s yield to the %s! The war ends with reparations paid." % [lf, wf],
		"war", "surrendered:" + loser, 1.0, -1, false, TRUTH_TRUE)
	r["quest_spawned"] = true
	r["press_ok"] = false
	# Jeremy 2026-10-07 (hearsay flesh-out): record both sides so hearers
	# react in character — the losers are demoralized, winners celebrate.
	r["loser"] = loser
	r["winner"] = winner
## NOTE 2026-10-06: surrender REFUSALS have no bus signal — diplomacy only
## _record()s them — so there is no handler to wire here. Refusals ARE
## covered: _report() publishes "SURRENDER REFUSED: ..." (kind "war") to
## the Gazette, and _on_story seeds a heat-1.0 war rumor from it (tested).
## A dedicated refused-handler awaits a one-line bus.surrender_refused
## emit in diplomacy.resolve_surrender — deferred while that file is hot.


func _on_alliance(faction_a: String, faction_b: String) -> void:
	var other: String = faction_b if faction_a == _gs.player_faction else faction_a
	_event_post(ALLIANCE_LINES, "news", {"f": _faction_name(other)})
	var r: Dictionary = seed_rumor("Alliance forged with the %s!" % _faction_name(other), "news", other, 0.75, -1, false, TRUTH_TRUE)
	# Jeremy 2026-10-07 (hearsay flesh-out): both sides, for the
	# diplomacy reaction matrix (allies celebrate, their enemies worry).
	r["dip"] = "alliance"
	r["side_a"] = faction_a
	r["side_b"] = faction_b


func _on_treaty_broken(breaker: String, other: String) -> void:
	_event_post(TREATY_BREAK_LINES, "news", {"f": _faction_name(breaker)})
	var r := seed_rumor("The %s broke their treaty. Oathbreakers!" % _faction_name(breaker),
		"news", breaker, 0.8, -1, false, TRUTH_TRUE)
	# Jeremy 2026-10-07 (hearsay flesh-out): the betrayed side was dropped
	# from the rumor (param was literally named _other) — the matrix needs
	# both sides to react: outrage on one, defiance on the other.
	r["betrayer"] = breaker
	r["betrayed"] = other


func _on_tribute(from_faction: String, to_faction: String, _res: String, amount: float) -> void:
	_event_post(TRIBUTE_LINES, "news",
		{"f": _faction_name(from_faction), "a": str(int(amount))})
	# Jeremy 2026-10-06: every other event handler seeded a rumor — tribute
	# only posted to Squabble. The grapevine hears about tribute too.
	# Jeremy 2026-10-07 (hearsay flesh-out): record payer AND receiver so
	# the diplomacy reaction matrix splits the room — the payer seethes,
	# the receiver feels smug.
	var r: Dictionary = seed_rumor("Tribute paid to the %s — %d gold for their patience." % [
		_faction_name(from_faction), int(amount)], "tribute", from_faction, 0.6, -1, false, TRUTH_TRUE)
	r["dip"] = "tribute"
	r["payer"] = from_faction
	r["receiver"] = to_faction


## Jeremy 2026-10-06: hearsay overhaul — the grapevine was deaf to half
## the sim. These handlers ground rumors in real events: construction,
## destruction, monastery captures, trade, refused tribute, and relation
## shifts. Nothing invented — every rumor traces to a fired bus signal.
func _on_deed(text: String) -> void:
	# Adventure deeds (heroics, toasts) become praised gossip.
	# Jeremy 2026-10-08 (hearsay flesh-out): quest outcome deeds now seed
	# rich rumors via the quest handlers below — the thin deed gossip
	# skips them so the tavern tells the story ONCE, not twice. The
	# failure deed's victim name is stashed (matched by quest title in
	# _on_quest_failed) because the failure signal carries no name.
	if text.begins_with("Completed quest:") \
			or text.begins_with("Accepted quest:") \
			or text.begins_with("Became a Legend") \
			or text.begins_with("The wilds claimed"):
		return
	if text.begins_with("Failed quest:"):
		_stash_quest_failure(text)
		return
	gossip_deed(text, true)


## Jeremy 2026-10-08 (hearsay flesh-out): adventure quest gossip — the
## last deaf thread in the sim. Quest outcomes used to arrive as a thin
## praised-gossip toast with no named parties and no reactions. Now the
## hero's name, the quest giver, and the stakes seed real rumors the
## realm reacts to in character. Lane-pure: reads the quest dicts
## adventure.gd emits on the bus; never touches adventure.gd.
## The adventure hero (the player's champion): name + faction for quest
## rumors. One O(240) unit scan per quest event — quests end rarely.
func _adventure_hero() -> Dictionary:
	if _gs == null:
		return {}
	for u: Dictionary in _gs.units:
		if bool(u.get("is_hero", false)):
			return u
	return {}


## The failure deed ("Failed quest: <title> — <name> died.") is the only
## place the fallen charge's name exists — the failure bus signal only
## carries the quest dict. The deed fires immediately before the signal
## (same synchronous call), so stash it keyed by title and consume it
## in _on_quest_failed.
func _stash_quest_failure(text: String) -> void:
	var body := text.trim_prefix("Failed quest: ")
	var parts := body.split(" — ", true, 1)
	if parts.size() < 2:
		return
	var title := String(parts[0])
	var victim := String(parts[1])
	if victim.ends_with(" died."):
		victim = victim.left(victim.length() - " died.".length())
	state["last_quest_failure"] = {"title": title, "victim": victim}


func _consume_quest_failure(title: String) -> String:
	var stash: Dictionary = state.get("last_quest_failure", {})
	if String(stash.get("title", "")) != title:
		return "the poor charge"
	state["last_quest_failure"] = {}
	return String(stash.get("victim", "the poor charge"))


## Type-flavored triumph verbs for the tavern's retelling.
func _quest_deed_verb(qtype: String) -> String:
	match qtype:
		"bounty":
			return "brought back the scalps"
		"rescue":
			return "brought the captive home alive"
		"escort":
			return "walked the pilgrim home safe"
		"fetch":
			return "recovered the relic"
		"clear":
			return "silenced the dungeon"
	return "finished the job"


## The tavern's first witness: the quest giver's court, the guild board —
## whoever heard it loudest. The hero's own faction hears first and
## celebrates loudest; the first knower's _on_heard routes into the
## quest reaction matrix (seeded after metadata, the petition pattern).
func _quest_first_knower(r: Dictionary, hero_faction: String) -> void:
	if hero_faction == "":
		return
	var first: Dictionary = _random_citizen(hero_faction)
	var kid := int(first.get("id", -1))
	if kid > 0 and not (r["knowers"] as Array).has(kid):
		(r["knowers"] as Array).append(kid)
		var ku: Dictionary = _gs.get_unit(kid)
		if not ku.is_empty():
			_on_heard(ku, r, {})


## Jeremy 2026-10-09 (hearsay flesh-out): quest acceptances were the last
## deaf thread in the adventure system — completions, failures, legends,
## and falls all gossiped while the TAKING-UP stayed silent. Now the
## tavern buzzes when the hero takes up a quest: the hero's faction
## swells with hopeful pride, war-rivals mock the fool, and everyone
## else takes wagers. Heat 0.55 is tavern talk, not front page
## (PRESS_HEAT = 0.85). The guild-board posting is witnessed fact, so
## TRUTH_TRUE, like a building rising. Re-accepting an abandoned quest
## refreshes the rumor via seed_rumor's subject dedup (no twin).
## Lane-pure: reads the quest dict adventure.gd emits on the bus; never
## touches adventure.gd.
func _on_quest_accepted(q: Dictionary) -> void:
	var hero: Dictionary = _adventure_hero()
	var hname := String(hero.get("name", "the hero"))
	var hfaction := String(hero.get("faction", ""))
	var title := String(q.get("title", "a quest"))
	var giver := String(q.get("giver_name", ""))
	if giver == "":
		giver = "the quest giver"
	var text := "Tavern buzz: %s has %s — \"%s\" (posted by %s). Place your bets, the realm is watching." \
		% [hname, _quest_take_verb(String(q.get("type", ""))), title, giver]
	var r := seed_rumor(text, "quest", "questtaken:%s" % String(q.get("id", "")),
		0.55, -1, false, TRUTH_TRUE)
	r["quest_outcome"] = "taken"
	r["quest_title"] = title
	r["hero_name"] = hname
	r["hero_faction"] = hfaction
	_quest_first_knower(r, hfaction)


## Type-flavored taking-up verbs for the tavern's telling.
func _quest_take_verb(qtype: String) -> String:
	match qtype:
		"bounty":
			return "taken up the bounty"
		"rescue":
			return "ridden out to bring the captive home"
		"escort":
			return "vowed to walk the pilgrim home"
		"fetch":
			return "sworn to recover the relic"
		"clear":
			return "marched out to silence the dungeon"
	return "taken up the quest"


func _on_quest_completed(q: Dictionary) -> void:
	var hero: Dictionary = _adventure_hero()
	var hname := String(hero.get("name", "the hero"))
	var hfaction := String(hero.get("faction", ""))
	var title := String(q.get("title", "a quest"))
	var giver := String(q.get("giver_name", ""))
	if giver == "":
		giver = "the quest giver"
	var text := "The tavern is roaring: %s has %s — \"%s\" is done, and %s sang their praise over the ale!" \
		% [hname, _quest_deed_verb(String(q.get("type", ""))), title, giver]
	var r := seed_rumor(text, "quest", "questdone:%s" % String(q.get("id", "")),
		0.75, -1, false, TRUTH_TRUE)
	r["quest_outcome"] = "done"
	r["quest_title"] = title
	r["hero_name"] = hname
	r["hero_faction"] = hfaction
	_quest_first_knower(r, hfaction)


func _on_quest_failed(q: Dictionary) -> void:
	var hero: Dictionary = _adventure_hero()
	var hname := String(hero.get("name", "the hero"))
	var hfaction := String(hero.get("faction", ""))
	var title := String(q.get("title", "a quest"))
	var victim := _consume_quest_failure(title)
	var text := "Word from the wilds: \"%s\" has failed — %s is dead, and %s came back alone." \
		% [title, victim, hname]
	var r := seed_rumor(text, "quest", "questfail:%s" % String(q.get("id", "")),
		0.8, -1, false, TRUTH_TRUE)
	r["quest_outcome"] = "failed"
	r["quest_title"] = title
	r["hero_name"] = hname
	r["hero_faction"] = hfaction
	_quest_first_knower(r, hfaction)


## A legend is realm-shaking news (heat 0.95 = press-eligible, like the
## other big stories) — the front page covers it, Squabble sings about
## it, and every faction reacts: pride at home, fear across the border.
func _on_adventure_won() -> void:
	var hero: Dictionary = _adventure_hero()
	var hname := String(hero.get("name", "the hero"))
	var hfaction := String(hero.get("faction", ""))
	var text := "%s is a LEGEND OF THE WILDS — the taverns will sing this one for a hundred years!" % hname
	var r := seed_rumor(text, "quest", "adventure:won", 0.95, -1,
		false, TRUTH_TRUE)
	r["quest_outcome"] = "legend"
	r["quest_title"] = ""
	r["hero_name"] = hname
	r["hero_faction"] = hfaction
	_quest_first_knower(r, hfaction)
	if phone != null and phone.has_method("npc_post"):
		var author: Dictionary = _random_citizen(hfaction)
		if not author.is_empty():
			phone.npc_post(author, text, "deed")


## The hero's fall: the realm mourns — hardest at home, with schadenfreude
## across a war border. Heat 0.85 is press-eligible too; a fallen hero is
## front-page news.
func _on_adventure_lost() -> void:
	var hero: Dictionary = _adventure_hero()
	var hname := String(hero.get("name", "the hero"))
	var hfaction := String(hero.get("faction", ""))
	var text := "The wilds claimed %s. Light a candle and pour one out — the realm has lost its champion." % hname
	var r := seed_rumor(text, "quest", "adventure:lost", 0.85, -1,
		false, TRUTH_TRUE)
	r["quest_outcome"] = "fell"
	r["quest_title"] = ""
	r["hero_name"] = hname
	r["hero_faction"] = hfaction
	_quest_first_knower(r, hfaction)
	if phone != null and phone.has_method("npc_post"):
		var author: Dictionary = _random_citizen(hfaction)
		if not author.is_empty():
			phone.npc_post(author, text, "news")


## Jeremy 2026-10-08 (hearsay flesh-out): the crown's ruling on a
## petition seeds tavern talk. The petitioner stood in court and heard
## the verdict firsthand, so they are the first knower (seeded AFTER
## the verdict metadata is set — the seed_player_smear pattern — so
## their own _on_heard routes to the petition matrix, not generic).
## Denials are juicier gossip than grants (heat 0.75 vs 0.6). A court
## ruling is witnessed fact: TRUTH_TRUE, like a building rising.
## Lane-pure: reads the royal_court petition dict, never touches
## royal_court.gd.
func _on_petition_decided(p: Dictionary, choice: String) -> void:
	var pid := int(String(p.get("from_key", "")).trim_prefix("u"))
	var pname := String(p.get("from_name", "A petitioner"))
	if pname == "":
		pname = "A petitioner"
	var kind_human := String(p.get("kind", "petition")) \
		.replace("_", " ").capitalize()
	var verdict := _petition_verdict(choice)
	var text: String
	if verdict == "denied":
		text = "Word from the court: the crown has DENIED %s's %s plea — cold, says the tavern." \
			% [pname, kind_human]
	else:
		text = "Word from the court: the crown has GRANTED %s's %s plea — the tavern approves." \
			% [pname, kind_human]
	var r := seed_rumor(text, "news", "petition:%d" % int(p.get("id", 0)),
		0.75 if verdict == "denied" else 0.6, -1, false, TRUTH_TRUE)
	r["petitioner_id"] = pid
	r["petitioner_name"] = pname
	r["petitioner_faction"] = String(p.get("faction", ""))
	r["petition_kind"] = kind_human
	r["petition_verdict"] = verdict
	if pid > 0:
		var ku: Dictionary = _gs.get_unit(pid)
		if not ku.is_empty():
			var hk: Array = r["knowers"]
			if not hk.has(pid):
				hk.append(pid)
				_on_heard(ku, r, {})


## The verdict parsed from the ruling's choice text. Template options
## read like "Release Food"/"Refuse", "Grant Command"/"Deny",
## "Unleash Him"/"Forbid It", "Hold Festival"/"Not Now",
## "Lower to 10%"/"Hold Firm" — anything refusal-shaped is a denial.
func _petition_verdict(choice: String) -> String:
	var c := choice.to_lower()
	for w in ["refuse", "deny", "denied", "forbid", "not now",
			"hold firm", "reject", "veto"]:
		if c.contains(w):
			return "denied"
	return "granted"


## Jeremy 2026-10-08 (hearsay flesh-out): the court-ruling reaction
## matrix. The petitioner takes the verdict personally — a grant is
## pride and gratitude toward the crown, a denial is anger that lands
## on the ruler (affection moves via _react_apply, the player-agency
## half of this feature: the realm judges your mercy). Their own folk
## feel the ruling by proxy, a friend celebrates or defends, a rival
## grumbles at a grant and cackles at a denial (town remembers who
## laughed, like the gossip matrix). Everyone else gets the generic
## reception. Unhinged NPCs feel it 1.5x, same as the smear path.
func _petition_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var uid := int(u.get("id", 0))
	var pid := int(r.get("petitioner_id", 0))
	var pname := String(r.get("petitioner_name", "the petitioner"))
	var pfact := String(r.get("petitioner_faction", ""))
	var verdict := String(r.get("petition_verdict", "granted"))
	var denied := verdict == "denied"
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var ruler := "the crown"
	var rv = _gs.get("ruler_name")
	if rv != null and String(rv) != "":
		ruler = String(rv)
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if pid > 0 and uid == pid:
		# You stood in court and heard the crown's own mouth.
		if denied:
			_mem.remember(u, "petition_denied", rid, ruler, ufaction, 1.0)
			_react_apply(u, -10.0 * mult, -6.0, "insulted")
		else:
			_mem.remember(u, "petition_granted", rid, ruler, ufaction, 0.9)
			_react_apply(u, 8.0 * mult, 4.0, "praised")
		return
	var stance := 0.0
	if pid > 0:
		var pet: Dictionary = _gs.get_unit(pid)
		if not pet.is_empty():
			stance = SimLikesDislikes.npc_stance(u, pet, _gs)
	if pfact != "" and ufaction == pfact:
		# Your own folk's plea — the crown's mercy is personal.
		if denied:
			_mem.remember(u, "heard_petition_denied", pid, pname, pfact, 0.7)
			_react_apply(u, -4.0 * mult, -2.0, "insulted")
		else:
			_mem.remember(u, "heard_petition_granted", pid, pname, pfact, 0.6)
			_react_apply(u, 3.0 * mult, 1.0, "helped")
	elif stance >= 0.3:
		# A friend's plea — celebrate the grant, rage at the denial.
		if denied:
			_mem.remember(u, "defended_petition_victim", pid, pname,
				pfact, 0.8)
			_react_apply(u, -5.0 * mult, 0.0, "insulted")
		else:
			_mem.remember(u, "celebrated_petition_grant", pid, pname,
				pfact, 0.7)
			_react_apply(u, 4.0 * mult, 0.0, "helped")
	elif stance <= -0.3:
		# A rival's plea — grumble at the grant, cackle at the denial.
		if denied:
			_mem.remember(u, "mocked_petition_denial", pid, pname,
				pfact, 0.7)
			_react_apply(u, 5.0 * mult, 0.0, "liked_topic")
		else:
			_mem.remember(u, "grumbled_petition_grant", pid, pname,
				pfact, 0.5)
			_react_apply(u, -3.0 * mult, 0.0, "insulted")
	else:
		_generic_heard(u, r)


## Jeremy 2026-10-09 (hearsay flesh-out): a petition was FILED — seed
## the court-filing rumor. The crown's RULING gossiped since 10-08
## (petition_decided), but the filing itself — a courtier standing up
## to ask — was a deaf thread. Now the ask seeds its own "news" rumor
## (subject "petition_filed:<id>", disjoint from the verdict's
## "petition:<id>"), with the petitioner as first knower (they stood in
## court; metadata set before the first _on_heard, the seed_player_smear
## pattern, so routing hits the filing matrix). A filing is court fact:
## TRUTH_TRUE. Heat 0.55 stays under the ruler-DM bar (the crown already
## holds the petition); war-shaped pleas run at 0.7 so they reach the
## crown's ear as a DM — the realm should hear THOSE. Both stay under
## the press bar; the Gazette prints verdicts, not asks.
func _on_petition_opened(p: Dictionary) -> void:
	var pid := int(String(p.get("from_key", "")).trim_prefix("u"))
	var pname := String(p.get("from_name", "A petitioner"))
	if pname == "":
		pname = "A petitioner"
	var raw_kind := String(p.get("kind", "petition"))
	var kind_human := raw_kind.trim_prefix("bc_").replace("_", " ").capitalize()
	var hot := _petition_filing_hot(raw_kind)
	var heat := 0.7 if hot else 0.55
	var text: String
	if hot:
		text = "Word from the court: %s has petitioned the crown over %s — the tavern has gone very quiet." % [pname, kind_human]
	else:
		text = "Word from the court: %s has filed a %s plea before the crown — the tavern is already taking bets." % [pname, kind_human]
	var r := seed_rumor(text, "news", "petition_filed:%d" % int(p.get("id", 0)), heat, -1, false, TRUTH_TRUE)
	r["petitioner_id"] = pid
	r["petitioner_name"] = pname
	r["petitioner_faction"] = String(p.get("faction", ""))
	r["petition_filing"] = kind_human
	r["petition_hot"] = hot
	if pid > 0:
		var ku: Dictionary = _gs.get_unit(pid)
		if not ku.is_empty():
			var hk: Array = r["knowers"]
			if not hk.has(pid):
				hk.append(pid)
				_on_heard(ku, r, {})
	_petition_filing_squabble(pname, kind_human, hot)


## War-shaped filing kinds — the pleas that make the tavern go quiet.
## Substring-matched so new template ids inherit the dread.
func _petition_filing_hot(raw_kind: String) -> bool:
	var k := raw_kind.to_lower()
	for w in ["threat", "betray", "raid", "draft", "guns", "bandit", "war"]:
		if k.contains(w):
			return true
	return false


## Jeremy 2026-10-09 (hearsay flesh-out): the court-FILING reaction
## matrix. The petitioner stood up and asked — pride and hope now,
## stakes later. Their own folk take an interest, friends drum up
## support, rivals mock the ask around the tavern, and a war-shaped
## plea filed against YOUR people lands as dread, not gossip.
## Unhinged NPCs feel it 1.5x, same as the verdict path.
func _petition_filing_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var uid := int(u.get("id", 0))
	var pid := int(r.get("petitioner_id", 0))
	var pname := String(r.get("petitioner_name", "the petitioner"))
	var pfact := String(r.get("petitioner_faction", ""))
	var filing := String(r.get("petition_filing", "plea"))
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if pid > 0 and uid == pid:
		_mem.remember(u, "filed_petition", rid, filing, ufaction, 0.8)
		_react_apply(u, 4.0 * mult, 0.0, "hopeful")
		return
	var stance := 0.0
	if pid > 0:
		var pet: Dictionary = _gs.get_unit(pid)
		if not pet.is_empty():
			stance = SimLikesDislikes.npc_stance(u, pet, _gs)
	if bool(r.get("petition_hot", false)) and _rival_of(ufaction, pfact):
		# A war-plea filed against your people — dread, not gossip.
		_mem.remember(u, "dreaded_petition_filing", pid, pname, pfact, 0.9)
		_react_apply(u, -6.0 * mult, 0.0, "disliked_topic")
		return
	if pfact != "" and ufaction == pfact:
		# Your own folk stood up in court — the ask matters.
		_mem.remember(u, "heard_petition_filed", pid, pname, pfact, 0.6)
		_react_apply(u, 2.0 * mult, 1.0, "helped")
	elif stance >= 0.3:
		# A friend's plea — drum up support.
		_mem.remember(u, "backed_petition_filing", pid, pname, pfact, 0.7)
		_react_apply(u, 3.0 * mult, 1.0, "helped")
	elif stance <= -0.3:
		# A rival's plea — mock the ask around the tavern.
		_mem.remember(u, "mocked_petition_filing", pid, pname, pfact, 0.7)
		_react_apply(u, 2.0 * mult, 0.0, "liked_topic")
	else:
		_mem.remember(u, "heard_petition_filed", pid, pname, pfact, 0.4)
		_react_apply(u, 1.0 * mult, 0.0, "helped")


const PETITION_FILING_POST_LINES := [
	"Heard {name} filed a {kind} plea at court. Taking bets on the crown's mood. 🗳",
	"Word from the court: {name} stood up and asked for {kind}. Bold. We'll see. 👂",
	"{name} is petitioning the crown over {kind}. The tavern has OPINIONS. 🍺",
]
const PETITION_FILING_HOT_POST_LINES := [
	"{name} just petitioned the crown over {kind}. This is how wars start. Mark me. ⚔",
	"Word from the court: {name} wants {kind}. Sleep light tonight. 🌙",
]


func _petition_filing_squabble(pname: String, kind_human: String, hot: bool) -> void:
	var lines: Array = PETITION_FILING_HOT_POST_LINES if hot else PETITION_FILING_POST_LINES
	_event_post(lines, "petition_filing", {"name": pname, "kind": kind_human})


## Jeremy 2026-10-08 (hearsay flesh-out): a crime was committed — seed
## the rumor with the parties attached. Text is the exact Gazette
## headline so _on_story dedups the party-less story seed. Truth is
## TRUTH_TRUE: the crime really happened (witnessed fact). Repeat
## offenders get per-crime subjects — each crime is its own rumor, its
## own rep hit, its own grudge.
func _on_crime_committed(kind: String, crook_id: int, victim_id: int,
		town_name: String, loot: int, headline: String) -> void:
	if headline == "":
		return
	var heat := 0.65
	match kind:
		"mugging":
			heat = 0.8
		"burglary":
			heat = 0.7
		"pickpocket":
			heat = 0.65
		_:  # "tool_theft", "vandalism", anything else
			heat = 0.6
	var day_num := 1
	if _gs != null and _gs.get("day_number") != null:
		day_num = int(_gs.day_number)
	var n := 0
	for r2: Dictionary in state["rumors"]:
		if String(r2.get("subject", "")).begins_with(
				"crime:%d:%d" % [crook_id, day_num]):
			n += 1
	var subject := "crime:%d:%d:%d" % [crook_id, day_num, n + 1]
	var r := seed_rumor(headline, "crime", subject, heat, -1, false,
		TRUTH_TRUE)
	# Parties recorded BEFORE any _on_heard fires (seed/petition
	# pattern), so the first knowers hit the crime matrix, not the
	# generic path. crook_id 0 = unseen thief — the town knows a crime
	# happened, not who did it.
	var cname := "an unseen thief"
	var cfaction := ""
	if crook_id > 0:
		var crook: Dictionary = _gs.get_unit(crook_id)
		if not crook.is_empty():
			cname = SimPersonality.display_name(crook)
			if cname == "":
				cname = "a thief"
			cfaction = String(crook.get("faction", ""))
	var vfaction := ""
	if victim_id > 0:
		var victim: Dictionary = _gs.get_unit(victim_id)
		if not victim.is_empty():
			vfaction = String(victim.get("faction", ""))
	r["crook_id"] = crook_id
	r["crook_name"] = cname
	r["crook_faction"] = cfaction
	r["victim_id"] = victim_id
	r["victim_faction"] = vfaction
	r["town_name"] = town_name
	r["loot"] = loot
	r["crime_kind"] = kind
	# The victim lived it; the named thief knows the town is talking.
	if victim_id > 0:
		_crime_add_knower(r, victim_id)
	if crook_id > 0:
		_crime_add_knower(r, crook_id)


## Adds a knower to a crime rumor, firing _on_heard for them (mirrors the
## seed_rumor dedup path).
func _crime_add_knower(r: Dictionary, uid: int) -> void:
	if uid <= 0:
		return
	if (r.get("knowers", []) as Array).has(uid):
		return
	(r["knowers"] as Array).append(uid)
	var ku: Dictionary = _gs.get_unit(uid)
	if not ku.is_empty():
		_on_heard(ku, r, {})


## Jeremy 2026-10-08 (hearsay flesh-out): the crime reaction matrix. A
## named thief is the town's villain — the victim is outraged (grudge
## fuel aimed AT the crook), the crook is caught out (unhinged ones
## brag), the town feels unsafe, rivals mock the thief, and the crook's
## friends are disappointed. An unseen thief still outrages the victim
## and unsettles the victim's folk — but nobody can mock a face they
## never saw.
func _crime_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var uid := int(u.get("id", 0))
	var cid := int(r.get("crook_id", 0))
	var vid := int(r.get("victim_id", 0))
	var cname := String(r.get("crook_name", "the thief"))
	var cfaction := String(r.get("crook_faction", ""))
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var unhinged := SimUnhinged.is_unhinged(u)
	var mult := 1.5 if unhinged else 1.0
	if cid > 0 and uid == cid:
		# The town is talking about YOU — shame, or bragging rights.
		# "attacked" reads as fear (brave crooks stand defiant: anger).
		if unhinged:
			_mem.remember(u, "crime_bragged", rid, cname, ufaction, 0.8)
			_react_apply(u, 6.0, 0.0, "liked_topic")
		else:
			_mem.remember(u, "crime_caught_out", rid, cname, ufaction, 0.9)
			_react_apply(u, -10.0, 0.0, "attacked")
		return
	if vid > 0 and uid == vid:
		# Robbed — and the town knows who (or that nobody saw).
		if cid > 0:
			_mem.remember(u, "crime_victim", cid, cname, cfaction, 1.0)
		else:
			_mem.remember(u, "crime_victim", rid, "an unseen thief",
				ufaction, 0.8)
		_react_apply(u, -14.0 * mult, 0.0, "insulted")
		return
	if cid > 0:
		var crook: Dictionary = _gs.get_unit(cid)
		var stance := 0.0
		if not crook.is_empty():
			stance = SimLikesDislikes.npc_stance(u, crook, _gs)
		if stance >= 0.3:
			# Your friend is the thief — disappointment stings.
			_mem.remember(u, "crook_friend_shame", cid, cname,
				cfaction, 0.7)
			_react_apply(u, -6.0 * mult, 0.0, "insulted")
			return
		if stance <= -0.3:
			# Someone you can't stand got caught thieving — delicious.
			_mem.remember(u, "mocked_thief", cid, cname, cfaction, 0.7)
			_react_apply(u, 7.0 * mult, 0.0, "liked_topic")
			return
	# A thief walks YOUR streets — nobody feels safe. For an unseen
	# thief, the victim's folk feel it instead (nobody knows whose).
	var home := cfaction
	if cid <= 0:
		home = String(r.get("victim_faction", ""))
	if home != "" and ufaction == home:
		_mem.remember(u, "heard_crime", rid if cid <= 0 else cid,
			cname, home, 0.6)
		_react_apply(u, -5.0 * mult, 0.0, "insulted")
		return
	_generic_heard(u, r)


func _on_building_placed(b: Dictionary) -> void:
	var btype := String(b.get("type", ""))
	# Jeremy 2026-10-11 (hearsay flesh-out): a wagon dealership opening
	# is commerce news with its own rich rumor — not the generic
	# "a new building rises" line.
	if btype == "wagon_dealership":
		_on_dealer_opened(b)
		return
	# Only notable buildings make the grapevine — not every wall segment.
	if not btype in ["town_hall", "monastery", "guild_hall", "market",
			"blacksmith", "temple", "tavern", "barracks"]:
		return
	var bname := String(b.get("name", btype.replace("_", " ")))
	seed_rumor("A new %s rises! The realm takes notice." % bname,
		"building", btype, 0.55, -1, false, TRUTH_TRUE)


func _on_building_destroyed(b: Dictionary) -> void:
	var btype := String(b.get("type", ""))
	var bname := String(b.get("name", btype.replace("_", " ")))
	var r := seed_rumor("The %s has fallen! Rubble and recriminations." % bname,
		"building", btype, 0.7, -1, false, TRUTH_TRUE)
	# Jeremy 2026-10-07 (hearsay flesh-out): a fallen hall is mourned, not
	# just noted — record whose building it was so the matrix can react.
	r["lost_holder"] = String(b.get("faction", ""))


func _on_monastery_captured(god_id: String, faction: String) -> void:
	# Jeremy 2026-10-07 (hearsay flesh-out): the conquest matrix needs the
	# LOSER too. The bus only carries the new holder, so diff against the
	# holder snapshot (see _snapshot_holders).
	var holders: Dictionary = state.get("holders", {})
	var key := "monastery:" + god_id
	var old_holder := String(holders.get(key, ""))
	holders[key] = faction
	state["holders"] = holders
	_seed_conquest("The %s monastery has fallen to the %s! The gods are watching." % [
		String(god_id).capitalize(), _faction_name(faction)],
		key, 0.9, old_holder, faction)


## Jeremy 2026-10-09 (hearsay flesh-out): storm omens were the last deaf
## thread with a visible dramatic event — lightning hammers the rogue
## gods' dark crystals every storm (combat_fx "crystal_strike", flare +
## hum) and the mill heard NOTHING. A strike now seeds a rich
## kind-"crystal" rumor: the god is named (Raijuk the Skyreaver, struck
## by LIGHTNING — the tavern will dine out on that irony), the holding
## faction recorded, first-hand witnesses within 300px (the fire
## radius). Repeat strikes refresh the rumor via seed_rumor's subject
## dedup — one live omen per god, not a twin per bolt. Heat 0.7 is
## tavern talk, below PRESS_HEAT 0.85 (no front page). Lane-pure: reads
## the crystal roster SimDarkCrystals exposes on the GameState (the
## _snapshot_holders precedent); never touches dark_crystals.gd.
func _on_crystal_struck(crystal_id: int, pos: Vector2) -> void:
	var god_id := ""
	var owner := ""
	var cname := "a dark crystal"
	# _gs.get("crystals") is the SimDarkCrystals node in production (an
	# Object — its get() takes exactly ONE arg), a plain Dictionary
	# roster in tests, or null before crystals exist. All three fall
	# back gracefully; a strike with no roster is still an omen.
	var crys = _gs.get("crystals")
	var roster: Array = []
	if crys is Object:
		var live = crys.get("crystals")
		if live is Array:
			roster = live
	elif crys is Dictionary:
		roster = crys.get("crystals", [])
	for c: Dictionary in roster:
		if int(c.get("id", -1)) == crystal_id:
			god_id = String(c.get("god_id", ""))
			owner = String(c.get("owner", ""))
			break
	if god_id != "" and crys is Object and crys.has_method("crystal_name"):
		cname = String(crys.call("crystal_name", god_id))
	elif god_id != "":
		cname = "the Dark Crystal of %s" % god_id.capitalize()
	var ofaction := _faction_name(owner) if owner != "" else "no faction"
	var text := "Lightning SPLIT the sky and struck %s — the whole crystal flared and hummed like a struck bell! The %s hold it. An omen... or just weather?" % [cname, ofaction]
	if owner == "":
		text = "Lightning SPLIT the sky and struck %s — the whole crystal flared and hummed like a struck bell! No faction holds it. The wild gods quarrel among themselves tonight." % cname
	var subject := "crystalstruck:" + (god_id if god_id != "" else "wild")
	var fresh := _live_rumor("crystal", subject).is_empty()
	var r := seed_rumor(text, "crystal", subject, 0.7, -1, false,
		TRUTH_TRUE)
	r["crystal_owner"] = owner
	r["crystal_god"] = god_id
	r["crystal_name"] = cname
	if fresh:
		_event_post(CRYSTAL_STRIKE_LINES, "crystal",
			{"god": cname, "owner": ofaction})
	# Nearby NPCs watch the sky split with their own eyes — first-hand
	# witnesses (the same 300px terror radius as wildfires).
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if upos.distance_to(pos) > 300.0:
			continue
		_witness(u, r)


## The realm reads a lightning strike on a dark crystal as an omen —
## nobody shrugs at the sky smiting a rogue god's seat of power.
func _crystal_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var owner := String(r.get("crystal_owner", ""))
	var god := String(r.get("crystal_name", "the crystal"))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if owner != "" and ufaction == owner:
		if SimUnhinged.is_unhinged(u):
			_mem.remember(u, "crystal_struck_glee", rid, god, ufaction, 0.7)
			_react_apply(u, 3.0 * mult, 0.0, "mocked")
			return
		_mem.remember(u, "crystal_struck_omen", rid, god, ufaction, 0.8)
		_react_apply(u, -3.0 * mult, 0.0, "disaster")
		return
	if owner != "" and _rival_of(ufaction, owner):
		_mem.remember(u, "crystal_struck_glee", rid, god, ufaction, 0.7)
		_react_apply(u, 4.0 * mult, 0.0, "mocked")
		return
	if owner == "":
		_mem.remember(u, "crystal_struck_wonder", rid, god, ufaction, 0.5)
		_react_apply(u, 2.0 * mult, 0.0, "helped")
		return
	_mem.remember(u, "crystal_struck_news", rid, god, ufaction, 0.4)
	_react_apply(u, -1.5 * mult, 0.0, "disaster")


## Jeremy 2026-10-10 (hearsay flesh-out): trespass gossip — "seen
## slipping into X's house". bus.interior_entered fires on EVERY
## building entry, so this gates hard before a rumor is worth the
## mill's time: only houses with a living owner, only when the entrant
## is NOT a resident (your own people coming home is not news), and
## only when the entry is rumor-worthy — at night, or when somebody
## actually saw it. Witnesses are occupants still inside the house
## (cheap O(occupants) read — the owner catching you red-handed is the
## juiciest case) or bystanders within 250px by day (one bounded
## O(240) scan, crystal-handler precedent). A quiet daytime visit to
## an empty house seeds nothing: nobody saw, nobody cares.
## Subject dedups per house ("trespass:<building_id>") — repeat visits
## refresh the heat instead of spawning twins. Witnessed seeds are
## TRUTH_TRUE at heat 0.65 (tavern scandal, below PRESS_HEAT 0.85 —
## no front page); night second-hand seeds are TRUTH_UNKNOWN at 0.45.
func _on_interior_entered(building_id: int, unit_id: int) -> void:
	if unit_id <= 0 or building_id <= 0:
		return
	var b := _gs.get_building(building_id)
	if b.is_empty() or not bool(b.get("alive", false)) \
			or not bool(b.get("complete", false)):
		return
	if String(b.get("type", "")) != "house":
		return
	var owner_id := int(b.get("owner_unit", -1))
	if owner_id <= 0:
		return
	var snoop := _gs.get_unit(unit_id)
	if snoop.is_empty() or not bool(snoop.get("alive", false)):
		return
	var residents: Array = b.get("residents", [])
	if unit_id in residents:
		return  # coming home, not sneaking in
	var owner := _gs.get_unit(owner_id)
	if owner.is_empty() or not bool(owner.get("alive", false)):
		return
	# Occupant witnesses: the entry signal fires AFTER interiors.gd
	# appends the entrant to occupants, so skip the snoop themself.
	var intr: Dictionary = b.get("interior", {})
	var seen := false
	for oid in (intr.get("occupants", []) as Array):
		if int(oid) != unit_id:
			seen = true
			break
	var night := bool(_gs.is_night)
	if not seen and not night:
		# Daytime needs a bystander witness — otherwise it's just a
		# quiet visit and the mill stays out of it.
		var bpos: Vector2 = b.get("position", Vector2.ZERO)
		for w: Dictionary in _gs.units:
			if not bool(w.get("alive", false)):
				continue
			if int(w.get("id", 0)) == unit_id:
				continue
			var wpos: Vector2 = w.get("position", Vector2.ZERO)
			if wpos.distance_to(bpos) > 250.0:
				continue
			seen = true
			break
	if not seen and not night:
		return
	var sname := SimPersonality.display_name(snoop)
	var oname := SimPersonality.display_name(owner)
	var text := ""
	if seen and night:
		text = "%s crept into %s's house after dark — and somebody SAW. The tavern is already placing bets on why." % [sname, oname]
	elif seen:
		text = "%s was spotted slipping into %s's house in broad daylight. Either very brave or very stupid." % [sname, oname]
	else:
		text = "Someone slipped into %s's house last night. Nobody admits seeing it, but everybody's heard about it." % oname
	var truth := TRUTH_TRUE if seen else TRUTH_UNKNOWN
	var heat := 0.65 if seen else 0.45
	var subject := "trespass:" + str(building_id)
	var fresh := _live_rumor("trespass", subject).is_empty()
	var r := seed_rumor(text, "trespass", subject, heat, -1, false, truth)
	r["trespass_snoop_id"] = unit_id
	r["trespass_owner_id"] = owner_id
	r["trespass_house"] = building_id
	r["trespass_witnessed"] = seen
	if fresh:
		_event_post(TRESPASS_LINES, "trespass",
			{"snoop": sname, "owner": oname})
	if not seen:
		return
	# First-hand witnesses remember it as something they SAW, not just
	# something they heard (the _witness precedent).
	var bpos2: Vector2 = b.get("position", Vector2.ZERO)
	for w2: Dictionary in _gs.units:
		if not bool(w2.get("alive", false)):
			continue
		if int(w2.get("id", 0)) == unit_id:
			continue
		var w2pos: Vector2 = w2.get("position", Vector2.ZERO)
		if w2pos.distance_to(bpos2) > 250.0:
			continue
		_witness(w2, r)


## The realm reads a trespass rumor in character: the house owner is
## furious at the violation, the household is uneasy, the snoop is
## shamed (or defiant and delighted, if unhinged), the snoop's rivals
## cackle, the snoop's friends go quiet, and everyone else is mildly
## entertained by the tavern talk.
func _trespass_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var uid := int(u.get("id", 0))
	var snoop_id := int(r.get("trespass_snoop_id", 0))
	var owner_id := int(r.get("trespass_owner_id", 0))
	var snoop := _gs.get_unit(snoop_id)
	var sname := "the snoop"
	if not snoop.is_empty():
		sname = SimPersonality.display_name(snoop)
	var ufaction := String(u.get("faction", ""))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if uid == owner_id:
		_mem.remember(u, "trespass_anger", rid, sname, ufaction, 0.9)
		_react_apply(u, -4.0 * mult, 0.0, "insulted")
		return
	if uid == snoop_id:
		if SimUnhinged.is_unhinged(u):
			_mem.remember(u, "trespass_glee", rid, sname, ufaction, 0.7)
			_react_apply(u, 3.0 * mult, 0.0, "mocked")
			return
		_mem.remember(u, "trespass_shame", rid, sname, ufaction, 0.8)
		_react_apply(u, -2.5 * mult, 0.0, "disaster")
		return
	var hb := _gs.get_building(int(r.get("trespass_house", 0)))
	if not hb.is_empty() and uid in (hb.get("residents", []) as Array):
		_mem.remember(u, "trespass_wary", rid, sname, ufaction, 0.7)
		_react_apply(u, -2.0 * mult, 0.0, "disaster")
		return
	if not snoop.is_empty():
		var stance := SimLikesDislikes.npc_stance(u, snoop, _gs)
		if stance <= -0.3:
			_mem.remember(u, "trespass_glee", rid, sname, ufaction, 0.7)
			_react_apply(u, 3.0 * mult, 0.0, "mocked")
			return
		if stance >= 0.3:
			_mem.remember(u, "trespass_wary", rid, sname, ufaction, 0.5)
			_react_apply(u, -1.0 * mult, 0.0, "disaster")
			return
	_mem.remember(u, "trespass_news", rid, sname, ufaction, 0.4)
	_react_apply(u, 1.0 * mult, 0.0, "helped")


## Jeremy 2026-10-10 (hearsay flesh-out): beastloss gossip — "the
## miller's cow starved". Farm animals die of hunger when their faction's
## stockpile runs dry (animals.gd feeds 1 food/day from it); a starved
## herd is faction neglect and the tavern mocks it. Wild predator kills
## ("slain") are the season's wolf-drama. Subject dedups per
## faction+cause ("beastloss:<faction>:starved") so a starvation wave
## refreshes one rumor instead of spamming the mill; wild kills share one
## wolf-drama rumor ("beastloss:wild:slain"). Both stay below PRESS_HEAT
## — tavern talk, never the front page. Pets are NOT excluded: the grief
## system owns the private mourning, the mill owns the public mockery.
func _on_animal_died(plot_id: int, animal_id: int, cause: String,
		animal_type: String) -> void:
	var beast := animal_type if animal_type != "" else "beast"
	if plot_id >= 0:
		_on_farm_beast_died(plot_id, beast, cause)
	elif cause == "slain":
		_on_wild_beast_slain(beast)
	# Wild "starved" and unknown causes stay quiet — nobody saw it,
	# nobody cares.


func _on_farm_beast_died(plot_id: int, beast: String, cause: String) -> void:
	if cause != "starved":
		return  # slaughter/butchery is farm business, not gossip
	var faction := ""
	var farming = _gs.get("farming")
	if farming != null:
		for p in (farming.plots as Array):
			if p is Dictionary and int(p.get("id", 0)) == plot_id:
				faction = String(p.get("faction", ""))
				break
	if faction == "":
		return  # ownerless plot — nobody to mock
	var fname := _faction_name(faction)
	var subject := "beastloss:" + faction + ":starved"
	# Famine tie-in: a starving herd during a live famine rumor reads as
	# one story, not two — hotter talk, grimmer text.
	var famine := not _live_famine_rumor(faction).is_empty()
	var heat := 0.65 if famine else 0.55
	var text := "Another %s dropped dead in the %s pastures — somebody isn't feeding the herd, and the tavern has opinions." % [beast, fname]
	if famine:
		text = "With the granaries bare, the %s herd is dropping — another %s starved in the night. The tavern is taking bets on who's to blame." % [fname, beast]
	var fresh := _live_rumor("beastloss", subject).is_empty()
	var knower := _random_citizen(faction)
	var kid := int(knower.get("id", 0)) if not knower.is_empty() else -1
	var r := seed_rumor(text, "beastloss", subject, heat, kid, false,
		TRUTH_TRUE)
	r["beastloss_cause"] = "starved"
	r["beastloss_faction"] = faction
	r["beastloss_beast"] = beast
	if fresh:
		_event_post(BEASTLOSS_STARVED_LINES, "beastloss",
			{"faction": fname, "beast": beast})


func _on_wild_beast_slain(beast: String) -> void:
	var subject := "beastloss:wild:slain"
	var fresh := _live_rumor("beastloss", subject).is_empty()
	var text := "Wolves are getting bold — a %s was taken in the wilds last night. Shepherds are sharpening their sticks." % beast
	var r := seed_rumor(text, "beastloss", subject, 0.5, -1, false,
		TRUTH_UNKNOWN)
	r["beastloss_cause"] = "slain"
	r["beastloss_faction"] = ""
	r["beastloss_beast"] = beast
	if fresh:
		_event_post(BEASTLOSS_SLAIN_LINES, "beastloss", {"beast": beast})


## The realm reads a beastloss rumor in character: the hungry herd's own
## faction is shamed (the unhinged among them find it hilarious), rival
## factions gloat, everyone else gets mild tavern amusement — while a
## wolf kill in the wilds leaves everyone wary (except the unhinged, who
## love wolf drama). All emotion args are EVENT_MAP keys
## (emotion_audit-safe).
func _beastloss_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var beast := String(r.get("beastloss_beast", "the beast"))
	var cause := String(r.get("beastloss_cause", ""))
	var bfaction := String(r.get("beastloss_faction", ""))
	var ufaction := String(u.get("faction", ""))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if cause == "starved":
		if ufaction == bfaction and bfaction != "":
			if SimUnhinged.is_unhinged(u):
				_mem.remember(u, "beastloss_glee", rid, beast, ufaction, 0.6)
				_react_apply(u, 2.0 * mult, 0.0, "mocked")
				return
			_mem.remember(u, "beastloss_shame", rid, beast, ufaction, 0.7)
			_react_apply(u, -2.0 * mult, 0.0, "mocked")
			return
		if bfaction != "" and _rival_of(ufaction, bfaction):
			_mem.remember(u, "beastloss_glee", rid, beast, ufaction, 0.6)
			_react_apply(u, 2.0 * mult, 0.0, "mocked")
			return
		_mem.remember(u, "beastloss_news", rid, beast, ufaction, 0.4)
		_react_apply(u, 1.0 * mult, 0.0, "helped")
		return
	if SimUnhinged.is_unhinged(u):
		_mem.remember(u, "beastloss_glee", rid, beast, ufaction, 0.6)
		_react_apply(u, 2.0 * mult, 0.0, "mocked")
		return
	_mem.remember(u, "beastloss_wary", rid, beast, ufaction, 0.5)
	_react_apply(u, -1.5 * mult, 0.0, "disaster")


## Jeremy 2026-10-10 (hearsay flesh-out): harvest gossip — bumper crops
## and lean hauls. bus.farm_harvested fires on EVERY tile harvest (a tile
## grows 0->1 in ~1.5 days, 60-100 food normally), so the handler gates
## hard: bumper (>= 85 food, the top of the natural range) is boast-worthy,
## lean (< 55 food, only reachable when something's wrong — Bill's
## cybernetics -15%, flood mud, famine fields) is mock-worthy. A normal
## haul is farm business, not gossip, and stays quiet. Subject dedups per
## faction+type ("harvest:<faction>:bumper") so a good season refreshes one
## rumor instead of spamming the mill; Squabble posts only on the fresh
## seed. Both stay below PRESS_HEAT — tavern talk, never the front page.
func _on_farm_harvested(plot_id: int, food: float, seeds: float) -> void:
	var htype := ""
	if food >= 85.0:
		htype = "bumper"
	elif food < 55.0:
		htype = "lean"
	else:
		return  # normal haul — farm business, not gossip
	var faction := ""
	var farming = _gs.get("farming")
	if farming != null:
		for p in (farming.plots as Array):
			if p is Dictionary and int(p.get("id", 0)) == plot_id:
				faction = String(p.get("faction", ""))
				break
	if faction == "":
		return  # ownerless plot — nobody to boast at or mock
	var fname := _faction_name(faction)
	var food_int := int(round(food))
	var subject := "harvest:" + faction + ":" + htype
	var fresh := _live_rumor("harvest", subject).is_empty()
	var knower := _random_citizen(faction)
	var kid := int(knower.get("id", 0)) if not knower.is_empty() else -1
	var heat := 0.6 if htype == "bumper" else 0.55
	var text := ""
	if htype == "bumper":
		text = "Bumper crop in the %s fields — %d food off a single harvest! The farmers are insufferable and the tavern is pouring doubles." % [fname, food_int]
	else:
		text = "Lean season for the %s — %d food off a whole harvest. The tavern is taking bets on whose field that was." % [fname, food_int]
	var r := seed_rumor(text, "harvest", subject, heat, kid, false,
		TRUTH_TRUE)
	r["harvest_type"] = htype
	r["harvest_faction"] = faction
	r["harvest_food"] = food_int
	if fresh:
		if htype == "bumper":
			_event_post(HARVEST_BUMPER_LINES, "harvest",
				{"faction": fname, "food": str(food_int)})
		else:
			_event_post(HARVEST_LEAN_LINES, "harvest",
				{"faction": fname, "food": str(food_int)})


## The realm reads a harvest rumor in character: the bumper faction swells
## with pride, rivals are envious, neutrals just enjoy the good news; the
## lean faction is embarrassed (the unhinged among them laugh along),
## rivals mock the empty granary, neutrals get mild tavern amusement.
## All emotion args are EVENT_MAP keys (emotion_audit-safe).
func _harvest_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var htype := String(r.get("harvest_type", ""))
	var hfaction := String(r.get("harvest_faction", ""))
	var food := str(r.get("harvest_food", "the harvest"))
	var ufaction := String(u.get("faction", ""))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if htype == "bumper":
		if ufaction == hfaction and hfaction != "":
			_mem.remember(u, "harvest_pride", rid, food, ufaction, 0.6)
			_react_apply(u, 2.0 * mult, 0.0, "helped")
			return
		if hfaction != "" and _rival_of(ufaction, hfaction):
			_mem.remember(u, "harvest_envy", rid, food, ufaction, 0.5)
			_react_apply(u, -1.0 * mult, 0.0, "mocked")
			return
		_mem.remember(u, "harvest_news", rid, food, ufaction, 0.4)
		_react_apply(u, 1.0 * mult, 0.0, "helped")
		return
	# lean: the lean faction is embarrassed, rivals mock the empty
	# granary, everyone else gets mild tavern amusement.
	if ufaction == hfaction and hfaction != "":
		_mem.remember(u, "harvest_mock", rid, food, ufaction, 0.5)
		_react_apply(u, -1.5 * mult, 0.0, "mocked")
		return
	if hfaction != "" and _rival_of(ufaction, hfaction):
		_mem.remember(u, "harvest_mock", rid, food, ufaction, 0.6)
		_react_apply(u, 2.0 * mult, 0.0, "mocked")
		return
	_mem.remember(u, "harvest_news", rid, food, ufaction, 0.4)
	_react_apply(u, 1.0 * mult, 0.0, "helped")


## Jeremy 2026-10-10 (hearsay flesh-out): fire-brigade rollout gossip —
## "the {faction} engine is rolling!" The station's firetruck pulling out
## with crew aboard (Jeremy's 2026-10-10 direct order: real truck dispatch
## replacing the rapid-response abstraction) is the realm's favorite
## spectacle — bells ringing, a speeding engine, somebody else's
## emergency. bus.fire_brigade_rolled fires once per dispatch per fire
## (see DisasterSim._tick_station_truck); the handler gates hard and keeps
## it tavern talk (heat 0.6 < PRESS_HEAT 0.85, < QUEST_HEAT 0.7 — no front
## page, no advisor proposal). Multiple stations rolling to the same fire
## refresh one rumor via subject dedup ("brigade:<fire_id>"); Squabble
## posts only on the fresh seed. TRUTH_TRUE — the whole town heard the
## bells — so it joins the witnessed-fact doubt-immunity club.
func _on_fire_brigade_rolled(station_id: int, fire_id: int,
		faction: String) -> void:
	if faction == "":
		return  # station with no faction — nobody's brigade to cheer
	var fname := _faction_name(faction)
	var subject := "brigade:%d" % fire_id
	var fresh := _live_rumor("brigade", subject).is_empty()
	var text := "The %s fire brigade rolled out — bells ringing, crew aboard, straight for the smoke! Nothing draws a crowd like somebody else's emergency." % fname
	var r := seed_rumor(text, "brigade", subject, 0.6, -1, false,
		TRUTH_TRUE)
	r["brigade_faction"] = faction
	r["brigade_fire"] = fire_id
	r["brigade_station"] = station_id
	if fresh:
		_event_post(BRIGADE_LINES, "brigade", {"faction": fname})


## The realm reads a brigade rollout in character: the brigade's own
## faction swells with pride, the burning town feels hope (read off the
## live wildfire rumor's hit faction), rivals mock the bells, the unhinged
## thrill at the spectacle, and everyone else just enjoys the news.
## All emotion args are EVENT_MAP keys (emotion_audit-safe).
func _brigade_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var bfaction := String(r.get("brigade_faction", ""))
	var ufaction := String(u.get("faction", ""))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if SimUnhinged.is_unhinged(u):
		_mem.remember(u, "brigade_thrill", rid, bfaction, ufaction, 0.5)
		_react_apply(u, 3.0 * mult, 0.0, "cheerful")
		return
	if ufaction == bfaction and bfaction != "":
		_mem.remember(u, "brigade_pride", rid, bfaction, ufaction, 0.6)
		_react_apply(u, 2.0 * mult, 0.0, "victory")
		return
	# The burning town reads the rollout as rescue, not theater.
	var fr := _live_rumor("disaster", "wildfire")
	var victim := String(fr.get("hit_faction", ""))
	if victim != "" and ufaction == victim:
		_mem.remember(u, "brigade_hope", rid, bfaction, ufaction, 0.6)
		_react_apply(u, 2.0 * mult, 0.0, "hopeful")
		return
	if bfaction != "" and _rival_of(ufaction, bfaction):
		_mem.remember(u, "brigade_mock", rid, bfaction, ufaction, 0.5)
		_react_apply(u, 1.5 * mult, 0.0, "mocked")
		return
	_mem.remember(u, "brigade_news", rid, bfaction, ufaction, 0.4)
	_react_apply(u, 1.0 * mult, 0.0, "helped")



## Jeremy 2026-10-11 (hearsay flesh-out): wagon-dealership opening gossip.
## A new "wagon_dealership" building is commerce news — carts, wagons and
## carriages for citizen coin. Tavern talk (heat 0.55 < PRESS_HEAT), one
## live rumor refreshed per opening via subject dedup, Squabble post on
## the fresh seed. TRUTH_TRUE — the whole town watched the lot fill —
## so it joins the witnessed-fact doubt-immunity club.
func _on_dealer_opened(b: Dictionary) -> void:
	var faction := String(b.get("faction", ""))
	if faction == "":
		return  # unowned lot — nobody's commerce to cheer
	var fname := _faction_name(faction)
	var subject := "dealeropened"
	var fresh := _live_rumor("vehicle", subject).is_empty()
	var r := seed_rumor(String(VEHICLE_DEALER_LINES[
		randi() % VEHICLE_DEALER_LINES.size()]), "vehicle", subject,
		0.55, -1, false, TRUTH_TRUE)
	r["vehicle_kind"] = "opened"
	r["vehicle_faction"] = faction
	r["press_ok"] = false
	if fresh:
		_event_post(VEHICLE_DEALER_POST_LINES, "vehicle",
			{"faction": fname})


## Jeremy 2026-10-11 (hearsay flesh-out): vehicle-purchase gossip. The
## bus.vehicle_bought signal fires once per completed sale (buyer id,
## vehicle type, price — see SimDealership._close_sale). One rumor per
## buyer via subject dedup ("vehiclebought:<id>") — a second purchase
## refreshes the talk instead of doubling it. Heat 0.5 is tavern talk
## (< PRESS_HEAT, < QUEST_HEAT — no front page, no advisor proposal);
## TRUTH_TRUE joins the witnessed-fact doubt-immunity club — the buyer
## drove it home through town, nobody doubts new wheels. Squabble posts
## only on the fresh seed.
func _on_vehicle_bought(buyer_id: int, vtype: String, price: float) -> void:
	var buyer: Dictionary = _gs.get_unit(buyer_id)
	if buyer.is_empty():
		return  # buyer died mid-sale — no one left to brag about
	var faction := String(buyer.get("faction", ""))
	if faction == "":
		return  # factionless buyer — nobody's show-off to mock
	var bname := String(buyer.get("name", "somebody"))
	var lines: Array = VEHICLE_BOUGHT_LINES.get(vtype,
		VEHICLE_BOUGHT_LINES["wagon"])
	var subject := "vehiclebought:%d" % buyer_id
	var fresh := _live_rumor("vehicle", subject).is_empty()
	var r := seed_rumor(String(lines[randi() % lines.size()]) % [
		bname, int(price)], "vehicle", subject, 0.5, -1, false,
		TRUTH_TRUE)
	r["vehicle_kind"] = "bought"
	r["vehicle_buyer"] = buyer_id
	r["vehicle_buyer_name"] = bname
	r["vehicle_faction"] = faction
	r["vehicle_type"] = vtype
	r["vehicle_price"] = price
	r["press_ok"] = false
	if fresh:
		_event_post(VEHICLE_POST_LINES, "vehicle",
			{"buyer": bname, "vtype": vtype})


## The realm reads dealership news in character — no dead-end rumors:
##   - OPENED: the dealer's faction takes an interest (commerce is civic
##     pride); everyone else just enjoys the news.
##   - BOUGHT: the buyer hears their own legend — proud ("vehicle_proud");
##     the unhinged covet the wheels ("vehicle_thrill"); the buyer's
##     faction admires — or envies, if they couldn't afford it
##     ("vehicle_envy", grumpy); rivals mock the show-off
##     ("vehicle_mock"); everyone else just enjoys the news.
## Unhinged NPCs feel it 1.5x, matching the other matrices. Everything
## persists as memories + ruler-mood so the talk surfaces in later
## dialogue. All emotion args are EVENT_MAP keys (emotion_audit-safe).
func _vehicle_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var vkind := String(r.get("vehicle_kind", ""))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var uf := String(u.get("faction", ""))
	var vfact := String(r.get("vehicle_faction", ""))
	var rid := int(r.get("id", 0))
	if vkind == "opened":
		if uf == vfact:
			_mem.remember(u, "vehicle_dealer_news", rid, "dealeropened",
				uf, 0.5)
			_react_apply(u, 2.0 * mult, 0.0, "helped")
		else:
			_mem.remember(u, "vehicle_dealer_news", rid, "dealeropened",
				uf, 0.4)
			_react_apply(u, 1.0 * mult, 0.0, "cheerful")
		return
	var buyer_id := int(r.get("vehicle_buyer", 0))
	var subject := "vehiclebought:%d" % buyer_id
	if int(u.get("id", 0)) == buyer_id:
		# The buyer hears their own legend — insufferable and proud.
		_mem.remember(u, "vehicle_proud", rid, subject, uf, 0.7)
		_react_apply(u, 4.0 * mult, 0.0, "cheerful")
		return
	if SimUnhinged.is_unhinged(u):
		_mem.remember(u, "vehicle_thrill", rid, subject, uf, 0.6)
		_react_apply(u, 3.0 * mult, 0.0, "cheerful")
		return
	if uf == vfact and vfact != "":
		if float(u.get("coins", 0.0)) < float(r.get("vehicle_price", 0.0)):
			_mem.remember(u, "vehicle_envy", rid, subject, uf, 0.6)
			_react_apply(u, -2.0 * mult, 0.0, "grumpy")
		else:
			_mem.remember(u, "vehicle_news", rid, subject, uf, 0.4)
			_react_apply(u, 2.0 * mult, 0.0, "helped")
		return
	if vfact != "" and _rival_of(uf, vfact):
		_mem.remember(u, "vehicle_mock", rid, subject, uf, 0.6)
		_react_apply(u, 2.0 * mult, 0.0, "mocked")
		return
	_mem.remember(u, "vehicle_news", rid, subject, uf, 0.4)
	_react_apply(u, 1.0 * mult, 0.0, "cheerful")


## Jeremy 2026-10-06: Command Posts — dark crystal captures seed rumors.
func _on_crystal_captured(god_id: String, faction: String) -> void:
	# Jeremy 2026-10-07 (hearsay flesh-out): same loser-tracking as
	# monasteries — the snapshot diffs who held the crystal before.
	var holders: Dictionary = state.get("holders", {})
	var key := "crystal:" + god_id
	var old_holder := String(holders.get(key, ""))
	holders[key] = faction
	state["holders"] = holders
	_seed_conquest("The %s dark crystal burns with %s light now. The %s have claimed it — pray they don't learn to use it." % [
		String(god_id).capitalize(), _faction_name(faction),
		_faction_name(faction)],
		key, 0.9, old_holder, faction)


## Jeremy 2026-10-06: Command Posts — town captures seed rumors.
## (Monasteries keep their dedicated handler above.)
func _on_command_post_captured(kind: String, post_id: int,
		old_holder: String, new_holder: String, position: Vector2) -> void:
	if kind != "town":
		return
	if old_holder == "" or old_holder == new_holder:
		return
	# Jeremy 2026-10-07 (hearsay flesh-out): the town signal already
	# carries both sides — record them so the matrix can react.
	_seed_conquest("Word from the front: the %s have seized a town from the %s! Their banner flies over the hall now." % [
		_faction_name(new_holder), _faction_name(old_holder)],
		"townpost:" + str(post_id), 0.85, old_holder, new_holder)


## Jeremy 2026-10-07 (hearsay flesh-out): conquest rumors are keyed
## per-post (two different monasteries falling are two different rumors),
## but a RECAPTURE of the same post refreshes the shared rumor instead of
## doubling it — and the text must follow the newest capture, or the
## taverns would name last month's taker while the sides say otherwise.
## A recapture is a new event, so text_orig resets too.
func _seed_conquest(text: String, subject_key: String, heat: float,
		old_holder: String, new_holder: String) -> Dictionary:
	var existed := not _live_rumor("war", subject_key).is_empty()
	var r := seed_rumor(text, "war", subject_key, heat, -1, false, TRUTH_TRUE)
	if existed:
		r["text"] = text
		r["text_orig"] = text
	r["holder_old"] = old_holder
	r["holder_new"] = new_holder
	return r


func _on_trade_signed(faction_a: String, faction_b: String) -> void:
	var other: String = faction_b if faction_a == _gs.player_faction else faction_a
	var r: Dictionary = seed_rumor("Trade pact signed with the %s. The markets buzz." % _faction_name(other),
		"news", other, 0.55, -1, false, TRUTH_TRUE)
	# Jeremy 2026-10-07 (hearsay flesh-out): both sides, for the
	# diplomacy reaction matrix (traders content, their enemies sneer).
	r["dip"] = "trade"
	r["side_a"] = faction_a
	r["side_b"] = faction_b


## Jeremy 2026-10-08 (hearsay flesh-out): the caravan rumor thread.
## Captain Funky Pants' visits seed a RICH rumor (town attached, truth
## TRUE, first-hand witnesses who were standing near the caravan), deals
## struck during the visit get recorded on it, and departure folds in
## as a last-call rush instead of a second rumor. The reaction matrix
## (_trader_reaction) makes the realm CARE: the host town buzzes,
## dealers brag about their steals, latecomers regret missing it, and
## the proud sniff at the whole affair. Lane-pure: industry.gd already
## emits trader_arrived/trader_left/trade_done — hearsay just listens.
func _on_trader_arrived(trader_name: String, pos: Vector2) -> void:
	var town := _town_at(pos)
	var town_name := String(town.get("name", "the wilds"))
	var town_faction := String(town.get("faction", ""))
	# The text matches industry.gd's Gazette headline verbatim, so the
	# story path dedups against this rich rumor instead of double-seeding.
	var r: Dictionary = seed_rumor(
		"%s's caravan has arrived — limited stock!" % trader_name,
		"trade", town_name, 0.7, -1, false, TRUTH_TRUE)
	r["trader_visit"] = true
	r["trader_name"] = trader_name
	r["trader_town"] = town_name
	r["trader_faction"] = town_faction
	r["deals"] = []
	r["trader_gone"] = false
	# Anyone standing near the caravan SAW it arrive — first-hand
	# witnesses, same 400px market radius as the funky barter range.
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if upos.distance_to(pos) > 400.0:
			continue
		_witness(u, r)


## The caravan packed up: no second rumor — the live visit rumor gets a
## last-call heat rush (missed-it regret hits harder in _trader_reaction).
func _on_trader_left(_trader_name: String) -> void:
	var r := _live_trader_rumor()
	if r.is_empty():
		return
	r["trader_gone"] = true
	r["heat"] = minf(float(r.get("heat", 0.0)) + 0.15, 1.0)


## A barter completed while the caravan visits (player or AI faction):
## recorded on the live visit rumor so dealers can brag about it later.
## Bounded — a busy market day never grows the list unbounded.
func _on_trade_done(faction: String, give: String, take: String,
		give_amt: float, take_amt: float) -> void:
	var r := _live_trader_rumor()
	if r.is_empty():
		return
	var deals: Array = r.get("deals", [])
	deals.append({"faction": faction, "give": give, "take": take,
		"give_amt": give_amt, "take_amt": take_amt})
	while deals.size() > 12:
		deals.pop_front()
	r["deals"] = deals


## Jeremy 2026-10-08 (hearsay flesh-out): festival gossip. Festivals were
## a deaf thread — the mill only ever heard the thin court Gazette story
## (no town, no reactions) about the biggest party in the realm. Now
## policies.gd emits bus.festival_event with the town, host faction, and
## joy BEFORE the Gazette story publishes, so the mill seeds a rich
## rumor and _on_story dedups the party-less story seed (HTML Gazette
## "Society Pages" parity — festivals are news the whole realm talks
## about). HELD is hot (0.85 — press-eligible, ruler hears the buzz),
## CANCELLED is town grief (0.7), WOUND_DOWN is fond afterglow (0.5).
## The host faction's citizens are the first knowers — they react in
## character (see _festival_reaction). One rumor per town: a repeat
## event refreshes the heat and updates the text (the mill moves on).
## Held festivals are posted to Squabble by policies.gd's own FEST_LINES;
## cancellations and wind-downs get the mill's voice here instead. All
## event-driven — zero per-tick cost.
func _on_festival_event(festival: String, town: String, faction: String,
		joy: int) -> void:
	var text: String
	var heat: float
	match festival:
		"cancelled":
			text = "The festival planned for %s is CALLED OFF. No pies. No dancing. The town is gutted." % town
			heat = 0.7
		"wound_down":
			text = "The festival in %s is over — the bunting's down, the last dancers stumbled home. Already legend." % town
			heat = 0.5
		_:
			text = "GRAND FESTIVAL in %s! Music, pies, dancing in the mud — the whole town's invited!" % town
			heat = 0.85
	var r: Dictionary = seed_rumor(text, "festival", town, heat, -1, false,
		TRUTH_TRUE)
	# Dedup refresh keeps the newest event's news on the same town.
	if String(r.get("fest_event", "")) != festival:
		r["text"] = text
		r["text_orig"] = text
	r["fest_event"] = festival
	r["fest_town"] = town
	r["fest_faction"] = faction
	r["fest_joy"] = joy
	if festival == "cancelled":
		_event_post(FEST_CANCELLED_LINES, "festival", {"t": town})
	elif festival == "wound_down":
		_event_post(FEST_WOUND_DOWN_LINES, "festival", {"t": town})
	# The host town hears it first, loud and in character.
	var first: Dictionary = _random_citizen(faction)
	var kid := int(first.get("id", -1))
	if kid > 0 and not (r["knowers"] as Array).has(kid):
		(r["knowers"] as Array).append(kid)
		var ku: Dictionary = _gs.get_unit(kid)
		if not ku.is_empty():
			_on_heard(ku, r, {})


const FEST_CANCELLED_LINES: Array[String] = [
	"No festival in {t}. They took the pies BACK. I watched.",
	"{t}'s festival got called off. The refund queue is longer than the pie line was.",
	"They cancelled the festival in {t}. Somewhere a pie judge weeps.",
	"{t} had a festival planned and everything. Now it's just... Tuesday.",
	"Pour one out for {t}'s festival. The bunting never even came out of the box.",
]

const FEST_WOUND_DOWN_LINES: Array[String] = [
	"{t}'s festival is over. My feet hurt and my heart is full.",
	"The Great Mosh Pit of {t} is already legend. I was there.",
	"{t} danced in the mud and nobody regrets a thing.",
	"Festival's done in {t}. Already counting down to the next one.",
	"I ate seven pies in {t}. Seven. No regrets.",
]


## The festival reaction matrix. Everyone hears festival news and feels
## SOMETHING about it — no dead-end rumors:
##   - HELD: the host faction celebrates (proud, big mood lift, a warm
##     memory of the pies); war-rivals sneer at the joy; everyone else
##     just enjoys the happy news.
##   - CANCELLED: the host town is gutted (sad, remembers the broken
##     promise); war-rivals cackle at the refund queue; everyone else
##     feels mild sympathy. No blame on the crown — refunds were full.
##   - WOUND_DOWN: the host town basks in the afterglow; everyone else
##     hears it as pleasant small talk.
## Unhinged NPCs feel it 1.5x, matching the other matrices. Everything
## persists as memories + ruler-mood so the talk surfaces later.
func _festival_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var host := String(r.get("fest_faction", ""))
	var town := String(r.get("fest_town", "the town"))
	var fev := String(r.get("fest_event", "held"))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if fev == "held":
		if host != "" and ufaction == host:
			_mem.remember(u, "celebrated_festival", rid, town, ufaction,
				0.9)
			_react_apply(u, 8.0 * mult, 0.0, "victory")
			return
		if host != "" and _rival_of(ufaction, host):
			_mem.remember(u, "sneered_at_festival", rid, town, ufaction,
				0.6)
			_react_apply(u, -2.0 * mult, 0.0, "mocked")
			return
		_mem.remember(u, "heard_festival", rid, town, ufaction, 0.5)
		_react_apply(u, 2.0 * mult, 0.0, "helped")
		return
	if fev == "cancelled":
		if host != "" and ufaction == host:
			_mem.remember(u, "festival_cancelled", rid, town, ufaction,
				0.85)
			_react_apply(u, -6.0 * mult, 0.0, "mocked")
			return
		if host != "" and _rival_of(ufaction, host):
			_mem.remember(u, "mocked_festival", rid, town, ufaction, 0.6)
			_react_apply(u, 3.0 * mult, 0.0, "helped")
			return
		_mem.remember(u, "heard_festival", rid, town, ufaction, 0.4)
		_react_apply(u, -1.0 * mult, 0.0, "mocked")
		return
	if host != "" and ufaction == host:
		_mem.remember(u, "festival_memory", rid, town, ufaction, 0.7)
		_react_apply(u, 3.0 * mult, 0.0, "helped")
		return
	_mem.remember(u, "heard_festival", rid, town, ufaction, 0.3)
	_react_apply(u, 1.0 * mult, 0.0, "helped")


## Jeremy 2026-10-09 (hearsay flesh-out): the founding beat. The realm's
## own birth was a deaf thread — the mill only ever heard the thin "A
## KINGDOM RISES" court Gazette story (heat 0.7, no town, no faction, no
## reactions, nobody cared) about the biggest news there is. Now
## bus.kingdom_founded (town, faction, ruler attached) seeds a RICH named
## rumor BEFORE the Gazette story publishes:
##   - the home faction celebrates the coronation (proud, big mood lift,
##     a warm crowning memory, affection for the new crown)
##   - war-rivals sneer at the new crown (another tyrant to mock)
##   - allies congratulate (a friendly crown is good news)
##   - everyone else hears hopeful news
##   - heat 0.85: press-eligible (the coronation makes the Society Pages)
##     and it clears the ruler bar — the crown hears its own press
##   - Squabble lights up; the home faction boasts the news everywhere
## Old saves: the thin story still seeds the generic proclamation (the
## _on_story dedup only folds stories that match a rich rumor's town).
## Zero per-tick cost — one signal, one rumor, one reaction pass.
func _on_kingdom_founded(town: String, faction: String, ruler: String) -> void:
	var pretty := _faction_name(faction)
	var text := "A KINGDOM RISES in %s! %s of the %s takes the crown — the banners are up, the horns are hoarse, and the treasury has opened a ledger titled 'Regrettable Decisions'." % [town, ruler, pretty]
	var r: Dictionary = seed_rumor(text, "founding", town, 0.85, -1, false,
		TRUTH_TRUE)
	# One founding rumor per town: a repeat proclamation refreshes it.
	r["founding_town"] = town
	r["founding_faction"] = faction
	r["founding_ruler"] = ruler
	# The home town hears it first, loud and in character.
	var first: Dictionary = _random_citizen(faction)
	var kid := int(first.get("id", -1))
	if kid > 0 and not (r["knowers"] as Array).has(kid):
		(r["knowers"] as Array).append(kid)
		var ku: Dictionary = _gs.get_unit(kid)
		if not ku.is_empty():
			_on_heard(ku, r, {})
	# The whole realm talks about a coronation — Squabble lights up.
	_event_post(FOUNDING_LINES, "founding",
		{"t": town, "r": ruler, "f": pretty})


const FOUNDING_LINES: Array[String] = [
	"A KINGDOM RISES in {t}! {r} takes the crown — I was there, I heard the horns go hoarse.",
	"{t} has a new ruler: {r} of the {f}. The treasury is already weeping.",
	"They crowned {r} in {t} today. The gnomes are taking bets on the ledgers.",
	"New crown in {t}! {r} looked confident. Nobody's seen the tax ledgers yet.",
	"{r} of the {f} sits the throne in {t}. Festivities until someone does the math.",
]


## The founding reaction matrix. Everyone hears coronation news and feels
## SOMETHING about it — no dead-end rumors:
##   - HOME: the founding faction celebrates (proud, big mood lift, a warm
##     crowning memory, affection for the new crown)
##   - RIVALS: war-rivals sneer at the new crown (amused contempt — the
##     name-roast writes itself)
##   - ALLIES: allied factions congratulate (a friendly crown is good news)
##   - EVERYONE ELSE: hopeful news, a mild lift
## Unhinged NPCs feel it 1.5x, matching the other matrices. Everything
## persists as memories + ruler-mood so the talk surfaces later.
func _founding_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var home := String(r.get("founding_faction", ""))
	var town := String(r.get("founding_town", "the town"))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if home != "" and ufaction == home:
		_mem.remember(u, "crowned_ruler", rid, town, ufaction, 0.9)
		_react_apply(u, 8.0 * mult, 1.0 * mult, "victory")
		return
	if home != "" and _rival_of(ufaction, home):
		_mem.remember(u, "mocked_founding", rid, town, ufaction, 0.6)
		_react_apply(u, 3.0 * mult, 0.0, "mocked")
		return
	if home != "" and _gs.diplomacy != null and String(
			_gs.diplomacy.relation_state(ufaction, home)) == "allied":
		_mem.remember(u, "congratulated_founding", rid, town, ufaction, 0.6)
		_react_apply(u, 4.0 * mult, 0.5 * mult, "helped")
		return
	_mem.remember(u, "heard_founding", rid, town, ufaction, 0.5)
	_react_apply(u, 2.0 * mult, 0.0, "helped")


## Jeremy 2026-10-09 (hearsay flesh-out): the famine watch. The AI
## director has declared food emergencies since 2026-10-05 — workers
## yanked onto foraging, farms rushed, Gazette "FAMINE!" stories — and
## the rumor mill NEVER noticed. Now the mill reads the same granary
## ledgers the director does (per-capita food against the director's own
## thresholds: SimAIDirector.FOOD_EMERGENCY_PER_CAP / _CRIT_PER_CAP) and
## turns hunger into tavern talk:
##   - a starving faction seeds a rich kind-"famine" rumor — shortage
##     (0.7) or critical (0.9, press-eligible, reaches the ruler). The
##     starving hear it first AS WITNESSES: empty bellies testify, and
##     _belief weighs their testimony (+0.25, doubt-proof like slurs).
##   - still starving the next day: the rumor refreshes — the claim
##     escalates to critical text when it gets worse, eases back when
##     the pots start filling (same rumor, newest news wins).
##   - recovered (back above the threshold): one relief rumor ("they
##     eat again") — the live famine rumor keeps its natural decay.
## Called from _on_day before daily_tick, so hunger seeds gossip before
## the press pass runs. One census pass over _gs.units (240 max) — zero
## per-tick cost. Scan-based dedup on kind+famine_faction: no save
## schema, old saves and the director's own Gazette stories (routed
## through _on_story) self-heal.
func _famine_tick() -> void:
	var res = _gs.get("resources")
	if res == null or not res.has_method("get_amount"):
		return
	var pop := {}
	for u: Dictionary in _gs.units:
		if bool(u.get("alive", false)):
			var f := String(u.get("faction", ""))
			pop[f] = int(pop.get(f, 0)) + 1
	for f: String in Config.FACTIONS.keys():
		var p := int(pop.get(f, 0))
		if p <= 0:
			continue
		var per_cap: float = float(res.call("get_amount", f, "food")) \
				/ float(p)
		if per_cap < SimAIDirector.FOOD_EMERGENCY_PER_CAP:
			_seed_famine_rumor(f,
				per_cap < SimAIDirector.FOOD_EMERGENCY_CRIT_PER_CAP)
			continue
		if not _live_famine_rumor(f).is_empty():
			_seed_famine_relief(f)


## Jeremy 2026-10-09 (hearsay flesh-out): the turning seasons. The rumor
## claim per season (tavern talk) plus the Squabble first-person lines
## that mark the turn.
const SEASON_LINES := {
	"Winter": [
		"Winter has come. The elders say this will be a hard one.",
		"Snow's on the ground — stock the cellars and mend the furs.",
		"Deep winter. The roads go quiet and the wolves grow bold.",
	],
	"Spring": [
		"Spring! The thaw is here — planting season wakes the fields.",
		"The ice breaks. New lambs, new crops, new beginnings.",
		"Bloommoon winds — time to sow and mend fences.",
	],
	"Summer": [
		"High summer. The fields bake and the soldiers grow restless.",
		"Sunpeak heat — swim at noon, work at dawn.",
		"Summer's here. Long days, short tempers, cold ale.",
	],
	"Autumn": [
		"Autumn turns. Harvest time — the storehouses must be filled.",
		"Fallingleaf. Get the harvest in before the frost takes it.",
		"The leaves turn. A fat harvest means a kind winter.",
	],
}
const SEASON_POST_LINES := {
	"Winter": [
		"First snow. My toes have filed a formal complaint.",
		"Winter's here and my firewood pile is judging me.",
		"If the wolves want my chickens they'll have to go through me. They will go through me.",
	],
	"Spring": [
		"Planted the first row today. Felt like a promise.",
		"Spring! The mud is back and honestly I missed it.",
		"Thaw's here — time to fix everything winter broke.",
	],
	"Summer": [
		"Too hot to fight, too bored not to. Summer, man.",
		"Harvest is coming and my back already hurts.",
		"Cold ale season is the best season. Fight me.",
	],
	"Autumn": [
		"Harvest time. Every basket counts.",
		"The storehouse is filling. Winter can try its worst.",
		"Nothing smells better than a full granary in Fallingleaf.",
	],
}
## Jeremy 2026-10-10 (hearsay flesh-out): weather arrivals. Forecasts
## gossip about INCOMING disasters and the seasons cover the turning year;
## the remaining deaf thread was the ARRIVAL itself — "a storm broke over
## the realm at dawn." Only arrivals gossip (storm/rain/snow): clearing
## skies, cloud cover, and fog are routine and stay quiet.
const WEATHER_LINES := {
	"storm": [
		"A storm broke over the realm at dawn — black clouds, hard wind, the works.",
		"Storm's rolling in. The sky went green and the livestock are hiding.",
		"A big storm overhead. Shutters barred, cellars stocked, tempers frayed.",
	],
	"rain": [
		"Rain moved in over the fields. Steady, soaking, and right on time.",
		"It's raining again. The roads turn to soup but the crops are drinking.",
		"A good soaking rain settled over the realm. The farmers are smiling.",
	],
	"snow": [
		"Snow's falling. The first white of the turn — winter's knocking.",
		"Snow came down in the night. Everything's white and quiet.",
		"It's snowing. Wrap up, stock up, and keep the fire fed.",
	],
}
const WEATHER_POST_LINES := {
	"storm": [
		"Storm's here. Batten the shutters and pray for the roof.",
		"The wind just took my laundry AND my dignity. Storm's here.",
		"Thunder's close enough to count. Love it. (Do not tell my crops.)",
	],
	"rain": [
		"Rain! My garden is doing a happy dance. I am also doing a happy dance.",
		"Soaking rain. The well's full, the mud's back, life is good.",
		"Rain day. Perfect excuse to stay in and sharpen everything.",
	],
	"snow": [
		"Snow! First snow! My toes have already filed a complaint.",
		"Woke up to white. It's pretty. It's also cold. It's mostly cold.",
		"Snow's falling. Fire's lit, soup's on, winter can try its worst.",
	],
}
## Jeremy 2026-10-11 (hearsay flesh-out): wagon-dealership gossip lines.
## Jeremy's 2026-10-10 direct order put personal vehicles on the roads
## (dealership lots, assigned parking, real driving physics) and the
## grapevine was DEAF to it — nobody talked about the new dealership
## or who just bought wheels. Now a dealership opening seeds rich
## kind-"vehicle" talk, and every citizen purchase (bus.vehicle_bought,
## emitted from SimDealership._close_sale) seeds its own. No HTML
## mechanic to port — the dealership is a Godot-era system; the rumor
## machinery (belief, spread, doubt-immunity) follows the ported idiom.
const VEHICLE_DEALER_LINES: Array[String] = [
	"A wagon dealership just opened in town — carts, wagons, and carriages for sale, citizen coin only!",
	"New dealership on the edge of town! Somebody's selling wagons to anyone with the coins.",
	"There's a vehicle dealership now. Wagons for the hauling folk, carriages for the show-offs.",
]
const VEHICLE_BOUGHT_LINES := {
	"cart": [
		"%s just bought a CART from the dealership — %d coins! Hauling in style now.",
		"Heard %s picked up a cart. %d coins of pure hauling ambition.",
		"A cart! %s is the proud owner of a cart — %d coins lighter. The mill has opinions.",
	],
	"wagon": [
		"%s just bought a WAGON — %d coins! The roads will know their name.",
		"Heard %s rolled out of the dealership in a wagon. %d coins, cash on the counter.",
		"A brand-new wagon for %s! %d coins and not a single regret. Probably.",
	],
	"carriage": [
		"%s just bought a CARRIAGE — %d coins! Somebody's riding fancy.",
		"Heard %s picked up a carriage. %d coins of pure showing off.",
		"A carriage! %s is rolling fancy now — %d coins of preening. The whole town watched.",
	],
}
const VEHICLE_DEALER_POST_LINES: Array[String] = [
	"Dealership's OPEN! Who's buying the first wagon? (Not me. I'm broke. But who?)",
	"New wagon dealership in town! Carts for workers, carriages for show-offs. I know my lane.",
	"The dealership opened and I already want a carriage I can't afford. Classic.",
]
const VEHICLE_POST_LINES: Array[String] = [
	"{buyer} just bought a {vtype}! I saw them drive it home. JEALOUS.",
	"Somebody's got new wheels and it's {buyer}. The {vtype} life chose them.",
	"{buyer} and their new {vtype} just passed my window. SLOWLY. On purpose.",
]
const FAMINE_LINES: Array[String] = [
	"The {f} granaries are running empty. Somebody's eating their pride for dinner.",
	"Heard the {f} are down to crumbs. Sending thoughts. And maybe a pie.",
	"Short rations among the {f}. Their foragers are stripping the wilds bare.",
	"The {f} are counting grains now. Every. Single. Grain.",
]

const FAMINE_CRIT_LINES: Array[String] = [
	"FAMINE among the {f}! Empty bellies, hollow eyes. This is bad.",
	"The {f} are STARVING. If you've got food to spare, now's the time.",
	"Nothing in the pots for the {f}. Even the rats filed a complaint.",
	"Starvation among the {f} — the tavern went quiet when the news came in.",
]

const FAMINE_RELIEF_LINES: Array[String] = [
	"The {f} eat again! Granaries filling. Somebody pass the pies!",
	"Famine's over for the {f}. Tonight we feast in their honor.",
	"The {f} survived the hunger. The harvest came through!",
]


## Seeds (or refreshes) the rich famine rumor for one faction. Subject
## dedup ("famine:<faction>") keeps one live rumor per hunger — repeat
## calls refresh heat and rewrite the claim on escalation. The starving
## hear it first as witnesses; Squabble posts the news.
func _seed_famine_rumor(faction: String, critical: bool) -> Dictionary:
	var fname := _faction_name(faction)
	var text: String
	var heat: float
	if critical:
		text = "FAMINE! The %s are STARVING — empty bellies, hollow eyes, nothing in the pots." % fname
		heat = 0.9
	else:
		text = "The %s's granaries are running EMPTY — bellies rumbling, tempers short." % fname
		heat = 0.7
	var r: Dictionary = seed_rumor(text, "famine", "famine:" + faction,
		heat, -1, false, TRUTH_TRUE)
	r["famine_faction"] = faction
	var was: Variant = r.get("famine_critical", null)
	r["famine_critical"] = critical
	if was != null and bool(was) != critical:
		r["text"] = text
		r["text_orig"] = text
	if (r.get("knowers", []) as Array).is_empty():
		for i in 2:
			var w: Dictionary = _random_citizen(faction)
			if w.is_empty():
				break
			_witness(w, r)
		if critical:
			_event_post(FAMINE_CRIT_LINES, "famine", {"f": fname})
		else:
			_event_post(FAMINE_LINES, "famine", {"f": fname})
	return r


## The live (non-relief) famine rumor naming this faction, or {}.
func _live_famine_rumor(faction: String) -> Dictionary:
	for r: Dictionary in state["rumors"]:
		if String(r.get("kind", "")) == "famine" \
				and String(r.get("famine_faction", "")) == faction \
				and not bool(r.get("relief", false)):
			return r
	return {}


## The hunger lifted: one happy-news rumor + a Squabble feast post. The
## old famine rumor keeps its natural decay — grief fades, relief is new.
func _seed_famine_relief(faction: String) -> void:
	var fname := _faction_name(faction)
	var r: Dictionary = seed_rumor(
		"The %s eat again — granaries filling, the famine is OVER. Pass the pies." % fname,
		"famine", "famine_relief:" + faction, 0.5, -1, false, TRUTH_TRUE)
	r["famine_faction"] = faction
	r["relief"] = true
	_event_post(FAMINE_RELIEF_LINES, "famine", {"f": fname})


## The famine reaction matrix. Everyone hears hunger news and feels
## SOMETHING about it — no dead-end rumors:
##   - the STARVING faction despairs (critical: deep dread; shortage:
##     gnawing worry) — mood down, the hunger remembered.
##   - WAR-RIVALS cackle at the empty pots (schadenfreude — an enemy's
##     hunger is a rival's joy), harder when it's critical.
##   - everyone else grieves a little for the hungry.
##   - RELIEF: the recovered faction celebrates; everyone else feels
##     warm about the good news.
## Unhinged NPCs feel it 1.5x, matching the other matrices. Everything
## persists as memories + ruler-mood so the talk surfaces later.
func _famine_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var fam := String(r.get("famine_faction", ""))
	var fname := _faction_name(fam)
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if bool(r.get("relief", false)):
		if fam != "" and ufaction == fam:
			_mem.remember(u, "famine_relieved", rid, fname, ufaction, 0.9)
			_react_apply(u, 6.0 * mult, 0.0, "helped")
			return
		_mem.remember(u, "heard_famine", rid, fname, ufaction, 0.3)
		_react_apply(u, 1.0 * mult, 0.0, "helped")
		return
	var crit := bool(r.get("famine_critical", false))
	if fam != "" and ufaction == fam:
		_mem.remember(u, "starving_famine" if crit else "hungry_famine",
			rid, fname, ufaction, 1.0 if crit else 0.85)
		_react_apply(u, (-8.0 if crit else -4.0) * mult, 0.0, "starving")
		return
	if fam != "" and _rival_of(ufaction, fam):
		# Schadenfreude: nothing cheers a rival like an enemy's empty
		# pot — the cackling is HAPPY (festival-cancellation parity).
		_mem.remember(u, "mocked_famine", rid, fname, ufaction, 0.7)
		_react_apply(u, (5.0 if crit else 3.0) * mult, 0.0, "helped")
		return
	_mem.remember(u, "heard_famine", rid, fname, ufaction, 0.5)
	_react_apply(u, -1.5 * mult, 0.0, "friend_died")


## The live caravan-visit rumor, preferring the still-visiting one.
## Jeremy 2026-10-09 (hearsay flesh-out): the turning seasons seed rich
## rumors. Each year's season is its own rumor (the subject carries the
## year — last winter's talk doesn't stale this winter's dread), truth
## TRUE (the snow is on the ground), never press-eligible (the calendar
## needs no front page). A Squabble post marks the turn.
func _on_season_changed(season: String) -> void:
	var lines: Array = SEASON_LINES.get(season, [])
	if lines.is_empty():
		return
	var heat := 0.6
	if season == "Winter":
		heat = 0.7
	elif season == "Spring":
		heat = 0.55
	elif season == "Summer":
		heat = 0.5
	var yr := 1
	if _gs != null:
		var seas = _gs.get("seasons")
		if seas != null and seas.has_method("year"):
			yr = int(seas.year())
	var r: Dictionary = seed_rumor(String(lines[randi() % lines.size()]),
		"season", "season:%s:%d" % [season, yr], heat, -1, false,
		TRUTH_TRUE)
	r["season"] = season
	r["press_ok"] = false
	_season_squabble_posts(season)


func _season_squabble_posts(season: String) -> void:
	var lines: Array = SEASON_POST_LINES.get(season, [])
	if lines.is_empty():
		return
	_event_post(lines, "season", {})


## Jeremy 2026-10-09 (hearsay flesh-out): the seasonal reaction matrix.
## The turning year is the realm's biggest shared experience — everyone
## feels it, so everyone reacts:
##   - WINTER: dread (mood down, "dreaded_winter"). Farmers dread deeper
##     (the fields sleep; the stores decide who eats); a faction with a
##     live famine rumor dreads deepest ("starving_winter").
##   - SPRING: hope (mood up, "welcomed_spring"); farmers brightest.
##   - SUMMER: ease for most ("summer_ease"); soldiers grow restless
##     ("summer_restless", mood down).
##   - AUTUMN: harvest hope (mood up, "harvest_hope").
## Unhinged NPCs feel it 1.5x, matching the other matrices. Everything
## persists as memories + ruler-mood so the talk surfaces in later
## dialogue.
func _season_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var season := String(r.get("season", ""))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var uf := String(u.get("faction", ""))
	var job := String(u.get("job", ""))
	var rid := int(r.get("id", 0))
	match season:
		"Winter":
			var md := -5.0
			var mem := "dreaded_winter"
			if job == "farmer":
				md -= 3.0
			if not _live_famine_rumor(uf).is_empty():
				md -= 4.0
				mem = "starving_winter"
			_mem.remember(u, mem, rid, "season:Winter", uf, 0.8)
			_react_apply(u, md * mult, 0.0, "dismayed")
		"Spring":
			var ms := 4.0
			if job == "farmer":
				ms += 3.0
			_mem.remember(u, "welcomed_spring", rid, "season:Spring",
				uf, 0.8)
			_react_apply(u, ms * mult, 0.0, "cheerful")
		"Summer":
			if JobDefs.is_military(job):
				_mem.remember(u, "summer_restless", rid, "season:Summer",
					uf, 0.6)
				_react_apply(u, -2.0 * mult, 0.0, "grumpy")
			else:
				_mem.remember(u, "summer_ease", rid, "season:Summer",
					uf, 0.6)
				_react_apply(u, 2.0 * mult, 0.0, "cheerful")
		"Autumn":
			_mem.remember(u, "harvest_hope", rid, "season:Autumn", uf,
				0.8)
			_react_apply(u, 3.0 * mult, 0.0, "cheerful")


## Jeremy 2026-10-10 (hearsay flesh-out): weather arrivals — "a storm
## broke over the realm at dawn." Forecasts gossip about incoming
## disasters and the seasons cover the turning year; the arrival itself
## was the deaf thread. Only storm/rain/snow arrivals seed: clearing
## skies, cloud cover, and fog are routine and stay quiet. Subject
## dedups per kind ("weather:storm") so a stormy stretch refreshes one
## rumor instead of spamming the mill (repeat arrivals re-assert the
## heat floor after daily decay via seed_rumor's maxf dedup). Heat
## stays below PRESS_HEAT and press_ok is false — sky talk is tavern
## talk, never the front page, and never an advisor proposal (storm
## sits under QUEST_HEAT). Knower -1: everybody saw the sky.
func _on_weather_changed(kind: String) -> void:
	if kind != "storm" and kind != "rain" and kind != "snow":
		return  # quiet skies aren't gossip
	var lines: Array = WEATHER_LINES.get(kind, [])
	if lines.is_empty():
		return
	var heat := 0.65
	if kind == "snow":
		heat = 0.55
	elif kind == "rain":
		heat = 0.45
	var subject := "weather:" + kind
	var fresh := _live_rumor("weather", subject).is_empty()
	var r: Dictionary = seed_rumor(String(lines[randi() % lines.size()]),
		"weather", subject, heat, -1, false, TRUTH_TRUE)
	r["weather_kind"] = kind
	r["press_ok"] = false
	if fresh:
		_event_post(WEATHER_POST_LINES.get(kind, []), "weather", {})


## The realm reads a weather rumor in character — no dead-end rumors:
##   - STORM: dread for most ("storm_dread"); farmers fear for the
##     crops ("storm_crops", deeper); the unhinged LOVE it ("storm_thrill",
##     glee — drama from the heavens).
##   - RAIN: farmers welcome the soaking ("rain_blessing"); everyone
##     else takes mild comfort ("rain_news").
##   - SNOW: the realm edges toward winter dread ("snow_dread");
##     farmers count the stores ("snow_stores", deeper).
## Unhinged NPCs feel it 1.5x, matching the other matrices. Everything
## persists as memories + ruler-mood so the talk surfaces in later
## dialogue. All emotion args are EVENT_MAP keys (emotion_audit-safe).
func _weather_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var wk := String(r.get("weather_kind", ""))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var uf := String(u.get("faction", ""))
	var job := String(u.get("job", ""))
	var rid := int(r.get("id", 0))
	if wk == "storm" and SimUnhinged.is_unhinged(u):
		# Drama from the heavens — the unhinged are delighted.
		_mem.remember(u, "storm_thrill", rid, "weather:storm", uf, 0.7)
		_react_apply(u, 4.0 * mult, 0.0, "cheerful")
		return
	match wk:
		"storm":
			if job == "farmer":
				_mem.remember(u, "storm_crops", rid, "weather:storm",
					uf, 0.8)
				_react_apply(u, -5.0 * mult, 0.0, "disaster")
			else:
				_mem.remember(u, "storm_dread", rid, "weather:storm",
					uf, 0.6)
				_react_apply(u, -3.0 * mult, 0.0, "dismayed")
		"rain":
			if job == "farmer":
				_mem.remember(u, "rain_blessing", rid, "weather:rain",
					uf, 0.7)
				_react_apply(u, 3.0 * mult, 0.0, "cheerful")
			else:
				_mem.remember(u, "rain_news", rid, "weather:rain", uf,
					0.4)
				_react_apply(u, 1.0 * mult, 0.0, "cheerful")
		"snow":
			if job == "farmer":
				_mem.remember(u, "snow_stores", rid, "weather:snow",
					uf, 0.8)
				_react_apply(u, -5.0 * mult, 0.0, "disaster")
			else:
				_mem.remember(u, "snow_dread", rid, "weather:snow",
					uf, 0.6)
				_react_apply(u, -3.0 * mult, 0.0, "dismayed")


func _live_trader_rumor() -> Dictionary:
	var fallback: Dictionary = {}
	for r: Dictionary in state["rumors"]:
		if String(r.get("kind", "")) == "trade" \
				and bool(r.get("trader_visit", false)):
			if not bool(r.get("trader_gone", false)):
				return r
			fallback = r
	return fallback


## The trader reaction matrix. Everyone hears the caravan news and feels
## SOMETHING about it — no dead-end rumors:
##   - proud/haughty NPCs sniff at the caravan rabble (disgusted, small
##     mood dent) instead of joining the buzz.
##   - the HOST town buzzes: market day is exciting (mood up, memory).
##   - a faction that struck a deal brags: "got a steal from Funky Pants".
##   - late hearers whose faction never dealt regret missing it (sad).
##   - foreign factions with no deal just feel market-day curiosity.
## Unhinged NPCs feel it 1.5x, matching the smear/war/gossip paths.
func _trader_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var town_faction := String(r.get("trader_faction", ""))
	var tname := String(r.get("trader_name", "the trader"))
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	var persona := SimPersonality.persona_of(u)
	var stuffy := persona == "proud" or persona == "haughty" \
		or SimPersonality.trait_of(u, "proud") >= 0.6
	if stuffy:
		_mem.remember(u, "trader_sniffed", rid, tname, ufaction, 0.6)
		_react_apply(u, -2.0 * mult, 0.0, "grossed_out")
		return
	var my_deal: Dictionary = {}
	for d: Dictionary in (r.get("deals", []) as Array):
		if String(d.get("faction", "")) == ufaction:
			my_deal = d
			break
	if town_faction != "" and ufaction == town_faction:
		# The caravan is in YOUR town — market-day buzz.
		_mem.remember(u, "trader_visited", rid,
			String(r.get("trader_town", "town")), ufaction, 0.9)
		_react_apply(u, 6.0 * mult, 0.0, "helped")
		if not my_deal.is_empty():
			_mem.remember(u, "trader_deal", rid,
				String(my_deal.get("take", "goods")), ufaction, 0.9)
			_react_apply(u, 2.0 * mult, 0.0, "helped")
		return
	if not my_deal.is_empty():
		# Your faction got a steal — brag about it at the tavern.
		_mem.remember(u, "trader_deal", rid,
			String(my_deal.get("take", "goods")), ufaction, 0.9)
		_react_apply(u, 4.0 * mult, 0.0, "helped")
		return
	if bool(r.get("trader_gone", false)):
		# Heard too late — the caravan packed up before you got there.
		_mem.remember(u, "missed_caravan", rid, tname, ufaction, 0.7)
		_react_apply(u, -3.0 * mult, 0.0, "mocked")
		return
	_mem.remember(u, "trader_visited", rid,
		String(r.get("trader_town", "town")), ufaction, 0.5)
	_react_apply(u, 2.0 * mult, 0.0, "helped")


func _on_tribute_refused(demander: String, target: String) -> void:
	var r := seed_rumor("The %s REFUSED tribute to the %s. Bold. Dangerous. Bold." % [
		_faction_name(target), _faction_name(demander)],
		"news", target, 0.75, -1, false, TRUTH_TRUE)
	# Jeremy 2026-10-07 (hearsay flesh-out): the demander was only in the
	# text — record both sides so the refuser's defiance and the
	# demander's humiliation land in character.
	r["refuser"] = target
	r["demander"] = demander


func _on_relation_changed(faction_a: String, faction_b: String, state: String) -> void:
	# War declarations have their own handler; only hostile turns gossip here.
	if state != "hostile":
		return
	var other: String = faction_b if faction_a == _gs.player_faction else faction_a
	var r: Dictionary = seed_rumor("Tensions rise — the %s are openly hostile now. Watch the borders." % _faction_name(other),
		"news", other, 0.7, -1, false, TRUTH_TRUE)
	# Jeremy 2026-10-07 (hearsay flesh-out): both sides, for the
	# diplomacy reaction matrix (both sides brace for trouble).
	r["dip"] = "hostile"
	r["side_a"] = faction_a
	r["side_b"] = faction_b


## A deed worth gossiping about (HTML sqbGenDeeds): good deeds praised,
## bad deeds grumbled over — always naming the ruler verbatim.
## Jeremy 2026-10-06: the rumor no longer depends on finding a Squabble
## author — the grapevine hears about deeds even if nobody posts.
func gossip_deed(text: String, good: bool) -> void:
	var table: Array = DEED_PRAISE if good else DEED_GRUMBLE
	var line: String = String(table[randi() % table.size()])
	line = line.replace("{k}", _gs.ruler_name)
	line = line.replace("{t}", text.left(90))
	var kid := -1
	if phone != null and phone.has_method("npc_post"):
		var author: Dictionary = _random_author()
		if not author.is_empty():
			phone.npc_post(author, line, "deed")
			kid = int(author.get("id", 0))
	var deed_r: Dictionary = seed_rumor(line, "deed", "", 0.8 if good else 0.85, kid, false, TRUTH_TRUE)
	deed_r["deed_good"] = good
	# Jeremy 2026-10-06 (lane 6): praise/grumble about the crown moves
	# the player faction's standing once, at seed (no waiting for a
	# hearer). Dedup keeps the flag.
	if not bool(deed_r.get("rep_faction_applied", false)):
		deed_r["rep_faction_applied"] = true
		_faction_rep(String(_gs.player_faction),
			REP_FACTION_DEED_GOOD if good else REP_FACTION_DEED_BAD)


## --- investigation + reputation + rumor quests (lane 6, 2026-10-06) ----

## Enemy strategic proposals are worth gossiping about: a non-player
## faction's buildup/war authorization seeds a "mass troops" rumor the
## player can investigate or scout. The player's own proposals never seed
## gossip about themselves. Truth stays unknown — the crown hasn't
## verified tavern talk about closed war councils.
func _on_strategic_proposal(p: Dictionary) -> void:
	var faction := String(p.get("faction", ""))
	var pf := String(_gs.player_faction)
	if faction == "" or faction == pf:
		return
	var kind := String(p.get("kind", ""))
	if kind != SimProposals.KIND_MAJOR_BUILDUP \
			and kind != SimProposals.KIND_DECLARE_WAR:
		return
	var fname := _faction_name(faction)
	var knower: Dictionary = _random_citizen(faction)
	var kid: int = int(knower.get("id", -1)) \
		if not knower.is_empty() else -1
	if kind == SimProposals.KIND_MAJOR_BUILDUP:
		# subject = the faction building up, so _quest_tick can propose
		# scouting THEM specifically.
		seed_rumor("Scouts swear the %s are massing troops near the border. Drums at night, they say." % fname,
			"war", faction, 0.8, kid)
	else:
		# Jeremy 2026-10-08 (hearsay flesh-out): the proposal names its
		# target (details.target) — record BOTH sides (side_a = plotter,
		# side_b = target) plus war_plot=true, so the war-plot reaction
		# matrix reacts in character: the target fears the looming drums,
		# the plotters grimly anticipate. Subject stays the plotter so
		# proposal decisions and declarations refresh the same rumor.
		var target := String(
			(p.get("details", {}) as Dictionary).get("target", ""))
		var text := "Word in the taverns: the %s mean war. Their war council met behind closed doors." % fname
		if target != "":
			text = "Word in the taverns: the %s mean war with the %s. Their war council met behind closed doors." % [
				fname, _faction_name(target)]
		var r := seed_rumor(text, "war", faction, 0.85, -1)
		r["side_a"] = faction
		r["side_b"] = target
		r["war_plot"] = true
		# Fields must be stamped before the first _on_heard — seed with
		# no knower, then hand the rumor to the first citizen ourselves
		# (smear-lie parity: _seed_malicious_smear). A seed-time knower
		# would otherwise hear a facet-less rumor and land in the generic
		# reception with a spurious "disaster" emotion.
		if kid > 0:
			var ku: Dictionary = _gs.get_unit(kid)
			if not ku.is_empty():
				(r["knowers"] as Array).append(kid)
				_on_heard(ku, r, {})


## Jeremy 2026-10-06 (hearsay gap coverage): towns were founded in total
## silence — bus.town_founded fired with nobody listening. New towns now
## get a rumor and a Squabble post.
func _on_town_founded(town: Dictionary) -> void:
	var tname := String(town.get("name", "a new town"))
	var fname := _faction_name(String(town.get("faction", "")))
	_event_post(TOWN_FOUNDED_LINES, "news", {"t": tname, "f": fname})
	var r: Dictionary = seed_rumor("The %s founded the town of %s!" % [fname, tname],
		"news", "town:" + tname, 0.55, -1, false, TRUTH_TRUE)
	# Jeremy 2026-10-07 (hearsay flesh-out): the founder, for the
	# diplomacy reaction matrix — the founding faction celebrates.
	r["dip"] = "town"
	r["founder"] = String(town.get("faction", ""))


## Jeremy 2026-10-06 (hearsay gap coverage): proposal DECISIONS were deaf
## to the grapevine — only the proposal itself gossiped. The player's own
## decisions stay off the street — advisers report those in Messenger.
## Jeremy 2026-10-09 (hearsay flesh-out): the proposal grapevine was
## half-dead in live play — bus.strategic_proposal only ever fires for
## the PLAYER's faction (the proposals.gd emit is player-gated) while the
## proposal handler ignores the player, so AI war plots and troop
## buildups never reached the mill (the war-plot tests emitted the signal
## by hand). AI factions decide synchronously inside propose(), so the
## decided signal is the grapevine's only hook — every gossip-worthy
## kind is dispatched here now.
func _on_strategic_proposal_decided(p: Dictionary, approved: bool) -> void:
	var faction := String(p.get("faction", ""))
	var pf := String(_gs.player_faction)
	if faction == "" or faction == pf:
		return
	match String(p.get("kind", "")):
		SimProposals.KIND_DECLARE_WAR:
			_on_war_proposal_decided(p, faction, approved)
		SimProposals.KIND_MAJOR_BUILDUP:
			_on_buildup_decided(faction, approved)
		SimProposals.KIND_SUE_FOR_PEACE:
			_on_peace_feeler_decided(p, faction, approved)
		# monastery_assault / expand_territory: the assault/founding
		# itself gossips; the closed-council authorization stays quiet
		# (a deliberate leak would betray the attacker's timing).


## The declare-war decision (split out of _on_strategic_proposal_decided,
## 2026-10-09: the decided handler now dispatches by proposal kind).
## Denied war proposals are tavern comedy: the drums beat, the council
## blinked (the rumor text is corrected, heat 0.65: hot enough to reach
## the ruler, too cool for scout quests or the press); approvals heat the
## war talk to full (war_declared fires right after with its own rumor);
## expiries just let the drums go quiet.
func _on_war_proposal_decided(p: Dictionary, faction: String,
		approved: bool) -> void:
	var fname := _faction_name(faction)
	var r: Dictionary = _live_rumor("war", faction)
	if approved:
		if not r.is_empty():
			r["heat"] = maxf(float(r.get("heat", 0.0)), 1.0)
		return
	if String(p.get("status", "")) == SimProposals.STATUS_DENIED:
		_event_post(WAR_CHICKEN_LINES, "war", {"f": fname})
		var dtext := "The %s talked war and then chickened out — their own council said no!" % fname
		# Jeremy 2026-10-08 (hearsay flesh-out): the plot is dead but the
		# taverns aren't done with it — flip to tavern comedy
		# (plot_denied): the would-be target breathes relief, the plotters
		# get roasted, the realm laughs. Sides come from the decided
		# proposal defensively (real flow carries details.target).
		var dtarget := String(
			(p.get("details", {}) as Dictionary).get("target", ""))
		if r.is_empty():
			var dr: Dictionary = seed_rumor(dtext, "war", faction,
				0.65, -1, false, TRUTH_TRUE)
			dr["quest_spawned"] = true
			dr["side_a"] = faction
			dr["side_b"] = dtarget
			dr["war_plot"] = true
			dr["plot_denied"] = true
		else:
			r["text"] = dtext
			r["heat"] = 0.65
			r["quest_spawned"] = true
			r["war_plot"] = true
			r["plot_denied"] = true
			if dtarget != "":
				r["side_b"] = dtarget
	else:
		# Expired (ignored) proposals: no post, the drums just go quiet.
		if not r.is_empty():
			r["heat"] = minf(float(r.get("heat", 0.0)), 0.35)


## Jeremy 2026-10-09 (hearsay flesh-out): troop buildups were the other
## half of the dead proposal grapevine — the "mass troops" rumor only
## lived in the never-firing _on_strategic_proposal handler. An approved
## buildup now seeds it at decision time: subject = the faction building
## up (so _quest_tick can propose scouting THEM specifically), truth
## unknown (unverified tavern talk), heat 0.8 (scout-quest eligible).
## A denied buildup beat no drums — the mill stays quiet.
func _on_buildup_decided(faction: String, approved: bool) -> void:
	if not approved:
		return
	var fname := _faction_name(faction)
	seed_rumor("Scouts swear the %s are massing troops near the border. Drums at night, they say." % fname,
		"war", faction, 0.8, -1, false, TRUTH_UNKNOWN)


## Jeremy 2026-10-09 (hearsay flesh-out): peace feelers were the last deaf
## proposal — a losing faction's council debating surrender gossiped
## nowhere. An APPROVED feeler needs no rumor of its own: _execute runs
## offer_surrender on the same tick and _on_surrender_offered seeds the
## rich white-flag rumor (same event — no double coverage). A DENIED
## feeler is pure tavern gold the mill never heard: the beaten faction
## talked of begging and their own council said no — the war grinds on.
## Heat 0.75 (the ruler hears; the press might if it spreads);
## quest_spawned marks it confirmed council gossip, not a scout lead.
func _on_peace_feeler_decided(p: Dictionary, faction: String,
		approved: bool) -> void:
	if approved:
		return
	if String(p.get("status", "")) != SimProposals.STATUS_DENIED:
		return  # expired: the drums of peace just go quiet
	var target := String(
		(p.get("details", {}) as Dictionary).get("target", ""))
	var fname := _faction_name(faction)
	var tname := _faction_name(target) if target != "" else "their enemies"
	_event_post(PEACE_FEELER_LINES, "war", {"f": fname, "t": tname})
	var r: Dictionary = seed_rumor(
		"The %s talked of begging the %s for peace — their own council said no! The war grinds on." % [fname, tname],
		"war", "peacefeeler:" + faction, 0.75, -1, false, TRUTH_TRUE)
	r["quest_spawned"] = true
	r["peace_feeler"] = true
	r["side_a"] = faction  # the would-be beggars
	r["side_b"] = target  # the would-be recipients


## Jeremy 2026-10-06 (hearsay gap coverage): fires raged in the grapevine
## but died in silence — fire_out fired with nobody listening. The shared
## ("disaster", "wildfire") rumor now cools and the realm posts its
## relief. (Covers both water put-outs and natural burnout: both route
## through disasters.extinguish().)
func _on_fire_out(_fire_id: int) -> void:
	var fr: Dictionary = _live_rumor("disaster", "wildfire")
	if fr.is_empty():
		return
	fr["heat"] = minf(float(fr.get("heat", 0.0)), 0.3)
	_event_post(FIRE_OUT_LINES, "disaster", {})


## Jeremy 2026-10-06 (hearsay gap coverage): disaster_left fired with
## nobody listening. Flood endings cool the flood rumor and post relief.
## Other kinds are ignored defensively — disasters.gd also emits this
## with unit job names, which are not disasters.
func _on_disaster_left(kind: String) -> void:
	if kind != "flood":
		return
	var fr: Dictionary = _live_rumor("disaster", "flood")
	if fr.is_empty():
		return
	fr["heat"] = minf(float(fr.get("heat", 0.0)), 0.3)
	_event_post(FLOOD_OUT_LINES, "disaster", {})


## --- reputation ------------------------------------------------------

## Per-NPC reputation 0..100 (50 = unknown). Believed rumors move it:
## smears drag the target down, scandals destroy. Surfaced in the Rumors
## app and on NPC profiles.
func reputation_of(unit_id: int) -> float:
	var reps: Dictionary = state.get("npc_rep", {})
	return clampf(float(reps.get(str(unit_id), REP_DEFAULT)), 0.0, 100.0)


func rep_label(v: float) -> String:
	if v >= 80.0:
		return "Beloved"
	if v >= 60.0:
		return "Liked"
	if v >= 40.0:
		return "Known"
	if v >= 20.0:
		return "Shady"
	return "Despised"


func _bump_npc_rep(unit_id: int, delta: float) -> void:
	if unit_id <= 0:
		return
	var reps: Dictionary = state["npc_rep"]
	var key := str(unit_id)
	reps[key] = clampf(float(reps.get(key, REP_DEFAULT)) + delta,
		0.0, 100.0)


func _faction_rep(faction: String, delta: float) -> void:
	if faction == "":
		return
	if _gs.diplomacy != null \
			and _gs.diplomacy.has_method("tarnish_reputation"):
		_gs.diplomacy.tarnish_reputation(faction, delta)


## A hearer carries the rumor now — reputations shift. One shift per
## (rumor, hearer) so the grapevine can't double-count; per-rumor caps
## keep a single whisper from ending a career.
func _rep_tick(u: Dictionary, r: Dictionary) -> void:
	var uid := int(u.get("id", 0))
	if uid <= 0:
		return
	var applied: Array = r.get("rep_applied", [])
	if applied.has(uid):
		return
	applied.append(uid)
	r["rep_applied"] = applied
	var kind := String(r.get("kind", "misc"))
	if kind == "smear":
		var tid := int(r.get("target_id", 0))
		if tid > 0:
			var shifted: Dictionary = r.get("rep_shifted", {})
			var key := str(tid)
			var total := float(shifted.get(key, 0.0))
			if total > -REP_SMEAR_CAP:
				shifted[key] = total - REP_SMEAR_HIT
				r["rep_shifted"] = shifted
				_bump_npc_rep(tid, -REP_SMEAR_HIT)
	# Jeremy 2026-10-08 (hearsay flesh-out): a NAMED thief's reputation
	# bleeds with every hearer — the town remembers who stole from whom.
	# Unseen thieves dodge it: no name, no shame.
	if kind == "crime":
		var ccid := int(r.get("crook_id", 0))
		if ccid > 0:
			var cshifted: Dictionary = r.get("rep_shifted", {})
			var ckey := str(ccid)
			var ctotal := float(cshifted.get(ckey, 0.0))
			if ctotal > -REP_CRIME_CAP:
				cshifted[ckey] = ctotal - REP_CRIME_HIT
				r["rep_shifted"] = cshifted
				_bump_npc_rep(ccid, -REP_CRIME_HIT)
	# Faction-level shifts (smear target faction, deed praise/grumble)
	# are applied once at seed time (seed_player_smear / gossip_deed) —
	# they don't wait for a hearer.


## --- investigation ---------------------------------------------------

## The player investigates a rumor from the Rumors app: the crown asks
## around (DM flow — answers arrive as Messenger messages from the NPCs
## asked). Respondents answer from what they actually know: knowers
## confirm true claims and deny false ones; nobody bluffs knowledge they
## don't have. A false claim denied by 2+ respondents is DEBUNKED — it
## dies with a Gazette correction. A true claim confirmed by 2+ is
## VERIFIED (heat bump). Unknown-truth talk stays inconclusive.
## HARD LINE: slur rumors are never debunked — the incident really
## happened, and the answers say so furiously.
func investigate_rumor(rumor_id: int) -> Dictionary:
	var r := _rumor_by_id(rumor_id)
	if r.is_empty():
		return {"ok": false, "reason": "no such rumor"}
	if bool(r.get("debunked", false)):
		return {"ok": false, "reason": "already debunked"}
	var respondents := _pick_respondents(r, INVESTIGATE_N)
	if respondents.is_empty():
		return {"ok": false, "reason": "no one to ask"}
	var answers: Array = []
	var confirms := 0
	var denies := 0
	for u: Dictionary in respondents:
		var a := answer_about_rumor(u, r)
		answers.append(a)
		match String(a.get("stance", "")):
			"confirm":
				confirms += 1
			"deny":
				denies += 1
		if phone != null and phone.has_method("npc_message"):
			phone.npc_message(int(u.get("id", 0)), String(a.get("text", "")))
	var verdict := rumor_truth(r)
	var outcome := "inconclusive"
	if String(r.get("kind", "misc")) != "slur":
		if verdict == TRUTH_FALSE and denies >= 2:
			_debunk(r)
			outcome = "debunked"
		elif verdict == TRUTH_TRUE and confirms >= 2:
			r["verified"] = true
			r["heat"] = minf(1.0, float(r.get("heat", 0.0)) + 0.1)
			# Jeremy 2026-10-08 (hearsay flesh-out): the believers
			# called it — they remember calling it.
			_verified_reactions(r)
			outcome = "confirmed"
	r["investigations"] = int(r.get("investigations", 0)) + 1
	return {"ok": true, "rumor_id": rumor_id, "answers": answers,
		"verdict": verdict, "outcome": outcome}


func _rumor_by_id(rid: int) -> Dictionary:
	for r: Dictionary in state["rumors"]:
		if int(r.get("id", 0)) == rid:
			return r
	return {}


func rumor_truth(r: Dictionary) -> String:
	var t := String(r.get("truth", TRUTH_UNKNOWN))
	if t != TRUTH_TRUE and t != TRUTH_FALSE:
		return TRUTH_UNKNOWN
	return t


## Who the investigators ask: knowers first (real knowledge), then the
## crown's own citizens, then anyone alive. Blocked NPCs are silent —
## never tapped, never DM'd.
func _pick_respondents(r: Dictionary, n: int) -> Array:
	var out: Array = []
	var seen := {}
	var pf := String(_gs.player_faction)
	var knowers: Array = r.get("knowers", [])
	for kid: Variant in knowers:
		if out.size() >= n:
			break
		var u: Dictionary = _gs.get_unit(int(kid))
		if _askable(u, seen):
			out.append(u)
			seen[int(u.get("id", 0))] = true
	for u2: Dictionary in _gs.units:
		if out.size() >= n:
			break
		if String(u2.get("faction", "")) != pf:
			continue
		if _askable(u2, seen):
			out.append(u2)
			seen[int(u2.get("id", 0))] = true
	for u3: Dictionary in _gs.units:
		if out.size() >= n:
			break
		if _askable(u3, seen):
			out.append(u3)
			seen[int(u3.get("id", 0))] = true
	return out


func _askable(u: Dictionary, seen: Dictionary) -> bool:
	if u.is_empty():
		return false
	var uid := int(u.get("id", 0))
	if uid <= 0 or seen.has(uid):
		return false
	if not bool(u.get("alive", true)):
		return false
	if phone != null and phone.has_method("is_blocked") \
			and bool(phone.is_blocked(uid)):
		return false
	return true


## One NPC's answer about a rumor: confirm/deny/shrug from what they
## actually know. Slur rumors ALWAYS get condemnation — the incident is
## real, nobody denies it, nobody finds it funny, nobody softens it.
func answer_about_rumor(u: Dictionary, r: Dictionary) -> Dictionary:
	var kind := String(r.get("kind", "misc"))
	if kind == "slur":
		return {"stance": "confirm", "unit_id": int(u.get("id", 0)),
			"text": _invest_line(u, INVEST_SLUR_CONDEMN, r)}
	var knower := (r.get("knowers", []) as Array).has(int(u.get("id", 0)))
	# Jeremy 2026-10-08 (hearsay flesh-out): crime rumors are witnessed
	# fact — knowers confirm, and witnesses name the thief (HTML "THIEF!
	# I SAW THE WHOLE THING!" parity). Unseen thieves get the honest
	# version: the crime happened, the crook didn't.
	if kind == "crime":
		if not knower:
			return {"stance": "shrug", "unit_id": int(u.get("id", 0)),
				"text": _invest_line(u, INVEST_SHRUG, r)}
		var cpool := INVEST_CRIME_CONFIRM \
			if int(r.get("crook_id", 0)) > 0 else INVEST_CRIME_UNSEEN
		return {"stance": "confirm", "unit_id": int(u.get("id", 0)),
			"text": _invest_line(u, cpool, r)}
	if not knower:
		return {"stance": "shrug", "unit_id": int(u.get("id", 0)),
			"text": _invest_line(u, INVEST_SHRUG, r)}
	var truth := rumor_truth(r)
	if truth == TRUTH_TRUE:
		return {"stance": "confirm", "unit_id": int(u.get("id", 0)),
			"text": _invest_line(u, INVEST_CONFIRM, r)}
	if truth == TRUTH_FALSE:
		return {"stance": "deny", "unit_id": int(u.get("id", 0)),
			"text": _invest_line(u, INVEST_DENY, r)}
	return {"stance": "shrug", "unit_id": int(u.get("id", 0)),
		"text": _invest_line(u, INVEST_HEARD_UNSURE, r)}


func _invest_line(u: Dictionary, pool: Array, r: Dictionary) -> String:
	var line: String = String(pool[randi() % pool.size()])
	line = line.replace("{t}", String(
		r.get("text_orig", r.get("text", ""))).left(90))
	var who := SimPersonality.display_name(u)
	if who != "":
		line = "[%s] says: %s" % [who, line]
	return line


## A debunked rumor dies: heat zeroed (decay sweeps it), flagged so the
## press never prints it, and the Gazette runs a correction — honestly
## labeled, anti-loop safe (the headline can't match any rumor's own
## press headline, and the story seeds only a from_gazette rumor).
## HARD LINE: slur rumors can never be debunked. Ever.
func _debunk(r: Dictionary) -> void:
	if String(r.get("kind", "misc")) == "slur":
		return
	if bool(r.get("debunked", false)):
		return
	r["debunked"] = true
	r["heat"] = 0.0
	r["verified"] = false
	# Jeremy 2026-10-08 (hearsay flesh-out): the lie dies in public —
	# its believers feel sheepish, and a smeared target's name is
	# cleared (the reputation this rumor took is given back).
	_debunk_reactions(r)
	var court = _gs.court_sys
	if court == null or not court.has_method("publish_story"):
		return
	var claim := String(r.get("text_orig", r.get("text", ""))).strip_edges()
	if claim.length() > 96:
		claim = claim.left(93) + "..."
	court.publish_story("RUMOR MILL CORRECTION: %s" % claim,
		"The crown's investigators looked into the tavern talk — \"%s\" — and found it baseless. Consider it buried. The Gazette regrets the whisper." % claim,
		"court")


## Jeremy 2026-10-08 (hearsay flesh-out): a debunked rumor's fallout.
## Every believer remembers swallowing the lie (sheepish — the
## conversation engine can surface "I can't believe I bought that"),
## and a false smear's target gets their name back: exactly the
## reputation this rumor's believers took (tracked in rep_shifted) is
## restored. Slur rumors never reach here (the hard line holds).
func _debunk_reactions(r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var kind := String(r.get("kind", "misc"))
	for kid: Variant in (r.get("knowers", []) as Array).duplicate():
		var u: Dictionary = _gs.get_unit(int(kid))
		if u.is_empty() or not bool(u.get("alive", true)):
			continue
		_mem.remember(u, "believed_a_lie", rid, kind,
			String(u.get("faction", "")), 0.6)
		_react_apply(u, -3.0, 0.0, "mocked")
	if kind == "smear":
		var tid := int(r.get("target_id", 0))
		var shifted: Dictionary = r.get("rep_shifted", {})
		var taken := float(shifted.get(str(tid), 0.0))
		if tid > 0 and taken < 0.0:
			_bump_npc_rep(tid, -taken)


## Jeremy 2026-10-08 (hearsay flesh-out): a verified rumor vindicates
## its believers — they called it, and the realm knows they called it.
func _verified_reactions(r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var kind := String(r.get("kind", "misc"))
	for kid: Variant in (r.get("knowers", []) as Array).duplicate():
		var u: Dictionary = _gs.get_unit(int(kid))
		if u.is_empty() or not bool(u.get("alive", true)):
			continue
		_mem.remember(u, "called_it_right", rid, kind,
			String(u.get("faction", "")), 0.5)
		_react_apply(u, 2.0, 0.0, "helped")


## --- rumor quests ----------------------------------------------------

## Hot rumors become advisor proposals: talk of an enemy buildup sends
## the War Advisor asking to scout; talk of a hidden cache sends the
## Civic Advisor asking to mount an expedition. One proposal per rumor
## (quest_spawned), dedup/cooldown handled by the proposal protocol.
func _quest_tick() -> void:
	var props = _gs.get("proposals")
	if props == null or not props.has_method("propose"):
		return
	var pf := String(_gs.player_faction)
	if pf == "":
		return
	for r: Dictionary in state["rumors"]:
		if bool(r.get("quest_spawned", false)) \
				or bool(r.get("debunked", false)):
			continue
		if float(r.get("heat", 0.0)) < QUEST_HEAT:
			continue
		var kind := String(r.get("kind", "misc"))
		var claim := String(
			r.get("text_orig", r.get("text", ""))).left(80)
		if kind == "war":
			# Jeremy 2026-10-09 (hearsay flesh-out): a loosed sun-spear
			# is not a troop buildup — the War Advisor doesn't "scout"
			# a missile already in the air ("nuke_launch:gnomes" is not
			# a faction to scout). The dread spreads on its own.
			if bool(r.get("nuke_launch", false)):
				continue
			var subj := String(r.get("subject", ""))
			if subj == "" or subj == pf:
				continue
			# Jeremy 2026-10-07 (hearsay flesh-out): conquest rumors are
			# confirmed-true captures (the Gazette reported the fall
			# directly) — not unverified buildup talk. Scouting a fallen
			# monastery is moot, and the per-post subject is not a faction.
			if r.has("holder_new"):
				continue
			if _gs.diplomacy != null and _gs.diplomacy.has_method(
					"relation_state") \
					and String(_gs.diplomacy.relation_state(pf, subj)) \
					== "war":
				continue  # already at war — scouting is moot
			var res: Dictionary = props.propose(pf,
				SimProposals.KIND_SCOUT,
				{"target": subj, "rumor_id": int(r.get("id", 0)),
				"rumor_text": claim, "advisor": "war",
				"brief": "Tavern talk says the %s are massing for war: \"%s\" The War Advisor wants scouts on the border before the drums beat for real." % [
					_faction_name(subj), claim]})
			if bool(res.get("ok", false)):
				r["quest_spawned"] = true
		elif kind == "cache":
			var res2: Dictionary = props.propose(pf,
				SimProposals.KIND_INVESTIGATE,
				{"rumor_id": int(r.get("id", 0)), "rumor_text": claim,
				"advisor": "civic",
				"brief": "Tavern talk of a hidden cache: \"%s\" The Civic Advisor wants a scout party sent after it." % claim})
			if bool(res2.get("ok", false)):
				r["quest_spawned"] = true


## The crown approved a rumor-born proposal — the advisors act.
## Called by SimProposals._execute (guarded for bare tests).
func quest_approved(kind: String, details: Dictionary) -> void:
	if kind == SimProposals.KIND_SCOUT:
		_scout_report(String(details.get("target", "")), details)
	elif kind == SimProposals.KIND_INVESTIGATE:
		_cache_expedition(details)


## Scouts come home with a real report: military-strength intel on the
## rumored enemy, DM'd by the War Advisor. If the realm truly is at war
## with them, the rumor is marked verified — gossip grounded in fact.
func _scout_report(target: String, details: Dictionary) -> void:
	var pf := String(_gs.player_faction)
	var adv := _advisor_unit(pf, "advisor_war")
	var intel := "Scouts are still out, sire — no word yet."
	if target != "" and _gs.diplomacy != null \
			and _gs.diplomacy.has_method("military_strength"):
		var foe: float = _gs.diplomacy.military_strength(target)
		var own: float = _gs.diplomacy.military_strength(pf)
		var verdict := "We match them blade for blade."
		if foe > own * 1.5:
			verdict = "They outmatch us — I advise caution, sire."
		elif own > foe * 1.5:
			verdict = "We outmatch them. Their buildup is bluster."
		intel = "Scout report on the %s: their strength runs about %d to our %d. %s" % [
			_faction_name(target), int(foe), int(own), verdict]
		if _gs.diplomacy.has_method("relation_state") \
				and String(_gs.diplomacy.relation_state(pf, target)) \
				== "war":
			var rr := _rumor_by_id(int(details.get("rumor_id", 0)))
			if not rr.is_empty():
				rr["verified"] = true
	_advisor_dm(adv, intel)


## The Civic Advisor dispatches a scout party after the rumored cache.
## They report back in a day or two: real caches pay gold, duds pay
## humility. Real finds verify the rumor that sent them.
func _cache_expedition(details: Dictionary) -> void:
	var pf := String(_gs.player_faction)
	var adv := _advisor_unit(pf, "advisor_civic")
	_advisor_dm(adv,
		"Scout party dispatched after the rumored cache, sire. They'll report back in a day or two.")
	var day_num := 1
	if _gs != null and _gs.get("day_number") != null:
		day_num = int(_gs.day_number)
	(state["pending_caches"] as Array).append({
		"day": day_num + 1,
		"rumor_id": int(details.get("rumor_id", 0)),
		"faction": pf,
		"real": randf() < 0.55,
	})


func _resolve_pending_caches() -> void:
	var pending: Array = state.get("pending_caches", [])
	if pending.is_empty():
		return
	var day_num := 1
	if _gs != null and _gs.get("day_number") != null:
		day_num = int(_gs.day_number)
	var done: Array = []
	for c: Dictionary in pending:
		if int(c.get("day", 0)) > day_num:
			continue
		done.append(c)
		var pf := String(c.get("faction", String(_gs.player_faction)))
		var adv := _advisor_unit(pf, "advisor_civic")
		if bool(c.get("real", false)):
			var haul := randf_range(150.0, 400.0)
			if _gs.resources != null \
					and _gs.resources.has_method("add_resource"):
				_gs.resources.add_resource(pf, "gold", haul, true)
			_advisor_dm(adv,
				"The cache was REAL, sire! The scouts hauled back %d gold. The taverns will sing of this." % int(haul))
			var rr := _rumor_by_id(int(c.get("rumor_id", 0)))
			if not rr.is_empty():
				rr["verified"] = true
				rr["heat"] = minf(1.0,
					float(rr.get("heat", 0.0)) + 0.15)
		else:
			_advisor_dm(adv,
				"Dead end, sire — the 'cache' was old bones and wishful thinking. The scouts came home empty-handed.")
	for c2: Dictionary in done:
		pending.erase(c2)


func _advisor_unit(faction: String, job: String) -> Dictionary:
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) == faction \
				and String(u.get("job", "")) == job \
				and bool(u.get("alive", true)):
			return u
	return {}


## Advisor DMs ride the normal DM flow (blocked advisors stay silent).
## Guarded for bare-sim tests without a phone.
func _advisor_dm(adv: Dictionary, text: String) -> void:
	if adv.is_empty():
		return
	if phone == null or not phone.has_method("npc_message"):
		return
	var aid := int(adv.get("id", 0))
	if phone.has_method("is_blocked") and bool(phone.is_blocked(aid)):
		return
	phone.npc_message(aid, text)


## --- save -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return state.duplicate(true)


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	state = {
		"rumors": (data.get("rumors", []) as Array).duplicate(true),
		"seq": int(data.get("seq", 1)),
		"last_press_day": int(data.get("last_press_day", 0)),
		"npc_rep": (data.get("npc_rep", {}) as Dictionary).duplicate(true),
		"pending_caches": (data.get("pending_caches", []) as Array).duplicate(true),
		# Jeremy 2026-10-07 (hearsay flesh-out): the conquest holder
		# snapshot survives save/load; pre-matrix saves rebuild it from
		# the live sims (or on the next day tick if they're not up yet).
		"holders": (data.get("holders", {}) as Dictionary).duplicate(true),
	}
	if (state.get("holders", {}) as Dictionary).is_empty():
		_snapshot_holders()
	# Jeremy 2026-10-06: backfill distortion schema on pre-overhaul saves.
	for r: Dictionary in state["rumors"]:
		if not r.has("text_orig"):
			r["text_orig"] = String(r.get("text", ""))
		if not r.has("distortions"):
			r["distortions"] = 0
		# Jeremy 2026-10-06: backfill the press-pass schema — old rumors
		# were never in print and never Gazette-born.
		if not r.has("published"):
			r["published"] = false
		if not r.has("from_gazette"):
			r["from_gazette"] = false
		# Jeremy 2026-10-06 (lane 6): backfill investigation/reputation
		# schema on pre-expansion saves.
		if not r.has("truth"):
			r["truth"] = TRUTH_UNKNOWN
		if not r.has("debunked"):
			r["debunked"] = false
		if not r.has("verified"):
			r["verified"] = false
		if not r.has("quest_spawned"):
			r["quest_spawned"] = false
		# Jeremy 2026-10-06 (hearsay flesh-out): backfill the witness
		# schema — pre-fleshout saves never tracked first-hand witnesses.
		if not r.has("witnesses"):
			r["witnesses"] = []
		# Jeremy 2026-10-08 (hearsay flesh-out): backfill the war-plot
		# schema — old plot rumors never marked themselves as unconfirmed
		# plots (they stay generic instead of hitting the plot matrix).
		if not r.has("war_plot"):
			r["war_plot"] = false
		if not r.has("plot_denied"):
			r["plot_denied"] = false
		# Jeremy 2026-10-07 (hearsay flesh-out): backfill the war-sides
		# schema — old war/surrender rumors never recorded declarer,
		# defender, loser, or winner; they get the generic reception.
		if not r.has("side_a"):
			r["side_a"] = ""
		if not r.has("side_b"):
			r["side_b"] = ""
		if not r.has("loser"):
			r["loser"] = ""
		if not r.has("winner"):
			r["winner"] = ""
		# Jeremy 2026-10-07 (hearsay flesh-out): backfill the
		# conquest/betrayal schema — old capture rumors never recorded
		# the loser, and old treaty/tribute/building rumors never
		# recorded the other side; they get the generic reception.
		if not r.has("holder_old"):
			r["holder_old"] = ""
		if not r.has("holder_new"):
			r["holder_new"] = ""
		if not r.has("betrayer"):
			r["betrayer"] = ""
		if not r.has("betrayed"):
			r["betrayed"] = ""
		if not r.has("refuser"):
			r["refuser"] = ""
		if not r.has("demander"):
			r["demander"] = ""
		if not r.has("lost_holder"):
			r["lost_holder"] = ""
		# Jeremy 2026-10-07 (hearsay flesh-out): backfill the diplomacy
		# subtype schema — old diplomatic rumors never recorded the
		# subtype, payer, receiver, or founder; they get the generic
		# reception (side_a/side_b are backfilled above).
		if not r.has("dip"):
			r["dip"] = ""
		if not r.has("payer"):
			r["payer"] = ""
		if not r.has("receiver"):
			r["receiver"] = ""
		if not r.has("founder"):
			r["founder"] = ""
		# Jeremy 2026-10-07 (hearsay flesh-out): backfill the disaster
		# schema — old disaster rumors never recorded the stricken town;
		# they get the generic reception.
		if not r.has("hit_faction"):
			r["hit_faction"] = ""
		if not r.has("hit_town"):
			r["hit_town"] = ""
		# Jeremy 2026-10-07 (hearsay flesh-out): backfill the obituary
		# schema — old death rumors never recorded the dead's faction;
		# they get the generic reception.
		if not r.has("dead_faction"):
			r["dead_faction"] = ""
		# Jeremy 2026-10-07 (hearsay flesh-out): backfill the doubt
		# schema — old rumors never tracked their skeptics; doubt
		# pressure starts at zero.
		if not r.has("doubters"):
			r["doubters"] = []
		# Jeremy 2026-10-08 (hearsay flesh-out): backfill the
		# false-smear source schema — old smears never recorded who
		# invented the lie.
		if not r.has("source_id"):
			r["source_id"] = 0
		if not r.has("source_name"):
			r["source_name"] = ""


## Jeremy 2026-10-09 (hearsay flesh-out): border-wall Squabble lines.
## Raise = civic pride and uneasy jokes; skip = the taverns are split.
const WALL_RAISE_LINES: Array[String] = [
	"Walls going up around {r}. The crown is NOT messing about.",
	"They're raising walls around {r}. Stone by stone, the border closes.",
	"{r} gets a wall. Say what you like about the crown — they build.",
	"Saw the wall crews heading for {r}. That's a LOT of stone.",
	"Walls around {r}. Sleep a little easier tonight, friends.",
]
const WALL_SKIP_LINES: Array[String] = [
	"The crown offered {r} walls and they said NO. Bold. Or mad.",
	"No walls for {r}. The tavern is split — brave or foolish?",
	"{r} turned down the crown's wall. We'll see how that ages.",
	"They refused walls for {r}. Someone's feeling lucky.",
	"{r} said no to walls. Hope their gates are strong.",
]


## Jeremy 2026-10-09 (hearsay flesh-out): border-wall gossip. The
## crown's Raise/Skip verdict on a named region was the last deaf
## thread in the civic beat — the Gazette printed ROYAL WORKS and the
## mill heard nothing. Now both verdicts seed rich rumors:
##   - RAISED (heat 0.7): stone goes up, the realm notices.
##   - SKIPPED (heat 0.5): the refusal itself is the story.
## The raiser is always the player's faction (wall_answer is the
## crown's own verdict, via the NPC prompt or Ruler's Voice). Truth is
## TRUE — the crews are visible. Repeat verdicts refresh the rumor
## instead of doubling it; the ROYAL WORKS story folds in via _on_story
## (no thin twin). Heat stays below PRESS_HEAT — the Gazette's ROYAL
## WORKS already IS the press coverage.
func _on_wall_answer(region_name: String, raise: bool) -> void:
	var pf := String(_gs.player_faction)
	var region := region_name.strip_edges()
	if region == "":
		return
	var text: String
	var ev: String
	var heat: float
	if raise:
		ev = "raised"
		heat = 0.7
		text = "The crown is RAISING WALLS around %s — stone by stone, the border closes." % region
	else:
		ev = "skipped"
		heat = 0.5
		text = "The crown offered walls for %s and the answer was NO. Brave or foolish — the taverns are split." % region
	var r: Dictionary = seed_rumor(text, "wall", region, heat, -1, false,
		TRUTH_TRUE)
	if String(r.get("wall_event", "")) != ev:
		r["text"] = text
		r["text_orig"] = text
		r["wall_event"] = ev
		r["wall_region"] = region
		r["wall_faction"] = pf
	if raise:
		_event_post(WALL_RAISE_LINES, "wall", {"r": region})
	else:
		_event_post(WALL_SKIP_LINES, "wall", {"r": region})
	# The crown's own people hear it first, loud and in character.
	var first: Dictionary = _random_citizen(pf)
	var kid := int(first.get("id", -1))
	if kid > 0 and not (r["knowers"] as Array).has(kid):
		(r["knowers"] as Array).append(kid)
		var ku: Dictionary = _gs.get_unit(kid)
		if not ku.is_empty():
			_on_heard(ku, r, {})


## The border-wall reaction matrix. Nobody shrugs at the stones:
##   - RAISED: the crown's people swell with pride; war-rivals sneer
##     ("hiding behind stone"); everyone else reads the closing border
##     with awe and a little unease.
##   - SKIPPED: the crown's people split — the unhinged laugh at the
##     gamble, the rest feel uneasy; war-rivals cackle at the open
##     border; everyone else files it as tavern talk.
## Unhinged NPCs feel it 1.5x, matching the other matrices. Everything
## persists as memories so the talk surfaces in conversation later.
func _wall_reaction(u: Dictionary, r: Dictionary) -> void:
	if _mem == null:
		return
	var rid := int(r.get("id", 0))
	var ufaction := String(u.get("faction", ""))
	var crown := String(r.get("wall_faction", ""))
	var region := String(r.get("wall_region", "the border"))
	var raised := String(r.get("wall_event", "")) == "raised"
	var mult := 1.5 if SimUnhinged.is_unhinged(u) else 1.0
	if raised:
		if crown != "" and ufaction == crown:
			_mem.remember(u, "wall_raised_pride", rid, region, ufaction,
				0.8)
			_react_apply(u, 6.0 * mult, 0.0, "praised")
			return
		if crown != "" and _rival_of(ufaction, crown):
			_mem.remember(u, "wall_raised_sneer", rid, region, ufaction,
				0.6)
			_react_apply(u, 2.0 * mult, 0.0, "mocked")
			return
		_mem.remember(u, "wall_raised_news", rid, region, ufaction, 0.4)
		_react_apply(u, -2.0 * mult, 0.0, "disaster")
		return
	if crown != "" and ufaction == crown:
		if SimUnhinged.is_unhinged(u):
			_mem.remember(u, "wall_skipped_laugh", rid, region, ufaction,
				0.6)
			_react_apply(u, 3.0 * mult, 0.0, "mocked")
			return
		_mem.remember(u, "wall_skipped_unease", rid, region, ufaction,
			0.7)
		_react_apply(u, -3.0 * mult, 0.0, "disaster")
		return
	if crown != "" and _rival_of(ufaction, crown):
		_mem.remember(u, "wall_skipped_mock", rid, region, ufaction,
			0.6)
		_react_apply(u, 4.0 * mult, 0.0, "mocked")
		return
	_mem.remember(u, "wall_skipped_news", rid, region, ufaction, 0.4)
	_react_apply(u, 1.0 * mult, 0.0, "mocked")
