extends RefCounted
## Versioned data-only save. Restore into a candidate before replacing live state.

const World = preload("res://scripts/world/world_state.gd")
const VERSION: int = 4
const DEFAULT_PATH: String = "user://world-save.json"
const MAX_BYTES: int = 1048576

static func snapshot(world: RefCounted) -> Dictionary:
	var people: Array = []
	for entity in world.entities:
		var row: Dictionary = entity.duplicate(true)
		row.position = [entity.position.x, entity.position.y]
		row.path = _pack(entity.path)
		row.patrol = _pack(entity.patrol)
		people.append(row)
	return {"version": VERSION, "map": "fixed-world-v1", "paused": world.paused,
		"political_turn": world.political_turn,
		"economy": world.economy.snapshot(),
		"shipments": world.shipments.duplicate(true),
		"speed": world.speed, "ticks": world.tick_count, "accumulator": maxf(0.0, world.accumulator),
		"entities": people, "border": _pack(world.treaty.border),
		"draft": _pack(world.treaty.draft), "revision": world.treaty.revision,
		"journal": world.journal.duplicate()}

static func restore(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return _failure("保存データの形式が不正です。")
	if not _integer(data.get("version"), 1, VERSION) or data.get("map") != "fixed-world-v1":
		return _failure("この保存形式または地図には対応していません。")
	if int(data.version) == 1:
		if not _number(data.get("accumulator")) or data.accumulator < -0.000001 or data.accumulator >= 0.1:
			return _failure("旧保存の時間の端数が不正です。")
		data = data.duplicate(true)
		data.version = 2
		data.accumulator = maxf(0.0, data.accumulator) * World.GAME_SECONDS_PER_REAL_SECOND
		data.political_turn = data.get("draft") is Array and not data.draft.is_empty()
	if not data.get("political_turn") is bool:
		return _failure("政治調整の状態が不正です。")
	if not data.get("paused") is bool or not _integer(data.get("speed"), 1, 4):
		return _failure("時間設定が不正です。")
	if int(data.speed) not in [1, 2, 4]:
		return _failure("時間設定が不正です。")
	if not _integer(data.get("ticks"), 0, 1000000000000) or not _integer(data.get("revision"), 0, 1000000000):
		return _failure("時間または条約番号が不正です。")
	if not _number(data.get("accumulator")) or data.accumulator < -0.000001 or data.accumulator >= World.TICK_SECONDS:
		return _failure("時間の端数が不正です。")
	if not data.get("entities") is Array or data.entities.size() != 24:
		return _failure("人物一覧が不正です。")
	if not data.get("journal") is Array or data.journal.size() > 50:
		return _failure("履歴が不正です。")
	for line in data.journal:
		if not line is String or line.length() > 2000:
			return _failure("履歴の内容が不正です。")
	if not _points(data.get("border"), 3, 32) or not _points(data.get("draft"), 0, 32):
		return _failure("国境の座標が不正です。")
	if not data.political_turn and not data.draft.is_empty():
		return _failure("未確定の国境には政治調整の停止が必要です。")
	var candidate: RefCounted = World.new()
	candidate.treaty.draft = _unpack(data.border)
	# Existing territory must pass the same geography/site checks as a proposal.
	if not candidate.treaty.evaluate().valid:
		return _failure("保存された領土は現在の地図で成立しません。")
	candidate.treaty.border = candidate.treaty.draft.duplicate()
	# A draft may be invalid: it is an unfinished editing operation, not a treaty.
	candidate.treaty.draft = _unpack(data.draft)
	candidate.treaty.revision = int(data.revision)
	for index in range(data.entities.size()):
		var row: Variant = data.entities[index]
		if not row is Dictionary:
			return _failure("人物の形式が不正です。")
		if not _integer(row.get("id"), index, index) or row.get("owner") not in ["council", "rival", "neutral"]:
			return _failure("人物IDまたは所属が不正です。")
		if not row.get("name") is String or row.name.length() > 100 or row.get("role") not in ["兵士", "住民"]:
			return _failure("人物の名前または役割が不正です。")
		if not _point(row.get("position")) or not _points(row.get("path"), 0, 256) or not _points(row.get("patrol"), 0, 2):
			return _failure("人物の移動座標が不正です。")
		if row.get("order") not in ["待機", "移動", "巡回", "労働"] or not _integer(row.get("path_index"), 0, row.path.size()) or not _integer(row.get("patrol_index"), 0, 1):
			return _failure("人物の命令が不正です。")
		var person: Dictionary = {"id": index, "name": row.name, "owner": row.owner,
			"role": row.role, "position": Vector2(row.position[0], row.position[1]),
			"path": _unpack(row.path), "path_index": int(row.path_index), "order": row.order,
			"patrol": _unpack(row.patrol), "patrol_index": int(row.patrol_index)}
		if not candidate.geography.is_walkable(person.position):
			return _failure("人物が通行不能な地点にいます。")
		if person.order in ["待機", "労働"]:
			if not person.path.is_empty() or not person.patrol.is_empty():
				return _failure("待機と経路の状態が一致しません。")
		elif person.path.is_empty() or person.path_index < 1 or person.path_index >= person.path.size():
			return _failure("移動命令に有効な経路がありません。")
		if (person.order == "巡回" and person.patrol.size() != 2) or (person.order != "巡回" and not person.patrol.is_empty()):
			return _failure("巡回命令の状態が一致しません。")
		for point in person.patrol:
			if not candidate.geography.is_walkable(point):
				return _failure("巡回先が通行不能です。")
		if person.order == "巡回":
			if not person.path[-1].is_equal_approx(person.patrol[person.patrol_index]) or candidate.geography.find_path(person.patrol[0], person.patrol[1]).is_empty():
				return _failure("巡回先と経路が一致しません。")
		var start: Vector2 = person.position
		for path_index in range(person.path_index, person.path.size()):
			if not candidate.geography.segment_walkable(start, person.path[path_index]):
				return _failure("保存された経路は通行不能です。")
			start = person.path[path_index]
		candidate.entities[index] = person
	candidate.paused = data.paused
	candidate.political_turn = data.political_turn
	candidate.speed = int(data.speed)
	candidate.tick_count = int(data.ticks)
	candidate.elapsed = candidate.tick_count * World.TICK_SECONDS
	candidate.accumulator = maxf(0.0, data.accumulator)
	candidate.journal.assign(data.journal)
	candidate.economy = World.Economy.new(candidate.entities)
	if int(data.get("version")) < 3 and not data.has("economy"):
		candidate.economy.day = int(candidate.elapsed / World.Economy.DAY_SECONDS)
		for person in candidate.entities:
			if person.order == "労働":
				return _failure("旧形式に労働命令は保存できません。")
	elif not candidate.economy.restore(data.get("economy"), candidate.entities, int(candidate.elapsed / World.Economy.DAY_SECONDS), fmod(candidate.elapsed, World.Economy.DAY_SECONDS)):
		return _failure("経済・在庫・仕事の保存状態が不正です。")
	if int(data.version) >= 4 and not World.Transport.restore(candidate, data.get("shipments")):
		return _failure("輸送または荷物の保存状態が不正です。")
	return {"ok": true, "reason": "保存した世界を読み込みました。", "world": candidate}

static func save_world(world: RefCounted, path: String = DEFAULT_PATH) -> Dictionary:
	var content: String = JSON.stringify(snapshot(world), "\t", true, true)
	# Validate before touching a previous save.
	var parser: JSON = JSON.new()
	if parser.parse(content) != OK:
		return _failure("現在の状態を保存できません。以前の保存を維持しました。")
	var validation: Dictionary = restore(parser.data)
	if not validation.ok:
		return _failure("保存できません：" + str(validation.reason))
	var temporary: String = path + ".tmp"
	var backup: String = path + ".bak"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("保存先を開けません。以前の保存を維持しました。")
	file.store_string(content)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return _failure("保存の書き込みに失敗しました。")
	var had_save: bool = FileAccess.file_exists(path)
	if had_save:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return _failure("旧バックアップを更新できません。")
		if DirAccess.rename_absolute(path, backup) != OK:
			return _failure("以前の保存を退避できません。")
	if DirAccess.rename_absolute(temporary, path) != OK:
		if had_save:
			DirAccess.rename_absolute(backup, path)
		return _failure("保存ファイルを確定できません。バックアップを確認してください。")
	return {"ok": true, "reason": "世界を保存しました。"}

static func load_world(path: String = DEFAULT_PATH) -> Dictionary:
	var result: Dictionary = _read(path)
	if result.ok:
		return result
	# Recover a valid prior generation after an interrupted/invalid write.
	var backup: Dictionary = _read(path + ".bak")
	if backup.ok:
		backup.reason = "前回のバックアップから世界を復元しました。"
		return backup
	return result

static func _read(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("保存ファイルを開けません。現在の世界を維持しました。")
	if file.get_length() > MAX_BYTES:
		return _failure("保存ファイルが大きすぎます。")
	var content: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return _failure("保存ファイルの読み取りに失敗しました。")
	var parser: JSON = JSON.new()
	if parser.parse(content) != OK:
		return _failure("保存ファイルが破損しています。現在の世界を維持しました。")
	return restore(parser.data)

static func _pack(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point in points:
		result.append([point.x, point.y])
	return result

static func _unpack(points: Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point in points:
		result.append(Vector2(point[0], point[1]))
	return result

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and value >= minimum and value <= maximum and float(value) == floorf(float(value))

static func _point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and absf(value[0]) < 100000 and absf(value[1]) < 100000

static func _points(value: Variant, minimum: int, maximum: int) -> bool:
	if not value is Array or value.size() < minimum or value.size() > maximum:
		return false
	for point in value:
		if not _point(point):
			return false
	return true

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
