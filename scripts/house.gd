class_name House
extends BuildableBuilding

var _resident: Villager


func _ready() -> void:
	super._ready()
	add_to_group(&"houses")
	_update_status_label()


func is_vacant() -> bool:
	return not is_instance_valid(_resident)


func assign_villager(villager: Villager) -> void:
	if not is_vacant() or not is_instance_valid(villager):
		return
	_resident = villager
	_update_status_label()


func _update_status_label() -> void:
	var status_label := get_node_or_null("StatusLabel") as Label
	if not status_label:
		return
	status_label.text = "空屋" if is_vacant() else "已入住"
