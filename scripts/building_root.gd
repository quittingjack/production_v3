extends Node2D
class_name BuildingRoot

signal demolished(building)

@export var footprint_size := Vector2(96.0, 96.0)
@export var debug_draw_footprint := false
@export var hover_color: Color = Color(1.0, 0.92, 0.25, 0.9)

var _is_hovered := false


func _ready() -> void:
	add_to_group(&"buildings")
	add_to_group(&"building_roots")


func contains_point(world_position: Vector2) -> bool:
	return Rect2(
		global_position - footprint_size * 0.5,
		footprint_size
	).has_point(world_position)


func set_hovered(value: bool) -> void:
	if _is_hovered == value:
		return
	_is_hovered = value
	queue_redraw()


func demolish() -> void:
	demolished.emit(self)
	queue_free()


func _draw() -> void:
	if _is_hovered:
		draw_rect(
			Rect2(-footprint_size * 0.5, footprint_size),
			Color(hover_color, 0.08),
			true
		)
		draw_rect(
			Rect2(-footprint_size * 0.5, footprint_size),
			hover_color,
			false,
			3.0
		)
	if debug_draw_footprint:
		draw_rect(
			Rect2(-footprint_size * 0.5, footprint_size),
			Color(0.9, 0.65, 0.25, 0.85),
			false,
			2.0
		)
