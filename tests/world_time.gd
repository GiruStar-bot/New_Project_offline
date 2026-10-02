extends SceneTree

const World = preload("res://scripts/world/world_state.gd")
const Save = preload("res://scripts/world/world_save.gd")
var failures: int = 0
var checks: int = 0

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TIME FAIL: " + title)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for speed in [1, 2, 4]:
		var world: RefCounted = World.new()
		world.set_speed(speed)
		world.issue_move(0, Vector2(390, 800))
		world.advance(1)
		check(is_equal_approx(world.elapsed, 30.0 * speed), "One real second advances correct game time at %dx" % speed)
	var world: RefCounted = World.new()
	world.issue_move(0, Vector2(1050, 800))
	world.advance(0.05)
	var partial: float = world.accumulator
	world.begin_political_turn()
	var initial: Dictionary = Save.snapshot(world)
	world.begin_political_turn()
	check(Save.snapshot(world) == initial, "Repeated begin is idempotent")
	world.advance(1000)
	check(Save.snapshot(world) == initial, "Politics freezes clock, remainder and all people")
	world.set_paused(false)
	check(world.is_time_stopped(), "Manual resume cannot override politics")
	world.set_speed(4)
	world.advance(1)
	check(world.elapsed == 0 and world.accumulator == partial, "Changing speed during politics does not simulate")
	var restored: Dictionary = Save.restore(Save.snapshot(world))
	check(restored.ok and restored.world.political_turn and restored.world.is_time_stopped(), "Political pause survives save/restore")
	check(world.issue_move(1, Vector2(550, 800)).ok, "Orders can be queued during politics")
	var position: Vector2 = world.entities[1].position
	world.advance(1)
	check(world.entities[1].position == position, "Queued order does not execute during politics")
	world.end_political_turn()
	world.advance(0.05)
	check(is_equal_approx(world.elapsed, 6) and is_equal_approx(world.accumulator, 1.5), "Resume consumes time once and preserves remainder")
	check(world.entities[1].position != position, "Queued order starts after politics")
	world.set_paused(true)
	world.begin_political_turn()
	world.end_political_turn()
	check(world.paused and world.is_time_stopped(), "Politics exit preserves prior manual pause")
	world.set_paused(false)
	world.begin_proposal()
	check(world.political_turn, "Border editing automatically enters politics")
	check(not world.end_political_turn().ok and world.political_turn, "Cannot resume with unfinished treaty")
	world.cancel_proposal()
	check(world.end_political_turn().ok and not world.is_time_stopped(), "Cancel then exit resumes")
	world.example_proposal()
	check(world.submit_proposal().accepted and world.political_turn, "Agreement does not prematurely end politics")
	world.end_political_turn()
	check(not world.is_time_stopped(), "Agreement then exit resumes")
	var legacy: Dictionary = Save.snapshot(world)
	legacy.version = 1
	legacy.erase("political_turn")
	legacy.accumulator /= 30.0
	restored = Save.restore(legacy)
	check(restored.ok and restored.world.tick_count == world.tick_count and is_equal_approx(restored.world.accumulator, world.accumulator), "Version 1 migrates clock units without changing tick progress")
	legacy.draft = legacy.border.duplicate(true)
	restored = Save.restore(legacy)
	check(restored.ok and restored.world.political_turn, "Legacy unfinished treaty migrates into political pause")
	var scene: Control = load("res://scenes/world.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.world.set_paused(false)
	scene.political_button.pressed.emit()
	check(scene.world.political_turn and scene.pause_button.disabled, "Politics UI starts mandatory pause")
	scene._toggle_pause()
	check(scene.world.is_time_stopped(), "Space handler cannot bypass politics")
	scene.political_button.pressed.emit()
	check(not scene.world.is_time_stopped() and not scene.pause_button.disabled, "Politics UI exits and restores clock controls")
	scene.world.advance(2880)
	scene._update_panel()
	check(scene.clock_label.text.begins_with("1日 00:00:00"), "48 real minutes displays one game day")
	scene.queue_free()
	await process_frame
	print("World time checks: %d; failures: %d" % [checks, failures])
	quit(1 if failures else 0)
