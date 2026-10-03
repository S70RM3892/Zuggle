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
const SWING_STEP := 0.04

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
	if mode == "compass":
		for yaw in COMPASS:
			await _place(Vector3(0, 0.9, 0), yaw, 8.0)
			await _save("compass_%03d" % int(yaw))
	if mode == "swing" or mode == "all":
		await _place(Vector3(-5, 0.9, 6.0), 0.0, -3.0)
		_player.input_enabled = true
		await _sequence("attack", "swing")
		await _wait(0.8)
		await _sequence("attack", "swing2")
		await _wait(0.8)
		await _sequence("inspect", "inspect", 0.09)
	get_tree().quit()


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	_player.respawn()
	_player.global_position = pos
	_player.rotation = Vector3(0, deg_to_rad(yaw), 0)
	_player.velocity = Vector3.ZERO
	await _wait(0.6)
	_player.head.rotation = Vector3(deg_to_rad(pitch), 0, 0)
	await _wait(0.4)


func _sequence(action: String, name: String, step := SWING_STEP) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	for i in SWING_FRAMES:
		await _save("%s_%02d" % [name, i])
		await _wait(step)


func _wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
