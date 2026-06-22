extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var house_scene := load("res://scenes/house.tscn") as PackedScene
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var buildings := main.get_node("Buildings")
	var building_manager := main.get_node("BuildingManager")
	var builder := main.get_node("Villagers/Villager1") as Villager
	var site := site_scene.instantiate() as ConstructionSite
	site.position = Vector2(160.0, 600.0)
	site.initialize(house_scene, Vector2(96.0, 96.0), &"wood", 10, 0.05)
	site.construction_completed.connect(
		Callable(building_manager, "_on_construction_completed")
	)
	buildings.add_child(site)
	await process_frame

	if get_nodes_in_group(&"houses").size() != 0:
		_fail("A construction site must not count as a completed house.")
		return
	if site.get_navigation_obstacle_size() != Vector2(96.0, 96.0):
		_fail("Construction site did not preserve the target footprint.")
		return
	if site.store_resource(&"wood", 9) != 9 or site.is_constructing():
		_fail("Construction started before all materials arrived.")
		return
	if site.store_resource(&"wood", 1) != 1 or site.is_constructing():
		_fail("Construction started without an assigned builder.")
		return
	builder.move_speed = 1000.0
	builder.navigation_agent.max_speed = builder.move_speed
	builder.construct_at(site)

	await create_timer(1.0).timeout
	var houses := get_nodes_in_group(&"houses")
	if houses.size() != 1:
		_fail("Expected one completed house, got %d." % houses.size())
		return
	if get_nodes_in_group(&"construction_sites").size() != 0:
		_fail("Construction site remained after completion.")
		return
	if builder.get_state_name() != "IDLE":
		_fail("Builder did not become idle after construction.")
		return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
