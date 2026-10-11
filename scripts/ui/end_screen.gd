class_name EndScreen
extends CanvasLayer
## Cursing Gnomes — end-of-game screen.
##
## HTML parity (screen-end, fix79):
##   - standard win:  "VICTORY" (green) — "<City> stands. Enemy Halls are rubble."
##   - standard loss: "DEFEAT"  (red)   — "The Hall of <City> has fallen."
##   - sandbox:       "SIMULATION COMPLETE" (gold) —
##     "<Name> dominated the continent. (Sandbox — you were an observer.)"
##   - Buttons: PLAY AGAIN (re-boots the same mode) / MAIN MENU.
##
## Shown by the world when an end condition fires (see HOOKS). No emoji —
## plain text labels only.


signal play_again_requested
signal main_menu_requested


var _title: Label
var _msg: Label
var _built := false


func _ready() -> void:
	_build()
	visible = false


func _build() -> void:
	_built = true
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# POLISH MODE 2026-10-10 (menu-scroll audit): the end screen content
	# (88px title + message + two 88px buttons) clipped ~25px on the
	# smallest landscape phones in the sandbox case. Wrap it in a
	# vertical-only ScrollContainer capped at 90% of the viewport height
	# so it can never run off-screen; short content keeps the old
	# centered look via the inner vbox's minimum height.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(vp.x * 0.94, 560.0)
	var h: float = vp.y * 0.90
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(w, h)
	center.add_child(scroll)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(w, h)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	scroll.add_child(v)

	_title = Label.new()
	_title.text = "VICTORY"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 88)
	_title.add_theme_color_override("font_color", Color(0.298, 0.686, 0.314))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("shadow_offset_x", 3)
	_title.add_theme_constant_override("shadow_offset_y", 3)
	v.add_child(_title)

	_msg = Label.new()
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", 28)
	_msg.add_theme_color_override("font_color", Color(0.941, 0.902, 0.784))
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_msg)

	var b_again := _btn("PLAY AGAIN", true)
	b_again.pressed.connect(func() -> void: play_again_requested.emit())
	v.add_child(b_again)
	var b_menu := _btn("MAIN MENU", false)
	b_menu.pressed.connect(func() -> void: main_menu_requested.emit())
	v.add_child(b_menu)


func _btn(t: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 88)
	b.add_theme_font_size_override("font_size", 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.239, 0.165, 0.098)
	sb.set_border_width_all(3 if primary else 2)
	sb.border_color = Color(0.788, 0.635, 0.153)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", sb)
	return b


## Show the end screen. kind: "victory" | "defeat" | "sandbox".
func show_end(kind: String, title_override := "", msg_override := "") -> void:
	if not _built:
		_build()
	match kind:
		"sandbox":
			_title.text = "SIMULATION COMPLETE"
			_title.add_theme_color_override("font_color",
				Color(1.0, 0.835, 0.310))
			_msg.text = msg_override
		"defeat":
			_title.text = "DEFEAT"
			_title.add_theme_color_override("font_color",
				Color(0.914, 0.271, 0.376))
			_msg.text = msg_override
		_:
			_title.text = "VICTORY"
			_title.add_theme_color_override("font_color",
				Color(0.298, 0.686, 0.314))
			_msg.text = msg_override
	if title_override != "":
		_title.text = title_override
	visible = true


func hide_end() -> void:
	visible = false
