class_name ResourceNode
extends Node2D

signal depleted(resource_node: ResourceNode)

@export var resource_type: StringName = &"wood"
@export var resource_amount := 20
@export var obstacle_size := Vector2(64.0, 64.0)
@export var interaction_clearance := 40.0
@export var approach_clearance := 136.0
@export var interaction_slot_clearance := 64.0

@onready var amount_label: Label = $AmountLabel

var _interaction_slot_occupants: Array[Node] = []


func _ready() -> void:
	_interaction_slot_occupants.resize(4)
	_update_amount_label()


func take_resource(amount: int) -> int:
	if amount <= 0 or resource_amount <= 0:
		return 0

	var taken := mini(amount, resource_amount)
	resource_amount -= taken
	_update_amount_label()

	if resource_amount <= 0:
		depleted.emit(self)
		_notify_navigation_changed()
		queue_free()

	return taken


func contains_point(world_position: Vector2) -> bool:
	var resource_rect := Rect2(
		global_position - obstacle_size * 0.5,
		obstacle_size
	)
	return resource_rect.has_point(world_position)


func get_interaction_position(from_position: Vector2) -> Vector2:
	return get_interaction_slot_position(_get_nearest_direction(from_position))


func get_approach_position(direction_index: int) -> Vector2:
	return _get_direction_position(direction_index, approach_clearance)


func has_available_interaction_slot(occupant: Node = null) -> bool:
	_cleanup_interaction_slots()
	for slot_index in _interaction_slot_occupants.size():
		if _interaction_slot_occupants[slot_index] == occupant:
			return true
		if is_instance_valid(_interaction_slot_occupants[slot_index]):
			continue
		if _is_interaction_slot_clear(
			get_interaction_slot_position(slot_index),
			occupant
		):
			return true
	return false


func reserve_interaction_slot(occupant: Node, from_position: Vector2) -> int:
	if not is_instance_valid(occupant):
		return -1

	_cleanup_interaction_slots()
	for slot_index in _interaction_slot_occupants.size():
		if _interaction_slot_occupants[slot_index] == occupant:
			return slot_index

	var nearest_slot := -1
	var nearest_distance := INF
	for slot_index in _interaction_slot_occupants.size():
		if is_instance_valid(_interaction_slot_occupants[slot_index]):
			continue

		var slot_position := get_interaction_slot_position(slot_index)
		if not _is_interaction_slot_clear(slot_position, occupant):
			continue

		var distance := from_position.distance_squared_to(slot_position)
		if distance < nearest_distance:
			nearest_slot = slot_index
			nearest_distance = distance

	if nearest_slot >= 0:
		_interaction_slot_occupants[nearest_slot] = occupant
	return nearest_slot


func release_interaction_slot(occupant: Node) -> void:
	for slot_index in _interaction_slot_occupants.size():
		if _interaction_slot_occupants[slot_index] == occupant:
			_interaction_slot_occupants[slot_index] = null


func get_interaction_slot_position(slot_index: int) -> Vector2:
	return _get_direction_position(slot_index, interaction_clearance)


func _get_direction_position(
	direction_index: int,
	clearance: float
) -> Vector2:
	var half_size := obstacle_size * 0.5
	match posmod(direction_index, 4):
		0:
			return global_position + Vector2(
				-(half_size.x + clearance),
				0.0
			)
		1:
			return global_position + Vector2(
				half_size.x + clearance,
				0.0
			)
		2:
			return global_position + Vector2(
				0.0,
				-(half_size.y + clearance)
			)
		_:
			return global_position + Vector2(
				0.0,
				half_size.y + clearance
			)


func _get_nearest_direction(from_position: Vector2) -> int:
	var nearest_direction := 0
	var nearest_distance := INF
	for direction_index in 4:
		var slot_position := get_interaction_slot_position(direction_index)
		var distance := from_position.distance_squared_to(slot_position)
		if distance < nearest_distance:
			nearest_direction = direction_index
			nearest_distance = distance
	return nearest_direction


func get_navigation_obstacle_size() -> Vector2:
	return obstacle_size


func _update_amount_label() -> void:
	amount_label.text = "木頭：%d" % resource_amount


func _notify_navigation_changed() -> void:
	for node in get_tree().get_nodes_in_group(&"building_managers"):
		node.call_deferred("request_navigation_rebuild")


func _cleanup_interaction_slots() -> void:
	for slot_index in _interaction_slot_occupants.size():
		if not is_instance_valid(_interaction_slot_occupants[slot_index]):
			_interaction_slot_occupants[slot_index] = null


func _is_interaction_slot_clear(
	slot_position: Vector2,
	occupant: Node
) -> bool:
	var clearance_squared := interaction_slot_clearance * interaction_slot_clearance
	for node in get_tree().get_nodes_in_group(&"villagers"):
		var villager := node as Villager
		if not villager or villager == occupant:
			continue
		if villager.global_position.distance_squared_to(slot_position) < clearance_squared:
			return false
	return true
