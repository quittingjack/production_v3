extends PanelContainer

@export var selection_manager_path: NodePath

@onready var villager_name_label: Label = %VillagerNameLabel
@onready var state_value_label: Label = %StateValueLabel

var _selection_manager: Node


func _ready() -> void:
	_selection_manager = get_node(selection_manager_path)
	visible = false


func _process(_delta: float) -> void:
	var villager := (
		_selection_manager.get_single_selected_villager() as Villager
	)
	if not villager:
		visible = false
		return

	visible = true
	villager_name_label.text = villager.name
	state_value_label.text = villager.get_state_name()
