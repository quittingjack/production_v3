extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var building_scene := load("res://scenes/building.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var buildings := main.get_node("Buildings")
	var building_manager := main.get_node("BuildingManager")
	var started_sites: Array[ConstructionSite] = []
	building_manager.construction_started.connect(
		func(site: ConstructionSite) -> void:
			started_sites.append(site)
	)

	building_manager._start_placement(
		building_scene,
		Vector2(96.0, 96.0)
	)
	_place_at(building_manager, Vector2(-800.0, -400.0), true)
	if not _expect_placement_state(
		building_manager,
		buildings,
		started_sites,
		1,
		true
	):
		return

	_place_at(building_manager, Vector2(-608.0, -400.0), true)
	if not _expect_placement_state(
		building_manager,
		buildings,
		started_sites,
		2,
		true
	):
		return

	_place_at(building_manager, Vector2(-416.0, -400.0), false)
	if not _expect_placement_state(
		building_manager,
		buildings,
		started_sites,
		3,
		false
	):
		return

	quit(0)


func _place_at(
	building_manager: Node,
	world_position: Vector2,
	shift_pressed: bool
) -> void:
	building_manager._preview_position = world_position
	building_manager._preview.global_position = world_position
	building_manager._placement_is_valid = true

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.shift_pressed = shift_pressed
	building_manager._unhandled_input(event)


func _expect_placement_state(
	building_manager: Node,
	buildings: Node,
	started_sites: Array[ConstructionSite],
	expected_site_count: int,
	expect_placing: bool
) -> bool:
	var site_count := buildings.get_tree().get_nodes_in_group(
		&"construction_sites"
	).size()
	if site_count != expected_site_count:
		_fail("A placement did not create exactly one construction site.")
		return false
	if started_sites.size() != expected_site_count:
		_fail("construction_started was not emitted exactly once per site.")
		return false
	if building_manager._is_placing != expect_placing:
		_fail("The placement mode did not match the Shift-click state.")
		return false
	if building_manager._preview.visible != expect_placing:
		_fail("The placement preview visibility was incorrect.")
		return false
	if expect_placing and building_manager._selected_scene == null:
		_fail("Continuous placement did not retain the selected building.")
		return false
	if not expect_placing and building_manager._selected_scene != null:
		_fail("Normal placement did not clear the selected building.")
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
