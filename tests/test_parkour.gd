extends Node
## パルクールの動き（スライディング・壁登り・左手・右手・手と脚の見た目）を自動で確かめる。実行：
##   godot --headless --path . res://tests/test_parkour.tscn
## 失敗があれば終了コード1で終わる。
## ParkourLab（x=20〜24）：VaultBox 上面y=1・z=5.6〜6.4、SlideBar 下面y=1.3・z=-0.5〜0.5、
## MantleBlock 上面y=2・z=-7.5〜-4.5、ClimbWall 上面y=4.5・z=-15.5〜-12.5。
## PoleA は(-20, 0〜4, 0)。プレイヤーは回転0で前(-Z)を向く。

var DT := 1.0 / Engine.physics_ticks_per_second

var _player: Player
var _actions: HandActions
var _hands: HandsView
var _legs: LegsView
var _failures := 0


func _ready() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	_player = scene.get_node("Player")
	_actions = scene.get_node("Player/HandActions")
	_hands = scene.get_node("Player/Head/Camera3D/Hands")
	_legs = scene.get_node("Player/Legs")
	_run.call_deferred()


func _run() -> void:
	await _test_slide()
	await _test_slide_boost_cooldown()
	await _test_slide_jump_keeps_speed()
	await _test_slide_hop()
	await _test_overspeed_landing()
	await _test_slide_under_bar()
	await _test_wall_climb()
	await _test_climb_and_grab()
	await _test_ledge_from_jump()
	await _test_vault()
	await _test_wall_push_from_wallrun()
	await _test_wall_push_on_ground()
	await _test_pole_swing()
	await _test_whiff()
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
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "crouch", "hand_left", "hand_right"]:
		Input.action_release(action)


## 床に立たせて、yaw（度）の向きにする。
func _stand(pos: Vector3, yaw := 0.0) -> void:
	_release_all()
	_player.respawn()
	await _frames(5)
	_player.global_position = pos
	_player.rotation = Vector3(0, deg_to_rad(yaw), 0)
	_player.velocity = Vector3.ZERO
	await _frames(40)


## ボタンを一度押して離す。
func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


func _run_until_z(z: float, max_sec := 3.0) -> void:
	Input.action_press("move_forward")
	var limit := int(max_sec / DT)
	while _player.global_position.z > z and limit > 0:
		limit -= 1
		await get_tree().physics_frame


func _test_slide() -> void:
	print("スライディング")
	await _stand(Vector3(0, 0.9, 8))
	Input.action_press("move_forward")
	await _frames(int(0.6 / DT))
	var before := _player.horizontal_speed()
	Input.action_press("crouch")
	await _frames(3)
	_check(_player.is_sliding(), "走ってしゃがむとスライディングに入る")
	_check(_player.horizontal_speed() > before + Tuning.slide_boost * 0.8, "加速する (%.2f → %.2f)" % [before, _player.horizontal_speed()])
	await _frames(int(0.2 / DT))
	_check(_player.get_node("Head").position.y < Player.HEAD_HEIGHT - 0.4, "目線が下がる (%.2f)" % _player.get_node("Head").position.y)
	_check(_legs._legs[1].hip_a > 50.0, "前の脚を伸ばす (%.0f 度)" % _legs._legs[1].hip_a)
	var mid := _player.horizontal_speed()
	await _frames(int(0.3 / DT))
	_check(_player.horizontal_speed() < mid, "少しずつ減速する (%.2f → %.2f)" % [mid, _player.horizontal_speed()])
	Input.action_release("crouch")
	Input.action_release("move_forward")
	await _frames(int(0.5 / DT))
	_check(not _player.is_sliding() and not _player.is_crouching(), "離すと立つ")


func _test_slide_boost_cooldown() -> void:
	print("スライディングの加速は連打で重ならない")
	await _stand(Vector3(0, 0.9, 8))
	Input.action_press("move_forward")
	await _frames(int(0.6 / DT))
	await _tap("crouch")
	await _frames(int(Tuning.slide_min_time / DT) + 5)
	_check(not _player.is_sliding(), "離せば最短時間で終わる")
	var before := _player.horizontal_speed()
	await _tap("crouch")
	await _frames(2)
	_check(_player.is_sliding(), "すぐもう一度入れる")
	_check(_player.horizontal_speed() <= before + 0.1, "待ち時間の間は加速しない (%.2f → %.2f)" % [before, _player.horizontal_speed()])
	_release_all()


func _test_slide_jump_keeps_speed() -> void:
	print("スライドジャンプ")
	await _stand(Vector3(0, 0.9, 8))
	Input.action_press("move_forward")
	await _frames(int(0.6 / DT))
	Input.action_press("crouch")
	await _frames(int(0.1 / DT))
	var speed := _player.horizontal_speed()
	Input.action_press("jump")
	await _frames(3)
	_check(not _player.is_on_floor() and not _player.is_sliding(), "跳ぶとスライディングが終わる")
	await _frames(int(0.3 / DT))
	_check(_player.horizontal_speed() >= speed - 0.1, "速さを空中へ持ち出す (%.2f → %.2f)" % [speed, _player.horizontal_speed()])
	_release_all()


func _test_slide_hop() -> void:
	print("空中でしゃがみを押すと、着地でスライディング")
	await _stand(Vector3(0, 0.9, 8))
	_player.global_position = Vector3(0, 1.6, 8)
	_player.velocity = Vector3(0, 0, -10)
	await _frames(1)
	_player.velocity = Vector3(0, 0, -10)
	Input.action_press("move_forward")
	await _tap("crouch")
	Input.action_press("crouch")
	var slid := false
	for i in int(1.0 / DT):
		await get_tree().physics_frame
		if _player.is_on_floor():
			await _frames(2)
			slid = _player.is_sliding()
			break
	_check(slid, "着地した瞬間にスライディングへ入る")
	_check(_player.horizontal_speed() > 9.5, "勢いを落とさない (%.2f)" % _player.horizontal_speed())
	_release_all()


func _test_overspeed_landing() -> void:
	print("最高速度を超えて着地しても、走り続ければ一気には落ちない")
	await _stand(Vector3(0, 0.9, 8))
	_player.global_position = Vector3(0, 1.2, 8)
	_player.velocity = Vector3(0, 0, -12)
	await _frames(1)
	_player.velocity = Vector3(0, 0, -12)
	Input.action_press("move_forward")
	while not _player.is_on_floor():
		await get_tree().physics_frame
	await _frames(int(0.25 / DT))
	_check(_player.horizontal_speed() > 10.5, "0.25秒後も10.5 m/s以上 (%.2f)" % _player.horizontal_speed())
	await _frames(int(1.5 / DT))
	_check(absf(_player.horizontal_speed() - Tuning.max_speed) < 0.2, "やがて最高速度に戻る (%.2f)" % _player.horizontal_speed())
	_release_all()


func _test_slide_under_bar() -> void:
	print("低いバーの下をスライディングでくぐる")
	await _stand(Vector3(22, 0.9, 4))
	await _run_until_z(0.8, 1.5)
	await _frames(int(0.4 / DT))
	_check(_player.global_position.z > 0.4, "立ったままでは通れない (z %.2f)" % _player.global_position.z)
	await _stand(Vector3(22, 0.9, 4.5))
	await _run_until_z(2.0)
	Input.action_press("crouch")
	var under_crouched := false
	for i in int(1.0 / DT):
		await get_tree().physics_frame
		if absf(_player.global_position.z) < 0.3:
			Input.action_release("crouch") # バーの下で離しても立ち上がらない
			under_crouched = _player.is_crouching()
		if _player.global_position.z < -1.5:
			break
	_check(under_crouched, "バーの下では離しても立たない")
	_check(_player.global_position.z < -1.5, "くぐり抜ける (z %.2f)" % _player.global_position.z)
	_release_all()


## ClimbWall の手前から走って跳び、壁を登る。hand があれば左手を押しっぱなしにする。最高の足の高さを返す。
func _climb(hand: bool) -> float:
	await _stand(Vector3(22, 0.9, -8.5))
	if hand:
		Input.action_press("hand_left")
	await _run_until_z(-11.0)
	Input.action_press("jump")
	var top := 0.0
	var climbed := false
	for i in int(2.0 / DT):
		await get_tree().physics_frame
		climbed = climbed or _player.is_climbing()
		top = maxf(top, _player.feet_position().y)
		if i > 30 and _player.is_on_floor():
			break
	_check(climbed, "壁に正面から跳ぶと登る")
	return top


func _test_wall_climb() -> void:
	print("壁登り")
	var top := await _climb(false)
	_check(top > 2.4, "2.4m以上登る (%.2f m)" % top)
	_check(_player.feet_position().y < 0.2, "手を使わなければ4.5mの壁は越えられない")
	_release_all()


func _test_climb_and_grab() -> void:
	print("壁登り＋左手で縁を掴んで上に乗る")
	await _climb(true)
	_check(_actions.last_left == "ledge", "縁を掴む")
	_check(absf(_player.feet_position().y - 4.5) < 0.1 and _player.global_position.z < -12.6, "壁の上に立つ (足 %.2f, z %.2f)" % [_player.feet_position().y, _player.global_position.z])
	_release_all()


func _test_ledge_from_jump() -> void:
	print("跳んで左手で縁を掴む（左手は押しっぱなしでよい）")
	await _stand(Vector3(22, 0.9, -1.5))
	Input.action_press("hand_left")
	await _run_until_z(-3.0)
	var speed := _player.horizontal_speed()
	Input.action_press("jump")
	var grabbed := false
	var hand_near := false
	for i in int(1.0 / DT):
		await get_tree().physics_frame
		if _actions.move == HandActions.Move.MANTLE:
			grabbed = true
			await _frames(int(0.08 / DT))
			var plant := _actions.plant(HandActions.Side.LEFT)
			hand_near = not plant.is_empty() and _hands.hand_position(HandActions.Side.LEFT).distance_to(plant.point) < 0.25
			break
	_check(grabbed, "縁を掴む")
	_check(hand_near, "左手が縁に届いている")
	while _actions.is_busy():
		await get_tree().physics_frame
	_check(_player.global_position.z < -4.6 and _player.feet_position().y > 1.95, "上に乗る (z %.2f, 足 %.2f)" % [_player.global_position.z, _player.feet_position().y])
	_check(_player.horizontal_speed() >= minf(speed * Tuning.mantle_keep, Tuning.max_speed) - 0.3, "速さを持ち出す (%.2f → %.2f)" % [speed, _player.horizontal_speed()])
	_release_all()


func _test_vault() -> void:
	print("右手でボールト")
	await _stand(Vector3(22, 0.9, 11))
	await _run_until_z(7.3)
	var speed := _player.horizontal_speed()
	await _tap("hand_right")
	_check(_actions.last_right == "vault", "低い障害物に手をついて越える")
	while _actions.is_busy():
		await get_tree().physics_frame
	_check(_player.global_position.z < 5.4, "向こう側へ出る (z %.2f)" % _player.global_position.z)
	_check(_player.horizontal_speed() > speed + Tuning.vault_boost * 0.7, "加速する (%.2f → %.2f)" % [speed, _player.horizontal_speed()])
	_release_all()


func _launch_wallrun() -> void:
	_release_all()
	_player.respawn()
	await _frames(30)
	_player.rotation = Vector3(0, deg_to_rad(-90.0), 0)
	_player.global_position = Vector3(-10, 3, 17.5 - 0.4)
	_player.velocity = Vector3.ZERO
	await _frames(1)
	_player.velocity = Vector3(8, 0, 0)
	await _frames(10)


func _test_wall_push_from_wallrun() -> void:
	print("壁走り中に右手で壁を押す")
	await _launch_wallrun()
	_check(_player.is_wall_running(), "壁走り中")
	await _tap("hand_right")
	_check(_actions.last_right == "push", "壁を押す")
	_check(not _player.is_wall_running(), "壁から離れる")
	_check(_player.velocity.z < -Tuning.wall_push_speed * 0.9, "壁と反対へ飛ぶ (vz %.2f)" % _player.velocity.z)
	_check(_player.velocity.x > 7.5, "壁沿いの勢いは保つ (vx %.2f)" % _player.velocity.x)
	_check(_player.velocity.y > 0.0, "少し上へ (vy %.2f)" % _player.velocity.y)
	await _frames(2)
	await _tap("hand_right")
	_check(_actions.last_right == "whiff", "同じ壁は着地するまで押せない")
	_release_all()


func _test_wall_push_on_ground() -> void:
	print("地上で横の壁を押す")
	await _stand(Vector3(-5, 0.9, 17.5 - 0.5), -90.0)
	await _tap("hand_right")
	_check(_actions.last_right == "push", "壁を押す")
	_check(_player.velocity.z < -Tuning.wall_push_speed * 0.9, "壁から離れる (vz %.2f)" % _player.velocity.z)
	_release_all()


func _test_pole_swing() -> void:
	print("左手でポールを掴んで回る")
	await _stand(Vector3(-19.4, 0.9, 7))
	Input.action_press("move_forward")
	await _frames(int(0.6 / DT))
	Input.action_press("hand_left")
	var yaw0 := _player.rotation.y
	var speed := 0.0
	var grabbed := false
	for i in int(1.5 / DT):
		await get_tree().physics_frame
		if _actions.move == HandActions.Move.POLE:
			grabbed = true
			speed = _actions._pole_speed
			break
	_check(grabbed, "近くを通るとポールを掴む")
	if not grabbed:
		_release_all()
		return
	await _frames(int(0.25 / DT))
	var pole := Vector3(-20, 0, 0)
	var hand := _hands.hand_position(HandActions.Side.LEFT)
	_check(Vector2(hand.x - pole.x, hand.z - pole.z).length() < 0.35, "左手がポールを握っている (%.2f m)" % Vector2(hand.x - pole.x, hand.z - pole.z).length())
	var d := Vector2(_player.global_position.x - pole.x, _player.global_position.z - pole.z).length()
	_check(absf(d - Tuning.pole_radius) < 0.15, "ポールの周りを回る (半径 %.2f)" % d)
	_check(absf(wrapf(_player.rotation.y - yaw0, -PI, PI)) > deg_to_rad(45.0), "視点もついて回る (%.0f 度)" % rad_to_deg(absf(wrapf(_player.rotation.y - yaw0, -PI, PI))))
	Input.action_release("hand_left")
	await _frames(2)
	_check(not _actions.is_busy(), "離すと手を放す")
	_check(_player.horizontal_speed() > speed + Tuning.pole_release_boost * 0.8, "加速して飛び出す (%.2f → %.2f)" % [speed, _player.horizontal_speed()])
	_check(_player.velocity.y > 0.0, "少し上へ (vy %.2f)" % _player.velocity.y)
	_release_all()


func _test_whiff() -> void:
	print("何もないところでは空振り")
	await _stand(Vector3(0, 0.9, 8))
	await _tap("hand_left")
	_check(_actions.last_left == "whiff" and not _actions.is_busy(), "左手は空振り")
	_check(not _actions.plant(HandActions.Side.LEFT).is_empty(), "手を伸ばす")
	await _tap("hand_right")
	_check(_actions.last_right == "whiff" and not _actions.is_busy(), "右手は空振り")
	await _frames(int(0.5 / DT))
	_check(_actions.plant(HandActions.Side.LEFT).is_empty(), "手が戻る")
	_check(_player.horizontal_speed() < 0.01, "体は動かない")
