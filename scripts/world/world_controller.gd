extends Control
## Coordinator for the new milestone. Legacy scenes/main.tscn remains standalone.

const World = preload("res://scripts/world/world_state.gd")
const Save = preload("res://scripts/world/world_save.gd")
const MapView = preload("res://scripts/world/map_view.gd")
const UI = preload("res://scripts/ui/ui.gd")
var world: RefCounted = World.new()
var map_view: SubViewportContainer
var selected_entity: int = -1
var selected_site: int = -1
var patrol_mode: bool = false
var title_label: Label
var details_label: Label
var area_label: Label
var verdict_label: Label
var clock_label: Label
var notice_label: Label
var log_label: RichTextLabel
var pause_button: Button
var political_button: Button
var economy_label: Label
var report_label: Label
var work_choice: OptionButton
var work_button: Button
var ration_button: Button
var tax_value: SpinBox
var tax_button: Button
var relief_check: CheckButton
var transport_source: OptionButton
var transport_target: OptionButton
var transport_resource: OptionButton
var transport_amount: SpinBox
var transport_button: Button
var resume_button: Button
var return_button: Button
var shipment_label: Label
var patrol_button: Button
var halt_button: Button
var begin_button: Button
var example_button: Button
var cancel_button: Button
var submit_button: Button
var evaluation: Dictionary = {}
var panel_elapsed: float = 0.0

func _ready() -> void:
	theme = UI.theme()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic", "Meiryo", "Noto Sans CJK JP"])
	theme.default_font = font
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = UI.label_text("FRONTIER COUNCIL", 25, UI.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	clock_label = UI.label_text("", 15, UI.TEAL)
	clock_label.custom_minimum_size.x = 245
	header.add_child(clock_label)
	pause_button = _button("一時停止", _toggle_pause)
	header.add_child(pause_button)
	for value in [1, 2, 4]:
		header.add_child(_button("%d×" % value, func() -> void: world.set_speed(value)))
	header.add_child(_button("初期化", _reset_world))
	column.add_child(UI.label_text("連続した世界  /  左クリック：選択　右クリック：移動　中ボタンドラッグ：地図移動　ホイール：拡大縮小　Space：停止", 13, UI.MUTED))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	map_view = MapView.new()
	map_view.custom_minimum_size = Vector2(650, 470)
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.world = world
	row.add_child(map_view)
	map_view.person_selected.connect(_select_person)
	map_view.site_selected.connect(_select_site)
	map_view.destination_requested.connect(_destination)
	map_view.border_point_moved.connect(world.move_border_point)
	map_view.border_point_inserted.connect(world.insert_border_point)
	map_view.border_point_removed.connect(world.remove_border_point)
	# Scrollable sidebar keeps controls reachable on smaller windows.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size.x = 322
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var sidebar: VBoxContainer = VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 7)
	scroll.add_child(sidebar)
	title_label = UI.label_text("", 21, UI.GOLD)
	sidebar.add_child(title_label)
	details_label = UI.label_text("", 14)
	details_label.custom_minimum_size.y = 80
	sidebar.add_child(details_label)
	var commands: HBoxContainer = HBoxContainer.new()
	sidebar.add_child(commands)
	halt_button = _button("命令解除", _halt)
	patrol_button = _button("巡回先を指定", _choose_patrol)
	commands.add_child(halt_button)
	commands.add_child(patrol_button)
	sidebar.add_child(_button("地図全体を表示", func() -> void: map_view.fit_map()))
	var save_controls: HBoxContainer = HBoxContainer.new()
	sidebar.add_child(save_controls)
	save_controls.add_child(_button("世界を保存", _save_world))
	save_controls.add_child(_button("読み込む", _load_world))
	political_button = _button("政治調整を開始", _toggle_political_turn)
	sidebar.add_child(political_button)
	sidebar.add_child(UI.label_text("政治調整中は世界全体が停止します。税率・配給方針・土地交換を調整できます。", 13, UI.MUTED))
	sidebar.add_child(HSeparator.new())
	sidebar.add_child(UI.label_text("生活と国家財政", 20, UI.GOLD))
	economy_label = UI.label_text("", 14, UI.TEAL)
	sidebar.add_child(economy_label)
	var jobs: HBoxContainer = HBoxContainer.new()
	sidebar.add_child(jobs)
	work_choice = OptionButton.new()
	for label in ["仕事を解除", "農業", "伐採", "採石"]:
		work_choice.add_item(label)
	work_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jobs.add_child(work_choice)
	work_button = _button("割り当て", _assign_work)
	jobs.add_child(work_button)
	ration_button = _button("選択した人物へ食料1を配給", _give_ration)
	sidebar.add_child(ration_button)
	var tax_row: HBoxContainer = HBoxContainer.new()
	tax_row.add_theme_constant_override("separation", 8)
	sidebar.add_child(tax_row)
	var tax_caption: Label = UI.label_text("現物税 %", 14)
	tax_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	tax_row.add_child(tax_caption)
	tax_value = SpinBox.new()
	tax_value.min_value = 0
	tax_value.max_value = 100
	tax_value.step = 1
	tax_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tax_row.add_child(tax_value)
	tax_button = _button("適用", _apply_tax)
	tax_row.add_child(tax_button)
	relief_check = CheckButton.new()
	relief_check.text = "食料不足時に国庫から自動配給"
	relief_check.toggled.connect(_change_relief)
	sidebar.add_child(relief_check)
	report_label = UI.label_text("", 13, UI.MUTED)
	sidebar.add_child(report_label)
	sidebar.add_child(UI.label_text("物資の陸上輸送", 20, UI.GOLD))
	sidebar.add_child(UI.label_text("自国の住民を選択。上が出発元、下が届け先。国庫の受渡地点は自国の村です。", 13, UI.MUTED))
	transport_source = OptionButton.new()
	transport_target = OptionButton.new()
	for choice in [transport_source, transport_target]:
		choice.add_item("国庫（自国の村）")
		for id in range(10):
			choice.add_item(world.entities[id].name + " の私有在庫")
		sidebar.add_child(choice)
	transport_target.select(1)
	var cargo_row: HBoxContainer = HBoxContainer.new()
	sidebar.add_child(cargo_row)
	transport_resource = OptionButton.new()
	for resource in World.Economy.RESOURCES:
		transport_resource.add_item(World.Economy.LABELS[resource])
	cargo_row.add_child(transport_resource)
	transport_amount = SpinBox.new()
	transport_amount.min_value = 0.1
	transport_amount.max_value = 15
	transport_amount.step = 0.1
	transport_amount.value = 1
	transport_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cargo_row.add_child(transport_amount)
	transport_button = _button("選択した住民に輸送を指示", _transport)
	sidebar.add_child(transport_button)
	shipment_label = UI.label_text("", 13, UI.TEAL)
	sidebar.add_child(shipment_label)
	var transport_actions: HBoxContainer = HBoxContainer.new()
	sidebar.add_child(transport_actions)
	resume_button = _button("輸送を再開", func() -> void: notice_label.text = world.resume_transport(selected_entity).reason)
	return_button = _button("取消・返送", func() -> void: notice_label.text = world.resume_transport(selected_entity, true).reason)
	transport_actions.add_child(resume_button)
	transport_actions.add_child(return_button)
	sidebar.add_child(UI.label_text("命令解除：積込前は取消、積込後は荷物を保持して停止。税と自動配給は現段階では即時処理です。", 12, UI.MUTED))
	sidebar.add_child(HSeparator.new())
	sidebar.add_child(UI.label_text("土地交換の交渉", 20, UI.GOLD))
	sidebar.add_child(UI.label_text("国境は地形や人物の所属と別の状態です。青緑は自国の取得、赤は相手国の取得を表します。", 13, UI.MUTED))
	begin_button = _button("国境の提案を開始", _begin)
	sidebar.add_child(begin_button)
	example_button = _button("同面積の試案を作る", _example)
	sidebar.add_child(example_button)
	area_label = UI.label_text("", 15, UI.TEAL)
	sidebar.add_child(area_label)
	verdict_label = UI.label_text("", 14)
	verdict_label.custom_minimum_size.y = 50
	sidebar.add_child(verdict_label)
	submit_button = _button("相手国に提案する", _submit)
	cancel_button = _button("提案を取り消す", _cancel)
	sidebar.add_child(submit_button)
	sidebar.add_child(cancel_button)
	sidebar.add_child(UI.label_text("丸い点：ドラッグで移動\n線をダブルクリック：点を追加\n点を右クリック：削除\n四角い両端：固定 / 標石に吸着", 13, UI.MUTED))
	sidebar.add_child(UI.label_text("相手国の仮判断：取得面積が譲渡面積の95%以上なら合意。村・城塞・無所属地域は交換対象外です。", 12, UI.MUTED))
	column.add_child(UI.label_text("● 青緑：自国人物　● 赤：他国人物　● 淡黄：無所属　■：兵士　薄い実線：確定国境　黄色の線：提案", 12, UI.MUTED))
	notice_label = UI.label_text("住民を選んで仕事を割り当てます。税率と配給方針は「政治調整を開始」から変更できます。", 14, UI.GOLD)
	column.add_child(notice_label)
	log_label = RichTextLabel.new()
	log_label.custom_minimum_size.y = 64
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_label.add_theme_color_override("default_color", UI.MUTED)
	log_label.scroll_following = true
	column.add_child(log_label)
	world.changed.connect(_state_changed)
	_state_changed()

func _button(value: String, action: Callable) -> Button:
	var button: Button = UI.button(value, action)
	button.focus_mode = Control.FOCUS_NONE
	return button

func _process(delta: float) -> void:
	world.advance(delta)
	panel_elapsed += delta
	if panel_elapsed >= 0.2:
		panel_elapsed = 0
		_update_panel()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _state_changed() -> void:
	evaluation = world.treaty.evaluate()
	tax_value.set_value_no_signal(world.economy.countries.council.tax * 100.0)
	relief_check.set_pressed_no_signal(world.economy.countries.council.relief)
	map_view.update_assessment()
	_update_panel()
	log_label.text = "世界の記録\n" + "\n".join(world.journal.slice(maxi(0, world.journal.size() - 8)))

func _update_panel() -> void:
	var seconds: int = int(world.elapsed)
	clock_label.text = "%d日 %02d:%02d:%02d / %d× %s" % [seconds / 86400, (seconds / 3600) % 24, (seconds / 60) % 60, seconds % 60, world.speed, "政治調整" if world.political_turn else ("停止" if world.paused else "進行")]
	pause_button.text = "再開 [Space]" if world.paused else "一時停止 [Space]"
	pause_button.disabled = world.political_turn
	political_button.text = "政治調整を終了" if world.political_turn else "政治調整を開始"
	tax_button.disabled = not world.political_turn
	tax_value.editable = world.political_turn
	relief_check.disabled = not world.political_turn
	var economy: RefCounted = world.economy
	var stock: Dictionary = economy.countries.council.stock
	economy_label.text = "仮暦 月%d・%d日 / %s\n国庫 食料%.2f・木材%.2f・石材%.2f" % [economy.day / 30 + 1, economy.day % 30 + 1, economy.season(), stock.food, stock.wood, stock.stone]
	if economy.reports.is_empty():
		report_label.text = "決算は月末です。農業は夏と秋に収穫。移動・巡回中は生産しません。"
	else:
		var latest: Dictionary = economy.reports[-1]
		var flow: Dictionary = latest.countries.council
		report_label.text = "月%d 決算\n生産 食料%.1f / 木材%.1f / 石材%.1f\n税要求 %.1f / %.1f / %.1f\n実納税 %.1f / %.1f / %.1f\n食料消費%.1f・配給%.1f・不足%.2f\n拠点維持 木材%.1f・石材%.1f\n維持不足 木材%.1f・石材%.1f" % [latest.month, flow.produced.food, flow.produced.wood, flow.produced.stone, flow.requested.food, flow.requested.wood, flow.requested.stone, flow.paid.food, flow.paid.wood, flow.paid.stone, flow.consumed, flow.relief, flow.shortage, flow.maintenance.wood, flow.maintenance.stone, flow.maintenance_shortage.wood, flow.maintenance_shortage.stone]
	var can_command: bool = selected_entity >= 0 and world.entities[selected_entity].owner == "council" and world.treaty.draft.is_empty()
	halt_button.disabled = not can_command
	patrol_button.disabled = not can_command
	work_button.disabled = not can_command or world.entities[selected_entity].role != "住民"
	ration_button.disabled = not can_command
	var shipping: bool = world.shipments.has(str(selected_entity))
	transport_button.disabled = not can_command or world.entities[selected_entity].role != "住民" or shipping
	resume_button.disabled = not can_command or not shipping
	return_button.disabled = not can_command or not shipping
	shipment_label.text = "予約中・輸送中の物資も保存します。"
	if can_command and world.entities[selected_entity].role == "住民":
		transport_amount.max_value = world.Transport.capacity(world, selected_entity)
		shipment_label.text = "積載上限 %.1f" % transport_amount.max_value
	if shipping:
		var task: Dictionary = world.shipments[str(selected_entity)]
		var phases: Dictionary = {"pickup": "受取へ移動（在庫予約済）", "delivery": "配送中", "return": "返送中", "held": "荷物を保持して停止", "held_return": "返送を停止"}
		shipment_label.text += "\n%s %.1f / %s\n%s → %s" % [World.Economy.LABELS[task.resource], task.amount, phases[task.phase], _account_name(task.source), _account_name(task.target)]
	patrol_button.text = "巡回先を右クリック" if patrol_mode else "巡回先を指定"
	if selected_entity >= 0:
		var entity: Dictionary = world.entities[selected_entity]
		title_label.text = str(entity.name) + " / " + str(entity.role)
		details_label.text = "所属：%s　人物ID：%d\n所在地：%s\n座標：%.0f, %.0f　行動：%s\n%s" % [_owner_name(entity.owner), entity.id, _owner_name(world.treaty.owner_at(entity.position)), entity.position.x, entity.position.y, entity.order, "右クリックで移動を指示できます。" if entity.owner == "council" else "他国・無所属の人物は情報確認のみ。"]
		var account: Dictionary = economy.accounts[selected_entity]
		var job_name: String = "なし" if int(account.job) < 0 else str(economy.worksites[int(account.job)].name)
		details_label.text += "\n仕事：%s\n私有 食料%.2f・木材%.2f・石材%.2f\n忠誠%.0f・体力%.0f・不足日数%.1f" % [job_name, account.stock.food, account.stock.wood, account.stock.stone, account.loyalty, account.strength, account.hunger]
		var labor_seconds: float = 0.0
		for amount in account.work.values():
			labor_seconds += float(amount)
		details_label.text += "\n本日の労働：%.2f時間" % (labor_seconds / 3600.0)
	elif selected_site >= 0:
		var site: Dictionary = world.sites[selected_site]
		title_label.text = site.name
		details_label.text = "%s / %s\n座標：%.0f, %.0f\nこの段階では拠点の建設・譲渡は扱いません。" % [site.kind, _owner_name(site.owner), site.position.x, site.position.y]
	else:
		title_label.text = "地図を見渡す"
		details_label.text = "2国家・5拠点・24人\n海と崖は通行不可。川は石橋から渡れます。国境を越えても人物の所属は変わりません。"
	var editing: bool = not world.treaty.draft.is_empty()
	begin_button.disabled = editing
	cancel_button.disabled = not editing
	submit_button.disabled = not editing or not evaluation.get("valid", false)
	area_label.text = "自国の取得：%.0f\n相手国の取得：%.0f　/　条約 #%d" % [evaluation.get("council_gain", 0.0), evaluation.get("rival_gain", 0.0), world.treaty.revision]
	verdict_label.text = str(evaluation.get("reason", ""))
	verdict_label.add_theme_color_override("font_color", UI.TEAL if evaluation.get("accepted", false) else UI.MUTED)
	map_view.artwork.selected_entity = selected_entity
	map_view.artwork.selected_site = selected_site

func _select_person(id: int) -> void:
	selected_entity = id
	selected_site = -1
	patrol_mode = false
	_update_panel()

func _select_site(id: int) -> void:
	selected_site = id
	selected_entity = -1
	patrol_mode = false
	_update_panel()

func _destination(point: Vector2) -> void:
	var result: Dictionary = world.issue_patrol(selected_entity, point) if patrol_mode else world.issue_move(selected_entity, point)
	notice_label.text = result.reason
	if result.ok:
		patrol_mode = false
	_update_panel()

func _choose_patrol() -> void:
	patrol_mode = not patrol_mode
	notice_label.text = "右クリックで巡回の折り返し地点を指定してください。" if patrol_mode else "巡回先の指定を解除しました。"
	_update_panel()

func _halt() -> void:
	notice_label.text = world.halt(selected_entity).reason
	patrol_mode = false
	_update_panel()

func _assign_work() -> void:
	var result: Dictionary = world.halt(selected_entity) if work_choice.selected == 0 else world.assign_job(selected_entity, work_choice.selected - 1)
	notice_label.text = result.reason
	patrol_mode = false

func _give_ration() -> void:
	notice_label.text = world.redistribute(selected_entity, "food", 1.0).reason

func _apply_tax() -> void:
	notice_label.text = world.set_tax_rate(tax_value.value / 100.0).reason

func _change_relief(value: bool) -> void:
	notice_label.text = world.set_relief(value).reason

func _toggle_pause() -> void:
	if world.political_turn:
		notice_label.text = "政治調整を終了すると時間を再開できます。"
		return
	world.set_paused(not world.paused)

func _toggle_political_turn() -> void:
	if world.political_turn:
		notice_label.text = world.end_political_turn().reason
	else:
		world.begin_political_turn()
		notice_label.text = "政治調整中です。税率・配給方針・土地交換を調整し、終了ボタンで通常の操作へ戻ります。"

func _begin() -> void:
	patrol_mode = false
	world.begin_proposal()
	notice_label.text = "黄色い線の丸い点をドラッグして交換案を作成してください。"

func _example() -> void:
	patrol_mode = false
	world.example_proposal()
	notice_label.text = "同面積の交換案です。点を調整するか「相手国に提案する」で提出してください。"

func _submit() -> void:
	var result: Dictionary = world.submit_proposal()
	notice_label.text = "土地交換に合意しました。両国の領土を更新しました。" if result.accepted else result.reason

func _cancel() -> void:
	world.cancel_proposal()
	notice_label.text = "提案を取り消しました。確定済みの国境は元のままです。"

func _reset_world() -> void:
	_replace_world(World.new())
	notice_label.text = "新しい世界を開始しました。"

func _save_world() -> void:
	notice_label.text = Save.save_world(world).reason

func _load_world() -> void:
	var result: Dictionary = Save.load_world()
	if result.ok:
		_replace_world(result.world)
	notice_label.text = result.reason

func _replace_world(replacement: RefCounted) -> void:
	world.changed.disconnect(_state_changed)
	# Reconnect signal targets to the replacement authoritative model.
	map_view.border_point_moved.disconnect(world.move_border_point)
	map_view.border_point_inserted.disconnect(world.insert_border_point)
	map_view.border_point_removed.disconnect(world.remove_border_point)
	world = replacement
	map_view.configure(world)
	map_view.border_point_moved.connect(world.move_border_point)
	map_view.border_point_inserted.connect(world.insert_border_point)
	map_view.border_point_removed.connect(world.remove_border_point)
	world.changed.connect(_state_changed)
	selected_entity = -1
	selected_site = -1
	patrol_mode = false
	map_view.dragging_point = -1
	map_view.panning = false
	map_view.artwork.hovered_entity = -1
	map_view.fit_map()
	_state_changed()

func _owner_name(owner: String) -> String:
	return "評議国（自国）" if owner == "council" else ("東方国" if owner == "rival" else ("海" if owner == "sea" else "無所属"))

func _account_name(id: int) -> String:
	return "国庫" if id == -1 else str(world.entities[id].name)

func _transport() -> void:
	notice_label.text = world.issue_transport(selected_entity, transport_source.selected - 1, transport_target.selected - 1, World.Economy.RESOURCES[transport_resource.selected], transport_amount.value).reason
	patrol_mode = false
