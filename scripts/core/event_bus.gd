class_name EventBus
extends Node
## Cursing Gnomes — decoupled signal bus (Milestone 1: sim core).
##
## Sim systems emit here; future UI / AI / audio subscribe here.
## Pure logic — no rendering, no input, no audio in this file.
## NOTE: GameState owns its own EventBus instance (GameState.bus) and all sim
## systems emit through it. This script is ALSO registered as an autoload
## (named "Events" to avoid shadowing the EventBus class) for future non-sim
## use; do not mix the two buses for sim events.


## Emitted when Spawner successfully creates a unit. Payload is the unit record.
signal unit_spawned(unit: Dictionary)
## Emitted when a unit dies. Carries the unit id and its faction.
signal unit_died(unit_id: int, faction: String)
## Emitted when a building record is added to the game state.
signal building_placed(building: Dictionary)
## Emitted whenever a faction's resource amount changes.
signal resource_changed(faction: String, resource: String, new_amount: float)
## Emitted when a town is founded.
signal town_founded(town: Dictionary)
## Emitted when the day/night cycle rolls over to a new day.
signal day_changed(day_number: int, is_night: bool)
## Emitted once per new game with the active faction id list.
signal game_started(factions: Array)
## --- Milestone 4: combat & disasters ---------------------------------------
## Emitted when SimCombat fires a projectile record (visual layer spawns a node).
signal projectile_fired(projectile: Dictionary)
## Emitted when a projectile record finishes (visual layer frees the node).
signal projectile_done(projectile: Dictionary)
## Emitted when a projectile lands. impact is the Vector2 hit point.
signal projectile_hit(projectile: Dictionary, impact: Vector2)
## Emitted when combat (not disaster/natural causes) kills a unit.
## source_faction is who dealt the killing blow ("fire" for wildfire).
signal unit_killed(unit_id: int, source_faction: String)
## Emitted when a corpse record is purged (or a monster leaves the map).
signal unit_purged(unit_id: int)
## Emitted when a building is destroyed in combat. Payload is the record.
signal building_destroyed(building: Dictionary)
## Emitted when a wildfire ignites. Payload is the fire record.
signal fire_started(fire: Dictionary)
## Emitted when a fire goes out. Carries the fire id.
signal fire_out(fire_id: int)
## Jeremy 2026-10-10 (hearsay flesh-out): the fire brigade rolling out of
## its station lot with crew aboard is a public spectacle — the grapevine
## hears the bells. Emitted once per dispatch per fire.
signal fire_brigade_rolled(station_id: int, fire_id: int, faction: String)
# Jeremy 2026-10-11 (hearsay flesh-out): a citizen bought a personal
# vehicle at a wagon dealership with their own coins — the grapevine's
# newest bragging rights.
signal vehicle_bought(buyer_id: int, vehicle_type: String, price: float)
## Emitted when a disaster spawns. kind: giant_ass | thicc_moose |
## bandit_raid | giant_lizard | rogue_wizard | cardboard_cat | nasty_priest |
## count_bastard | hoa_karen | jesus | seagull_swarm | taxman | booze_ooze |
## doom_prophet | gig_gnome | borg_crab_bill | twister_sister.
signal disaster_spawned(kind: String, position: Vector2)
## Emitted when a disaster's budget is spent and it starts leaving.
signal disaster_left(kind: String)
## Emitted when the thicc moose moons a town hall. Payload: hall record.
signal moose_mooned(hall: Dictionary)
## Jeremy 2026-10-04: THE NASTY MONASTERY — emitted each time Father
## Filthwick bursts out of the monastery screaming. Payload: priest unit id,
## burst position, and the outburst text.
signal priest_burst(priest_id: int, pos: Vector2, outburst: String)
## Jeremy 2026-10-04: emitted when the REAL n-word is used in diplomacy.
## The whole realm condemns racism — hearsay seeds anti-racist rumors and
## Squabble posts from every faction. Payload: insulter faction, target
## faction, the exact quote, and the offender's personal name ("" when the
## offender is a faction ruler rather than a named NPC).
## Jeremy 2026-10-04: NPC reporters must NEVER quote the slur — they
## euphemize ("THAT word", "won't repeat it") so they don't trigger the
## system on themselves. Hearsay deliberately ignores the quote.
signal slur_incident(insulter: String, target: String, text: String, offender_name: String)
## --- Milestone 5: minds ----------------------------------------------------
## Emitted when an NPC says a scripted dialogue line. Bubble visuals were
## removed 2026-10-05; text is 100% offline/scripted, never generated.
signal unit_said(unit_id: int, text: String)
## --- Milestone 6: interiors & phone -----------------------------------------
## Emitted when a unit enters / exits a building interior.
signal interior_entered(building_id: int, unit_id: int)
signal interior_exited(building_id: int, unit_id: int)
## Emitted when a Messenger message arrives (player-sent or NPC-sent).
## key is the thread contact key; text is the new message.
signal phone_message(key: String, text: String)
## Jeremy 2026-10-04: realistic texting — typing indicator state changed.
## key is the thread contact key; typing is whether "X is typing..." shows.
signal phone_typing(key: String, typing: bool)
## Jeremy 2026-10-04: player answered a wall-raise prompt via hearsay
## (replied yes/no to the advisor's message). The world commits or skips
## the walls for the region. One ask, one answer — no repeated prompts.
signal wall_answer(region_name: String, raise: bool)
## Jeremy 2026-10-04: realistic texting — a message's delivery status
## changed ("sending" -> "delivered" -> "seen"). index is the message
## index in the thread (-1 = refresh all); status is the new status.
signal phone_message_status(key: String, index: int, status: String)
## Emitted when the player adds a contact.
signal phone_contact_added(key: String)
## Emitted when a Squabble post is published. Payload is the post record.
signal squabble_post(post: Dictionary)
## Emitted when a courtier petitions the crown. Payload is the petition.
signal petition_opened(petition: Dictionary)
## Jeremy 2026-10-04: tool/shop petition chain — a faction adviser asks the
## PLAYER for permission to build a shop (AI factions auto-resolve through
## SimPetitions). phone_ui shows an Approve/Deny modal; the decision returns
## via SimPetitions.resolve_petition(). Emitted at most once per petition.
signal build_request(petition: Dictionary)
## Emitted when the player decides a petition. choice is the option text.
signal petition_decided(petition: Dictionary, choice: String)
## Jeremy 2026-10-08 (hearsay flesh-out): a crime was committed — the
## grapevine names names. kind: pickpocket|burglary|vandalism|mugging|
## tool_theft. crook_id 0 = the thief was NOT seen (the town knows a
## crime happened, not who did it). headline is the exact Gazette
## headline, so hearsay can dedup the party-less story seed against the
## rich rumor. Emitted BEFORE the Gazette story publishes.
signal crime_committed(kind: String, crook_id: int, victim_id: int,
	town_name: String, loot: int, headline: String)
## Jeremy 2026-10-04: strategic proposal protocol ("AI plays the game,
## player approves"). An adviser (or the AI director) asks for a MAJOR
## decision: declare_war | monastery_assault | expand_territory |
## major_buildup | sue_for_peace. Player faction -> phone_ui shows an
## Approve/Deny modal; the answer returns via SimProposals.resolve_proposal().
## AI factions auto-resolve through SimProposals._ai_evaluate.
signal strategic_proposal(proposal: Dictionary)
## Emitted when a strategic proposal is decided (approved, denied, expired).
## approved is true only when the decision-maker said yes.
signal strategic_proposal_decided(proposal: Dictionary, approved: bool)
## Emitted when the Gazette publishes. Payload is the story record.
signal gazette_story(story: Dictionary)
## Jeremy 2026-10-06: player-facing toast banner (HTML systemMsg parity).
## Sim systems emit here for transient announcements that deserve a banner
## but are not urgent Gazette headlines. The HUD's urgent toast renders it.
signal toast(text: String)
## Jeremy 2026-10-04: Seven Monasteries — a faction captured a monastery.
## god_id is the god's id, faction the new owner.
signal monastery_captured(god_id: String, faction: String)
## Jeremy 2026-10-04: Seven Dark Crystals — a faction captured a crystal.
## god_id is the rogue god's id, faction the new owner.
signal crystal_captured(god_id: String, faction: String)
## Jeremy 2026-10-04: Seven Dark Crystals — storm lightning struck a
## crystal. Payload: crystal id, world position.
signal crystal_struck(crystal_id: int, pos: Vector2)
## Jeremy 2026-10-06: Command Posts (Battlefront directive) — unified
## capture signal for ALL post types. kind is "town"|"monastery"|"crystal",
## post_id the post's id, old/new_holder factions ("" = unclaimed).
signal command_post_captured(kind: String, post_id: int,
	old_holder: String, new_holder: String, position: Vector2)
## --- Adventure mode --------------------------------------------------------
## Emitted for adventure log entries and player-facing toasts.
signal adventure_deed(text: String)
## Emitted when a quest is accepted / completed. Payload is the quest record.
signal adventure_quest_accepted(quest: Dictionary)
signal adventure_quest_completed(quest: Dictionary)
## Emitted when a quest fails (quest NPC died). Payload is the quest record.
signal adventure_quest_failed(quest: Dictionary)
## Emitted when the hero levels up.
signal adventure_level_up(level: int)
## Emitted when the campaign is won (Bandit King slain) or lost (5 falls).
signal adventure_won()
signal adventure_lost()
## --- Milestone 8: diplomacy --------------------------------------------------
## Emitted when a faction declares war on another.
signal war_declared(faction_a: String, faction_b: String)
## Emitted when two factions make peace.
signal peace_made(faction_a: String, faction_b: String)
## Emitted when two factions sign an alliance.
signal alliance_signed(faction_a: String, faction_b: String)
## Emitted when a faction breaks a treaty. breaker is the oathbreaker.
signal treaty_broken(breaker: String, other: String)
## Emitted when tribute changes hands. from_faction paid to_faction.
signal tribute_paid(from_faction: String, to_faction: String, resource: String, amount: float)
## Emitted when a tribute demand is refused.
signal tribute_refused(demander: String, target: String)
## Emitted when two factions sign a trade agreement.
signal trade_signed(faction_a: String, faction_b: String)
## Emitted when a pair's relationship state changes.
signal relation_changed(faction_a: String, faction_b: String, state: String)
## Emitted when a losing faction sues for peace (loser yields to winner).
signal surrender_offered(loser: String, winner: String)
## Emitted when a surrender is accepted — the white flag flies.
signal surrender_accepted(loser: String, winner: String)
## --- War-spare fate votes + peace treaties (Jeremy 2026-10-11) -----------------
## Emitted when a town hall falls to a war enemy and the land must vote.
signal spare_vote_started(vote: Dictionary)
## Emitted when the fate vote resolves (result in vote["result"]).
signal spare_vote_resolved(vote: Dictionary)
## Emitted when a spare-vote peace treaty is signed.
signal treaty_signed(treaty: Dictionary)
## --- Disaster-aid votes (Jeremy 2026-10-11) ------------------------------------
## Emitted when a hall falls to nature and the land votes on sending aid.
signal aid_vote_started(vote: Dictionary)
## Emitted when the aid vote resolves.
signal aid_vote_resolved(vote: Dictionary)
## Emitted when an aid mission dispatches helpers.
signal aid_mission_started(mission: Dictionary)
## Emitted when an aid mission's helpers head home.
signal aid_mission_done(mission: Dictionary)
## --- Zoning ----------------------------------------------------------------
## Emitted whenever zones are painted, merged, or dezoned.
signal zone_changed
## --- Spatial SFX -----------------------------------------------------------
## Emitted when a positional sound should play (HTML playSpatial parity).
## velocity drives the Doppler pitch (e.g. projectile velocity).
signal sfx_spatial(sfx_name: String, world_pos: Vector2, velocity: Vector2)
## --- UI tap feedback ---------------------------------------------------------
## Emitted whenever any UI button is pressed (global tap capture in
## scripts/audio/ui_tap_sfx.gd: menu, phone, HUD, dialogs, keyboard keys).
## AudioManager answers with the synthesized "click" (2026-10-09: UI taps
## were completely silent).
signal ui_click
## --- Combat FX -------------------------------------------------------------
## Emitted when a combat visual should play at a position (muzzle flashes,
## spell effects, siege impacts). world.gd connects this to CombatFX.
signal combat_fx(kind: String, world_pos: Vector2)
## Jeremy 2026-10-08 (rapid-iteration): floating damage numbers. Emitted by
## SimCombat.damage_unit with the FINAL mitigated amount so battles read —
## white for light hits, gold for heavy, red-orange for massive. world.gd
## routes this to the DamageNumbers layer (plain text only, no bubble
## visuals per the 2026-10-05 bubble ban). kind is the damage kind
## ("", "cannonball", spell ids...) for future tinting.
signal unit_damaged(unit_id: int, amount: float, world_pos: Vector2, kind: String)
## --- Seasons / farming / industry ------------------------------------------
## All emissions are has_signal-guarded by senders; safe to add anytime.
signal weather_changed(kind: String)
signal season_changed(season: String)
signal disaster_forecast_posted(entries: Dictionary)
signal disaster_forecast_fired(label: String)
signal farm_plot_created(plot: Dictionary)
signal farm_harvested(plot_id: int, food: float, seeds: float)
signal seeds_bought(faction: String, amount: int)
signal trader_arrived(name: String, position: Vector2)
signal trader_left(name: String)
signal trade_done(faction: String, give: String, take: String, give_amt: float, take_amt: float)
## Jeremy 2026-10-08 (hearsay flesh-out): a festival was held, cancelled,
## or wound down — the grapevine names the town and the joy. event:
## held|cancelled|wound_down. faction: the host faction. joy: happiness
## granted (0 for cancelled/wound_down). Emitted BEFORE the Gazette
## story publishes, so hearsay seeds the rich rumor first and dedups
## the party-less story seed.
signal festival_event(event: String, town: String, faction: String, joy: int)
## A kingdom's founding — the opening coronation beat. town: the crown's
## first town. faction: the founding faction key. ruler: the ruler's name,
## verbatim (naming law). Emitted BEFORE the Gazette "A KINGDOM RISES"
## story publishes, so hearsay seeds the rich named rumor first and the
## thin party-less story seed dedups against it.
signal kingdom_founded(town: String, faction: String, ruler: String)
signal gather_ordered(faction: String, site_id: int, worker_count: int)
## --- Farm animals ------------------------------------------------------------
## All emissions are has_signal-guarded by senders; safe to add anytime.
signal animals_stocked(plot_id: int, kind: String, types: Array)
signal animal_yield(plot_id: int, faction: String, food: float)
signal animal_died(plot_id: int, animal_id: int, cause: String, animal_type: String)
