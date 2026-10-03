extends Node
## M5のパルクール（スライディング・乗り越え・よじ登り・左手）と街を自動で確かめる。実行：
##   godot --headless --path . res://tests/test_parkour.tscn
## 失敗があれば終了コード1で終わる。
## 座標は scripts/city.gd の表を参照。屋上（ホーム）の上面は y=0、路地の底は y=-6。

var DT := 1.0 / Engine.physics_ticks_per_second

var _player: Player
var _hand: LeftHand
var _failures := 0


func _ready() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	_player = scene.get_node("Player")
	_hand = scene.get_node("Player/Head/Camera3D/LeftHand")
	_run.call_deferred()


func _run() -> void:
	await _test_city()
	await _test_slide()
	await _test_slide_needs_speed()
	await _test_slide_jump()
	await _test_pipe_blocks_standing()
	await _test_slide_under_pipe_and_duct()
	await _test_slide_ramp()
	await _test_vault()
	await _test_mantle()
	await _test_no_mantle_from_ground()
	await _test_wallrun_mantle()
	await _test_left_hand_on_wall()
	await _test_climb_out_of_alley()
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
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "slide"]:
		Input.action_release(action)


## 床に立たせる。yaw 0で前が-Z、90で-X、180で+Z、-90で+X。
func _stand(pos: Vector3, yaw_deg: float) -> void:
	_release_all()
	_player.respawn()
	await _frames(2)
	_player.global_position = pos
	_player.rotation = Vector3(0, deg_to_rad(yaw_deg), 0)
	_player.velocity = Vector3.ZERO
	await _frames(int(0.4 / DT))


## 空中に置いて速度を与える（test_wallrun と同じ手順）。
func _launch(pos: Vector3, vel: Vector3, yaw_deg: float) -> void:
	_release_all()
	_player.respawn()
	await _frames(30)
	_player.rotation = Vector3(0, deg_to_rad(yaw_deg), 0)
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	await _frames(1)
	_player.velocity = vel


func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


func _feet() -> float:
	return _player.global_position.y - 0.9


func _test_city() -> void:
	print("街")
	var city := _player.get_parent().get_node("City")
	var blocks := 0
	for b in City.BLOCKS:
		var body := city.get_node_or_null(NodePath(b[0])) as StaticBody3D
		if body and body.collision_layer & Player.WORLD_LAYER:
			blocks += 1
	_check(blocks == City.BLOCKS.size(), "屋上のまわりに%d棟のビル（壁走りできる層）" % blocks)
	# 屋上のまわりの路地はどれも4m幅：ホームの北の面（z=-31）から北のビル（z=-35）まで
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(-10, -3, -31.5), Vector3(-10, -3, -40))
	var hit := space.intersect_ray(q)
	_check(not hit.is_empty() and absf(hit.position.z + 35.0) < 0.01, "北の路地の幅は4m")
	q = PhysicsRayQueryParameters3D.create(Vector3(0, 10, -45), Vector3(0, -20, -45))
	hit = space.intersect_ray(q)
	_check(not hit.is_empty() and absf(hit.position.y - City.STREET_Y) < 0.01, "路地の底は y=%.0f" % City.STREET_Y)


func _test_slide() -> void:
	print("スライディング")
	await _stand(Vector3(0, 0.9, 8), 0.0)
	Input.action_press("move_forward")
	await _frames(int(0.6 / DT))
	var run_speed := _player.horizontal_speed()
	await _tap("slide")
	_check(_player.is_sliding(), "走りながら押すと滑る")
	_check(_player.horizontal_speed() >= run_speed + Tuning.slide_boost - 0.2, "始めに加速する (%.2f → %.2f)" % [run_speed, _player.horizontal_speed()])
	await _frames(int(0.25 / DT))
	_check(_player.head.position.y < 0.3, "目の高さが下がる (%.2f)" % _player.head.position.y)
	var mid := _player.horizontal_speed()
	await _frames(int(0.3 / DT))
	_check(_player.horizontal_speed() < mid - 0.5, "滑るうちに減速する (%.2f → %.2f)" % [mid, _player.horizontal_speed()])
	var frames := 0
	while _player.is_sliding() and frames < 400:
		await get_tree().physics_frame
		frames += 1
	_check(not _player.is_sliding(), "上限時間までに立ち上がる")
	await _frames(int(0.4 / DT))
	_check(_player.head.position.y > 0.7, "目の高さが戻る (%.2f)" % _player.head.position.y)
	_check(absf(_player.horizontal_speed() - Tuning.max_speed) < 0.1, "そのまま走りに戻る (%.2f)" % _player.horizontal_speed())
	_release_all()


func _test_slide_needs_speed() -> void:
	print("止まっていると滑らない")
	await _stand(Vector3(0, 0.9, 8), 0.0)
	await _tap("slide")
	await _frames(2)
	_check(not _player.is_sliding(), "最低速度未満では滑らない")


func _test_slide_jump() -> void:
	print("スライディングジャンプ")
	await _stand(Vector3(0, 0.9, 8), 0.0)
	Input.action_press("move_forward")
	await _frames(int(0.6 / DT))
	await _tap("slide")
	await _frames(int(0.1 / DT))
	var speed := _player.horizontal_speed()
	Input.action_release("move_forward")
	await _tap("jump")
	_check(not _player.is_sliding() and _player.velocity.y > 0.0, "滑りながら跳べる")
	_check(_player.horizontal_speed() >= speed - 0.3, "速さを落とさない (%.2f → %.2f)" % [speed, _player.horizontal_speed()])
	_release_all()
	await _frames(int(1.0 / DT))


## W_Bottom の練習コース：坂(z=2〜14) → パイプ(z=18、下端1.1m) → ダクト(z=21〜27、下端1.15m) → 柵(z=29、高さ1m)。
func _test_pipe_blocks_standing() -> void:
	print("立ったままではパイプをくぐれない")
	await _stand(Vector3(-54, 0.9, 15), 180.0)
	Input.action_press("move_forward")
	await _frames(int(1.0 / DT))
	_check(_player.global_position.z < 18.0, "パイプの手前で止まる (z %.2f)" % _player.global_position.z)
	_release_all()


func _test_slide_under_pipe_and_duct() -> void:
	print("スライディングでパイプとダクトをくぐる")
	await _stand(Vector3(-54, 0.9, 14.5), 180.0)
	Input.action_press("move_forward")
	await _frames(int(0.35 / DT))
	await _tap("slide")
	_check(_player.is_sliding(), "滑り出す")
	var stood_in_duct := false
	var max_z := 0.0
	var frames := 0
	while frames < int(3.0 / DT):
		await get_tree().physics_frame
		frames += 1
		var z := _player.global_position.z
		max_z = maxf(max_z, z)
		if z > 21.3 and z < 26.7 and not _player.is_sliding():
			stood_in_duct = true
		if z > 28.0:
			break
	_check(max_z > 28.0, "パイプとダクトを抜ける (z %.2f)" % max_z)
	_check(not stood_in_duct, "ダクトの中では立ち上がらない")
	_release_all()


func _test_slide_ramp() -> void:
	print("坂を滑り降りると速くなる")
	# W_Top（上面3.5）から橋を渡って坂の上へ
	await _stand(Vector3(-54, 4.4, -6), 180.0)
	Input.action_press("move_forward")
	while _player.global_position.z < 1.5:
		await get_tree().physics_frame
	await _tap("slide")
	var top := _player.horizontal_speed()
	var frames := 0
	while _player.global_position.z < 13.5 and frames < int(3.0 / DT):
		await get_tree().physics_frame
		frames += 1
	_check(_player.is_sliding(), "坂の下まで滑り続ける")
	_check(_player.horizontal_speed() > top + 1.5, "坂で加速する (%.2f → %.2f)" % [top, _player.horizontal_speed()])
	_release_all()


func _test_vault() -> void:
	print("乗り越え（柵、高さ1m）")
	# W_Bottom の柵 Barrier1（x=-41〜-40.4）へ -X に走る
	await _stand(Vector3(-36, 0.9, 16), 90.0)
	Input.action_press("move_forward")
	await _frames(int(0.5 / DT))
	var speed := _player.horizontal_speed()
	var vaulted := false
	var hand_near := false
	var frames := 0
	while _player.global_position.x > -41.5 and frames < int(2.0 / DT):
		await get_tree().physics_frame
		frames += 1
		if _player.ledge_kind() == "vault":
			vaulted = true
			var hp := _hand.global_position
			hand_near = hand_near or (_hand.visible and absf(hp.x + 40.7) < 0.45 and absf(hp.y - 1.0) < 0.3)
	_check(vaulted, "走って当たると手をついて乗り越える")
	_check(_player.global_position.x < -41.5, "柵の向こうへ出る (x %.2f)" % _player.global_position.x)
	_check(hand_near, "左手を柵の上につく")
	_check(_player.horizontal_speed() >= speed - 0.3, "速さを落とさない (%.2f → %.2f)" % [speed, _player.horizontal_speed()])
	_release_all()


func _test_mantle() -> void:
	print("よじ登り（小屋、高さ2.4m）")
	# N_Right の屋上（y=-2）にある小屋 Hut_NRight（z=-50〜-44、上面0.4）へ -Z に跳ぶ
	await _stand(Vector3(15, -1.1, -42.5), 0.0)
	Input.action_press("move_forward")
	await _frames(int(0.15 / DT))
	await _tap("jump")
	var mantled := false
	var hooked := false
	var frames := 0
	while frames < int(1.5 / DT):
		await get_tree().physics_frame
		frames += 1
		if _player.ledge_kind() == "mantle":
			mantled = true
			hooked = hooked or (_hand.visible and _hand.kind == "mantle")
		elif mantled:
			break
	_check(mantled, "跳んで縁に手が届くとよじ登る")
	_check(hooked, "左手を縁に掛ける")
	await _frames(int(0.2 / DT))
	_check(_player.is_on_floor() and absf(_feet() - 0.4) < 0.1 and _player.global_position.z < -44.0, "小屋の上に立つ (%.2f, %.2f)" % [_feet(), _player.global_position.z])
	_release_all()


func _test_no_mantle_from_ground() -> void:
	print("地上からは高い段に登らない")
	await _stand(Vector3(15, -1.1, -42.5), 0.0)
	Input.action_press("move_forward")
	await _frames(int(0.6 / DT))
	_check(_player.ledge_kind() == "" and _feet() < -1.9, "跳ばなければ壁の前で止まる (%.2f)" % _feet())
	_release_all()


func _test_wallrun_mantle() -> void:
	print("壁走りから壁の上へ")
	# JumpWall（z=22.5〜23.5、上面5）の手前の面に沿って +X へ壁走りし、壁へ倒す
	await _launch(Vector3(-10, 4.2, 22.5 - 0.4), Vector3(8, 0, 0), -90.0)
	await _frames(6)
	_check(_player.is_wall_running(), "壁走りに入る")
	Input.action_press("move_right") # yaw -90度では右が+Z＝壁の方
	var mantled := false
	for i in int(1.0 / DT):
		await get_tree().physics_frame
		mantled = mantled or _player.ledge_kind() != ""
		if mantled and _player.ledge_kind() == "":
			break
	Input.action_release("move_right")
	await _frames(int(0.1 / DT))
	_check(mantled, "壁へ倒すとよじ登る")
	_check(absf(_feet() - 5.0) < 0.15, "壁の上に立つ (足 %.2f)" % _feet())
	_release_all()


func _test_left_hand_on_wall() -> void:
	print("壁走り中の左手")
	# RunWall の裏の面（z=18.5）を +X へ。yaw -90度では壁が左
	await _launch(Vector3(-10, 3, 18.5 + 0.4), Vector3(8, 0, 0), -90.0)
	await _frames(int(0.3 / DT))
	_check(_player.is_wall_running(), "左の壁で壁走り")
	var hp := _hand.global_position
	_check(_hand.visible and absf(hp.z - 18.5) < 0.3, "左手を壁に添える (z %.2f)" % hp.z)
	# 右の壁では左手を出さない
	await _launch(Vector3(-10, 3, 17.5 - 0.4), Vector3(8, 0, 0), -90.0)
	await _frames(int(0.3 / DT))
	_check(_player.is_wall_running(), "右の壁で壁走り")
	await _frames(int(0.3 / DT))
	_check(not _hand.visible, "右の壁には左手を伸ばさない")
	await _stand(Vector3(0, 0.9, 8), 0.0)
	_check(not _hand.visible, "何もしていないときは左手を隠す")


## 路地に落ちても、両側の壁を壁ジャンプで乗り継いで屋上へ戻れる。
## ホームの北の面（z=-31、手すりの上面1.2）と北のビル N_Left（z=-35、上面5）の間の路地を +X へ。
func _test_climb_out_of_alley() -> void:
	print("路地から壁ジャンプで屋上へ戻る")
	await _stand(Vector3(-28, City.STREET_Y + 0.9, -33), -90.0)
	Input.action_press("move_forward")
	await _frames(int(0.5 / DT))
	Input.action_press("move_left") # yaw -90度では左が-Z＝N_Left の方
	await _tap("jump")
	var jumps := 0
	var on_wall := 0
	var best := _feet()
	var mantled := false
	var frames := 0
	while frames < int(8.0 / DT):
		await get_tree().physics_frame
		frames += 1
		best = maxf(best, _feet())
		if _player.ledge_kind() != "":
			mantled = true
		if mantled and _player.ledge_kind() == "" and _player.is_on_floor():
			break
		if not _player.is_wall_running():
			on_wall = 0
			continue
		on_wall += 1
		if on_wall < 3:
			continue
		var n := _player.wall_normal()
		var home_wall := n.z < -0.5 # ホームの面は法線が-Z
		Input.action_release("move_left")
		Input.action_release("move_right")
		if home_wall and _feet() > 1.2 - Tuning.mantle_max_height + 0.1:
			Input.action_press("move_right") # 手すりに手が届くので、壁へ倒してよじ登る
			continue
		# 向かいの壁へ、前と斜めに倒して壁ジャンプ
		Input.action_press("move_left" if home_wall else "move_right")
		Input.action_release("jump")
		await get_tree().physics_frame
		Input.action_press("jump")
		jumps += 1
		on_wall = -1000 # 次に壁へ入るまで待つ
	_release_all()
	await _frames(int(0.3 / DT))
	print("       壁ジャンプ %d 回、最高の足の高さ %.2f" % [jumps, best])
	_check(jumps >= 3, "壁ジャンプを何度も乗り継ぐ (%d 回)" % jumps)
	# 手すり（上面1.2）へよじ登り、勢いのまま屋上（上面0）へ降りる
	_check(mantled and _feet() > -0.1 and _player.global_position.z > -31.0, "手すりへよじ登って屋上へ戻る (足 %.2f, z %.2f)" % [_feet(), _player.global_position.z])
