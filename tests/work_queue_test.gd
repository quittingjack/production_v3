extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var villager_scene := load("res://scenes/villager.tscn") as PackedScene
	var building_scene := load("res://scenes/building.tscn") as PackedScene
	var resource_scene := load("res://scenes/wood_resource.tscn") as PackedScene
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var house_scene := load("res://scenes/house.tscn") as PackedScene
	var villager := villager_scene.instantiate() as Villager
	root.add_child(villager)
	await process_frame

	villager.move_to(Vector2(100.0, 0.0))
	villager.move_to(Vector2(200.0, 0.0), true)
	if villager.get_work_queue_count() != 2:
		_fail("Shift move did not append to the work queue.")
		return
	villager._complete_current_work_order()
	if (
		villager.get_work_queue_count() != 1
		or villager._target_position != Vector2(200.0, 0.0)
	):
		_fail("Completing a move did not start the next queued move.")
		return

	var empty_resource := resource_scene.instantiate() as ResourceNode
	empty_resource.resource_amount = 0
	root.add_child(empty_resource)
	await process_frame
	villager.gather_from(empty_resource)
	villager.move_to(Vector2(300.0, 0.0), true)
	if (
		villager.get_current_work_type_name() != "MOVE"
		or villager.get_work_queue_count() != 1
		or villager._target_position != Vector2(300.0, 0.0)
	):
		_fail("Empty finite gather did not advance to the next queued work.")
		return

	villager.move_to(Vector2(400.0, 0.0))
	if (
		villager.get_work_queue_count() != 1
		or villager.get_current_work_type_name() != "MOVE"
	):
		_fail("A normal command did not replace the existing queue.")
		return

	var sources: Array[Building] = []
	var destinations: Array[Building] = []
	for index in 3:
		var source := building_scene.instantiate() as Building
		var destination := building_scene.instantiate() as Building
		root.add_child(source)
		root.add_child(destination)
		source.store_resource(&"wood", 10)
		sources.append(source)
		destinations.append(destination)
	await process_frame

	villager.start_haul_job(sources[0], destinations[0], [], 1)
	villager.start_haul_job(sources[1], destinations[1], [], 1, true)
	villager.start_haul_job(sources[2], destinations[2], [], 1, true)
	var expected_sources := [
		sources[0],
		sources[1],
		sources[2],
		sources[0],
		sources[1],
	]
	for expected_source in expected_sources:
		if villager._haul_source != expected_source:
			_fail("Repeating haul order did not follow A-B-C-A-B.")
			return
		villager._advance_repeating_work_order()

	villager.move_to(Vector2(600.0, 0.0))
	villager.move_to(Vector2(700.0, 0.0), true, true)
	if villager.get_work_queue_count() != 2:
		_fail("Ctrl move did not append to the work queue.")
		return
	villager._complete_current_work_order()
	if (
		villager.get_work_queue_count() != 2
		or villager._target_position != Vector2(700.0, 0.0)
	):
		_fail("Ctrl queue did not preserve orders while advancing.")
		return
	villager._complete_current_work_order()
	if (
		villager.get_work_queue_count() != 2
		or villager._target_position != Vector2(600.0, 0.0)
	):
		_fail("Ctrl queue did not loop back to the first order.")
		return
	villager.stop_all_work()
	if (
		villager.get_work_queue_count() != 0
		or villager.get_state_name() != "IDLE"
	):
		_fail("Stopping did not clear the queue and idle the villager.")
		return

	var site := site_scene.instantiate() as ConstructionSite
	site.initialize(house_scene, Vector2(96.0, 96.0), &"wood", 0, 1.0)
	root.add_child(site)
	await process_frame
	villager.construct_at(site)
	villager.move_to(Vector2(500.0, 0.0), true)
	villager.on_construction_site_completed(site)
	if (
		villager.get_work_queue_count() != 1
		or villager.get_current_work_type_name() != "MOVE"
	):
		_fail("Construction completion did not advance to queued work.")
		return

	var invalid_site := site_scene.instantiate() as ConstructionSite
	invalid_site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"wood",
		0,
		1.0
	)
	root.add_child(invalid_site)
	await process_frame
	villager.construct_at(invalid_site, true)
	invalid_site.queue_free()
	villager._complete_current_work_order()
	if villager.get_work_queue_count() != 0:
		_fail("An invalid queued construction target was not removed.")
		return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
