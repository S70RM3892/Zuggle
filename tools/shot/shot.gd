extends Node
## 見た目を確かめるためのスクリーンショット。ウィンドウが要るので xvfb-run で動かす（tools/dev.sh shot）。
##   views：決めた位置から部屋を撮る → build/shots/view_*.png
##   swing：攻撃とナイフ回しを一定間隔で撮る → build/shots/swing_*.png, inspect_*.png

const OUT := "res://build/shots"
const VIEWS := [
	# 名前, 位置, 向き（度：左右）, 見上げ（度）
	["spawn", Vector3(0, 0.9, 8), 0.0, -5.0],
	["steps", Vector3(-6, 0.9, 2), 35.0, 0.0],
	["wallrun", Vector3(-12, 1.9, 16.2), -90.0, 5.0],
	["gaps", Vector3(10, 1.9, 4), 0.0, -8.0],
	["overview", Vector3(22, 9.0, 22), 45.0, -22.0],
	["corner", Vector3(-14, 1.65, -14), 45.0, 2.0],
]
const COMPASS := [0.0, 90.0, 180.0, 270.0]
const SWING_FRAMES := 12
const SWING_STEP := 1.0 / 30.0

var _player: Player


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	_player = scene.get_node("Player")
	scene.get_node("DebugUI").visible = false
	_run.call_deferred()


func _run() -> void:
	var mode := "views"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
	_player.input_enabled = false
	if mode == "views" or mode == "all":
		_player.set_physics_process(false) # 宙に置いた視点でも落ちないように
		for v in VIEWS:
			await _place(v[1], v[2], v[3])
			await _save("view_%s" % v[0])
		_player.set_physics_process(true)
	if mode == "idle":
		await _place(Vector3(-5, 0.9, 5.6), 0.0, -3.0)
		await _save("idle_0")
		_player.get_node("Head/Camera3D/ViewLight").visible = false
		await _wait(0.2)
		await _save("idle_1")
	if mode == "compass":
		for yaw in COMPASS:
			await _place(Vector3(0, 0.9, 0), yaw, 8.0)
			await _save("compass_%03d" % int(yaw))
	if mode == "swing" or mode == "all":
		# 描画が遅くても動きを等間隔に撮れるよう、武器の時間を手で進める
		await _place(Vector3(-5, 0.9, 5.6), 0.0, -3.0)
		var weapon: Weapon = _player.get_node("Head/Camera3D/Hand")
		weapon.set_physics_process(false)
		for k in 3:
			weapon.call("_start_swing")
			await _steps(weapon, "swing%d" % k, SWING_FRAMES, SWING_STEP)
			_steps_silent(weapon, 0.25) # 振り終わってすぐ次を振り、型をつなげる
		weapon.call("_start_inspect")
		await _steps(weapon, "inspect", SWING_FRAMES, 0.09)
		weapon.set_physics_process(true)
	get_tree().quit()


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	_player.respawn()
	_player.global_position = pos
	_player.rotation = Vector3(0, deg_to_rad(yaw), 0)
	_player.velocity = Vector3.ZERO
	await _wait(0.6)
	_player.head.rotation = Vector3(deg_to_rad(pitch), 0, 0)
	await _wait(0.4)


func _steps(weapon: Weapon, name: String, frames: int, step: float) -> void:
	for i in frames:
		await _save("%s_%02d" % [name, i])
		_steps_silent(weapon, step)


func _steps_silent(weapon: Weapon, sec: float) -> void:
	var dt := 1.0 / 120.0
	for i in int(round(sec / dt)):
		weapon.call("_physics_process", dt)


func _wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
