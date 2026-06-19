class_name Villager
extends CharacterBody2D

signal selection_changed(villager: Villager, is_selected: bool)

const RADIUS := 32.0

enum WorkState {
	IDLE,
	MOVING,
	MOVING_TO_RESOURCE,
	GATHERING,
	SEARCHING_BUILDING,
	MOVING_TO_BUILDING,
	WAITING_TO_DEPOSIT,
}

@export var move_speed := 220.0
@export var arrival_distance := 3.0
@export var backpack_capacity := 5
@export var gather_interval := 1.0
@export var retry_interval := 1.0

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


func _ready() -> void:
	_update_backpack_label()


func _physics_process(delta: float) -> void:
	_update_work(delta)

	if not _has_target:
		velocity = Vector2.ZERO
		return

	if navigation_agent.is_navigation_finished():
		_arrive_at_target()
		return

	var next_path_position := navigation_agent.get_next_path_position()
	var target_offset := next_path_position - global_position
	if target_offset.length() <= arrival_distance:
		velocity = Vector2.ZERO
		return

	velocity = target_offset.normalized() * minf(
		move_speed,
		target_offset.length() / maxf(delta, 0.001)
	)
	move_and_slide()


func set_selected(value: bool) -> void:
	if _is_selected == value:
		return

	_is_selected = value
	selection_highlight.visible = value
	selection_changed.emit(self, value)


func is_selected() -> bool:
	return _is_selected


func move_to(world_position: Vector2) -> void:
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

	_resource_target = resource_node
	_building_target = null
	_work_resource_type = resource_node.resource_type
	_action_timer = 0.0

	if _backpack_amount >= backpack_capacity:
		_begin_delivery()
		return

	_state = WorkState.MOVING_TO_RESOURCE
	_set_movement_target(resource_node.get_interaction_position(global_position))


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
	if _state == WorkState.MOVING:
		_state = WorkState.IDLE


func contains_point(world_position: Vector2) -> bool:
	return global_position.distance_squared_to(world_position) <= RADIUS * RADIUS


func _update_work(delta: float) -> void:
	match _state:
		WorkState.GATHERING:
			if not is_instance_valid(_resource_target):
				_handle_resource_unavailable()
				return
			_action_timer -= delta
			if _action_timer <= 0.0:
				_gather_once()
		WorkState.SEARCHING_BUILDING:
			_action_timer -= delta
			if _action_timer <= 0.0:
				_find_and_move_to_building()
		WorkState.WAITING_TO_DEPOSIT:
			if not is_instance_valid(_building_target):
				_state = WorkState.SEARCHING_BUILDING
				_action_timer = 0.0
				return
			_action_timer -= delta
			if _action_timer <= 0.0:
				_attempt_deposit()


func _arrive_at_target() -> void:
	_has_target = false
	velocity = Vector2.ZERO

	match _state:
		WorkState.MOVING:
			_state = WorkState.IDLE
		WorkState.MOVING_TO_RESOURCE:
			if is_instance_valid(_resource_target):
				_state = WorkState.GATHERING
				_action_timer = gather_interval
			else:
				_handle_resource_unavailable()
		WorkState.MOVING_TO_BUILDING:
			if is_instance_valid(_building_target):
				_attempt_deposit()
			else:
				_state = WorkState.SEARCHING_BUILDING
				_action_timer = 0.0


func _gather_once() -> void:
	_action_timer = gather_interval
	if not is_instance_valid(_resource_target):
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
	elif not is_instance_valid(_resource_target) or _resource_target.resource_amount <= 0:
		_handle_resource_unavailable()


func _handle_resource_unavailable() -> void:
	_resource_target = null
	if _backpack_amount > 0:
		_begin_delivery()
	else:
		_state = WorkState.IDLE
		_work_resource_type = &""


func _begin_delivery() -> void:
	if _backpack_amount <= 0:
		_return_to_resource_or_idle()
		return

	_state = WorkState.SEARCHING_BUILDING
	_action_timer = 0.0
	_find_and_move_to_building()


func _find_and_move_to_building() -> void:
	var nearest_building: Building = null
	var nearest_distance := INF

	for node in get_tree().get_nodes_in_group(&"buildings"):
		var building := node as Building
		if not building or not building.accepts_resource(_backpack_resource_type):
			continue

		var interaction_position := building.get_interaction_position(global_position)
		var distance := global_position.distance_squared_to(interaction_position)
		if distance < nearest_distance:
			nearest_building = building
			nearest_distance = distance

	if not nearest_building:
		_building_target = null
		_state = WorkState.SEARCHING_BUILDING
		_action_timer = retry_interval
		return

	_building_target = nearest_building
	_state = WorkState.MOVING_TO_BUILDING
	_set_movement_target(nearest_building.get_interaction_position(global_position))


func _attempt_deposit() -> void:
	if not is_instance_valid(_building_target):
		_state = WorkState.SEARCHING_BUILDING
		_action_timer = 0.0
		return

	var stored := _building_target.store_resource(
		_backpack_resource_type,
		_backpack_amount
	)
	_backpack_amount -= stored
	if _backpack_amount <= 0:
		_clear_backpack()
		_return_to_resource_or_idle()
		return

	_update_backpack_label()
	_state = WorkState.WAITING_TO_DEPOSIT
	_action_timer = retry_interval


func _return_to_resource_or_idle() -> void:
	_building_target = null
	if is_instance_valid(_resource_target):
		_state = WorkState.MOVING_TO_RESOURCE
		_set_movement_target(_resource_target.get_interaction_position(global_position))
	else:
		_state = WorkState.IDLE
		_work_resource_type = &""


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
