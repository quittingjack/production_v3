class_name Building
extends BuildableBuilding

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


func get_output_resource_type() -> StringName:
	return accepted_resource_type


func get_output_amount(type: StringName = &"") -> int:
	if type != &"" and type != accepted_resource_type:
		return 0
	return stored_amount


func take_output(type: StringName, amount: int) -> int:
	if type != accepted_resource_type or amount <= 0:
		return 0

	var taken := mini(amount, stored_amount)
	if taken <= 0:
		return 0

	stored_amount -= taken
	_update_storage_label()
	storage_changed.emit(self)
	return taken


func get_interaction_position(from_position: Vector2) -> Vector2:
	return super.get_interaction_position(from_position)


func get_approach_position(direction_index: int) -> Vector2:
	return get_approach_position_by_direction(direction_index)


func _update_storage_label() -> void:
	storage_label.text = "木頭：%d/%d" % [stored_amount, max_storage]
