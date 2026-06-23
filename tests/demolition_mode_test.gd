extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var building_scene := load("res://scenes/building.tscn") as PackedScene
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var house_scene := load("res://scenes/house.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var buildings := main.get_node("Buildings")
	var building_manager := main.get_node("BuildingManager")
	var selection_manager := main.get_node("SelectionManager")
	var town_center := main.get_node("Buildings/TownCenter")

	_send_key(building_manager, KEY_X)
	if not building_manager.is_demolishing():
		_fail("X did not enable demolition mode.")
		return
	if not building_manager._demolition_cursor.visible:
		_fail("Demolition cursor was not shown.")
		return

	var storage := building_scene.instantiate() as Building
	storage.position = Vector2(-800.0, -400.0)
	buildings.add_child(storage)
	storage.store_resource(&"wood", 12)
	await process_frame

	_send_left_click(main, selection_manager, storage.global_position)
	if storage.get_parent() != null or not storage.is_queued_for_deletion():
		_fail("Left click did not immediately remove a completed building.")
		return
	if not building_manager.is_demolishing():
		_fail("Demolition mode did not remain active after demolition.")
		return
	await process_frame
	await physics_frame

	building_manager._start_placement(building_scene, Vector2(96.0, 96.0))
	if not building_manager._can_place_at(Vector2(-800.0, -400.0)):
		_fail("A demolished footprint did not become placeable again.")
		return
	building_manager._cancel_placement()
	_send_key(building_manager, KEY_X)

	var site := site_scene.instantiate() as ConstructionSite
	site.position = Vector2(-608.0, -400.0)
	site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"wood",
		10,
		10.0
	)
	site.construction_completed.connect(
		Callable(building_manager, "_on_construction_completed")
	)
	buildings.add_child(site)
	site.store_resource(&"wood", 6)
	await process_frame

	_send_left_click(main, selection_manager, site.global_position)
	if site.get_parent() != null or not site.is_queued_for_deletion():
		_fail("Construction site could not be demolished.")
		return
	await process_frame
	if not get_nodes_in_group(&"construction_sites").is_empty():
		_fail("Demolished construction site remained in its group.")
		return
	if not get_nodes_in_group(&"houses").is_empty():
		_fail("Demolishing a site incorrectly completed its building.")
		return

	_send_left_click(main, selection_manager, town_center.global_position)
	if not is_instance_valid(town_center) or town_center.get_parent() != buildings:
		_fail("Town center must not be demolishable.")
		return

	var haul_source := building_scene.instantiate() as Building
	var haul_destination := building_scene.instantiate() as Building
	haul_source.position = Vector2(-416.0, -400.0)
	haul_destination.position = Vector2(-224.0, -400.0)
	buildings.add_child(haul_source)
	buildings.add_child(haul_destination)
	haul_source.store_resource(&"wood", 5)
	var worker := main.get_node("Villagers/Villager1") as Villager
	worker.start_haul_job(haul_source, haul_destination, [], 5)
	await process_frame
	if worker._haul_source != haul_source:
		_fail("Test setup did not start a haul job.")
		return
	if not building_manager.demolish_building(haul_source):
		_fail("Active haul source could not be demolished.")
		return
	await physics_frame
	await physics_frame
	if worker.get_state_name() != "IDLE" or worker._haul_source != null:
		_fail(
			"Villager did not cancel a job targeting a demolished building: %s."
			% worker.get_state_name()
		)
		return

	var active_site := site_scene.instantiate() as ConstructionSite
	active_site.position = Vector2(-32.0, -400.0)
	active_site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"wood",
		10,
		10.0
	)
	buildings.add_child(active_site)
	worker.construct_at(active_site)
	await process_frame
	if worker._construction_target != active_site:
		_fail("Test setup did not assign a construction target.")
		return
	if not building_manager.demolish_building(active_site):
		_fail("Active construction target could not be demolished.")
		return
	await physics_frame
	await physics_frame
	if worker.get_state_name() != "IDLE" or worker._construction_target != null:
		_fail("Builder did not cancel work at a demolished site.")
		return

	building_manager._start_placement(building_scene, Vector2(96.0, 96.0))
	if building_manager.is_demolishing():
		_fail("Starting placement did not exit demolition mode.")
		return
	building_manager._cancel_placement()

	selection_manager._select_only(
		main.get_node("Villagers/Villager1") as Villager
	)
	selection_manager.begin_construction_planning()
	if not selection_manager.is_command_planning():
		_fail("Test setup did not start command planning.")
		return
	_send_key(building_manager, KEY_X)
	if selection_manager.is_command_planning():
		_fail("Demolition mode did not cancel command planning.")
		return

	_send_right_click(main, selection_manager, Vector2.ZERO)
	if building_manager.is_demolishing():
		_fail("Right click did not exit demolition mode.")
		return

	_send_key(building_manager, KEY_X)
	_send_key(building_manager, KEY_ESCAPE)
	if building_manager.is_demolishing():
		_fail("Escape did not exit demolition mode.")
		return

	_send_key(building_manager, KEY_X)
	_send_key(building_manager, KEY_B)
	if building_manager.is_demolishing() or not building_manager.building_menu.visible:
		_fail("B did not replace demolition mode with the building menu.")
		return

	quit(0)


func _send_key(building_manager: Node, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	building_manager._unhandled_input(event)


func _send_left_click(
	main: Node2D,
	selection_manager: Node,
	world_position: Vector2
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = main.get_viewport().get_canvas_transform() * world_position
	selection_manager._unhandled_input(event)


func _send_right_click(
	main: Node2D,
	selection_manager: Node,
	world_position: Vector2
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = main.get_viewport().get_canvas_transform() * world_position
	selection_manager._unhandled_input(event)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
