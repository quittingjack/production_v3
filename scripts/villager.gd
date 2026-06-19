class_name Villager
extends CharacterBody2D

signal selection_changed(villager: Villager, is_selected: bool)

const RADIUS := 32.0

enum WorkState {
	IDLE,
	MOVING,
	MOVING_TO_RESOURCE_APPROACH,
	WAITING_FOR_RESOURCE_SLOT,
	MOVING_TO_RESOURCE_SLOT,
	GATHERING,
	SEARCHING_BUILDING,
	MOVING_TO_BUILDING_APPROACH,
	WAITING_FOR_BUILDING_SLOT,
	MOVING_TO_BUILDING_SLOT,
}

@export var move_speed := 220.0
@export var arrival_distance := 3.0
@export var backpack_capacity := 5
@export var gather_interval := 1.0
@export var retry_interval := 1.0
@export var alternative_resource_search_radius := 600.0
@export var slot_move_timeout := 3.0
@export var avoidance_neighbor_distance := 180.0
@export var avoidance_max_neighbors := 8

@onready var selection_highlight: Sprite2D = $SelectionHighlight
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var backpack_label: Label = $BackpackLabel

var _target_position := Vector2.ZERO
var _has_target := false
var _is_selected := false
var _state := WorkState.IDLE
var _resource_target: ResourceNode
var _building_target: Building
var _work_resource_type: StringName = &""
var _backpack_resource_type: StringName = &""
var _backpack_amount := 0
var _action_timer := 0.0
var _slot_move_timer := 0.0
var _resource_slot := -1
var _building_slot := -1
var _approach_direction := 0


func _ready() -> void:
	_approach_direction = int(get_instance_id() % 4)
	navigation_agent.avoidance_enabled = true
	navigation_agent.radius = RADIUS
	navigation_agent.max_speed = move_speed
	navigation_agent.neighbor_distance = avoidance_neighbor_distance
	navigation_agent.max_neighbors = avoidance_max_neighbors
	navigation_agent.velocity_computed.connect(_on_velocity_computed)
	navigation_agent.target_position = global_position
	_update_backpack_label()


func _exit_tree() -> void:
	_release_resource_slot()
	_release_building_slot()


func _physics_process(delta: float) -> void:
	_update_work(delta)

	if not _has_target:
		navigation_agent.velocity = Vector2.ZERO
		return

	if navigation_agent.is_navigation_finished():
		_arrive_at_target()
		navigation_agent.velocity = Vector2.ZERO
		return

	var next_path_position := navigation_agent.get_next_path_position()
	var target_offset := next_path_position - global_position
	if target_offset.length() <= arrival_distance:
		navigation_agent.velocity = Vector2.ZERO
		return

	var desired_velocity := target_offset.normalized() * minf(
		move_speed,
		target_offset.length() / maxf(delta, 0.001)
	)
	navigation_agent.velocity = desired_velocity


func set_selected(value: bool) -> void:
	if _is_selected == value:
		return

	_is_selected = value
	selection_highlight.visible = value
	selection_changed.emit(self, value)


func is_selected() -> bool:
	return _is_selected


func move_to(world_position: Vector2) -> void:
	_release_all_slots()
	_resource_target = null
	_building_target = null
	_work_resource_type = &""
	_state = WorkState.MOVING
	_action_timer = 0.0
	_set_movement_target(world_position)


func gather_from(resource_node: ResourceNode) -> void:
	if not is_instance_valid(resource_node):
		return

	if _backpack_amount > 0 and _backpack_resource_type != resource_node.resource_type:
		_clear_backpack()

	_release_all_slots()
	_resource_target = resource_node
	_building_target = null
	_work_resource_type = resource_node.resource_type
	_action_timer = 0.0

	if _backpack_amount >= backpack_capacity:
		_begin_delivery()
		return

	_move_to_resource_approach()


func _set_movement_target(world_position: Vector2) -> void:
	_target_position = world_position
	_has_target = true
	navigation_agent.target_position = world_position


func refresh_navigation_target() -> void:
	if _has_target:
		navigation_agent.target_position = _target_position


func stop_moving() -> void:
	_has_target = false
	velocity = Vector2.ZERO
	navigation_agent.velocity = Vector2.ZERO
	if _state == WorkState.MOVING:
		_state = WorkState.IDLE


func contains_point(world_position: Vector2) -> bool:
	return global_position.distance_squared_to(world_position) <= RADIUS * RADIUS


func _update_work(delta: float) -> void:
	match _state:
		WorkState.WAITING_FOR_RESOURCE_SLOT:
			if not _is_resource_available(_resource_target):
				_handle_resource_unavailable()
				return
			_action_timer -= delta
			if _action_timer <= 0.0:
				_try_reserve_resource_slot()
		WorkState.MOVING_TO_RESOURCE_SLOT:
			_slot_move_timer -= delta
			if _slot_move_timer <= 0.0:
				_recover_from_resource_slot_stall()
		WorkState.GATHERING:
			if not _is_resource_available(_resource_target):
				_handle_resource_unavailable()
				return
			_action_timer -= delta
			if _action_timer <= 0.0:
				_gather_once()
		WorkState.SEARCHING_BUILDING:
			_action_timer -= delta
			if _action_timer <= 0.0:
				_find_and_move_to_building()
		WorkState.WAITING_FOR_BUILDING_SLOT:
			if not _is_building_usable(_building_target):
				_release_building_slot()
				_find_and_move_to_building()
				return
			_action_timer -= delta
			if _action_timer <= 0.0:
				_try_reserve_building_slot()
		WorkState.MOVING_TO_BUILDING_SLOT:
			_slot_move_timer -= delta
			if _slot_move_timer <= 0.0:
				_recover_from_building_slot_stall()


func _arrive_at_target() -> void:
	_has_target = false
	velocity = Vector2.ZERO

	match _state:
		WorkState.MOVING:
			_state = WorkState.IDLE
		WorkState.MOVING_TO_RESOURCE_APPROACH:
			_try_reserve_resource_slot()
		WorkState.MOVING_TO_RESOURCE_SLOT:
			if _is_resource_available(_resource_target) and _resource_slot >= 0:
				_state = WorkState.GATHERING
				_action_timer = gather_interval
			else:
				_handle_resource_unavailable()
		WorkState.MOVING_TO_BUILDING_APPROACH:
			_try_reserve_building_slot()
		WorkState.MOVING_TO_BUILDING_SLOT:
			if _is_building_usable(_building_target) and _building_slot >= 0:
				_attempt_deposit()
			else:
				_release_building_slot()
				_find_and_move_to_building()


func _move_to_resource_approach() -> void:
	if not _is_resource_available(_resource_target):
		_handle_resource_unavailable()
		return

	_release_resource_slot()
	_state = WorkState.MOVING_TO_RESOURCE_APPROACH
	_set_movement_target(
		_resource_target.get_approach_position(_approach_direction)
	)


func _try_reserve_resource_slot() -> void:
	if not _is_resource_available(_resource_target):
		_handle_resource_unavailable()
		return

	var slot := _resource_target.reserve_interaction_slot(
		self,
		global_position
	)
	if slot < 0:
		if _move_to_alternative_resource(_resource_target.global_position):
			return
		_state = WorkState.WAITING_FOR_RESOURCE_SLOT
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	_resource_slot = slot
	_slot_move_timer = slot_move_timeout
	_state = WorkState.MOVING_TO_RESOURCE_SLOT
	_set_movement_target(
		_resource_target.get_interaction_slot_position(_resource_slot)
	)


func _recover_from_resource_slot_stall() -> void:
	_release_resource_slot()
	if not _is_resource_available(_resource_target):
		_handle_resource_unavailable()
		return
	if _move_to_alternative_resource(_resource_target.global_position):
		return
	_move_to_resource_approach()


func _gather_once() -> void:
	_action_timer = gather_interval
	if not _is_resource_available(_resource_target):
		_handle_resource_unavailable()
		return

	var free_space := backpack_capacity - _backpack_amount
	if free_space <= 0:
		_begin_delivery()
		return

	var gathered := _resource_target.take_resource(1)
	if gathered > 0:
		_backpack_resource_type = _work_resource_type
		_backpack_amount += gathered
		_update_backpack_label()

	if _backpack_amount >= backpack_capacity:
		_begin_delivery()
	elif not _is_resource_available(_resource_target):
		_handle_resource_unavailable()


func _handle_resource_unavailable() -> void:
	var search_origin := global_position
	if is_instance_valid(_resource_target):
		search_origin = _resource_target.global_position

	_release_resource_slot()
	_resource_target = null
	if _backpack_amount > 0:
		_begin_delivery()
	elif not _move_to_alternative_resource(search_origin):
		_state = WorkState.IDLE
		_work_resource_type = &""
		_stop_at_current_position()


func _move_to_alternative_resource(search_origin: Vector2) -> bool:
	if _work_resource_type == &"":
		return false

	var nearest_resource: ResourceNode = null
	var nearest_distance := INF
	var search_radius_squared := (
		alternative_resource_search_radius
		* alternative_resource_search_radius
	)

	for node in get_tree().get_nodes_in_group(&"resources"):
		var resource_node := node as ResourceNode
		if not _is_resource_available(resource_node):
			continue
		if resource_node == _resource_target:
			continue
		if resource_node.resource_type != _work_resource_type:
			continue
		if (
			resource_node.global_position.distance_squared_to(search_origin)
			> search_radius_squared
		):
			continue
		if not resource_node.has_available_interaction_slot(self):
			continue

		var distance := global_position.distance_squared_to(
			resource_node.global_position
		)
		if distance < nearest_distance:
			nearest_resource = resource_node
			nearest_distance = distance

	if not nearest_resource:
		return false

	_release_resource_slot()
	_resource_target = nearest_resource
	_move_to_resource_approach()
	return true


func _begin_delivery() -> void:
	if _backpack_amount <= 0:
		_return_to_resource_or_idle()
		return

	_release_resource_slot()
	_release_building_slot()
	_state = WorkState.SEARCHING_BUILDING
	_action_timer = 0.0
	_find_and_move_to_building()


func _find_and_move_to_building(excluded_building: Building = null) -> void:
	var nearest_available: Building = null
	var nearest_available_distance := INF
	var nearest_waitable: Building = null
	var nearest_waitable_distance := INF

	for node in get_tree().get_nodes_in_group(&"buildings"):
		var building := node as Building
		if not _is_building_usable(building) or building == excluded_building:
			continue

		var distance := global_position.distance_squared_to(
			building.global_position
		)
		if (
			building.has_available_interaction_slot(self)
			and distance < nearest_available_distance
		):
			nearest_available = building
			nearest_available_distance = distance
		if distance < nearest_waitable_distance:
			nearest_waitable = building
			nearest_waitable_distance = distance

	var target := nearest_available if nearest_available else nearest_waitable
	if not target:
		_release_building_slot()
		_building_target = null
		_state = WorkState.SEARCHING_BUILDING
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	_release_building_slot()
	_building_target = target
	_state = WorkState.MOVING_TO_BUILDING_APPROACH
	_set_movement_target(
		target.get_approach_position(_approach_direction)
	)


func _try_reserve_building_slot() -> void:
	if not _is_building_usable(_building_target):
		_release_building_slot()
		_find_and_move_to_building()
		return

	var slot := _building_target.reserve_interaction_slot(
		self,
		global_position
	)
	if slot < 0:
		var blocked_building := _building_target
		var alternative := _find_available_building(blocked_building)
		if alternative:
			_release_building_slot()
			_building_target = alternative
			_state = WorkState.MOVING_TO_BUILDING_APPROACH
			_set_movement_target(
				alternative.get_approach_position(_approach_direction)
			)
			return
		_state = WorkState.WAITING_FOR_BUILDING_SLOT
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	_building_slot = slot
	_slot_move_timer = slot_move_timeout
	_state = WorkState.MOVING_TO_BUILDING_SLOT
	_set_movement_target(
		_building_target.get_interaction_slot_position(_building_slot)
	)


func _find_available_building(excluded_building: Building) -> Building:
	var nearest_building: Building = null
	var nearest_distance := INF

	for node in get_tree().get_nodes_in_group(&"buildings"):
		var building := node as Building
		if (
			not _is_building_usable(building)
			or building == excluded_building
			or not building.has_available_interaction_slot(self)
		):
			continue

		var distance := global_position.distance_squared_to(
			building.global_position
		)
		if distance < nearest_distance:
			nearest_building = building
			nearest_distance = distance

	return nearest_building


func _recover_from_building_slot_stall() -> void:
	var blocked_building := _building_target
	_release_building_slot()
	var alternative := _find_available_building(blocked_building)
	if alternative:
		_building_target = alternative
		_state = WorkState.MOVING_TO_BUILDING_APPROACH
		_set_movement_target(
			alternative.get_approach_position(_approach_direction)
		)
	elif _is_building_usable(blocked_building):
		_building_target = blocked_building
		_state = WorkState.MOVING_TO_BUILDING_APPROACH
		_set_movement_target(
			blocked_building.get_approach_position(_approach_direction)
		)
	else:
		_find_and_move_to_building()


func _attempt_deposit() -> void:
	if not _is_building_usable(_building_target):
		_release_building_slot()
		_find_and_move_to_building()
		return

	var stored := _building_target.store_resource(
		_backpack_resource_type,
		_backpack_amount
	)
	_backpack_amount -= stored
	_release_building_slot()

	if _backpack_amount <= 0:
		_clear_backpack()
		_return_to_resource_or_idle()
		return

	_update_backpack_label()
	_find_and_move_to_building()


func _return_to_resource_or_idle() -> void:
	_release_building_slot()
	_building_target = null
	if _is_resource_available(_resource_target):
		_move_to_resource_approach()
		return

	var search_origin := global_position
	if is_instance_valid(_resource_target):
		search_origin = _resource_target.global_position
	_resource_target = null
	if not _move_to_alternative_resource(search_origin):
		_state = WorkState.IDLE
		_work_resource_type = &""
		_stop_at_current_position()


func _is_resource_available(resource_node) -> bool:
	return (
		is_instance_valid(resource_node)
		and not resource_node.is_queued_for_deletion()
		and resource_node.resource_amount > 0
	)


func _is_building_usable(building) -> bool:
	return (
		is_instance_valid(building)
		and not building.is_queued_for_deletion()
		and building.accepts_resource(_backpack_resource_type)
		and building.has_storage_space()
	)


func _release_all_slots() -> void:
	_release_resource_slot()
	_release_building_slot()


func _release_resource_slot() -> void:
	if is_instance_valid(_resource_target) and _resource_slot >= 0:
		_resource_target.release_interaction_slot(self)
	_resource_slot = -1


func _release_building_slot() -> void:
	if is_instance_valid(_building_target) and _building_slot >= 0:
		_building_target.release_interaction_slot(self)
	_building_slot = -1


func _stop_at_current_position() -> void:
	_has_target = false
	velocity = Vector2.ZERO
	navigation_agent.velocity = Vector2.ZERO


func _clear_backpack() -> void:
	_backpack_amount = 0
	_backpack_resource_type = &""
	_update_backpack_label()


func _update_backpack_label() -> void:
	if _backpack_amount <= 0:
		backpack_label.text = ""
	else:
		backpack_label.text = "木頭 %d/%d" % [
			_backpack_amount,
			backpack_capacity,
		]


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity if _has_target else Vector2.ZERO
	move_and_slide()
