extends SceneTree

const World = preload("res://scripts/world/world_state.gd")
const Save = preload("res://scripts/world/world_save.gd")
var failures: int = 0
var checks: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SAVE FAIL: " + label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world: RefCounted = World.new()
	world.issue_move(0, Vector2(1050, 800))
	world.issue_patrol(1, Vector2(590, 790))
	world.advance(0.35)
	world.example_proposal()
	world.submit_proposal()
	world.example_proposal()
	world.move_border_point(1, Vector2(1000, 900)) # unfinished invalid draft
	world.set_speed(4)
	world.set_paused(true)
	var original: Dictionary = Save.snapshot(world)
	var result: Dictionary = Save.restore(original)
	check(result.ok, "Restore moving, paused world with accepted treaty and invalid draft")
	if result.ok:
		var restored: RefCounted = result.world
		check(Save.snapshot(restored) == original, "All IDs, owners, positions, paths, clock, borders and logs survive")
		restored.advance(10)
		check(Save.snapshot(restored) == original, "Pause prevents changes after reload")
		world.set_paused(false)
		restored.set_paused(false)
		world.cancel_proposal()
		restored.cancel_proposal()
		world.end_political_turn()
		restored.end_political_turn()
		world.advance(3.27)
		restored.advance(3.27)
		check(Save.snapshot(restored) == Save.snapshot(world), "Resume preserves fractional clock and produces identical simulation")
	world.halt(0)
	world.advance(25)
	check(Save.restore(Save.snapshot(world)).ok, "Completed and halted commands remain saveable")
	for field in ["version", "map", "paused", "political_turn", "speed", "ticks", "accumulator", "entities", "border", "draft", "revision", "journal"]:
		var bad: Dictionary = original.duplicate(true)
		bad.erase(field)
		check(not Save.restore(bad).ok, "Missing field rejected: " + field)
	for edit in [
		["speed", 3], ["ticks", -1], ["ticks", 1.5], ["paused", 1],
		["accumulator", 3.5], ["version", 99], ["journal", [1]],
		["border", [[900, 300], [540, 950], [900, 1100]]]]:
		var bad: Dictionary = original.duplicate(true)
		bad[edit[0]] = edit[1]
		check(not Save.restore(bad).ok, "Corrupt value rejected: " + str(edit[0]))
	for edit in [["id", 2], ["position", [0, 0]], ["path_index", 999], ["owner", "unknown"], ["path", [[500, 800], [735, 500]]], ["order", "待機"], ["patrol", [[400, 800]]]]:
		var bad: Dictionary = original.duplicate(true)
		bad.entities[0][edit[0]] = edit[1]
		check(not Save.restore(bad).ok, "Invalid person rejected: " + str(edit[0]))
	var directory: String = "user://save-test-" + str(Time.get_ticks_usec())
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create isolated test save directory")
	var path: String = directory.path_join("world.json")
	var write_result: Dictionary = Save.save_world(world, path)
	check(write_result.ok, "Write first generation: " + str(write_result.reason))
	check(Save.load_world(path).ok, "Read first generation")
	world.set_speed(2)
	check(Save.save_world(world, path).ok, "Write second generation with backup")
	result = Save.load_world(path)
	if result.ok:
		var loaded_data: Dictionary = Save.snapshot(result.world)
		var live_data: Dictionary = Save.snapshot(world)
		check(absf(loaded_data.accumulator - live_data.accumulator) < 0.000000001, "JSON clock precision below simulation tolerance")
		loaded_data.accumulator = live_data.accumulator
		check(loaded_data == live_data, "Disk roundtrip preserves all remaining state exactly")
	else:
		check(false, "Disk roundtrip restored world")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	result = Save.load_world(path)
	check(result.ok and result.world.speed == 4, "Corrupt latest generation recovers previous save")
	check(not Save.load_world(directory.path_join("missing.json")).ok, "Missing save fails without a world replacement")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.remove_absolute(directory)
	var scene: Control = load("res://scenes/world.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var previous: RefCounted = scene.world
	world.begin_proposal()
	scene._replace_world(world)
	check(scene.world == world and scene.map_view.world == world, "Loaded world attached to map and controller")
	check(not previous.changed.is_connected(scene._state_changed), "Previous signal owner detached")
	scene.map_view.border_point_moved.emit(1, Vector2(840, 500))
	check(world.treaty.draft[1] == Vector2(840, 500), "Border input connected after load")
	scene._reset_world()
	check(scene.world.entities.size() == 24 and scene.world.treaty.revision == 0, "Reset still works after load")
	scene.queue_free()
	await process_frame
	print("World save checks: %d; failures: %d" % [checks, failures])
	quit(1 if failures else 0)
