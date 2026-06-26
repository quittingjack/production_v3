extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var building_scene := load("res://scenes/building.tscn") as PackedScene
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var house_scene := load("res://scenes/house.tscn") as PackedScene
	var villager_scene := load("res://scenes/villager.tscn") as PackedScene
	var source := building_scene.instantiate() as Building
	var site := site_scene.instantiate() as ConstructionSite
	site.initialize(house_scene, Vector2(96.0, 96.0), &"wood", 7, 10.0)
	var first := villager_scene.instantiate() as Villager
	var second := villager_scene.instantiate() as Villager
	var third := villager_scene.instantiate() as Villager
	root.add_child(source)
	root.add_child(site)
	root.add_child(first)
	root.add_child(second)
	root.add_child(third)
	await process_frame

	var job := ConstructionJob.new(source, site)
	var first_claim := job.claim_amount(first, 5)
	var second_claim := job.claim_amount(second, 5)
	var third_claim := job.claim_amount(third, 5)
	if first_claim != 5 or second_claim != 2 or third_claim != 0:
		_fail("Construction claims did not use maximum capacities.")
		return
	if not job.is_fully_covered() or site.is_material_ready():
		_fail("Reserved cargo should cover the site before delivery.")
		return

	job.adjust_claim_after_pickup(first, 5)
	job.record_delivery(first, site.store_resource(&"wood", 5))
	if site.stored_amount != 5 or job.get_unreserved_amount() != 0:
		_fail("First delivery did not preserve cargo already in transit.")
		return

	job.adjust_claim_after_pickup(second, 2)
	job.record_delivery(second, site.store_resource(&"wood", 2))
	if not site.is_material_ready() or site.stored_amount != 7:
		_fail("Construction materials did not stop at the site requirement.")
		return
	if job.claim_amount(third, 5) != 0:
		_fail("A material-ready site accepted another cargo claim.")
		return

	var release_site := site_scene.instantiate() as ConstructionSite
	release_site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"wood",
		4,
		10.0
	)
	root.add_child(release_site)
	await process_frame
	var release_job := ConstructionJob.new(source, release_site)
	if release_job.claim_amount(first, 4) != 4:
		_fail("Unable to reserve construction material.")
		return
	release_job.release_claim(first)
	if release_job.claim_amount(second, 4) != 4:
		_fail("Released material was not made available.")
		return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
