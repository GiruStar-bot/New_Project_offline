extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func capture(path: String) -> void:
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: Control = load("res://scenes/world.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.world.halt(0)
	scene.world.entities[0].position = Vector2(1100,800)
	scene._select_person(4)
	scene._transport()
	scene.world.advance(12)
	scene._state_changed()
	var panel: ScrollContainer = scene.find_children("*", "ScrollContainer", true, false)[0]
	panel.scroll_vertical = 590
	await capture(args[0].path_join("transport-delivery.png"))
	scene._halt()
	await capture(args[0].path_join("transport-held.png"))
	scene.world.resume_transport(4)
	scene.world.advance(40)
	scene._state_changed()
	await capture(args[0].path_join("transport-complete.png"))
	scene.queue_free()
	await process_frame
	print("Captured three transport viewports.")
	quit()
