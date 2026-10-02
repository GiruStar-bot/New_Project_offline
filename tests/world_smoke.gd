extends SceneTree

const World = preload("res://scripts/world/world_state.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var world: RefCounted = World.new()
	check(world.entities.size() == 24 and world.sites.size() == 5, "24 people and five settlements")
	var populations: Dictionary = {"council": 0, "rival": 0, "neutral": 0}
	for person in world.entities:
		populations[person.owner] += 1
		check(world.geography.is_walkable(person.position), "Person spawns on walkable land: %d" % person.id)
	check(populations.council == 10 and populations.rival == 10 and populations.neutral == 4, "Population split")
	var geography: RefCounted = world.geography
	check(not geography.is_walkable(Vector2(100, 600)), "Sea blocked")
	check(not geography.is_walkable(Vector2(480, 470)), "Cliff blocked")
	check(not geography.is_walkable(Vector2(735, 500)), "River blocked")
	check(geography.is_walkable(Vector2(735, 670)), "Bridge traversable")
	var river_path: PackedVector2Array = geography.find_path(Vector2(500, 800), Vector2(1050, 800))
	check(not river_path.is_empty(), "Land route across river exists")
	var uses_bridge: bool = false
	for index in range(river_path.size() - 1):
		check(geography.segment_walkable(river_path[index], river_path[index + 1]), "Path segment stays walkable")
		if river_path[index].y >= 640 and river_path[index].y <= 700:
			uses_bridge = true
	check(uses_bridge, "Cross-river route uses bridge")
	check(geography.find_path(Vector2(500, 800), Vector2(1820, 820)).is_empty(), "No land path to island")
	var detour: PackedVector2Array = geography.find_path(Vector2(360, 470), Vector2(600, 470))
	check(detour.size() > 2, "Route avoids mountain cliff")
	var before: Vector2 = world.entities[0].position
	check(not world.issue_move(0, Vector2(735, 500)).ok, "River destination rejected")
	check(not world.issue_move(0, Vector2(1820, 820)).ok, "Disconnected island rejected")
	check(not world.issue_move(10, Vector2(1050, 800)).ok, "Other nation not commandable")
	check(not world.issue_move(20, Vector2(610, 230)).ok, "Neutral person not commandable")
	world.set_paused(true)
	check(world.issue_move(0, Vector2(1050, 800)).ok, "Commands accepted while paused")
	world.advance(10)
	check(world.entities[0].position == before and world.tick_count == 0, "Pause freezes clock and movement")
	world.set_paused(false)
	world.advance(0.5)
	check(world.tick_count == 5 and world.entities[0].position != before, "Resume executes queued command")
	world.set_speed(4)
	world.advance(0.5)
	check(world.tick_count == 25 and is_equal_approx(world.elapsed, 2.5), "4x clock advances once per tick")
	check(not world.set_speed(3) and world.speed == 4, "Unsupported speed rejected")
	world.advance(20)
	check(world.entities[0].position.is_equal_approx(Vector2(1050, 800)) and world.entities[0].order == "待機", "Movement finishes precisely")
	check(world.entities[0].owner == "council" and world.treaty.owner_at(world.entities[0].position) == "rival", "Citizenship independent of physical territory")
	check(world.issue_patrol(0, Vector2(1100, 850)).ok, "Patrol command accepted")
	world.advance(3)
	check(world.entities[0].order == "巡回", "Patrol repeats")
	world.halt(0)
	before = world.entities[0].position
	world.advance(3)
	check(world.entities[0].position == before, "Halt clears ongoing and repeating movement")
	var border: PackedVector2Array = world.treaty.border.duplicate()
	world.begin_proposal()
	check(not world.treaty.move_point(0, Vector2(910, 300)), "Endpoint immutable")
	check(not world.treaty.evaluate().accepted, "Zero-area exchange rejected")
	world.example_proposal()
	var result: Dictionary = world.treaty.evaluate()
	check(result.valid and result.accepted, "Balanced proposal accepted by NPC")
	check(absf(result.council_gain - result.rival_gain) < 0.1 and result.council_gain > 1, "Exchange areas calculated equally")
	check(world.treaty.border == border, "Draft does not modify committed territory")
	world.cancel_proposal()
	check(world.treaty.border == border and world.treaty.draft.is_empty(), "Cancel preserves committed border")
	world.begin_proposal()
	world.move_border_point(1, Vector2(1050, 500))
	world.move_border_point(2, Vector2(1000, 700))
	world.move_border_point(3, Vector2(850, 900))
	result = world.submit_proposal()
	check(result.valid and not result.accepted and world.treaty.border == border, "Unbalanced exchange rejected without state change")
	world.example_proposal()
	var positions: Array[Vector2] = []
	for entity in world.entities:
		positions.append(entity.position)
	result = world.submit_proposal()
	check(result.accepted and world.treaty.revision == 1 and world.treaty.draft.is_empty(), "Agreement atomically commits and clears draft")
	for index in range(world.entities.size()):
		check(world.entities[index].position == positions[index], "Treaty preserves person position")
	check(world.treaty.owner_at(world.sites[4].position) == "neutral", "Neutral village preserved")
	check(world.treaty.owner_at(Vector2(1820, 820)) == "neutral", "Island preserved")
	var regions: Array[PackedVector2Array] = world.treaty.regions(world.treaty.border)
	check(world.treaty.area_sum(Geometry2D.intersect_polygons(regions[0], regions[1])) < 0.1, "Countries do not overlap")
	world.begin_proposal()
	world.move_border_point(1, Vector2(900, 800))
	check(not world.treaty.evaluate().valid, "Folded boundary rejected")
	world.begin_proposal()
	world.move_border_point(2, Vector2(360, 760))
	check(not world.treaty.evaluate().valid, "Settlement transfer rejected")
	world.begin_proposal()
	world.move_border_point(1, Vector2(1800, 500))
	check(not world.treaty.evaluate().valid, "Sea boundary rejected")
	world.begin_proposal()
	world.move_border_point(1, Vector2(820, 200))
	check(not world.treaty.evaluate().valid, "Neutral annexation rejected")
	world.begin_proposal()
	world.move_border_point(1, Vector2(823, 503))
	check(world.treaty.draft[1] == Vector2(820, 500), "Landmark snapping")
	check(world.treaty.insert_point(1, Vector2(900, 600)), "Insert boundary point")
	check(world.treaty.remove_point(2) and world.treaty.draft.size() == 5, "Remove intermediate boundary point")
	check(not world.treaty.remove_point(0), "Cannot delete fixed endpoint")
	var bounds_world: RefCounted = World.new()
	bounds_world.begin_proposal()
	bounds_world.move_border_point(1, Vector2(800, 500))
	bounds_world.move_border_point(2, Vector2(1003, 700))
	check(bounds_world.treaty.evaluate().accepted, "NPC accepts just above 95 percent threshold")
	bounds_world.move_border_point(2, Vector2(1004, 700))
	check(not bounds_world.treaty.evaluate().accepted, "NPC rejects just below 95 percent threshold")
	bounds_world.begin_proposal()
	bounds_world.move_border_point(1, Vector2(165, 500))
	bounds_world.move_border_point(2, Vector2(165, 900))
	bounds_world.remove_border_point(3)
	check(not bounds_world.treaty.evaluate().valid, "Border segment cannot shortcut concave coastline")
	bounds_world.begin_proposal()
	bounds_world.move_border_point(1, Vector2(150, 450))
	check(not bounds_world.treaty.evaluate().valid, "Interior handle cannot split country at coastline")
	var before_tick: int = bounds_world.tick_count
	bounds_world.set_speed(2)
	bounds_world.advance(0.5)
	check(bounds_world.tick_count == before_tick + 10, "2x fixed timestep")
	var rival_position: Vector2 = bounds_world.entities[19].position
	bounds_world.advance(0.5)
	check(bounds_world.entities[19].position != rival_position, "Autonomous rival continues without view dependence")
	# Real scene and mouse coordinate adapter, including camera transforms.
	var scene: Control = load("res://scenes/world.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.world.set_paused(true)
	var view: SubViewportContainer = scene.map_view
	var position: Vector2 = scene.world.entities[0].position
	var screen_position: Vector2 = view.screen_from_world(position)
	check(view.world_from_screen(screen_position).distance_to(position) < 0.01, "Screen/world coordinates round-trip")
	check(view.pick_person(view.world_from_screen(screen_position)) == 0, "Person selection matches rendered coordinates")
	view.zoom_at(screen_position, 1.8)
	check(view.world_from_screen(screen_position).distance_to(position) < 0.01, "Zoom preserves world point under cursor")
	view.camera.position += Vector2(40, -20)
	view.camera.force_update_scroll()
	screen_position = view.screen_from_world(position)
	check(view.pick_person(view.world_from_screen(screen_position)) == 0, "Selection remains correct after zoom and pan")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_position
	view._gui_input(click)
	check(scene.selected_entity == 0 and not scene.halt_button.disabled, "Left click selects and enables own-person controls")
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = view.screen_from_world(Vector2(1050, 800))
	view._gui_input(click)
	check(scene.world.entities[0].order == "移動", "Right-click adapter issues authoritative move command")
	before = scene.world.entities[0].position
	scene.world.advance(10)
	check(scene.world.entities[0].position == before, "GUI-issued command waits during global pause")
	scene.world.set_paused(false)
	scene.world.advance(1)
	check(scene.world.entities[0].position != before, "GUI-issued move starts after resume")
	scene.world.set_paused(true)
	scene._select_person(10)
	check(scene.halt_button.disabled and scene.patrol_button.disabled, "Foreign-person UI is inspection-only")
	scene._example()
	check(not scene.submit_button.disabled, "Valid draft enables treaty submit control")
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = view.screen_from_world(scene.world.treaty.draft[1])
	view._gui_input(click)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = view.screen_from_world(Vector2(850, 500))
	view._gui_input(motion)
	check(scene.world.treaty.draft[1].distance_to(Vector2(850, 500)) < 0.05, "Drag adapter edits intermediate border point")
	click.pressed = false
	view._gui_input(click)
	check(view.dragging_point == -1, "Release ends handle dragging")
	scene._example()
	scene.submit_button.pressed.emit()
	check(scene.world.treaty.revision == 1, "Submit button commits agreement")
	scene._reset_world()
	check(scene.world.entities.size() == 24 and scene.world.treaty.revision == 0 and scene.selected_entity == -1, "Reset creates a fresh authoritative world")
	scene.begin_button.pressed.emit()
	check(scene.world.treaty.draft.size() == 5, "Signals reconnect to replacement world")
	scene.cancel_button.pressed.emit()
	check(scene.world.treaty.draft.is_empty(), "Cancel UI preserves world")
	for control in scene.find_children("*", "Button", true, false):
		if control.text == "2×":
			control.pressed.emit()
	check(scene.world.speed == 2, "Speed-button closure retains its own value after reset")
	for control in scene.find_children("*", "Button", true, false):
		if control.text == "4×":
			control.pressed.emit()
	check(scene.world.speed == 4, "4x UI controls replacement world's clock")
	scene.queue_free()
	await process_frame
	print("WORLD CHECKS: %d / FAILURES: %d" % [checks, failures])
	quit(1 if failures else 0)
