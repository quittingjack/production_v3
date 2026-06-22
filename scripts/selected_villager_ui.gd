extends PanelContainer

@export var selection_manager_path: NodePath

@onready var villager_name_label: Label = %VillagerNameLabel
@onready var state_value_label: Label = %StateValueLabel
@onready var stationary_value_label: Label = %StationaryValueLabel
@onready var create_haul_button: Button = %CreateHaulButton

var _selection_manager: Node


func _ready() -> void:
	_selection_manager = get_node(selection_manager_path)
	create_haul_button.pressed.connect(
		_selection_manager.begin_haul_planning
	)
	visible = false


func _process(_delta: float) -> void:
	var villagers: Array[Villager] = _selection_manager.get_selected_villagers()
	if villagers.is_empty():
		visible = false
		return

	visible = true
	create_haul_button.disabled = _selection_manager.is_haul_planning()
	if villagers.size() == 1:
		var villager := villagers[0]
		villager_name_label.text = villager.name
		state_value_label.text = villager.get_state_name()
		stationary_value_label.text = str(villager.is_stationary())
	else:
		villager_name_label.text = "已選擇 %d 位村民" % villagers.size()
		state_value_label.text = "MULTIPLE"
		stationary_value_label.text = "-"
