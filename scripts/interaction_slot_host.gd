class_name InteractionSlotHost
extends Node2D

@export var obstacle_size := Vector2(64.0, 64.0):
	set(value):
		obstacle_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_request_slot_layout_rebuild()

@export var interaction_range_multiplier := 1.0:
	set(value):
		interaction_range_multiplier = maxf(value, 0.01)
		queue_redraw()

@export var interaction_clearance := 40.0:
	set(value):
		interaction_clearance = maxf(value, 0.0)
		_request_slot_layout_rebuild()

@export var approach_clearance := 136.0:
	set(value):
		approach_clearance = maxf(value, 0.0)
		_request_debug_redraw()

@export var interaction_slot_clearance := 64.0:
	set(value):
		interaction_slot_clearance = maxf(value, 0.0)
		_request_debug_redraw()

@export var interaction_slot_spacing := 64.0:
	set(value):
		interaction_slot_spacing = maxf(value, 1.0)
		_request_slot_layout_rebuild()

@export var debug_draw_interaction_slots := false:
	set(value):
		debug_draw_interaction_slots = value
		_request_debug_redraw()

@export_group("Debug Color")
@export var available_slot_color: Color = Color(0.25, 0.95, 0.4, 0.95)
@export var occupied_slot_color: Color = Color(1.0, 0.62, 0.18, 0.95)
@export var blocked_slot_color: Color = Color(1.0, 0.25, 0.25, 0.95)
@export var obstacle_color: Color = Color(0.35, 0.7, 1.0, 0.85)
@export var interaction_perimeter_color: Color = Color(0.3, 1.0, 0.75, 0.65)
@export var approach_perimeter_color: Color = Color(0.85, 0.45, 1.0, 0.65)
@export var hover_highlight_color: Color = Color(1.0, 0.92, 0.25, 0.9)

var _interaction_slot_positions: Array[Vector2] = []
var _interaction_slot_occupants: Array[Node] = []
var _slot_layout_ready := false
var _is_hovered := false


func _ready() -> void:
	_slot_layout_ready = true
	_sync_collision_shape()
	_rebuild_interaction_slots()
	set_process(debug_draw_interaction_slots)


func _process(_delta: float) -> void:
	queue_redraw()


func get_interaction_position(from_position: Vector2) -> Vector2:
	return get_interaction_slot_position(_get_nearest_slot_index(from_position))


func get_approach_position_by_direction(direction_index: int) -> Vector2:
	return _get_direction_position(direction_index, approach_clearance)


func get_nearest_approach_position(from_position: Vector2) -> Vector2:
	return get_approach_position_by_direction(
		_get_nearest_approach_direction(from_position)
	)


func is_within_approach_clearance(world_position: Vector2) -> bool:
	var local_position := to_local(world_position)
	var half_size := obstacle_size * 0.5
	var closest_point := Vector2(
		clampf(local_position.x, -half_size.x, half_size.x),
		clampf(local_position.y, -half_size.y, half_size.y)
	)
	return local_position.distance_squared_to(closest_point) <= (
		approach_clearance * approach_clearance
	)


func has_available_interaction_slot(occupant: Node = null) -> bool:
	_cleanup_interaction_slots()
	for slot_index in _interaction_slot_occupants.size():
		if _interaction_slot_occupants[slot_index] == occupant:
			return true
		if is_instance_valid(_interaction_slot_occupants[slot_index]):
			continue
		if _is_interaction_slot_clear(
			get_interaction_slot_position(slot_index),
			occupant
		):
			return true
	return false


func reserve_interaction_slot(
	occupant: Node,
	from_position: Vector2,
	minimum_empty_slots := 0
) -> int:
	if not is_instance_valid(occupant):
		return -1

	_cleanup_interaction_slots()
	for slot_index in _interaction_slot_occupants.size():
		if _interaction_slot_occupants[slot_index] == occupant:
			return slot_index

	var available_slot_count := 0
	for slot_index in _interaction_slot_occupants.size():
		if is_instance_valid(_interaction_slot_occupants[slot_index]):
			continue
		if _is_interaction_slot_clear(
			get_interaction_slot_position(slot_index),
			occupant
		):
			available_slot_count += 1
	if available_slot_count <= maxi(minimum_empty_slots, 0):
		return -1

	var nearest_slot := -1
	var nearest_distance := INF
	for slot_index in _interaction_slot_occupants.size():
		if is_instance_valid(_interaction_slot_occupants[slot_index]):
			continue

		var slot_position := get_interaction_slot_position(slot_index)
		if not _is_interaction_slot_clear(slot_position, occupant):
			continue

		var distance := from_position.distance_squared_to(slot_position)
		if distance < nearest_distance:
			nearest_slot = slot_index
			nearest_distance = distance

	if nearest_slot >= 0:
		_interaction_slot_occupants[nearest_slot] = occupant
		queue_redraw()
	return nearest_slot


func release_interaction_slot(occupant: Node) -> void:
	for slot_index in _interaction_slot_occupants.size():
		if _interaction_slot_occupants[slot_index] == occupant:
			_interaction_slot_occupants[slot_index] = null
	queue_redraw()


func get_interaction_slot_position(slot_index: int) -> Vector2:
	if _interaction_slot_positions.is_empty():
		return global_position
	return to_global(
		_interaction_slot_positions[posmod(slot_index, _interaction_slot_positions.size())]
	)


func get_interaction_slot_count() -> int:
	return _interaction_slot_positions.size()


func get_navigation_obstacle_size() -> Vector2:
	return obstacle_size


func get_interaction_size() -> Vector2:
	return obstacle_size * interaction_range_multiplier


func contains_point(world_position: Vector2) -> bool:
	var interaction_size := get_interaction_size()
	var rect := Rect2(
		global_position - interaction_size * 0.5,
		interaction_size
	)
	return rect.has_point(world_position)


func set_hovered(value: bool) -> void:
	if _is_hovered == value:
		return
	_is_hovered = value
	queue_redraw()


func _request_slot_layout_rebuild() -> void:
	if not _slot_layout_ready:
		return
	_sync_collision_shape()
	_rebuild_interaction_slots()
	_notify_navigation_changed()


func _rebuild_interaction_slots() -> void:
	var old_positions: Array[Vector2] = _interaction_slot_positions.duplicate()
	var old_occupants: Array[Node] = _interaction_slot_occupants.duplicate()
	_interaction_slot_positions = _generate_interaction_slot_positions()
	_interaction_slot_occupants.clear()
	_interaction_slot_occupants.resize(_interaction_slot_positions.size())

	var claimed_slots: Array[int] = []
	for old_index in old_occupants.size():
		var occupant: Node = old_occupants[old_index]
		if not is_instance_valid(occupant):
			continue

		var old_position := Vector2.ZERO
		if old_index < old_positions.size():
			old_position = old_positions[old_index]
		var new_index := _find_nearest_unclaimed_slot(old_position, claimed_slots)
		if new_index >= 0:
			_interaction_slot_occupants[new_index] = occupant
			claimed_slots.append(new_index)
		_notify_occupant_slot_rebuilt(occupant, new_index)

	queue_redraw()


func _generate_interaction_slot_positions() -> Array[Vector2]:
	var half_extents := obstacle_size * 0.5 + Vector2.ONE * interaction_clearance
	var perimeter := 4.0 * (half_extents.x + half_extents.y)
	var slot_count := maxi(4, ceili(perimeter / interaction_slot_spacing))
	var slot_step := perimeter / float(slot_count)
	var positions: Array[Vector2] = []

	for slot_index in slot_count:
		var perimeter_distance := (float(slot_index) + 0.5) * slot_step
		positions.append(_point_on_rectangle_perimeter(half_extents, perimeter_distance))

	return positions


func _point_on_rectangle_perimeter(
	half_extents: Vector2,
	perimeter_distance: float
) -> Vector2:
	var width := half_extents.x * 2.0
	var height := half_extents.y * 2.0
	var distance := fposmod(
		perimeter_distance,
		2.0 * (width + height)
	)

	if distance < width:
		return Vector2(-half_extents.x + distance, -half_extents.y)
	distance -= width
	if distance < height:
		return Vector2(half_extents.x, -half_extents.y + distance)
	distance -= height
	if distance < width:
		return Vector2(half_extents.x - distance, half_extents.y)
	distance -= width
	return Vector2(-half_extents.x, half_extents.y - distance)


func _find_nearest_unclaimed_slot(
	old_position: Vector2,
	claimed_slots: Array[int]
) -> int:
	var nearest_slot := -1
	var nearest_distance := INF
	for slot_index in _interaction_slot_positions.size():
		if claimed_slots.has(slot_index):
			continue
		var distance := old_position.distance_squared_to(
			_interaction_slot_positions[slot_index]
		)
		if distance < nearest_distance:
			nearest_slot = slot_index
			nearest_distance = distance
	return nearest_slot


func _notify_occupant_slot_rebuilt(occupant: Node, new_slot_index: int) -> void:
	if occupant.has_method("on_interaction_slots_rebuilt"):
		occupant.call_deferred(
			"on_interaction_slots_rebuilt",
			self,
			new_slot_index
		)


func _get_nearest_slot_index(from_position: Vector2) -> int:
	var nearest_slot := 0
	var nearest_distance := INF
	for slot_index in _interaction_slot_positions.size():
		var distance := from_position.distance_squared_to(
			get_interaction_slot_position(slot_index)
		)
		if distance < nearest_distance:
			nearest_slot = slot_index
			nearest_distance = distance
	return nearest_slot


func _get_nearest_approach_direction(from_position: Vector2) -> int:
	var nearest_direction := 0
	var nearest_distance := INF
	for direction_index in 4:
		var distance := from_position.distance_squared_to(
			get_approach_position_by_direction(direction_index)
		)
		if distance < nearest_distance:
			nearest_direction = direction_index
			nearest_distance = distance
	return nearest_direction


func _get_direction_position(
	direction_index: int,
	clearance: float
) -> Vector2:
	var half_size := obstacle_size * 0.5
	match posmod(direction_index, 4):
		0:
			return to_global(Vector2(-(half_size.x + clearance), 0.0))
		1:
			return to_global(Vector2(half_size.x + clearance, 0.0))
		2:
			return to_global(Vector2(0.0, -(half_size.y + clearance)))
		_:
			return to_global(Vector2(0.0, half_size.y + clearance))


func _cleanup_interaction_slots() -> void:
	for slot_index in _interaction_slot_occupants.size():
		if not is_instance_valid(_interaction_slot_occupants[slot_index]):
			_interaction_slot_occupants[slot_index] = null


func _is_interaction_slot_clear(
	slot_position: Vector2,
	occupant: Node
) -> bool:
	var clearance_squared := interaction_slot_clearance * interaction_slot_clearance
	for node in get_tree().get_nodes_in_group(&"villagers"):
		var villager := node as Villager
		if not villager or villager == occupant:
			continue
		if villager.global_position.distance_squared_to(slot_position) < clearance_squared:
			return false
	return true


func _sync_collision_shape() -> void:
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
	rectangle_shape.size = obstacle_size


func _notify_navigation_changed() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(&"building_managers"):
		node.call_deferred("request_navigation_rebuild")


func _request_debug_redraw() -> void:
	if not is_inside_tree():
		return
	set_process(debug_draw_interaction_slots)
	queue_redraw()


func _draw() -> void:
	if _is_hovered:
		var half_interaction_size := get_interaction_size() * 0.5
		draw_rect(
			Rect2(-half_interaction_size, get_interaction_size()),
			Color(hover_highlight_color, 0.12),
			true
		)
		_draw_rectangle_outline(
			half_interaction_size,
			hover_highlight_color,
			3.0
		)

	if not debug_draw_interaction_slots:
		return

	_draw_rectangle_outline(obstacle_size * 0.5, obstacle_color, 2.0)
	_draw_rectangle_outline(
		obstacle_size * 0.5 + Vector2.ONE * interaction_clearance,
		interaction_perimeter_color,
		2.0
	)
	_draw_rectangle_outline(
		obstacle_size * 0.5 + Vector2.ONE * approach_clearance,
		approach_perimeter_color,
		2.0
	)

	for direction_index in 4:
		draw_circle(
			to_local(get_approach_position_by_direction(direction_index)),
			5.0,
			approach_perimeter_color
		)

	var font := ThemeDB.fallback_font
	for slot_index in _interaction_slot_positions.size():
		var slot_color := available_slot_color
		if is_instance_valid(_interaction_slot_occupants[slot_index]):
			slot_color = occupied_slot_color
		elif not _is_interaction_slot_clear(
			get_interaction_slot_position(slot_index),
			null
		):
			slot_color = blocked_slot_color

		var slot_position := _interaction_slot_positions[slot_index]
		draw_circle(slot_position, 6.0, slot_color)
		draw_string(
			font,
			slot_position + Vector2(8.0, -8.0),
			str(slot_index),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			12,
			slot_color
		)


func _draw_rectangle_outline(
	half_extents: Vector2,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array([
		Vector2(-half_extents.x, -half_extents.y),
		Vector2(half_extents.x, -half_extents.y),
		Vector2(half_extents.x, half_extents.y),
		Vector2(-half_extents.x, half_extents.y),
		Vector2(-half_extents.x, -half_extents.y),
	])
	draw_polyline(points, color, width, true)
