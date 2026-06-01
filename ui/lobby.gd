extends Control

const LEVEL_PATH := "res://levels/main_level.tscn"

# Refs
var _name_edit    : LineEdit
var _avatar_btn   : OptionButton
var _solo_btn     : Button
var _host_btn     : Button
var _mp_toggle    : Button
var _mp_panel     : VBoxContainer
var _server_list  : ItemList
var _ip_edit      : LineEdit
var _join_ip_btn  : Button
var _join_sel_btn : Button
var _refresh_btn  : Button
var _status_lbl   : Label

var _server_data  : Array = []
var _pending_action : String = ""  # "solo" | "host"


func _ready() -> void:
	_build_ui()

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.connected_to_server.connect(_enter_level)
	LanDiscovery.server_found.connect(_on_server_found)
	LanDiscovery.server_lost.connect(_on_server_lost)


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_top = 24
	panel.offset_right = -24
	panel.offset_bottom = -24
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# --- Título ---
	var title := Label.new()
	title.text = "Arquitecto"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# --- Nombre + avatar ---
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	vbox.add_child(row1)

	var nl := Label.new()
	nl.text = "Nombre:"
	row1.add_child(nl)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Tu nombre"
	_name_edit.text = "Jugador"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_name_edit)

	var al := Label.new()
	al.text = "  Avatar:"
	row1.add_child(al)

	_avatar_btn = OptionButton.new()
	_avatar_btn.add_item("Masculino", 0)
	_avatar_btn.add_item("Femenino",  1)
	row1.add_child(_avatar_btn)

	vbox.add_child(HSeparator.new())

	# --- Jugar solo (acción principal) ---
	_solo_btn = Button.new()
	_solo_btn.text = "Entrar a la casa"
	_solo_btn.custom_minimum_size = Vector2(0, 56)
	_solo_btn.add_theme_font_size_override("font_size", 22)
	_solo_btn.pressed.connect(_on_solo_pressed)
	vbox.add_child(_solo_btn)

	# --- Toggle multijugador ---
	_mp_toggle = Button.new()
	_mp_toggle.text = "Multijugador ▾"
	_mp_toggle.toggle_mode = true
	_mp_toggle.pressed.connect(_on_mp_toggle)
	vbox.add_child(_mp_toggle)

	# --- Panel multijugador (oculto por defecto) ---
	_mp_panel = VBoxContainer.new()
	_mp_panel.add_theme_constant_override("separation", 8)
	_mp_panel.visible = false
	vbox.add_child(_mp_panel)

	_host_btn = Button.new()
	_host_btn.text = "Hospedar partida"
	_host_btn.pressed.connect(_on_host_pressed)
	_mp_panel.add_child(_host_btn)

	_mp_panel.add_child(HSeparator.new())

	var join_lbl := Label.new()
	join_lbl.text = "Servidores en la red:"
	_mp_panel.add_child(join_lbl)

	_server_list = ItemList.new()
	_server_list.custom_minimum_size = Vector2(0, 100)
	_mp_panel.add_child(_server_list)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	_mp_panel.add_child(row2)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Buscar"
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	row2.add_child(_refresh_btn)

	_join_sel_btn = Button.new()
	_join_sel_btn.text = "Unirse"
	_join_sel_btn.pressed.connect(_on_join_selected_pressed)
	row2.add_child(_join_sel_btn)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	_mp_panel.add_child(row3)

	var ip_lbl := Label.new()
	ip_lbl.text = "IP:"
	row3.add_child(ip_lbl)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.x.x"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_ip_edit)

	_join_ip_btn = Button.new()
	_join_ip_btn.text = "Conectar"
	_join_ip_btn.pressed.connect(_on_join_ip_pressed)
	row3.add_child(_join_ip_btn)

	# --- Estado ---
	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_color_override("font_color", Color.YELLOW)
	vbox.add_child(_status_lbl)


# --- Acciones ---

func _on_mp_toggle() -> void:
	_mp_panel.visible = _mp_toggle.button_pressed
	_mp_toggle.text = "Multijugador ▴" if _mp_toggle.button_pressed else "Multijugador ▾"
	if _mp_toggle.button_pressed:
		_on_refresh_pressed()
	else:
		LanDiscovery.stop_listening()


func _on_solo_pressed() -> void:
	_pending_action = "solo"
	_pick_house()


func _on_host_pressed() -> void:
	_pending_action = "host"
	_pick_house()


func _pick_house() -> void:
	_set_status("Selecciona un archivo .glb o .gltf…")
	var filters := PackedStringArray(["*.glb,*.gltf ; Modelos 3D (GLTF / GLB)"])
	var err := DisplayServer.file_dialog_show(
		"Selecciona la casa (.glb / .gltf)",
		OS.get_user_data_dir(),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		filters,
		_on_native_file_dialog
	)
	if err != OK:
		# Fallback: diálogo Godot embebido
		_open_embedded_dialog()


func _on_native_file_dialog(status: bool, paths: PackedStringArray, _filter_idx: int) -> void:
	if not status or paths.is_empty():
		_on_house_cancelled()
		return
	_on_house_selected(paths[0])


func _open_embedded_dialog() -> void:
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.filters = PackedStringArray(["*.glb,*.gltf ; Modelos 3D (GLTF / GLB)"])
	dlg.title = "Selecciona la casa (.glb / .gltf)"
	dlg.size = Vector2i(900, 600)
	# Padre = root para que no se libere con el lobby al cambiar escena.
	get_tree().root.add_child(dlg)
	dlg.file_selected.connect(func(p):
		dlg.queue_free()
		_on_house_selected(p)
	)
	dlg.canceled.connect(func():
		dlg.queue_free()
		_on_house_cancelled()
	)
	dlg.popup_centered()


func _on_house_cancelled() -> void:
	_pending_action = ""
	_set_status("Carga cancelada.")


func _on_house_selected(path: String) -> void:
	NetworkManager.house_path = path
	match _pending_action:
		"solo":
			_apply_my_info()
			NetworkManager.start_solo()
			_enter_level()
		"host":
			_apply_my_info()
			_set_status("Iniciando servidor…")
			_disable_buttons()
			# Arrancar LAN ANTES de host() porque host() emite player_connected
			# sincrónicamente y _enter_level cambiará de escena.
			LanDiscovery.start_hosting(_name_edit.text + "'s room")
			var err := NetworkManager.host()
			if err != OK:
				LanDiscovery.stop_hosting()
				_set_status("Error al abrir servidor: %d" % err)
				_enable_buttons()
				return
	_pending_action = ""


func _on_refresh_pressed() -> void:
	_server_data.clear()
	_server_list.clear()
	LanDiscovery.stop_listening()
	LanDiscovery.start_listening()
	_set_status("Buscando servidores…")


func _on_join_selected_pressed() -> void:
	var sel := _server_list.get_selected_items()
	if sel.is_empty():
		_set_status("Selecciona un servidor de la lista.")
		return
	var info : Dictionary = _server_data[sel[0]]
	_do_join(info.ip)


func _on_join_ip_pressed() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip.is_empty():
		_set_status("Introduce una IP.")
		return
	_do_join(ip)


func _do_join(ip: String) -> void:
	_apply_my_info()
	_set_status("Conectando a %s…" % ip)
	_disable_buttons()
	var err := NetworkManager.join(ip)
	if err != OK:
		_set_status("Error al conectar: %d" % err)
		_enable_buttons()


func _apply_my_info() -> void:
	NetworkManager.my_info = {
		name   = _name_edit.text.strip_edges().left(24) if _name_edit.text.strip_edges() != "" else "Jugador",
		avatar = "male" if _avatar_btn.selected == 0 else "female",
	}


func _set_status(msg: String) -> void:
	_status_lbl.text = msg


func _disable_buttons() -> void:
	_solo_btn.disabled     = true
	_host_btn.disabled     = true
	_join_ip_btn.disabled  = true
	_join_sel_btn.disabled = true


func _enable_buttons() -> void:
	_solo_btn.disabled     = false
	_host_btn.disabled     = false
	_join_ip_btn.disabled  = false
	_join_sel_btn.disabled = false


# --- Señales de red ---

func _on_player_connected(id: int, _info: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server() and id == 1:
		_enter_level()


func _enter_level() -> void:
	# Solo paramos browsing (listening). El hosting LAN sigue activo si somos host.
	LanDiscovery.stop_listening()
	get_tree().change_scene_to_file(LEVEL_PATH)


func _on_connection_failed() -> void:
	_set_status("No se pudo conectar.")
	_enable_buttons()


func _on_server_disconnected() -> void:
	_set_status("Desconectado del servidor.")
	_enable_buttons()


# --- LAN Discovery ---

func _on_server_found(info: Dictionary) -> void:
	for i in _server_data.size():
		if _server_data[i].ip == info.ip:
			_server_data[i] = info
			_server_list.set_item_text(i, _format_server(info))
			return
	_server_data.append(info)
	_server_list.add_item(_format_server(info))


func _on_server_lost(ip: String) -> void:
	for i in _server_data.size():
		if _server_data[i].ip == ip:
			_server_data.remove_at(i)
			_server_list.remove_item(i)
			return


func _format_server(info: Dictionary) -> String:
	return "%s  (%s)  %d/%d" % [
		info.get("name",    "?"),
		info.get("ip",      "?"),
		info.get("players", 0),
		info.get("max_players", 6),
	]
