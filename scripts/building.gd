class_name Building
extends Node2D

signal storage_changed(building: Building)

@export var accepted_resource_type: StringName = &"wood"
@export var max_storage := 20
@export var obstacle_size := Vector2(96.0, 96.0)
@export var interaction_clearance := 40.0
@export var approach_clearance := 136.0
@export var interaction_slot_clearance := 64.0

@onready var storage_label: Label = $StorageLabel

var stored_amount := 0
var _interaction_slot_occupants: Array[Node] = []


func _ready() -> void:
	_interaction_slot_occupants.resize(4)
	_update_storage_label()


func accepts_resource(type: StringName) -> bool:
	return type == accepted_resource_type


func has_storage_space() -> bool:
	return stored_amount < max_storage


func store_resource(type: StringName, amount: int) -> int:
	if not accepts_resource(type) or amount <= 0:
		return 0

	var stored := mini(amount, max_storage - stored_amount)
	if stored <= 0:
		return 0

	stored_amount += stored
	_update_storage_label()
	storage_changed.emit(self)
	return stored


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
	if not is_instance_valid(occupant) or not has_storage_space():
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


func get_navigation_obstacle_size() -> Vector2:
	return obstacle_size


func _update_storage_label() -> void:
	storage_label.text = "木頭：%d/%d" % [stored_amount, max_storage]


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
