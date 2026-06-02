extends CanvasLayer

var _players_box   : VBoxContainer
var _status_lbl    : Label
var _scale_slider  : HSlider
var _scale_lbl     : Label
var _scale_panel   : PanelContainer
var _climb_prompt  : Label
var _scale_hold_timer : float = 0.0
var _scale_hold_delay : float = 0.15


func _ready() -> void:
	_build_ui()
	NetworkManager.player_connected.connect(_rebuild_player_list)
	NetworkManager.player_disconnected.connect(_rebuild_player_list.unbind(1))
	_rebuild_player_list(0, {})
	_refresh_scale_panel_visibility()

	# Botón ESC para salir
	set_process_unhandled_input(true)
	set_process(true)


func _build_ui() -> void:
	# Fondo semitransparente arriba a la derecha
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.custom_minimum_size = Vector2(200, 0)
	panel.position = Vector2(-210, 8)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Jugadores"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	_players_box = VBoxContainer.new()
	vbox.add_child(_players_box)

	# Status / hint abajo
	_status_lbl = Label.new()
	_status_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status_lbl.position = Vector2(8, -32)
	_status_lbl.text = "ESC = liberar ratón  |  Tab = salir"
	_status_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	add_child(_status_lbl)

	# Panel de escala de la casa (solo autoridad / solo / host)
	_scale_panel = PanelContainer.new()
	_scale_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_scale_panel.position = Vector2(-280, -96)
	_scale_panel.custom_minimum_size = Vector2(270, 0)
	add_child(_scale_panel)

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	_scale_panel.add_child(sv)

	var title2 := Label.new()
	title2.text = "Escala de la casa"
	title2.add_theme_font_size_override("font_size", 13)
	sv.add_child(title2)

	_scale_lbl = Label.new()
	_scale_lbl.text = "x 1.000"
	_scale_lbl.add_theme_font_size_override("font_size", 12)
	sv.add_child(_scale_lbl)

	_scale_slider = HSlider.new()
	_scale_slider.min_value = -3.0  # log10 → 0.001
	_scale_slider.max_value =  2.0  # log10 → 100
	_scale_slider.step      =  0.01
	_scale_slider.value     =  0.0  # 10^0 = 1.0
	_scale_slider.custom_minimum_size = Vector2(250, 0)
	_scale_slider.focus_mode = Control.FOCUS_NONE
	_scale_slider.value_changed.connect(_on_scale_changed)
	sv.add_child(_scale_slider)

	var reset_btn := Button.new()
	reset_btn.text = "Reset (x1)"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(func(): _scale_slider.value = 0.0)
	sv.add_child(reset_btn)

	# Prompt centrado para climbing
	_climb_prompt = Label.new()
	_climb_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_climb_prompt.text = "Pulsa E para escalar"
	_climb_prompt.add_theme_font_size_override("font_size", 18)
	_climb_prompt.add_theme_color_override("font_color", Color(1, 1, 1))
	_climb_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_climb_prompt.add_theme_constant_override("outline_size", 6)
	_climb_prompt.position = Vector2(-80, 60)
	_climb_prompt.visible = false
	add_child(_climb_prompt)


func _refresh_scale_panel_visibility() -> void:
	# Solo el host (o solo) puede cambiar la escala; clientes no.
	var is_authority := multiplayer.multiplayer_peer == null or multiplayer.is_server()
	_scale_panel.visible = is_authority and _get_level() != null and _get_level().get_house() != null


func _on_scale_changed(v: float) -> void:
	var factor := pow(10.0, v)
	_scale_lbl.text = "x %.3f" % factor
	var lvl := _get_level()
	if lvl != null:
		lvl.set_house_scale(factor)


func _get_level() -> Node:
	var p := get_parent()
	if p != null and p.has_method("set_house_scale"):
		return p
	return null


func _rebuild_player_list(_id = 0, _info = {}) -> void:
	for c in _players_box.get_children():
		c.queue_free()
	for id in NetworkManager.players:
		var info : Dictionary = NetworkManager.players[id]
		var lbl  := Label.new()
		var my_id : int = 1 if multiplayer.multiplayer_peer == null else multiplayer.get_unique_id()
		var own  : bool = (int(id) == my_id)
		lbl.text = ("▶ " if own else "  ") + info.get("name", "?")
		lbl.add_theme_font_size_override("font_size", 13)
		_players_box.add_child(lbl)


func _process(delta: float) -> void:
	if not is_inside_tree() or not _scale_panel.visible:
		return

	var plus_pressed := Input.is_key_pressed(KEY_PLUS) or Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD)
	var minus_pressed := Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT)

	if plus_pressed or minus_pressed:
		_scale_hold_timer += delta
		if _scale_hold_timer >= _scale_hold_delay:
			_scale_hold_timer -= _scale_hold_delay
			var amount := 0.05 if plus_pressed else -0.05
			_nudge_scale(amount)
	else:
		_scale_hold_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if event.is_action_pressed("ui_focus_next"):  # Tab
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		NetworkManager.disconnect_game()
		get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _nudge_scale(delta: float) -> void:
	if _scale_slider == null or not _scale_panel.visible:
		return
	_scale_slider.value = clamp(_scale_slider.value + delta, _scale_slider.min_value, _scale_slider.max_value)


func show_climb_prompt(on: bool) -> void:
	if _climb_prompt != null:
		_climb_prompt.visible = on
