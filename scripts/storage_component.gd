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
@export var debug_log := false
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
		_log(
			"can_interact",
			"interaction rejected by base validation",
			{"villager": _node_name(villager)}
		)
		return false
	if not is_instance_valid(villager):
		_warn("can_interact", "interaction rejected because villager is invalid")
		return false
	if villager.get_backpack_amount() > 0:
		if accepts_resource(villager.get_backpack_resource_type()):
			var can_deposit := allow_deposit and has_storage_space()
			if not can_deposit:
				_log(
					"can_interact",
					"interaction rejected for deposit branch",
					{
						"villager": villager.name,
						"allow_deposit": allow_deposit,
						"has_storage_space": has_storage_space(),
						"stored_amount": stored_amount,
						"capacity": capacity,
					}
				)
				return false
			_log(
				"can_interact",
				"interaction accepted for deposit branch",
				{"villager": villager.name, "backpack_amount": villager.get_backpack_amount()}
			)
			return true

		var can_replace_backpack := allow_take and get_output_amount(resource_type) > 0
		if not can_replace_backpack:
			_log(
				"can_interact",
				"interaction rejected for discard-and-take branch",
				{
					"villager": villager.name,
					"allow_take": allow_take,
					"available_output": get_output_amount(resource_type),
				}
			)
			return false
		_log(
			"can_interact",
			"interaction accepted for discard-and-take branch",
			{
				"villager": villager.name,
				"backpack_type": String(villager.get_backpack_resource_type()),
				"output_type": String(resource_type),
			}
		)
		return true

	var can_take := allow_take and get_output_amount(resource_type) > 0
	if can_take:
		_log(
			"can_interact",
			"interaction accepted for take branch",
			{"villager": villager.name, "available_output": get_output_amount(resource_type)}
		)
		return true

	var can_deposit_later := allow_deposit and has_storage_space()
	if can_deposit_later:
		_log(
			"can_interact",
			"interaction accepted for empty-backpack deposit branch",
			{
				"villager": villager.name,
				"stored_amount": stored_amount,
				"capacity": capacity,
			}
		)
		return true

	_log(
		"can_interact",
		"interaction rejected for empty-backpack branch",
		{
			"villager": villager.name,
			"allow_deposit": allow_deposit,
			"allow_take": allow_take,
			"has_storage_space": has_storage_space(),
			"available_output": get_output_amount(resource_type),
		}
	)
	return false


func perform_interaction(villager: Node) -> void:
	if not is_instance_valid(villager):
		_warn("perform_interaction", "skip interaction because villager is invalid")
		return
	_log(
		"perform_interaction",
		"begin storage interaction",
		{
			"villager": villager.name,
			"backpack_amount": villager.get_backpack_amount(),
			"backpack_type": String(villager.get_backpack_resource_type()),
			"stored_amount": stored_amount,
		}
	)
	if villager.get_backpack_amount() > 0:
		if accepts_resource(villager.get_backpack_resource_type()):
			_log(
				"perform_interaction",
				"deposit branch selected",
				{"villager": villager.name, "resource_type": String(resource_type)}
			)
			villager.deposit_backpack_to_storage(self)
			return
		if villager.has_method("discard_backpack"):
			_log(
				"perform_interaction",
				"discard backpack before taking output",
				{
					"villager": villager.name,
					"backpack_type": String(villager.get_backpack_resource_type()),
					"output_type": String(resource_type),
				}
			)
			villager.discard_backpack()
	_log(
		"perform_interaction",
		"take branch selected",
		{"villager": villager.name, "output_type": String(resource_type)}
	)
	villager.take_from_storage(self)


func accepts_resource(type: StringName) -> bool:
	return type == resource_type


func has_storage_space() -> bool:
	return stored_amount < capacity


func store_resource(type: StringName, amount: int) -> int:
	if not allow_deposit:
		_log(
			"store_resource",
			"reject deposit because storage does not allow deposits",
			{"resource_type": String(type), "amount": amount}
		)
		return 0
	if not accepts_resource(type):
		_log(
			"store_resource",
			"reject deposit because resource type is not accepted",
			{
				"resource_type": String(type),
				"accepted_type": String(resource_type),
				"amount": amount,
			}
		)
		return 0
	if amount <= 0:
		_log("store_resource", "reject deposit because amount is not positive", {"amount": amount})
		return 0
	var stored := mini(amount, capacity - stored_amount)
	if stored <= 0:
		_log(
			"store_resource",
			"reject deposit because storage is full",
			{"stored_amount": stored_amount, "capacity": capacity}
		)
		return 0
	stored_amount += stored
	_update_label()
	storage_changed.emit(self)
	_log(
		"store_resource",
		"stored resource",
		{
			"resource_type": String(type),
			"requested_amount": amount,
			"stored": stored,
			"stored_amount": stored_amount,
			"capacity": capacity,
		}
	)
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
	if not allow_take:
		_log(
			"take_output",
			"reject take because storage does not allow output",
			{"resource_type": String(type), "amount": amount}
		)
		return 0
	if type != resource_type:
		_log(
			"take_output",
			"reject take because resource type does not match output",
			{
				"resource_type": String(type),
				"output_type": String(resource_type),
				"amount": amount,
			}
		)
		return 0
	if amount <= 0:
		_log("take_output", "reject take because amount is not positive", {"amount": amount})
		return 0
	var taken := mini(amount, stored_amount)
	if taken <= 0:
		_log(
			"take_output",
			"reject take because storage is empty",
			{"stored_amount": stored_amount}
		)
		return 0
	stored_amount -= taken
	_update_label()
	storage_changed.emit(self)
	_log(
		"take_output",
		"took resource from storage",
		{
			"resource_type": String(type),
			"requested_amount": amount,
			"taken": taken,
			"stored_amount": stored_amount,
		}
	)
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
