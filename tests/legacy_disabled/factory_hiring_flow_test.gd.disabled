extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var factory_scene := load("res://scenes/factory.tscn") as PackedScene
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var buildings := main.get_node("Buildings")
	var selection_manager := main.get_node("SelectionManager")
	var building_manager := main.get_node("BuildingManager")
	var first := main.get_node("Villagers/Villager1") as Villager
	var second := main.get_node("Villagers/Villager2") as Villager
	var third := main.get_node("Villagers/Villager3") as Villager
	var factory := factory_scene.instantiate() as Factory
	factory.position = Vector2(-800.0, -400.0)
	buildings.add_child(factory)
	first.position = Vector2(-760.0, -400.0)
	second.position = Vector2(-300.0, -400.0)
	await process_frame

	selection_manager._selected_villagers.assign([first, second])
	_send_right_button(main, selection_manager, factory.global_position, true)
	await process_frame
	if factory.has_worker() or selection_manager.is_command_planning():
		_fail("Pressing a factory immediately hired or started planning.")
		return
	_send_right_button(main, selection_manager, factory.global_position, false)
	await process_frame
	if factory.get_worker() != first:
		_fail("A short factory right click did not hire the nearest villager.")
		return
	if second.get_current_work_type_name() != "MOVE":
		_fail("Non-hired villagers did not receive the approach command.")
		return

	selection_manager._selected_villagers.assign([third])
	selection_manager._command_selection_at(factory.global_position)
	if factory.get_worker() != first:
		_fail("Commanding an occupied factory replaced its worker.")
		return
	if third.get_current_work_type_name() != "MOVE":
		_fail("Occupied factory command did not become an approach command.")
		return

	var queued_factory := factory_scene.instantiate() as Factory
	queued_factory.position = Vector2(-608.0, -400.0)
	buildings.add_child(queued_factory)
	third.move_to(Vector2(0.0, 0.0))
	selection_manager._selected_villagers.assign([third])
	selection_manager._command_selection_at(
		queued_factory.global_position,
		true
	)
	if queued_factory.get_worker() != third:
		_fail("Queued factory work did not reserve the vacancy immediately.")
		return
	if third.get_work_queue_count() != 2:
		_fail("Queued factory work did not preserve the current order.")
		return
	third.move_to(Vector2(64.0, 64.0))
	if not queued_factory.has_vacancy():
		_fail("Replacing a queued factory order did not release its vacancy.")
		return

	var candidate_site := site_scene.instantiate() as ConstructionSite
	candidate_site.initialize(
		factory_scene,
		Vector2(128.0, 96.0),
		&"wood",
		0,
		1.0
	)
	buildings.add_child(candidate_site)
	first.move_to(Vector2(10.0, 10.0))
	first.construct_at(candidate_site)
	first.move_to(Vector2(20.0, 20.0), true)
	second.move_to(Vector2(30.0, 30.0))
	second.construct_at(candidate_site)
	var candidates := candidate_site._finish_builders()
	if candidates.size() != 1 or candidates[0] != second:
		_fail("Auto-hire candidates did not exclude queued builders.")
		return

	var completion_site := site_scene.instantiate() as ConstructionSite
	completion_site.position = Vector2(-416.0, -400.0)
	completion_site.initialize(
		factory_scene,
		Vector2(128.0, 96.0),
		&"wood",
		0,
		1.0
	)
	buildings.add_child(completion_site)
	building_manager._on_construction_completed(
		completion_site,
		factory_scene,
		candidates
	)
	var completed_factory: Factory
	for node in buildings.get_children():
		if node is Factory and node.position == Vector2(-416.0, -400.0):
			completed_factory = node as Factory
			break
	if not completed_factory or completed_factory.get_worker() != second:
		_fail("Completed factory did not retain an eligible builder.")
		return

	quit(0)


func _send_right_button(
	main: Node2D,
	selection_manager: Node,
	world_position: Vector2,
	pressed: bool
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = (
		main.get_viewport().get_canvas_transform() * world_position
	)
	if pressed:
		selection_manager._unhandled_input(event)
	else:
		selection_manager._input(event)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
