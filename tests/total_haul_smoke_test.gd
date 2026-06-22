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
	var source := building_scene.instantiate() as Building
	var destination := building_scene.instantiate() as Building
	source.position = Vector2(760.0, 700.0)
	destination.position = Vector2(1080.0, 700.0)
	buildings.add_child(source)
	buildings.add_child(destination)
	source.store_resource(&"wood", 30)

	var villagers: Array[Villager] = []
	for node in get_nodes_in_group(&"villagers"):
		var villager := node as Villager
		if villager and villagers.size() < 3:
			villager.move_speed = 1000.0
			villager.navigation_agent.max_speed = villager.move_speed
			villagers.append(villager)

	var job := TotalHaulJob.new(source, destination, &"wood", 7)
	for villager in villagers:
		villager.start_total_haul_job(job, [])

	await create_timer(6.0).timeout
	if destination.stored_amount != 7:
		_fail(
			"Expected exactly 7 delivered resources, got %d."
			% destination.stored_amount
		)
		return
	if not job.is_complete():
		_fail("Villager-driven total haul did not complete.")
		return
	for villager in villagers:
		if villager.get_state_name().begins_with("HAUL_"):
			_fail("A villager continued hauling after the total was reached.")
			return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
