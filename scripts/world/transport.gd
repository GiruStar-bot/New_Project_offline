extends RefCounted
## One reserved shipment per carrier. No resource creation or taxation on delivery.

static func capacity(world: RefCounted, id: int) -> float:
	return 5.0 + world.economy.accounts[id].strength / 10.0 # [PLACEHOLDER]

static func endpoint(world: RefCounted, account: int) -> Vector2:
	return world.sites[0].position if account == -1 else world.entities[account].position

static func inventory(world: RefCounted, account: int) -> Dictionary:
	return world.economy.countries.council.stock if account == -1 else world.economy.accounts[account].stock

static func valid_account(world: RefCounted, account: int) -> bool:
	return account == -1 or (account >= 0 and account < world.entities.size() and world.entities[account].owner == "council")

static func issue(world: RefCounted, carrier: int, source: int, target: int, resource: String, amount: float) -> Dictionary:
	if carrier < 0 or carrier >= world.entities.size() or world.entities[carrier].owner != "council" or world.entities[carrier].role != "住民":
		return {"ok": false, "reason": "輸送担当に自国の住民を選択してください。"}
	if world.shipments.has(str(carrier)):
		return {"ok": false, "reason": "現在の輸送を完了、返送、または取り消してください。"}
	if not valid_account(world, source) or not valid_account(world, target) or source == target or resource not in world.Economy.RESOURCES or not is_finite(amount) or amount <= 0 or amount > capacity(world, carrier):
		return {"ok": false, "reason": "出発元・届け先・資源・積載量を確認してください。"}
	if inventory(world, source)[resource] < amount:
		return {"ok": false, "reason": "出発元の在庫が不足しています。"}
	var pickup: Vector2 = endpoint(world, source)
	var delivery: Vector2 = endpoint(world, target)
	var approach: PackedVector2Array = world.geography.find_path(world.entities[carrier].position, pickup)
	if approach.is_empty() or world.geography.find_path(pickup, delivery).is_empty():
		return {"ok": false, "reason": "受取地点または届け先までの陸路がありません。"}
	# Reserve now so multiple carriers cannot promise the same inventory.
	inventory(world, source)[resource] -= amount
	world.economy.accounts[carrier].job = -1
	world.economy.accounts[carrier].slot = -1
	world.shipments[str(carrier)] = {"source": source, "target": target, "resource": resource, "amount": amount, "phase": "pickup"}
	_set_path(world, carrier, approach)
	return {"ok": true, "reason": "%sへ%s %.1fの輸送を指示しました。" % [world.entities[carrier].name, world.Economy.LABELS[resource], amount]}

static func stop(world: RefCounted, carrier: int) -> void:
	var key: String = str(carrier)
	if not world.shipments.has(key):
		return
	var task: Dictionary = world.shipments[key]
	if task.phase == "pickup":
		inventory(world, task.source)[task.resource] += task.amount
		world.shipments.erase(key)
	else:
		task.phase = "held_return" if task.phase in ["return", "held_return"] else "held"

static func resume(world: RefCounted, carrier: int, returning: bool = false) -> Dictionary:
	var key: String = str(carrier)
	if not world.shipments.has(key):
		return {"ok": false, "reason": "この人物は輸送を担当していません。"}
	var task: Dictionary = world.shipments[key]
	if returning and task.phase == "pickup":
		stop(world, carrier)
		_clear_path(world, carrier)
		return {"ok": true, "reason": "積込前の輸送を取り消し、予約分を出発元へ戻しました。"}
	var destination: int = int(task.source) if returning or task.phase in ["return", "held_return"] else int(task.source if task.phase == "pickup" else task.target)
	var path: PackedVector2Array = world.geography.find_path(world.entities[carrier].position, endpoint(world, destination))
	if path.is_empty():
		return {"ok": false, "reason": "再開先への陸路がありません。荷物は維持しています。"}
	if returning:
		task.phase = "return"
	elif task.phase == "held":
		task.phase = "delivery"
	elif task.phase == "held_return":
		task.phase = "return"
	_set_path(world, carrier, path)
	return {"ok": true, "reason": "荷物を出発元へ返送します。" if returning else "輸送を再開しました。"}

static func tick(world: RefCounted) -> void:
	for key in world.shipments.keys():
		var carrier: int = int(key)
		var task: Dictionary = world.shipments[key]
		if task.phase in ["held", "held_return"]:
			continue
		var recipient: int = int(task.target) if task.phase == "delivery" else int(task.source)
		var point: Vector2 = endpoint(world, recipient)
		var entity: Dictionary = world.entities[carrier]
		if entity.position.distance_to(point) <= 3.0: # [PLACEHOLDER] handover distance.
			if task.phase == "pickup":
				task.phase = "delivery"
				recipient = int(task.target)
				point = endpoint(world, recipient)
			else:
				inventory(world, recipient)[task.resource] += task.amount
				if task.phase == "delivery" and task.source == -1 and task.resource == "food":
					world.economy.month_flow.council.relief += task.amount
				world._record("%s：%s %.1fの%sが完了しました。" % [entity.name, world.Economy.LABELS[task.resource], task.amount, "返送" if task.phase == "return" else "配送"])
				world.shipments.erase(key)
				_clear_path(world, carrier)
				world.changed.emit()
				continue
		# A moving receiver may leave the last route endpoint; follow its current position.
		if entity.path.is_empty() or entity.path[-1].distance_to(point) > 20:
			var path: PackedVector2Array = world.geography.find_path(entity.position, point)
			if path.is_empty():
				if task.phase == "pickup":
					stop(world, carrier)
				else:
					task.phase = "held_return" if task.phase == "return" else "held"
				_clear_path(world, carrier)
				world._record("%sの輸送停止：届け先への陸路がありません。荷物を保全しました。" % entity.name)
				world.changed.emit()
			else:
				_set_path(world, carrier, path)

static func _set_path(world: RefCounted, carrier: int, path: PackedVector2Array) -> void:
	world.entities[carrier].path = path
	world.entities[carrier].path_index = 1
	world.entities[carrier].patrol = PackedVector2Array()
	world.entities[carrier].order = "移動"

static func _clear_path(world: RefCounted, carrier: int) -> void:
	world.entities[carrier].path = PackedVector2Array()
	world.entities[carrier].path_index = 0
	world.entities[carrier].patrol = PackedVector2Array()
	world.entities[carrier].order = "待機"

static func restore(world: RefCounted, data: Variant) -> bool:
	if not data is Dictionary or data.size() > world.entities.size():
		return false
	for key in data:
		if not key is String or not key.is_valid_int() or str(int(key)) != key:
			return false
		var carrier: int = int(key)
		if carrier < 0 or carrier >= world.entities.size() or world.entities[carrier].owner != "council" or world.entities[carrier].role != "住民" or world.economy.accounts[carrier].job != -1:
			return false
		var task: Variant = data[key]
		if not task is Dictionary or not _integer(task.get("source")) or not _integer(task.get("target")):
			return false
		if not valid_account(world, int(task.source)) or not valid_account(world, int(task.target)) or task.source == task.target or task.get("resource") not in world.Economy.RESOURCES:
			return false
		if not (task.get("amount") is int or task.get("amount") is float) or not is_finite(float(task.amount)) or task.amount <= 0 or task.amount > capacity(world, carrier) or task.get("phase") not in ["pickup", "delivery", "return", "held", "held_return"]:
			return false
		if task.phase in ["held", "held_return"]:
			if world.entities[carrier].order != "待機":
				return false
		elif world.entities[carrier].order != "移動":
			return false
	world.shipments = data.duplicate(true)
	for task in world.shipments.values():
		task.source = int(task.source)
		task.target = int(task.target)
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= -1 and value <= 1000
