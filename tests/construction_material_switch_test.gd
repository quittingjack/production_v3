extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var villager_scene := load("res://scenes/villager.tscn") as PackedScene
	var building_scene := load("res://scenes/building.tscn") as PackedScene
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var house_scene := load("res://scenes/house.tscn") as PackedScene
	var villager := villager_scene.instantiate() as Villager
	var source := building_scene.instantiate() as Building
	var site := site_scene.instantiate() as ConstructionSite
	source.accepted_resource_type = &"stone"
	site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"stone",
		5,
		100.0
	)
	root.add_child(villager)
	root.add_child(source)
	root.add_child(site)
	await process_frame

	villager._backpack_resource_type = &"wood"
	villager._backpack_amount = 3
	villager._update_backpack_label()
	var job := ConstructionJob.new(source, site)
	villager.start_construction_job(job, [], true)

	if villager.get_current_work_type_name() != "CONSTRUCTION_JOB":
		_fail("Different carried material cancelled the construction job.")
		return
	if not villager.get_state_name().begins_with("HAUL_"):
		_fail("Villager did not continue toward the construction material.")
		return
	if (
		villager._backpack_resource_type != &"wood"
		or villager._backpack_amount != 3
	):
		_fail("Old material was discarded before new material was available.")
		return

	villager._take_haul_output()
	if (
		villager._backpack_resource_type != &"wood"
		or villager._backpack_amount != 3
	):
		_fail("Failed pickup discarded the old material.")
		return

	source.store_resource(&"stone", 5)
	villager._take_haul_output()
	if (
		villager._backpack_resource_type != &"stone"
		or villager._backpack_amount != 5
	):
		_fail("Successful pickup did not replace the old material.")
		return
	if source.stored_amount != 0 or job.get_claimed_amount(villager) != 5:
		_fail("Construction material pickup did not preserve its claim.")
		return
	if not villager.get_state_name().begins_with("HAUL_"):
		_fail("Construction hauling did not continue after material replacement.")
		return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
