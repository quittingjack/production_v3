## Legacy compatibility for pre-component buildings. Do not extend for new component buildings.
class_name ConstructionJob
extends RefCounted

var source: Building
var site: ConstructionSite
var resource_type: StringName

var _reserved_amounts: Dictionary = {}


func _init(
	job_source: Building,
	job_site: ConstructionSite
) -> void:
	source = job_source
	site = job_site
	if is_instance_valid(site):
		resource_type = site.construction_resource_type


func claim_amount(villager: Villager, maximum: int) -> int:
	if (
		not is_instance_valid(villager)
		or maximum <= 0
		or not is_valid()
		or site.is_material_ready()
	):
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
	if not is_instance_valid(villager):
		return

	var villager_id := villager.get_instance_id()
	var reserved := int(_reserved_amounts.get(villager_id, 0))
	reserved = maxi(reserved - maxi(amount, 0), 0)
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


func get_missing_amount() -> int:
	if not is_instance_valid(site) or site.is_material_ready():
		return 0
	return maxi(site.max_storage - site.stored_amount, 0)


func get_unreserved_amount() -> int:
	return maxi(get_missing_amount() - get_reserved_amount(), 0)


func is_fully_covered() -> bool:
	return (
		is_instance_valid(site)
		and (
			site.is_material_ready()
			or site.stored_amount + get_reserved_amount() >= site.max_storage
		)
	)


func is_valid() -> bool:
	return (
		is_instance_valid(source)
		and not source.is_queued_for_deletion()
		and is_instance_valid(site)
		and not site.is_queued_for_deletion()
		and source != site
		and source.get_output_resource_type() == resource_type
		and site.accepts_resource(resource_type)
	)
