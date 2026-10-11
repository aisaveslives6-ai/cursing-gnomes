class_name UITapSfx
extends Node
## Cursing Gnomes — global UI tap feedback (2026-10-09 rapid-iteration).
##
## Every button press anywhere (main menu, phone apps, HUD, dialogs,
## keyboard keys) emits ui_click on the global Events autoload bus;
## AudioManager answers with the synthesized "click". Before this, ALL UI
## taps were silent — the "click" SFX sat in the synth registry with zero
## callers (2026-10-09 SFX audit finding).
##
## Wiring is automatic: the initial subtree sweep catches buttons built
## before this node is ready, and SceneTree.node_added catches every
## button created later (including the phone keyboard's per-key Buttons).
## A _cg_click_wired meta flag prevents double-wiring on re-adds.
## OptionButton extends Button, so dropdowns click too. Non-Button
## controls are untouched. Mute/sfx_volume apply via the SFX pool.
##
## The Events autoload is fetched via get_node_or_null (bare autoload
## identifiers don't resolve in headless -s script runs; cf. world.gd's
## Game fetch). If the bus is absent (isolated harnesses) taps stay silent.

var _bus: EventBus = null


func _ready() -> void:
	# The Events autoload is the global bus; it exists before any GameState,
	# so menu buttons click too.
	_bus = get_tree().root.get_node_or_null("Events") as EventBus
	_wire_subtree(get_tree().root)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	_wire_subtree(node)


func _wire_subtree(node: Node) -> void:
	if node is Button:
		_wire_button(node as Button)
	for child in node.get_children():
		_wire_subtree(child)


func _wire_button(b: Button) -> void:
	if b.has_meta("_cg_click_wired"):
		return
	b.set_meta("_cg_click_wired", true)
	b.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	if _bus != null:
		_bus.ui_click.emit()
