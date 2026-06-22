class_name ConstructionSite
extends Building

signal construction_completed(
	site: ConstructionSite,
	target_scene: PackedScene
)

@onready var site_body: Polygon2D = $SiteBody
@onready var status_label: Label = $StatusLabel

var target_scene: PackedScene
var _is_constructing := false
var _construction_time_left := 0.0


func initialize(
	scene: PackedScene,
	building_size: Vector2,
	resource_type: StringName,
	material_amount: int,
	duration: float
) -> void:
	target_scene = scene
	obstacle_size = building_size
	construction_resource_type = resource_type
	construction_material_amount = maxi(material_amount, 0)
	accepted_resource_type = resource_type
	max_storage = construction_material_amount
	construction_duration = maxf(duration, 0.0)

	if is_node_ready():
		_apply_site_size(building_size)
		_update_storage_label()


func _ready() -> void:
	super._ready()
	_apply_site_size(obstacle_size)
	set_process(true)
	_try_start_construction()


func _process(delta: float) -> void:
	if not _is_constructing:
		return

	_construction_time_left = maxf(_construction_time_left - delta, 0.0)
	_update_storage_label()
	if _construction_time_left <= 0.0:
		set_process(false)
		construction_completed.emit(self, target_scene)


func has_storage_space() -> bool:
	return not _is_constructing and super.has_storage_space()


func store_resource(type: StringName, amount: int) -> int:
	if _is_constructing:
		return 0
	var stored := super.store_resource(type, amount)
	_try_start_construction()
	return stored


func get_output_resource_type() -> StringName:
	return &""


func get_output_amount(_type: StringName = &"") -> int:
	return 0


func take_output(_type: StringName, _amount: int) -> int:
	return 0


func is_constructing() -> bool:
	return _is_constructing


func get_construction_progress() -> float:
	if not _is_constructing:
		return 0.0
	var duration := maxf(construction_duration, 0.001)
	return clampf(1.0 - _construction_time_left / duration, 0.0, 1.0)


func _try_start_construction() -> void:
	if _is_constructing or stored_amount < max_storage:
		return

	stored_amount = 0
	_is_constructing = true
	_construction_time_left = maxf(construction_duration, 0.0)
	storage_changed.emit(self)
	_update_storage_label()
	if _construction_time_left <= 0.0:
		call_deferred("_complete_immediately")


func _complete_immediately() -> void:
	if _is_constructing and is_inside_tree():
		construction_completed.emit(self, target_scene)


func _apply_site_size(building_size: Vector2) -> void:
	if not is_instance_valid(site_body):
		return
	var half_size := building_size * 0.5
	site_body.polygon = PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
	])


func _update_storage_label() -> void:
	if not is_node_ready():
		return
	if _is_constructing:
		storage_label.text = ""
		status_label.text = "施工中：%.1fs" % _construction_time_left
	else:
		storage_label.text = "%s：%d/%d" % [
			String(accepted_resource_type),
			stored_amount,
			max_storage,
		]
		status_label.text = "等待建材"
