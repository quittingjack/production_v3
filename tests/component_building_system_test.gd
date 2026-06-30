extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	await _test_manual_slot_reservation()
	await _test_loop_command_sequence()
	await _test_full_backpack_gather_completion()
	await _test_storage_interaction()
	await _test_empty_backpack_can_queue_input_storage()
	await _test_work_component()
	await _test_processor_without_worker()
	await _test_factory_scene_with_worker()
	await _test_building_manager_places_and_demolishes_roots()
	quit(0)


func _test_manual_slot_reservation() -> void:
	var storage := _instantiate("res://scenes/storage_component.tscn")
	var first := _instantiate("res://scenes/villager.tscn")
	var second := _instantiate("res://scenes/villager.tscn")
	root.add_child(storage)
	root.add_child(first)
	root.add_child(second)
	await process_frame

	_set_backpack(first, &"wood", 1)
	_set_backpack(second, &"wood", 1)
	if not first.interact_with_component(storage):
		_fail("The first villager could not reserve a manual component slot.")
	if second.interact_with_component(storage):
		_fail("A second villager reserved an already occupied slot.")

	storage.queue_free()
	first.queue_free()
	second.queue_free()
	await process_frame


func _test_loop_command_sequence() -> void:
	var villager := _instantiate("res://scenes/villager.tscn")
	root.add_child(villager)
	await process_frame

	var first := Vector2(10.0, 0.0)
	var second := Vector2(20.0, 0.0)
	var third := Vector2(30.0, 0.0)
	var tail := Vector2(40.0, 0.0)
	villager.move_to(first, false, true)
	villager.move_to(second, true, true)
	villager.move_to(third, true, true)
	villager.move_to(tail, true, false)

	if villager.get_work_queue_count() != 4:
		_fail("Loop command sequence did not keep all displayed commands.")
	if villager._target_position != first:
		_fail("Loop command sequence did not start at the first loop command.")
	villager._arrive_at_target()
	if villager._target_position != second:
		_fail("Loop command sequence did not advance to the second loop command.")
	villager._arrive_at_target()
	if villager._target_position != third:
		_fail("Loop command sequence did not advance to the third loop command.")
	villager._arrive_at_target()
	if villager._target_position != first:
		_fail("Loop command sequence did not wrap back to the first loop command.")

	villager.queue_free()
	await process_frame


func _test_full_backpack_gather_completion() -> void:
	var resource := _instantiate("res://scenes/wood_resource.tscn")
	var villager := _instantiate("res://scenes/villager.tscn") as Villager
	root.add_child(resource)
	root.add_child(villager)
	await process_frame

	_set_backpack(villager, &"wood", villager.backpack_capacity)
	villager.gather_from(resource)
	if villager.get_work_queue_count() != 0:
		_fail("Full backpack gather did not complete the one-shot gather order.")
	if villager.get_state_name() != "IDLE":
		_fail("Full backpack gather should not move or enter gather state.")
	if villager._resource_slot >= 0:
		_fail("Full backpack gather reserved a resource slot.")

	resource.queue_free()
	villager.queue_free()
	await process_frame

	resource = _instantiate("res://scenes/wood_resource.tscn")
	villager = _instantiate("res://scenes/villager.tscn") as Villager
	root.add_child(resource)
	root.add_child(villager)
	await process_frame

	_set_backpack(villager, &"wood", villager.backpack_capacity)
	villager.gather_from(resource, false, true)
	if villager.get_work_queue_count() != 1:
		_fail("Looping gather should remain displayed after full backpack completion.")
	if villager.get_current_work_index() != -1:
		_fail("Single looping full backpack gather should not restart itself immediately.")
	if villager.get_state_name() != "IDLE":
		_fail("Single looping full backpack gather should leave the villager idle.")

	resource.queue_free()
	villager.queue_free()
	await process_frame

	resource = _instantiate("res://scenes/wood_resource.tscn")
	var storage := _instantiate("res://scenes/storage_component.tscn")
	villager = _instantiate("res://scenes/villager.tscn") as Villager
	root.add_child(resource)
	root.add_child(storage)
	root.add_child(villager)
	await process_frame

	_set_backpack(villager, &"wood", villager.backpack_capacity)
	villager.gather_from(resource, false, true)
	if not villager.interact_with_component(storage, true, true):
		_fail("Could not queue storage after a looping gather.")
	if villager.get_current_work_type_name() != "INTERACT_STORAGE":
		_fail("Full backpack looping gather did not advance to the queued storage order.")
	if villager.get_state_name() != "MOVING_TO_COMPONENT_SLOT":
		_fail("Queued storage order did not start after full backpack looping gather.")

	resource.queue_free()
	storage.queue_free()
	villager.queue_free()
	await process_frame


func _test_storage_interaction() -> void:
	var storage := _instantiate("res://scenes/storage_component.tscn")
	var villager := _instantiate("res://scenes/villager.tscn")
	root.add_child(storage)
	root.add_child(villager)
	await process_frame

	_set_backpack(villager, &"wood", 3)
	if not villager.interact_with_component(storage):
		_fail("Villager could not start storage deposit interaction.")
	_arrive_at_reserved_slot(villager)
	if storage.stored_amount != 3 or villager.get_backpack_amount() != 0:
		_fail("Storage deposit did not move carried resources.")

	if not villager.interact_with_component(storage):
		_fail("Villager could not start storage take interaction.")
	_arrive_at_reserved_slot(villager)
	if storage.stored_amount != 0 or villager.get_backpack_amount() != 3:
		_fail("Storage take did not move output resources.")

	storage.store_resource(&"wood", 2)
	_set_backpack(villager, &"stone", 1)
	if not villager.interact_with_component(storage):
		_fail("Storage should discard mismatched carried resource and take output.")
	_arrive_at_reserved_slot(villager)
	if storage.stored_amount != 0:
		_fail("Mismatched storage interaction did not take available output.")
	if villager.get_backpack_resource_type() != &"wood" or villager.get_backpack_amount() != 2:
		_fail("Mismatched storage interaction did not replace the backpack.")

	storage.queue_free()
	villager.queue_free()
	await process_frame


func _test_empty_backpack_can_queue_input_storage() -> void:
	var storage := _instantiate("res://scenes/storage_component.tscn")
	var villager := _instantiate("res://scenes/villager.tscn")
	storage.allow_deposit = true
	storage.allow_take = false
	root.add_child(storage)
	root.add_child(villager)
	await process_frame

	if not villager.interact_with_component(storage, true, true):
		_fail("Empty backpack villager could not queue an input storage interaction.")
	if villager.get_current_work_type_name() != "INTERACT_STORAGE":
		_fail("Empty backpack input storage interaction did not create storage work.")
	if villager.get_state_name() != "MOVING_TO_COMPONENT_SLOT":
		_fail("Empty backpack input storage interaction did not start moving to storage.")

	storage.queue_free()
	villager.queue_free()
	await process_frame


func _test_work_component() -> void:
	var work := _instantiate("res://scenes/work_component.tscn")
	var villager := _instantiate("res://scenes/villager.tscn")
	root.add_child(work)
	root.add_child(villager)
	await process_frame

	if not villager.interact_with_component(work):
		_fail("Villager could not start work component interaction.")
	_arrive_at_reserved_slot(villager)
	if villager.get_state_name() != "COMPONENT_WORKING":
		_fail("Villager did not remain at the work component.")
	if not work.has_active_worker():
		_fail("Work component was not activated by the worker.")

	work.complete_active_workers()
	if villager.get_state_name() == "COMPONENT_WORKING":
		_fail("Completing work did not release the villager.")
	if work.has_active_worker():
		_fail("Completing work did not deactivate the work component.")

	if not villager.interact_with_component(work):
		_fail("Villager could not restart work after completion.")
	_arrive_at_reserved_slot(villager)
	villager.stop_all_work()
	if work.has_active_worker():
		_fail("Stopping work did not deactivate the work component.")

	work.queue_free()
	villager.queue_free()
	await process_frame


func _test_processor_without_worker() -> void:
	var container := Node2D.new()
	var input := _instantiate("res://scenes/storage_component.tscn")
	var output := _instantiate("res://scenes/storage_component.tscn")
	var processor := _instantiate("res://scenes/processor_component.tscn")
	input.name = "InputStorage"
	output.name = "OutputStorage"
	processor.name = "ProcessorComponent"
	output.resource_type = &"lumber"
	var input_paths: Array[NodePath] = [NodePath("../InputStorage")]
	var input_amounts: Array[int] = [2]
	var output_paths: Array[NodePath] = [NodePath("../OutputStorage")]
	var output_amounts: Array[int] = [1]
	var required_work_paths: Array[NodePath] = []
	processor.input_storage_paths = input_paths
	processor.input_amounts = input_amounts
	processor.output_storage_paths = output_paths
	processor.output_amounts = output_amounts
	processor.required_work_component_paths = required_work_paths
	processor.production_duration = 0.05
	root.add_child(container)
	container.add_child(input)
	container.add_child(output)
	container.add_child(processor)
	await process_frame

	input.store_resource(&"wood", 2)
	await create_timer(0.12).timeout
	if input.stored_amount != 0 or output.stored_amount != 1:
		_fail("Workerless processor did not consume input and produce output.")

	container.queue_free()
	await process_frame


func _test_factory_scene_with_worker() -> void:
	var factory := _instantiate("res://scenes/factory.tscn")
	var villager := _instantiate("res://scenes/villager.tscn")
	root.add_child(factory)
	root.add_child(villager)
	await process_frame

	var input := factory.get_node("InputStorage")
	var output := factory.get_node("OutputStorage")
	var work := factory.get_node("WorkComponent")
	var processor := factory.get_node("ProcessorComponent")
	processor.production_duration = 0.05
	input.store_resource(&"wood", 5)
	await create_timer(0.08).timeout
	if output.stored_amount != 0:
		_fail("Factory produced before its work component was active.")

	if not villager.interact_with_component(work):
		_fail("Villager could not reserve the factory work component.")
	_arrive_at_reserved_slot(villager)
	await create_timer(0.12).timeout
	if input.stored_amount != 0 or output.stored_amount != 1:
		_fail("Factory did not produce lumber with an active worker.")
	if work.has_active_worker():
		_fail("Factory work component did not release worker after one production.")
	if villager.get_state_name() == "COMPONENT_WORKING":
		_fail("Villager did not leave work state after one production.")

	factory.queue_free()
	villager.queue_free()
	await process_frame


func _test_building_manager_places_and_demolishes_roots() -> void:
	var main := _instantiate("res://scenes/main.tscn")
	var building_scene := load("res://scenes/building.tscn") as PackedScene
	root.add_child(main)
	await process_frame

	var buildings := main.get_node("Buildings")
	var building_manager := main.get_node("BuildingManager")
	var count_before := buildings.get_child_count()
	building_manager._start_placement(building_scene, Vector2(96.0, 96.0))
	building_manager._preview_position = Vector2(1280.0, 720.0)
	building_manager._placement_is_valid = true
	building_manager._place_building(false)
	await process_frame
	if buildings.get_child_count() != count_before + 1:
		_fail("BuildingManager did not place a completed building root.")

	var placed := buildings.get_child(buildings.get_child_count() - 1)
	var selection_manager := main.get_node("SelectionManager")
	var villager := main.get_node("Villagers/Villager1")
	var storage := placed.get_node("StorageComponent")
	selection_manager._select_only(villager)
	_set_backpack(villager, &"wood", 1)
	selection_manager._command_selection_at(storage.global_position)
	if villager.get_current_work_type_name() != "INTERACT_STORAGE":
		_fail("Right-clicking a storage component did not issue component work.")

	villager.stop_all_work()
	selection_manager._command_selection_at(placed.global_position)
	if villager.get_current_work_type_name() != "MOVE":
		_fail("Right-clicking building visuals should move, not interact.")

	building_manager._start_demolition()
	if not building_manager.demolish_building(placed):
		_fail("BuildingManager could not demolish a building root.")
	await process_frame
	if is_instance_valid(placed) and not placed.is_queued_for_deletion():
		_fail("Demolished building root remained alive.")

	main.queue_free()
	await process_frame


func _arrive_at_reserved_slot(villager: Node) -> void:
	villager.global_position = villager._component_slot.get_interaction_position()
	villager._arrive_at_target()


func _set_backpack(villager: Node, type: StringName, amount: int) -> void:
	villager._backpack_resource_type = type
	villager._backpack_amount = amount
	villager._update_backpack_label()


func _instantiate(path: String) -> Node:
	var scene := load(path) as PackedScene
	if not scene:
		_fail("Could not load scene: %s" % path)
	return scene.instantiate()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
