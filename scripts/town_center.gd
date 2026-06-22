class_name TownCenter
extends Node2D

@export var obstacle_size := Vector2(192.0, 128.0)
@export var immigrant_spawn_clearance := 64.0


func get_navigation_obstacle_size() -> Vector2:
	return obstacle_size


func get_immigrant_spawn_origin() -> Vector2:
	return global_position + Vector2(
		0.0,
		obstacle_size.y * 0.5 + immigrant_spawn_clearance
	)
