extends PanelContainer

@export var selection_manager_path: NodePath

@onready var villager_name_label: Label = %VillagerNameLabel
@onready var state_value_label: Label = %StateValueLabel
@onready var stationary_value_label: Label = %StationaryValueLabel
@onready var command_list: VBoxContainer = %CommandList
@onready var empty_queue_label: Label = %EmptyQueueLabel

var _selection_manager: Node


func _ready() -> void:
	_selection_manager = get_node(selection_manager_path)
	visible = false


func _process(_delta: float) -> void:
	var villagers: Array[Villager] = _selection_manager.get_selected_villagers()
	if villagers.is_empty():
		visible = false
		_clear_command_rows()
		return

	visible = true
	if villagers.size() == 1:
		var villager := villagers[0]
		villager_name_label.text = villager.name
		state_value_label.text = villager.get_state_name()
		stationary_value_label.text = str(villager.is_stationary())
		_rebuild_command_rows(villager)
	else:
		villager_name_label.text = "已選擇 %d 位村民" % villagers.size()
		state_value_label.text = "MULTIPLE"
		stationary_value_label.text = "-"
		_clear_command_rows()
		empty_queue_label.visible = true
		empty_queue_label.text = "多選時不顯示序列"


func _rebuild_command_rows(villager: Villager) -> void:
	_clear_command_rows()
	var orders := villager.get_work_queue_snapshot()
	empty_queue_label.visible = orders.is_empty()
	empty_queue_label.text = "沒有命令"
	if orders.is_empty():
		return

	var current_index := villager.get_current_work_index()
	for index in orders.size():
		var order := orders[index]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(0.0, 28.0)

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = _format_order_label(order, index == current_index)
		label.clip_text = true
		row.add_child(label)

		var cancel_button := Button.new()
		cancel_button.text = "X"
		cancel_button.custom_minimum_size = Vector2(28.0, 28.0)
		cancel_button.pressed.connect(_on_cancel_order_pressed.bind(villager, index))
		row.add_child(cancel_button)

		command_list.add_child(row)


func _format_order_label(order: VillagerWorkOrder, is_current: bool) -> String:
	var parts: Array[String] = []
	if is_current:
		parts.append(">")
	if order.is_looping:
		parts.append("[循環]")
	parts.append(order.get_display_name())
	return " ".join(parts)


func _clear_command_rows() -> void:
	for child in command_list.get_children():
		child.queue_free()


func _on_cancel_order_pressed(villager: Villager, order_index: int) -> void:
	if is_instance_valid(villager):
		villager.cancel_work_order_at(order_index)
