extends Node2D
class_name BuildingComponent

signal slots_changed(component)

@export var collision_size := Vector2(64.0, 64.0):
	set(value):
		collision_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_sync_collision_shape()
		queue_redraw()

@export var interaction_size := Vector2(64.0, 64.0):
	set(value):
		interaction_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		queue_redraw()

@export var debug_draw := false:
	set(value):
		debug_draw = value
		queue_redraw()

@export_group("Debug Color")
@export var hover_color: Color = Color(1.0, 0.92, 0.25, 0.9)
@export var collision_color: Color = Color(0.35, 0.7, 1.0, 0.75)

var _slots: Array = []
var _is_hovered := false


func _ready() -> void:
	add_to_group(&"navigation_obstacles")
	_refresh_slots()
	_sync_collision_shape()


func is_interactable() -> bool:
	return false


func can_interact(_villager: Node) -> bool:
	return is_interactable() and has_available_interaction_slot(_villager)


func perform_interaction(_villager: Node) -> void:
	pass


func get_navigation_obstacle_size() -> Vector2:
	return collision_size


func contains_point(world_position: Vector2) -> bool:
	return Rect2(
		global_position - interaction_size * 0.5,
		interaction_size
	).has_point(world_position)


func set_hovered(value: bool) -> void:
	if _is_hovered == value:
		return
	_is_hovered = value
	queue_redraw()


func has_available_interaction_slot(occupant: Node = null) -> bool:
	_cleanup_slots()
	for slot in _slots:
		if slot.is_available(occupant):
			return true
	return false


func reserve_interaction_slot(
	occupant: Node,
	from_position: Vector2 = Vector2.ZERO
) -> Node:
	if not is_instance_valid(occupant):
		return null
	_cleanup_slots()

	for slot in _slots:
		if slot.occupant == occupant:
			return slot

	var nearest_slot: Node
	var nearest_distance := INF
	for slot in _slots:
		if not slot.is_available(occupant):
			continue
		var distance := from_position.distance_squared_to(
			slot.get_interaction_position()
		)
		if distance < nearest_distance:
			nearest_slot = slot
			nearest_distance = distance

	if nearest_slot and nearest_slot.reserve(occupant):
		slots_changed.emit(self)
		return nearest_slot
	return null


func release_interaction_slot(occupant: Node) -> void:
	for slot in _slots:
		slot.release(occupant)
	slots_changed.emit(self)


func get_interaction_slot_count() -> int:
	_refresh_slots()
	return _slots.size()


func get_interaction_slot_position(slot_index: int) -> Vector2:
	_refresh_slots()
	if _slots.is_empty():
		return global_position
	return _slots[posmod(slot_index, _slots.size())].get_interaction_position()


func _refresh_slots() -> void:
	_slots.clear()
	for child in get_children():
		if child.has_method("reserve") and child.has_method("release"):
			_slots.append(child)


func _cleanup_slots() -> void:
	_refresh_slots()
	for slot in _slots:
		if not is_instance_valid(slot.occupant):
			slot.occupant = null


func _sync_collision_shape() -> void:
	if not is_node_ready():
		return
	var collision_shape := get_node_or_null(
		"StaticBody2D/CollisionShape2D"
	) as CollisionShape2D
	if not collision_shape:
		return

	var rectangle_shape := collision_shape.shape as RectangleShape2D
	if not rectangle_shape:
		return
	if not rectangle_shape.resource_local_to_scene:
		rectangle_shape = rectangle_shape.duplicate() as RectangleShape2D
		rectangle_shape.resource_local_to_scene = true
		collision_shape.shape = rectangle_shape
	rectangle_shape.size = collision_size


func _draw() -> void:
	if _is_hovered:
		draw_rect(
			Rect2(-interaction_size * 0.5, interaction_size),
			Color(hover_color, 0.14),
			true
		)
		draw_rect(
			Rect2(-interaction_size * 0.5, interaction_size),
			hover_color,
			false,
			3.0
		)

	if not debug_draw:
		return
	draw_rect(
		Rect2(-collision_size * 0.5, collision_size),
		collision_color,
		false,
		2.0
	)
