class_name ImmigrationManager
extends Node

@export var immigration_interval := 60.0
@export var minimum_immigrants := 1
@export var maximum_immigrants := 5
@export var entrance_position := Vector2(-1280.0, 320.0)
@export var spawn_spacing := 48.0
@export var confirmation_duration := 3.0
@export var villager_scene: PackedScene
@export var villagers_path: NodePath
@export var building_manager_path: NodePath
@export var notification_label_path: NodePath

@onready var villagers: Node2D = get_node(villagers_path)
@onready var building_manager: Node = get_node(building_manager_path)
@onready var notification_label: Label = get_node(notification_label_path)

var _time_until_next_wave := 0.0
var _waiting_immigrants := 0
var _confirmation_time_left := 0.0
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	_time_until_next_wave = maxf(immigration_interval, 0.0)
	notification_label.hide()
	building_manager.building_completed.connect(_on_building_completed)


func _process(delta: float) -> void:
	if _waiting_immigrants > 0:
		_try_accept_waiting_immigrants()
		return

	if _confirmation_time_left > 0.0:
		_confirmation_time_left = maxf(_confirmation_time_left - delta, 0.0)
		if _confirmation_time_left <= 0.0:
			notification_label.hide()

	_time_until_next_wave = maxf(_time_until_next_wave - delta, 0.0)
	if _time_until_next_wave <= 0.0:
		_begin_immigration_wave()


func _begin_immigration_wave() -> void:
	var minimum := maxi(minimum_immigrants, 1)
	var maximum := maxi(maximum_immigrants, minimum)
	_waiting_immigrants = _random.randi_range(minimum, maximum)
	_confirmation_time_left = 0.0
	_update_waiting_notification()
	_try_accept_waiting_immigrants()


func _try_accept_waiting_immigrants() -> void:
	if _waiting_immigrants <= 0:
		return

	var vacant_houses := _get_vacant_houses()
	if vacant_houses.size() < _waiting_immigrants:
		_update_waiting_notification(vacant_houses.size())
		return

	var accepted_count := _waiting_immigrants
	for index in accepted_count:
		var villager := villager_scene.instantiate() as Villager
		if not villager:
			push_error("ImmigrationManager requires a Villager scene.")
			return
		villager.position = _get_spawn_position(index, accepted_count)
		villagers.add_child(villager)
		vacant_houses[index].assign_villager(villager)

	_waiting_immigrants = 0
	_time_until_next_wave = maxf(immigration_interval, 0.0)
	_confirmation_time_left = maxf(confirmation_duration, 0.0)
	notification_label.text = "%d 位移民已加入村莊" % accepted_count
	notification_label.show()


func _get_vacant_houses() -> Array[House]:
	var vacant_houses: Array[House] = []
	for node in get_tree().get_nodes_in_group(&"houses"):
		var house := node as House
		if house and house.is_vacant():
			vacant_houses.append(house)
	return vacant_houses


func _get_spawn_position(index: int, count: int) -> Vector2:
	var columns := mini(count, 3)
	var row := index / 3
	var column := index % 3
	var row_count := mini(columns, count - row * 3)
	var row_width := (row_count - 1) * spawn_spacing
	return entrance_position + Vector2(
		column * spawn_spacing - row_width * 0.5,
		row * spawn_spacing
	)


func _update_waiting_notification(vacant_count: int = -1) -> void:
	if vacant_count < 0:
		vacant_count = _get_vacant_houses().size()
	var missing_houses := maxi(_waiting_immigrants - vacant_count, 0)
	notification_label.text = "新移民：%d 人／尚缺 %d 棟房屋" % [
		_waiting_immigrants,
		missing_houses,
	]
	notification_label.show()


func _on_building_completed(building: Node2D) -> void:
	if building is House and _waiting_immigrants > 0:
		_try_accept_waiting_immigrants()
