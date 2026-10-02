extends RefCounted
## Authoritative continuous-world state. One clock; views only issue commands.

const Geography = preload("res://scripts/world/geography.gd")
const Treaty = preload("res://scripts/world/border_treaty.gd")
const Economy = preload("res://scripts/world/economy.gd")
const Transport = preload("res://scripts/world/transport.gd")
const GAME_SECONDS_PER_REAL_SECOND: float = 30.0
const TICK_SECONDS: float = 3.0 # 0.1 real seconds at 1x; authoritative game seconds.
const WALK_SPEED: float = 50.0 / GAME_SECONDS_PER_REAL_SECOND # [PLACEHOLDER] map units/game second.
signal changed
var geography: RefCounted = Geography.new()
var treaty: RefCounted
var economy: RefCounted
var shipments: Dictionary = {}
var entities: Array[Dictionary] = []
var sites: Array[Dictionary] = []
var journal: Array[String] = []
var paused: bool = false
var political_turn: bool = false
var speed: int = 1
var elapsed: float = 0.0
var tick_count: int = 0
var accumulator: float = 0.0

func _init() -> void:
	sites = [
		{"id": 0, "name": "ハヴェン村", "kind": "村", "owner": "council", "position": Vector2(360, 760)},
		{"id": 1, "name": "西の城塞", "kind": "城塞", "owner": "council", "position": Vector2(540, 950)},
		{"id": 2, "name": "リード村", "kind": "村", "owner": "rival", "position": Vector2(1340, 740)},
		{"id": 3, "name": "東の城塞", "kind": "城塞", "owner": "rival", "position": Vector2(1370, 950)},
		{"id": 4, "name": "北の無所属村", "kind": "村", "owner": "neutral", "position": Vector2(560, 220)}]
	treaty = Treaty.new(geography, sites)
	var names: Array[String] = ["ミラ", "レン", "エマ", "ノア", "ユナ", "カイ", "アレン", "セナ", "レオ", "リナ", "イリス", "ロアン", "ベラ", "エリ", "フィン", "ナディア", "オーウェン", "テオ", "サラ", "ルカ", "マヤ", "エズラ", "ニナ", "ユリ"]
	for index in range(24):
		var owner: String = "council" if index < 10 else ("rival" if index < 20 else "neutral")
		var local_index: int = index % 10
		var soldier: bool = index < 20 and local_index >= 6
		var site_index: int = (1 if soldier else 0) if owner == "council" else ((3 if soldier else 2) if owner == "rival" else 4)
		var origin: Vector2 = sites[site_index].position
		var offset: Vector2 = Vector2((local_index % 3 - 1) * 25, 48 + (local_index / 3) * 22)
		entities.append({"id": index, "name": names[index], "owner": owner, "role": "兵士" if soldier else "住民", "position": origin + offset, "path": PackedVector2Array(), "path_index": 0, "order": "待機", "patrol": PackedVector2Array(), "patrol_index": 0})
	# Visible autonomous movement, including the rival and neutral population.
	_set_patrol(entities[9], PackedVector2Array([entities[9].position, Vector2(620, 960)]))
	_set_patrol(entities[19], PackedVector2Array([entities[19].position, Vector2(1490, 930)]))
	_set_patrol(entities[23], PackedVector2Array([entities[23].position, Vector2(620, 260)]))
	economy = Economy.new(entities)
	for id in [0, 1, 2, 3, 10, 11, 12, 13, 20, 21]:
		_start_work(id, 0 if id < 10 else (3 if id < 20 else 6))
	_record("世界が動き始めました。人物を選択し、右クリックで移動先を指定してください。")

func set_paused(value: bool) -> void:
	paused = value
	changed.emit()

func is_time_stopped() -> bool:
	return paused or political_turn

func begin_political_turn() -> void:
	if political_turn:
		return
	political_turn = true
	_record("政治調整を開始しました。世界全体の時間を停止します。")
	changed.emit()

func end_political_turn() -> Dictionary:
	if not treaty.draft.is_empty():
		return _response(false, "国境の提案を確定または取り消してから政治調整を終了してください。")
	political_turn = false
	return _response(true, "政治調整を終了しました。" + ("手動の一時停止は維持します。" if paused else "世界の時間を再開します。"))

func set_speed(value: int) -> bool:
	if value not in [1, 2, 4]:
		return false
	speed = value
	changed.emit()
	return true

func advance(real_seconds: float) -> void:
	if is_time_stopped() or real_seconds <= 0 or not is_finite(real_seconds):
		return
	accumulator += real_seconds * speed * GAME_SECONDS_PER_REAL_SECOND
	while accumulator + 0.000001 >= TICK_SECONDS:
		accumulator -= TICK_SECONDS
		tick_count += 1
		elapsed = tick_count * TICK_SECONDS
		for entity in entities:
			var working_seconds: float = _step_entity(entity, TICK_SECONDS)
			var job: int = int(economy.accounts[entity.id].job)
			if job >= 0 and working_seconds > 0:
				economy.add_work(entity.id, job, working_seconds)
		Transport.tick(self)
		if int(elapsed / Economy.DAY_SECONDS) > economy.day:
			economy.finish_day(entities, sites)
			if economy.day % Economy.MONTH_DAYS == 0:
				var flow: Dictionary = economy.reports[-1].countries.council
				_record("月%d決算：生産 食料%.1f・木材%.1f・石材%.1f / 食料税 要求%.1f・納入%.1f / 食料不足%.2f。" % [economy.day / Economy.MONTH_DAYS, flow.produced.food, flow.produced.wood, flow.produced.stone, flow.requested.food, flow.paid.food, flow.shortage])
			changed.emit()

func assign_job(id: int, site_id: int) -> Dictionary:
	if shipments.has(str(id)):
		return _response(false, "輸送を完了、返送、または取り消してから仕事を変更してください。")
	var error: String = economy.job_error(id, site_id, entities)
	if not error.is_empty():
		return _response(false, error)
	if not _start_work(id, site_id):
		return _response(false, "作業場までの陸路がありません。")
	return _response(true, "%sを%sへ割り当てました。到着後に働きます。" % [entities[id].name, economy.worksites[site_id].name])

func _start_work(id: int, site_id: int) -> bool:
	var slot: int = economy.available_slot(id, site_id)
	if slot < 0:
		return false
	var destination: Vector2 = economy.work_position(site_id, slot)
	var path: PackedVector2Array = geography.find_path(entities[id].position, destination)
	if path.is_empty():
		return false
	economy.accounts[id].job = site_id
	economy.accounts[id].slot = slot
	entities[id].patrol = PackedVector2Array()
	entities[id].path = path
	entities[id].path_index = 1
	entities[id].order = "移動"
	return true

func set_tax_rate(rate: float) -> Dictionary:
	if not political_turn:
		return _response(false, "税率は政治調整中に変更してください。")
	if not is_finite(rate) or rate < 0 or rate > 1:
		return _response(false, "税率は0〜100%の範囲で指定してください。")
	economy.countries.council.tax = rate
	return _response(true, "現物税率を%.0f%%へ変更しました。今月の生産分から月末に徴収します。" % (rate * 100))

func set_relief(value: bool) -> Dictionary:
	if not political_turn:
		return _response(false, "自動配給は政治調整中に変更してください。")
	economy.countries.council.relief = value
	return _response(true, "食料不足時の国庫からの自動配給を" + ("有効にしました。" if value else "停止しました。"))

func redistribute(id: int, resource: String, quantity: float) -> Dictionary:
	var result: Dictionary = economy.redistribute(id, resource, quantity, entities)
	return _response(result.ok, result.reason)

func issue_transport(carrier: int, source: int, target: int, resource: String, amount: float) -> Dictionary:
	var result: Dictionary = Transport.issue(self, carrier, source, target, resource, amount)
	return _response(result.ok, result.reason)

func resume_transport(carrier: int, returning: bool = false) -> Dictionary:
	var result: Dictionary = Transport.resume(self, carrier, returning)
	return _response(result.ok, result.reason)

func issue_move(id: int, destination: Vector2) -> Dictionary:
	var error: String = _command_error(id, destination)
	if not error.is_empty():
		return _response(false, error)
	var entity: Dictionary = entities[id]
	var path: PackedVector2Array = geography.find_path(entity.position, destination)
	if path.is_empty():
		return _response(false, "到達できる陸路がありません。橋や海岸を確認してください。")
	entity.path = path
	economy.accounts[id].job = -1
	economy.accounts[id].slot = -1
	entity.path_index = 1
	entity.order = "移動"
	entity.patrol = PackedVector2Array()
	return _response(true, "%sに移動を指示しました。%s" % [entity.name, "再開後に移動します。" if is_time_stopped() else ""])

func issue_patrol(id: int, destination: Vector2) -> Dictionary:
	var error: String = _command_error(id, destination)
	if not error.is_empty():
		return _response(false, error)
	if entities[id].position.distance_to(destination) < 10:
		return _response(false, "巡回先は現在地から離れた地点を指定してください。")
	if not _set_patrol(entities[id], PackedVector2Array([entities[id].position, destination])):
		return _response(false, "巡回先までの陸路がありません。")
	economy.accounts[id].job = -1
	economy.accounts[id].slot = -1
	return _response(true, "%sに2地点の往復巡回を指示しました。" % entities[id].name)

func halt(id: int) -> Dictionary:
	if id < 0 or id >= entities.size() or entities[id].owner != "council":
		return _response(false, "自国の人物を選択してください。")
	Transport.stop(self, id)
	entities[id].path = PackedVector2Array()
	economy.accounts[id].job = -1
	economy.accounts[id].slot = -1
	entities[id].path_index = 0
	entities[id].patrol = PackedVector2Array()
	entities[id].order = "待機"
	return _response(true, "%sの移動命令を解除しました。" % entities[id].name)

func begin_proposal() -> void:
	begin_political_turn()
	treaty.begin()
	changed.emit()

func move_border_point(index: int, position: Vector2) -> void:
	if treaty.move_point(index, position):
		changed.emit()

func insert_border_point(segment: int, position: Vector2) -> void:
	if treaty.insert_point(segment, position):
		changed.emit()

func remove_border_point(index: int) -> void:
	if treaty.remove_point(index):
		changed.emit()

func example_proposal() -> void:
	begin_political_turn()
	treaty.example()
	changed.emit()

func cancel_proposal() -> void:
	treaty.cancel()
	_record("国境の提案を取り消しました。確定済みの領土は変更されていません。")
	changed.emit()

func submit_proposal() -> Dictionary:
	var result: Dictionary = treaty.submit()
	if result.accepted:
		_record("条約 #%d 合意：自国 +%.0f / 相手国 +%.0f の地図面積を交換。人物の所属は維持。" % [treaty.revision, result.council_gain, result.rival_gain])
	else:
		_record("提案は未確定：" + str(result.reason))
	changed.emit()
	return result

func _command_error(id: int, destination: Vector2) -> String:
	if id < 0 or id >= entities.size():
		return "人物を選択してください。"
	if entities[id].owner != "council":
		return "他国・無所属の人物は情報の確認のみ可能です。"
	if shipments.has(str(id)):
		return "輸送担当です。命令解除で停止し、輸送再開または返送を選択してください。"
	if not destination.is_finite() or not geography.is_walkable(destination):
		return "海・川・崖には移動できません。歩ける陸地を指定してください。"
	return ""

func _set_patrol(entity: Dictionary, points: PackedVector2Array) -> bool:
	var path: PackedVector2Array = geography.find_path(points[0], points[1])
	if path.is_empty():
		return false
	entity.patrol = points
	entity.patrol_index = 1
	entity.path = path
	entity.path_index = 1
	entity.order = "巡回"
	return true

func _step_entity(entity: Dictionary, seconds: float) -> float:
	if entity.order == "労働":
		return seconds
	var remaining: float = WALK_SPEED * seconds
	var path: PackedVector2Array = entity.path
	while entity.path_index < path.size() and remaining > 0:
		var target: Vector2 = path[entity.path_index]
		var distance: float = entity.position.distance_to(target)
		if distance <= remaining:
			entity.position = target
			entity.path_index += 1
			remaining -= distance
		else:
			entity.position = entity.position.move_toward(target, remaining)
			remaining = 0
	if entity.path_index >= path.size() and not path.is_empty():
		if not entity.patrol.is_empty():
			entity.patrol_index = (int(entity.patrol_index) + 1) % entity.patrol.size()
			entity.path = geography.find_path(entity.position, entity.patrol[entity.patrol_index])
			entity.path_index = 1
		else:
			entity.path = PackedVector2Array()
			entity.path_index = 0
			if int(economy.accounts[entity.id].job) >= 0:
				entity.order = "労働"
				return remaining / WALK_SPEED
			entity.order = "待機"
	return 0.0

func _response(ok: bool, reason: String) -> Dictionary:
	_record(reason)
	changed.emit()
	return {"ok": ok, "reason": reason}

func _record(message: String) -> void:
	journal.append(message)
	if journal.size() > 50:
		journal.pop_front()
