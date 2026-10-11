class_name GuildHiring
extends RefCounted
## Cursing Gnomes — worker economy: hiring, officer appointments, training
## queues, barracks beds (Milestone 3: workers / hiring / housing).
##
## Ports the HTML build's MISS 13/14/15/16 workforce block (guildTick57,
## rosterScan57, rosterHireTick57, ensureGuildMaster57, ensureAdviser57,
## ensureWatchCaptain57, computeQuotas57, assignBarracksBed57) and its
## Building.startTrain/trainQueue training loop (not its code):
##
##   - Officer appointments: each completed government hall gets 1 adviser
##     and 1 watch captain; the guild master lives and works in the guild
##     hall (job "guild_master", auto-staffed by SimBuildings.tick_service;
##     here they are appointed an office + home). Appointments are recorded
##     as unit["mind"]["gov_role"] ("adviser" | "guild_master" |
##     "watch_captain") so SimPhone.government_contacts() picks them up.
##   - Labor roster: every completed workplace building generates open
##     positions from JobDefs.WORKPLACES; open slots = ceil(openHours / 8h
##     workday) * base slots (MISS 15). Officers hire unemployed laborers
##     (job == "worker") into open posts until every post is covered or no
##     seekers remain. Ticks-service jobs (doctor/firefighter/guard/
##     guild_master) are auto-staffed by SimBuildings and respected, not
##     re-hired; soldiers come from training queues, not repurposing.
##   - Training queues: trainer buildings (barracks/town hall/clinic/
##     fire station/fishing dock/faction uniques) queue unit types with a
##     cost and training time; graduates spawn via Spawner (caps re-checked
##     at spawn; a clogged queue retries, then refunds and drops — HTML
##     parity). The guild master keeps barracks training military to quota.
##   - Barracks: 25 beds each (Jeremy's law). Military units are assigned a
##     bunk in the least-full barracks of their faction; demand shortfalls
##     surface as staffing demand.
##
## Deterministic: no randomness in any hiring decision — candidates are
## ordered by unit id (HTML's "no Math.random() in hiring" rule).
## Caps are NEVER exceeded here: hiring repurposes existing units, and all
## spawns go through Spawner.spawn_unit().
##
## Pure logic — no rendering, no input, no audio.


## Seconds between hiring sweeps (the HTML guildTick57 ran every frame;
## a 4 s sweep is plenty for appointments + recruiting).
const HIRE_INTERVAL := 4.0

## Max entries per building training queue (HTML: reject at 5).
const TRAIN_QUEUE_MAX := 5

## Max units of one trained type per faction (HTML canTrainMore /
## UNIT_TYPE_CAP).
const UNIT_TYPE_CAP := 10

## Stall retries before a blocked training job is dropped with a refund
## (HTML: "a clogged queue must never spin forever").
const STALL_RETRIES := 5

## Building type -> trainable unit types (HTML canTrain roster).
const TRAINER_TYPES := {
	"barracks": ["soldier", "archer", "ranger", "mage", "cannoneer", "guard"],
	"knights_castle": ["soldier", "archer"],
	"war_hut": ["soldier", "ranger"],
	"mage_spire": ["mage"],
	"town_hall": ["worker", "roadbuilder"],
	"hall": ["worker", "roadbuilder"],
	"clinic": ["doctor"],
	"fire_station": ["firefighter"],
	"fishing_dock": ["fisher"],
}

## Training time in seconds (HTML TRAIN_TIME; fisher/firefighter/guards use
## the HTML's generic fallbacks).
const TRAIN_TIME := {
	"worker": 2.4, "roadbuilder": 3.2, "soldier": 3.8, "archer": 3.8, "ranger": 4.0,
	"mage": 5.2, "cannoneer": 6.2, "guard": 3.8, "doctor": 3.5,
	"firefighter": 4.0, "fisher": 3.0,
}

## Training cost {gold, wood} (HTML COSTS; fisher invented to match
## worker-scale costs).
const TRAIN_COST := {
	"worker": {"gold": 30, "wood": 12},
	"roadbuilder": {"gold": 35, "wood": 35},
	"soldier": {"gold": 45, "wood": 25},
	"archer": {"gold": 40, "wood": 35},
	"ranger": {"gold": 42, "wood": 38},
	"mage": {"gold": 55, "wood": 45},
	"cannoneer": {"gold": 95, "wood": 50},
	"guard": {"gold": 45, "wood": 25},
	"doctor": {"gold": 50, "wood": 30},
	"firefighter": {"gold": 50, "wood": 30},
	"fisher": {"gold": 30, "wood": 12},
}

## Jobs auto-staffed by SimBuildings.tick_service — the roster respects
## their holders but never re-hires into them.
const AUTOSTAFF_JOBS := ["doctor", "firefighter", "guard", "guild_master"]

## Jobs filled by appointment (_appoint_officers), never by open hiring.
const APPOINTED_JOBS := ["adviser", "watchcaptain"]

## Jeremy 2026-10-03: player-set recruiting priorities per faction, via the
## guild master phone chat ("recruit more warriors"). Maps faction -> job id.
## The guild master biases training queues toward the priority job.
var recruit_priority: Dictionary = {}


## Set the recruiting priority for a faction (via guild master phone chat).
func set_recruit_priority(faction: String, job: String) -> void:
	recruit_priority[faction] = job


## Get the recruiting priority for a faction ("" = no priority set).
func get_recruit_priority(faction: String) -> String:
	return String(recruit_priority.get(faction, ""))


## Jeremy 2026-10-03: guild masters actively recruit — they queue training
## at their guild hall, biased toward the player's priority job if set.
## Otherwise they recruit a balanced mix (workers + military).
func _guild_master_recruit() -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("job", "")) != "guild_master":
			continue
		var faction: String = String(u.get("faction", ""))
		# Find the guild master's hall.
		var st: Dictionary = u.get("station", {})
		var hall: Dictionary = {}
		for b: Dictionary in _gs.buildings:
			if int(b.get("id", -1)) == int(st.get("building_id", -1)):
				hall = b
				break
		if hall.is_empty() or not hall.get("complete", false):
			continue
		var queue: Array = _train_queue(hall)
		if queue.size() >= 2:  # Don't over-queue; keep it steady.
			continue
		# Priority job from player, else balanced default.
		var auto := false
		var job: String = get_recruit_priority(faction)
		if job == "":
			auto = true
			# Balanced: alternate workers and military.
			var wcount: int = _gs.population.count_job(faction, "worker")
			var mcount: int = 0
			for mj: String in ["soldier", "archer", "ranger", "mage"]:
				mcount += _gs.population.count_job(faction, mj)
			job = "soldier" if mcount < wcount / 3 else "worker"
		# Jeremy 2026-10-04: population control — don't queue what the
		# faction doesn't need. A player-set priority is explicit intent
		# and skips the check; the balanced default is gated.
		if auto and _gs.spawner != null \
				and not _gs.spawner.faction_needs_unit(faction, job):
			continue
		queue_training(hall, job)


var _gs: GameState
var _hire_accum: float = 0.0
## Batch unit index: faction -> alive unit dicts (live refs, _gs.units
## order). Built once per hiring batch so the per-position scans in
## scan_positions/_hire_open_slots/_fill_farm_posts iterate the faction's
## slice instead of all units (75 positions x up to 4 full scans was a
## 50-80 ms spike every 4 s). Filters read live dict values, so mid-batch
## hires (job changes) are always seen. Ephemeral: cleared at batch end;
## helpers fall back to _gs.units when no batch is active (e.g. tests
## calling scan_positions directly).
var _batch_units: Dictionary = {}
## Perf R31: per-batch candidate indexes for _best_candidate. _begin_batch
## buckets alive units per faction into hire-candidate ref lists, so each
## open position scans seekers + laborers (small) instead of re-walking the
## full faction roster twice. Dict refs stay live: _best_candidate re-checks
## job/_hireable per position, so mid-batch hires are skipped exactly like
## the old per-position full scans (bit-identical choices).
var _batch_seekers: Dictionary = {}   # faction -> [unemployed unit refs]
var _batch_laborers: Dictionary = {}  # faction -> [worker unit refs]
## Worker-quota memo per batch: pop per (faction, town) and resources are
## constant during _hire_open_slots (hiring only reassigns jobs), so the
## quota computed for the first position of a town is reused for the rest.
var _quota_cache: Dictionary = {}


func _init(game_state: GameState) -> void:
	_gs = game_state


func _begin_batch() -> void:
	_batch_units.clear()
	_quota_cache.clear()
	_batch_seekers.clear()
	_batch_laborers.clear()
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var f: String = String(u.get("faction", ""))
		if not _batch_units.has(f):
			_batch_units[f] = []
			_batch_seekers[f] = []
			_batch_laborers[f] = []
		(_batch_units[f] as Array).append(u)
		# Perf R31: candidate buckets (job re-checked live per position).
		var job := String(u.get("job", ""))
		if job == "unemployed":
			(_batch_seekers[f] as Array).append(u)
		elif job == "worker":
			(_batch_laborers[f] as Array).append(u)


func _end_batch() -> void:
	_batch_units.clear()
	_quota_cache.clear()
	_batch_seekers.clear()
	_batch_laborers.clear()


## Alive units of a faction in _gs.units order. During a batch this is the
## prebuilt index slice; outside a batch it filters _gs.units directly.
func _faction_units(faction: String) -> Array:
	if not _batch_units.is_empty():
		return _batch_units.get(faction, [])
	var out: Array = []
	for u: Dictionary in _gs.units:
		if u.get("alive", false) \
				and String(u.get("faction", "")) == faction:
			out.append(u)
	return out


## One world tick: training queues always progress; the hiring sweep runs
## on the throttle. hour is 0-24 (WorkerAI.hour_of_day) for shift checks.
func tick(delta: float, hour: float) -> void:
	_tick_training(delta)
	_hire_accum += delta
	if _hire_accum < HIRE_INTERVAL:
		return
	_hire_accum = 0.0
	_begin_batch()
	_appoint_officers()
	_detect_workplace_loss()
	_update_unemployed()
	_hire_open_slots(hour)
	_assign_barracks()
	_guild_master_recruit()
	# Jeremy 2026-10-05: labor market (HTML stage8 port) — job
	# satisfaction + farm vacancy fill, same 4 s cadence as hiring.
	_tick_satisfaction()
	_fill_farm_posts()
	_end_batch()


## Bunks for existing military: any soldier without a barracks home takes a
## free bunk in the least-full barracks.
## Perf R29: free-bed cache for the sweep. _barracks_assigned is O(units),
## and assign_barracks_bed called it once per barracks per homeless
## soldier — O(soldiers x barracks x units). The sweep now counts once
## (O(buildings + units)) and decrements on its own assigns; nothing else
## mutates homes mid-sweep, so every pick is bit-identical. Outside a
## sweep the cache is empty and assign_barracks_bed uses the old path.
var _bed_free: Dictionary = {}


func _assign_barracks() -> void:
	_bed_free = _compute_bed_free()
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		var home: Dictionary = u.get("home", {})
		if not home.is_empty() and home.get("alive", false):
			continue
		assign_barracks_bed(u)
	_bed_free = {}


## Free bunks per completed barracks id: BARRACKS_BEDS minus every living
## unit currently homed there.
func _compute_bed_free() -> Dictionary:
	var free: Dictionary = {}
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("type", "")) != "barracks":
			continue
		free[int(b.get("id", -1))] = Config.BARRACKS_BEDS
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var home: Dictionary = u.get("home", {})
		if home.is_empty():
			continue
		var hid: int = int(home.get("id", -2))
		if free.has(hid):
			free[hid] = int(free[hid]) - 1
	return free


## ---- Training queues -------------------------------------------------------

## True when the building type can train the unit type.
static func can_train(btype: String, unit_type: String) -> bool:
	return unit_type in TRAINER_TYPES.get(btype, [])


## Queue a training job: charges the faction cost up front (refunded if the
## job is dropped after stall retries). Returns false when blocked
## ("unknown_type" | "not_trainer" | "queue_full" | "type_capped" |
## "unaffordable" | "foreign_sovereign" in last_train_block).
## by_player marks player-issued orders (Jeremy 2026-10-04 faction
## sovereignty): training another faction's troops directly is refused by
## that faction's leader — and the AI director's advisor mode skips any
## training line the player already queued (never duplicates player orders).
var last_train_block: String = ""


func queue_training(building: Dictionary, unit_type: String,
		by_player: bool = false, known_count: int = -1) -> bool:
	last_train_block = ""
	if building.is_empty() or not building.get("alive", false):
		last_train_block = "dead_building"
		return false
	if not building.get("complete", false):
		last_train_block = "incomplete"
		return false
	var btype: String = String(building.get("type", ""))
	if not can_train(btype, unit_type):
		last_train_block = "not_trainer"
		return false
	var queue: Array = _train_queue(building)
	if queue.size() >= TRAIN_QUEUE_MAX:
		last_train_block = "queue_full"
		return false
	var faction: String = String(building.get("faction", ""))
	# Faction sovereignty: the player can only train their own faction.
	if by_player and faction != "" and faction != _gs.player_faction:
		var fl = _gs.get("faction_leaders")
		if fl != null:
			fl.refuse_direct_control(faction)
		last_train_block = "foreign_sovereign"
		return false
	# perf R20: the AI director passes its per-think census count (identical
	# to count_job: live units of this faction+job; nothing spawns mid-think)
	# to skip a full unit scan per queue call. -1 = compute it here.
	var have: int = known_count if known_count >= 0 \
		else _gs.population.count_job(faction, unit_type)
	if have >= UNIT_TYPE_CAP:
		last_train_block = "type_capped"
		return false
	var cost: Dictionary = (TRAIN_COST.get(unit_type, {}) as Dictionary).duplicate()
	if cost.is_empty() or not _gs.resources.spend(faction, cost):
		last_train_block = "unaffordable"
		return false
	queue.append({"unit_type": unit_type, "time_left": float(TRAIN_TIME.get(unit_type, 4.0)),
		"stall_n": 0, "cost": cost, "by_player": by_player})
	return true


## Per-tick progress for every training queue. Graduates spawn via the
## Spawner (caps re-checked); a spawn-blocked job retries STALL_RETRIES
## times, then is dropped with a FULL cost refund.
func _tick_training(delta: float) -> void:
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		var queue: Array = _train_queue(b)
		if queue.is_empty():
			continue
		var job: Dictionary = queue[0]
		# Policies: government train-speed multiplier (HTML trainSpeed).
		var tmult := 1.0
		if _gs.get("court_sys") != null \
				and _gs.court_sys.get("policies") != null:
			tmult = _gs.court_sys.policies.train_speed_mult()
		job["time_left"] = float(job.get("time_left", 0.0)) - delta * tmult
		if float(job.get("time_left", 0.0)) > 0.0:
			continue
		var faction: String = String(b.get("faction", ""))
		var utype: String = String(job.get("unit_type", "worker"))
		# Undead elite soul gate (HTML soul check): spend soul at
		# graduation; stall (don't consume) when the faction lacks soul.
		if _gs.get("undead") != null \
				and _gs.undead.soul_cost(utype) > 0.0 \
				and not _gs.undead.train_elite(faction, utype):
			job["time_left"] = 3.0
			continue
		var made: Dictionary = _gs.spawner.spawn_unit(faction, utype,
			int(b.get("town_id", -1)),
			(b.get("position", Vector2.ZERO) as Vector2) + Vector2(28, 20))
		if made.is_empty():
			# Spawn blocked (caps): retry a few times, then drop + refund.
			var stall: int = int(job.get("stall_n", 0)) + 1
			job["stall_n"] = stall
			if stall < STALL_RETRIES:
				job["time_left"] = 3.0
				continue
			var cost: Dictionary = job.get("cost", {})
			for res: String in cost.keys():
				_gs.resources.add_resource(faction, res, float(cost[res]), true)
			# Never fail silently: a dropped graduate means the player watched
			# training finish and got nothing ("they don't even spawn in an
			# army"). Name the blocker so it can be acted on.
			var block_reason: String = String(
				_gs.spawner.last_block_reason)
			last_train_block = "graduate_blocked_" + block_reason
			# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
			SimGazette.publish_or_emit(_gs, "TRAINING WASTED",
				"%s barracks graduated a %s but there was no room (%s) — cost refunded." % [
					faction.capitalize(), utype, block_reason],
				"hiring")
			queue.pop_front()
			continue
		# Military graduates move straight into a barracks bunk.
		if JobDefs.is_military(utype):
			assign_barracks_bed(made)
			# Jeremy 2026-10-08 (wake rapid lane): feed the Gazette news
			# desk's RECRUITS MUSTER trivia bucket — one tally per
			# military graduation (wired live 2026-10-08; not dormant). Reported straight to the news desk,
			# not bus.gazette_story, so the rumor mill doesn't mint a
			# whisper for every recruit — the aggregated MUSTER story
			# still reaches the bus, Chronicle, and mill via
			# court.publish_story.
			_report_graduation_trivia(faction, utype)
		queue.pop_front()


## One training-completion tally for the news desk's RECRUITS MUSTER
## trivia bucket (called from _tick_training's graduation branch).
## Military graduations only (the bucket headline is RECRUITS MUSTER).
## Null-safe: bare-sim tests and worlds without a court skip silently;
## no new persisted state, so old saves are unaffected.
func _report_graduation_trivia(faction: String, utype: String) -> void:
	var court = _gs.get("court_sys")
	if court == null:
		return
	var desk = court.get("news_desk")
	if desk == null or not desk.has_method("report"):
		return
	var disp := utype.replace("_", " ")
	desk.report("completed training",
		"A %s completed training in %s lands." % [disp, faction.capitalize()])


## The training queue array on a building record (created on first use so
## saves stay lean).
func _train_queue(building: Dictionary) -> Array:
	if not building.has("train_queue"):
		building["train_queue"] = []
	return building["train_queue"] as Array


## ---- Officer appointments --------------------------------------------------
## Port of ensureGuildMaster57 / ensureAdviser57 / ensureWatchCaptain57.
## gov_role strings match SimPhone.GOV_RANK ("adviser", "guild_master",
## "watch_captain") — the other agent owns gov_role assignment at spawn;
## we only set it for officers WE appoint.


## One hiring sweep of officer posts (throttled).
func _appoint_officers() -> void:
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		var btype: String = String(b.get("type", ""))
		if btype != "town_hall" and btype != "hall":
			continue
		var faction: String = String(b.get("faction", ""))
		_ensure_adviser(b, faction)
		_ensure_watchcaptain(b, faction)
	_ensure_guild_master_office()


## The guild master is auto-staffed by SimBuildings.tick_service; here we
## give them their proper office: they LIVE and WORK in the guild hall
## (Jeremy's rule), with the town hall as fallback.
func _ensure_guild_master_office() -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("job", "")) != "guild_master":
			continue
		var faction: String = String(u.get("faction", ""))
		_set_gov_role(u, "guild_master")
		var gh: Dictionary = _nearest_completed(faction,
			["guild_hall"], u.get("position", Vector2.ZERO))
		var office: Dictionary = gh if not gh.is_empty() \
			else _nearest_completed(faction, ["town_hall", "hall"],
				u.get("position", Vector2.ZERO))
		if office.is_empty():
			continue
		u["station"] = {"job": "guild_master",
			"building_id": int(office["id"]),
			"spot": "desk", "act": "running the guild"}
		u["home"] = office  # lives AND works in the guild hall


## One adviser per completed government hall — appointed from the nearest
## eligible laborer, works a cubicle desk in the hall.
func _ensure_adviser(hall: Dictionary, faction: String) -> void:
	if not _officer_for(hall, "adviser").is_empty():
		return
	var u: Dictionary = _nearest_laborer(faction, hall["position"])
	if u.is_empty():
		return
	WorkerAI.assign_job(u, "adviser")
	_set_gov_role(u, "adviser")
	u["station"] = {"job": "adviser", "building_id": int(hall["id"]),
		"spot": "desk", "act": "balancing the books"}


## One watch captain per completed government hall — promoted from the
## nearest guard, else deputized from the nearest laborer.
func _ensure_watchcaptain(hall: Dictionary, faction: String) -> void:
	if not _officer_for(hall, "watchcaptain").is_empty():
		return
	var u: Dictionary = _nearest_job_unit(faction, "guard", hall["position"])
	if u.is_empty():
		u = _nearest_laborer(faction, hall["position"])
	if u.is_empty():
		return
	WorkerAI.assign_job(u, "watchcaptain")
	_set_gov_role(u, "watch_captain")
	u["station"] = {"job": "watchcaptain", "building_id": int(hall["id"]),
		"spot": "desk", "act": "commanding the watch"}


## The unit holding an officer post at a hall (via gov_role), or {}.
func _officer_for(hall: Dictionary, post: String) -> Dictionary:
	for u: Dictionary in _faction_units(String(hall.get("faction", ""))):
		if not u.get("alive", false):
			continue
		var got: String = String(_mind(u).get("gov_role", ""))
		if post == "watchcaptain" and got != "watch_captain":
			continue
		if post == "adviser" and got != "adviser":
			continue
		var st: Dictionary = u.get("station", {})
		if int(st.get("building_id", -1)) == int(hall.get("id", -2)):
			return u
	return {}


## Sets the government role on the unit's mind (phone contact rank).
func _set_gov_role(u: Dictionary, role: String) -> void:
	_mind(u)["gov_role"] = role


func _mind(u: Dictionary) -> Dictionary:
	if not u.has("mind"):
		u["mind"] = {}
	return u["mind"] as Dictionary


## Nearest alive adult unit of the faction with job "worker" and no
## officer post (deterministic: lowest unit id wins ties).
func _nearest_laborer(faction: String, pos: Vector2) -> Dictionary:
	return _nearest_job_unit(faction, "worker", pos)


func _nearest_job_unit(faction: String, job: String, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for u: Dictionary in _faction_units(faction):
		if not u.get("alive", false):
			continue
		if String(u.get("job", "")) != job:
			continue
		if not _hireable(u):
			continue
		var d: float = (u.get("position", Vector2.ZERO) as Vector2).distance_to(pos)
		var key: float = d + float(u.get("id", 0)) * 0.0001  # id breaks ties
		if key < best_d:
			best_d = key
			best = u
	return best


func _nearest_completed(faction: String, types: Array,
		pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not String(b.get("type", "")) in types:
			continue
		var d: float = (b.get("position", Vector2.ZERO) as Vector2).distance_to(pos)
		if d < best_d:
			best_d = d
			best = b
	return best


## ---- Unemployment ------------------------------------------------------------
## Jeremy 2026-10-04: units can lose their jobs. When a workplace is
## destroyed (or a unit is fired), they become "unemployed": they keep
## their urges and daily life, walk to the nearest guild hall, and wait
## for the guild master to assign them to an open position. The hiring
## sweep hires unemployed seekers FIRST (before repurposing workers).


## Lay off a unit: they become unemployed, lose their station/desk, and
## head for the guild hall. Emits a speech bubble so the player sees it.
func lay_off(u: Dictionary, reason: String = "") -> void:
	if u.is_empty() or not u.get("alive", false):
		return
	if String(u.get("job", "")) == "unemployed":
		return
	# Officers keep their posts — you can't lay off the guild master.
	var gov: String = String(_mind(u).get("gov_role", ""))
	if gov == "guild_master" or gov == "adviser" or gov == "watch_captain":
		return
	WorkerAI.release_desk(u)
	u["station"] = {}
	u["work_state"] = "idle"
	u["work_pose"] = null
	u.erase("_seek_pos")
	u.erase("_farm_plot_id")  # Jeremy 2026-10-05: laid-off farmhands lose
	                          # their plot assignment (labor market)
	WorkerAI.assign_job(u, "unemployed")
	var why: String = (" (" + reason + ")") if reason != "" else ""
	_gs.bus.unit_said.emit(int(u.get("id", 0)),
		"Lost my job%s — seeking work at the guild hall…" % why)


## True when the unit is unemployed and seeking work.
func is_unemployed(u: Dictionary) -> bool:
	return String(u.get("job", "")) == "unemployed"


## Count of unemployed units for a faction (for UI / guild master logic).
func unemployed_count(faction: String) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == faction \
				and is_unemployed(u):
			n += 1
	return n


## Sweep: units whose station building died (destroyed, captured, or
## otherwise gone) are laid off instead of idling forever.
func _detect_workplace_loss() -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if is_unemployed(u):
			continue
		var st: Dictionary = u.get("station", {})
		if st.is_empty():
			continue
		var bid: int = int(st.get("building_id", -1))
		var b: Dictionary = _building_by_id(bid)
		if b.is_empty() or not b.get("alive", false):
			lay_off(u, "workplace destroyed")


## Sweep: point every unemployed unit at the nearest completed guild hall
## (town hall fallback). They walk there and wait for assignment.
func _update_unemployed() -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) or not is_unemployed(u):
			continue
		var pos: Vector2 = u.get("position", Vector2.ZERO)
		var faction: String = String(u.get("faction", ""))
		var hall: Dictionary = _nearest_completed(faction,
			["guild_hall"], pos)
		if hall.is_empty():
			hall = _nearest_completed(faction, ["town_hall", "hall"], pos)
		if hall.is_empty():
			u.erase("_seek_pos")
			continue
		var hp: Vector2 = hall.get("position", Vector2.ZERO)
		# Loiter near the hall entrance, not inside the walls.
		var seek := hp + Vector2(36, 28)
		u["_seek_pos"] = seek
		if pos.distance_to(seek) < 70.0:
			# Arrived: wait at the hall. Occasional status bubble.
			u.erase("_seek_pos")
			if int(u.get("id", 0)) % 7 == int(_gs.day_number) % 7 \
					and not bool(u.get("_seek_said_today", false)):
				u["_seek_said_today"] = true
				_gs.bus.unit_said.emit(int(u.get("id", 0)),
					"Still looking for work…")
		else:
			u["_seek_said_today"] = false


func _building_by_id(bid: int) -> Dictionary:
	# Jeremy 2026-10-05 perf: shared O(1) id index on GameState.
	return _gs.get_building(bid)


## ---- Labor roster + hiring --------------------------------------------------
## Port of rosterScan57 / rosterOpen57 / rosterBestCandidate57 /
## rosterHireTick57 (MISS 14). Runs on the hiring throttle.


## Scans every completed workplace building into open positions:
## [{job, building_id, building_type, faction, town_id, slots, holders}].
## Perf R31: building type -> WORKPLACES entries, built once. scan_positions
## did a 14-entry `btype in e["types"]` array scan per building.
static var _WORKPLACES_BY_BTYPE: Dictionary = {}


static func _workplaces_for(btype: String) -> Array:
	if _WORKPLACES_BY_BTYPE.is_empty():
		for e: Dictionary in JobDefs.WORKPLACES:
			for t in (e["types"] as Array):
				var tt := String(t)
				if not _WORKPLACES_BY_BTYPE.has(tt):
					_WORKPLACES_BY_BTYPE[tt] = []
				(_WORKPLACES_BY_BTYPE[tt] as Array).append(e)
	return _WORKPLACES_BY_BTYPE.get(btype, [])


func scan_positions() -> Array:
	var buckets: Dictionary = _holder_buckets()
	var positions: Array = []
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		var btype: String = String(b.get("type", ""))
		# Perf R31: static btype -> WORKPLACES map instead of the 14-entry
		# array scan per building.
		for e: Dictionary in _workplaces_for(btype):
			# Officer posts anchor on the town hall only (unique per town).
			var job: String = String(e["job"])
			if (job == "guild_master" or job == "adviser" or job == "watchcaptain") \
					and not btype in ["town_hall", "hall"]:
				continue
			var pfaction: String = String(b.get("faction", ""))
			var p: Dictionary = {
				"job": job,
				"building_id": int(b["id"]),
				"building_type": btype,
				"faction": pfaction,
				"town_id": int(b.get("town_id", -1)),
				"spot": String(e["spot"]),
				"act": String(e["act"]),
				"slots": JobDefs.slots_for(btype, int(e["slots"])),
				"holders": _holders_for(pfaction, job, int(b["id"]), buckets),
			}
			positions.append(p)
	return positions


## Perf R29: the holders scan used to cost O(positions x faction_units) —
## every position re-walked the faction's whole roster through
## _holder_matches. Now one pass over each faction's roster buckets units
## by holder key (gov-role bucket + job/station bucket); each position is
## a dict lookup. Per-faction iteration order is unchanged, so every
## position's holders array is bit-identical (contents and order) to the
## old scan. _holder_matches stays as the spec/oracle for tests.
func _holder_buckets() -> Dictionary:
	# faction -> {"gov": {role: [unit ids]}, "job": {job: {building_id: [ids]}}}
	# Faction set = active factions plus any faction owning live units: the
	# old code scanned per position faction, so non-active factions with
	# workplace buildings (e.g. monster dens) must bucket too.
	var factions: Dictionary = {}
	for f: String in _gs.active_factions:
		factions[f] = true
	for u0: Dictionary in _gs.units:
		if u0.get("alive", false):
			factions[String(u0.get("faction", ""))] = true
	var buckets: Dictionary = {}
	for f: String in factions.keys():
		var fb: Dictionary = {"gov": {}, "job": {}}
		buckets[f] = fb
		var gov: Dictionary = fb["gov"]
		var jobd: Dictionary = fb["job"]
		for u: Dictionary in _faction_units(f):
			if not u.get("alive", false):
				continue
			var uid: int = int(u.get("id", 0))
			var role: String = String(_mind(u).get("gov_role", ""))
			if role == "guild_master" or role == "watch_captain" \
					or role == "adviser":
				if not gov.has(role):
					gov[role] = []
				(gov[role] as Array).append(uid)
			var uj: String = String(u.get("job", ""))
			var st: Dictionary = u.get("station", {})
			var bid: int = int(st.get("building_id", -1))
			if not jobd.has(uj):
				jobd[uj] = {}
			var jm: Dictionary = jobd[uj]
			if not jm.has(bid):
				jm[bid] = []
			(jm[bid] as Array).append(uid)
	return buckets


## Holder unit ids for one position record (each caller gets its own
## array, like the old per-position append loop).
func _holders_for(faction: String, job: String, building_id: int,
		buckets: Dictionary) -> Array:
	var fb: Dictionary = buckets.get(faction, {})
	if fb.is_empty():
		return []
	var role := ""
	if job == "guild_master":
		role = "guild_master"
	elif job == "watchcaptain":
		role = "watch_captain"
	elif job == "adviser":
		role = "adviser"
	if role != "":
		return ((fb["gov"] as Dictionary).get(role, []) as Array).duplicate()
	var jm: Dictionary = (fb["job"] as Dictionary).get(job, {})
	return (jm.get(building_id, []) as Array).duplicate()


## True when the unit holds the roster position.
func _holder_matches(u: Dictionary, p: Dictionary) -> bool:
	if not u.get("alive", false):
		return false
	if String(u.get("faction", "")) != String(p["faction"]):
		return false
	var job: String = String(p["job"])
	var mind: Dictionary = _mind(u)
	if job == "guild_master":
		return String(mind.get("gov_role", "")) == "guild_master"
	if job == "watchcaptain":
		return String(mind.get("gov_role", "")) == "watch_captain"
	if job == "adviser":
		return String(mind.get("gov_role", "")) == "adviser"
	if String(u.get("job", "")) != job:
		return false
	var st: Dictionary = u.get("station", {})
	return int(st.get("building_id", -1)) == int(p["building_id"])


## Hires laborers into every open roster slot (one sweep). Skips
## auto-staffed jobs (tick_service owns those) and soldier slots (the
## training queue owns military). Never drains laborers below the town's
## worker quota — the town still needs gatherers.
func _hire_open_slots(_hour: float) -> void:
	var positions: Array = scan_positions()
	# Shops first: Jeremy's rule is to staff shops all business hours.
	# Government offices (town_hall) hire after workplaces are covered.
	positions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ao: int = 1 if String(a.get("building_type", "")) == "town_hall" else 0
		var bo: int = 1 if String(b.get("building_type", "")) == "town_hall" else 0
		if ao != bo:
			return ao < bo
		return int(a.get("building_id", 0)) < int(b.get("building_id", 0)))
	for p: Dictionary in positions:
		var job: String = String(p["job"])
		if job in AUTOSTAFF_JOBS or job in APPOINTED_JOBS or job == "soldier":
			continue
		var open: int = int(p["slots"]) - (p["holders"] as Array).size()
		while open > 0:
			var u: Dictionary = _best_candidate(p)
			if u.is_empty():
				break
			_hire(p, u)
			open -= 1
	_maintain_military()


## Best hire candidate: UNEMPLOYED seekers first (they walked to the
## guild hall asking for work), then a laborer of the position's faction,
## nearest the building, deterministic by unit id. Returns {} when hiring
## a laborer would drop the town's workers below the worker quota
## (unemployed hires never count against the quota — they're pure gain).
##
## Perf R28: when no unemployed seeker exists, the laborer headcount and
## the nearest-laborer search share a single pass over the faction's
## units (the old code walked the list twice more). Iteration order,
## filters, and the id tie-break are unchanged, so the hire choice is
## bit-identical to before.
func _best_candidate(p: Dictionary) -> Dictionary:
	var faction: String = String(p["faction"])
	var b: Dictionary = _building_by_id(int(p["building_id"]))
	var bp: Vector2 = b.get("position", Vector2.ZERO) as Vector2 \
		if not b.is_empty() else Vector2.ZERO
	# Unemployed seekers first — no quota check, they're asking for work.
	# Perf R31: scan the prebuilt seeker list when in a batch (same candidate
	# set as the full-roster scan; job/_hireable re-checked live so mid-batch
	# hires are skipped identically). Outside a batch, use the oracle helper.
	if _batch_seekers.is_empty():
		var seeker: Dictionary = _nearest_seeker(faction, bp)
		if not seeker.is_empty():
			return seeker
	else:
		var best: Dictionary = {}
		var best_d := INF
		for u: Dictionary in (_batch_seekers.get(faction, []) as Array):
			if not u.get("alive", false):
				continue
			if not is_unemployed(u):
				continue  # hired earlier in this batch
			if not _hireable(u):
				continue
			var d: float = (u.get("position", Vector2.ZERO) as Vector2).distance_to(bp)
			var key: float = d + float(u.get("id", 0)) * 0.0001  # id breaks ties
			if key < best_d:
				best_d = key
				best = u
		if not best.is_empty():
			return best
	var laborers := 0
	var laborer: Dictionary = {}
	var laborer_d := INF
	# Perf R31: prebuilt laborer list in a batch (live job re-check keeps the
	# quota count and the nearest pick bit-identical to the full scan).
	var pool: Array = (_batch_laborers.get(faction, []) as Array) \
		if not _batch_laborers.is_empty() else _faction_units(faction)
	for u: Dictionary in pool:
		if not u.get("alive", false):
			continue
		if String(u.get("job", "")) != "worker":
			continue
		laborers += 1
		if not _hireable(u):
			continue
		var up: Vector2 = u.get("position", Vector2.ZERO)
		var key: float = up.distance_to(bp) \
			+ float(u.get("id", 0)) * 0.0001  # id breaks ties
		if key < laborer_d:
			laborer_d = key
			laborer = u
	if laborers <= _worker_quota(p):
		return {}
	return laborer


## Nearest unemployed unit of the faction (deterministic by unit id).
func _nearest_seeker(faction: String, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for u: Dictionary in _faction_units(faction):
		if not u.get("alive", false):
			continue
		if not is_unemployed(u):
			continue
		if not _hireable(u):
			continue
		var d: float = (u.get("position", Vector2.ZERO) as Vector2).distance_to(pos)
		var key: float = d + float(u.get("id", 0)) * 0.0001  # id breaks ties
		if key < best_d:
			best_d = key
			best = u
	return best


## HTML rosterBestCandidate57 parity: criminals, the jailed, and current
## office-holders are never hired into positions. (Children and ruler units
## have no Godot equivalent — the crown is the player.)
func _hireable(u: Dictionary) -> bool:
	if String(_mind(u).get("gov_role", "")) != "":
		return false
	var court = _gs.get("court_sys")
	var crime = null
	if court != null:
		crime = court.get("crime")
	if crime != null:
		var uid: int = int(u.get("id", 0))
		var rec: Dictionary = crime.rec_for(uid)
		if bool(rec.get("criminal", false)):
			return false
		if crime.is_jailed(uid):
			return false
	return true


## Worker quota — port of computeQuotas57's worker line: the town keeps at
## least this many general laborers gathering/building.
func _worker_quota(p: Dictionary) -> int:
	var faction: String = String(p["faction"])
	var town_id: int = int(p["town_id"])
	var key: String = faction + "|" + str(town_id)
	if _quota_cache.has(key):
		return int(_quota_cache[key])
	var pop := 0
	for u: Dictionary in _faction_units(faction):
		if not u.get("alive", false):
			continue
		if town_id >= 0 and int(u.get("town_id", -1)) != town_id:
			continue
		pop += 1
	var wood: float = _gs.resources.get_amount(faction, "wood")
	var food: float = _gs.resources.get_amount(faction, "food")
	var gold: float = _gs.resources.get_amount(faction, "gold")
	var q: int = 2 + int(ceil(pop * 0.22))
	if wood < 300.0 or food < 300.0:
		q += 2
	if gold < 200.0:
		q += 1
	_quota_cache[key] = q
	return q


## Hire one laborer into one position: job + station assigned, shift reset.
func _hire(p: Dictionary, u: Dictionary) -> void:
	WorkerAI.assign_job(u, String(p["job"]))
	_set_gov_role(u, _gov_role_for(String(p["job"])))
	u["station"] = {"job": String(p["job"]),
		"building_id": int(p["building_id"]),
		"spot": String(p["spot"]), "act": String(p["act"])}


func _gov_role_for(job: String) -> String:
	match job:
		"guild_master":
			return "guild_master"
		"adviser":
			return "adviser"
		"watchcaptain":
			return "watch_captain"
	return ""


## ---- Military demand -> training -------------------------------------------
## The guild master and the watch captain "actively hire" military too
## (Jeremy's rule): barracks with an empty queue start training toward the
## town's military quotas (port of the HTML's continuous military
## production).


func _maintain_military() -> void:
	_mil_memo.clear()
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("type", "")) != "barracks":
			continue
		if not (_train_queue(b) as Array).is_empty():
			continue
		var faction: String = String(b.get("faction", ""))
		# Perf R29: per-faction memo for the sweep. get_faction_pop and the
		# soldier/archer counts are identical for every barracks of a
		# faction, and nothing between the want check and the queue call
		# changes military rosters (queues only complete later, in
		# _tick_training), so passing the memo as known_count is
		# bit-identical to recounting inside queue_training.
		if not _mil_memo.has(faction):
			_mil_memo[faction] = {
				"pop": _gs.population.get_faction_pop(faction),
				"soldier": _gs.population.count_job(faction, "soldier"),
				"archer": _gs.population.count_job(faction, "archer"),
			}
		var m: Dictionary = _mil_memo[faction]
		var want: String = _military_want_memo(m)
		if want == "":
			continue
		queue_training(b, want, false, int(m[want]))


## Perf R29: per-faction military roster memo, filled by
## _maintain_military each sweep. Empty outside the sweep.
var _mil_memo: Dictionary = {}


## Which military type the faction wants trained next ("" = none): keeps
## soldiers near quota, archers as skirmish support, mages rare. Quotas
## port computeQuotas57 (soldier = ceil(pop*0.08) + threat*2); threat is
## not simulated yet, so this is the peacetime baseline.
func _military_want(faction: String) -> String:
	var pop: int = _gs.population.get_faction_pop(faction)
	var soldier_q: int = maxi(2, int(ceil(pop * 0.08)))
	var archer_q: int = maxi(1, int(pop * 0.04))
	if _gs.population.count_job(faction, "soldier") < soldier_q:
		return "soldier"
	if _gs.population.count_job(faction, "archer") < archer_q:
		return "archer"
	return ""


## Memoized twin of _military_want for the sweep: identical decisions from
## the precomputed roster counts.
func _military_want_memo(m: Dictionary) -> String:
	var pop: int = int(m["pop"])
	var soldier_q: int = maxi(2, int(ceil(pop * 0.08)))
	var archer_q: int = maxi(1, int(pop * 0.04))
	if int(m["soldier"]) < soldier_q:
		return "soldier"
	if int(m["archer"]) < archer_q:
		return "archer"
	return ""


## ---- Barracks beds ----------------------------------------------------------
## MISS 16: 25 beds per barracks (Config.BARRACKS_BEDS). House one military
## unit: the least-full completed barracks of its faction wins (ties by
## building id — deterministic). A full house means the unit waits and the
## shortfall shows up as demand.


## Assigns a bunk to a military unit; sets unit["home"] = barracks.
## Returns the barracks, or {} when none has a free bed.
func assign_barracks_bed(u: Dictionary) -> Dictionary:
	if u.is_empty() or not u.get("alive", false):
		return {}
	if not JobDefs.is_military(String(u.get("job", ""))):
		return {}
	var home: Dictionary = u.get("home", {})
	if not home.is_empty() and home.get("alive", false) \
			and _barracks_beds(home) > 0:
		# Perf R29: cached free-bed count when a sweep cache is active;
		# identical old computation otherwise (e.g. the training path).
		var hid0: int = int(home.get("id", -2))
		var keep := false
		if not _bed_free.is_empty() and _bed_free.has(hid0):
			keep = int(_bed_free[hid0]) > 0
		else:
			keep = _barracks_assigned(home) < Config.BARRACKS_BEDS
		if keep:
			return home
	var faction: String = String(u.get("faction", ""))
	var best: Dictionary = {}
	var best_free := -1
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if _barracks_beds(b) <= 0:
			continue
		var bid: int = int(b.get("id", -1))
		var free: int
		if not _bed_free.is_empty() and _bed_free.has(bid):
			free = int(_bed_free[bid])
		else:
			free = Config.BARRACKS_BEDS - _barracks_assigned(b)
		if free <= 0:
			continue
		if free > best_free or (free == best_free and not best.is_empty() \
				and int(b.get("id", 0)) < int(best.get("id", 0))):
			best = b
			best_free = free
	if not best.is_empty():
		u["home"] = best
		var best_id: int = int(best.get("id", -1))
		if _bed_free.has(best_id):
			_bed_free[best_id] = int(_bed_free[best_id]) - 1
	return best


## Staffing demand for a faction: {beds, assigned, military, shortfall}.
## A shortfall is demand for another barracks.
func barracks_demand(faction: String) -> Dictionary:
	var beds := 0
	var assigned := 0
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or String(b.get("faction", "")) != faction:
			continue
		if _barracks_beds(b) <= 0:
			continue
		beds += Config.BARRACKS_BEDS
		assigned += _barracks_assigned(b)
	var military := 0
	for u: Dictionary in _gs.units:
		if u.get("alive", false) and String(u.get("faction", "")) == faction \
				and JobDefs.is_military(String(u.get("job", ""))):
			military += 1
	return {"kind": "barracks", "faction": faction, "beds": beds,
		"assigned": assigned, "military": military,
		"shortfall": maxi(0, military - beds)}


func _barracks_beds(b: Dictionary) -> int:
	if String(b.get("type", "")) == "barracks":
		return Config.BARRACKS_BEDS
	return 0


func _barracks_assigned(b: Dictionary) -> int:
	var n := 0
	var bid: int = int(b.get("id", -1))
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var home: Dictionary = u.get("home", {})
		if not home.is_empty() and int(home.get("id", -2)) == bid:
			n += 1
	return n


## ---- Labor market: job satisfaction + farm vacancies -----------------------
## Jeremy 2026-10-05: AI-first phase — port of HTML fix79 stage8LaborTick's
## satisfaction model (s8SatisfactionSlice) and farm staffing
## (s8FillFarmPosts). HTML-verbatim economics:
##   - jobSat 0..100, drifts 6% toward neutral 55 each pass
##   - pay matters: (wage - 2.5) * 1.5 (S8_WAGE table verbatim)
##   - military -2 ("service is duty, not joy"), farmer on assigned land
##     +1.5, shopkeeper/cashier at a living shop +1, homeless -1.5,
##     downed -4
##   - each farm plot keeps one owner (jobSat 62) + up to 3 hands (jobSat
##     60), hired from seekers: idle jobless first, then dissatisfied
##     (jobSat < 25) switchers — HTML s8IsSeeker's "grounded reason to
##     switch". A poached shopkeeper's old post goes vacant and the roster
##     refills it: the full labor-market loop.
## Deliberate deviations from HTML (documented):
##   - military VOLUNTEERING and 3-day enlistment terms are NOT ported:
##     Godot's training-queue + barracks military model deliberately
##     replaces the HTML volunteer draft.
##   - undead plots ARE staffed (HTML C61F skipped them: "the dead do not
##     farm") — Godot's flesh_farm economy needs undead farmhands.
##   - wage fallback by JobDefs category (HTML only knew 7 jobs):
##     military/service 2.8 (= HTML isWorker=false default), civilian 2.2
##     (= isWorker=true default).
##   - per-unit on-fire has no Godot field (buildings carry on_fire), so
##     only "downed" applies the -4.
##   - hired farmers walk to their plot through the normal WorkerAI farmer
##     chore machine (assigned plot preferred via nearest_work_plot's
##     prefer_id) instead of an HTML moveTarget.

## HTML S8_WAGE verbatim.
const S8_WAGE := {
	"worker": 2.5, "roadbuilder": 2.2, "farmer": 2.6, "shopkeeper": 2.4,
	"cashier": 2.2, "soldier": 3.0, "guard": 3.0,
}
const FARM_HANDS_WANT := 3      # HTML: owner + 3 workers per plot
const FARM_OWNER_SAT := 62.0    # HTML: farm owner jobSat on hire
const FARM_HAND_SAT := 60.0     # HTML: farmhand jobSat on hire
const SEEKER_SAT_GATE := 25.0   # HTML s8IsSeeker: jobSat < 25 = switch
const SAT_SLICE := 200          # HTML: up to 200 units per satisfaction pass

var _sat_idx := 0  # rotating index for the staggered satisfaction slice


## HTML S8_WAGE for known jobs; Godot-only jobs fall back by category.
static func _s8_wage(job: String) -> float:
	if S8_WAGE.has(job):
		return float(S8_WAGE[job])
	var cat := JobDefs.category(job)
	if cat == "military" or cat == "service":
		return 2.8  # HTML isWorker=false default
	return 2.2  # HTML isWorker=true default


## Job-satisfaction pass (HTML s8SatisfactionSlice verbatim economics).
## Staggered: up to SAT_SLICE units per sweep, rotating index.
func _tick_satisfaction() -> void:
	var units: Array = _gs.units
	if units.is_empty():
		return
	var n: int = mini(units.size(), SAT_SLICE)
	for k in n:
		var u: Dictionary = units[_sat_idx % units.size()]
		_sat_idx += 1
		if not u.get("alive", false):
			continue
		var s: float = float(u.get("jobSat", 60.0))
		s += (55.0 - s) * 0.06                      # slow drift to neutral
		var job: String = String(u.get("job", ""))
		s += (_s8_wage(job) - 2.5) * 1.5            # pay matters
		if JobDefs.is_military(job):
			s -= 2.0                                # service is duty, not joy
		if job == "farmer" and _farm_plot_alive(u):
			s += 1.5                               # working the land feels good
		if (job == "shopkeeper" or job == "cashier") \
				and _station_shop_alive(u):
			s += 1.0
		if _unit_homeless(u):
			s -= 1.5                               # homeless hurts
		if bool(u.get("downed", false)):
			s -= 4.0
		u["jobSat"] = clampf(s, 0.0, 100.0)


## True when the unit's assigned farm plot still exists (HTML farmOf(u)).
func _farm_plot_alive(u: Dictionary) -> bool:
	var farming = _gs.get("farming")
	if farming == null:
		return false
	var pid: int = int(u.get("_farm_plot_id", -1))
	return pid > 0 and not farming.get_plot(pid).is_empty()


## True when the unit's station building is alive and completed
## (shopkeeper/cashier morale bonus).
func _station_shop_alive(u: Dictionary) -> bool:
	var st: Dictionary = u.get("station", {})
	if st.is_empty():
		return false
	var b := _building_by_id(int(st.get("building_id", -1)))
	return not b.is_empty() and b.get("alive", false) \
		and b.get("complete", false)


## Homeless check, mirroring SimHousing._is_homeless (kept local so the
## labor pass never depends on housing tick order).
func _unit_homeless(u: Dictionary) -> bool:
	var home: Dictionary = u.get("home", {})
	return home.is_empty() or not home.get("alive", false)


## Staff every farm plot: one owner + FARM_HANDS_WANT hands
## (HTML s8FillFarmPosts verbatim: owner jobSat 62, hands 60).
func _fill_farm_posts() -> void:
	var farming = _gs.get("farming")
	if farming == null:
		return
	_clear_stale_farm_links(farming)
	for plot: Dictionary in farming.plots:
		if plot.is_empty():
			continue
		# Prune dead workers (HTML aliveWorkers pass).
		var alive_workers: Array = []
		for wid in plot.get("worker_uids", []):
			var wu: Dictionary = _gs.get_unit(int(wid))
			if not wu.is_empty() and wu.get("alive", false):
				alive_workers.append(int(wid))
		plot["worker_uids"] = alive_workers
		var owner: Dictionary = _gs.get_unit(int(plot.get("owner_uid", -1)))
		var need_owner: bool = owner.is_empty() \
			or not owner.get("alive", false)
		var need_workers: int = maxi(0, FARM_HANDS_WANT - alive_workers.size())
		if not need_owner and need_workers <= 0:
			continue
		var seekers := _farm_seekers(String(plot.get("faction", "")),
			plot.get("position", Vector2.ZERO))
		var si := 0
		if need_owner and si < seekers.size():
			_hire_farmer(seekers[si] as Dictionary, plot, true)
			si += 1
		while need_workers > 0 and si < seekers.size():
			_hire_farmer(seekers[si] as Dictionary, plot, false)
			si += 1
			need_workers -= 1


## Drop _farm_plot_id links whose plot no longer exists so those farmers
## fall back to the open chore market instead of idling on a dead post.
func _clear_stale_farm_links(farming) -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var pid: int = int(u.get("_farm_plot_id", -1))
		if pid > 0 and farming.get_plot(pid).is_empty():
			u.erase("_farm_plot_id")


## Job seekers for farm posts (HTML s8IsSeeker): idle jobless first, then
## dissatisfied (jobSat < SEEKER_SAT_GATE) switchers. Never: leaders,
## children, officers (gov_role), military (can't quit mid-term),
## homesteaders, or units the sim already owns (player orders,
## urge-trippers, siege-owned). Nearest the plot first.
func _farm_seekers(faction: String, plot_pos: Vector2) -> Array:
	var out: Array = []
	for u: Dictionary in _faction_units(faction):
		if not u.get("alive", false):
			continue
		if bool(u.get("is_leader", false)) or bool(u.get("is_child", false)):
			continue
		if u.has("_homestead"):
			continue
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue
		if String(u.get("mind_state", "")).begins_with("satisfying:"):
			continue
		if bool(u.get("_siege_hide", false)) \
				or bool(u.get("_siege_repair", false)):
			continue
		if String(_mind(u).get("gov_role", "")) != "":
			continue
		var job: String = String(u.get("job", ""))
		if JobDefs.is_military(job):
			continue  # cannot quit mid-term
		var sat: float = float(u.get("jobSat", 60.0))
		if job != "unemployed" and sat >= SEEKER_SAT_GATE:
			continue
		out.append(u)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.get("position", Vector2.ZERO) as Vector2) \
				.distance_to(plot_pos) \
			< (b.get("position", Vector2.ZERO) as Vector2) \
				.distance_to(plot_pos))
	return out


## Put a seeker to work on a plot (HTML s8FillFarmPosts hire verbatim:
## clear work, job=farmer, jobSat set, plot link). The farmer then walks
## to the plot through the normal WorkerAI chore machine, which prefers
## the assigned plot (SimFarming.nearest_work_plot prefer_id).
func _hire_farmer(u: Dictionary, plot: Dictionary, is_owner: bool) -> void:
	if u.is_empty() or not u.get("alive", false):
		return
	WorkerAI.release_desk(u)
	u["station"] = {}
	u["work_state"] = "idle"
	u.erase("_seek_pos")
	WorkerAI.assign_job(u, "farmer")
	var pid: int = int(plot.get("id", -1))
	u["_farm_plot_id"] = pid
	var uid: int = int(u.get("id", -1))
	if is_owner:
		plot["owner_uid"] = uid
		u["jobSat"] = FARM_OWNER_SAT
	else:
		var wids: Array = plot.get("worker_uids", [])
		wids.append(uid)
		plot["worker_uids"] = wids
		u["jobSat"] = FARM_HAND_SAT
	# New-hire bubble for the player's own faction only (HTML bubbled the
	# player race; AI hires stay quiet).
	if String(u.get("faction", "")) == _gs.player_faction:
		_gs.bus.unit_said.emit(uid,
			"My farm!" if is_owner else "Hired on as a farmhand.")
