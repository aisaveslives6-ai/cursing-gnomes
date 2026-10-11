class_name AutosaveSystem
extends Node
## Cursing Gnomes — autosave (Milestone 7: polish & ship).
##
## HTML behavior: the game saved on tab close (visibilitychange/pagehide).
## Web exports cannot reliably catch tab close, so this port does:
##   1. PERIODIC autosave — every N minutes while playing (user setting,
##      default ON, default 5 minutes).
##   2. SAVE-ON-QUIT-TO-MENU — the host calls save_now("quit") before
##      tearing the world down (see HOOKS).
## Platform limitation: a killed/closed browser tab may still lose the last
## few minutes — nothing in a web export can hook the close event reliably.
##
## The autosave lives OUTSIDE the 8 manual slots (user://saves/autosave.json)
## so it can never clobber a manual save. Settings come from the same
## user://settings.json the menu writes: "autosave" (bool, default true),
## "autosave_minutes" (int, default 5).


signal autosaved(path: String)
signal autosave_failed(reason: String)


const AUTOSAVE_PATH := "user://saves/autosave.json"
const SETTINGS_PATH := "user://settings.json"
const DEFAULT_MINUTES := 5

var _game: GameState = null
var _get_adventure: Callable = Callable()  # () -> SimAdventure or null
var _acc := 0.0
var _enabled := true
var _minutes := DEFAULT_MINUTES


## Wire to a live game. get_adventure is a Callable returning the world's
## adventure instance (or null) for adventure-mode saves.
func setup(game: GameState, get_adventure: Callable = Callable()) -> void:
	_game = game
	_get_adventure = get_adventure
	_load_settings()
	set_process(true)


func _load_settings() -> void:
	_enabled = true
	_minutes = DEFAULT_MINUTES
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_enabled = bool(parsed.get("autosave", true))
				_minutes = maxi(1, int(parsed.get("autosave_minutes",
					DEFAULT_MINUTES)))


## Hot-reload settings (called when the menu emits settings_changed).
func refresh_settings() -> void:
	_load_settings()
	_acc = 0.0


func _process(delta: float) -> void:
	if _game == null or not _enabled:
		return
	_acc += delta
	if _acc >= float(_minutes) * 60.0:
		_acc = 0.0
		save_now("periodic")


## Write a snapshot now. reason: "periodic" | "quit" | "manual".
func save_now(reason := "manual") -> bool:
	if _game == null:
		return false
	if _game.units.is_empty() and _game.buildings.is_empty():
		return false  # nothing worth saving yet
	var adventure = null
	if _get_adventure.is_valid():
		adventure = _get_adventure.call()
	var data := SaveSystem.snapshot(_game, adventure)
	data["autosave"] = true
	data["autosave_reason"] = reason
	data["autosave_at"] = Time.get_unix_time_from_system()
	if not DirAccess.dir_exists_absolute("user://saves"):
		DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(AUTOSAVE_PATH, FileAccess.WRITE)
	if f == null:
		autosave_failed.emit("could not open " + AUTOSAVE_PATH)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	autosaved.emit(AUTOSAVE_PATH)
	return true


## Load the autosave snapshot, or {} when none exists.
static func load_autosave() -> Dictionary:
	if not FileAccess.file_exists(AUTOSAVE_PATH):
		return {}
	var f := FileAccess.open(AUTOSAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
