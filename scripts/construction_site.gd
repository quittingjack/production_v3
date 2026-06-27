## Legacy compatibility for pre-component buildings. Do not extend for new component buildings.
class_name ConstructionSite
extends Building

signal construction_completed(
	site: ConstructionSite,
	target_scene: PackedScene,
	auto_hire_candidates: Array[Villager]
)

@onready var site_body: Polygon2D = $SiteBody
@onready var status_label: Label = $StatusLabel
@onready var construction_progress_bar: ProgressBar = $ConstructionProgressBar

var target_scene: PackedScene
var _is_constructing := false
var _construction_time_left := 0.0
var _assigned_builders: Array[Villager] = []
var _active_builders: Array[Villager] = []


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
	_update_storage_label()


func _process(delta: float) -> void:
	_cleanup_builders()
	_try_start_construction()
	if not _is_constructing:
		_update_storage_label()
		return

	if not _active_builders.is_empty():
		_construction_time_left = maxf(
			_construction_time_left - delta * _active_builders.size(),
			0.0
		)
	_update_storage_label()
	if _construction_time_left <= 0.0:
		set_process(false)
		var candidates := _finish_builders()
		construction_completed.emit(self, target_scene, candidates)


func has_storage_space() -> bool:
	return not _is_constructing and super.has_storage_space()


func store_resource(type: StringName, amount: int) -> int:
	if _is_constructing:
		return 0
	var stored := super.store_resource(type, amount)
	_try_start_construction()
	_update_storage_label()
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


func assign_builder(builder: Villager) -> void:
	if (
		not is_instance_valid(builder)
		or _is_constructing and _construction_time_left <= 0.0
		or _assigned_builders.has(builder)
	):
		return
	_assigned_builders.append(builder)
	_update_storage_label()


func remove_builder(builder: Villager) -> void:
	_assigned_builders.erase(builder)
	_active_builders.erase(builder)
	_update_storage_label()


func set_builder_active(builder: Villager, active: bool) -> void:
	if not _assigned_builders.has(builder):
		return
	if active:
		if not _active_builders.has(builder):
			_active_builders.append(builder)
	else:
		_active_builders.erase(builder)
	_try_start_construction()
	_update_storage_label()


func get_active_builder_count() -> int:
	_cleanup_builders()
	return _active_builders.size()


func is_material_ready() -> bool:
	return _is_constructing or stored_amount >= max_storage


func _try_start_construction() -> void:
	if (
		_is_constructing
		or not is_material_ready()
		or _active_builders.is_empty()
	):
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
		var candidates := _finish_builders()
		construction_completed.emit(self, target_scene, candidates)


func _cleanup_builders() -> void:
	for index in range(_assigned_builders.size() - 1, -1, -1):
		if not is_instance_valid(_assigned_builders[index]):
			_assigned_builders.remove_at(index)
	for index in range(_active_builders.size() - 1, -1, -1):
		var builder := _active_builders[index]
		if (
			not is_instance_valid(builder)
			or not _assigned_builders.has(builder)
		):
			_active_builders.remove_at(index)


func _finish_builders() -> Array[Villager]:
	var builders := _assigned_builders.duplicate()
	var auto_hire_candidates: Array[Villager] = []
	for builder in builders:
		if (
			is_instance_valid(builder)
			and not builder.has_work_queued_after_current()
		):
			auto_hire_candidates.append(builder)
	_assigned_builders.clear()
	_active_builders.clear()
	for builder in builders:
		if is_instance_valid(builder):
			builder.on_construction_site_completed(self)
	return auto_hire_candidates


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
		status_label.visible = false
		construction_progress_bar.visible = true
		construction_progress_bar.value = get_construction_progress() * 100.0
	else:
		storage_label.text = "%s：%d/%d" % [
			String(accepted_resource_type),
			stored_amount,
			max_storage,
		]
		status_label.visible = true
		construction_progress_bar.visible = false
		if is_material_ready():
			status_label.text = "等待工人"
		elif _assigned_builders.is_empty():
			status_label.text = "等待建材"
		else:
			status_label.text = "等待建材（已派工）"
