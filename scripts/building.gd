class_name Building
extends InteractionSlotHost

signal storage_changed(building: Building)

@export var accepted_resource_type: StringName = &"wood"
@export var max_storage := 20

@onready var storage_label: Label = $StorageLabel

var stored_amount := 0


func _ready() -> void:
	super._ready()
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
	return super.get_interaction_position(from_position)


func get_approach_position(direction_index: int) -> Vector2:
	return get_approach_position_by_direction(direction_index)


func reserve_interaction_slot(occupant: Node, from_position: Vector2) -> int:
	if not has_storage_space():
		return -1
	return super.reserve_interaction_slot(occupant, from_position)


func _update_storage_label() -> void:
	storage_label.text = "木頭：%d/%d" % [stored_amount, max_storage]
