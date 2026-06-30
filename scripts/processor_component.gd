extends "res://scripts/building_component.gd"
class_name ProcessorComponent

signal production_changed(processor)

@export var input_storage_paths: Array[NodePath] = []
@export var input_amounts: Array[int] = []
@export var output_storage_paths: Array[NodePath] = []
@export var output_amounts: Array[int] = []
@export var required_work_component_paths: Array[NodePath] = []
@export var production_duration := 10.0
@export var status_label_path: NodePath = ^"StatusLabel"
@export var progress_bar_path: NodePath = ^"ProductionProgressBar"

var _is_producing := false
var _production_time_left := 0.0


func _ready() -> void:
	super._ready()
	set_process(true)
	_update_status()


func is_interactable() -> bool:
	return false


func is_producing() -> bool:
	return _is_producing


func get_production_progress() -> float:
	if not _is_producing:
		return 0.0
	return clampf(
		1.0 - _production_time_left / maxf(production_duration, 0.001),
		0.0,
		1.0
	)


func _process(delta: float) -> void:
	if _is_producing:
		if not _has_required_workers():
			_update_status()
			return
		_production_time_left = maxf(_production_time_left - delta, 0.0)
		if _production_time_left <= 0.0:
			_finish_production()
	else:
		_try_start_production()
	_update_status()


func _try_start_production() -> void:
	if _is_producing or not _has_required_workers():
		return
	if not _has_required_inputs() or not _has_output_space():
		return
	_consume_inputs()
	_is_producing = true
	_production_time_left = maxf(production_duration, 0.001)
	production_changed.emit(self)


func _finish_production() -> void:
	_is_producing = false
	_production_time_left = 0.0
	_store_outputs()
	production_changed.emit(self)
	_complete_required_workers()
	_try_start_production()


func _complete_required_workers() -> void:
	for path in required_work_component_paths:
		var work_component := get_node_or_null(path)
		if work_component and work_component.has_method("complete_active_workers"):
			work_component.complete_active_workers()


func _has_required_workers() -> bool:
	for path in required_work_component_paths:
		var work_component := get_node_or_null(path)
		if not work_component or not work_component.has_active_worker():
			return false
	return true


func _has_required_inputs() -> bool:
	for index in input_storage_paths.size():
		var storage := get_node_or_null(input_storage_paths[index])
		if not storage:
			return false
		var amount := _get_amount(input_amounts, index)
		if storage.stored_amount < amount:
			return false
	return true


func _has_output_space() -> bool:
	for index in output_storage_paths.size():
		var storage := get_node_or_null(output_storage_paths[index])
		if not storage:
			return false
		var amount := _get_amount(output_amounts, index)
		if storage.stored_amount + amount > storage.capacity:
			return false
	return true


func _consume_inputs() -> void:
	for index in input_storage_paths.size():
		var storage := get_node_or_null(input_storage_paths[index])
		if storage:
			storage.force_take_input(_get_amount(input_amounts, index))


func _store_outputs() -> void:
	for index in output_storage_paths.size():
		var storage := get_node_or_null(output_storage_paths[index])
		if storage:
			storage.force_store_output(_get_amount(output_amounts, index))


func _get_amount(amounts: Array[int], index: int) -> int:
	if index < 0 or index >= amounts.size():
		return 1
	return maxi(amounts[index], 1)


func _update_status() -> void:
	if not is_node_ready():
		return
	var label := get_node_or_null(status_label_path) as Label
	var progress_bar := get_node_or_null(progress_bar_path) as ProgressBar
	if progress_bar:
		progress_bar.visible = _is_producing
		progress_bar.value = get_production_progress() * 100.0
	if not label:
		return
	label.visible = not _is_producing
	if not _has_required_workers():
		label.text = "等待工人"
	elif not _has_required_inputs():
		label.text = "等待物資"
	elif not _has_output_space():
		label.text = "產出已滿"
	else:
		label.text = "待機"
