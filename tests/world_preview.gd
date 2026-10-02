extends SceneTree
## Graphical QA: godot --path . --script tests/world_preview.gd -- <output dir>
var failures: int = 0

func _initialize() -> void:
	call_deferred("_capture")

func _frames() -> void:
	for index in range(6):
		await process_frame
	await RenderingServer.frame_post_draw

func _save(directory: String, name: String) -> void:
	await _frames()
	var result: Error = root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
	if result != OK:
		failures += 1
		push_error("Unable to save preview: " + name)

func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass output directory after --")
		quit(1)
		return
	var scene: Control = load("res://scenes/world.tscn").instantiate()
	root.add_child(scene)
	await _frames()
	scene.set_process(false)
	scene.world.set_paused(true)
	await _save(args[0], "world-map")
	scene._select_person(0)
	scene._destination(Vector2(1050, 800))
	await _save(args[0], "world-route")
	scene._example()
	await _save(args[0], "world-treaty")
	scene._submit()
	await _save(args[0], "world-agreement")
	# Inspect the detailed view and a rejected proposal too.
	scene.map_view.zoom_at(scene.map_view.screen_from_world(Vector2(735, 670)), 1.7)
	await _save(args[0], "world-bridge")
	scene._begin()
	scene.world.move_border_point(1, Vector2(1060, 500))
	scene.world.move_border_point(2, Vector2(1030, 700))
	scene.world.move_border_point(3, Vector2(870, 900))
	scene._submit()
	await _save(args[0], "world-rejected")
	# A smaller physical window still renders the fixed logical canvas.
	root.size = Vector2i(1152, 720)
	scene.map_view.fit_map()
	await _save(args[0], "world-small-window")
	print("Captured seven continuous-world viewports.")
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
