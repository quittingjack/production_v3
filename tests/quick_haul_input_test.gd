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
	if not selection_manager.is_haul_planning():
		_fail("Right-button press on a valid source did not start haul planning.")
		return

	_send_right_button(main, selection_manager, destination.global_position, false)
	await process_frame
	if selection_manager.is_haul_planning():
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
	await process_frame
	_send_right_button(main, selection_manager, source.global_position, false)
	await process_frame
	if selection_manager.is_haul_planning():
		_fail("Releasing on the source building did not cancel haul planning.")
		return

	_send_right_button(main, selection_manager, source.global_position, true)
	await process_frame
	_send_right_button(
		main,
		selection_manager,
		Vector2(1300.0, 850.0),
		false
	)
	await process_frame
	if selection_manager.is_haul_planning():
		_fail("Releasing on empty ground did not cancel haul planning.")
		return

	var construction_site := site_scene.instantiate() as ConstructionSite
	construction_site.position = Vector2(1320.0, 700.0)
	buildings.add_child(construction_site)
	await process_frame
	_send_right_button(
		main,
		selection_manager,
		construction_site.global_position,
		true
	)
	await process_frame
	if selection_manager.is_haul_planning():
		_fail("A building without output incorrectly started haul planning.")
		return
	if first._construction_target != construction_site:
		_fail("An invalid haul source did not preserve its original command.")
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
