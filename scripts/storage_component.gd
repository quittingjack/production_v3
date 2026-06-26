extends "res://scripts/building_component.gd"
class_name StorageComponent

signal storage_changed(storage)

@export var resource_type: StringName = &"wood"
@export var capacity := 20:
	set(value):
		capacity = maxi(value, 0)
		stored_amount = mini(stored_amount, capacity)
		_update_label()

@export var allow_deposit := true
@export var allow_take := true
@export var label_path: NodePath = ^"AmountLabel"

var stored_amount := 0


func _ready() -> void:
	super._ready()
	add_to_group(&"interactable_components")
	_update_label()


func is_interactable() -> bool:
	return true


func can_interact(villager: Node) -> bool:
	if not super.can_interact(villager):
		return false
	if not is_instance_valid(villager):
		return false
	if villager.get_backpack_amount() > 0:
		return (
			allow_deposit
			and accepts_resource(villager.get_backpack_resource_type())
			and has_storage_space()
		)
	return allow_take and get_output_amount(resource_type) > 0


func perform_interaction(villager: Node) -> void:
	if not is_instance_valid(villager):
		return
	if villager.get_backpack_amount() > 0:
		villager.deposit_backpack_to_storage(self)
	else:
		villager.take_from_storage(self)


func accepts_resource(type: StringName) -> bool:
	return type == resource_type


func has_storage_space() -> bool:
	return stored_amount < capacity


func store_resource(type: StringName, amount: int) -> int:
	if not allow_deposit or not accepts_resource(type) or amount <= 0:
		return 0
	var stored := mini(amount, capacity - stored_amount)
	if stored <= 0:
		return 0
	stored_amount += stored
	_update_label()
	storage_changed.emit(self)
	return stored


func get_output_resource_type() -> StringName:
	return resource_type if allow_take else &""


func get_output_amount(type: StringName = &"") -> int:
	if not allow_take:
		return 0
	if type != &"" and type != resource_type:
		return 0
	return stored_amount


func take_output(type: StringName, amount: int) -> int:
	if not allow_take or type != resource_type or amount <= 0:
		return 0
	var taken := mini(amount, stored_amount)
	if taken <= 0:
		return 0
	stored_amount -= taken
	_update_label()
	storage_changed.emit(self)
	return taken


func force_store_output(amount: int) -> int:
	if amount <= 0:
		return 0
	var stored := mini(amount, capacity - stored_amount)
	if stored <= 0:
		return 0
	stored_amount += stored
	_update_label()
	storage_changed.emit(self)
	return stored


func force_take_input(amount: int) -> int:
	if amount <= 0:
		return 0
	var taken := mini(amount, stored_amount)
	if taken <= 0:
		return 0
	stored_amount -= taken
	_update_label()
	storage_changed.emit(self)
	return taken


func _update_label() -> void:
	if not is_node_ready():
		return
	var label := get_node_or_null(label_path) as Label
	if not label:
		return
	label.text = "%s：%d/%d" % [
		String(resource_type),
		stored_amount,
		capacity,
	]
