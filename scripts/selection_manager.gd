extends Node2D

@export var drag_threshold := 8.0

@onready var selection_fill: Polygon2D = $SelectionFill
@onready var selection_border: Line2D = $SelectionBorder

var _selected_villagers: Array[Villager] = []
var _left_button_down := false
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO


func _ready() -> void:
	_set_selection_box_visible(false)


func _unhandled_input(event: InputEvent) -> void:
	if _is_building_placement_active():
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		var world_position := _screen_to_world(mouse_button.position)

		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				_begin_left_action(world_position)
			else:
				_finish_left_action(world_position)
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			_command_selection_at(world_position)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _left_button_down:
		var mouse_motion := event as InputEventMouseMotion
		_update_left_action(_screen_to_world(mouse_motion.position))
		get_viewport().set_input_as_handled()


func _begin_left_action(world_position: Vector2) -> void:
	_left_button_down = true
	_is_dragging = false
	_drag_start = world_position
	_drag_current = world_position
	_set_selection_box_visible(false)


func _update_left_action(world_position: Vector2) -> void:
	_drag_current = world_position
	if not _is_dragging and _drag_start.distance_to(_drag_current) >= drag_threshold:
		_is_dragging = true
		_set_selection_box_visible(true)

	if _is_dragging:
		_update_selection_box()


func _finish_left_action(world_position: Vector2) -> void:
	if not _left_button_down:
		return

	_drag_current = world_position
	if _is_dragging:
		_select_villagers_in(_selection_rect())
	else:
		var clicked_villager := _find_villager_at(world_position)
		if clicked_villager:
			_select_only(clicked_villager)
		else:
			_clear_selection()

	_left_button_down = false
	_is_dragging = false
	_set_selection_box_visible(false)


func _find_villager_at(world_position: Vector2) -> Villager:
	var closest_villager: Villager = null
	var closest_distance := INF

	for node in get_tree().get_nodes_in_group(&"villagers"):
		var villager := node as Villager
		if villager and villager.contains_point(world_position):
			var distance := villager.global_position.distance_squared_to(world_position)
			if distance < closest_distance:
				closest_villager = villager
				closest_distance = distance

	return closest_villager


func _select_only(villager: Villager) -> void:
	_clear_selection()
	_selected_villagers.append(villager)
	villager.set_selected(true)


func _select_villagers_in(selection_rect: Rect2) -> void:
	_clear_selection()
	for node in get_tree().get_nodes_in_group(&"villagers"):
		var villager := node as Villager
		if villager and selection_rect.has_point(villager.global_position):
			_selected_villagers.append(villager)
			villager.set_selected(true)


func _clear_selection() -> void:
	for villager in _selected_villagers:
		if is_instance_valid(villager):
			villager.set_selected(false)
	_selected_villagers.clear()


func _move_selection_to(world_position: Vector2) -> void:
	for villager in _selected_villagers:
		if is_instance_valid(villager):
			villager.move_to(world_position)


func _command_selection_at(world_position: Vector2) -> void:
	var resource_node := _find_resource_at(world_position)
	if resource_node:
		for villager in _selected_villagers:
			if is_instance_valid(villager):
				villager.gather_from(resource_node)
		return

	_move_selection_to(world_position)


func _find_resource_at(world_position: Vector2) -> ResourceNode:
	var closest_resource: ResourceNode = null
	var closest_distance := INF

	for node in get_tree().get_nodes_in_group(&"resources"):
		var resource_node := node as ResourceNode
		if resource_node and resource_node.contains_point(world_position):
			var distance := resource_node.global_position.distance_squared_to(world_position)
			if distance < closest_distance:
				closest_resource = resource_node
				closest_distance = distance

	return closest_resource


func _selection_rect() -> Rect2:
	return Rect2(_drag_start, _drag_current - _drag_start).abs()


func _update_selection_box() -> void:
	var rect := _selection_rect()
	var top_left := to_local(rect.position)
	var top_right := to_local(Vector2(rect.end.x, rect.position.y))
	var bottom_right := to_local(rect.end)
	var bottom_left := to_local(Vector2(rect.position.x, rect.end.y))

	selection_fill.polygon = PackedVector2Array([
		top_left,
		top_right,
		bottom_right,
		bottom_left,
	])
	selection_border.points = PackedVector2Array([
		top_left,
		top_right,
		bottom_right,
		bottom_left,
		top_left,
	])


func _set_selection_box_visible(value: bool) -> void:
	selection_fill.visible = value
	selection_border.visible = value


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position


func _is_building_placement_active() -> bool:
	var managers := get_tree().get_nodes_in_group(&"building_managers")
	if managers.is_empty():
		return false
	return managers[0].is_placing()
