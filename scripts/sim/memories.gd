class_name SimMemories
extends RefCounted
## Cursing Gnomes — NPC memory system (Milestone 5: minds).
##
## NPCs remember what happened to them: who hurt them, who helped them,
## whose death they witnessed. Memories have a strength that decays over
## game time (old memories fade unless reinforced) and feed the
## relationship score the dialogue and behavior systems read.
##
## Memories live on the unit record ("memories" array of dicts):
##   {type, subject_id, subject_name, faction, strength, game_time}
## Pure logic — no rendering, no input, no audio.


## Memory types. Signed for relationship scoring.
const TYPES: Array[String] = ["hurt_by", "helped_by", "saved_by",
	"insulted_by", "praised_by", "friend_died", "worked_with", "mocked_by",
	# Jeremy 2026-10-04: likes/dislikes engine — the ruler said something
	# about a topic the NPC loved or hated.
	"loved_topic", "hated_topic",
	# Jeremy 2026-10-04: THE NASTY MONASTERY — NPCs remember Father Filthwick.
	"harassed_by",
	# Jeremy 2026-10-06: hearsay overhaul — NPCs remember rumors they
	# heard through the grapevine (and ones they doubted), so the
	# conversation engine can reference them. Never invented — always
	# grounded in a real rumor that reached them.
	"heard_rumor", "doubted_rumor",
	# Jeremy 2026-10-06 (hearsay flesh-out): first-hand witnesses remember
	# what they SAW, not just what they heard — their testimony weighs on
	# belief (see SimHearsay._belief).
	"witnessed_rumor",
	# Jeremy 2026-10-07 (hearsay flesh-out): proud skeptics remember
	# scoffing at a rumor publicly, not just doubting it quietly —
	# doubt is contagious, and their scoffs count (see _on_doubted).
	"scoffed_at_rumor",
	# Jeremy 2026-10-06: player smear pipeline — NPCs remember what the
	# player said about third parties and how they felt about it, so
	# grudges (and amused alliances) persist across conversations.
	"player_smeared_me", "player_smeared_friend", "player_roasted_enemy",
	# Jeremy 2026-10-07 (hearsay flesh-out): war-news reaction matrix —
	# NPCs remember war declarations and surrenders in character, so
	# war-fear, rallying, and humiliation persist across conversations.
	"war_on_us", "war_declared_by_us",
	"we_surrendered", "surrender_offered",
	"enemy_surrendered", "surrender_offered_us",
	# Jeremy 2026-10-08 (hearsay flesh-out): war-PLOT reaction matrix —
	# NPCs remember war-plotting in character: the target fears the
	# looming drums, the plotters grimly anticipate, and a denied plot
	# leaves relief, embarrassment, and tavern comedy.
	"war_plotted_on_us", "war_plotting",
	"war_plot_dead", "war_plot_chickened", "heard_war_plot",
	# Jeremy 2026-10-07 (hearsay flesh-out): conquest/betrayal matrix —
	# captures, treaty breaks, tribute refusals, and fallen buildings
	# are remembered by side, so shame, pride, outrage, and defiance
	# persist (and feed grudges) across conversations.
	"lost_post", "took_post",
	"betrayed_by", "broke_treaty",
	"refused_tribute", "tribute_refused_us",
	"building_lost",
	# Jeremy 2026-10-07 (hearsay flesh-out): diplomacy-news matrix —
	# peace, alliances, trade, tribute paid, hostile turns, and town
	# foundings are remembered by side, so relief, pride, suspicion,
	# and grudges persist across conversations.
	"heard_peace", "heard_alliance", "enemy_alliance",
	"heard_trade", "rival_trade",
	"paid_tribute", "tribute_won",
	"heard_hostile", "town_founded_us",
	# Jeremy 2026-10-07 (hearsay flesh-out): disaster reaction matrix —
	# disasters record the stricken town, so victims remember the panic,
	# rivals remember laughing at the misery, and allies remember the
	# grief, across conversations.
	# Jeremy 2026-10-09 (hearsay flesh-out): the sun-bomb matrices — the
	# stricken remember the sky catching fire, the launcher's people
	# remember their spear flying, war-rivals remember the dread (not
	# the laughter), and the whole realm remembers the inbound spear
	# and watching the second sun die, across conversations.
	"disaster_hit_us", "rival_disaster", "ally_disaster",
	"nuke_hit_us", "nuke_our_spear", "nuke_dread", "saw_sun_die",
	"nuke_spear_inbound",
	# Jeremy 2026-10-07 (hearsay flesh-out): death-of-a-notable reaction
	# matrix — deaths record the dead's faction, so the dead's own faction
	# remembers the mourning, war-rivals remember cackling at the loss,
	# and everyone else remembers paying respects, across conversations.
	"mourned_our_dead", "rival_dead", "heard_dead_other",
	# Jeremy 2026-10-08 (hearsay flesh-out): the false-smear loop —
	# targets remember who invented the lie about them (grudge fuel),
	# believers remember swallowing a debunked lie (sheepish), and
	# believers remember calling a verified rumor right (vindicated).
	"npc_smeared_me", "believed_a_lie", "called_it_right",
	# Jeremy 2026-10-08 (hearsay flesh-out): the gossip reaction matrix —
	# tavern talk names a citizen, so the victim remembers the
	# mortification, laughers remember cackling at them, and defenders
	# remember standing up for them (HTML p13CitizenMemoryLine parity).
	"gossiped_about_me", "mocked_gossip_victim", "defended_gossip_victim",
	# Jeremy 2026-10-08 (hearsay flesh-out): court-ruling rumors — the
	# petitioner remembers the verdict, laughers remember cackling at a
	# denial, defenders remember raging at it (HTML court-gossip parity).
	"petition_granted", "petition_denied", "heard_petition_granted",
	"heard_petition_denied", "celebrated_petition_grant",
	"grumbled_petition_grant", "mocked_petition_denial",
	"defended_petition_victim",
	# Jeremy 2026-10-09 (hearsay flesh-out): court-FILING matrix —
	# the ask gossips before the ruling. Petitioners remember filing,
	# friends remember backing, rivals remember mocking, and a
	# war-plea filed at your people is remembered with dread.
	"filed_petition", "heard_petition_filed", "backed_petition_filing",
	"mocked_petition_filing", "dreaded_petition_filing",
	# Jeremy 2026-10-08 (hearsay flesh-out): the crime reaction matrix —
	# the victim remembers who robbed them (grudge fuel aimed at the
	# crook), the named thief remembers being caught out (unhinged ones
	# remember bragging), and the town remembers who mocked or excused
	# the thief.
	"crime_victim", "crime_caught_out", "crime_bragged",
	"mocked_thief", "crook_friend_shame", "heard_crime",
	# Jeremy 2026-10-08 (hearsay flesh-out): the who-killed-whom matrix —
	# the victim's kin remember WHICH faction's blades did it (grudge
	# fuel), the killer's kin remember the slaying, and third parties
	# remember a peacetime assassination as the scandal it is.
	"kin_slain_by", "our_blades_slew", "heard_assassination",
	# Jeremy 2026-10-08 (hearsay flesh-out): the caravan gossip matrix —
	# market days are remembered warmly, good deals remembered fondly,
	# missed caravans remembered with regret, and the proud remember
	# sniffing at the whole affair.
	"trader_visited", "trader_deal", "missed_caravan", "trader_sniffed",
	# Jeremy 2026-10-08 (hearsay flesh-out): adventure quest gossip —
	# a completed quest is remembered warmly, a failed one with grief
	# (or glee — rivals remember mocking it), and a legend / a fallen
	# hero is remembered by the whole realm.
	"heard_quest_done", "heard_quest_failed", "heard_legend",
	"heard_hero_fell", "mocked_quest_fail",
	# Jeremy 2026-10-09 (hearsay flesh-out): quest acceptances — the
	# tavern buzzes when a hero takes up a quest (hope at home, mockery
	# from war-rivals), remembered when the outcome lands.
	"heard_quest_taken", "mocked_quest_take",
	# Jeremy 2026-10-08 (hearsay flesh-out): festival gossip — the host
	# town remembers celebrating, cancelled festivals are remembered as
	# broken promises, wind-downs as warm afterglow; rivals remember
	# sneering or mocking, and happy news is remembered fondly.
	"celebrated_festival", "festival_cancelled", "festival_memory",
	"sneered_at_festival", "mocked_festival", "heard_festival",
	# Jeremy 2026-10-09 (hearsay flesh-out): founding gossip — the home
	# faction remembers the coronation, rivals remember mocking the new
	# crown, allies remember congratulating, everyone else remembers
	# hearing the news.
	"crowned_ruler", "heard_founding", "mocked_founding",
	"congratulated_founding",
	# Jeremy 2026-10-09 (hearsay flesh-out): famine gossip — the starving
	# remember hunger (critical = starving, shortage = hungry), rivals
	# remember mocking it, everyone else remembers hearing about it,
	# and the recovered remember the relief.
	"starving_famine", "hungry_famine", "mocked_famine",
	"heard_famine", "famine_relieved",
	# Jeremy 2026-10-09 (hearsay flesh-out): denied peace-feeler gossip —
	# a beaten faction's council debated begging for peace and said no.
	# The proud remember the shame, hawks the defiance, doves the
	# despair; the would-be recipients remember gloating, rivals
	# remember mocking, and everyone else remembers hearing about it.
	"peace_feeler_shame", "peace_feeler_defiant", "peace_feeler_despair",
	"peace_feeler_gloated", "peace_feeler_mocked", "heard_peace_feeler",
	# Jeremy 2026-10-09 (hearsay flesh-out): seasonal gossip — the realm
	# remembers how each turning year felt: winter's dread (deepest when
	# the pots were already empty), spring's hope, summer's ease (or a
	# soldier's restlessness), autumn's harvest hope.
	"dreaded_winter", "starving_winter", "welcomed_spring",
	"summer_ease", "summer_restless", "harvest_hope",
	# Jeremy 2026-10-09 (hearsay flesh-out): border-wall gossip — the
	# crown's people remember pride in the raising (or the split over
	# a refusal); rivals remember sneering and cackling; everyone else
	# remembers the news.
	"wall_raised_pride", "wall_raised_sneer", "wall_raised_news",
	"wall_skipped_laugh", "wall_skipped_unease", "wall_skipped_mock",
	"wall_skipped_news",
	# Jeremy 2026-10-09 (hearsay flesh-out): storm-omen memories — the
	# holder's people remember dread, rivals remember gloating, the
	# wild-crystal awe and plain news are remembered too.
	"crystal_struck_omen", "crystal_struck_glee", "crystal_struck_wonder",
	"crystal_struck_news",
	# Jeremy 2026-10-10 (hearsay flesh-out): trespass memories — the
	# owner's fury, the household's unease, the tavern's glee at the
	# caught snoop, the snoop's shame, and the plain news.
	"trespass_anger", "trespass_wary", "trespass_glee",
	"trespass_shame", "trespass_news",
	# Jeremy 2026-10-10 (hearsay flesh-out): beastloss memories — the
	# herd's faction remembers shame, rivals remember gloating, wolf
	# kills leave wariness, and the plain news is remembered too.
	"beastloss_shame", "beastloss_glee", "beastloss_wary",
	"beastloss_news",
	# Jeremy 2026-10-10 (hearsay flesh-out): weather memories — storm
	# dread, the farmer's crop fear, the unhinged thrill, rain's
	# blessing (and plain news), snow dread and the farmer's stores.
	"storm_dread", "storm_crops", "storm_thrill", "rain_blessing",
	"rain_news", "snow_dread", "snow_stores",
	# Jeremy 2026-10-10 (hearsay flesh-out): harvest memories — bumper
	# pride for the fed faction, envy from rivals, mockery (and quiet
	# self-embarrassment) over a lean haul, and the plain news.
	"harvest_pride", "harvest_envy", "harvest_mock", "harvest_news",
	# Jeremy 2026-10-10 (hearsay flesh-out): brigade memories — pride in
	# the home crew, hope in the burning town, the unhinged thrill,
	# rival mockery of the bells, and the plain news.
	"brigade_pride", "brigade_hope", "brigade_thrill", "brigade_mock",
	"brigade_news",
	# Jeremy 2026-10-11 (hearsay flesh-out): vehicle memories — the
	# buyer's pride, a neighbor's envy, rival mockery of the show-off,
	# the unhinged coveting the wheels, plain news, and the dealership
	# opening itself.
	"vehicle_proud", "vehicle_envy", "vehicle_mock", "vehicle_news",
	"vehicle_thrill", "vehicle_dealer_news"]

## Relationship weight per memory type (positive = likes them).
const REL_WEIGHT := {
	"hurt_by": -1.0,
	"helped_by": 1.0,
	"saved_by": 1.5,
	"insulted_by": -0.8,
	"praised_by": 0.8,
	"friend_died": -0.5,
	"worked_with": 0.2,
	"mocked_by": -0.6,
	# Jeremy 2026-10-04: likes/dislikes engine.
	"loved_topic": 0.7,
	"hated_topic": -0.7,
	# Jeremy 2026-10-04: THE NASTY MONASTERY.
	"harassed_by": -0.5,
	# Jeremy 2026-10-06: hearsay — hearing gossip is mildly engaging,
	# doubting it is neutral.
	"heard_rumor": 0.1,
	"doubted_rumor": 0.0,
	# Jeremy 2026-10-06 (hearsay flesh-out): being there firsthand is
	# mildly engaging, like hearing the gossip.
	"witnessed_rumor": 0.1,
	# Jeremy 2026-10-07 (hearsay flesh-out): scoffing publicly at a rumor
	# is mildly engaging — the skeptic enjoyed the performance.
	"scoffed_at_rumor": 0.1,
	# Jeremy 2026-10-06: player smear pipeline — being smeared (or hearing
	# a friend smeared) damages the relationship; laughing along with the
	# player about a mutual enemy builds it.
	"player_smeared_me": -1.0,
	"player_smeared_friend": -0.7,
	"player_roasted_enemy": 0.6,
	# Jeremy 2026-10-08 (hearsay flesh-out): the false-smear loop — being
	# smeared by a fellow citizen stings like a player smear (grudge
	# fuel); swallowing a debunked lie is neutral sheepishness; calling
	# a verified rumor right is mildly satisfying.
	"npc_smeared_me": -1.0,
	"believed_a_lie": 0.0,
	"called_it_right": 0.1,
	# Jeremy 2026-10-07 (hearsay flesh-out): war news colors how an NPC
	# feels about the remembered event — fear and humiliation weigh
	# negative, rallying and triumph weigh positive.
	"war_on_us": -0.8,
	"war_declared_by_us": 0.3,
	"we_surrendered": -0.6,
	"surrender_offered": -0.3,
	"enemy_surrendered": 0.6,
	"surrender_offered_us": 0.3,
	# Jeremy 2026-10-08 (hearsay flesh-out): war plots color how an NPC
	# feels — a plot against your faction weighs like a war threat;
	# plotting weighs like a boast; a dead plot is relief or comedy.
	"war_plotted_on_us": -0.7,
	"war_plotting": 0.2,
	"war_plot_dead": 0.3,
	"war_plot_chickened": -0.3,
	"heard_war_plot": 0.1,
	# Jeremy 2026-10-07 (hearsay flesh-out): conquest/betrayal — losing
	# ground, being betrayed, or being refused tribute stings; taking
	# ground, breaking a treaty from strength, or refusing tribute feels
	# like power. Fallen buildings are mourned.
	"lost_post": -0.8,
	"took_post": 0.5,
	"betrayed_by": -0.9,
	"broke_treaty": 0.3,
	"refused_tribute": 0.4,
	"tribute_refused_us": -0.7,
	"building_lost": -0.5,
	# Jeremy 2026-10-07 (hearsay flesh-out): disaster news colors how an
	# NPC feels about the remembered event — the devastation of your own
	# town weighs negative; laughing at (or grieving) someone else's does
	# not change how you feel about them.
	"disaster_hit_us": -0.7,
	"rival_disaster": 0.0,
	"ally_disaster": 0.0,
	# Jeremy 2026-10-09 (hearsay flesh-out): sun-bomb memories color how
	# an NPC feels about the remembered event — the devastation of your
	# own town weighs heaviest; the launcher's pride warms them toward
	# their own; dread and awe weigh negative on everyone else.
	"nuke_hit_us": -0.9,
	"nuke_our_spear": 0.4,
	"nuke_dread": -0.3,
	"saw_sun_die": -0.2,
	"nuke_spear_inbound": -0.5,
	# Jeremy 2026-10-07 (hearsay flesh-out): death-of-a-notable reaction
	# matrix — mourning your own dead weighs negative; cackling at a
	# rival's loss feels positive; paying respects barely registers.
	"mourned_our_dead": -0.6,
	"rival_dead": 0.3,
	"heard_dead_other": -0.1,
	# Jeremy 2026-10-08 (hearsay flesh-out): gossip reaction matrix —
	# being the town's laughingstock stings (self-directed, neutral for
	# relationship math), laughing at the victim cools the town toward
	# them a little, defending them warms it.
	"gossiped_about_me": 0.0,
	"mocked_gossip_victim": -0.4,
	"defended_gossip_victim": 0.5,
	# Jeremy 2026-10-08 (hearsay flesh-out): court-ruling memories — the
	# verdict itself is self/faction-directed (neutral for relationship
	# math); laughing at someone's denied plea cools the town toward the
	# laugher, raging at it warms them.
	"petition_granted": 0.0,
	"petition_denied": 0.0,
	"heard_petition_granted": 0.0,
	"heard_petition_denied": 0.0,
	"celebrated_petition_grant": 0.2,
	"grumbled_petition_grant": -0.2,
	"mocked_petition_denial": -0.4,
	"defended_petition_victim": 0.5,
	# Jeremy 2026-10-09 (hearsay flesh-out): court-FILING weights —
	# mockery of the ask cools relations, backing warms them; dread of
	# a war-plea cools a little (it's the plea you fear, not the asker).
	"filed_petition": 0.0,
	"heard_petition_filed": 0.0,
	"backed_petition_filing": 0.4,
	"mocked_petition_filing": -0.3,
	"dreaded_petition_filing": -0.2,
	# Jeremy 2026-10-08 (hearsay flesh-out): crime memories — being
	# robbed is a real grudge against the crook; being caught out or
	# bragging is self-directed; mocking the thief cools the town toward
	# them a little, excusing them cools it more; hearing about a thief
	# in town makes everyone warier of them.
	"crime_victim": -1.0,
	"crime_caught_out": 0.0,
	"crime_bragged": 0.0,
	"mocked_thief": -0.4,
	"crook_friend_shame": -0.5,
	"heard_crime": -0.2,
	# Jeremy 2026-10-08 (hearsay flesh-out): caravan memories — market
	# days and good deals are remembered fondly, a missed caravan with
	# mild regret, and the proud's sniffing is self-directed.
	"trader_visited": 0.3,
	"trader_deal": 0.5,
	"missed_caravan": -0.2,
	"trader_sniffed": 0.0,
	# Jeremy 2026-10-08 (hearsay flesh-out): adventure quest memories —
	# legends are admired, a fallen hero is mourned, a failed quest is
	# grieved at home and gleefully mocked by rivals.
	"heard_legend": 0.3,
	"heard_quest_done": 0.2,
	"heard_hero_fell": -0.3,
	"heard_quest_failed": -0.1,
	"mocked_quest_fail": -0.3,
	# Jeremy 2026-10-09 (hearsay flesh-out): taking up a quest is
	# remembered with hope; rivals remember mocking the attempt.
	"heard_quest_taken": 0.1,
	"mocked_quest_take": -0.2,
	# Jeremy 2026-10-08 (hearsay flesh-out): festival memories — a great
	# party is remembered warmly, a cancelled one as a broken promise,
	# and the wind-down afterglow fondly; rivals sneering or mocking
	# cools the memory a little.
	"celebrated_festival": 0.4,
	"festival_memory": 0.2,
	"heard_festival": 0.2,
	"festival_cancelled": -0.3,
	"sneered_at_festival": -0.2,
	"mocked_festival": -0.2,
	# Jeremy 2026-10-09 (hearsay flesh-out): founding memories — a
	# coronation is remembered warmly at home, mocked by rivals, and
	# kindly by allies.
	"crowned_ruler": 0.8,
	"heard_founding": 0.2,
	"mocked_founding": -0.3,
	"congratulated_founding": 0.4,
	# Jeremy 2026-10-09 (hearsay flesh-out): famine memories — hunger is
	# remembered coldly, mocking someone's famine cools the memory of
	# them, and the relief of eating again is remembered warmly.
	"starving_famine": -0.4,
	"hungry_famine": -0.2,
	"heard_famine": -0.1,
	"mocked_famine": -0.3,
	"famine_relieved": 0.4,
	# Jeremy 2026-10-09 (hearsay flesh-out): peace feelers — shame and
	# despair weigh cold, defiance and gloating weigh warm, mocking a
	# balked beggar cools the memory of them slightly.
	"peace_feeler_shame": -0.3,
	"peace_feeler_defiant": 0.2,
	"peace_feeler_despair": -0.2,
	"peace_feeler_gloated": 0.3,
	"peace_feeler_mocked": 0.1,
	"heard_peace_feeler": 0.0,
	# Jeremy 2026-10-09 (hearsay flesh-out): seasonal gossip — dread and
	# hungry winters weigh cold, hopeful springs and harvests weigh warm,
	# a soldier's summer restlessness barely registers.
	"dreaded_winter": -0.3,
	"starving_winter": -0.5,
	"welcomed_spring": 0.3,
	"summer_ease": 0.2,
	"summer_restless": -0.1,
	"harvest_hope": 0.3,
	# Jeremy 2026-10-09 (hearsay flesh-out): border-wall gossip — pride
	# in the raising warms, sneering at a rival's wall is faintly warm
	# (schadenfreude), unease over a refusal weighs cold, mocking a
	# refusal cools relations a little.
	"wall_raised_pride": 0.3,
	# Jeremy 2026-10-09 (hearsay flesh-out): storm-omen weights — dread
	# and plain news are self-directed (0.0), gloating at a rival's omen
	# cools like the other mocks (-0.2), wild-crystal awe is fond (0.1).
	"crystal_struck_omen": 0.0,
	"crystal_struck_glee": -0.2,
	"crystal_struck_wonder": 0.1,
	"crystal_struck_news": 0.0,
	# Jeremy 2026-10-10 (hearsay flesh-out): trespass weights — the
	# owner's fury cools hard toward the snoop, the household's unease
	# cools a little, tavern glee cools like the other mocks, shame
	# and plain news are self-directed.
	"trespass_anger": -0.3,
	"trespass_wary": -0.1,
	"trespass_glee": -0.2,
	"trespass_shame": 0.0,
	"trespass_news": 0.0,
	# Jeremy 2026-10-10 (hearsay flesh-out): beastloss weights — herd
	# shame is self-directed, gloating at a rival's hungry herd cools
	# like the other mocks, wolf-wariness and plain news are neutral.
	"beastloss_shame": 0.0,
	"beastloss_glee": -0.2,
	"beastloss_wary": 0.0,
	"beastloss_news": 0.0,
	# Jeremy 2026-10-10 (hearsay flesh-out): weather weights — storm
	# dread, crop fear, and snow/store dread are self-directed; the
	# unhinged delighting in a storm cools like the other mocks; rain
	# news is neutral.
	"storm_dread": 0.0,
	"storm_crops": 0.0,
	"storm_thrill": -0.2,
	"rain_blessing": 0.0,
	"rain_news": 0.0,
	"snow_dread": 0.0,
	"snow_stores": 0.0,
	# Jeremy 2026-10-10 (hearsay flesh-out): harvest weights — bumper
	# pride and plain news are self-directed, envy at a rival's bumper
	# crop cools like the other mocks, and lean-harvest mockery cools
	# like tavern laughter at someone's expense.
	"harvest_pride": 0.0,
	"harvest_envy": -0.2,
	"harvest_mock": -0.2,
	"harvest_news": 0.0,
	# Jeremy 2026-10-10 (hearsay flesh-out): brigade weights — pride and
	# hope are self-directed, the unhinged thrill and rival mockery cool
	# like tavern laughter at someone's expense, plain news is neutral.
	"brigade_pride": 0.0,
	"brigade_hope": 0.0,
	"brigade_thrill": -0.2,
	"brigade_mock": -0.2,
	"brigade_news": 0.0,
	# Jeremy 2026-10-11 (hearsay flesh-out): vehicle weights — pride
	# and news are self-directed, envy and mockery cool like tavern
	# laughter at someone's expense, the unhinged thrill cools the same,
	# the opening is neutral commerce news.
	"vehicle_proud": 0.0,
	"vehicle_envy": -0.2,
	"vehicle_mock": -0.2,
	"vehicle_news": 0.0,
	"vehicle_thrill": -0.2,
	"vehicle_dealer_news": 0.0,
	"wall_raised_sneer": 0.1,
	"wall_raised_news": 0.0,
	"wall_skipped_laugh": 0.1,
	"wall_skipped_unease": -0.2,
	"wall_skipped_mock": -0.3,
	"wall_skipped_news": 0.0,
}

const HALFLIFE := 240.0   # seconds of game time for a memory to halve
const FORGET_BELOW := 0.05


var _gs: GameState


func _init(game_state: GameState) -> void:
	_gs = game_state


func ensure(unit: Dictionary) -> Array:
	if not unit.has("memories"):
		unit["memories"] = []
	return unit["memories"]


## Record a memory. Reinforces an existing memory of the same type+subject
## instead of duplicating it. Caps at Config.MIND_MEMORY_CAP (drops weakest).
func remember(unit: Dictionary, mtype: String, subject_id: int,
		subject_name: String, faction: String, strength: float = 1.0) -> void:
	if not mtype in TYPES:
		return
	var mems: Array = ensure(unit)
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype and int(m.get("subject_id", 0)) == subject_id:
			m["strength"] = clampf(float(m.get("strength", 0.0)) + strength, 0.0, 2.0)
			m["game_time"] = _gs.game_time
			return
	mems.append({
		"type": mtype,
		"subject_id": subject_id,
		"subject_name": subject_name,
		"faction": faction,
		"strength": clampf(strength, 0.0, 2.0),
		"game_time": _gs.game_time,
	})
	_prune_to_cap(mems)


## Decayed strength of the memory of a type+subject, 0.0 if forgotten.
## Prunes fully-forgotten memories as a side effect.
func recall(unit: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = ensure(unit)
	for i: int in range(mems.size() - 1, -1, -1):
		var m: Dictionary = mems[i]
		if String(m.get("type", "")) == mtype and int(m.get("subject_id", 0)) == subject_id:
			var s: float = _decayed(m)
			if s < FORGET_BELOW:
				mems.remove_at(i)
				return 0.0
			return s
	return 0.0


## Relationship score toward a subject: sum of decayed signed memories.
## Negative = grudge, positive = fondness.
func relationship(unit: Dictionary, subject_id: int) -> float:
	var total := 0.0
	for m: Dictionary in ensure(unit):
		if int(m.get("subject_id", 0)) == subject_id:
			total += float(REL_WEIGHT.get(String(m.get("type", "")), 0.0)) * _decayed(m)
	return total


## Tick: drop forgotten memories. Cheap — memories are few.
func tick(unit: Dictionary) -> void:
	var mems: Array = ensure(unit)
	for i: int in range(mems.size() - 1, -1, -1):
		if _decayed(mems[i]) < FORGET_BELOW:
			mems.remove_at(i)


## Does this NPC hold a grudge against the subject?
func holds_grudge(unit: Dictionary, subject_id: int) -> bool:
	return relationship(unit, subject_id) <= -0.8


func _decayed(m: Dictionary) -> float:
	var age: float = maxf(0.0, _gs.game_time - float(m.get("game_time", 0.0)))
	return float(m.get("strength", 0.0)) * pow(0.5, age / HALFLIFE)


func _prune_to_cap(mems: Array) -> void:
	while mems.size() > Config.MIND_MEMORY_CAP:
		var weakest := 0
		for i: int in range(1, mems.size()):
			if _decayed(mems[i]) < _decayed(mems[weakest]):
				weakest = i
		mems.remove_at(weakest)
