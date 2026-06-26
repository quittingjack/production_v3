class_name InteractionSlot
extends Node2D

@export var debug_radius := 8.0

var occupant: Node


func is_available(for_occupant: Node = null) -> bool:
	return (
		not is_instance_valid(occupant)
		or occupant == for_occupant
	)


func reserve(new_occupant: Node) -> bool:
	if not is_instance_valid(new_occupant) or not is_available(new_occupant):
		return false
	occupant = new_occupant
	queue_redraw()
	return true


func release(releasing_occupant: Node) -> void:
	if occupant != releasing_occupant:
		return
	occupant = null
	queue_redraw()


func get_interaction_position() -> Vector2:
	return global_position


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := Color(0.25, 0.95, 0.45, 0.85)
	if is_instance_valid(occupant):
		color = Color(1.0, 0.62, 0.18, 0.9)
	draw_circle(Vector2.ZERO, debug_radius, color)
