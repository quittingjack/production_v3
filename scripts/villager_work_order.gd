class_name VillagerWorkOrder
extends RefCounted

enum Type {
	MOVE,
	GATHER,
	HAUL,
	CONSTRUCT,
	CONSTRUCTION_JOB,
	FACTORY_WORK,
	INTERACT_BUILDING,
	INTERACT_CONSTRUCTION_SITE,
	INTERACT_COMPONENT,
}

var type := Type.MOVE
var position := Vector2.ZERO
var resource_target: ResourceNode
var resource_type: StringName = &""
var source: Building
var destination: Building
var waypoints: Array[Vector2] = []
var amount_per_trip := 1
var construction_site: ConstructionSite
var construction_job: ConstructionJob
var haul_material := false
var factory: Factory
var building: Building
var component: Node
var interaction_slot: Node


static func create_move(target_position: Vector2) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.MOVE
	order.position = target_position
	return order


static func create_gather(target: ResourceNode) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.GATHER
	order.resource_target = target
	order.resource_type = target.resource_type
	return order


static func create_haul(
	haul_source: Building,
	haul_destination: Building,
	haul_waypoints: Array[Vector2],
	haul_amount_per_trip: int
) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.HAUL
	order.source = haul_source
	order.destination = haul_destination
	order.waypoints = haul_waypoints.duplicate()
	order.amount_per_trip = haul_amount_per_trip
	order.resource_type = haul_source.get_output_resource_type()
	return order


static func create_construct(site: ConstructionSite) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.CONSTRUCT
	order.construction_site = site
	return order


static func create_construction_job(
	job: ConstructionJob,
	job_waypoints: Array[Vector2],
	should_haul_material: bool
) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.CONSTRUCTION_JOB
	order.construction_job = job
	order.construction_site = job.site
	order.waypoints = job_waypoints.duplicate()
	order.haul_material = should_haul_material
	order.resource_type = job.resource_type
	return order


static func create_factory_work(target_factory: Factory) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.FACTORY_WORK
	order.factory = target_factory
	return order


static func create_interact_building(target_building: Building) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.INTERACT_BUILDING
	order.building = target_building
	return order


static func create_interact_construction_site(
	site: ConstructionSite
) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.INTERACT_CONSTRUCTION_SITE
	order.construction_site = site
	order.building = site
	return order


static func create_interact_component(
	target_component: Node,
	target_slot: Node
) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.INTERACT_COMPONENT
	order.component = target_component
	order.interaction_slot = target_slot
	return order


func is_repeating() -> bool:
	return type == Type.HAUL


func get_type_name() -> String:
	return Type.keys()[type]
