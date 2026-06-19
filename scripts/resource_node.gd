class_name ResourceNode
extends Node2D

signal depleted(resource_node: ResourceNode)

@export var resource_type: StringName = &"wood"
@export var resource_amount := 20
@export var obstacle_size := Vector2(64.0, 64.0)
@export var interaction_clearance := 40.0

@onready var amount_label: Label = $AmountLabel


func _ready() -> void:
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


func _update_amount_label() -> void:
	amount_label.text = "木頭：%d" % resource_amount


func _notify_navigation_changed() -> void:
	for node in get_tree().get_nodes_in_group(&"building_managers"):
		node.call_deferred("request_navigation_rebuild")
