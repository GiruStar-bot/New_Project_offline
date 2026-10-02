extends RefCounted
## Physical in-kind economy. All balance values are [PLACEHOLDER], not historical rates.

const DAY_SECONDS: float = 86400.0
const MONTH_DAYS: int = 30
const RESOURCES: Array[String] = ["food", "wood", "stone"]
const LABELS: Dictionary = {"food": "食料", "wood": "木材", "stone": "石材"}
var day: int = 0
var accounts: Array[Dictionary] = []
var countries: Dictionary = {}
var worksites: Array[Dictionary] = []
var reports: Array[Dictionary] = []
var month_flow: Dictionary = {}

func _init(people: Array[Dictionary]) -> void:
	for owner in ["council", "rival", "neutral"]:
		countries[owner] = {"stock": {"food": 24.0, "wood": 20.0, "stone": 12.0}, "tax": 0.0 if owner == "neutral" else 0.2, "relief": true}
		month_flow[owner] = _flow()
	for person in people:
		accounts.append({"stock": {"food": 9.0, "wood": 0.0, "stone": 0.0}, "income": _stock(), "loyalty": 75.0, "strength": float(50 + (int(person.id) * 17) % 41), "hunger": 0.0, "job": -1, "slot": -1, "work": {}})
	var layouts: Array = [
		["council", Vector2(625, 800), Vector2(320, 690), Vector2(365, 570)],
		["rival", Vector2(1120, 740), Vector2(1430, 660), Vector2(1410, 570)],
		["neutral", Vector2(570, 280), Vector2(610, 210), Vector2(470, 250)]]
	for layout in layouts:
		for kind in range(3):
			worksites.append({"id": worksites.size(), "owner": layout[0], "kind": ["farm", "wood", "stone"][kind], "name": ["農地（水源あり）", "伐採地", "採石場"][kind], "position": layout[kind + 1], "capacity": 4 if kind == 0 else 3, "remaining": 240.0 if kind == 1 else (300.0 if kind == 2 else 0.0), "fertility": 1.0, "crops": {}})

static func _stock() -> Dictionary:
	return {"food": 0.0, "wood": 0.0, "stone": 0.0}

static func _flow() -> Dictionary:
	return {"produced": _stock(), "requested": _stock(), "paid": _stock(), "consumed": 0.0, "relief": 0.0, "shortage": 0.0, "maintenance": _stock(), "maintenance_shortage": _stock(), "seed": 0.0}

func season() -> String:
	return ["春", "夏", "秋", "冬"][(day / MONTH_DAYS / 3) % 4]

func job_error(id: int, site_id: int, people: Array[Dictionary]) -> String:
	if id < 0 or id >= accounts.size() or people[id].owner != "council" or people[id].role != "住民":
		return "自国の住民を選択してください。兵士の職業変更は後続の更新で扱います。"
	if site_id < 0 or site_id >= worksites.size() or worksites[site_id].owner != people[id].owner:
		return "自国の作業場を選択してください。"
	var count: int = 0
	for index in range(accounts.size()):
		if index != id and accounts[index].job == site_id:
			count += 1
	if count >= int(worksites[site_id].capacity):
		return "作業場の定員に達しています。"
	if worksites[site_id].kind == "stone" and worksites[site_id].remaining <= 0:
		return "この採石場は枯渇しています。"
	return ""

func add_work(id: int, site_id: int, seconds: float) -> void:
	if seconds <= 0:
		return
	var key: String = str(site_id)
	accounts[id].work[key] = float(accounts[id].work.get(key, 0.0)) + seconds

func available_slot(id: int, site_id: int) -> int:
	for slot in range(worksites[site_id].capacity):
		var taken: bool = false
		for index in range(accounts.size()):
			if index != id and accounts[index].job == site_id and accounts[index].slot == slot:
				taken = true
		if not taken:
			return slot
	return -1

func work_position(site_id: int, slot: int) -> Vector2:
	return worksites[site_id].position + Vector2(-16 if slot % 2 == 0 else 16, -16 if slot < 2 else 16)

func finish_day(people: Array[Dictionary], settlements: Array[Dictionary]) -> void:
	var month_index: int = (day / MONTH_DAYS) % 12
	for index in range(accounts.size()):
		var account: Dictionary = accounts[index]
		for key in account.work:
			var site: Dictionary = worksites[int(key)]
			var fraction: float = float(account.work[key]) / DAY_SECONDS
			var ability: float = (0.75 + account.strength / 200.0) * maxf(0.25, 1.0 - account.hunger / 30.0)
			if site.kind == "farm":
				if month_index < 9:
					site.crops[str(index)] = float(site.crops.get(str(index), 0.0)) + fraction * (72.0 / 270.0) * ability * site.fertility
			else:
				var resource: String = str(site.kind)
				var output: float = minf(site.remaining, fraction * (4.0 if resource == "wood" else 3.0) / MONTH_DAYS * ability)
				site.remaining = maxf(0.0, site.remaining - output)
				_credit(index, resource, output, people)
		account.work.clear()
	for site in worksites:
		if site.kind == "wood":
			site.remaining = minf(240.0, site.remaining + 0.1)
		elif site.kind == "farm" and month_index >= 9:
			site.fertility = minf(1.0, site.fertility + 0.0001)
	day += 1
	if day % MONTH_DAYS == 0:
		if month_index == 5 or month_index == 8:
			_harvest(0.375 if month_index == 5 else 1.0, people)
		_collect_taxes(people)
		_maintain(settlements)
	_consume(people)
	if day % MONTH_DAYS == 0:
		var report: Dictionary = {"month": day / MONTH_DAYS, "countries": month_flow.duplicate(true)}
		reports.append(report)
		if reports.size() > 12:
			reports.pop_front()
		for owner in countries:
			month_flow[owner] = _flow()

func _credit(id: int, resource: String, quantity: float, people: Array[Dictionary]) -> void:
	accounts[id].stock[resource] += quantity
	accounts[id].income[resource] += quantity
	month_flow[people[id].owner].produced[resource] += quantity

func _harvest(ratio: float, people: Array[Dictionary]) -> void:
	for site in worksites:
		if site.kind != "farm":
			continue
		for key in site.crops:
			var gross: float = float(site.crops[key]) * ratio
			site.crops[key] = maxf(0.0, float(site.crops[key]) - gross)
			var id: int = int(key)
			# Seed/replanting input is a 5% abstract sink in this first prototype.
			month_flow[people[id].owner].seed += gross * 0.05
			_credit(id, "food", gross * 0.95, people)
		site.fertility = maxf(0.5, site.fertility - 0.005)

func _collect_taxes(people: Array[Dictionary]) -> void:
	for id in range(accounts.size()):
		var account: Dictionary = accounts[id]
		var owner: String = str(people[id].owner)
		var rate: float = float(countries[owner].tax)
		var safe_rate: float = 0.1 + account.loyalty * 0.004
		var cooperation: float = clampf(1.0 - maxf(0.0, rate - safe_rate) * 2.0, 0.0, 1.0)
		for resource in RESOURCES:
			var requested: float = account.income[resource] * rate
			var available: float = account.stock[resource]
			if resource == "food":
				available = maxf(0.0, available - 1.0) # [PLACEHOLDER] one month protected subsistence.
			var paid: float = minf(available, requested * cooperation)
			account.stock[resource] -= paid
			countries[owner].stock[resource] += paid
			month_flow[owner].requested[resource] += requested
			month_flow[owner].paid[resource] += paid
			account.income[resource] = 0.0
		if rate > safe_rate:
			account.loyalty = maxf(0.0, account.loyalty - (rate - safe_rate) * 8.0)

func _consume(people: Array[Dictionary]) -> void:
	for id in range(accounts.size()):
		var account: Dictionary = accounts[id]
		var owner: String = str(people[id].owner)
		var demand: float = 1.0 / MONTH_DAYS
		var missing: float = maxf(0.0, demand - account.stock.food)
		if countries[owner].relief and missing > 0:
			var relief: float = minf(missing, countries[owner].stock.food)
			countries[owner].stock.food -= relief
			account.stock.food += relief
			month_flow[owner].relief += relief
			account.loyalty = minf(100.0, account.loyalty + relief * 0.2)
		var consumed: float = minf(demand, account.stock.food)
		account.stock.food = maxf(0.0, account.stock.food - consumed)
		month_flow[owner].consumed += consumed
		month_flow[owner].shortage += demand - consumed
		if consumed + 0.000001 < demand:
			account.hunger += (demand - consumed) / demand
			account.loyalty = maxf(0.0, account.loyalty - 0.5)
		else:
			account.hunger = maxf(0.0, account.hunger - 1.0)

func _maintain(settlements: Array[Dictionary]) -> void:
	for settlement in settlements:
		var owner: String = str(settlement.owner)
		for resource in ["wood", "stone"]:
			var demand: float = 1.0 if resource == "wood" else 0.5
			var spent: float = minf(demand, countries[owner].stock[resource])
			countries[owner].stock[resource] -= spent
			month_flow[owner].maintenance[resource] += spent
			month_flow[owner].maintenance_shortage[resource] += demand - spent

func redistribute(id: int, resource: String, quantity: float, people: Array[Dictionary]) -> Dictionary:
	if id < 0 or id >= accounts.size() or people[id].owner != "council" or resource not in RESOURCES or not is_finite(quantity) or quantity <= 0:
		return {"ok": false, "reason": "配給先と数量を確認してください。"}
	if countries.council.stock[resource] + 0.000001 < quantity:
		return {"ok": false, "reason": "国庫の在庫が不足しています。"}
	countries.council.stock[resource] = maxf(0.0, countries.council.stock[resource] - quantity)
	accounts[id].stock[resource] += quantity
	if resource == "food":
		month_flow.council.relief += quantity
	return {"ok": true, "reason": "%sへ%sを%.1f配給しました。" % [people[id].name, LABELS[resource], quantity]}

func snapshot() -> Dictionary:
	var fields: Array = []
	for site in worksites:
		fields.append({"remaining": site.remaining, "fertility": site.fertility, "crops": site.crops.duplicate(true)})
	return {"day": day, "accounts": accounts.duplicate(true), "countries": countries.duplicate(true), "worksites": fields, "reports": reports.duplicate(true), "month_flow": month_flow.duplicate(true)}

func restore(data: Variant, people: Array[Dictionary], expected_day: int, partial_day_seconds: float = DAY_SECONDS) -> bool:
	if not data is Dictionary or not _integer(data.get("day"), expected_day, expected_day):
		return false
	if not data.get("accounts") is Array or data.accounts.size() != accounts.size() or not data.get("countries") is Dictionary or not data.get("month_flow") is Dictionary:
		return false
	if data.countries.size() != countries.size() or data.month_flow.size() != countries.size():
		return false
	if not data.get("worksites") is Array or data.worksites.size() != worksites.size() or not data.get("reports") is Array or data.reports.size() > 12:
		return false
	for owner in countries:
		var country: Variant = data.countries.get(owner)
		if not country is Dictionary or not _inventory(country.get("stock")) or not _number(country.get("tax"), 0, 1) or not country.get("relief") is bool or not _valid_flow(data.month_flow.get(owner)):
			return false
	var counts: Dictionary = {}
	var seats: Dictionary = {}
	for id in range(accounts.size()):
		var account: Variant = data.accounts[id]
		if not account is Dictionary or not _inventory(account.get("stock")) or not _inventory(account.get("income")) or not _number(account.get("loyalty"), 0, 100) or not _number(account.get("strength"), 0, 100) or not _number(account.get("hunger"), 0, 1e12) or not _integer(account.get("job"), -1, worksites.size() - 1) or not _integer(account.get("slot"), -1, 3) or not account.get("work") is Dictionary:
			return false
		var work_sum: float = 0.0
		for key in account.work:
			if not _site_key(key) or not _number(account.work[key], 0, DAY_SECONDS):
				return false
			work_sum += float(account.work[key])
		if work_sum > partial_day_seconds + 0.000001:
			return false
		var job: int = int(account.job)
		if job >= 0:
			var slot: int = int(account.slot)
			var seat: String = "%d:%d" % [job, slot]
			if slot < 0 or slot >= worksites[job].capacity or seats.has(seat):
				return false
			seats[seat] = true
			if people[id].role != "住民" or worksites[job].owner != people[id].owner or people[id].order not in ["移動", "労働"]:
				return false
			counts[job] = int(counts.get(job, 0)) + 1
			if counts[job] > worksites[job].capacity:
				return false
			if people[id].order == "労働" and people[id].position.distance_to(work_position(job, slot)) > 0.1:
				return false
			if people[id].order == "移動" and not people[id].path[-1].is_equal_approx(work_position(job, slot)):
				return false
		elif people[id].order == "労働" or int(account.slot) != -1:
			return false
	for index in range(worksites.size()):
		var field: Variant = data.worksites[index]
		if not field is Dictionary or not _number(field.get("remaining"), 0, 240 if worksites[index].kind == "wood" else 300) or not _number(field.get("fertility"), 0.5, 1) or not field.get("crops") is Dictionary:
			return false
		for key in field.crops:
			if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 0 or int(key) >= accounts.size() or not _number(field.crops[key], 0, 1e12) or worksites[index].kind != "farm":
				return false
	var previous_month: int = maxi(0, expected_day / MONTH_DAYS - data.reports.size())
	for report in data.reports:
		if not report is Dictionary or not _integer(report.get("month"), previous_month + 1, previous_month + 1) or not report.get("countries") is Dictionary:
			return false
		for owner in countries:
			if not _valid_flow(report.countries.get(owner)):
				return false
		previous_month += 1
	day = expected_day
	accounts.assign(data.accounts.duplicate(true))
	for account in accounts:
		account.job = int(account.job)
		account.slot = int(account.slot)
	countries = data.countries.duplicate(true)
	month_flow = data.month_flow.duplicate(true)
	reports.assign(data.reports.duplicate(true))
	for index in range(worksites.size()):
		var field: Dictionary = data.worksites[index].duplicate(true)
		for key in ["remaining", "fertility", "crops"]:
			worksites[index][key] = field[key]
	return true

func _site_key(value: Variant) -> bool:
	return value is String and value.is_valid_int() and str(int(value)) == value and int(value) >= 0 and int(value) < worksites.size()

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

static func _inventory(value: Variant) -> bool:
	if not value is Dictionary or value.size() != RESOURCES.size():
		return false
	for resource in RESOURCES:
		if not _number(value.get(resource), 0, 1e12):
			return false
	return true

static func _valid_flow(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["produced", "requested", "paid", "maintenance", "maintenance_shortage"]:
		if not _inventory(value.get(key)):
			return false
	for key in ["consumed", "relief", "shortage", "seed"]:
		if not _number(value.get(key), 0, 1e12):
			return false
	return true
