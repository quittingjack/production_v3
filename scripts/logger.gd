extends Node

const LEVELS := ["INFO", "WARN", "ERROR"]
const LEVEL_RANK := {
	"INFO": 0,
	"WARN": 1,
	"ERROR": 2,
}
const MAX_ENTRIES := 200

var minimum_level := "INFO"
var show_node := true
var show_file := true
var show_function := true

var _entries: Array[Dictionary] = []
var _canvas_layer: CanvasLayer
var _panel: PanelContainer
var _log_text: RichTextLabel
var _level_option: OptionButton
var _node_check: CheckBox
var _file_check: CheckBox
var _function_check: CheckBox


func _ready() -> void:
	_build_ui()


func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if (
		key_event
		and key_event.pressed
		and not key_event.echo
		and key_event.keycode == KEY_L
	):
		toggle_ui()
		get_viewport().set_input_as_handled()


func log(node: Node, function_name: String, action: String, params: Dictionary = {}) -> void:
	_emit("INFO", node, function_name, action, params)


func warn(node: Node, function_name: String, action: String, params: Dictionary = {}) -> void:
	var entry := _make_entry("WARN", node, function_name, action, params)
	if entry.is_empty():
		return
	_add_entry(entry)
	if not _should_show_level("WARN"):
		return
	var message := _format_entry(entry)
	push_warning(message)


func error(node: Node, function_name: String, action: String, params: Dictionary = {}) -> void:
	var entry := _make_entry("ERROR", node, function_name, action, params)
	if entry.is_empty():
		return
	_add_entry(entry)
	if not _should_show_level("ERROR"):
		return
	var message := _format_entry(entry)
	push_error(message)


func toggle_ui() -> void:
	if not _panel:
		return
	_panel.visible = not _panel.visible


func set_ui_visible(is_visible: bool) -> void:
	if not _panel:
		return
	_panel.visible = is_visible


func _emit(level: String, node: Node, function_name: String, action: String, params: Dictionary = {}) -> void:
	var entry := _make_entry(level, node, function_name, action, params)
	if entry.is_empty():
		return
	_add_entry(entry)
	if not _should_show_level(level):
		return
	var message := _format_entry(entry)
	print(message)


func _make_entry(level: String, node: Node, function_name: String, action: String, params: Dictionary = {}) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}

	var file_path := ""
	var script: Script = node.get_script() as Script
	if script and script.resource_path != "":
		file_path = str(script.resource_path)

	return {
		"level": level,
		"node": node.name,
		"file": file_path,
		"function": function_name,
		"action": action,
		"params": params.duplicate(true),
	}


func _add_entry(entry: Dictionary) -> void:
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	_refresh_log_text()


func _format_entry(entry: Dictionary) -> String:
	var parts: Array[String] = ["[%s]" % [entry.get("level", "INFO")]]
	if show_node:
		parts.append("[Node: %s]" % [entry.get("node", "")])
	if show_file:
		parts.append("[File: %s]" % [entry.get("file", "")])
	if show_function:
		parts.append("[Fn: %s]" % [entry.get("function", "")])

	var params_text := ""
	var params: Dictionary = entry.get("params", {})
	if not params.is_empty():
		params_text = " | params: %s" % [params]

	return "%s %s%s" % [
		" ".join(parts),
		entry.get("action", ""),
		params_text,
	]


func _should_show_level(level: String) -> bool:
	return LEVEL_RANK.get(level, 0) >= LEVEL_RANK.get(minimum_level, 0)


func _build_ui() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "LoggerOverlay"
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	_panel = PanelContainer.new()
	_panel.name = "LoggerPanel"
	_panel.visible = false
	_panel.offset_left = 18.0
	_panel.offset_top = 82.0
	_panel.offset_right = 720.0
	_panel.offset_bottom = 500.0
	_canvas_layer.add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.055, 0.075, 0.94)
	panel_style.border_color = Color(0.35, 0.78, 1.0, 0.75)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 14
	panel_style.content_margin_top = 12
	panel_style.content_margin_right = 14
	panel_style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", panel_style)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	_panel.add_child(content)

	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("separation", 10)
	content.add_child(title_row)

	var title := Label.new()
	title.text = "Logger"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	title_row.add_child(title)

	var close_button := Button.new()
	close_button.text = "L"
	close_button.tooltip_text = "Toggle logger"
	close_button.custom_minimum_size = Vector2(44, 30)
	close_button.pressed.connect(toggle_ui)
	title_row.add_child(close_button)

	var controls := HBoxContainer.new()
	controls.name = "Controls"
	controls.add_theme_constant_override("separation", 10)
	content.add_child(controls)

	var level_label := Label.new()
	level_label.text = "Level"
	level_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8, 1.0))
	controls.add_child(level_label)

	_level_option = OptionButton.new()
	for index in LEVELS.size():
		_level_option.add_item("%s+" % [LEVELS[index]], index)
	_level_option.select(0)
	_level_option.item_selected.connect(_on_level_selected)
	controls.add_child(_level_option)

	_node_check = _make_check_box("Node", show_node)
	_node_check.toggled.connect(_on_show_node_toggled)
	controls.add_child(_node_check)

	_file_check = _make_check_box("File", show_file)
	_file_check.toggled.connect(_on_show_file_toggled)
	controls.add_child(_file_check)

	_function_check = _make_check_box("Fn", show_function)
	_function_check.toggled.connect(_on_show_function_toggled)
	controls.add_child(_function_check)

	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(_clear_entries)
	controls.add_child(clear_button)

	_log_text = RichTextLabel.new()
	_log_text.name = "LogText"
	_log_text.bbcode_enabled = false
	_log_text.scroll_following = true
	_log_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_text.custom_minimum_size = Vector2(660, 320)
	_log_text.add_theme_font_size_override("normal_font_size", 14)
	_log_text.add_theme_color_override("default_color", Color(0.9, 0.95, 1.0, 1.0))
	content.add_child(_log_text)


func _make_check_box(label: String, is_pressed: bool) -> CheckBox:
	var check_box := CheckBox.new()
	check_box.text = label
	check_box.button_pressed = is_pressed
	return check_box


func _on_level_selected(index: int) -> void:
	if index < 0 or index >= LEVELS.size():
		return
	minimum_level = LEVELS[index]
	_refresh_log_text()


func _on_show_node_toggled(is_pressed: bool) -> void:
	show_node = is_pressed
	_refresh_log_text()


func _on_show_file_toggled(is_pressed: bool) -> void:
	show_file = is_pressed
	_refresh_log_text()


func _on_show_function_toggled(is_pressed: bool) -> void:
	show_function = is_pressed
	_refresh_log_text()


func _clear_entries() -> void:
	_entries.clear()
	_refresh_log_text()


func _refresh_log_text() -> void:
	if not _log_text:
		return

	var lines: Array[String] = []
	for entry in _entries:
		if _should_show_level(entry.get("level", "INFO")):
			lines.append(_format_entry(entry))
	_log_text.text = "\n".join(lines)
