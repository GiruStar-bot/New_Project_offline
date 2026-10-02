extends SceneTree
const World = preload("res://scripts/world/world_state.gd")
const Save = preload("res://scripts/world/world_save.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TRANSPORT FAIL: " + title)
func total(world: RefCounted) -> float:
	var amount: float = 0
	for country in world.economy.countries.values():
		amount += country.stock.food
	for account in world.economy.accounts:
		amount += account.stock.food
	for task in world.shipments.values():
		if task.resource == "food":
			amount += task.amount
	return amount
func roundtrip(world: RefCounted) -> RefCounted:
	var result: Dictionary = Save.restore(JSON.parse_string(JSON.stringify(Save.snapshot(world))))
	check(result.ok, "Save restores shipment phase")
	return result.world if result.ok else World.new()
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var world: RefCounted = World.new()
	var before: float = total(world)
	for args in [[6,-1,0,"food",1], [10,-1,0,"food",1], [4,-1,10,"food",1], [4,-1,-1,"food",1], [4,-1,0,"food",100], [4,-1,0,"food",0], [4,-1,0,"gold",1], [4,0,-1,"wood",1]]:
		check(not world.issue_transport(args[0],args[1],args[2],args[3],args[4]).ok, "Invalid transport rejected")
	check(is_equal_approx(total(world),before), "Rejected orders preserve inventory")
	world.set_paused(true)
	check(world.issue_transport(0,-1,1,"food",2).ok, "Worker can become carrier")
	check(world.economy.accounts[0].job == -1, "Carrier releases work slot")
	check(world.economy.countries.council.stock.food == 22, "Source inventory reserved")
	check(not world.issue_transport(0,-1,1,"food",1).ok, "Duplicate carrier rejected")
	check(not world.assign_job(0,0).ok, "Cannot abandon cargo for a job")
	check(not world.issue_move(0,Vector2(400,800)).ok, "Direct move respects transport")
	world.advance(20)
	check(world.shipments["0"].phase == "pickup", "Paused time prevents pickup")
	world = roundtrip(world)
	world.halt(0)
	check(world.shipments.is_empty() and world.economy.countries.council.stock.food == 24, "Before pickup cancellation refunds reservation")
	check(world.issue_transport(4,-1,0,"food",2).ok, "National to private order accepted")
	world = roundtrip(world)
	world.set_paused(false)
	for i in range(200):
		world.advance(0.1)
		if world.shipments.has("4") and world.shipments["4"].phase == "delivery":
			break
	check(world.shipments.has("4") and world.shipments["4"].phase == "delivery", "Physical pickup occurs")
	world = roundtrip(world)
	world.halt(4)
	check(world.shipments["4"].phase == "held", "Loaded halt retains cargo")
	world = roundtrip(world)
	check(is_equal_approx(total(world),before), "Save and halt conserve inventory")
	check(world.resume_transport(4,true).ok, "Loaded cargo can return")
	world = roundtrip(world)
	world.advance(20)
	check(world.shipments.is_empty() and world.economy.countries.council.stock.food == 24, "Return physically refunds source")
	world.halt(0)
	world.entities[0].position = Vector2(1100,800)
	check(world.issue_transport(4,-1,0,"food",2).ok, "Cross river order accepted")
	world.advance(1)
	check(world.shipments["4"].phase == "delivery", "Second pickup succeeds")
	var route: PackedVector2Array = world.entities[4].path
	check(route.size() > 2, "Cross river delivery takes bridge detour")
	world.begin_political_turn()
	var position: Vector2 = world.entities[4].position
	world.advance(10)
	check(world.entities[4].position == position, "Political turn stops cargo movement")
	world.end_political_turn()
	world.advance(50)
	check(world.shipments.is_empty(), "Bridge delivery completes")
	check(world.economy.accounts[0].stock.food == 11, "Destination receives exactly once")
	check(world.economy.accounts[0].income.food == 0, "Transfer is not new taxable production")
	world.advance(10)
	check(world.economy.accounts[0].stock.food == 11 and is_equal_approx(total(world),before), "Repeated ticks do not duplicate cargo")
	check(world.issue_transport(4,0,-1,"food",1).ok, "Private to national transport")
	world.advance(60)
	check(world.shipments.is_empty() and world.economy.countries.council.stock.food == 23, "Private goods reach national treasury")
	check(world.issue_transport(4,0,1,"food",1).ok, "Private to private transport")
	world.advance(60)
	check(world.shipments.is_empty() and world.economy.accounts[1].stock.food == 10, "Private goods delivered")
	check(is_equal_approx(total(world),before), "All transfers conserve food")
	check(world.issue_transport(4,-1,0,"food",1).ok, "Moving recipient scenario starts")
	for i in range(200):
		world.advance(0.1)
		if world.shipments["4"].phase == "delivery":
			break
	world.entities[0].position = Vector2(1820,820)
	world.advance(0.1)
	check(world.shipments["4"].phase == "held", "Unreachable moving target preserves loaded cargo")
	check(not world.resume_transport(4).ok, "Cannot resume toward unreachable target")
	world = roundtrip(world)
	world.entities[0].position = Vector2(600,800)
	check(world.resume_transport(4).ok, "Recipient returns to land and transport resumes")
	world.advance(30)
	check(world.shipments.is_empty(), "Resumed cargo delivered")
	check(is_equal_approx(total(world),before), "Interrupted cargo conserved")
	world.issue_transport(4,-1,1,"food",1)
	var data: Dictionary = Save.snapshot(world)
	for mutation in [["phase","lost"],["amount",99],["amount",-1],["source",10],["target",-1],["resource","gold"]]:
		var bad: Dictionary = data.duplicate(true)
		bad.shipments["4"][mutation[0]] = mutation[1]
		check(not Save.restore(bad).ok, "Invalid shipment save rejected")
	var missing: Dictionary = data.duplicate(true)
	missing.erase("shipments")
	check(not Save.restore(missing).ok, "Version four requires shipments")
	var old: Dictionary = Save.snapshot(World.new())
	old.version = 3
	old.erase("shipments")
	check(Save.restore(old).ok, "Version three migrates without cargo")
	var moving: RefCounted = World.new()
	moving.halt(0)
	moving.entities[0].position = Vector2(550,800)
	check(moving.issue_transport(4,-1,0,"wood",2).ok, "Wood transport accepted")
	moving.advance(2)
	check(moving.shipments["4"].phase == "delivery", "Wood loaded")
	moving.issue_move(0,Vector2(650,800))
	moving.advance(15)
	check(moving.shipments.is_empty() and moving.economy.accounts[0].stock.wood == 2, "Moving recipient tracked and delivered")
	check(moving.issue_transport(5,-1,1,"stone",2).ok, "Stone transport accepted")
	moving.advance(20)
	check(moving.shipments.is_empty() and moving.economy.accounts[1].stock.stone == 2, "Stone delivered")
	var reserved: RefCounted = World.new()
	reserved.economy.countries.council.stock.food = 1
	check(reserved.issue_transport(4,-1,0,"food",1).ok, "First reservation succeeds")
	check(not reserved.issue_transport(5,-1,1,"food",1).ok, "Second carrier cannot reserve the same goods")
	reserved.resume_transport(4,true)
	check(reserved.shipments.is_empty() and reserved.economy.countries.council.stock.food == 1, "Explicit preloading cancel refunds")
	check(world.shipments.has("4"), "Active save fixture still exists")
	var wrong_carrier: Dictionary = data.duplicate(true)
	wrong_carrier.shipments["6"] = wrong_carrier.shipments["4"]
	wrong_carrier.shipments.erase("4")
	check(not Save.restore(wrong_carrier).ok, "Soldier cargo save rejected")
	var conflict: Dictionary = data.duplicate(true)
	conflict.shipments["0"] = conflict.shipments["4"]
	check(not Save.restore(conflict).ok, "Work and transport conflict rejected")
	var scene: Control = load("res://scenes/world.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene._select_person(4)
	scene._transport()
	check(scene.world.shipments.has("4"), "UI issues manual transport")
	scene._halt()
	check(scene.world.shipments.is_empty(), "UI cancellation returns reservation")
	scene.queue_free()
	await process_frame
	print("Transport checks: %d; failures: %d" % [checks,failures])
	quit(1 if failures else 0)

