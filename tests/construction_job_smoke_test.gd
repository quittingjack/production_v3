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
	var source := building_scene.instantiate() as Building
	var site := site_scene.instantiate() as ConstructionSite
	source.position = Vector2(760.0, 700.0)
	site.position = Vector2(1080.0, 700.0)
	site.initialize(house_scene, Vector2(96.0, 96.0), &"wood", 7, 100.0)
	buildings.add_child(source)
	buildings.add_child(site)
	source.store_resource(&"wood", 3)
	await process_frame

	var villagers: Array[Villager] = []
	for node in get_nodes_in_group(&"villagers"):
		var villager := node as Villager
		if villager and villagers.size() < 3:
			villager.move_speed = 1000.0
			villager.navigation_agent.max_speed = villager.move_speed
			villager.backpack_capacity = 5
			villagers.append(villager)

	var job := ConstructionJob.new(source, site)
	villagers[0].start_construction_job(job, [], true)
	villagers[1].start_construction_job(job, [], true)
	villagers[2].start_construction_job(job, [], false)

	await create_timer(2.0).timeout
	if site.stored_amount != 3:
		_fail("Available construction material was not delivered.")
		return
	if not villagers[0].get_state_name().begins_with("HAUL_"):
		_fail("A hauler did not wait for missing source material.")
		return
	if villagers[2]._construction_target != site:
		_fail("An excess villager did not wait at the construction site.")
		return

	source.store_resource(&"wood", 4)
	await create_timer(4.0).timeout
	if not site.is_constructing():
		_fail("Construction did not begin after all material arrived.")
		return
	if source.stored_amount != 0:
		_fail("Construction hauled more material than required.")
		return
	for villager in villagers:
		if villager._construction_target != site:
			_fail("A participant did not transition to construction.")
			return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
