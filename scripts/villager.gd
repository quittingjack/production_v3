class_name Villager
extends CharacterBody2D

signal selection_changed(villager: Villager, is_selected: bool)

const RADIUS := 32.0

@export var move_speed := 220.0
@export var arrival_distance := 3.0

@onready var selection_highlight: Sprite2D = $SelectionHighlight
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D

var _target_position := Vector2.ZERO
var _has_target := false
var _is_selected := false


func _physics_process(delta: float) -> void:
	if not _has_target:
		velocity = Vector2.ZERO
		return

	if navigation_agent.is_navigation_finished():
		stop_moving()
		return

	var next_path_position := navigation_agent.get_next_path_position()
	var target_offset := next_path_position - global_position
	if target_offset.length() <= arrival_distance:
		velocity = Vector2.ZERO
		return

	velocity = target_offset.normalized() * minf(
		move_speed,
		target_offset.length() / maxf(delta, 0.001)
	)
	move_and_slide()


func set_selected(value: bool) -> void:
	if _is_selected == value:
		return

	_is_selected = value
	selection_highlight.visible = value
	selection_changed.emit(self, value)


func is_selected() -> bool:
	return _is_selected


func move_to(world_position: Vector2) -> void:
	_target_position = world_position
	_has_target = true
	navigation_agent.target_position = world_position


func refresh_navigation_target() -> void:
	if _has_target:
		navigation_agent.target_position = _target_position


func stop_moving() -> void:
	_has_target = false
	velocity = Vector2.ZERO


func contains_point(world_position: Vector2) -> bool:
	return global_position.distance_squared_to(world_position) <= RADIUS * RADIUS
