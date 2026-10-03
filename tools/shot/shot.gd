extends Node
## 一人称の手とナイフの見え方を撮る。表示が要るので xvfb-run で実行する：
##   SHOT_DIR=build/shots xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/shot/shot.tscn
## 構え、振り（振りかぶり・判定・戻り）、ナイフ回しの途中、スーパーグライドを書き出す。

var _player: Player
var _weapon: Weapon
var _dir := ""
var _n := 0


func _ready() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://build/shots")
	DirAccess.make_dir_recursive_absolute(_dir)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	_player = scene.get_node("Player")
	_weapon = scene.get_node("Player/Head/Camera3D/Hand")
	scene.get_node("DebugUI").visible = false
	_run.call_deferred()


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	get_viewport().get_texture().get_image().save_png(_dir.path_join("fp_%02d_%s.png" % [_n, name]))


func _run() -> void:
	_player.global_position = Vector3(-5, 0.9, 7)
	_player.rotation = Vector3(0, 0, 0) # ダミーの方を向く
	await _physics(120)
	await _snap("idle")
	_player.global_position = Vector3(0, 0.9, 0) # 振りは何もない所で撮る（ヒットストップを避ける）
	await _physics(30)
	Input.action_press("attack")
	await _physics(1)
	Input.action_release("attack")
	for name in ["windup", "active", "active2", "recovery"]:
		await _physics(4 if name == "windup" else 5)
		await _snap(name)
	await _physics(120)
	Input.action_press("inspect")
	await _physics(1)
	Input.action_release("inspect")
	for i in 8:
		await _physics(14)
		await _snap("spin%d" % i)
	await _glide()
	get_tree().quit()


## GlideLedge（高さ1.5m、手前の面はz=2）でよじ登り、縁を越える頃にジャンプ→しゃがみ
func _glide() -> void:
	_player.respawn()
	await _physics(2)
	_player.global_position = Vector3(-20, 0.9, 5.0)
	_player.rotation = Vector3.ZERO
	await _physics(30)
	Input.action_press("move_forward")
	await _physics(20)
	Input.action_press("jump")
	while not _player.is_mantling():
		await _physics(1)
	Input.action_release("jump")
	await _snap("mantle")
	while not _player.superglide_window():
		await _physics(1)
	await _snap("mantle_top")
	Input.action_press("jump")
	await _physics(2)
	Input.action_press("crouch")
	await _physics(2)
	Input.action_release("jump")
	Input.action_release("crouch")
	for i in 4:
		await _physics(18)
		await _snap("glide%d" % i)
	Input.action_release("move_forward")
