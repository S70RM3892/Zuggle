extends Node
## M1の動きを自動で確かめる。実行：
##   godot --headless --path . res://tests/test_movement.tscn
## 失敗があれば終了コード1で終わる。

var DT := 1.0 / Engine.physics_ticks_per_second

var _player: Player
var _failures := 0


func _ready() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	_player = scene.get_node("Player")
	_run.call_deferred()


func _run() -> void:
	await _test_lands_on_floor()
	await _test_reaches_max_speed()
	await _test_jump()
	await _test_jump_buffer()
	await _test_coyote_time()
	await _test_coyote_expires()
	await _test_air_keeps_momentum()
	await _test_jump_cut()
	print("\n%s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_failures += 1


## action_pressした入力は、次の物理フレームでis_action_just_pressedになる。
## 押してから結果を見るときは2フレーム待つ。
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _reset_at(pos: Vector3) -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
		Input.action_release(action)
	_player.global_position = pos
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await _frames(60)


func _test_lands_on_floor() -> void:
	print("着地")
	await _reset_at(Vector3(0, 3, 8))
	_check(_player.is_on_floor(), "床に立つ")


func _test_reaches_max_speed() -> void:
	print("走り")
	await _reset_at(Vector3(0, 0.9, 8))
	Input.action_press("move_forward")
	await _frames(60)
	_check(absf(_player.horizontal_speed() - Tuning.max_speed) < 0.05, "0.5秒で最高速度に届く (%.2f)" % _player.horizontal_speed())
	_check(_player.velocity.z < 0.0, "前(-Z)へ進む")
	Input.action_release("move_forward")
	await _frames(60)
	_check(_player.horizontal_speed() < 0.01, "離すと止まる")


func _test_jump() -> void:
	print("ジャンプ")
	await _reset_at(Vector3(0, 0.9, 8))
	Input.action_press("jump")
	await _frames(2)
	_check(_player.velocity.y > 0.0 and not _player.is_on_floor(), "押すと跳ぶ")
	var apex := _player.global_position.y
	while _player.velocity.y > 0.0:
		await get_tree().physics_frame
		apex = maxf(apex, _player.global_position.y)
	var expected := Tuning.jump_velocity * Tuning.jump_velocity / (2.0 * Tuning.gravity)
	var height := apex - 0.9
	_check(absf(height - expected) < 0.1, "押し続けると理論値の高さ (%.2f / %.2f m)" % [height, expected])
	Input.action_release("jump")
	await _frames(120)


func _test_jump_buffer() -> void:
	print("先行入力")
	await _reset_at(Vector3(0, 0.9, 8))
	_player.global_position.y = 1.4 # 床から0.5m浮かせて落とす
	_player.velocity = Vector3.ZERO
	# 着地までのフレーム数を数え、着地の少し前（受付時間の内側）に押す
	var frames_to_land := int(ceil(sqrt(2.0 * 0.5 / (Tuning.gravity * Tuning.fall_gravity_mult)) / DT))
	var press_before := int(Tuning.jump_buffer / DT) - 3
	await _frames(frames_to_land - press_before)
	_check(not _player.is_on_floor(), "押す時点ではまだ空中")
	Input.action_press("jump")
	var jumped := false
	for i in press_before + 10:
		await get_tree().physics_frame
		if _player.velocity.y > 0.0:
			jumped = true
			break
	_check(jumped, "着地の直前に押しても、着地と同時に跳ぶ")
	Input.action_release("jump")
	await _frames(120)


func _test_coyote_time() -> void:
	print("コヨーテタイム")
	await _start_off_ledge()
	await _frames(int(Tuning.coyote_time / DT) - 3)
	_check(not _player.is_on_floor(), "崖から出て空中にいる")
	Input.action_press("jump")
	await _frames(2)
	_check(_player.velocity.y > 0.0, "崖を出た直後なら跳べる")
	Input.action_release("jump")


func _test_coyote_expires() -> void:
	print("コヨーテタイム切れ")
	await _start_off_ledge()
	await _frames(int(Tuning.coyote_time / DT) + 6)
	Input.action_press("jump")
	await _frames(2)
	_check(_player.velocity.y <= 0.0, "時間を過ぎたら跳べない")
	Input.action_release("jump")


## PlatformA（上面y=1、z=-4が端）の上に立たせてから、端の外へ出す。
func _start_off_ledge() -> void:
	await _reset_at(Vector3(10, 1.9, 0))
	_player.global_position = Vector3(10, 1.9, -4.5)
	_player.velocity = Vector3.ZERO


func _test_air_keeps_momentum() -> void:
	print("空中の勢い")
	await _reset_at(Vector3(0, 0.9, 8))
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("move_forward")
	var before := _player.horizontal_speed()
	await _frames(30)
	_check(not _player.is_on_floor(), "まだ空中")
	_check(absf(_player.horizontal_speed() - before) < 0.01, "入力を離しても水平速度が落ちない (%.2f → %.2f)" % [before, _player.horizontal_speed()])
	Input.action_release("jump")
	await _frames(120)


func _test_jump_cut() -> void:
	print("小ジャンプ")
	await _reset_at(Vector3(0, 0.9, 8))
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	var apex := _player.global_position.y
	while _player.velocity.y > 0.0:
		await get_tree().physics_frame
		apex = maxf(apex, _player.global_position.y)
	var full := Tuning.jump_velocity * Tuning.jump_velocity / (2.0 * Tuning.gravity)
	_check(apex - 0.9 < full * 0.6, "すぐ離すと低く跳ぶ (%.2f m)" % (apex - 0.9))
	await _frames(120)
