extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var factory_scene := load("res://scenes/factory.tscn") as PackedScene
	var villager_scene := load("res://scenes/villager.tscn") as PackedScene
	var factory := factory_scene.instantiate() as Factory
	var first_worker := villager_scene.instantiate() as Villager
	var second_worker := villager_scene.instantiate() as Villager
	factory.production_duration = 0.5
	root.add_child(factory)
	root.add_child(first_worker)
	root.add_child(second_worker)
	await process_frame

	factory.store_resource(factory.input_resource_type, factory.input_amount)
	if factory.is_producing():
		_fail("Factory produced without a worker.")
		return
	if not first_worker.work_at_factory(factory):
		_fail("The first factory worker could not be assigned.")
		return
	if factory.get_worker() != first_worker:
		_fail("Factory did not reserve its vacancy immediately.")
		return
	if second_worker.work_at_factory(factory):
		_fail("Factory accepted a second worker.")
		return

	first_worker.global_position = factory.global_position
	first_worker._try_reserve_factory_slot()
	if first_worker._factory_slot < 0:
		_fail("Factory worker did not reserve an interaction slot.")
		return
	first_worker.global_position = factory.get_interaction_slot_position(
		first_worker._factory_slot
	)
	first_worker._arrive_at_target()
	if first_worker.get_state_name() != "FACTORY_WORKING":
		_fail("Factory worker did not enter the working state.")
		return
	if not factory.is_producing():
		_fail("Factory did not start when its worker became active.")
		return

	await create_timer(0.1).timeout
	var paused_progress := factory.get_production_progress()
	first_worker.move_to(Vector2(300.0, 0.0))
	if factory.has_worker():
		_fail("Reassigning the worker did not release the factory vacancy.")
		return
	await create_timer(0.1).timeout
	if not is_equal_approx(factory.get_production_progress(), paused_progress):
		_fail("Production progress changed while the factory had no worker.")
		return
	if factory.status_label.text != "等待工人":
		_fail("Paused factory did not display the waiting-for-worker status.")
		return

	if not second_worker.work_at_factory(factory):
		_fail("A replacement worker could not be hired.")
		return
	second_worker.global_position = factory.global_position
	second_worker._try_reserve_factory_slot()
	second_worker.global_position = factory.get_interaction_slot_position(
		second_worker._factory_slot
	)
	second_worker._arrive_at_target()
	await create_timer(0.1).timeout
	if factory.get_production_progress() <= paused_progress:
		_fail("Replacement worker did not resume paused production.")
		return

	factory.queue_free()
	await process_frame
	await physics_frame
	await physics_frame
	if second_worker.get_state_name() != "IDLE":
		_fail(
			"Demolished factory did not cancel its worker's job: %s."
			% second_worker.get_state_name()
		)
		return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
