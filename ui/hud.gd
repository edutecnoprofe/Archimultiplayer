extends CanvasLayer

var _players_box : VBoxContainer
var _status_lbl  : Label


func _ready() -> void:
	_build_ui()
	NetworkManager.player_connected.connect(_rebuild_player_list)
	NetworkManager.player_disconnected.connect(_rebuild_player_list.unbind(1))
	_rebuild_player_list(0, {})

	# Botón ESC para salir
	set_process_unhandled_input(true)


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


func _rebuild_player_list(_id = 0, _info = {}) -> void:
	for c in _players_box.get_children():
		c.queue_free()
	for id in NetworkManager.players:
		var info : Dictionary = NetworkManager.players[id]
		var lbl  := Label.new()
		var own  := (id == multiplayer.get_unique_id())
		lbl.text = ("▶ " if own else "  ") + info.get("name", "?")
		lbl.add_theme_font_size_override("font_size", 13)
		_players_box.add_child(lbl)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next"):  # Tab
		NetworkManager.disconnect_game()
		get_tree().change_scene_to_file("res://ui/lobby.tscn")
