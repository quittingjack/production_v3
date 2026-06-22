class_name ResourceNode
extends InteractionSlotHost

signal depleted(resource_node: ResourceNode)

@export var resource_type: StringName = &"wood"
@export var resource_amount := 20

@onready var amount_label: Label = $AmountLabel

func _ready() -> void:
	super._ready()
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
	return super.get_interaction_position(from_position)


func get_approach_position(from_position: Vector2) -> Vector2:
	return get_nearest_approach_position(from_position)


func _update_amount_label() -> void:
	amount_label.text = "木頭：%d" % resource_amount
