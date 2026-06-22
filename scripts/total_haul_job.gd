class_name TotalHaulJob
extends RefCounted

var source: Building
var destination: Building
var resource_type: StringName
var target_amount := 0
var delivered_amount := 0

var _reserved_amounts: Dictionary = {}


func _init(
	job_source: Building,
	job_destination: Building,
	job_resource_type: StringName,
	job_target_amount: int
) -> void:
	source = job_source
	destination = job_destination
	resource_type = job_resource_type
	target_amount = maxi(job_target_amount, 1)


func claim_amount(villager: Villager, maximum: int) -> int:
	if not is_instance_valid(villager) or maximum <= 0:
		return 0

	var villager_id := villager.get_instance_id()
	var existing := int(_reserved_amounts.get(villager_id, 0))
	if existing > 0:
		return existing

	var claimed := mini(maximum, get_unreserved_amount())
	if claimed > 0:
		_reserved_amounts[villager_id] = claimed
	return claimed


func adjust_claim_after_pickup(villager: Villager, picked_up: int) -> void:
	if not is_instance_valid(villager):
		return
	var villager_id := villager.get_instance_id()
	if picked_up > 0:
		_reserved_amounts[villager_id] = picked_up
	else:
		_reserved_amounts.erase(villager_id)


func record_delivery(villager: Villager, amount: int) -> void:
	if not is_instance_valid(villager) or amount <= 0:
		return

	var villager_id := villager.get_instance_id()
	var reserved := int(_reserved_amounts.get(villager_id, 0))
	delivered_amount = mini(delivered_amount + amount, target_amount)
	reserved = maxi(reserved - amount, 0)
	if reserved > 0:
		_reserved_amounts[villager_id] = reserved
	else:
		_reserved_amounts.erase(villager_id)


func release_claim(villager: Villager) -> void:
	if is_instance_valid(villager):
		_reserved_amounts.erase(villager.get_instance_id())


func get_claimed_amount(villager: Villager) -> int:
	if not is_instance_valid(villager):
		return 0
	return int(_reserved_amounts.get(villager.get_instance_id(), 0))


func get_reserved_amount() -> int:
	var total := 0
	for amount in _reserved_amounts.values():
		total += int(amount)
	return total


func get_unreserved_amount() -> int:
	return maxi(target_amount - delivered_amount - get_reserved_amount(), 0)


func is_fully_covered() -> bool:
	return delivered_amount + get_reserved_amount() >= target_amount


func is_complete() -> bool:
	return delivered_amount >= target_amount


func is_valid() -> bool:
	return (
		is_instance_valid(source)
		and not source.is_queued_for_deletion()
		and is_instance_valid(destination)
		and not destination.is_queued_for_deletion()
		and source != destination
		and source.get_output_resource_type() == resource_type
		and destination.accepts_resource(resource_type)
	)

