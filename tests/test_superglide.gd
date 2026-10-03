extends Node
## スーパーグライドを自動で確かめる。実行：
##   godot --headless --path . res://tests/test_superglide.tscn
## 失敗があれば終了コード1で終わる。
## よじ登りは N_Right の屋上（y=-2）にある小屋 Hut_NRight（z=-50〜-44、上面0.4、高さ2.4m）で行う。

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
	await _test_jump_then_slide()
	await _test_slide_then_jump()
	await _test_after_climb()
	await _test_gap_too_long()
	await _test_too_early()
	await _test_jump_only()
	await _test_no_window_without_mantle()
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


## 小屋の前に立ち、前へ倒して跳び、よじ登りが始まるまで待つ。始まればtrue
func _start_mantle() -> bool:
	_release_all()
	_player.respawn()
	await _frames(2)
	_player.global_position = Vector3(15, -1.1, -42.5)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await _frames(int(0.4 / DT))
	_last_tech = ""
	Input.action_press("move_forward")
	await _frames(int(0.15 / DT))
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	for i in int(1.0 / DT):
		if _player.ledge_kind() == "mantle":
			return true
		await get_tree().physics_frame
	return false


func _wait_window() -> bool:
	for i in int(1.0 / DT):
		if _player.superglide_window():
			return true
		await get_tree().physics_frame
	return false


## 着地まで待ち、スライディングに入ったか
func _lands_sliding() -> bool:
	for i in int(2.0 / DT):
		await get_tree().physics_frame
		if _player.is_on_floor():
			await _frames(2)
			return _player.is_sliding()
	return false


func _test_jump_then_slide() -> void:
	print("スーパーグライド（ジャンプ → しゃがみ）")
	_check(await _start_mantle(), "小屋へよじ登り始める")
	_check(await _wait_window(), "縁を越える頃に受付が開く")
	_check(_hud.get_node("CenterDot").color.g > 0.95 and _hud.get_node("CenterDot").color.r < 0.5, "受付中は照準の点が緑")
	Input.action_press("jump")
	await _frames(2) # 1フレーム遅れてしゃがむ
	Input.action_press("slide")
	await _frames(2)
	var h := _player.horizontal_speed()
	_check(_player.ledge_kind() == "", "よじ登りを切り上げる")
	_check(absf(h - Tuning.superglide_speed) < 0.05, "スーパーグライドの速さで飛ぶ (%.2f m/s)" % h)
	_check(_player.velocity.y > 0.0 and _player.velocity.y <= Tuning.superglide_up + 0.01, "低く飛ぶ (vy %.2f)" % _player.velocity.y)
	_check(_last_success and _last_tech.begins_with("スーパーグライド"), "成功と間の長さを出す（%s）" % _last_tech)
	_check(_hud.last_text() == _last_tech, "HUDに表示する")
	_check(not _player.superglide_window(), "決まったら受付を閉じる")
	_release_all()
	Input.action_press("move_forward")
	_check(await _lands_sliding(), "押し直さなくても着地でスライディングに入る")
	_release_all()


func _test_slide_then_jump() -> void:
	print("スーパーグライド（しゃがみ → ジャンプ）")
	_check(await _start_mantle(), "よじ登り始める")
	_check(await _wait_window(), "受付が開く")
	Input.action_press("slide")
	await _frames(2)
	Input.action_press("jump")
	await _frames(2)
	_check(absf(_player.horizontal_speed() - Tuning.superglide_speed) < 0.05, "しゃがみが先でも決まる (%.2f m/s)" % _player.horizontal_speed())
	_release_all()
	await _frames(int(1.0 / DT))


func _test_after_climb() -> void:
	print("登り切った直後")
	_check(await _start_mantle(), "よじ登り始める")
	while _player.ledge_kind() != "":
		await get_tree().physics_frame
	_check(_player.superglide_window(), "登り切った直後も受付中")
	Input.action_press("jump")
	await _frames(2)
	Input.action_press("slide")
	await _frames(2)
	_check(absf(_player.horizontal_speed() - Tuning.superglide_speed) < 0.05, "決まる (%.2f m/s)" % _player.horizontal_speed())
	_release_all()
	await _frames(int(1.0 / DT))


func _test_gap_too_long() -> void:
	print("ジャンプとしゃがみの間が長すぎる")
	_check(await _start_mantle(), "よじ登り始める")
	_check(await _wait_window(), "受付が開く")
	Input.action_press("jump")
	await _frames(int((Tuning.superglide_gap + 0.05) / DT))
	Input.action_press("slide")
	await _frames(2)
	_check(_player.horizontal_speed() < Tuning.superglide_speed - 1.0, "スーパーグライドにならない (%.2f m/s)" % _player.horizontal_speed())
	_check(not _last_success and _last_tech.contains("遅い"), "しゃがみが遅いと出す（%s）" % _last_tech)
	_release_all()
	await _frames(int(1.0 / DT))


func _test_too_early() -> void:
	print("早すぎる")
	_check(await _start_mantle(), "よじ登り始める")
	Input.action_press("jump")
	await _frames(2)
	Input.action_press("slide")
	await _frames(2)
	_check(_player.ledge_kind() == "mantle", "体を持ち上げている間は何も起きない")
	_check(not _last_success and _last_tech.begins_with("早すぎ"), "早すぎと出す（%s）" % _last_tech)
	_release_all()
	Input.action_press("move_forward")
	while _player.ledge_kind() != "":
		await get_tree().physics_frame
	await _frames(int(0.2 / DT))
	_check(_player.horizontal_speed() < Tuning.superglide_speed - 1.0, "スーパーグライドにならない (%.2f m/s)" % _player.horizontal_speed())
	_release_all()


func _test_jump_only() -> void:
	print("ジャンプだけ")
	_check(await _start_mantle(), "よじ登り始める")
	_check(await _wait_window(), "受付が開く")
	Input.action_press("jump")
	var jumped := false
	for i in int(0.6 / DT):
		await get_tree().physics_frame
		if _player.ledge_kind() == "" and _player.velocity.y > Tuning.jump_velocity * 0.8:
			jumped = true
			break
	_check(jumped, "登り切ってから普通に跳ぶ")
	var vy := _player.velocity.y
	Input.action_release("jump")
	await _frames(int(0.1 / DT))
	Input.action_press("jump")
	await _frames(2)
	_check(_player.velocity.y < vy, "空中でもう一度は跳ばない")
	_release_all()
	await _frames(int(1.0 / DT))


func _test_no_window_without_mantle() -> void:
	print("よじ登りでなければ出ない")
	_release_all()
	_player.respawn()
	await _frames(30)
	Input.action_press("move_forward")
	await _frames(int(0.5 / DT))
	Input.action_press("jump")
	await _frames(1)
	Input.action_press("slide")
	await _frames(2)
	_check(_player.horizontal_speed() < Tuning.superglide_speed - 1.0, "平らな所でジャンプ＋しゃがみをしても速くならない (%.2f)" % _player.horizontal_speed())
	_release_all()
