extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var site_scene := load("res://scenes/construction_site.tscn") as PackedScene
	var house_scene := load("res://scenes/house.tscn") as PackedScene
	var villager_scene := load("res://scenes/villager.tscn") as PackedScene

	var waiting_site := site_scene.instantiate() as ConstructionSite
	waiting_site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"wood",
		2,
		1.0
	)
	root.add_child(waiting_site)
	await process_frame

	var waiting_builders: Array[Villager] = []
	for index in waiting_site.get_interaction_slot_count():
		var builder := villager_scene.instantiate() as Villager
		root.add_child(builder)
		waiting_builders.append(builder)
		var slot := waiting_site.reserve_interaction_slot(
			builder,
			builder.global_position,
			1
		)
		if index < waiting_site.get_interaction_slot_count() - 1 and slot < 0:
			_fail("A construction slot was rejected before the reserved slot.")
			return
		if index == waiting_site.get_interaction_slot_count() - 1 and slot >= 0:
			_fail("Waiting builders did not preserve one delivery slot.")
			return

	waiting_site.queue_free()
	await process_frame

	var one_builder_progress := await _measure_progress(
		site_scene,
		house_scene,
		villager_scene,
		1
	)
	var three_builder_progress := await _measure_progress(
		site_scene,
		house_scene,
		villager_scene,
		3
	)
	if three_builder_progress < one_builder_progress * 2.5:
		_fail(
			"Three builders did not provide approximately linear speed."
		)
		return

	var pause_site := site_scene.instantiate() as ConstructionSite
	pause_site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"wood",
		1,
		1.0
	)
	root.add_child(pause_site)
	var pause_builder := villager_scene.instantiate() as Villager
	root.add_child(pause_builder)
	await process_frame
	pause_site.store_resource(&"wood", 1)
	pause_builder.construct_at(pause_site)
	pause_site.set_builder_active(pause_builder, true)
	await create_timer(0.1).timeout
	var progress_before_cancel := pause_site.get_construction_progress()
	pause_builder.move_to(Vector2(200.0, 0.0))
	await create_timer(0.1).timeout
	if not is_equal_approx(
		pause_site.get_construction_progress(),
		progress_before_cancel
	):
		_fail("Construction continued after the final builder left.")
		return

	quit(0)


func _measure_progress(
	site_scene: PackedScene,
	house_scene: PackedScene,
	villager_scene: PackedScene,
	builder_count: int
) -> float:
	var site := site_scene.instantiate() as ConstructionSite
	site.initialize(
		house_scene,
		Vector2(96.0, 96.0),
		&"wood",
		1,
		2.0
	)
	root.add_child(site)
	await process_frame
	site.store_resource(&"wood", 1)

	var builders: Array[Villager] = []
	for index in builder_count:
		var builder := villager_scene.instantiate() as Villager
		root.add_child(builder)
		builders.append(builder)
		builder.construct_at(site)
		site.set_builder_active(builder, true)

	await create_timer(0.1).timeout
	var progress := site.get_construction_progress()
	site.queue_free()
	for builder in builders:
		builder.queue_free()
	await process_frame
	return progress


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
