extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var building_scene := load("res://scenes/building.tscn") as PackedScene
	var villager_scene := load("res://scenes/villager.tscn") as PackedScene
	var source := building_scene.instantiate() as Building
	var destination := building_scene.instantiate() as Building
	var first := villager_scene.instantiate() as Villager
	var second := villager_scene.instantiate() as Villager
	var third := villager_scene.instantiate() as Villager
	root.add_child(source)
	root.add_child(destination)
	root.add_child(first)
	root.add_child(second)
	root.add_child(third)

	var job := TotalHaulJob.new(source, destination, &"wood", 7)
	var first_claim := job.claim_amount(first, 5)
	var second_claim := job.claim_amount(second, 5)
	var third_claim := job.claim_amount(third, 5)
	if first_claim != 5 or second_claim != 2 or third_claim != 0:
		_fail("Shared claims exceeded or failed to fill the target amount.")
		return
	if not job.is_fully_covered() or job.is_complete():
		_fail("Reserved cargo should cover, but not complete, the job.")
		return

	job.adjust_claim_after_pickup(first, 5)
	job.record_delivery(first, destination.store_resource(&"wood", 5))
	if job.delivered_amount != 5 or job.get_unreserved_amount() != 0:
		_fail("First delivery did not preserve the second villager's claim.")
		return

	job.adjust_claim_after_pickup(second, 2)
	job.record_delivery(second, destination.store_resource(&"wood", 2))
	if not job.is_complete() or destination.stored_amount != 7:
		_fail("Total haul did not stop at the exact requested amount.")
		return

	var release_job := TotalHaulJob.new(source, destination, &"wood", 4)
	if release_job.claim_amount(first, 4) != 4:
		_fail("Unable to create a claim for release testing.")
		return
	release_job.release_claim(first)
	if release_job.claim_amount(second, 4) != 4:
		_fail("Released quota was not made available to another villager.")
		return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

