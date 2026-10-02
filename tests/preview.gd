extends SceneTree
## Renders actual Godot viewports, requires a graphical display.
## godot --path . --script tests/preview.gd -- <output directory>

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass an output directory after --")
		quit(1)
		return
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for index in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join("strategy.png"))
	main._action("attack")
	for index in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join("battle.png"))
	main._battle_command("attack")
	main._battle_command("attack")
	main._battle_command("attack")
	main._return_to_map()
	for index in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join("result.png"))
	print("Captured strategy, battle, result viewports.")
	main.queue_free()
	await process_frame
	quit()
