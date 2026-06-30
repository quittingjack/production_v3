extends Node

@export var pause_label_path: NodePath

@onready var pause_label: Label = get_node_or_null(pause_label_path) as Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_pause_label()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"toggle_pause"):
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return

	get_tree().paused = not get_tree().paused
	_update_pause_label()
	get_viewport().set_input_as_handled()


func _update_pause_label() -> void:
	if pause_label:
		pause_label.visible = get_tree().paused
