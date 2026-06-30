@tool
class_name Villager
extends CharacterBody2D

signal selection_changed(villager: Villager, is_selected: bool)
signal work_queue_changed(villager: Villager)

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
	MOVING_TO_COMPONENT_SLOT,
	COMPONENT_WORKING,
}

@export var move_speed := 220.0
@export var arrival_distance := 3.0
@export var backpack_capacity := 5
@export var debug_log := false
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
var _selection_radius := BASE_SELECTION_RADIUS
var _is_navigation_stationary := true

var _backpack_resource_type: StringName = &""
var _backpack_amount := 0

var _work_queue: Array[VillagerWorkOrder] = []
var _current_work_index := -1
var _is_starting_work_order := false

var _resource_target: ResourceNode
var _resource_slot := -1
var _work_resource_type: StringName = &""
var _component_target: Node
var _component_slot: Node
var _action_timer := 0.0
var _slot_move_timer := 0.0


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
	_clear_work_queue_and_current()


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


func move_to(
	world_position: Vector2,
	queue_work := false,
	repeat_queue := false
) -> void:
	_schedule_work(
		VillagerWorkOrder.create_move(world_position, repeat_queue),
		queue_work or repeat_queue
	)


func gather_from(
	resource_node: ResourceNode,
	queue_work := false,
	repeat_queue := false
) -> void:
	if not is_instance_valid(resource_node):
		return
	_schedule_work(
		VillagerWorkOrder.create_gather(resource_node, repeat_queue),
		queue_work or repeat_queue
	)


func interact_with_component(
	component: Node,
	queue_work := false,
	repeat_queue := false
) -> bool:
	_log(
		"interact_with_component",
		"request interaction",
		{
			"component": _node_name(component),
			"queue_work": queue_work,
			"repeat_queue": repeat_queue,
		}
	)
	if not _is_component_interaction_valid(component):
		_warn(
			"interact_with_component",
			"interaction rejected because component is not interactable",
			{"component": _node_name(component)}
		)
		return false
	if component.has_method("can_interact") and not component.can_interact(self):
		_warn(
			"interact_with_component",
			"interaction rejected by component.can_interact",
			{"component": component.name}
		)
		return false

	if not queue_work and not repeat_queue:
		_log(
			"interact_with_component",
			"clearing current work before scheduling component interaction",
			{"component": component.name}
		)
		_clear_work_queue_and_current()

	var order: VillagerWorkOrder
	if component is WorkComponent or component.has_method("activate_worker"):
		order = VillagerWorkOrder.create_work_component(
			component,
			null,
			repeat_queue
		)
		_log(
			"interact_with_component",
			"created work component order",
			_describe_work_order(order)
		)
	else:
		order = VillagerWorkOrder.create_interact_storage(
			component,
			null,
			repeat_queue
		)
		_log(
			"interact_with_component",
			"created storage interaction order",
			_describe_work_order(order)
		)
	_schedule_work(order, true)
	return _work_queue.has(order)


func stop_all_work() -> void:
	_clear_work_queue_and_current()


func get_work_queue_count() -> int:
	return _work_queue.size()


func get_work_queue_snapshot() -> Array[VillagerWorkOrder]:
	return _work_queue.duplicate()


func get_current_work_index() -> int:
	return _current_work_index


func get_current_work_type_name() -> String:
	var order := _get_current_work_order()
	return order.get_type_name() if order else ""


func has_work_queued_after_current() -> bool:
	return _current_work_index >= 0 and _work_queue.size() > 1


func cancel_work_order_at(index: int) -> void:
	if index < 0 or index >= _work_queue.size():
		return

	var was_current := index == _current_work_index
	if was_current:
		_cancel_active_work()
	else:
		_release_work_order_reservations(_work_queue[index])

	_work_queue.remove_at(index)
	if _work_queue.is_empty():
		_current_work_index = -1
		_state = WorkState.IDLE
		_stop_at_current_position()
	elif was_current:
		_current_work_index = mini(index, _work_queue.size() - 1)
		_start_current_work_order()
	elif index < _current_work_index:
		_current_work_index -= 1
	work_queue_changed.emit(self)


func get_backpack_amount() -> int:
	return _backpack_amount


func get_backpack_resource_type() -> StringName:
	return _backpack_resource_type


func discard_backpack() -> void:
	_clear_backpack()


func deposit_backpack_to_storage(storage: Node) -> int:
	_log(
		"deposit_backpack_to_storage",
		"deposit attempt",
		{
			"storage": _node_name(storage),
			"resource_type": String(_backpack_resource_type),
			"amount": _backpack_amount,
		}
	)
	if not is_instance_valid(storage):
		_warn("deposit_backpack_to_storage", "deposit aborted because storage is invalid")
		return 0
	if _backpack_amount <= 0:
		_warn("deposit_backpack_to_storage", "deposit aborted because backpack is empty")
		return 0
	var stored: int = storage.store_resource(
		_backpack_resource_type,
		_backpack_amount
	)
	_backpack_amount -= stored
	_log(
		"deposit_backpack_to_storage",
		"deposit result",
		{"stored": stored, "remaining": _backpack_amount}
	)
	if _backpack_amount <= 0:
		_log("deposit_backpack_to_storage", "backpack emptied after deposit")
		_clear_backpack()
	else:
		_log(
			"deposit_backpack_to_storage",
			"backpack still has remaining resources",
			{
				"resource_type": String(_backpack_resource_type),
				"remaining": _backpack_amount,
			}
		)
		_update_backpack_label()
	return stored


func take_from_storage(storage: Node) -> int:
	_log(
		"take_from_storage",
		"take attempt",
		{
			"storage": _node_name(storage),
			"backpack_amount": _backpack_amount,
			"backpack_type": String(_backpack_resource_type),
		}
	)
	if not is_instance_valid(storage):
		_warn("take_from_storage", "take aborted because storage is invalid")
		return 0
	if _backpack_amount >= backpack_capacity:
		_warn(
			"take_from_storage",
			"take aborted because backpack is full",
			{"backpack_amount": _backpack_amount, "capacity": backpack_capacity}
		)
		return 0
	var output_type: StringName = storage.get_output_resource_type()
	if output_type == &"":
		_warn("take_from_storage", "take aborted because storage has no output resource type")
		return 0
	if _backpack_amount > 0 and _backpack_resource_type != output_type:
		_warn(
			"take_from_storage",
			"take aborted because backpack resource type does not match output",
			{
				"backpack_type": String(_backpack_resource_type),
				"output_type": String(output_type),
			}
		)
		return 0
	var free_space := maxi(backpack_capacity - _backpack_amount, 0)
	var taken: int = storage.take_output(output_type, free_space)
	if taken <= 0:
		_warn(
			"take_from_storage",
			"take aborted because storage returned no resource",
			{"output_type": String(output_type), "free_space": free_space}
		)
		return 0
	_backpack_resource_type = output_type
	_backpack_amount += taken
	_update_backpack_label()
	_log(
		"take_from_storage",
		"take result",
		{
			"taken": taken,
			"resource_type": String(output_type),
			"backpack_amount": _backpack_amount,
		}
	)
	return taken


func finish_component_work(component: Node) -> void:
	if _state != WorkState.COMPONENT_WORKING or component != _component_target:
		return
	_complete_current_work_order()


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


func contains_point(world_position: Vector2) -> bool:
	return (
		global_position.distance_squared_to(world_position)
		<= _selection_radius * _selection_radius
	)


func on_interaction_slots_rebuilt(host: InteractionSlotHost, _new_slot_index: int) -> void:
	if host == _resource_target:
		_release_resource_slot()
		_move_to_resource_approach()


# Legacy no-op API kept so older helper code can still parse and fail softly.
func start_haul_job(_source, _destination, _waypoints: Array[Vector2], _amount_per_trip: int, _queue_work := false, _repeat_queue := false) -> void:
	return


func start_construction_job(_job, _waypoints: Array[Vector2], _haul_material: bool, _queue_work := false, _repeat_queue := false) -> void:
	return


func construct_at(_site, _queue_work := false, _repeat_queue := false) -> void:
	return


func work_at_factory(_factory, _queue_work := false, _repeat_queue := false) -> bool:
	return false


func interact_with_building(_building, _queue_work := false, _repeat_queue := false) -> void:
	return


func interact_with_construction_site(_site, _queue_work := false, _repeat_queue := false) -> void:
	return


func can_work_at_factory_from_smart_click(_factory) -> bool:
	return false


func _schedule_work(order: VillagerWorkOrder, queue_work: bool) -> void:
	if not queue_work:
		_log(
			"_schedule_work",
			"clearing work queue before scheduling order",
			_describe_work_order(order)
		)
		_clear_work_queue_and_current()

	_work_queue.append(order)
	_log(
		"_schedule_work",
		"scheduled work order",
		{
			"order": _describe_work_order(order),
			"queue_length": _work_queue.size(),
			"queue_work": queue_work,
		}
	)
	if _current_work_index < 0:
		_current_work_index = _find_next_executable_index(0)
		_log(
			"_schedule_work",
			"starting first available work order immediately",
			{"current_work_index": _current_work_index}
		)
		_start_current_work_order()
	work_queue_changed.emit(self)


func _clear_work_queue_and_current() -> void:
	for order in _work_queue:
		_release_work_order_reservations(order)
	_work_queue.clear()
	_current_work_index = -1
	_cancel_active_work()
	work_queue_changed.emit(self)


func _cancel_active_work() -> void:
	_release_all_slots()
	_resource_target = null
	_component_target = null
	_component_slot = null
	_work_resource_type = &""
	_action_timer = 0.0
	_slot_move_timer = 0.0
	_state = WorkState.IDLE
	_stop_at_current_position()


func _start_current_work_order() -> void:
	if _is_starting_work_order:
		_log("_start_current_work_order", "skip because a work order is already starting")
		return
	_is_starting_work_order = true
	while not _work_queue.is_empty() and _current_work_index >= 0:
		_current_work_index = posmod(_current_work_index, _work_queue.size())
		var order := _work_queue[_current_work_index]
		_log(
			"_start_current_work_order",
			"attempting to start work order",
			{
				"current_work_index": _current_work_index,
				"order": _describe_work_order(order),
			}
		)
		if not _is_work_order_valid(order):
			_warn(
				"_start_current_work_order",
				"discarding invalid work order before start",
				{
					"current_work_index": _current_work_index,
					"order": _describe_work_order(order),
				}
			)
			_remove_current_work_order()
			continue

		var starting_work_index := _current_work_index
		match order.type:
			VillagerWorkOrder.Type.MOVE:
				_start_move_order(order.position)
			VillagerWorkOrder.Type.GATHER:
				_start_gather_order(order)
			VillagerWorkOrder.Type.INTERACT_STORAGE, VillagerWorkOrder.Type.WORK_COMPONENT:
				_start_component_interaction_order(order)
		if _state == WorkState.IDLE and _current_work_index >= 0 and not _work_queue.is_empty():
			if _current_work_index == starting_work_index and _get_current_work_order() == order:
				_is_starting_work_order = false
				work_queue_changed.emit(self)
				return
			continue
		_is_starting_work_order = false
		work_queue_changed.emit(self)
		return

	_log("_start_current_work_order", "no executable work order remains; entering idle state")
	_current_work_index = -1
	_state = WorkState.IDLE
	_stop_at_current_position()
	_is_starting_work_order = false
	work_queue_changed.emit(self)


func _start_move_order(world_position: Vector2) -> void:
	_cancel_active_work()
	_state = WorkState.MOVING
	_set_movement_target(world_position)


func _start_gather_order(order: VillagerWorkOrder) -> void:
	_cancel_active_work()
	if _has_full_backpack_for(order.resource_type):
		_complete_full_backpack_gather_order(order)
		return
	if _backpack_amount > 0 and _backpack_resource_type != order.resource_type:
		_complete_current_work_order()
		return

	_resource_target = order.resource_target
	_work_resource_type = order.resource_type
	if _backpack_amount >= backpack_capacity:
		_complete_current_work_order()
	elif _is_resource_available(_resource_target):
		_move_to_resource_approach()
	else:
		_handle_resource_unavailable()


func _has_full_backpack_for(resource_type: StringName) -> bool:
	return (
		backpack_capacity > 0
		and _backpack_amount >= backpack_capacity
		and _backpack_resource_type == resource_type
	)


func _complete_full_backpack_gather_order(order: VillagerWorkOrder) -> void:
	_log(
		"_complete_full_backpack_gather_order",
		"completing gather order because backpack already has the requested resource at capacity",
		{
			"current_work_index": _current_work_index,
			"order": _describe_work_order(order),
			"backpack_amount": _backpack_amount,
			"backpack_capacity": backpack_capacity,
		}
	)
	if not order.is_looping:
		_release_work_order_reservations(order)
		_work_queue.remove_at(_current_work_index)
		if _work_queue.is_empty():
			_current_work_index = -1
		else:
			_current_work_index = _find_next_executable_index(_current_work_index)
		work_queue_changed.emit(self)
		return

	var next_loop := _find_next_looping_index_after_excluding(
		_current_work_index + 1,
		_current_work_index
	)
	if next_loop < 0:
		_current_work_index = -1
		_state = WorkState.IDLE
		_stop_at_current_position()
	else:
		_current_work_index = next_loop
	work_queue_changed.emit(self)


func _start_component_interaction_order(order: VillagerWorkOrder) -> void:
	_cancel_active_work()
	_component_target = order.component
	_component_slot = order.interaction_slot
	_log(
		"_start_component_interaction_order",
		"start component interaction order",
		{
			"order": _describe_work_order(order),
			"component": _node_name(_component_target),
			"slot": _slot_name(_component_slot),
		}
	)
	if not _is_current_component_interaction_valid():
		_warn(
			"_start_component_interaction_order",
			"discarding component interaction order because reserved slot is invalid",
			{
				"component": _node_name(_component_target),
				"slot": _slot_name(_component_slot),
			}
		)
		_discard_invalid_current_work_order()
		return

	_state = WorkState.MOVING_TO_COMPONENT_SLOT
	_slot_move_timer = slot_move_timeout
	_log(
		"_start_component_interaction_order",
		"moving to reserved component slot",
		{
			"component": _component_target.name,
			"slot": _slot_name(_component_slot),
			"target_position": _component_slot.get_interaction_position(),
			"timeout": _slot_move_timer,
		}
	)
	_set_movement_target(_component_slot.get_interaction_position())


func _is_work_order_valid(order: VillagerWorkOrder) -> bool:
	match order.type:
		VillagerWorkOrder.Type.MOVE:
			return true
		VillagerWorkOrder.Type.GATHER:
			return order.resource_type != &""
		VillagerWorkOrder.Type.INTERACT_STORAGE, VillagerWorkOrder.Type.WORK_COMPONENT:
			return _ensure_component_order_slot(order)
	return false


func _ensure_component_order_slot(order: VillagerWorkOrder) -> bool:
	if (
		not is_instance_valid(order.component)
		or order.component.is_queued_for_deletion()
	):
		_warn(
			"_ensure_component_order_slot",
			"component order is invalid because component no longer exists",
			{"order": _describe_work_order(order)}
		)
		return false
	if is_instance_valid(order.interaction_slot) and order.interaction_slot.occupant == self:
		_log(
			"_ensure_component_order_slot",
			"reusing existing reserved interaction slot",
			{
				"component": order.component.name,
				"slot": _slot_name(order.interaction_slot),
			}
		)
		return true
	if order.component.has_method("can_interact") and not order.component.can_interact(self):
		_warn(
			"_ensure_component_order_slot",
			"component rejected interaction before slot reservation",
			{"component": order.component.name}
		)
		return false
	var slot = order.component.reserve_interaction_slot(self, global_position)
	if not slot:
		_warn(
			"_ensure_component_order_slot",
			"failed to reserve interaction slot for component order",
			{"component": order.component.name}
		)
		return false
	order.interaction_slot = slot
	_log(
		"_ensure_component_order_slot",
		"reserved interaction slot for component order",
		{
			"component": order.component.name,
			"slot": _slot_name(slot),
		}
	)
	return true


func _get_current_work_order() -> VillagerWorkOrder:
	if _current_work_index < 0 or _current_work_index >= _work_queue.size():
		return null
	return _work_queue[_current_work_index]


func _remove_current_work_order() -> void:
	if _current_work_index < 0 or _current_work_index >= _work_queue.size():
		_current_work_index = -1
		return
	_release_work_order_reservations(_work_queue[_current_work_index])
	_work_queue.remove_at(_current_work_index)
	if _work_queue.is_empty():
		_current_work_index = -1
	elif _current_work_index >= _work_queue.size():
		_current_work_index = _find_next_executable_index(0)
	work_queue_changed.emit(self)


func _release_work_order_reservations(order: VillagerWorkOrder) -> void:
	if (
		(
			order.type == VillagerWorkOrder.Type.INTERACT_STORAGE
			or order.type == VillagerWorkOrder.Type.WORK_COMPONENT
		)
		and is_instance_valid(order.component)
	):
		if order.type == VillagerWorkOrder.Type.WORK_COMPONENT:
			if order.component.has_method("deactivate_worker"):
				order.component.deactivate_worker(self)
		order.component.release_interaction_slot(self)


func _complete_current_work_order() -> void:
	var order := _get_current_work_order()
	_log(
		"_complete_current_work_order",
		"completing current work order",
		{
			"current_work_index": _current_work_index,
			"state": get_state_name(),
			"order": _describe_work_order(order),
		}
	)
	_cancel_active_work()
	if not order:
		_log("_complete_current_work_order", "no current work order found after cancellation; trying next order")
		_start_current_work_order()
		return

	if order.is_looping:
		_current_work_index = _find_next_looping_index_after(
			_current_work_index + 1
		)
		_log(
			"_complete_current_work_order",
			"looping work order kept in queue",
			{"next_work_index": _current_work_index, "order": _describe_work_order(order)}
		)
	else:
		_release_work_order_reservations(order)
		_work_queue.remove_at(_current_work_index)
		if _work_queue.is_empty():
			_current_work_index = -1
		else:
			_current_work_index = _find_next_executable_index(_current_work_index)
		_log(
			"_complete_current_work_order",
			"non-looping work order removed from queue",
			{
				"next_work_index": _current_work_index,
				"remaining_queue_length": _work_queue.size(),
				"order": _describe_work_order(order),
			}
		)
	work_queue_changed.emit(self)
	_start_current_work_order()


func _discard_invalid_current_work_order() -> void:
	_warn(
		"_discard_invalid_current_work_order",
		"discarding invalid current work order",
		{
			"current_work_index": _current_work_index,
			"order": _describe_work_order(_get_current_work_order()),
		}
	)
	_cancel_active_work()
	_remove_current_work_order()
	_start_current_work_order()


func _find_first_looping_index() -> int:
	for index in _work_queue.size():
		if _work_queue[index].is_looping:
			return index
	return -1


func _find_next_looping_index_after(start_index: int) -> int:
	if _work_queue.is_empty():
		return -1
	for offset in _work_queue.size():
		var index := posmod(start_index + offset, _work_queue.size())
		if _work_queue[index].is_looping:
			return index
	return -1


func _find_next_looping_index_after_excluding(start_index: int, excluded_index: int) -> int:
	if _work_queue.size() <= 1:
		return -1
	for offset in _work_queue.size():
		var index := posmod(start_index + offset, _work_queue.size())
		if index == excluded_index:
			continue
		if _work_queue[index].is_looping:
			return index
	return -1


func _find_next_executable_index(start_index: int) -> int:
	if _work_queue.is_empty():
		return -1
	var first_loop := _find_first_looping_index()
	if first_loop >= 0:
		return first_loop
	return posmod(start_index, _work_queue.size())


func _update_work(delta: float) -> void:
	match _state:
		WorkState.MOVING_TO_RESOURCE_APPROACH:
			if not _is_resource_available(_resource_target):
				_handle_resource_unavailable()
				return
			if _resource_target.is_within_approach_clearance(global_position):
				_try_reserve_resource_slot()
			else:
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
				_release_resource_slot()
				_move_to_resource_approach()
		WorkState.GATHERING:
			if not _is_resource_available(_resource_target):
				_handle_resource_unavailable()
				return
			_action_timer -= delta
			if _action_timer <= 0.0:
				_gather_once()
		WorkState.MOVING_TO_COMPONENT_SLOT:
			if not _is_current_component_interaction_valid():
				_warn(
					"_update_work",
					"component slot became invalid while moving; completing work order",
					{
						"component": _node_name(_component_target),
						"slot": _slot_name(_component_slot),
					}
				)
				_complete_current_work_order()
				return
			_slot_move_timer -= delta
			if _slot_move_timer <= 0.0:
				_warn(
					"_update_work",
					"timed out while moving to component slot",
					{
						"component": _node_name(_component_target),
						"slot": _slot_name(_component_slot),
					}
				)
				_complete_current_work_order()
		WorkState.COMPONENT_WORKING:
			if not _is_current_component_interaction_valid():
				_warn(
					"_update_work",
					"component work became invalid while working; completing work order",
					{
						"component": _node_name(_component_target),
						"slot": _slot_name(_component_slot),
					}
				)
				_complete_current_work_order()


func _arrive_at_target() -> void:
	_has_target = false
	velocity = Vector2.ZERO

	match _state:
		WorkState.MOVING:
			_complete_current_work_order()
		WorkState.MOVING_TO_RESOURCE_APPROACH:
			if _resource_target.is_within_approach_clearance(global_position):
				_try_reserve_resource_slot()
			else:
				_update_resource_approach_target()
		WorkState.MOVING_TO_RESOURCE_SLOT:
			if _is_resource_available(_resource_target) and _resource_slot >= 0:
				_state = WorkState.GATHERING
				_action_timer = gather_interval
			else:
				_handle_resource_unavailable()
		WorkState.MOVING_TO_COMPONENT_SLOT:
			if _is_current_component_interaction_valid():
				_log(
					"_arrive_at_target",
					"arrived at reserved component slot",
					{
						"component": _node_name(_component_target),
						"slot": _slot_name(_component_slot),
					}
				)
				_arrive_at_component_slot()
			else:
				_warn(
					"_arrive_at_target",
					"arrived near component target but slot is no longer valid",
					{
						"component": _node_name(_component_target),
						"slot": _slot_name(_component_slot),
					}
				)
				_complete_current_work_order()

	_set_navigation_stationary(not _has_target)


func _move_to_resource_approach() -> void:
	if not _is_resource_available(_resource_target):
		_handle_resource_unavailable()
		return

	_release_resource_slot()
	_state = WorkState.MOVING_TO_RESOURCE_APPROACH
	_update_resource_approach_target()


func _update_resource_approach_target() -> void:
	if not _is_resource_available(_resource_target):
		return
	if not _has_target or _target_position.distance_squared_to(_resource_target.global_position) > 1.0:
		_set_movement_target(_resource_target.global_position)


func _try_reserve_resource_slot() -> void:
	if not _is_resource_available(_resource_target):
		_handle_resource_unavailable()
		return

	var slot := _resource_target.reserve_interaction_slot(self, global_position)
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
	_set_movement_target(_resource_target.get_interaction_slot_position(_resource_slot))


func _gather_once() -> void:
	_action_timer = gather_interval
	if not _is_resource_available(_resource_target):
		_handle_resource_unavailable()
		return

	var free_space := backpack_capacity - _backpack_amount
	if free_space <= 0:
		_complete_current_work_order()
		return

	var gathered := _resource_target.take_resource(1)
	if gathered > 0:
		_backpack_resource_type = _work_resource_type
		_backpack_amount += gathered
		_update_backpack_label()

	if _backpack_amount >= backpack_capacity:
		_complete_current_work_order()
	elif not _is_resource_available(_resource_target):
		var search_origin := _resource_target.global_position if is_instance_valid(_resource_target) else global_position
		if not _move_to_alternative_resource(search_origin):
			_complete_current_work_order()


func _handle_resource_unavailable() -> void:
	var search_origin := global_position
	if is_instance_valid(_resource_target):
		search_origin = _resource_target.global_position
	_release_resource_slot()
	_resource_target = null
	if not _move_to_alternative_resource(search_origin):
		_complete_current_work_order()


func _move_to_alternative_resource(search_origin: Vector2) -> bool:
	if _work_resource_type == &"" or _backpack_amount >= backpack_capacity:
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
		if resource_node.resource_type != _work_resource_type:
			continue
		if resource_node.global_position.distance_squared_to(search_origin) > search_radius_squared:
			continue
		if not resource_node.has_available_interaction_slot(self):
			continue

		var distance := global_position.distance_squared_to(resource_node.global_position)
		if distance < nearest_distance:
			nearest_resource = resource_node
			nearest_distance = distance

	if not nearest_resource:
		return false

	_release_resource_slot()
	_resource_target = nearest_resource
	_move_to_resource_approach()
	return true


func _arrive_at_component_slot() -> void:
	_log(
		"_arrive_at_component_slot",
		"arrived at component slot",
		{"component": _node_name(_component_target), "slot": _slot_name(_component_slot)}
	)
	if not _is_current_component_interaction_valid():
		_warn(
			"_arrive_at_component_slot",
			"component slot is invalid on arrival",
			{"component": _node_name(_component_target), "slot": _slot_name(_component_slot)}
		)
		_complete_current_work_order()
		return

	if _component_target.has_method("activate_worker"):
		_log(
			"_arrive_at_component_slot",
			"activating worker on component",
			{"component": _component_target.name}
		)
		_component_target.activate_worker(self)
		_state = WorkState.COMPONENT_WORKING
		_stop_at_current_position()
		return

	_log(
		"_arrive_at_component_slot",
		"performing immediate component interaction",
		{"component": _component_target.name}
	)
	_component_target.perform_interaction(self)
	_complete_current_work_order()


func _is_resource_available(resource_node) -> bool:
	return (
		is_instance_valid(resource_node)
		and not resource_node.is_queued_for_deletion()
		and resource_node.resource_amount > 0
	)


func _is_component_interaction_valid(component) -> bool:
	return (
		is_instance_valid(component)
		and not component.is_queued_for_deletion()
		and component.has_method("is_interactable")
		and component.is_interactable()
	)


func _is_current_component_interaction_valid() -> bool:
	return (
		_is_component_interaction_valid(_component_target)
		and is_instance_valid(_component_slot)
		and _component_slot.occupant == self
	)


func _release_all_slots() -> void:
	_release_resource_slot()
	_release_component_slot()


func _release_resource_slot() -> void:
	if is_instance_valid(_resource_target) and _resource_slot >= 0:
		_resource_target.release_interaction_slot(self)
	_resource_slot = -1


func _release_component_slot() -> void:
	if is_instance_valid(_component_target):
		if _component_target.has_method("deactivate_worker"):
			_component_target.deactivate_worker(self)
		_component_target.release_interaction_slot(self)
	_component_target = null
	_component_slot = null


func _set_movement_target(world_position: Vector2) -> void:
	_target_position = world_position
	_has_target = true
	_set_navigation_stationary(false)
	navigation_agent.target_position = world_position


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
	if not is_node_ready():
		return
	if _backpack_amount <= 0:
		backpack_label.text = ""
	else:
		backpack_label.text = "%s %d/%d" % [
			String(_backpack_resource_type),
			_backpack_amount,
			backpack_capacity,
		]


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


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity if _has_target else Vector2.ZERO
	move_and_slide()


func _log(function_name: String, action: String, params: Dictionary = {}) -> void:
	if not debug_log:
		return
	var logger := get_node_or_null("/root/GameLogger")
	if logger and logger.has_method("log"):
		logger.log(self, function_name, action, params)
	else:
		print("[%s] %s | params: %s" % [function_name, action, params])


func _warn(function_name: String, action: String, params: Dictionary = {}) -> void:
	if not debug_log:
		return
	var logger := get_node_or_null("/root/GameLogger")
	if logger and logger.has_method("warn"):
		logger.warn(self, function_name, action, params)
	else:
		push_warning("[%s] %s | params: %s" % [function_name, action, params])


func _node_name(node: Node) -> String:
	if is_instance_valid(node):
		return node.name
	return "<invalid>"


func _slot_name(slot: Node) -> String:
	if is_instance_valid(slot):
		return slot.name
	return "<invalid>"


func _describe_work_order(order: VillagerWorkOrder) -> Dictionary:
	if order == null:
		return {"type": "<none>"}

	var description := {
		"type": order.get_type_name(),
		"is_looping": order.is_looping,
	}
	match order.type:
		VillagerWorkOrder.Type.MOVE:
			description["position"] = order.position
		VillagerWorkOrder.Type.GATHER:
			description["resource_type"] = String(order.resource_type)
			description["resource_target"] = _node_name(order.resource_target)
		VillagerWorkOrder.Type.INTERACT_STORAGE, VillagerWorkOrder.Type.WORK_COMPONENT:
			description["component"] = _node_name(order.component)
			description["slot"] = _slot_name(order.interaction_slot)
	return description
