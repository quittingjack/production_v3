extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var factory_scene := load("res://scenes/factory.tscn") as PackedScene
	var construction_site_scene := load(
		"res://scenes/construction_site.tscn"
	) as PackedScene
	var house_scene := load("res://scenes/house.tscn") as PackedScene

	var factory := factory_scene.instantiate() as Factory
	factory.production_duration = 0.4
	root.add_child(factory)
	await process_frame

	var factory_status := factory.get_node("StatusLabel") as Label
	var production_progress := factory.get_node(
		"ProductionProgressBar"
	) as ProgressBar
	if not factory_status.visible or production_progress.visible:
		_fail("Factory progress bar must be hidden while waiting for input.")
		return

	factory.store_resource(factory.input_resource_type, factory.input_amount)
	var factory_start_progress := production_progress.value
	if factory_status.visible or not production_progress.visible:
		_fail("Factory progress bar must replace status text during production.")
		return
	if factory_status.text.contains("s"):
		_fail("Factory production status still displays remaining seconds.")
		return

	await create_timer(0.1).timeout
	if production_progress.value <= factory_start_progress:
		_fail("Factory production progress bar did not advance.")
		return

	var site := construction_site_scene.instantiate() as ConstructionSite
	site.initialize(house_scene, Vector2(96.0, 96.0), &"wood", 2, 0.4)
	root.add_child(site)
	await process_frame

	var site_status := site.get_node("StatusLabel") as Label
	var construction_progress := site.get_node(
		"ConstructionProgressBar"
	) as ProgressBar
	if not site_status.visible or construction_progress.visible:
		_fail("Construction progress bar must be hidden while waiting for materials.")
		return

	site.store_resource(&"wood", 2)
	var construction_start_progress := construction_progress.value
	if site_status.visible or not construction_progress.visible:
		_fail("Construction progress bar must replace status text during construction.")
		return
	if site_status.text.contains("s"):
		_fail("Construction status still displays remaining seconds.")
		return

	await create_timer(0.1).timeout
	if construction_progress.value <= construction_start_progress:
		_fail("Construction progress bar did not advance.")
		return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
