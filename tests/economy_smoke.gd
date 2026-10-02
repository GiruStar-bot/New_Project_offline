extends SceneTree

const World = preload("res://scripts/world/world_state.gd")
const Economy = preload("res://scripts/world/economy.gd")
const Save = preload("res://scripts/world/world_save.gd")
var failures: int = 0
var checks: int = 0

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ECONOMY FAIL: " + title)

func total(economy: RefCounted, resource: String) -> float:
	var sum: float = 0.0
	for country in economy.countries.values():
		sum += country.stock[resource]
	for account in economy.accounts:
		sum += account.stock[resource]
	return sum

func fixture() -> RefCounted:
	var world: RefCounted = World.new()
	world.assign_job(4, 1)
	world.assign_job(5, 2)
	for id in range(world.entities.size()):
		var job: int = world.economy.accounts[id].job
		if job >= 0:
			world.entities[id].position = world.economy.work_position(job, world.economy.accounts[id].slot)
			world.entities[id].path = PackedVector2Array()
			world.entities[id].path_index = 0
			world.entities[id].order = "労働"
	return world

func virtual_day(world: RefCounted) -> void:
	for id in range(world.entities.size()):
		var job: int = int(world.economy.accounts[id].job)
		if job >= 0:
			world.economy.add_work(id, job, Economy.DAY_SECONDS)
	world.economy.finish_day(world.entities, world.sites)
	world.tick_count = int(world.economy.day * Economy.DAY_SECONDS / World.TICK_SECONDS)
	world.elapsed = world.tick_count * World.TICK_SECONDS
	world.accumulator = 0

func close_enough(left: Variant, right: Variant) -> bool:
	if (left is float or left is int) and (right is float or right is int):
		return absf(float(left) - float(right)) < 0.000000001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not close_enough(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not close_enough(left[index], right[index]):
				return false
		return true
	return left == right

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world: RefCounted = World.new()
	check(world.economy.accounts.size() == 24 and world.economy.worksites.size() == 9, "Individual economy and developed worksites initialized")
	for site in world.economy.worksites:
		check(world.geography.is_walkable(site.position), "Worksite accessible: " + str(site.id))
	check(not world.assign_job(10, 3).ok, "Foreign citizen cannot be assigned")
	check(not world.assign_job(6, 1).ok, "Soldier cannot be reassigned as citizen")
	check(not world.assign_job(4, 3).ok, "Foreign worksite rejected")
	check(not world.assign_job(4, 0).ok, "Farm reservations respect capacity")
	check(world.assign_job(4, 1).ok and world.entities[4].order == "移動", "Job creates real travel order")
	check(world.economy.accounts[4].work.is_empty(), "No work before arrival")
	world.advance(15)
	check(world.entities[4].order == "労働" and not world.economy.accounts[4].work.is_empty(), "Arrival starts accumulating labor")
	world.issue_move(4, Vector2(500, 800))
	var labor: Dictionary = world.economy.accounts[4].work.duplicate(true)
	world.advance(1)
	check(world.economy.accounts[4].job == -1 and world.economy.accounts[4].work == labor, "Direct movement cancels job without erasing earned labor")
	world.assign_job(4, 1)
	world.halt(4)
	check(world.economy.accounts[4].job == -1 and world.entities[4].order == "待機", "Halt releases worksite reservation")
	check(not world.set_tax_rate(0.5).ok and not world.set_relief(false).ok, "Policy requires political turn")
	world.begin_political_turn()
	check(world.set_tax_rate(0.5).ok and world.set_relief(false).ok, "Political policies accepted")
	check(not world.set_tax_rate(-1).ok and not world.set_tax_rate(INF).ok and not world.set_tax_rate(1.01).ok, "Invalid rates rejected")
	var saved: Dictionary = Save.snapshot(world)
	world.advance(2880)
	check(Save.snapshot(world) == saved, "Politics freezes economics and work progress")
	world.end_political_turn()
	world.set_speed(1)
	world.advance(2880)
	check(world.economy.day == 1 and world.economy.accounts[0].stock.food < 9, "Shared clock executes daily life exactly once")
	var state: Dictionary = world.economy.snapshot()
	world.advance(0.1)
	check(world.economy.day == 1 and world.economy.accounts[0].stock == state.accounts[0].stock, "Additional ticks do not repeat daily consumption")
	world = fixture()
	check(world.entities[0].position != world.entities[1].position and world.entities[2].position != world.entities[3].position, "Farm workers occupy distinct selectable positions")
	var previous_food: float = total(world.economy, "food")
	var previous_wood: float = total(world.economy, "wood")
	var previous_stone: float = total(world.economy, "stone")
	for day_index in range(90):
		virtual_day(world)
	check(world.economy.reports.size() == 3 and world.economy.day == 90, "90-day simulation produces three reports")
	var consumed: float = 0
	var wood_output: float = 0
	var stone_output: float = 0
	var wood_spent: float = 0
	var stone_spent: float = 0
	for report in world.economy.reports:
		for flow in report.countries.values():
			check(flow.produced.food == 0 and flow.requested.food == 0, "No harvest or food tax in spring")
			consumed += flow.consumed
			wood_output += flow.produced.wood
			stone_output += flow.produced.stone
			wood_spent += flow.maintenance.wood
			stone_spent += flow.maintenance.stone
	check(is_equal_approx(previous_food - total(world.economy, "food"), consumed), "Food conservation including national relief")
	check(is_equal_approx(total(world.economy, "wood"), previous_wood + wood_output - wood_spent), "Wood conserved through production, taxes and maintenance")
	check(is_equal_approx(total(world.economy, "stone"), previous_stone + stone_output - stone_spent), "Stone conserved through production, taxes and maintenance")
	check(world.economy.accounts[4].stock.wood > 0 and world.economy.countries.council.stock.wood < 20, "Private timber and national accounts remain distinct")
	previous_food = total(world.economy, "food")
	check(world.redistribute(4, "food", 1).ok, "National redistribution succeeds")
	check(is_equal_approx(total(world.economy, "food"), previous_food), "Redistribution conserves food")
	var income_before: Dictionary = world.economy.accounts[4].income.duplicate(true)
	world.redistribute(4, "wood", 1)
	check(world.economy.accounts[4].income == income_before, "Redistribution does not become taxable production")
	check(not world.redistribute(4, "food", 1e12).ok and not world.redistribute(10, "food", 1).ok, "Unfunded and foreign redistribution rejected")
	var snapshot: Dictionary = Save.snapshot(world)
	var result: Dictionary = Save.restore(snapshot)
	check(result.ok and result.world.economy.snapshot() == world.economy.snapshot(), "Economy roundtrip preserves stocks, crop progress, loyalty and reports")
	if result.ok:
		var restored: RefCounted = result.world
		virtual_day(world)
		virtual_day(restored)
		check(restored.economy.snapshot() == world.economy.snapshot(), "Reload does not replay taxes or consumption")
	for field in ["day", "accounts", "countries", "worksites", "reports", "month_flow"]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.economy.erase(field)
		check(not Save.restore(bad).ok, "Missing economic field rejected: " + field)
	var bad: Dictionary = snapshot.duplicate(true)
	bad.economy.accounts[0].stock.food = -1
	check(not Save.restore(bad).ok, "Negative saved inventory rejected")
	bad = snapshot.duplicate(true)
	bad.economy.accounts[0].job = 1
	check(not Save.restore(bad).ok, "Saved labor at wrong worksite rejected")
	bad = snapshot.duplicate(true)
	bad.economy.day += 1
	check(not Save.restore(bad).ok, "Saved economy cannot disagree with clock")
	bad = snapshot.duplicate(true)
	bad.economy.accounts[0].work["0"] = 100
	check(not Save.restore(bad).ok, "Saved labor cannot exceed elapsed part of day")
	bad = snapshot.duplicate(true)
	bad.economy.accounts[1].slot = bad.economy.accounts[0].slot
	check(not Save.restore(bad).ok, "Duplicate work reservation rejected")
	var parser: JSON = JSON.new()
	parser.parse(JSON.stringify(snapshot, "", true, true))
	result = Save.restore(parser.data)
	check(result.ok and close_enough(result.world.economy.snapshot(), snapshot.economy), "JSON roundtrip preserves economic state within numerical tolerance")
	var old: Dictionary = snapshot.duplicate(true)
	old.version = 2
	old.erase("economy")
	for person in old.entities:
		if person.order == "労働":
			person.order = "待機"
	result = Save.restore(old)
	check(result.ok and result.world.economy.day == 90, "Old save begins economy at current day without retroactive taxes")
	world = fixture()
	world.economy.worksites[2].remaining = 0.04
	virtual_day(world)
	check(is_equal_approx(world.economy.accounts[5].stock.stone, 0.04) and world.economy.worksites[2].remaining == 0, "Stone extraction cannot exceed deposit")
	check(not world.assign_job(4, 2).ok, "Exhausted quarry cannot accept a new assignment")
	world.economy.worksites[1].remaining = 0
	virtual_day(world)
	check(world.economy.worksites[1].remaining > 0, "Forest regenerates after depletion")
	world = fixture()
	world.economy.accounts[4].stock.food = 0
	world.economy.countries.council.stock.food = 0
	virtual_day(world)
	check(world.economy.accounts[4].hunger > 0 and world.economy.accounts[4].loyalty < 75, "Unfunded food needs cause hunger and dissatisfaction")
	var scenarios: Array = []
	for rate in [0.0, 0.2, 0.8]:
		world = fixture()
		var food_start: float = total(world.economy, "food")
		world.economy.countries.council.tax = rate
		for day_index in range(360):
			virtual_day(world)
		check(world.economy.reports.size() == 12, "Annual seasonal simulation completes")
		check(world.economy.reports[5].countries.council.produced.food > 0 and world.economy.reports[8].countries.council.produced.food > 0, "Summer and autumn harvests occur")
		check(world.economy.reports[11].countries.council.produced.food == 0, "Winter has no new food harvest")
		var requested: float = 0
		var paid: float = 0
		var produced: float = 0
		var all_food_produced: float = 0
		var all_food_consumed: float = 0
		for report in world.economy.reports:
			var flow: Dictionary = report.countries.council
			requested += flow.requested.food
			paid += flow.paid.food
			produced += flow.produced.food
			for country_flow in report.countries.values():
				all_food_produced += country_flow.produced.food
				all_food_consumed += country_flow.consumed
		check(is_equal_approx(total(world.economy, "food"), food_start + all_food_produced - all_food_consumed), "Annual harvest, tax and redistribution conserve food")
		check(is_equal_approx(requested, produced * rate), "Tax applied only to actual harvest")
		check(paid <= requested + 0.000001, "Taxes cannot exceed requested amounts")
		if rate == 0.8:
			check(paid < requested and world.economy.accounts[0].loyalty < 75, "Excess tax causes nonpayment and loyalty loss")
		scenarios.append({"tax": rate, "food_produced": produced, "tax_requested": requested, "tax_paid": paid, "national_stock": world.economy.countries.council.stock, "loyalty": world.economy.accounts[0].loyalty})
	print("ECONOMY SCENARIOS: ", JSON.stringify(scenarios))
	var output_args: PackedStringArray = OS.get_cmdline_user_args()
	if not output_args.is_empty():
		var evidence: FileAccess = FileAccess.open(output_args[0], FileAccess.WRITE)
		if evidence != null:
			evidence.store_string(JSON.stringify({"days": 360, "setup": "Four council farm workers, one logger, one quarry worker; continuous labor at developed sites; all numerical parameters PLACEHOLDER", "scenarios": scenarios}, "\t", true, true))
			evidence.close()
	var scene: Control = load("res://scenes/world.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene._select_person(4)
	scene.work_choice.select(2)
	scene.work_button.pressed.emit()
	check(scene.world.economy.accounts[4].job == 1, "UI assigns selected citizen to logging")
	scene._toggle_political_turn()
	scene.tax_value.value = 35
	scene.tax_button.pressed.emit()
	check(is_equal_approx(scene.world.economy.countries.council.tax, 0.35), "UI applies tax during politics")
	scene._replace_world(world)
	check(scene.economy_label.text.contains("月13") and scene.report_label.text.contains("月12"), "Reload replacement updates economic calendar and report UI")
	scene.queue_free()
	await process_frame
	print("Economy checks: %d; failures: %d" % [checks, failures])
	quit(1 if failures else 0)
