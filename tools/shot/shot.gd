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
	if mode == "grip" or mode == "inspect":
		await _grip_views(mode)
	if mode == "thumb":
		await _place(Vector3(-15, 0.9, 5.6), 0.0, 0.0)
		var weapon: Weapon = _player.get_node("Head/Camera3D/Hand")
		weapon.set_physics_process(false)
		var cam := Camera3D.new()
		cam.fov = 40.0
		cam.near = 0.01
		add_child(cam)
		for curl in [[-40.0, 30.0, 30.0], [80.0, 70.0, 60.0]]:
			for across in [-90.0, -45.0, 0.0, 45.0]:
				weapon.thumb_across = across
				weapon.thumb_grip = Vector3(curl[0], curl[1], curl[2])
				weapon.call("_pose_fingers")
				var center: Vector3 = weapon.get_node("Swing/Grip").global_position
				for a in [["back", Vector3(0.15, 0.12, 0.45)]]:
					cam.global_position = center + a[1]
					cam.look_at(center)
					cam.make_current()
					await _save("thumb_%+03d_%+03d_%s" % [int(curl[0]), int(across), a[0]])
	if mode == "compass":
		for yaw in COMPASS:
			await _place(Vector3(0, 0.9, 0), yaw, 8.0)
			await _save("compass_%03d" % int(yaw))
	if mode == "look":
		await _place(Vector3(-15, 0.9, 5.6), 0.0, -3.0)
		var w: Weapon = _player.get_node("Head/Camera3D/Hand")
		w.set_physics_process(false)
		w.call("_start_inspect")
		await _steps(w, "inspect", 16, Weapon.INSPECT_TIME / 15.0)
		w.set_physics_process(true)
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
		await _steps(weapon, "inspect", 16, Weapon.INSPECT_TIME / 15.0)
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


## 手元を別のカメラで、横・上・前・後ろから撮る。inspect ではナイフ回しの途中も撮る。
func _grip_views(mode: String) -> void:
	await _place(Vector3(-15, 0.9, 5.6), 0.0, 0.0)
	var weapon: Weapon = _player.get_node("Head/Camera3D/Hand")
	weapon.set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.01
	add_child(cam)
	var times: Array = [0.0] if mode == "grip" else [0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9]
	if mode == "inspect":
		weapon.call("_start_inspect")
	var done := 0.0
	for t in times:
		_steps_silent(weapon, t - done)
		done = t
		var center: Vector3 = weapon.get_node("Swing/Grip").global_position
		var angles: Array = [["side", Vector3(-0.55, 0.05, 0.0)], ["top", Vector3(0.0, 0.55, 0.05)], ["front", Vector3(0.0, 0.05, -0.55)], ["back", Vector3(0.15, 0.12, 0.45)]]
		if mode == "inspect":
			angles = [angles[3], angles[0]]
		for a in angles:
			cam.global_position = center + a[1]
			cam.look_at(center, Vector3.UP if a[0] != "top" else Vector3.FORWARD)
			cam.make_current()
			await _save("%s_%02d_%s" % [mode, int(t * 100), a[0]])
		_player.camera.make_current()
		await _save("%s_%02d_view" % [mode, int(t * 100)])
	cam.queue_free()
	weapon.set_physics_process(true)


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
