extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var house_scene := load("res://scenes/house.tscn") as PackedScene
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var main := main_scene.instantiate()
	var immigration_manager := main.get_node("ImmigrationManager")
	var buildings := main.get_node("Buildings")
	var building_manager := main.get_node("BuildingManager")

	immigration_manager.immigration_interval = 0.05
	immigration_manager.minimum_immigrants = 2
	immigration_manager.maximum_immigrants = 2
	immigration_manager.confirmation_duration = 0.05

	root.add_child(main)
	await create_timer(0.1).timeout

	if get_nodes_in_group(&"villagers").size() != 6:
		push_error("Immigrants arrived without completed houses.")
		quit(1)
		return

	for index in 2:
		var site := site_scene.instantiate() as ConstructionSite
		site.position = Vector2(-400.0 + index * 128.0, 600.0)
		site.initialize(house_scene, Vector2(96.0, 96.0), &"wood", 10, 0.05)
		site.construction_completed.connect(
			Callable(building_manager, "_on_construction_completed")
		)
		buildings.add_child(site)
		site.store_resource(&"wood", 10)

	await create_timer(0.2).timeout

	var villagers := get_nodes_in_group(&"villagers")
	var houses := get_nodes_in_group(&"houses")
	if villagers.size() != 8:
		push_error("Expected 8 villagers, got %d." % villagers.size())
		quit(1)
		return
	for node in houses:
		var house := node as House
		if house and house.is_vacant():
			push_error("Expected every test house to be occupied.")
			quit(1)
			return

	quit(0)
