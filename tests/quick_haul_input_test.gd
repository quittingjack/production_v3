extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var building_scene := load("res://scenes/building.tscn") as PackedScene
	var factory_scene := load("res://scenes/factory.tscn") as PackedScene
	var resource_scene := load("res://scenes/wood_resource.tscn") as PackedScene
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var house_scene := load("res://scenes/house.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var buildings := main.get_node("Buildings")
	var resources := main.get_node("Resources")
	var selection_manager := main.get_node("SelectionManager")
	var villager := main.get_node("Villagers/Villager1") as Villager
	selection_manager._select_only(villager)

	var resource := resource_scene.instantiate() as ResourceNode
	resource.position = Vector2(760.0, 700.0)
	resources.add_child(resource)
	await process_frame

	_send_right_button(main, selection_manager, resource.global_position)
	if (
		villager.get_current_work_type_name() != "GATHER"
		or villager.get_work_queue_count() != 1
	):
		_fail("Right-clicking a resource did not issue a finite gather order.")
		return
	villager.backpack_capacity = 2
	villager._gather_once()
	villager._gather_once()
	if (
		villager._backpack_amount != 2
		or villager.get_work_queue_count() != 0
		or villager.get_state_name() != "IDLE"
	):
		_fail("Finite gather did not stop with a full backpack.")
		return
	villager.backpack_capacity = 5
	villager._clear_backpack()

	_send_right_button(main, selection_manager, resource.global_position)
	_send_right_button(
		main,
		selection_manager,
		Vector2(920.0, 700.0),
		true
	)
	if villager.get_work_queue_count() != 2:
		_fail("Shift + right-click did not append a command.")
		return

	villager.stop_all_work()
	_send_right_button(main, selection_manager, Vector2(1000.0, 700.0))
	_send_right_button(
		main,
		selection_manager,
		Vector2(1120.0, 700.0),
		false,
		true
	)
	villager._complete_current_work_order()
	if (
		villager.get_work_queue_count() != 2
		or villager._target_position != Vector2(1120.0, 700.0)
	):
		_fail("Ctrl + right-click did not preserve the looping queue.")
		return
	villager._complete_current_work_order()
	if (
		villager.get_work_queue_count() != 2
		or villager._target_position != Vector2(1000.0, 700.0)
	):
		_fail("Ctrl queue did not repeat from the first command.")
		return

	_send_key(selection_manager, KEY_S)
	if (
		villager.get_work_queue_count() != 0
		or villager.get_state_name() != "IDLE"
	):
		_fail("S did not stop all selected villager work.")
		return

	var building := building_scene.instantiate() as Building
	building.position = Vector2(1280.0, 700.0)
	buildings.add_child(building)
	await process_frame

	villager._backpack_resource_type = &"wood"
	villager._backpack_amount = 3
	villager._update_backpack_label()
	_send_right_button(main, selection_manager, building.global_position)
	if villager.get_current_work_type_name() != "INTERACT_BUILDING":
		_fail("Right-clicking a building did not issue a smart interaction.")
		return
	villager._perform_building_interaction()
	if building.stored_amount != 3 or villager._backpack_amount != 0:
		_fail("Smart building interaction did not deposit carried input.")
		return

	_send_right_button(main, selection_manager, building.global_position)
	villager._perform_building_interaction()
	if villager._backpack_amount != 3 or building.stored_amount != 0:
		_fail("Smart building interaction did not take available output.")
		return

	villager.stop_all_work()
	building.store_resource(&"wood", 2)
	villager._backpack_resource_type = &"stone"
	villager._backpack_amount = 1
	villager._update_backpack_label()
	_send_right_button(main, selection_manager, building.global_position)
	if (
		villager.get_state_name() != "MOVING"
		or villager._backpack_resource_type != &"stone"
		or villager._backpack_amount != 1
	):
		_fail("Mismatched carried resource was discarded or mishandled.")
		return

	villager.stop_all_work()
	var site := site_scene.instantiate() as ConstructionSite
	site.initialize(house_scene, Vector2(96.0, 96.0), &"wood", 5, 10.0)
	site.position = Vector2(1480.0, 700.0)
	buildings.add_child(site)
	villager._backpack_resource_type = &"wood"
	villager._backpack_amount = 2
	villager._update_backpack_label()
	await process_frame
	_send_right_button(main, selection_manager, site.global_position)
	villager._perform_building_interaction()
	if site.stored_amount != 2 or villager._construction_target != site:
		_fail("Construction-site interaction did not deposit and wait.")
		return

	villager.stop_all_work()
	var factory := factory_scene.instantiate() as Factory
	factory.position = Vector2(1680.0, 700.0)
	buildings.add_child(factory)
	await process_frame
	_send_right_button(main, selection_manager, factory.global_position)
	if factory.get_worker() != villager:
		_fail("Right-clicking an empty factory did not preserve hiring.")
		return

	quit(0)


func _send_right_button(
	main: Node2D,
	selection_manager: Node,
	world_position: Vector2,
	shift_pressed := false,
	ctrl_pressed := false
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.shift_pressed = shift_pressed
	event.ctrl_pressed = ctrl_pressed
	event.position = (
		main.get_viewport().get_canvas_transform() * world_position
	)
	selection_manager._unhandled_input(event)


func _send_key(selection_manager: Node, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = keycode
	selection_manager._unhandled_input(event)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
