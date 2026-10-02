extends Node
## M2の壁走りを自動で確かめる。実行：
##   godot --headless --path . res://tests/test_wallrun.tscn
## 失敗があれば終了コード1で終わる。
## RunWallの手前の面はz=17.5、x=-12〜12。プレイヤーの半径は0.35m。
## WallrunCourseの足場は上面y=1、x=-12〜-3とx=3〜12（隙間6m）。

const WALL_SIDE_Z := 17.5 - 0.35 - 0.05 # 壁に沿って空中にいる位置

var DT := 1.0 / Engine.physics_ticks_per_second

var _player: Player
var _failures := 0


func _ready() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	_player = scene.get_node("Player")
	_run.call_deferred()


func _run() -> void:
	await _test_enters_and_keeps_speed()
	await _test_reduced_gravity()
	await _test_time_limit()
	await _test_exits_at_wall_end()
	await _test_head_on_does_not_start()
	await _test_too_slow_does_not_start()
	await _test_stick_away_detaches()
	await _test_jump_into_wall()
	await _test_course()
	await _test_turn_around()
	await _test_wall_jump()
	await _test_wall_jump_steer()
	await _test_wall_jump_to_opposite_wall()
	await _test_early_press_does_not_jump_off()
	await _test_wall_coyote()
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
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
		Input.action_release(action)


## 床に一度立たせて状態を戻してから、指定の位置・速度で空中に置く。
func _launch(pos: Vector3, vel: Vector3, yaw_deg := -90.0) -> void:
	_release_all()
	_player.respawn()
	await _frames(30)
	_player.rotation = Vector3(0, deg_to_rad(yaw_deg), 0) # -90度で前(-Z)が+Xを向く
	_player.global_position = pos
	# 置いた直後の1フレームは前回の「床の上」判定が残るので、止めたまま空中判定にする
	_player.velocity = Vector3.ZERO
	await _frames(1)
	_player.velocity = vel


func _test_enters_and_keeps_speed() -> void:
	print("壁沿いを跳ぶと壁走りに入る")
	await _launch(Vector3(-10, 3, WALL_SIDE_Z), Vector3(8, 0, 0))
	await _frames(3)
	_check(_player.is_wall_running(), "空中で壁の横にいると自動で入る")
	await _frames(int(0.5 / DT))
	_check(_player.is_wall_running(), "0.5秒後も続いている")
	_check(absf(_player.horizontal_speed() - 8.0) < 0.05, "進入時の速さを保つ (%.2f)" % _player.horizontal_speed())


func _test_reduced_gravity() -> void:
	print("壁走り中は落ちにくい")
	await _launch(Vector3(-10, 3, WALL_SIDE_Z), Vector3(8, 0, 0))
	var y0 := _player.global_position.y
	await _frames(int(1.0 / DT))
	var dropped := y0 - _player.global_position.y
	var free_fall := 0.5 * Tuning.gravity * Tuning.fall_gravity_mult * 1.0
	_check(_player.is_wall_running(), "1秒後も壁走り中")
	_check(dropped < free_fall * 0.3, "1秒で %.2f m しか下がらない（自由落下なら %.2f m）" % [dropped, free_fall])


func _test_time_limit() -> void:
	print("継続時間の上限")
	# 遅めに走らせ、壁の端より先に時間切れになるようにする
	await _launch(Vector3(-11, 4.4, WALL_SIDE_Z), Vector3(5, 0, 0))
	await _frames(1)
	_check(_player.is_wall_running(), "入る")
	var frames := 1
	while _player.is_wall_running() and frames < 600:
		await get_tree().physics_frame
		frames += 1
	var expected := int(Tuning.wallrun_max_time / DT)
	_check(absi(frames - expected) <= 2, "上限で外れる (%d / %d フレーム)" % [frames, expected])
	_check(not _player.is_on_floor(), "外れたのは空中")
	await _frames(int(0.05 / DT))
	_check(not _player.is_wall_running(), "同じ壁にすぐ貼り付き直さない")
	_check(_player.velocity.y < -2.0, "落下している (vy %.2f)" % _player.velocity.y)


func _test_exits_at_wall_end() -> void:
	print("壁の端で抜ける")
	await _launch(Vector3(9, 3.5, WALL_SIDE_Z), Vector3(8, 0, 0))
	await _frames(3)
	_check(_player.is_wall_running(), "入る")
	# 端(x=12)まで約0.4秒
	await _frames(int(0.6 / DT))
	_check(not _player.is_wall_running(), "端を過ぎたら外れる")
	_check(_player.global_position.x > 12.0, "壁の外へ出ている (x %.2f)" % _player.global_position.x)
	_check(absf(_player.horizontal_speed() - 8.0) < 0.05, "勢いを保ったまま抜ける (%.2f)" % _player.horizontal_speed())


func _test_head_on_does_not_start() -> void:
	print("正面から当たったら壁走りにしない")
	await _launch(Vector3(0, 3, 15), Vector3(0, 0, 8), 180.0)
	var ran := false
	for i in int(0.6 / DT):
		await get_tree().physics_frame
		ran = ran or _player.is_wall_running()
	_check(not ran, "壁に正面からぶつかっても入らない")


func _test_too_slow_does_not_start() -> void:
	print("遅いと入らない")
	await _launch(Vector3(-10, 3, WALL_SIDE_Z), Vector3(Tuning.wallrun_min_speed * 0.5, 0, 0))
	await _frames(10)
	_check(not _player.is_wall_running(), "最低速度未満では入らない")


func _test_stick_away_detaches() -> void:
	print("壁と反対へ倒すと離れる")
	await _launch(Vector3(-10, 3, WALL_SIDE_Z), Vector3(8, 0, 0))
	await _frames(10)
	_check(_player.is_wall_running(), "入る")
	# yaw -90度では、左(move_left)が-Z＝壁から離れる向き
	Input.action_press("move_left")
	await _frames(3)
	_check(not _player.is_wall_running(), "離れる")
	Input.action_release("move_left")


func _test_jump_into_wall() -> void:
	print("床から斜めに跳んで壁に入る")
	_release_all()
	_player.respawn()
	await _frames(30)
	# RunWallの裏側（面はz=18.5）の床で、壁から1.5m離れ、壁へ20度寄せた向きに走って跳ぶ
	_player.global_position = Vector3(-11, 0.9, 20.0)
	_player.rotation = Vector3(0, deg_to_rad(-90.0 + 20.0), 0)
	Input.action_press("move_forward")
	await _frames(int(0.5 / DT))
	var speed := _player.horizontal_speed()
	Input.action_press("jump")
	var ran := false
	for i in int(1.0 / DT):
		await get_tree().physics_frame
		if _player.is_wall_running():
			ran = true
			break
	_check(ran, "壁走りに入る")
	await _frames(int(0.2 / DT))
	_check(_player.horizontal_speed() >= speed - 0.05, "走ってきた速さを落とさない (%.2f → %.2f)" % [speed, _player.horizontal_speed()])
	_release_all()


func _test_course() -> void:
	print("コース：StartPadから壁を走ってEndPadへ")
	_release_all()
	_player.respawn()
	await _frames(30)
	_player.global_position = Vector3(-11.5, 1.9, 16.25)
	# 壁へ少し寄せて走る（実際のプレイでも壁に寄って跳ぶ）
	_player.rotation = Vector3(0, deg_to_rad(-90.0 - 8.0), 0)
	await _frames(30)
	_check(_player.is_on_floor(), "StartPadに立つ")
	Input.action_press("move_forward")
	# 足場の端(x=-3)の少し手前で跳ぶ
	while _player.global_position.x < -4.0:
		await get_tree().physics_frame
	Input.action_press("jump")
	var ran := false
	for i in int(2.5 / DT):
		await get_tree().physics_frame
		ran = ran or _player.is_wall_running()
		if ran and _player.is_on_floor():
			break
	_check(ran, "途中で壁走りした")
	var pos := _player.global_position
	_check(_player.is_on_floor() and pos.x > 3.0 and pos.y > 1.5, "EndPadに着地 (%.2f, %.2f)" % [pos.x, pos.y])
	_release_all()


func _press_jump() -> void:
	Input.action_press("jump")
	await _frames(2)


func _test_turn_around() -> void:
	print("壁走り中の方向転換")
	await _launch(Vector3(-2, 3, WALL_SIDE_Z), Vector3(8, 0, 0))
	await _frames(3)
	_check(_player.is_wall_running(), "入る")
	# yaw -90度では、後ろ(move_back)が-X＝進む向きと逆
	Input.action_press("move_back")
	var reversed := false
	for i in int(0.8 / DT):
		await get_tree().physics_frame
		if _player.velocity.x < -7.9:
			reversed = true
			break
	Input.action_release("move_back")
	_check(reversed, "逆へ倒すと折り返す")
	_check(_player.is_wall_running(), "折り返しても壁走りが続く")
	_check(absf(_player.horizontal_speed() - 8.0) < 0.1, "折り返した後は元の速さに戻る (%.2f)" % _player.horizontal_speed())


func _test_wall_jump() -> void:
	print("壁ジャンプ")
	await _launch(Vector3(-10, 3, WALL_SIDE_Z), Vector3(8, 0, 0))
	await _frames(10)
	_check(_player.is_wall_running(), "入る")
	await _press_jump()
	_check(not _player.is_wall_running(), "壁から離れる")
	_check(_player.velocity.y > Tuning.wall_jump_up * 0.9, "上へ跳ぶ (vy %.2f)" % _player.velocity.y)
	_check(_player.velocity.z < -Tuning.wall_jump_push * 0.9, "壁と反対(-Z)へ跳ぶ (vz %.2f)" % _player.velocity.z)
	_check(_player.velocity.x > 7.9, "壁沿いの勢いを保つ (vx %.2f)" % _player.velocity.x)
	Input.action_release("jump")
	await _frames(int(0.3 / DT))
	_check(not _player.is_wall_running(), "同じ壁にすぐ貼り付かない")


func _test_wall_jump_steer() -> void:
	print("スティックの向きへ壁ジャンプ")
	await _launch(Vector3(-2, 3, WALL_SIDE_Z), Vector3(8, 0, 0))
	await _frames(10)
	var before := Vector3(_player.velocity.x, 0, _player.velocity.z).length()
	# 後ろ(-X)へ倒したまま跳ぶ。折り返しが始まる前に跳ぶ
	Input.action_press("move_back")
	await _press_jump()
	var h := Vector3(_player.velocity.x, 0, _player.velocity.z)
	_check(h.x < -1.0 and h.z < 0.0, "倒した向き（後ろ）へ跳ぶ (%.2f, %.2f)" % [h.x, h.z])
	_check(h.length() >= before - 0.1, "速さを落とさない (%.2f → %.2f)" % [before, h.length()])
	_release_all()
	# 壁へ向けて倒しても、壁から離れる成分は残る
	await _launch(Vector3(-2, 3, WALL_SIDE_Z), Vector3(8, 0, 0))
	await _frames(10)
	Input.action_press("move_right") # yaw -90度では右が+Z＝壁の方
	await _press_jump()
	_check(_player.velocity.z < -0.5, "壁に向けて倒しても壁から離れる (vz %.2f)" % _player.velocity.z)
	_release_all()


func _test_wall_jump_to_opposite_wall() -> void:
	print("壁ジャンプで向かいの壁へ乗り継ぐ")
	# RunWallの裏側（面はz=18.5）とJumpWall（面はz=22.5）の間は4m。裏側の面に沿って走らせる
	await _launch(Vector3(-10, 4, 18.5 + 0.35 + 0.05), Vector3(8, 0, 0))
	await _frames(10)
	_check(_player.is_wall_running(), "入る")
	# 前と右（+Z＝向かいの壁の方）の斜めに倒して跳ぶ。真横に跳ぶと正面衝突になり壁走りしない
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await _press_jump()
	Input.action_release("jump")
	var ran := false
	for i in int(2.0 / DT):
		await get_tree().physics_frame
		if _player.is_wall_running():
			ran = true
			break
	_check(ran and _player.global_position.z > 21.0, "向かいの壁で壁走りに入る (z %.2f)" % _player.global_position.z)
	_release_all()


func _test_early_press_does_not_jump_off() -> void:
	print("壁に入る直前の押しでは跳ばない")
	# 壁を検知する距離（体の表面から0.5m）の少し外から斜めに寄せ、押してから数フレーム後、
	# 先行入力の受付時間の内側で壁に入るようにする
	await _launch(Vector3(-10, 3, WALL_SIDE_Z - 0.6), Vector3(8, 0, 3))
	Input.action_press("jump") # 入る前に押して、押しっぱなし
	await _frames(int(0.2 / DT))
	_check(_player.is_wall_running(), "壁走りが続く")
	_release_all()


func _test_wall_coyote() -> void:
	print("壁を離れた直後の壁ジャンプ")
	await _launch(Vector3(-10, 3, WALL_SIDE_Z), Vector3(8, 0, 0))
	await _frames(10)
	Input.action_press("move_left") # 壁から離れる
	await _frames(3)
	_check(not _player.is_wall_running(), "離れる")
	Input.action_release("move_left")
	await _press_jump()
	_check(_player.velocity.y > Tuning.wall_jump_up * 0.9, "離れた直後なら壁ジャンプできる (vy %.2f)" % _player.velocity.y)
	_release_all()
	await _launch(Vector3(-10, 3, WALL_SIDE_Z), Vector3(8, 0, 0))
	await _frames(10)
	Input.action_press("move_left")
	await _frames(int(Tuning.coyote_time / DT) + 6)
	Input.action_release("move_left")
	await _press_jump()
	_check(_player.velocity.y < 0.0, "時間を過ぎたら跳べない (vy %.2f)" % _player.velocity.y)
	_release_all()
