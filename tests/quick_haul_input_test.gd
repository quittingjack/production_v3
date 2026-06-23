extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var building_scene := load("res://scenes/building.tscn") as PackedScene
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var buildings := main.get_node("Buildings")
	var selection_manager := main.get_node("SelectionManager")
	var first := main.get_node("Villagers/Villager1") as Villager
	var second := main.get_node("Villagers/Villager2") as Villager
	var source := building_scene.instantiate() as Building
	var destination := building_scene.instantiate() as Building
	source.position = Vector2(760.0, 700.0)
	destination.position = Vector2(1080.0, 700.0)
	buildings.add_child(source)
	buildings.add_child(destination)
	await process_frame

	first.backpack_capacity = 3
	second.backpack_capacity = 7
	selection_manager._select_villagers_in(
		Rect2(Vector2(240.0, 170.0), Vector2(230.0, 100.0))
	)
	if selection_manager.get_selected_villagers().size() != 2:
		_fail("Test setup did not select exactly two villagers.")
		return

	_send_right_button(main, selection_manager, source.global_position, true)
	await process_frame
	if selection_manager.is_command_planning():
		_fail("Right-button press started haul planning before a gesture threshold.")
		return
	_send_right_motion(
		main,
		selection_manager,
		source.global_position,
		Vector2(4.0, 0.0)
	)
	if selection_manager.is_command_planning():
		_fail("Sub-threshold pointer movement started haul planning.")
		return
	_send_right_button(main, selection_manager, source.global_position, false)
	await process_frame
	if (
		first.get_current_work_type_name() != "MOVE"
		or second.get_current_work_type_name() != "MOVE"
	):
		_fail("A short right click on a source did not issue a normal command.")
		return

	selection_manager.right_hold_threshold = 0.01
	_send_right_button(main, selection_manager, source.global_position, true)
	await create_timer(0.03).timeout
	if not selection_manager.is_command_planning():
		_fail("Holding the right button did not start haul planning.")
		return
	_send_right_button(main, selection_manager, source.global_position, false)
	await process_frame
	if selection_manager.is_command_planning():
		_fail("Releasing a held gesture on its source did not cancel planning.")
		return
	selection_manager.right_hold_threshold = 0.35

	_send_right_button(main, selection_manager, source.global_position, true)
	_send_right_motion(
		main,
		selection_manager,
		source.global_position,
		Vector2(9.0, 0.0)
	)
	if not selection_manager.is_command_planning():
		_fail("Dragging beyond eight screen pixels did not start haul planning.")
		return
	_send_right_button(main, selection_manager, destination.global_position, false)
	await process_frame
	if selection_manager.is_command_planning():
		_fail("Right-button release did not finish haul planning.")
		return
	if first._haul_amount_per_trip != 3 or second._haul_amount_per_trip != 7:
		_fail("Quick haul did not use each villager's backpack capacity.")
		return
	if first._haul_source != source or second._haul_source != source:
		_fail("Quick haul assigned the wrong source building.")
		return
	if first._haul_destination != destination or second._haul_destination != destination:
		_fail("Quick haul assigned the wrong destination building.")
		return

	_send_right_button(main, selection_manager, source.global_position, true)
	_send_right_motion(
		main,
		selection_manager,
		source.global_position,
		Vector2(9.0, 0.0)
	)
	_send_right_button(
		main,
		selection_manager,
		destination.global_position,
		false,
		true
	)
	await process_frame
	if (
		first.get_work_queue_count() != 2
		or second.get_work_queue_count() != 2
	):
		_fail("Shift on quick-haul release did not append the job.")
		return

	_send_right_button(main, selection_manager, source.global_position, true)
	_send_right_motion(
		main,
		selection_manager,
		source.global_position,
		Vector2(9.0, 0.0)
	)
	_send_right_button(main, selection_manager, source.global_position, false)
	await process_frame
	if selection_manager.is_command_planning():
		_fail("Releasing on the source building did not cancel haul planning.")
		return

	_send_right_button(main, selection_manager, source.global_position, true)
	_send_right_motion(
		main,
		selection_manager,
		source.global_position,
		Vector2(9.0, 0.0)
	)
	_send_right_button(
		main,
		selection_manager,
		Vector2(1300.0, 850.0),
		false
	)
	await process_frame
	if selection_manager.is_command_planning():
		_fail("Releasing on empty ground did not cancel haul planning.")
		return

	var construction_site := site_scene.instantiate() as ConstructionSite
	var house_scene := load("res://scenes/house.tscn") as PackedScene
	construction_site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"wood",
		3,
		10.0
	)
	construction_site.position = Vector2(1320.0, 700.0)
	buildings.add_child(construction_site)
	source.store_resource(&"wood", 3)
	await process_frame
	_send_right_button(
		main,
		selection_manager,
		source.global_position,
		true
	)
	_send_right_motion(
		main,
		selection_manager,
		source.global_position,
		Vector2(9.0, 0.0)
	)
	_send_right_button(
		main,
		selection_manager,
		construction_site.global_position,
		false
	)
	await process_frame
	if selection_manager.is_command_planning():
		_fail("Quick construction planning did not finish.")
		return
	if first._construction_job == null:
		_fail("Quick haul to a site did not create a construction job.")
		return
	if second._construction_target != construction_site:
		_fail("An excess villager did not go directly to construction.")
		return

	var queued_site := site_scene.instantiate() as ConstructionSite
	queued_site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"wood",
		0,
		10.0
	)
	queued_site.position = Vector2(1480.0, 700.0)
	buildings.add_child(queued_site)
	await process_frame
	selection_manager.begin_construction_planning()
	_send_left_button(
		main,
		selection_manager,
		source.global_position,
		false
	)
	_send_left_button(
		main,
		selection_manager,
		queued_site.global_position,
		true
	)
	await process_frame
	if (
		first.get_work_queue_count() != 2
		or second.get_work_queue_count() != 2
	):
		_fail("Shift on the final construction click did not append the job.")
		return

	quit(0)


func _send_right_button(
	main: Node2D,
	selection_manager: Node,
	world_position: Vector2,
	pressed: bool,
	shift_pressed := false
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	event.position = (
		main.get_viewport().get_canvas_transform() * world_position
	)
	if pressed:
		selection_manager._unhandled_input(event)
	else:
		selection_manager._input(event)


func _send_right_motion(
	main: Node2D,
	selection_manager: Node,
	world_position: Vector2,
	screen_offset: Vector2
) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	event.position = (
		main.get_viewport().get_canvas_transform() * world_position
		+ screen_offset
	)
	selection_manager._input(event)


func _send_left_button(
	main: Node2D,
	selection_manager: Node,
	world_position: Vector2,
	shift_pressed: bool
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.shift_pressed = shift_pressed
	event.position = (
		main.get_viewport().get_canvas_transform() * world_position
	)
	selection_manager._unhandled_input(event)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
