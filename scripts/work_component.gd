extends "res://scripts/building_component.gd"
class_name WorkComponent

signal workers_changed(work_component)

@export var label_path: NodePath = ^"StatusLabel"

var _active_workers: Array = []


func _ready() -> void:
	super._ready()
	add_to_group(&"interactable_components")
	_update_label()


func is_interactable() -> bool:
	return true


func activate_worker(worker: Node) -> void:
	if not is_instance_valid(worker) or _active_workers.has(worker):
		return
	_active_workers.append(worker)
	_update_label()
	workers_changed.emit(self)


func deactivate_worker(worker: Node) -> void:
	if not _active_workers.has(worker):
		return
	_active_workers.erase(worker)
	_update_label()
	workers_changed.emit(self)


func has_active_worker() -> bool:
	_cleanup_workers()
	return not _active_workers.is_empty()


func get_active_worker_count() -> int:
	_cleanup_workers()
	return _active_workers.size()


func _cleanup_workers() -> void:
	for index in range(_active_workers.size() - 1, -1, -1):
		if not is_instance_valid(_active_workers[index]):
			_active_workers.remove_at(index)


func _update_label() -> void:
	if not is_node_ready():
		return
	var label := get_node_or_null(label_path) as Label
	if not label:
		return
	label.text = "工作中：%d" % get_active_worker_count()
