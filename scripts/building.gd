class_name Building
extends Node2D

signal storage_changed(building: Building)

@export var accepted_resource_type: StringName = &"wood"
@export var max_storage := 20
@export var obstacle_size := Vector2(96.0, 96.0)
@export var interaction_clearance := 40.0

@onready var storage_label: Label = $StorageLabel

var stored_amount := 0


func _ready() -> void:
	_update_storage_label()


func accepts_resource(type: StringName) -> bool:
	return type == accepted_resource_type


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
	var direction := from_position - global_position
	if direction.is_zero_approx():
		direction = Vector2.DOWN

	var half_size := obstacle_size * 0.5
	if absf(direction.x) > absf(direction.y):
		return global_position + Vector2(
			signf(direction.x) * (half_size.x + interaction_clearance),
			0.0
		)

	return global_position + Vector2(
		0.0,
		signf(direction.y) * (half_size.y + interaction_clearance)
	)


func get_navigation_obstacle_size() -> Vector2:
	return obstacle_size


func _update_storage_label() -> void:
	storage_label.text = "木頭：%d/%d" % [stored_amount, max_storage]
