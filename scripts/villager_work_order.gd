class_name VillagerWorkOrder
extends RefCounted

enum Type {
	MOVE,
	GATHER,
	INTERACT_STORAGE,
	WORK_COMPONENT,
}

var type := Type.MOVE
var position := Vector2.ZERO
var resource_target: ResourceNode
var resource_type: StringName = &""
var component: Node
var interaction_slot: Node
var is_looping := false


static func create_move(
	target_position: Vector2,
	loop_order := false
) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.MOVE
	order.position = target_position
	order.is_looping = loop_order
	return order


static func create_gather(
	target: ResourceNode,
	loop_order := false
) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.GATHER
	order.resource_target = target
	order.resource_type = target.resource_type
	order.is_looping = loop_order
	return order


static func create_interact_storage(
	target_component: Node,
	target_slot: Node = null,
	loop_order := false
) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.INTERACT_STORAGE
	order.component = target_component
	order.interaction_slot = target_slot
	order.is_looping = loop_order
	return order


static func create_work_component(
	target_component: Node,
	target_slot: Node = null,
	loop_order := false
) -> VillagerWorkOrder:
	var order := VillagerWorkOrder.new()
	order.type = Type.WORK_COMPONENT
	order.component = target_component
	order.interaction_slot = target_slot
	order.is_looping = loop_order
	return order


func get_type_name() -> String:
	return Type.keys()[type]


func get_display_name() -> String:
	match type:
		Type.MOVE:
			return "移動"
		Type.GATHER:
			return "採集 %s" % String(resource_type)
		Type.INTERACT_STORAGE:
			if is_instance_valid(component):
				return "取出/放入 %s" % String(component.resource_type)
			return "取出/放入"
		Type.WORK_COMPONENT:
			return "工作"
	return get_type_name()
