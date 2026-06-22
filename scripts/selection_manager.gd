extends Node2D

@export var drag_threshold := 8.0
@export var formation_spacing := 32.0

@onready var selection_fill: Polygon2D = $SelectionFill
@onready var selection_border: Line2D = $SelectionBorder
@onready var haul_route_preview: Line2D = $HaulRoutePreview
@onready var haul_planning_label: Label = $"../Interface/HaulPlanningLabel"
@onready var haul_amount_cursor_label: Label = $"../Interface/HaulAmountCursorLabel"

var _selected_villagers: Array[Villager] = []
var _left_button_down := false
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
var _hovered_interaction_host: InteractionSlotHost

var _is_haul_planning := false
var _haul_villagers: Array[Villager] = []
var _haul_source: Building
var _haul_waypoints: Array[Vector2] = []
var _haul_amount_per_trip := 1
var _haul_max_amount := 1
const HAUL_CURSOR_LABEL_OFFSET := Vector2(16.0, 20.0)


func _ready() -> void:
	add_to_group(&"selection_managers")
	_set_selection_box_visible(false)
	haul_route_preview.visible = false
	haul_planning_label.visible = false
	haul_amount_cursor_label.visible = false


func _process(_delta: float) -> void:
	var mouse_position := get_viewport().get_mouse_position()
	var world_position := _screen_to_world(get_viewport().get_mouse_position())
	if _is_haul_planning:
		_update_haul_preview(world_position)
		_update_haul_amount_cursor_label(mouse_position)
		_set_hovered_interaction_host(_find_building_at(world_position))
		return

	if _is_building_placement_active():
		_set_hovered_interaction_host(null)
		return

	_update_hovered_interaction_host(world_position)


func _input(event: InputEvent) -> void:
	if not _is_haul_planning:
		return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		_cancel_haul_planning()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _is_haul_planning:
		_handle_haul_planning_input(event)
		return

	if _is_building_placement_active():
		_set_hovered_interaction_host(null)
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


func begin_haul_planning() -> void:
	if _is_building_placement_active():
		return

	_haul_villagers.clear()
	_haul_max_amount = 0
	for villager in _selected_villagers:
		if not is_instance_valid(villager):
			continue
		_haul_villagers.append(villager)
		if _haul_max_amount == 0:
			_haul_max_amount = villager.backpack_capacity
		else:
			_haul_max_amount = mini(
				_haul_max_amount,
				villager.backpack_capacity
			)

	if _haul_villagers.is_empty():
		return

	get_viewport().gui_release_focus()
	_is_haul_planning = true
	_haul_source = null
	_haul_waypoints.clear()
	_haul_amount_per_trip = clampi(1, 1, maxi(_haul_max_amount, 1))
	haul_route_preview.clear_points()
	haul_route_preview.visible = true
	haul_planning_label.visible = true
	haul_amount_cursor_label.visible = true
	_update_haul_planning_label()
	_update_haul_amount_cursor_label(get_viewport().get_mouse_position())
	_set_hovered_interaction_host(null)


func is_haul_planning() -> bool:
	return _is_haul_planning


func get_selected_villagers() -> Array[Villager]:
	var villagers: Array[Villager] = []
	for villager in _selected_villagers:
		if is_instance_valid(villager):
			villagers.append(villager)
	return villagers


func get_single_selected_villager() -> Villager:
	var villagers := get_selected_villagers()
	if villagers.size() != 1:
		return null
	return villagers[0]


func _handle_haul_planning_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if (
			key_event.pressed
			and not key_event.echo
			and key_event.keycode == KEY_B
		):
			get_viewport().set_input_as_handled()
			return

	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_haul_amount_per_trip = mini(
			_haul_amount_per_trip + 1,
			maxi(_haul_max_amount, 1)
		)
		_update_haul_planning_label()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_haul_amount_per_trip = maxi(_haul_amount_per_trip - 1, 1)
		_update_haul_planning_label()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if not _haul_waypoints.is_empty():
			_haul_waypoints.pop_back()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_add_haul_planning_point(_screen_to_world(mouse_event.position))
	else:
		return

	get_viewport().set_input_as_handled()


func _add_haul_planning_point(world_position: Vector2) -> void:
	var building := _find_building_at(world_position)
	if not is_instance_valid(_haul_source):
		if not building:
			return
		var output_type := building.get_output_resource_type()
		if output_type == &"":
			return
		_haul_source = building
		_update_haul_planning_label()
		return

	if building:
		if building == _haul_source:
			return
		var resource_type := _haul_source.get_output_resource_type()
		if not building.accepts_resource(resource_type):
			return
		_finish_haul_planning(building)
		return

	_haul_waypoints.append(world_position)


func _finish_haul_planning(destination: Building) -> void:
	var assigned_villagers: Array[Villager] = []
	for villager in _haul_villagers:
		if is_instance_valid(villager):
			assigned_villagers.append(villager)

	for villager in assigned_villagers:
		villager.start_haul_job(
			_haul_source,
			destination,
			_haul_waypoints,
			_haul_amount_per_trip
		)

	_cancel_haul_planning()


func _cancel_haul_planning() -> void:
	_is_haul_planning = false
	_haul_villagers.clear()
	_haul_source = null
	_haul_waypoints.clear()
	haul_route_preview.clear_points()
	haul_route_preview.visible = false
	haul_planning_label.visible = false
	haul_amount_cursor_label.visible = false
	_set_hovered_interaction_host(null)


func _update_haul_preview(mouse_world_position: Vector2) -> void:
	haul_route_preview.clear_points()
	if not is_instance_valid(_haul_source):
		return

	haul_route_preview.add_point(to_local(_haul_source.global_position))
	for waypoint in _haul_waypoints:
		haul_route_preview.add_point(to_local(waypoint))
	haul_route_preview.add_point(to_local(mouse_world_position))


func _update_haul_planning_label() -> void:
	if not is_instance_valid(_haul_source):
		haul_planning_label.text = (
			"搬運規劃：左鍵選擇起點建築\n"
			+ "滾輪調整每人載量：%d　Esc 取消"
			% _haul_amount_per_trip
		)
		return

	haul_planning_label.text = (
		"搬運規劃：%s × %d／人／趟\n"
		+ "左鍵空地新增中間點，左鍵相容建築完成\n"
		+ "右鍵撤銷中間點　Esc 取消"
	) % [
		String(_haul_source.get_output_resource_type()),
		_haul_amount_per_trip,
	]
	_update_haul_amount_cursor_text()


func _update_haul_amount_cursor_label(mouse_position: Vector2) -> void:
	if not _is_haul_planning:
		return

	haul_amount_cursor_label.position = mouse_position + HAUL_CURSOR_LABEL_OFFSET
	_update_haul_amount_cursor_text()


func _update_haul_amount_cursor_text() -> void:
	if not _is_haul_planning:
		return

	if not is_instance_valid(_haul_source):
		haul_amount_cursor_label.text = "x%d/人" % _haul_amount_per_trip
		return

	haul_amount_cursor_label.text = "%s x%d" % [
		String(_haul_source.get_output_resource_type()),
		_haul_amount_per_trip,
	]


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
	var villagers := get_selected_villagers()
	if villagers.is_empty():
		return

	villagers.sort_custom(_sort_villagers_by_position)
	var formation_positions := _get_formation_positions(
		world_position,
		villagers.size()
	)
	for villager_index in villagers.size():
		villagers[villager_index].move_to(
			formation_positions[villager_index]
		)


func _sort_villagers_by_position(
	first_villager: Villager,
	second_villager: Villager
) -> bool:
	if not is_equal_approx(
		first_villager.global_position.y,
		second_villager.global_position.y
	):
		return first_villager.global_position.y < second_villager.global_position.y
	if not is_equal_approx(
		first_villager.global_position.x,
		second_villager.global_position.x
	):
		return first_villager.global_position.x < second_villager.global_position.x
	return first_villager.get_instance_id() < second_villager.get_instance_id()


func _get_formation_positions(
	center_position: Vector2,
	villager_count: int
) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if villager_count <= 0:
		return positions
	if villager_count == 1:
		positions.append(center_position)
		return positions

	var column_count := ceili(sqrt(float(villager_count)))
	var row_count := ceili(float(villager_count) / column_count)
	var formation_height := (row_count - 1) * formation_spacing

	for row_index in row_count:
		var villagers_before_row := row_index * column_count
		var villagers_in_row := mini(
			column_count,
			villager_count - villagers_before_row
		)
		var row_width := (villagers_in_row - 1) * formation_spacing
		for column_index in villagers_in_row:
			positions.append(
				center_position
				+ Vector2(
					column_index * formation_spacing - row_width * 0.5,
					row_index * formation_spacing - formation_height * 0.5
				)
			)

	return positions


func _command_selection_at(world_position: Vector2) -> void:
	var resource_node := _find_resource_at(world_position)
	if resource_node:
		for villager in _selected_villagers:
			if is_instance_valid(villager):
				villager.gather_from(resource_node)
		return

	var building := _find_building_at(world_position)
	if building:
		for villager in _selected_villagers:
			if is_instance_valid(villager):
				villager.move_to(building.global_position)
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


func _find_building_at(world_position: Vector2) -> Building:
	var closest_building: Building = null
	var closest_distance := INF

	for node in get_tree().get_nodes_in_group(&"buildings"):
		var building := node as Building
		if building and building.contains_point(world_position):
			var distance := building.global_position.distance_squared_to(world_position)
			if distance < closest_distance:
				closest_building = building
				closest_distance = distance

	return closest_building


func _update_hovered_interaction_host(world_position: Vector2) -> void:
	var hovered_host: InteractionSlotHost = _find_resource_at(world_position)
	if not hovered_host:
		hovered_host = _find_building_at(world_position)
	_set_hovered_interaction_host(hovered_host)


func _set_hovered_interaction_host(host: InteractionSlotHost) -> void:
	if (
		is_instance_valid(_hovered_interaction_host)
		and _hovered_interaction_host != host
	):
		_hovered_interaction_host.set_hovered(false)

	_hovered_interaction_host = host
	if is_instance_valid(_hovered_interaction_host):
		_hovered_interaction_host.set_hovered(true)


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
