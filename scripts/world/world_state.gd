extends RefCounted
## Authoritative continuous-world state. One clock; views only issue commands.

const Geography = preload("res://scripts/world/geography.gd")
const Treaty = preload("res://scripts/world/border_treaty.gd")
const TICK_SECONDS: float = 0.1
const WALK_SPEED: float = 50.0 # [PLACEHOLDER] world units/s for prototype readability.
signal changed
var geography: RefCounted = Geography.new()
var treaty: RefCounted
var entities: Array[Dictionary] = []
var sites: Array[Dictionary] = []
var journal: Array[String] = []
var paused: bool = false
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
	_record("世界が動き始めました。人物を選択し、右クリックで移動先を指定してください。")

func set_paused(value: bool) -> void:
	paused = value
	changed.emit()

func set_speed(value: int) -> bool:
	if value not in [1, 2, 4]:
		return false
	speed = value
	changed.emit()
	return true

func advance(real_seconds: float) -> void:
	if paused or real_seconds <= 0 or not is_finite(real_seconds):
		return
	accumulator += real_seconds * speed
	while accumulator + 0.000001 >= TICK_SECONDS:
		accumulator -= TICK_SECONDS
		tick_count += 1
		elapsed = tick_count * TICK_SECONDS
		for entity in entities:
			_step_entity(entity, TICK_SECONDS)

func issue_move(id: int, destination: Vector2) -> Dictionary:
	var error: String = _command_error(id, destination)
	if not error.is_empty():
		return _response(false, error)
	var entity: Dictionary = entities[id]
	var path: PackedVector2Array = geography.find_path(entity.position, destination)
	if path.is_empty():
		return _response(false, "到達できる陸路がありません。橋や海岸を確認してください。")
	entity.path = path
	entity.path_index = 1
	entity.order = "移動"
	entity.patrol = PackedVector2Array()
	return _response(true, "%sに移動を指示しました。%s" % [entity.name, "再開後に移動します。" if paused else ""])

func issue_patrol(id: int, destination: Vector2) -> Dictionary:
	var error: String = _command_error(id, destination)
	if not error.is_empty():
		return _response(false, error)
	if entities[id].position.distance_to(destination) < 10:
		return _response(false, "巡回先は現在地から離れた地点を指定してください。")
	if not _set_patrol(entities[id], PackedVector2Array([entities[id].position, destination])):
		return _response(false, "巡回先までの陸路がありません。")
	return _response(true, "%sに2地点の往復巡回を指示しました。" % entities[id].name)

func halt(id: int) -> Dictionary:
	if id < 0 or id >= entities.size() or entities[id].owner != "council":
		return _response(false, "自国の人物を選択してください。")
	entities[id].path = PackedVector2Array()
	entities[id].patrol = PackedVector2Array()
	entities[id].order = "待機"
	return _response(true, "%sの移動命令を解除しました。" % entities[id].name)

func begin_proposal() -> void:
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

func _step_entity(entity: Dictionary, seconds: float) -> void:
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
			entity.order = "待機"

func _response(ok: bool, reason: String) -> Dictionary:
	_record(reason)
	changed.emit()
	return {"ok": ok, "reason": reason}

func _record(message: String) -> void:
	journal.append(message)
	if journal.size() > 50:
		journal.pop_front()
