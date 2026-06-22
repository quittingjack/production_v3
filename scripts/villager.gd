@tool
class_name Villager
extends CharacterBody2D

signal selection_changed(villager: Villager, is_selected: bool)

const BASE_BODY_SCALE := Vector2(1.0, 1.0)
const BASE_COLLISION_RADIUS := 32.0
const BASE_SELECTION_RADIUS := 32.0
const BASE_LABEL_OFFSETS := {
	"left": -50.0,
	"top": -60.0,
	"right": 50.0,
	"bottom": -36.0,
}

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
	HAUL_MOVING_TO_SOURCE_APPROACH,
	HAUL_WAITING_FOR_SOURCE,
	HAUL_MOVING_TO_SOURCE_SLOT,
	HAUL_MOVING_OUTBOUND,
	HAUL_MOVING_TO_DESTINATION_APPROACH,
	HAUL_WAITING_FOR_DESTINATION,
	HAUL_MOVING_TO_DESTINATION_SLOT,
	HAUL_MOVING_RETURN,
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
@export_range(0.25, 4.0, 0.05) var size_scale := 1.0:
	set(value):
		size_scale = maxf(value, 0.05)
		_apply_size_settings()

@onready var body_sprite: Sprite2D = $BodySprite
@onready var selection_highlight: Sprite2D = $SelectionHighlight
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var navigation_obstacle: NavigationObstacle2D = $NavigationObstacle2D
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
var _haul_source: Building
var _haul_destination: Building
var _haul_waypoints: Array[Vector2] = []
var _haul_amount_per_trip := 1
var _haul_resource_type: StringName = &""
var _haul_route_index := 0
var _haul_slot_host: Building
var _haul_slot := -1
var _selection_radius := BASE_SELECTION_RADIUS
var _is_navigation_stationary := true


func _enter_tree() -> void:
	_apply_size_settings()


func _ready() -> void:
	_apply_size_settings()
	navigation_agent.max_speed = move_speed
	navigation_agent.neighbor_distance = avoidance_neighbor_distance
	navigation_agent.max_neighbors = avoidance_max_neighbors
	navigation_agent.velocity_computed.connect(_on_velocity_computed)
	navigation_agent.target_position = global_position
	_set_navigation_stationary(true)
	_update_backpack_label()


func _exit_tree() -> void:
	_release_all_slots()


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


func get_state_name() -> String:
	return WorkState.keys()[_state]


func is_stationary() -> bool:
	return _is_navigation_stationary


func move_to(world_position: Vector2) -> void:
	_cancel_haul_job()
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

	_cancel_haul_job()
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


func start_haul_job(
	source: Building,
	destination: Building,
	waypoints: Array[Vector2],
	amount_per_trip: int
) -> void:
	if (
		not is_instance_valid(source)
		or not is_instance_valid(destination)
		or source == destination
	):
		return

	var resource_type := source.get_output_resource_type()
	if resource_type == &"" or not destination.accepts_resource(resource_type):
		return

	_cancel_haul_job()
	_release_all_slots()
	_resource_target = null
	_building_target = null
	_work_resource_type = &""
	_haul_source = source
	_haul_destination = destination
	_haul_waypoints = waypoints.duplicate()
	_haul_amount_per_trip = clampi(amount_per_trip, 1, maxi(backpack_capacity, 1))
	_haul_resource_type = resource_type
	_haul_route_index = 0
	_action_timer = 0.0

	if _backpack_amount > 0:
		if _backpack_resource_type == _haul_resource_type:
			_begin_haul_outbound()
		else:
			_end_haul_job()
		return

	_begin_haul_source_approach()


func _set_movement_target(world_position: Vector2) -> void:
	_target_position = world_position
	_has_target = true
	_set_navigation_stationary(false)
	navigation_agent.target_position = world_position


func refresh_navigation_target() -> void:
	if _has_target:
		navigation_agent.target_position = _target_position


func stop_moving() -> void:
	_has_target = false
	velocity = Vector2.ZERO
	navigation_agent.velocity = Vector2.ZERO
	_set_navigation_stationary(true)
	if _state == WorkState.MOVING:
		_state = WorkState.IDLE


func on_interaction_slots_rebuilt(
	host: InteractionSlotHost,
	new_slot_index: int
) -> void:
	if host == _haul_slot_host:
		_haul_slot = new_slot_index
		if new_slot_index < 0:
			if _state == WorkState.HAUL_MOVING_TO_SOURCE_SLOT:
				_begin_haul_source_approach()
			elif _state == WorkState.HAUL_MOVING_TO_DESTINATION_SLOT:
				_begin_haul_destination_approach()
			return
		if (
			_state == WorkState.HAUL_MOVING_TO_SOURCE_SLOT
			or _state == WorkState.HAUL_MOVING_TO_DESTINATION_SLOT
		):
			_slot_move_timer = slot_move_timeout
			_set_movement_target(
				_haul_slot_host.get_interaction_slot_position(_haul_slot)
			)
		return

	if host == _resource_target:
		_resource_slot = new_slot_index
		if new_slot_index < 0:
			_move_to_resource_approach()
			return
		if (
			_state == WorkState.MOVING_TO_RESOURCE_SLOT
			or _state == WorkState.GATHERING
		):
			_state = WorkState.MOVING_TO_RESOURCE_SLOT
			_slot_move_timer = slot_move_timeout
			_set_movement_target(
				_resource_target.get_interaction_slot_position(
					_resource_slot
				)
			)
		return

	if host == _building_target:
		_building_slot = new_slot_index
		if new_slot_index < 0:
			_state = WorkState.MOVING_TO_BUILDING_APPROACH
			_update_building_approach_target()
			return
		if _state == WorkState.MOVING_TO_BUILDING_SLOT:
			_slot_move_timer = slot_move_timeout
			_set_movement_target(
				_building_target.get_interaction_slot_position(
					_building_slot
				)
			)


func contains_point(world_position: Vector2) -> bool:
	return (
		global_position.distance_squared_to(world_position)
		<= _selection_radius * _selection_radius
	)


func _apply_size_settings() -> void:
	_selection_radius = BASE_SELECTION_RADIUS * size_scale

	if not is_node_ready():
		return

	body_sprite.scale = BASE_BODY_SCALE * size_scale
	selection_highlight.scale = Vector2.ONE * size_scale

	var circle_shape := collision_shape.shape as CircleShape2D
	if circle_shape:
		circle_shape.radius = BASE_COLLISION_RADIUS * size_scale * 0.5

	navigation_agent.radius = BASE_COLLISION_RADIUS * size_scale * 0.5
	navigation_obstacle.radius = BASE_COLLISION_RADIUS * size_scale * 0.5
	backpack_label.offset_left = BASE_LABEL_OFFSETS["left"] * size_scale
	backpack_label.offset_top = BASE_LABEL_OFFSETS["top"] * size_scale
	backpack_label.offset_right = BASE_LABEL_OFFSETS["right"] * size_scale
	backpack_label.offset_bottom = BASE_LABEL_OFFSETS["bottom"] * size_scale


func _update_work(delta: float) -> void:
	match _state:
		WorkState.MOVING_TO_RESOURCE_APPROACH:
			if not _is_resource_available(_resource_target):
				_handle_resource_unavailable()
				return
			if _is_within_resource_slot_claim_distance():
				_try_reserve_resource_slot()
				return
			_update_resource_approach_target()
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
		WorkState.MOVING_TO_BUILDING_APPROACH:
			if not _is_building_usable(_building_target):
				_release_building_slot()
				_find_and_move_to_building()
				return
			if _is_within_building_slot_claim_distance():
				_try_reserve_building_slot()
				return
			_update_building_approach_target()
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
		WorkState.HAUL_MOVING_TO_SOURCE_APPROACH:
			_update_haul_source_approach()
		WorkState.HAUL_WAITING_FOR_SOURCE:
			if not _is_haul_job_valid():
				_end_haul_job()
				return
			_action_timer -= delta
			if _action_timer <= 0.0:
				_begin_haul_source_approach()
		WorkState.HAUL_MOVING_TO_SOURCE_SLOT:
			if not _is_haul_job_valid():
				_end_haul_job()
				return
			_slot_move_timer -= delta
			if _slot_move_timer <= 0.0:
				_release_haul_slot()
				_begin_haul_source_approach()
		WorkState.HAUL_MOVING_OUTBOUND, WorkState.HAUL_MOVING_RETURN:
			if not _is_haul_job_valid():
				_end_haul_job()
		WorkState.HAUL_MOVING_TO_DESTINATION_APPROACH:
			_update_haul_destination_approach()
		WorkState.HAUL_WAITING_FOR_DESTINATION:
			if not _is_haul_job_valid():
				_end_haul_job()
				return
			_action_timer -= delta
			if _action_timer <= 0.0:
				_begin_haul_destination_approach()
		WorkState.HAUL_MOVING_TO_DESTINATION_SLOT:
			if not _is_haul_job_valid():
				_end_haul_job()
				return
			_slot_move_timer -= delta
			if _slot_move_timer <= 0.0:
				_release_haul_slot()
				_begin_haul_destination_approach()


func _arrive_at_target() -> void:
	_has_target = false
	velocity = Vector2.ZERO

	match _state:
		WorkState.MOVING:
			_state = WorkState.IDLE
		WorkState.MOVING_TO_RESOURCE_APPROACH:
			if _is_within_resource_slot_claim_distance():
				_try_reserve_resource_slot()
			else:
				_update_resource_approach_target()
		WorkState.MOVING_TO_RESOURCE_SLOT:
			if _is_resource_available(_resource_target) and _resource_slot >= 0:
				_state = WorkState.GATHERING
				_action_timer = gather_interval
			else:
				_handle_resource_unavailable()
		WorkState.MOVING_TO_BUILDING_APPROACH:
			if not _is_building_usable(_building_target):
				_release_building_slot()
				_find_and_move_to_building()
			elif _is_within_building_slot_claim_distance():
				_try_reserve_building_slot()
			else:
				_update_building_approach_target()
		WorkState.MOVING_TO_BUILDING_SLOT:
			if _is_building_usable(_building_target) and _building_slot >= 0:
				_attempt_deposit()
			else:
				_release_building_slot()
				_find_and_move_to_building()
		WorkState.HAUL_MOVING_TO_SOURCE_APPROACH:
			_update_haul_source_approach()
		WorkState.HAUL_MOVING_TO_SOURCE_SLOT:
			if _is_haul_job_valid() and _haul_slot >= 0:
				_take_haul_output()
			else:
				_end_haul_job()
		WorkState.HAUL_MOVING_OUTBOUND:
			_advance_haul_outbound()
		WorkState.HAUL_MOVING_TO_DESTINATION_APPROACH:
			_update_haul_destination_approach()
		WorkState.HAUL_MOVING_TO_DESTINATION_SLOT:
			if _is_haul_job_valid() and _haul_slot >= 0:
				_deposit_haul_output()
			else:
				_end_haul_job()
		WorkState.HAUL_MOVING_RETURN:
			_advance_haul_return()

	_set_navigation_stationary(not _has_target)


func _move_to_resource_approach() -> void:
	if not _is_resource_available(_resource_target):
		_handle_resource_unavailable()
		return

	_release_resource_slot()
	_state = WorkState.MOVING_TO_RESOURCE_APPROACH
	_update_resource_approach_target()


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


func _update_resource_approach_target() -> void:
	if not _is_resource_available(_resource_target):
		return

	var approach_target := _resource_target.global_position
	if (
		not _has_target
		or _target_position.distance_squared_to(approach_target) > 1.0
	):
		_set_movement_target(approach_target)


func _is_within_resource_slot_claim_distance() -> bool:
	if not _is_resource_available(_resource_target):
		return false

	return (
		_resource_target.is_within_approach_clearance(global_position)
	)


func _update_building_approach_target() -> void:
	if not _is_building_usable(_building_target):
		return

	var approach_target := _building_target.global_position
	if (
		not _has_target
		or _target_position.distance_squared_to(approach_target) > 1.0
	):
		_set_movement_target(approach_target)


func _is_within_building_slot_claim_distance() -> bool:
	if not _is_building_usable(_building_target):
		return false

	return (
		_building_target.is_within_approach_clearance(global_position)
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
	_update_building_approach_target()


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
			_update_building_approach_target()
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
		_update_building_approach_target()
	elif _is_building_usable(blocked_building):
		_building_target = blocked_building
		_state = WorkState.MOVING_TO_BUILDING_APPROACH
		_update_building_approach_target()
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


func _begin_haul_source_approach() -> void:
	_release_haul_slot()
	if not _is_haul_job_valid():
		_end_haul_job()
		return
	if _backpack_amount > 0:
		_begin_haul_outbound()
		return
	if _haul_source.get_output_amount(_haul_resource_type) <= 0:
		_state = WorkState.HAUL_WAITING_FOR_SOURCE
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	_state = WorkState.HAUL_MOVING_TO_SOURCE_APPROACH
	_update_haul_source_approach()


func _update_haul_source_approach() -> void:
	if not _is_haul_job_valid():
		_end_haul_job()
		return
	if _haul_source.get_output_amount(_haul_resource_type) <= 0:
		_state = WorkState.HAUL_WAITING_FOR_SOURCE
		_action_timer = retry_interval
		_stop_at_current_position()
		return
	if _haul_source.is_within_approach_clearance(global_position):
		_try_reserve_haul_source_slot()
		return
	if (
		not _has_target
		or _target_position.distance_squared_to(_haul_source.global_position) > 1.0
	):
		_set_movement_target(_haul_source.global_position)


func _try_reserve_haul_source_slot() -> void:
	if not _is_haul_job_valid():
		_end_haul_job()
		return
	if _haul_source.get_output_amount(_haul_resource_type) <= 0:
		_state = WorkState.HAUL_WAITING_FOR_SOURCE
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	var slot := _haul_source.reserve_interaction_slot(self, global_position)
	if slot < 0:
		_state = WorkState.HAUL_WAITING_FOR_SOURCE
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	_haul_slot_host = _haul_source
	_haul_slot = slot
	_slot_move_timer = slot_move_timeout
	_state = WorkState.HAUL_MOVING_TO_SOURCE_SLOT
	_set_movement_target(_haul_source.get_interaction_slot_position(slot))


func _take_haul_output() -> void:
	var free_space := maxi(backpack_capacity - _backpack_amount, 0)
	var requested := mini(_haul_amount_per_trip, free_space)
	var taken := _haul_source.take_output(_haul_resource_type, requested)
	_release_haul_slot()
	if taken <= 0:
		_state = WorkState.HAUL_WAITING_FOR_SOURCE
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	_backpack_resource_type = _haul_resource_type
	_backpack_amount += taken
	_update_backpack_label()
	_begin_haul_outbound()


func _begin_haul_outbound() -> void:
	if not _is_haul_job_valid():
		_end_haul_job()
		return
	_haul_route_index = 0
	if _haul_waypoints.is_empty():
		_begin_haul_destination_approach()
		return
	_state = WorkState.HAUL_MOVING_OUTBOUND
	_set_movement_target(_haul_waypoints[_haul_route_index])


func _advance_haul_outbound() -> void:
	_haul_route_index += 1
	if _haul_route_index >= _haul_waypoints.size():
		_begin_haul_destination_approach()
		return
	_state = WorkState.HAUL_MOVING_OUTBOUND
	_set_movement_target(_haul_waypoints[_haul_route_index])


func _begin_haul_destination_approach() -> void:
	_release_haul_slot()
	if not _is_haul_job_valid():
		_end_haul_job()
		return
	if _backpack_amount <= 0:
		_begin_haul_return()
		return
	if not _haul_destination.has_storage_space():
		_state = WorkState.HAUL_WAITING_FOR_DESTINATION
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	_state = WorkState.HAUL_MOVING_TO_DESTINATION_APPROACH
	_update_haul_destination_approach()


func _update_haul_destination_approach() -> void:
	if not _is_haul_job_valid():
		_end_haul_job()
		return
	if not _haul_destination.has_storage_space():
		_state = WorkState.HAUL_WAITING_FOR_DESTINATION
		_action_timer = retry_interval
		_stop_at_current_position()
		return
	if _haul_destination.is_within_approach_clearance(global_position):
		_try_reserve_haul_destination_slot()
		return
	if (
		not _has_target
		or _target_position.distance_squared_to(
			_haul_destination.global_position
		) > 1.0
	):
		_set_movement_target(_haul_destination.global_position)


func _try_reserve_haul_destination_slot() -> void:
	if not _is_haul_job_valid():
		_end_haul_job()
		return
	if not _haul_destination.has_storage_space():
		_state = WorkState.HAUL_WAITING_FOR_DESTINATION
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	var slot := _haul_destination.reserve_interaction_slot(self, global_position)
	if slot < 0:
		_state = WorkState.HAUL_WAITING_FOR_DESTINATION
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	_haul_slot_host = _haul_destination
	_haul_slot = slot
	_slot_move_timer = slot_move_timeout
	_state = WorkState.HAUL_MOVING_TO_DESTINATION_SLOT
	_set_movement_target(_haul_destination.get_interaction_slot_position(slot))


func _deposit_haul_output() -> void:
	var stored := _haul_destination.store_resource(
		_backpack_resource_type,
		_backpack_amount
	)
	_backpack_amount -= stored
	_release_haul_slot()
	if _backpack_amount > 0:
		_update_backpack_label()
		_state = WorkState.HAUL_WAITING_FOR_DESTINATION
		_action_timer = retry_interval
		_stop_at_current_position()
		return

	_clear_backpack()
	_begin_haul_return()


func _begin_haul_return() -> void:
	if not _is_haul_job_valid():
		_end_haul_job()
		return
	_haul_route_index = _haul_waypoints.size() - 1
	if _haul_route_index < 0:
		_begin_haul_source_approach()
		return
	_state = WorkState.HAUL_MOVING_RETURN
	_set_movement_target(_haul_waypoints[_haul_route_index])


func _advance_haul_return() -> void:
	_haul_route_index -= 1
	if _haul_route_index < 0:
		_begin_haul_source_approach()
		return
	_state = WorkState.HAUL_MOVING_RETURN
	_set_movement_target(_haul_waypoints[_haul_route_index])


func _is_haul_job_valid() -> bool:
	return (
		is_instance_valid(_haul_source)
		and not _haul_source.is_queued_for_deletion()
		and is_instance_valid(_haul_destination)
		and not _haul_destination.is_queued_for_deletion()
		and _haul_source != _haul_destination
		and _haul_source.get_output_resource_type() == _haul_resource_type
		and _haul_destination.accepts_resource(_haul_resource_type)
	)


func _cancel_haul_job() -> void:
	_release_haul_slot()
	_haul_source = null
	_haul_destination = null
	_haul_waypoints.clear()
	_haul_resource_type = &""
	_haul_route_index = 0


func _end_haul_job() -> void:
	_cancel_haul_job()
	_state = WorkState.IDLE
	_stop_at_current_position()


func _release_all_slots() -> void:
	_release_resource_slot()
	_release_building_slot()
	_release_haul_slot()


func _release_resource_slot() -> void:
	if is_instance_valid(_resource_target) and _resource_slot >= 0:
		_resource_target.release_interaction_slot(self)
	_resource_slot = -1


func _release_building_slot() -> void:
	if is_instance_valid(_building_target) and _building_slot >= 0:
		_building_target.release_interaction_slot(self)
	_building_slot = -1


func _release_haul_slot() -> void:
	if is_instance_valid(_haul_slot_host) and _haul_slot >= 0:
		_haul_slot_host.release_interaction_slot(self)
	_haul_slot_host = null
	_haul_slot = -1


func _stop_at_current_position() -> void:
	_has_target = false
	velocity = Vector2.ZERO
	navigation_agent.velocity = Vector2.ZERO
	_set_navigation_stationary(true)


func _set_navigation_stationary(is_stationary: bool) -> void:
	_is_navigation_stationary = is_stationary
	navigation_agent.avoidance_enabled = not is_stationary
	navigation_obstacle.avoidance_enabled = is_stationary


func _clear_backpack() -> void:
	_backpack_amount = 0
	_backpack_resource_type = &""
	_update_backpack_label()


func _update_backpack_label() -> void:
	if _backpack_amount <= 0:
		backpack_label.text = ""
	else:
		backpack_label.text = "%s %d/%d" % [
			String(_backpack_resource_type),
			_backpack_amount,
			backpack_capacity,
		]


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity if _has_target else Vector2.ZERO
	move_and_slide()
