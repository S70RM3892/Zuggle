extends CanvasLayer
## Tuning.SPECSからスライダーを並べる調整パネル。F1かパッドのBack(View)で開閉。
## 開いている間はプレイヤーの入力を止め、十字キーでスライダーを選んで左右で動かす。

@export var player_path: NodePath

var _speed_label: Label
var _sliders := {}
var _value_labels := {}
var _first_slider: HSlider

@onready var _player: Player = get_node(player_path)


func _ready() -> void:
	_build()
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_set_open(not visible)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if visible:
		_speed_label.text = "水平速度 %.2f m/s" % _player.horizontal_speed()
		if _player.is_wall_running():
			_speed_label.text += "　壁走り中（残り %.2f 秒）" % _player.wallrun_time_left()
		elif _player.is_mantling():
			_speed_label.text += "　よじ登り中"
		elif _player.is_sliding():
			_speed_label.text += "　スライディング中"
		if HitFeel.last_power > 0.0:
			_speed_label.text += "　直前のヒットの威力 %.2f" % HitFeel.last_power


func _set_open(open: bool) -> void:
	visible = open
	_player.input_enabled = not open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_sync_from_tuning()
		_first_slider.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title := Label.new()
	title.text = "調整パネル（1項目だけ動かす → 倍と半分を試す → 詰める）"
	box.add_child(title)

	_speed_label = Label.new()
	box.add_child(_speed_label)

	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)

	for spec in Tuning.SPECS:
		var key: String = spec[0]
		var name_label := Label.new()
		name_label.text = spec[1]
		grid.add_child(name_label)

		var slider := HSlider.new()
		slider.min_value = spec[2]
		slider.max_value = spec[3]
		slider.step = spec[4]
		slider.custom_minimum_size = Vector2(180, 0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_slider_changed.bind(key))
		grid.add_child(slider)
		_sliders[key] = slider
		if _first_slider == null:
			_first_slider = slider

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(56, 0)
		grid.add_child(value_label)
		_value_labels[key] = value_label

	var buttons := HBoxContainer.new()
	box.add_child(buttons)

	var reset := Button.new()
	reset.text = "初期値に戻す"
	reset.pressed.connect(func() -> void:
		Tuning.reset_all()
		_sync_from_tuning())
	buttons.add_child(reset)

	var copy := Button.new()
	copy.text = "値をコピー（改善ログ用）"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(Tuning.dump())
		print(Tuning.dump()))
	buttons.add_child(copy)

	var respawn := Button.new()
	respawn.text = "スタート地点へ戻る"
	respawn.pressed.connect(func() -> void: _player.respawn())
	buttons.add_child(respawn)


func _sync_from_tuning() -> void:
	for key in _sliders:
		_sliders[key].set_value_no_signal(Tuning.get(key))
		_value_labels[key].text = _format(Tuning.get(key))


func _on_slider_changed(value: float, key: String) -> void:
	Tuning.set(key, value)
	_value_labels[key].text = _format(value)


func _format(value: float) -> String:
	return "%.3f" % value if absf(value) < 1.0 else "%.1f" % value
