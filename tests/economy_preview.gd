extends SceneTree
## Render a fixture advanced by daily labor batches, not a gameplay fast-forward button.

func _initialize() -> void:
	call_deferred("_run")

func capture(path: String) -> void:
	for index in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Economic preview failed: " + path)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var scene: Control = load("res://scenes/world.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.world.set_paused(true)
	scene._select_person(4)
	await capture(args[0].path_join("economy-initial.png"))
	scene.work_choice.select(2)
	scene._assign_work()
	scene._toggle_political_turn()
	var panel: ScrollContainer = scene.find_children("*", "ScrollContainer", true, false)[0]
	panel.scroll_vertical = 320
	await capture(args[0].path_join("economy-policy.png"))
	var world: RefCounted = scene.world
	world.assign_job(5, 2)
	world.end_political_turn()
	for id in range(world.entities.size()):
		var job: int = int(world.economy.accounts[id].job)
		if job >= 0:
			world.entities[id].position = world.economy.work_position(job, world.economy.accounts[id].slot)
			world.entities[id].path = PackedVector2Array()
			world.entities[id].path_index = 0
			world.entities[id].order = "労働"
	# Batched fixture shows a real harvest and settlement without waiting nine real days.
	for day_index in range(270):
		for id in range(world.entities.size()):
			var job: int = int(world.economy.accounts[id].job)
			if job >= 0:
				world.economy.add_work(id, job, 86400.0)
		world.economy.finish_day(world.entities, world.sites)
	world.tick_count = int(270 * 86400.0 / world.TICK_SECONDS)
	world.elapsed = world.tick_count * world.TICK_SECONDS
	world.accumulator = 0
	scene._state_changed()
	panel.scroll_vertical = 410
	await capture(args[0].path_join("economy-harvest.png"))
	panel.scroll_vertical = 0
	scene._select_person(0)
	await capture(args[0].path_join("economy-workers.png"))
	root.size = Vector2i(1152, 720)
	panel.scroll_vertical = 350
	await capture(args[0].path_join("economy-small-window.png"))
	scene.queue_free()
	await process_frame
	print("Captured five economic viewports.")
	quit()
