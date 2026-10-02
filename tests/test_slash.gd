extends Node
## M4のアナログ斬りを自動で確かめる。実行：
##   godot --headless --path . res://tests/test_slash.tscn
## 失敗があれば終了コード1で終わる。
## ダミーは(-5, 0, 4)。プレイヤーは回転0で前(-Z)を向く。

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
	await _test_mode_stops_camera()
	await _test_flick_hits()
	await _test_slow_push_does_nothing()
	await _test_direction()
	await _test_strength()
	await _test_rearm()
	await _test_speed_still_counts()
	await _test_mouse_flick()
	await _test_flick_buffer()
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
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "attack", "inspect",
			"slash_mode", "look_left", "look_right", "look_up", "look_down"]:
		Input.action_release(action)


## ダミーの手前distメートルに立たせ、ダミーの方を向かせる。揺れが収まるまで待つ。
func _stand(dist: float) -> void:
	_release_all()
	_player.respawn()
	_player.global_position = _dummy.global_position + Vector3(0, 0.9, dist)
	_player.rotation = Vector3.ZERO
	await _frames(int(2.0 / DT))


## 右スティックを、v（右が+x、下が+y）の向きへ、framesフレームかけて中心から端まで倒す。
func _stick(v: Vector2) -> void:
	Input.action_release("look_left")
	Input.action_release("look_right")
	Input.action_release("look_up")
	Input.action_release("look_down")
	if v.x < 0.0:
		Input.action_press("look_left", -v.x)
	elif v.x > 0.0:
		Input.action_press("look_right", v.x)
	if v.y < 0.0:
		Input.action_press("look_up", -v.y)
	elif v.y > 0.0:
		Input.action_press("look_down", v.y)


func _flick(to: Vector2, frames: int) -> void:
	_stick(Vector2.ZERO)
	await _frames(2)
	for i in frames:
		_stick(to * float(i + 1) / frames)
		await _frames(1)
	await _frames(2)
	_stick(Vector2.ZERO)


## 斬撃モードで弾き、当たるまで（最大max_sec）待つ。当たった瞬間の威力を返す（当たらなければ-1）。
func _slash_and_wait_hit(to: Vector2, frames: int, max_sec := 0.6) -> float:
	var count := _dummy.hit_count
	Input.action_press("slash_mode")
	await _frames(2)
	await _flick(to, frames)
	var start := Time.get_ticks_msec()
	while _dummy.hit_count == count and Time.get_ticks_msec() - start < max_sec * 1000.0:
		await get_tree().process_frame
	var power := HitFeel.last_power if _dummy.hit_count != count else -1.0
	while Engine.time_scale == 0.0:
		await get_tree().process_frame
	Input.action_release("slash_mode")
	await _frames(int(0.5 / DT))
	return power


func _test_mode_stops_camera() -> void:
	print("斬撃モードでは右スティックで視点が動かない")
	await _stand(6.0)
	var yaw := _player.rotation.y
	_stick(Vector2(1, 0))
	await _frames(int(0.2 / DT))
	_check(absf(_player.rotation.y - yaw) > 0.1, "ふだんは右スティックで視点が回る")
	# 倒したままRTを押す
	Input.action_press("slash_mode")
	await _frames(1)
	_player.rotation = Vector3.ZERO
	await _frames(int(0.2 / DT))
	_check(absf(_player.rotation.y) < 0.001, "RTを押している間は視点が回らない")
	_check(_weapon.slash_stick().x > 0.9, "スティックの位置は斬撃に使う (%.2f)" % _weapon.slash_stick().x)
	_check(_weapon.slash_count == 0, "倒したまま入っても斬らない（中心に戻すまで）")
	_release_all()
	await _frames(int(0.3 / DT))


func _test_flick_hits() -> void:
	print("弾くとアナログ斬りが出て当たる")
	await _stand(1.3)
	var before := _weapon.slash_count
	var power := await _slash_and_wait_hit(Vector2(-1, 0), 3)
	_check(_weapon.slash_count - before == 1, "1回弾いて1回斬る (%d)" % (_weapon.slash_count - before))
	_check(power > 0.0, "目の前のダミーに当たる (威力 %.2f)" % power)


func _test_slow_push_does_nothing() -> void:
	print("ゆっくり倒しても斬らない")
	await _stand(1.3)
	var before := _weapon.slash_count
	Input.action_press("slash_mode")
	await _frames(2)
	await _flick(Vector2(-1, 0), int(0.5 / DT))
	await _frames(int(0.3 / DT))
	_check(_weapon.slash_count == before, "受付時間より遅い倒しは弾きではない")
	_release_all()


func _test_direction() -> void:
	print("弾いた向きが斬る向き")
	var cases := [
		[Vector2(-1, 0), Vector2(-1, 0), 0.0, "左へ弾くと右から左へ水平に斬る"],
		[Vector2(1, 0), Vector2(1, 0), 0.0, "右へ弾くと左から右へ水平に斬る"],
		[Vector2(0, 1), Vector2(0, -1), PI / 2, "下へ弾くと振り下ろす（振りの面を90度傾ける）"],
		[Vector2(-0.7, -0.7), Vector2(-0.707, 0.707), -PI / 4, "左上へ弾くと右下から左上へ斬り上げる"],
	]
	for c in cases:
		await _stand(6.0)
		Input.action_press("slash_mode")
		await _frames(2)
		await _flick(c[0], 3)
		var s := _weapon.last_slash
		var ok: bool = not s.is_empty() and s.dir.distance_to(c[1]) < 0.05 and absf(angle_difference(s.roll, c[2])) < 0.05
		_check(ok, "%s (向き %s, 傾き %.0f 度)" % [c[3], str(s.get("dir")), rad_to_deg(s.get("roll", 0.0))])
		await _frames(int(0.4 / DT))
		_release_all()
	# 振っている途中は振りの面が傾いている：振り下ろしでは刃先が下へ動く
	await _stand(6.0)
	Input.action_press("slash_mode")
	await _frames(2)
	_flick(Vector2(0, 1), 3)
	var ys := []
	for i in int(0.25 / DT):
		await get_tree().physics_frame
		if _weapon.state == Weapon.State.ACTIVE:
			ys.append(_weapon.hitbox_transform().origin.y)
	_check(ys.size() > 2 and ys[-1] < ys[0] - 0.2, "振り下ろしでは判定の箱が上から下へ動く (%.2f m)" % ((ys[0] - ys[-1]) if ys.size() > 1 else 0.0))
	_release_all()
	await _frames(int(0.4 / DT))


func _test_strength() -> void:
	print("速く弾くほど強い")
	await _stand(1.3)
	var weak := await _slash_and_wait_hit(Vector2(-1, 0), 14) # 約0.12秒かけて倒す
	await _stand(1.3)
	var strong := await _slash_and_wait_hit(Vector2(-1, 0), 2)
	_check(weak > 0.0 and strong > 0.0, "どちらも当たる (%.2f / %.2f)" % [weak, strong])
	_check(strong > weak + 0.3, "速い弾きのほうが威力が高い (%.2f > %.2f)" % [strong, weak])
	_check(absf(strong - Tuning.slash_power_max) < 0.01, "止まって最速で弾けば威力は強い弾きの基本威力 (%.2f)" % strong)


func _test_rearm() -> void:
	print("中心へ戻すまで次は出ない")
	await _stand(6.0)
	var before := _weapon.slash_count
	Input.action_press("slash_mode")
	await _frames(2)
	_stick(Vector2.ZERO)
	await _frames(2)
	_stick(Vector2(-1, 0))
	await _frames(2)
	_stick(Vector2(0, 1)) # 端のまま回しても出ない
	await _frames(2)
	_stick(Vector2(1, 0))
	await _frames(int(0.6 / DT))
	_check(_weapon.slash_count - before == 1, "端を回しても1回だけ (%d)" % (_weapon.slash_count - before))
	_release_all()
	await _frames(int(0.3 / DT))


func _test_speed_still_counts() -> void:
	print("走ってきた勢いも威力になる")
	await _stand(8.0)
	Input.action_press("move_forward")
	while _player.global_position.z - _dummy.global_position.z > 2.4:
		await get_tree().physics_frame
	var power := await _slash_and_wait_hit(Vector2(-1, 0), 2)
	_check(power > Tuning.slash_power_max * 1.8, "最高速度で強く弾けば威力はほぼ2倍 (%.2f)" % power)
	_release_all()


func _test_mouse_flick() -> void:
	print("右クリックを押しながらマウスを素早く動かしても斬れる")
	await _stand(6.0)
	var before := _weapon.slash_count
	var yaw := _player.rotation.y
	Input.action_press("slash_mode")
	await _frames(4)
	for i in 3:
		var m := InputEventMouseMotion.new()
		m.relative = Vector2(0, Tuning.slash_mouse_px * 0.4)
		Input.parse_input_event(m)
		await _frames(1)
	await _frames(2)
	_check(_weapon.slash_count - before == 1, "マウスの弾きで斬る (%d)" % (_weapon.slash_count - before))
	_check(not _weapon.last_slash.is_empty() and _weapon.last_slash.dir.y < -0.9, "下へ動かすと振り下ろす")
	_check(absf(_player.rotation.y - yaw) < 0.001, "その間は視点が動かない")
	_release_all()
	await _frames(int(0.5 / DT))


func _test_flick_buffer() -> void:
	print("通常攻撃の途中で弾いても出る（先行入力）")
	await _stand(6.0)
	var before := _weapon.slash_count
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	Input.action_press("slash_mode")
	await _frames(int((Tuning.attack_windup + Tuning.attack_active) / DT))
	_check(_weapon.is_attacking() and not _weapon.is_slashing(), "通常攻撃の途中")
	await _flick(Vector2(-1, 0), 2)
	await _frames(int(0.3 / DT))
	_check(_weapon.slash_count - before == 1, "振り終わりにアナログ斬りが出る (%d)" % (_weapon.slash_count - before))
	_release_all()
