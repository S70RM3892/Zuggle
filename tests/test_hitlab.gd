extends Node
## M3のヒットラボを自動で確かめる。実行：
##   godot --headless --path . res://tests/test_hitlab.tscn
## 失敗があれば終了コード1で終わる。
## ダミーは(-5, 0, 4)、当たり判定は幅1.7・高さ1.8・奥行き1.2の箱。プレイヤーは回転0で前(-Z)を向く。

var DT := 1.0 / Engine.physics_ticks_per_second

var _player: Player
var _dummy: Dummy
var _weapon: Weapon
var _failures := 0


func _ready() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	_player = scene.get_node("Player")
	_dummy = scene.get_node("Dummy")
	_weapon = scene.get_node("Player/Head/Camera3D/Hand")
	_run.call_deferred()


func _run() -> void:
	await _test_hit_and_hitstop()
	await _test_dummy_reacts_and_returns()
	await _test_whiff()
	await _test_speed_raises_power()
	await _test_attack_buffer()
	await _test_retract_near_wall()
	await _test_no_wallrun_on_dummy()
	await _test_inspect()
	await _test_attack_cancels_inspect()
	await _test_hand_rig()
	await _test_combo()
	await _test_grip()
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
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "attack", "inspect"]:
		Input.action_release(action)


## ダミーの手前distメートルに立たせ、ダミーの方を向かせる。揺れとダミーの揺れが収まるまで待つ。
func _stand(dist: float) -> void:
	_release_all()
	_player.respawn()
	_player.global_position = _dummy.global_position + Vector3(0, 0.9, dist)
	_player.rotation = Vector3.ZERO
	await _frames(int(2.0 / DT))


## 攻撃ボタンを押し、当たるまで（最大max_sec）待つ。当たった瞬間の状態を返す。
func _attack_and_wait_hit(max_sec := 0.6) -> Dictionary:
	var count := _dummy.hit_count
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	var start := Time.get_ticks_msec()
	while _dummy.hit_count == count and Time.get_ticks_msec() - start < max_sec * 1000.0:
		await get_tree().process_frame
	if _dummy.hit_count == count:
		return {}
	var hit_at := Time.get_ticks_usec()
	var stopped := Engine.time_scale == 0.0
	while Engine.time_scale == 0.0:
		await get_tree().process_frame
	return {"stopped": stopped, "stop_ms": (Time.get_ticks_usec() - hit_at) / 1000.0, "power": HitFeel.last_power}


func _test_hit_and_hitstop() -> void:
	print("通常攻撃が当たる")
	await _stand(1.3)
	var r := await _attack_and_wait_hit()
	_check(not r.is_empty(), "目の前のダミーに当たる")
	if r.is_empty():
		return
	_check(absf(r.power - 1.0) < 0.01, "止まっていれば威力1 (%.2f)" % r.power)
	_check(r.stopped, "当たった瞬間に世界が止まる")
	var expected := Tuning.hitstop_min * 1000.0
	_check(r.stop_ms > expected - 5.0 and r.stop_ms < expected + 40.0, "ヒットストップは威力1で約%dms (%.0f ms)" % [int(expected), r.stop_ms])
	_check(_player.trauma() > 0.0, "画面揺れが入る (%.2f)" % _player.trauma())
	await _frames(int(0.6 / DT))
	_check(_dummy.hit_count == 1, "1振りで当たるのは1回だけ (%d)" % _dummy.hit_count)
	await _frames(int(1.0 / DT))
	_check(_player.trauma() == 0.0, "画面揺れは時間で収まる")


func _test_dummy_reacts_and_returns() -> void:
	print("ダミーが吹き飛び、よろけ、戻る")
	await _stand(1.3)
	var r := await _attack_and_wait_hit()
	_check(not r.is_empty(), "当たる")
	var max_back := 0.0
	var max_lean := 0.0
	for i in int(0.4 / DT):
		await get_tree().physics_frame
		max_back = maxf(max_back, -_dummy.visual_offset().z)
		max_lean = maxf(max_lean, _dummy.lean_angle())
	_check(max_back > 0.2, "斬った向き（奥）へ吹き飛ぶ (%.2f m)" % max_back)
	_check(max_lean > deg_to_rad(10.0), "よろける (%.0f 度)" % rad_to_deg(max_lean))
	await _frames(int(3.0 / DT))
	_check(_dummy.visual_offset().length() < 0.02 and _dummy.lean_angle() < 0.02, "元の位置に戻る")


func _test_whiff() -> void:
	print("空振り")
	await _stand(1.3)
	_player.rotation = Vector3(0, PI, 0) # 背を向ける
	await _frames(2)
	var count := _dummy.hit_count
	var stopped := false
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	for i in int(0.5 / DT):
		await get_tree().physics_frame
		stopped = stopped or Engine.time_scale == 0.0
	_check(_weapon.swing_count > 0 and not _weapon.is_attacking(), "振って戻る")
	_check(_dummy.hit_count == count, "当たらない")
	_check(not stopped, "ヒットストップしない")


func _test_speed_raises_power() -> void:
	print("走ってきた勢いが威力になる")
	await _stand(8.0)
	Input.action_press("move_forward")
	while _player.global_position.z - _dummy.global_position.z > 2.0:
		await get_tree().physics_frame
	var speed := _player.horizontal_speed()
	var r := await _attack_and_wait_hit()
	Input.action_release("move_forward")
	_check(not r.is_empty(), "走りながら当たる (進入 %.2f m/s)" % speed)
	if r.is_empty():
		return
	_check(r.power > 1.9, "最高速度なら威力はほぼ2 (%.2f)" % r.power)
	var expected := Tuning.hitstop_max * 1000.0
	_check(r.stop_ms > expected - 15.0, "ヒットストップが長くなる (%.0f ms)" % r.stop_ms)


func _test_attack_buffer() -> void:
	print("攻撃の先行入力")
	await _stand(6.0)
	var before := _weapon.swing_count
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	# 振り終わりの少し前（受付時間の内側）に押す
	var press_at := Tuning.attack_windup + Tuning.attack_active + Tuning.attack_recovery - Tuning.attack_buffer * 0.5
	await _frames(int(press_at / DT) - 2)
	_check(_weapon.is_attacking(), "まだ1振り目の途中")
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(int(0.1 / DT))
	_check(_weapon.swing_count - before == 2, "途中で押した分も振る (%d)" % (_weapon.swing_count - before))


func _test_retract_near_wall() -> void:
	print("壁へのめり込み")
	_release_all()
	_player.respawn()
	# 壁走り用の長い壁（南の面はz=18.5）の手前0.6m
	_player.global_position = Vector3(0, 0.9, 19.1)
	_player.rotation = Vector3.ZERO
	await _frames(int(0.5 / DT))
	_check(_weapon.retract_amount() > 0.2, "壁の前では武器を引っ込める (%.2f)" % _weapon.retract_amount())
	_player.global_position = Vector3(0, 0.9, 8)
	await _frames(int(0.5 / DT))
	_check(_weapon.retract_amount() < 0.01, "開けた場所では元に戻る (%.2f)" % _weapon.retract_amount())


func _test_no_wallrun_on_dummy() -> void:
	print("ダミーでは壁走りしない")
	_release_all()
	_player.respawn()
	await _frames(30)
	_player.global_position = _dummy.global_position + Vector3(1.25, 1.2, 2.0) # 箱の側面(x=0.85)の横
	_player.velocity = Vector3.ZERO
	await _frames(1)
	_player.velocity = Vector3(0, 0, -8)
	var ran := false
	for i in int(0.5 / DT):
		await get_tree().physics_frame
		ran = ran or _player.is_wall_running()
	_check(not ran, "ダミーの横を跳んでも入らない")


func _press(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


func _knife_angle() -> float:
	# 柄の向き(Grip の Z)が、ナイフ回しの軸まわりに握った向きからどれだけ回っているか
	var z := (_weapon.swing.global_transform.affine_inverse() * _weapon.grip.global_transform).basis.z.normalized()
	var axis := _weapon.spin_axis()
	var e1 := _weapon.grip_rest().basis.z.normalized()
	var e2 := axis.cross(e1)
	return atan2(z.dot(e2), z.dot(e1))


func _test_inspect() -> void:
	print("ナイフ回し")
	await _stand(6.0)
	var rest := _knife_angle()
	await _press("inspect")
	_check(_weapon.is_inspecting(), "Y / F で回し始める")
	var turned := 0.0
	var last := rest
	var frames := 0
	while _weapon.is_inspecting() and frames < 400:
		await get_tree().physics_frame
		frames += 1
		var a := _knife_angle()
		turned += absf(wrapf(a - last, -PI, PI))
		last = a
	var secs := frames * DT
	_check(absf(secs - Weapon.INSPECT_TIME) < 0.05, "約%.1f秒で終わる (%.2f 秒)" % [Weapon.INSPECT_TIME, secs])
	_check(absf(turned - TAU * Weapon.SPIN_TURNS) < 0.3, "%d回転する (%.1f 回転)" % [int(Weapon.SPIN_TURNS), turned / TAU])
	_check(absf(wrapf(_knife_angle() - rest, -PI, PI)) < 0.01, "握り直して元の向きに戻る")


func _test_attack_cancels_inspect() -> void:
	print("ナイフ回しの途中でも攻撃できる")
	await _stand(1.3)
	await _press("inspect")
	await _frames(int(0.3 / DT))
	_check(_weapon.is_inspecting(), "回している")
	var r := await _attack_and_wait_hit()
	_check(not r.is_empty(), "攻撃が出て当たる")
	_check(not _weapon.is_inspecting(), "ナイフ回しは止まる")


func _test_hand_rig() -> void:
	print("手の骨")
	var skel: Skeleton3D = _weapon.find_children("*", "Skeleton3D", true, false)[0]
	_check(skel.get_bone_count() == 16, "骨は16本（手のひら＋指5本×3） (%d)" % skel.get_bone_count())
	var mesh: MeshInstance3D = skel.find_children("*", "MeshInstance3D", true, false)[0]
	_check(mesh.skin != null and mesh.skin.get_bind_count() == 16, "メッシュに重みが付いている")
	await _stand(6.0)
	var idx := skel.find_bone("middle_1")
	var gripped := skel.get_bone_pose_rotation(idx).angle_to(skel.get_bone_rest(idx).basis.get_rotation_quaternion())
	_check(gripped > deg_to_rad(60.0), "構えでは指を握っている (%.0f 度)" % rad_to_deg(gripped))


func _test_combo() -> void:
	print("3連の型")
	await _stand(6.0)
	var seen: Array[int] = []
	for i in 4:
		await _press("attack")
		seen.append(_weapon.combo)
		while _weapon.is_attacking():
			await get_tree().physics_frame
		await _frames(int(0.1 / DT))
	_check(seen == [0, 1, 2, 0], "続けて振ると型が1→2→3→1と進む (%s)" % str(seen))
	await _frames(int(0.8 / DT))
	await _press("attack")
	_check(_weapon.combo == 0, "間を空けると1の型に戻る (%d)" % _weapon.combo)
	while _weapon.is_attacking():
		await get_tree().physics_frame


func _test_grip() -> void:
	print("ナイフの握り")
	await _stand(6.0)
	var skel: Skeleton3D = _weapon.find_children("*", "Skeleton3D", true, false)[0]
	var to_swing := _weapon.swing.global_transform.affine_inverse() * skel.global_transform
	var bone := func(n: String) -> Vector3: return to_swing * skel.get_bone_global_pose(skel.find_bone(n)).origin
	var rest := _weapon.grip_rest()
	var ring: Vector3 = rest * _weapon._spin_pivot
	var index_mid: Vector3 = (bone.call("index_1") + bone.call("index_2")) * 0.5
	_check(ring.distance_to(index_mid) < 0.02, "輪は人差し指の付け根の節にかかる (%.3f m)" % ring.distance_to(index_mid))
	var tip: Vector3 = rest * Vector3(0, 0, _weapon.grip_back - _weapon.model_length)
	var pinky: Vector3 = bone.call("pinky_1")
	_check(tip.y < pinky.y, "刃先は小指より下へ出る")
	var curve: Vector3 = rest.basis * _weapon._blade_dir
	_check(curve.normalized().z < -0.7, "刃は拳の前へ曲がる (%.2f)" % curve.normalized().z)
