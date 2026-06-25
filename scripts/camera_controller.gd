extends Camera2D

@export var move_speed := 600.0
@export var zoom_step := 0.1
@export var min_zoom := 0.5
@export var max_zoom := 1.5


func _process(delta: float) -> void:
	var input_direction := Input.get_vector(
		&"camera_left",
		&"camera_right",
		&"camera_up",
		&"camera_down"
	)
	if _selected_villagers_use_stop_key():
		input_direction.y = minf(input_direction.y, 0.0)
	position += input_direction * move_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return

	var mouse_button := event as InputEventMouseButton
	if not mouse_button.pressed:
		return

	var zoom_change := 0.0
	if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_change = zoom_step
	elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_change = -zoom_step
	else:
		return

	var next_zoom := clampf(zoom.x + zoom_change, min_zoom, max_zoom)
	zoom = Vector2.ONE * next_zoom
	get_viewport().set_input_as_handled()


func _selected_villagers_use_stop_key() -> bool:
	if not Input.is_key_pressed(KEY_S):
		return false
	for node in get_tree().get_nodes_in_group(&"selection_managers"):
		if (
			node.has_method("has_selected_villagers")
			and node.has_selected_villagers()
		):
			return true
	return false
