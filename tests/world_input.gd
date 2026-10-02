extends SceneTree
## Tests actual Godot GUI input dispatch, not just coordinator method calls.
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("INPUT FAIL: " + title)

func frames() -> void:
	for index in range(3):
		await process_frame

func pointer(point: Vector2, button: int, pressed: bool = true, double: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	event.double_click = double
	root.push_input(event, true)

func motion(point: Vector2, relative: Vector2, mask: int = 0) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = mask
	root.push_input(event, true)

func _run() -> void:
	var scene: Control = load("res://scenes/world.tscn").instantiate()
	root.add_child(scene)
	await frames()
	scene.set_process(false)
	scene.world.set_paused(true)
	var view: Control = scene.map_view
	if DisplayServer.get_name() == "headless":
		root.notify_mouse_entered()
	var position: Vector2 = view.global_position + view.screen_from_world(scene.world.entities[0].position)
	motion(position, Vector2.ZERO)
	pointer(position, MOUSE_BUTTON_LEFT)
	pointer(position, MOUSE_BUTTON_LEFT, false)
	await frames()
	check(scene.selected_entity == 0, "Viewport dispatch selects person")
	position = view.global_position + view.screen_from_world(Vector2(1050, 800))
	motion(position, Vector2.ZERO)
	pointer(position, MOUSE_BUTTON_RIGHT)
	pointer(position, MOUSE_BUTTON_RIGHT, false)
	await frames()
	check(scene.world.entities[0].order == "移動", "Viewport dispatch issues destination")
	# Actual header button input; no world side effects from sidebar clicks.
	position = scene.pause_button.get_global_rect().get_center()
	motion(position, Vector2.ZERO)
	pointer(position, MOUSE_BUTTON_LEFT)
	pointer(position, MOUSE_BUTTON_LEFT, false)
	await frames()
	check(not scene.world.paused, "Pause/resume header button dispatch")
	scene.world.set_paused(true)
	position = view.global_position + Vector2(200, 200)
	motion(position, Vector2.ZERO)
	var prior_zoom: float = view.camera.zoom.x
	pointer(position, MOUSE_BUTTON_WHEEL_UP)
	await frames()
	check(view.camera.zoom.x > prior_zoom, "Wheel input zooms map")
	var prior_center: Vector2 = view.camera.position
	pointer(position, MOUSE_BUTTON_MIDDLE)
	motion(position + Vector2(40, 20), Vector2(40, 20), MOUSE_BUTTON_MASK_MIDDLE)
	pointer(position + Vector2(40, 20), MOUSE_BUTTON_MIDDLE, false)
	await frames()
	check(view.camera.position.distance_to(prior_center) > 1 and not view.panning, "Middle drag pans and release ends pan")
	position = view.global_position + view.screen_from_world(scene.world.entities[0].position)
	motion(position, Vector2.ZERO)
	pointer(position, MOUSE_BUTTON_LEFT)
	pointer(position, MOUSE_BUTTON_LEFT, false)
	await frames()
	check(scene.selected_entity == 0, "Dispatched picking remains correct after zoom and pan")
	scene._example()
	position = view.global_position + view.screen_from_world(scene.world.treaty.draft[1])
	motion(position, Vector2.ZERO)
	pointer(position, MOUSE_BUTTON_LEFT)
	var target: Vector2 = view.global_position + view.screen_from_world(Vector2(850, 500))
	motion(target, target - position, MOUSE_BUTTON_MASK_LEFT)
	pointer(target, MOUSE_BUTTON_LEFT, false)
	await frames()
	check(scene.world.treaty.draft[1].distance_to(Vector2(850, 500)) < 0.05, "Dispatched border dragging edits geometry")
	# Double-click adds a point on the current line; right-click deletes it.
	position = view.global_position + view.screen_from_world(scene.world.treaty.draft[1].lerp(scene.world.treaty.draft[2], 0.5))
	motion(position, Vector2.ZERO)
	pointer(position, MOUSE_BUTTON_LEFT, true, true)
	pointer(position, MOUSE_BUTTON_LEFT, false)
	await frames()
	check(scene.world.treaty.draft.size() == 6, "Dispatched double-click inserts border point")
	pointer(position, MOUSE_BUTTON_RIGHT)
	pointer(position, MOUSE_BUTTON_RIGHT, false)
	await frames()
	check(scene.world.treaty.draft.size() == 5, "Dispatched right-click removes border point")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	root.push_input(key)
	await frames()
	check(not scene.world.paused, "Space controls global clock without activating focused button")
	check(scene.world.treaty.revision == 0, "Map/sidebar interactions do not accidentally submit treaty")
	scene.queue_free()
	await frames()
	print("INPUT CHECKS: %d / FAILURES: %d" % [checks, failures])
	quit(1 if failures else 0)
