class_name Villager
extends CharacterBody2D

signal selection_changed(villager: Villager, is_selected: bool)

const RADIUS := 32.0

@export var move_speed := 220.0
@export var arrival_distance := 3.0
@export var blocked_stop_time := 0.25

@onready var selection_highlight: Sprite2D = $SelectionHighlight

var _target_position := Vector2.ZERO
var _has_target := false
var _is_selected := false
var _blocked_time := 0.0


func _physics_process(delta: float) -> void:
	if not _has_target:
		velocity = Vector2.ZERO
		return

	var target_offset := _target_position - global_position
	var distance_to_target := target_offset.length()
	if distance_to_target <= arrival_distance:
		stop_moving()
		return

	velocity = target_offset.normalized() * minf(move_speed, distance_to_target / maxf(delta, 0.001))
	var position_before_move := global_position
	move_and_slide()

	var moved_distance := position_before_move.distance_to(global_position)
	var expected_distance := velocity.length() * delta
	if get_slide_collision_count() > 0 and moved_distance < minf(0.5, expected_distance * 0.1):
		_blocked_time += delta
		if _blocked_time >= blocked_stop_time:
			stop_moving()
	else:
		_blocked_time = 0.0


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
	_blocked_time = 0.0


func stop_moving() -> void:
	_has_target = false
	velocity = Vector2.ZERO
	_blocked_time = 0.0


func contains_point(world_position: Vector2) -> bool:
	return global_position.distance_squared_to(world_position) <= RADIUS * RADIUS
