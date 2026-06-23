class_name Factory
extends Building

signal production_changed(factory: Factory)
signal output_storage_changed(factory: Factory)

@export_group("Recipe")
@export var input_resource_type: StringName = &"wood"
@export var input_amount := 5
@export var output_resource_type: StringName = &"lumber"
@export var output_amount := 1
@export var production_duration := 10.0

@export_group("Storage")
@export var input_capacity := 20
@export var output_capacity := 10

@onready var input_label: Label = $InputLabel
@onready var output_label: Label = $OutputLabel
@onready var status_label: Label = $StatusLabel
@onready var production_progress_bar: ProgressBar = $ProductionProgressBar

var input_stored_amount := 0
var output_stored_amount := 0
var _is_producing := false
var _production_time_left := 0.0
var _worker: Villager
var _worker_is_active := false


func _ready() -> void:
	super._ready()
	set_process(true)
	_try_start_production()
	_update_factory_labels()


func _process(delta: float) -> void:
	_cleanup_worker()
	if _is_producing and _worker_is_active:
		_production_time_left = maxf(_production_time_left - delta, 0.0)
		if _production_time_left <= 0.0:
			_finish_production()
	elif not _is_producing and _worker_is_active:
		_try_start_production()

	_update_factory_labels()
	if debug_draw_interaction_slots:
		queue_redraw()


func accepts_resource(type: StringName) -> bool:
	return type == input_resource_type


func has_storage_space() -> bool:
	return input_stored_amount < maxi(input_capacity, 0)


func store_resource(type: StringName, amount: int) -> int:
	if not accepts_resource(type) or amount <= 0:
		return 0

	var stored := mini(amount, maxi(input_capacity, 0) - input_stored_amount)
	if stored <= 0:
		return 0

	input_stored_amount += stored
	storage_changed.emit(self)
	_try_start_production()
	_update_factory_labels()
	return stored


func get_output_resource_type() -> StringName:
	return output_resource_type


func get_output_amount(type: StringName = &"") -> int:
	if type != &"" and type != output_resource_type:
		return 0
	return output_stored_amount


func take_output(type: StringName, amount: int) -> int:
	if type != output_resource_type or amount <= 0:
		return 0

	var taken := mini(amount, output_stored_amount)
	if taken <= 0:
		return 0

	output_stored_amount -= taken
	output_storage_changed.emit(self)
	_try_start_production()
	_update_factory_labels()
	return taken


func is_producing() -> bool:
	return _is_producing


func has_worker() -> bool:
	_cleanup_worker()
	return is_instance_valid(_worker)


func has_vacancy() -> bool:
	return not has_worker()


func get_worker() -> Villager:
	_cleanup_worker()
	return _worker


func hire_worker(worker: Villager) -> bool:
	_cleanup_worker()
	if not is_instance_valid(worker):
		return false
	if is_instance_valid(_worker) and _worker != worker:
		return false
	_worker = worker
	_worker_is_active = false
	_update_factory_labels()
	return true


func set_worker_active(worker: Villager, active: bool) -> void:
	_cleanup_worker()
	if worker != _worker:
		return
	_worker_is_active = active
	if active:
		_try_start_production()
	_update_factory_labels()


func release_worker(worker: Villager) -> void:
	if worker != _worker:
		return
	_worker = null
	_worker_is_active = false
	release_interaction_slot(worker)
	_update_factory_labels()


func get_production_progress() -> float:
	if not _is_producing:
		return 0.0
	var duration := maxf(production_duration, 0.001)
	return clampf(1.0 - _production_time_left / duration, 0.0, 1.0)


func _try_start_production() -> void:
	if _is_producing or not _worker_is_active:
		return

	var required_input := maxi(input_amount, 1)
	var produced_output := maxi(output_amount, 1)
	if input_stored_amount < required_input:
		return
	if output_stored_amount + produced_output > maxi(output_capacity, 0):
		return

	input_stored_amount -= required_input
	_is_producing = true
	_production_time_left = maxf(production_duration, 0.001)
	storage_changed.emit(self)
	production_changed.emit(self)


func _finish_production() -> void:
	_is_producing = false
	_production_time_left = 0.0
	output_stored_amount += maxi(output_amount, 1)
	output_storage_changed.emit(self)
	production_changed.emit(self)
	_try_start_production()


func _update_storage_label() -> void:
	if not is_node_ready():
		return
	_update_factory_labels()


func _update_factory_labels() -> void:
	if not is_instance_valid(input_label):
		return

	input_label.text = "木頭：%d/%d" % [
		input_stored_amount,
		maxi(input_capacity, 0),
	]
	output_label.text = "木材：%d/%d" % [
		output_stored_amount,
		maxi(output_capacity, 0),
	]

	if not _worker_is_active:
		status_label.visible = true
		production_progress_bar.visible = false
		status_label.text = "等待工人"
	elif _is_producing:
		status_label.visible = false
		production_progress_bar.visible = true
		production_progress_bar.value = get_production_progress() * 100.0
	elif input_stored_amount < maxi(input_amount, 1):
		status_label.visible = true
		production_progress_bar.visible = false
		status_label.text = "等待木頭"
	elif output_stored_amount + maxi(output_amount, 1) > maxi(output_capacity, 0):
		status_label.visible = true
		production_progress_bar.visible = false
		status_label.text = "木材倉已滿"
	else:
		status_label.visible = true
		production_progress_bar.visible = false
		status_label.text = "待機"


func _cleanup_worker() -> void:
	if is_instance_valid(_worker) and not _worker.is_queued_for_deletion():
		return
	_worker = null
	_worker_is_active = false
