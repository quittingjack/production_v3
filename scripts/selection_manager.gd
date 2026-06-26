extends Node2D

@export var drag_threshold := 8.0
@export var right_hold_threshold := 0.35
@export var right_drag_threshold := 8.0
@export var formation_spacing := 32.0

@onready var selection_fill: Polygon2D = $SelectionFill
@onready var selection_border: Line2D = $SelectionBorder
@onready var haul_route_preview: Line2D = $HaulRoutePreview
@onready var haul_planning_label: Label = $"../Interface/HaulPlanningLabel"

var _selected_villagers: Array[Villager] = []
var _left_button_down := false
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
var _hovered_interaction_host: Node

var _is_construction_planning := false
var _construction_villagers: Array[Villager] = []
var _construction_source: Building
var _construction_waypoints: Array[Vector2] = []
var _is_quick_haul_planning := false
var _quick_haul_villagers: Array[Villager] = []
var _quick_haul_source: Building
var _is_right_action_pending := false
var _right_action_source: Building
var _right_action_world_position := Vector2.ZERO
var _right_action_screen_position := Vector2.ZERO
var _right_action_elapsed := 0.0


func _ready() -> void:
	add_to_group(&"selection_managers")
	_set_selection_box_visible(false)
	haul_route_preview.visible = false
	haul_planning_label.visible = false


func _process(delta: float) -> void:
	_update_pending_right_action(delta)
	var world_position := _screen_to_world(get_viewport().get_mouse_position())
	if _is_demolition_active():
		_set_hovered_interaction_host(
			_find_demolishable_building_at(world_position)
		)
		return

	if _is_construction_planning or _is_quick_haul_planning:
		_update_haul_preview(world_position)
		_set_hovered_interaction_host(_find_building_at(world_position))
		return

	if _is_building_placement_active():
		_set_hovered_interaction_host(null)
		return

	_update_hovered_interaction_host(world_position)


func _input(event: InputEvent) -> void:
	if _is_right_action_pending:
		if event is InputEventMouseMotion:
			_update_pending_right_drag(
				(event as InputEventMouseMotion).position
			)
			get_viewport().set_input_as_handled()
			return
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_RIGHT
			and not event.pressed
		):
			_finish_pending_right_action(event as InputEventMouseButton)
			get_viewport().set_input_as_handled()
			return
		if (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and event.keycode == KEY_ESCAPE
		):
			_cancel_pending_right_action()
			get_viewport().set_input_as_handled()
			return

	if (
		_is_quick_haul_planning
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and not event.pressed
	):
		_handle_quick_haul_input(event)
		return

	if not _is_construction_planning and not _is_quick_haul_planning:
		return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		if _is_quick_haul_planning:
			_cancel_quick_haul_planning()
		else:
			_cancel_construction_planning()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _handle_stop_input(event):
		return

	if _is_demolition_active():
		_handle_demolition_input(event)
		return

	if _is_construction_planning:
		_handle_construction_planning_input(event)
		return
	if _is_quick_haul_planning:
		_handle_quick_haul_input(event)
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
		elif mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_button.pressed:
				_command_selection_at(
					world_position,
					mouse_button.shift_pressed,
					mouse_button.ctrl_pressed
				)
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _left_button_down:
		var mouse_motion := event as InputEventMouseMotion
		_update_left_action(_screen_to_world(mouse_motion.position))
		get_viewport().set_input_as_handled()


func begin_construction_planning() -> void:
	return


func _begin_construction_planning() -> void:
	return
	if _is_building_placement_active():
		return

	_construction_villagers.clear()
	for villager in _selected_villagers:
		if not is_instance_valid(villager):
			continue
		_construction_villagers.append(villager)

	if _construction_villagers.is_empty():
		return

	get_viewport().gui_release_focus()
	_is_construction_planning = true
	_construction_source = null
	_construction_waypoints.clear()
	haul_route_preview.clear_points()
	haul_route_preview.visible = true
	haul_planning_label.visible = true
	_update_construction_planning_label()
	_set_hovered_interaction_host(null)


func is_construction_planning() -> bool:
	return _is_construction_planning


func is_command_planning() -> bool:
	return _is_construction_planning or _is_quick_haul_planning


func cancel_command_planning() -> void:
	_cancel_pending_right_action()
	if _is_construction_planning:
		_cancel_construction_planning()
	if _is_quick_haul_planning:
		_cancel_quick_haul_planning()


func get_selected_villagers() -> Array[Villager]:
	var villagers: Array[Villager] = []
	for villager in _selected_villagers:
		if is_instance_valid(villager):
			villagers.append(villager)
	return villagers


func has_selected_villagers() -> bool:
	return not get_selected_villagers().is_empty()


func get_single_selected_villager() -> Villager:
	var villagers := get_selected_villagers()
	if villagers.size() != 1:
		return null
	return villagers[0]


func _handle_construction_planning_input(event: InputEvent) -> void:
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

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if not _construction_waypoints.is_empty():
			_construction_waypoints.pop_back()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_add_construction_planning_point(
			_screen_to_world(mouse_event.position),
			mouse_event.shift_pressed
		)
	else:
		return

	get_viewport().set_input_as_handled()


func _add_construction_planning_point(
	world_position: Vector2,
	queue_work := false
) -> void:
	var building := _find_building_at(world_position)
	if not is_instance_valid(_construction_source):
		if not building:
			return
		var output_type := building.get_output_resource_type()
		if output_type == &"":
			return
		_construction_source = building
		_update_construction_planning_label()
		return

	if building:
		if building == _construction_source:
			return
		if building is not ConstructionSite:
			return
		var site := building as ConstructionSite
		if not site.accepts_resource(
			_construction_source.get_output_resource_type()
		):
			return
		_finish_construction_planning(site, queue_work)
		return

	_construction_waypoints.append(world_position)


func _finish_construction_planning(
	site: ConstructionSite,
	queue_work := false
) -> void:
	var assigned_villagers: Array[Villager] = []
	for villager in _construction_villagers:
		if is_instance_valid(villager):
			assigned_villagers.append(villager)

	_start_construction_job(
		assigned_villagers,
		_construction_source,
		site,
		_construction_waypoints,
		queue_work
	)
	_cancel_construction_planning()


func _start_construction_job(
	villagers: Array[Villager],
	source: Building,
	site: ConstructionSite,
	waypoints: Array[Vector2],
	queue_work := false
) -> void:
	if (
		villagers.is_empty()
		or not is_instance_valid(source)
		or not is_instance_valid(site)
	):
		return

	var job := ConstructionJob.new(source, site)
	if not job.is_valid():
		return

	var remaining_capacity := job.get_missing_amount()
	for villager in villagers:
		if not is_instance_valid(villager):
			continue
		var should_haul := remaining_capacity > 0
		villager.start_construction_job(
			job,
			waypoints,
			should_haul,
			queue_work
		)
		if should_haul:
			remaining_capacity = maxi(
				remaining_capacity - maxi(villager.backpack_capacity, 1),
				0
			)


func _cancel_construction_planning() -> void:
	_is_construction_planning = false
	_construction_villagers.clear()
	_construction_source = null
	_construction_waypoints.clear()
	haul_route_preview.clear_points()
	haul_route_preview.visible = false
	haul_planning_label.visible = false
	_set_hovered_interaction_host(null)


func _update_haul_preview(mouse_world_position: Vector2) -> void:
	haul_route_preview.clear_points()
	var source := (
		_quick_haul_source
		if _is_quick_haul_planning
		else _construction_source
	)
	if not is_instance_valid(source):
		return

	haul_route_preview.add_point(to_local(source.global_position))
	if _is_construction_planning:
		for waypoint in _construction_waypoints:
			haul_route_preview.add_point(to_local(waypoint))
	haul_route_preview.add_point(to_local(mouse_world_position))


func _update_construction_planning_label() -> void:
	if not is_instance_valid(_construction_source):
		haul_planning_label.text = (
			"建造規劃：左鍵選擇建材起點\n"
			+ "Esc 取消"
		)
		return

	haul_planning_label.text = (
		"建造規劃：搬運 %s\n"
		+ "左鍵空地新增中間點，左鍵建築預定地完成\n"
		+ "完成時按住 Shift 可加入排程\n"
		+ "右鍵撤銷中間點　Esc 取消"
	) % [
		String(_construction_source.get_output_resource_type()),
	]


func _try_begin_pending_right_action(
	world_position: Vector2,
	screen_position: Vector2
) -> bool:
	return false
	if _find_resource_at(world_position):
		return false

	var source := _find_building_at(world_position)
	if (
		not is_instance_valid(source)
		or source.get_output_resource_type() == &""
	):
		return false

	var has_selected_villager := false
	for villager in _selected_villagers:
		if is_instance_valid(villager):
			has_selected_villager = true
			break
	if not has_selected_villager:
		return false

	_is_right_action_pending = true
	_right_action_source = source
	_right_action_world_position = world_position
	_right_action_screen_position = screen_position
	_right_action_elapsed = 0.0
	return true


func _update_pending_right_action(delta: float) -> void:
	if not _is_right_action_pending:
		return
	if (
		not is_instance_valid(_right_action_source)
		or _right_action_source.is_queued_for_deletion()
		or _is_demolition_active()
		or _is_building_placement_active()
	):
		_cancel_pending_right_action()
		return

	_right_action_elapsed += delta
	if _right_action_elapsed >= maxf(right_hold_threshold, 0.0):
		_promote_pending_right_action()


func _update_pending_right_drag(screen_position: Vector2) -> void:
	if not _is_right_action_pending:
		return
	if (
		_right_action_screen_position.distance_to(screen_position)
		>= maxf(right_drag_threshold, 0.0)
	):
		_promote_pending_right_action()


func _finish_pending_right_action(mouse_event: InputEventMouseButton) -> void:
	if not _is_right_action_pending:
		return

	if (
		_right_action_screen_position.distance_to(mouse_event.position)
		>= maxf(right_drag_threshold, 0.0)
	):
		_promote_pending_right_action()
		if _is_quick_haul_planning:
			_finish_quick_haul_planning(
				_find_building_at(_screen_to_world(mouse_event.position)),
				mouse_event.shift_pressed
			)
		return

	var command_position := _right_action_world_position
	_cancel_pending_right_action()
	_command_selection_at(command_position, mouse_event.shift_pressed)


func _promote_pending_right_action() -> void:
	if not _is_right_action_pending:
		return
	var source := _right_action_source
	_cancel_pending_right_action()
	_begin_quick_haul_planning(source)


func _cancel_pending_right_action() -> void:
	_is_right_action_pending = false
	_right_action_source = null
	_right_action_world_position = Vector2.ZERO
	_right_action_screen_position = Vector2.ZERO
	_right_action_elapsed = 0.0


func _begin_quick_haul_planning(source: Building) -> bool:
	if (
		not is_instance_valid(source)
		or source.is_queued_for_deletion()
		or source.get_output_resource_type() == &""
	):
		return false

	_quick_haul_villagers.clear()
	for villager in _selected_villagers:
		if is_instance_valid(villager):
			_quick_haul_villagers.append(villager)
	if _quick_haul_villagers.is_empty():
		return false

	_is_quick_haul_planning = true
	_quick_haul_source = source
	haul_route_preview.clear_points()
	haul_route_preview.visible = true
	haul_planning_label.text = (
		"搬運規劃：%s，每位村民使用最大載量\n"
		+ "在相容建築上放開右鍵，按住 Shift 可加入排程　Esc 取消"
	) % String(source.get_output_resource_type())
	haul_planning_label.visible = true
	_set_hovered_interaction_host(source)
	return true


func _handle_quick_haul_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if (
		mouse_event.button_index == MOUSE_BUTTON_RIGHT
		and not mouse_event.pressed
	):
		_finish_quick_haul_planning(
			_find_building_at(_screen_to_world(mouse_event.position)),
			mouse_event.shift_pressed
		)
	get_viewport().set_input_as_handled()


func _finish_quick_haul_planning(
	destination: Building,
	queue_work := false
) -> void:
	if (
		not is_instance_valid(_quick_haul_source)
		or not is_instance_valid(destination)
		or destination == _quick_haul_source
		or not destination.accepts_resource(
			_quick_haul_source.get_output_resource_type()
		)
	):
		_cancel_quick_haul_planning()
		return

	if destination is ConstructionSite:
		var villagers: Array[Villager] = []
		for villager in _quick_haul_villagers:
			if is_instance_valid(villager):
				villagers.append(villager)
		_start_construction_job(
			villagers,
			_quick_haul_source,
			destination as ConstructionSite,
			[],
			queue_work
		)
		_cancel_quick_haul_planning()
		return

	for villager in _quick_haul_villagers:
		if is_instance_valid(villager):
			villager.start_haul_job(
				_quick_haul_source,
				destination,
				[],
				maxi(villager.backpack_capacity, 1),
				queue_work
			)
	_cancel_quick_haul_planning()


func _cancel_quick_haul_planning() -> void:
	_is_quick_haul_planning = false
	_quick_haul_villagers.clear()
	_quick_haul_source = null
	haul_route_preview.clear_points()
	haul_route_preview.visible = false
	haul_planning_label.visible = false
	_set_hovered_interaction_host(null)


func _handle_demolition_input(event: InputEvent) -> void:
	var building_manager := _get_building_manager()
	if not building_manager:
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if (
			key_event.pressed
			and not key_event.echo
			and key_event.keycode == KEY_ESCAPE
		):
			building_manager.cancel_demolition()
			_set_hovered_interaction_host(null)
			get_viewport().set_input_as_handled()
		return

	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if mouse_event.pressed:
			building_manager.cancel_demolition()
			_set_hovered_interaction_host(null)
		get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if mouse_event.pressed:
		var world_position := _screen_to_world(mouse_event.position)
		var target := _find_demolishable_building_at(world_position)
		if is_instance_valid(target):
			_set_hovered_interaction_host(null)
			building_manager.demolish_building(target)
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


func _handle_stop_input(event: InputEvent) -> bool:
	if event is not InputEventKey:
		return false
	var key_event := event as InputEventKey
	if (
		not key_event.pressed
		or key_event.echo
		or key_event.keycode != KEY_S
	):
		return false

	var villagers := get_selected_villagers()
	if villagers.is_empty():
		return false

	cancel_command_planning()
	for villager in villagers:
		villager.stop_all_work()
	get_viewport().set_input_as_handled()
	return true


func _move_selection_to(
	world_position: Vector2,
	queue_work := false,
	repeat_queue := false
) -> void:
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
			formation_positions[villager_index],
			queue_work,
			repeat_queue
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


func _command_selection_at(
	world_position: Vector2,
	queue_work := false,
	repeat_queue := false
) -> void:
	var should_queue := queue_work or repeat_queue
	var resource_node := _find_resource_at(world_position)
	if resource_node:
		for villager in _selected_villagers:
			if is_instance_valid(villager):
				villager.gather_from(
					resource_node,
					should_queue,
					repeat_queue
				)
		return

	var component := _find_interactable_component_at(world_position)
	if component:
		for villager in _selected_villagers:
			if (
				is_instance_valid(villager)
				and component.can_interact(villager)
			):
				villager.interact_with_component(
					component,
					should_queue,
					repeat_queue
				)
		return

	_move_selection_to(world_position, should_queue, repeat_queue)


func _find_nearest_selected_villager(
	world_position: Vector2,
	factory: Factory = null
) -> Villager:
	var nearest_villager: Villager
	var nearest_distance := INF
	for villager in _selected_villagers:
		if not is_instance_valid(villager):
			continue
		if (
			is_instance_valid(factory)
			and not villager.can_work_at_factory_from_smart_click(factory)
		):
			continue
		var distance := villager.global_position.distance_squared_to(world_position)
		if distance < nearest_distance:
			nearest_villager = villager
			nearest_distance = distance
	return nearest_villager


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


func _find_interactable_component_at(world_position: Vector2) -> Node:
	var closest_component: Node = null
	var closest_distance := INF

	for node in get_tree().get_nodes_in_group(&"interactable_components"):
		var component := node as Node
		if (
			component
			and component.has_method("contains_point")
			and component.contains_point(world_position)
		):
			var distance: float = component.global_position.distance_squared_to(
				world_position
			)
			if distance < closest_distance:
				closest_component = component
				closest_distance = distance

	return closest_component


func _find_demolishable_building_at(
	world_position: Vector2
) -> Node2D:
	var closest_building: Node2D = null
	var closest_distance := INF

	for node in get_tree().get_nodes_in_group(&"building_roots"):
		var building := node as Node2D
		if (
			building
			and building.has_method("contains_point")
			and building.contains_point(world_position)
		):
			var distance := building.global_position.distance_squared_to(
				world_position
			)
			if distance < closest_distance:
				closest_building = building
				closest_distance = distance

	return closest_building


func _update_hovered_interaction_host(world_position: Vector2) -> void:
	var hovered_host: Node = _find_resource_at(world_position)
	if not hovered_host:
		hovered_host = _find_interactable_component_at(world_position)
	_set_hovered_interaction_host(hovered_host)


func _set_hovered_interaction_host(host: Node) -> void:
	if (
		is_instance_valid(_hovered_interaction_host)
		and _hovered_interaction_host != host
		and _hovered_interaction_host.has_method("set_hovered")
	):
		_hovered_interaction_host.set_hovered(false)

	_hovered_interaction_host = host
	if (
		is_instance_valid(_hovered_interaction_host)
		and _hovered_interaction_host.has_method("set_hovered")
	):
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
	var building_manager := _get_building_manager()
	return building_manager != null and building_manager.is_placing()


func _is_demolition_active() -> bool:
	var building_manager := _get_building_manager()
	return building_manager != null and building_manager.is_demolishing()


func _get_building_manager() -> Node:
	var managers := get_tree().get_nodes_in_group(&"building_managers")
	if managers.is_empty():
		return null
	return managers[0]
