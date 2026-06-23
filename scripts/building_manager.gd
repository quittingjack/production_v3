extends Node2D

signal construction_started(site: ConstructionSite)
signal building_completed(building: Node2D)

const BUILDING_SCENE := preload("res://scenes/building.tscn")
const FACTORY_SCENE := preload("res://scenes/factory.tscn")
const HOUSE_SCENE := preload("res://scenes/house.tscn")
const CONSTRUCTION_SITE_SCENE := preload("res://scenes/construction_site.tscn")
const BUILDING_SIZE := Vector2(96.0, 96.0)
const FACTORY_SIZE := Vector2(128.0, 96.0)
const GRID_SIZE := 32.0
const NAVIGATION_CLEARANCE := 36.0
const VALID_COLOR := Color(0.25, 0.9, 0.4, 0.55)
const INVALID_COLOR := Color(0.95, 0.25, 0.25, 0.55)
const DEMOLITION_CURSOR_COLOR := Color(1.0, 0.12, 0.12, 0.95)
const DEMOLITION_CURSOR_SIZE := 18.0
const DEMOLITION_CURSOR_WIDTH := 5.0

@export var navigation_bounds := Rect2(-1440.0, -1024.0, 3808.0, 2464.0)

@onready var navigation_region: NavigationRegion2D = $"../NavigationRegion2D"
@onready var buildings: Node2D = $"../Buildings"
@onready var building_menu: PanelContainer = $"../Interface/BuildingMenu"
@onready var storage_button: Button = $"../Interface/BuildingMenu/MenuContent/StorageButton"
@onready var factory_button: Button = $"../Interface/BuildingMenu/MenuContent/FactoryButton"
@onready var house_button: Button = $"../Interface/BuildingMenu/MenuContent/HouseButton"
@onready var cancel_button: Button = $"../Interface/BuildingMenu/MenuContent/CancelButton"

var _is_placing := false
var _selected_scene: PackedScene
var _selected_size := BUILDING_SIZE
var _preview: Polygon2D
var _preview_position := Vector2.ZERO
var _placement_is_valid := false
var _is_demolishing := false
var _demolition_cursor: Node2D


func _ready() -> void:
	add_to_group(&"building_managers")
	_create_preview()
	_create_demolition_cursor()
	storage_button.pressed.connect(
		_start_placement.bind(BUILDING_SCENE, BUILDING_SIZE)
	)
	factory_button.pressed.connect(
		_start_placement.bind(FACTORY_SCENE, FACTORY_SIZE)
	)
	house_button.pressed.connect(
		_start_placement.bind(HOUSE_SCENE, BUILDING_SIZE)
	)
	cancel_button.pressed.connect(_close_building_menu)
	_rebuild_navigation()


func _process(_delta: float) -> void:
	if _is_demolishing:
		_demolition_cursor.global_position = get_global_mouse_position()

	if _is_placing:
		_preview_position = _snap_to_grid(get_global_mouse_position())
		_preview.global_position = _preview_position
		_placement_is_valid = _can_place_at(_preview_position)
		_preview.color = VALID_COLOR if _placement_is_valid else INVALID_COLOR


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if (
			key_event.pressed
			and not key_event.echo
			and key_event.keycode == KEY_X
		):
			if _is_demolishing:
				cancel_demolition()
			else:
				_start_demolition()
			get_viewport().set_input_as_handled()
			return

		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_B:
			if _is_demolishing:
				cancel_demolition()
			if _is_placing:
				_cancel_placement()
			_toggle_building_menu()
			get_viewport().set_input_as_handled()
			return

		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			if _is_demolishing:
				cancel_demolition()
			elif _is_placing:
				_cancel_placement()
			elif building_menu.visible:
				_close_building_menu()
			get_viewport().set_input_as_handled()
			return

	if not _is_placing or not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if _placement_is_valid:
			_place_building(mouse_event.shift_pressed)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_placement()
		get_viewport().set_input_as_handled()


func is_placing() -> bool:
	return _is_placing or building_menu.visible


func is_demolishing() -> bool:
	return _is_demolishing


func cancel_demolition() -> void:
	_is_demolishing = false
	if is_instance_valid(_demolition_cursor):
		_demolition_cursor.visible = false


func demolish_building(target: BuildableBuilding) -> bool:
	if (
		not _is_demolishing
		or not is_instance_valid(target)
		or target.is_queued_for_deletion()
		or target.get_parent() != buildings
	):
		return false

	if target is ConstructionSite:
		var site := target as ConstructionSite
		var completion_callback := Callable(self, "_on_construction_completed")
		if site.construction_completed.is_connected(completion_callback):
			site.construction_completed.disconnect(completion_callback)

	buildings.remove_child(target)
	target.queue_free()
	_rebuild_navigation()
	return true


func _create_preview() -> void:
	_preview = Polygon2D.new()
	_preview.name = "BuildingPreview"
	_preview.z_index = 5
	_preview.polygon = _rectangle_polygon(BUILDING_SIZE * 0.5)
	_preview.color = VALID_COLOR
	_preview.visible = false
	add_child(_preview)


func _create_demolition_cursor() -> void:
	_demolition_cursor = Node2D.new()
	_demolition_cursor.name = "DemolitionCursor"
	_demolition_cursor.z_index = 100
	_demolition_cursor.visible = false
	add_child(_demolition_cursor)

	for direction in [1.0, -1.0]:
		var line := Line2D.new()
		line.width = DEMOLITION_CURSOR_WIDTH
		line.default_color = DEMOLITION_CURSOR_COLOR
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true
		line.points = PackedVector2Array([
			Vector2(-DEMOLITION_CURSOR_SIZE, -DEMOLITION_CURSOR_SIZE * direction),
			Vector2(DEMOLITION_CURSOR_SIZE, DEMOLITION_CURSOR_SIZE * direction),
		])
		_demolition_cursor.add_child(line)


func _start_demolition() -> void:
	if _is_placing:
		_cancel_placement()
	_close_building_menu()
	for node in get_tree().get_nodes_in_group(&"selection_managers"):
		if node.has_method("cancel_command_planning"):
			node.cancel_command_planning()
	_is_demolishing = true
	_demolition_cursor.global_position = get_global_mouse_position()
	_demolition_cursor.visible = true


func _start_placement(scene: PackedScene, building_size: Vector2) -> void:
	if _is_demolishing:
		cancel_demolition()
	_selected_scene = scene
	_selected_size = building_size
	building_menu.hide()
	_is_placing = true
	_preview.polygon = _rectangle_polygon(_selected_size * 0.5)
	_preview.visible = true
	_preview_position = _snap_to_grid(get_global_mouse_position())
	_preview.global_position = _preview_position
	_placement_is_valid = _can_place_at(_preview_position)
	_preview.color = VALID_COLOR if _placement_is_valid else INVALID_COLOR


func _cancel_placement() -> void:
	_is_placing = false
	_preview.visible = false
	_selected_scene = null


func _place_building(continue_placement := false) -> void:
	if not _selected_scene:
		return
	var site := CONSTRUCTION_SITE_SCENE.instantiate() as ConstructionSite
	var target_building := _selected_scene.instantiate() as BuildableBuilding
	if not site or not target_building:
		push_error("Building placement requires a BuildableBuilding scene.")
		return

	site.position = _preview_position
	site.initialize(
		_selected_scene,
		_selected_size,
		target_building.construction_resource_type,
		target_building.construction_material_amount,
		target_building.construction_duration
	)
	target_building.free()
	site.construction_completed.connect(_on_construction_completed)
	buildings.add_child(site)
	if continue_placement:
		_placement_is_valid = false
		_preview.color = INVALID_COLOR
	else:
		_cancel_placement()
	_rebuild_navigation()
	construction_started.emit(site)


func _on_construction_completed(
	site: ConstructionSite,
	target_scene: PackedScene,
	auto_hire_candidates: Array[Villager]
) -> void:
	if not is_instance_valid(site) or not target_scene:
		return

	var completed_building := target_scene.instantiate() as Node2D
	if not completed_building:
		push_error("Construction target must instantiate as Node2D.")
		return

	completed_building.position = site.position
	buildings.remove_child(site)
	site.queue_free()
	buildings.add_child(completed_building)
	if completed_building is Factory and not auto_hire_candidates.is_empty():
		var candidate: Villager = auto_hire_candidates.pick_random()
		if is_instance_valid(candidate):
			candidate.work_at_factory(completed_building as Factory)
	_rebuild_navigation()
	building_completed.emit(completed_building)


func request_navigation_rebuild() -> void:
	_rebuild_navigation()


func _can_place_at(world_position: Vector2) -> bool:
	var building_rect := Rect2(
		world_position - _selected_size * 0.5,
		_selected_size
	)
	if not navigation_bounds.encloses(building_rect):
		return false

	var shape := RectangleShape2D.new()
	shape.size = _selected_size

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, world_position)
	query.collision_mask = 3
	query.collide_with_areas = false
	query.collide_with_bodies = true

	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _toggle_building_menu() -> void:
	building_menu.visible = not building_menu.visible


func _close_building_menu() -> void:
	building_menu.hide()


func _rebuild_navigation() -> void:
	var navigation_polygon := NavigationPolygon.new()
	navigation_polygon.agent_radius = NAVIGATION_CLEARANCE
	navigation_polygon.cell_size = 1.0

	var source_geometry := NavigationMeshSourceGeometryData2D.new()
	source_geometry.add_traversable_outline(_rect_outline(navigation_bounds))

	var obstacle_nodes: Array[Node] = []
	obstacle_nodes.append_array(get_tree().get_nodes_in_group(&"buildings"))
	obstacle_nodes.append_array(get_tree().get_nodes_in_group(&"resources"))

	for node in obstacle_nodes:
		var obstacle := node as Node2D
		if not obstacle or not obstacle.has_method("get_navigation_obstacle_size"):
			continue
		var obstacle_size: Vector2 = obstacle.get_navigation_obstacle_size()
		var obstruction := _rectangle_polygon(
			obstacle_size * 0.5 + Vector2.ONE * NAVIGATION_CLEARANCE
		)
		for index in obstruction.size():
			obstruction[index] += obstacle.global_position
		source_geometry.add_projected_obstruction(obstruction, true)

	NavigationServer2D.bake_from_source_geometry_data(
		navigation_polygon,
		source_geometry
	)
	navigation_region.navigation_polygon = navigation_polygon
	NavigationServer2D.region_set_navigation_polygon(
		navigation_region.get_rid(),
		navigation_polygon
	)
	NavigationServer2D.map_force_update(navigation_region.get_navigation_map())

	for node in get_tree().get_nodes_in_group(&"villagers"):
		var villager := node as Villager
		if villager:
			villager.call_deferred("refresh_navigation_target")


func _snap_to_grid(world_position: Vector2) -> Vector2:
	return world_position.snapped(Vector2.ONE * GRID_SIZE)


func _rect_outline(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


func _rectangle_polygon(half_size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
	])
