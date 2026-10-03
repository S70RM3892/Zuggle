extends Node
## よじ登り・スーパーグライド・スライディングを自動で確かめる。実行：
##   godot --headless --path . res://tests/test_superglide.tscn
## 失敗があれば終了コード1で終わる。
## GlideLedgeは高さ1.5m、x=-22〜-18、z=-12〜2（手前の面はz=2）。プレイヤーの半径は0.35m、高さ1.8m。

const LEDGE_TOP := 1.5
const LEDGE_FACE_Z := 2.0

var DT := 1.0 / Engine.physics_ticks_per_second

var _player: Player
var _hud: Node
var _failures := 0
var _last_tech := ""
var _last_success := false


func _ready() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	_player = scene.get_node("Player")
	_hud = scene.get_node("HUD")
	_player.move_tech.connect(func(text: String, success: bool) -> void:
		_last_tech = text
		_last_success = success)
	_run.call_deferred()


func _run() -> void:
	await _test_mantle()
	await _test_no_mantle_without_input()
	await _test_no_mantle_on_tall_wall()
	await _test_superglide_jump_then_crouch()
	await _test_superglide_crouch_then_jump()
	await _test_superglide_after_climb()
	await _test_no_double_jump()
	await _test_gap_too_long()
	await _test_too_early()
	await _test_slide()
	await _test_slide_jump()
	await _test_air_crouch_slides_on_landing()
	print("\n%s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _release_all() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "crouch"]:
		Input.action_release(action)


func _place(pos: Vector3, yaw := 0.0) -> void:
	_release_all()
	_player.respawn()
	await _frames(2)
	_player.global_position = pos
	_player.rotation = Vector3(0, yaw, 0)
	_player.velocity = Vector3.ZERO
	await _frames(30)
	_last_tech = ""


func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(1)
	Input.action_release(action)


## GlideLedgeの前に立ち、前へ倒して跳び、よじ登りが始まるまで待つ。始まればtrue
func _start_mantle() -> bool:
	await _place(Vector3(-20, 0.9, LEDGE_FACE_Z + 0.6))
	Input.action_press("move_forward")
	Input.action_press("jump")
	for i in int(0.5 / DT):
		await get_tree().physics_frame
		if _player.is_mantling():
			Input.action_release("jump")
			return true
	Input.action_release("jump")
	return false


func _wait_window() -> bool:
	for i in int(1.0 / DT):
		if _player.superglide_window():
			return true
		await get_tree().physics_frame
	return false


func _test_mantle() -> void:
	print("よじ登り")
	_check(await _start_mantle(), "段差（1.5m）へ前へ倒して跳ぶと、よじ登り始める")
	var frames := 0
	while _player.is_mantling() and frames < 200:
		await get_tree().physics_frame
		frames += 1
	_check(absf(frames * DT - Tuning.mantle_time) < 0.03, "約%.2f秒で登り切る (%.2f 秒)" % [Tuning.mantle_time, frames * DT])
	await _frames(3)
	var feet := _player.global_position.y - 0.9
	_check(_player.is_on_floor() and absf(feet - LEDGE_TOP) < 0.05, "段差の上に立つ (足 %.2f m)" % feet)
	_check(_player.global_position.z < LEDGE_FACE_Z, "縁を越えている (z %.2f)" % _player.global_position.z)
	_check(_player.horizontal_speed() <= Tuning.max_speed + 0.01, "スーパーグライドしなければ速さは最高速度まで")
	_release_all()


func _test_no_mantle_without_input() -> void:
	print("前へ倒していなければよじ登らない")
	await _place(Vector3(-20, 0.9, LEDGE_FACE_Z + 0.4))
	Input.action_press("jump")
	var mantled := false
	for i in int(0.8 / DT):
		await get_tree().physics_frame
		mantled = mantled or _player.is_mantling()
	_check(not mantled, "その場で跳んでも登らない")
	_release_all()


func _test_no_mantle_on_tall_wall() -> void:
	print("高すぎる壁は登らない")
	# RunWall（高さ5m、手前の面はz=17.5）に正面から
	await _place(Vector3(0, 0.9, 17.5 - 0.6), PI)
	Input.action_press("move_forward")
	Input.action_press("jump")
	var mantled := false
	for i in int(0.8 / DT):
		await get_tree().physics_frame
		mantled = mantled or _player.is_mantling()
	_check(not mantled, "5mの壁には登らない")
	_release_all()


func _test_superglide_jump_then_crouch() -> void:
	print("スーパーグライド（ジャンプ → しゃがみ）")
	_check(await _start_mantle(), "よじ登り始める")
	_check(await _wait_window(), "縁を越える頃に受付が開く")
	Input.action_press("jump")
	await _frames(2) # 1フレーム遅れてしゃがむ
	Input.action_press("crouch")
	await _frames(2)
	var h := _player.horizontal_speed()
	_check(absf(h - Tuning.superglide_speed) < 0.05, "スーパーグライドの速さで飛ぶ (%.2f m/s)" % h)
	_check(_player.velocity.y > 0.0 and _player.velocity.y <= Tuning.superglide_up + 0.01, "低く飛ぶ (vy %.2f)" % _player.velocity.y)
	_check(_last_success and _last_tech.begins_with("スーパーグライド"), "成功と間の長さを出す（%s）" % _last_tech)
	_check(_hud.last_text() == _last_tech, "HUDに表示する")
	_release_all()
	Input.action_press("move_forward")
	var landed := false
	for i in int(1.5 / DT):
		await get_tree().physics_frame
		if _player.is_on_floor():
			landed = true
			break
	await _frames(1)
	_check(landed and _player.is_sliding(), "着地するとスライディングに入る")
	_check(_player.horizontal_speed() > Tuning.max_speed, "最高速度を超えたまま滑る (%.2f m/s)" % _player.horizontal_speed())
	_check(_player.camera.fov > Tuning.fov + 1.0, "速いほど視野が広がる (%.1f 度)" % _player.camera.fov)
	_release_all()


func _test_superglide_crouch_then_jump() -> void:
	print("スーパーグライド（しゃがみ → ジャンプ）")
	_check(await _start_mantle(), "よじ登り始める")
	_check(await _wait_window(), "受付が開く")
	Input.action_press("crouch")
	await _frames(2)
	Input.action_press("jump")
	await _frames(2)
	_check(absf(_player.horizontal_speed() - Tuning.superglide_speed) < 0.05, "しゃがみが先でも決まる (%.2f m/s)" % _player.horizontal_speed())
	_release_all()
	await _frames(int(1.0 / DT))


func _test_superglide_after_climb() -> void:
	print("登り切った直後のスーパーグライド")
	_check(await _start_mantle(), "よじ登り始める")
	while _player.is_mantling():
		await get_tree().physics_frame
	_check(_player.superglide_window(), "登り切った直後も受付中")
	Input.action_press("jump")
	await _frames(2)
	Input.action_press("crouch")
	await _frames(2)
	_check(absf(_player.horizontal_speed() - Tuning.superglide_speed) < 0.05, "決まる (%.2f m/s)" % _player.horizontal_speed())
	_check(not _player.superglide_window(), "決まったら受付を閉じる")
	_release_all()
	var landed := false
	for i in int(1.5 / DT):
		await get_tree().physics_frame
		if _player.is_on_floor():
			landed = true
			break
	await _frames(1)
	_check(landed and _player.is_sliding(), "立っていた所から飛んでも、着地でスライディングに入る")
	_release_all()


func _test_no_double_jump() -> void:
	print("よじ登りジャンプのあと空中では跳べない")
	_check(await _start_mantle(), "よじ登り始める")
	_check(await _wait_window(), "受付が開く")
	await _tap("jump")
	await _frames(int(0.1 / DT))
	var vy := _player.velocity.y
	await _tap("jump")
	await _frames(1)
	_check(_player.velocity.y < vy, "2回目の押しでは跳ばない (vy %.2f → %.2f)" % [vy, _player.velocity.y])
	_release_all()
	await _frames(int(1.0 / DT))


func _test_gap_too_long() -> void:
	print("ジャンプとしゃがみの間が長すぎる")
	_check(await _start_mantle(), "よじ登り始める")
	_check(await _wait_window(), "受付が開く")
	Input.action_press("jump")
	await _frames(int((Tuning.superglide_gap + 0.05) / DT))
	Input.action_press("crouch")
	await _frames(2)
	_check(_player.horizontal_speed() < Tuning.max_speed, "スーパーグライドにならない (%.2f m/s)" % _player.horizontal_speed())
	_check(_player.velocity.y > Tuning.superglide_up, "普通のジャンプになる (vy %.2f)" % _player.velocity.y)
	_check(not _last_success and _last_tech.contains("遅い"), "しゃがみが遅いと出す（%s）" % _last_tech)
	_release_all()
	await _frames(int(1.0 / DT))


func _test_too_early() -> void:
	print("早すぎる")
	_check(await _start_mantle(), "よじ登り始める")
	Input.action_press("jump")
	await _frames(2)
	Input.action_press("crouch")
	await _frames(2)
	_check(_player.is_mantling(), "体を持ち上げている間は何も起きない")
	_check(not _last_success and _last_tech.begins_with("早すぎ"), "早すぎと出す（%s）" % _last_tech)
	_release_all()
	Input.action_press("move_forward")
	while _player.is_mantling():
		await get_tree().physics_frame
	await _frames(int(0.3 / DT))
	_check(_player.horizontal_speed() <= Tuning.max_speed + 0.01, "スーパーグライドにならない (%.2f m/s)" % _player.horizontal_speed())
	_release_all()


func _run_to_max_speed() -> void:
	await _place(Vector3(0, 0.9, 8))
	Input.action_press("move_forward")
	await _frames(int(0.5 / DT))


func _test_slide() -> void:
	print("スライディング")
	await _run_to_max_speed()
	var eye := _player.head.position.y
	await _tap("crouch")
	await _frames(1)
	_check(_player.is_sliding(), "走っていてしゃがむと滑る")
	Input.action_release("move_forward")
	await _frames(int(0.2 / DT))
	var expected := Tuning.max_speed - Tuning.slide_friction * 0.2
	_check(absf(_player.horizontal_speed() - expected) < 0.2, "入力を離してもゆっくり減速する (%.2f / %.2f m/s)" % [_player.horizontal_speed(), expected])
	_check(_player.head.position.y < eye - 0.2, "目の高さが下がる")
	var frames := 0
	while _player.is_sliding() and frames < 600:
		await get_tree().physics_frame
		frames += 1
	_check(not _player.is_sliding(), "遅くなると終わる")
	_check(_player.horizontal_speed() < Tuning.slide_end_speed + 0.1, "終わるのは %.1f m/s 付近 (%.2f)" % [Tuning.slide_end_speed, _player.horizontal_speed()])
	await _place(Vector3(0, 0.9, 8))
	await _tap("crouch")
	await _frames(1)
	_check(not _player.is_sliding(), "止まっているときは滑らない")


func _test_slide_jump() -> void:
	print("スライディングジャンプ")
	await _run_to_max_speed()
	await _tap("crouch")
	await _frames(int(0.1 / DT))
	var before := _player.horizontal_speed()
	Input.action_release("move_forward")
	await _tap("jump")
	await _frames(int(0.2 / DT))
	_check(not _player.is_on_floor() and not _player.is_sliding(), "跳ぶとスライディングが終わる")
	_check(absf(_player.horizontal_speed() - before) < 0.15, "滑っていた速さのまま跳ぶ (%.2f → %.2f)" % [before, _player.horizontal_speed()])
	_release_all()


func _test_air_crouch_slides_on_landing() -> void:
	print("空中でしゃがむと、着地でスライディング")
	await _run_to_max_speed()
	await _tap("jump")
	await _frames(int(0.2 / DT))
	await _tap("crouch")
	var landed := false
	for i in int(1.5 / DT):
		await get_tree().physics_frame
		if _player.is_on_floor():
			landed = true
			break
	await _frames(1)
	_check(landed and _player.is_sliding(), "着地で滑る")
	_release_all()
