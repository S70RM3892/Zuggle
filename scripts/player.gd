class_name Player
extends CharacterBody3D
## 一人称プレイヤー。M1：走り・ジャンプ・コヨーテタイム・先行入力。
## 大原則：動作を切り替えても水平方向の速度を落とさない。

const PITCH_LIMIT := deg_to_rad(89.0)
const BOB_FREQ := 1.6 # 1mあたりの揺れの位相（ラジアン）
const RESPAWN_Y := -20.0

## falseの間は入力を読まない（デバッグUIを開いているときなど）
var input_enabled := true

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _rising_from_jump := false
var _bob_phase := 0.0
var _spawn_transform: Transform3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D


func _ready() -> void:
	_spawn_transform = global_transform


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var deg_per_px := Tuning.mouse_sensitivity
		_rotate_view(-event.relative.x * deg_to_rad(deg_per_px), -event.relative.y * deg_to_rad(deg_per_px))


func _physics_process(delta: float) -> void:
	if input_enabled:
		_process_stick_look(delta)
	_update_timers(delta)
	_apply_gravity(delta)
	_try_jump()
	_apply_jump_cut()
	_apply_horizontal(delta)
	move_and_slide()
	_update_camera(delta)
	if global_position.y < RESPAWN_Y:
		respawn()


func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	head.rotation = Vector3.ZERO


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _process_stick_look(delta: float) -> void:
	var v := Input.get_vector("look_left", "look_right", "look_up", "look_down", Tuning.stick_deadzone)
	if v == Vector2.ZERO:
		return
	# 小さい倒しで細かく、大きい倒しで速く回せるようにカーブをかける
	v = v.normalized() * pow(v.length(), Tuning.look_curve)
	var step := deg_to_rad(Tuning.look_speed) * delta
	_rotate_view(-v.x * step, -v.y * step)


func _rotate_view(yaw: float, pitch: float) -> void:
	rotate_y(yaw)
	head.rotation.x = clampf(head.rotation.x + pitch, -PITCH_LIMIT, PITCH_LIMIT)


func _update_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = Tuning.coyote_time
	else:
		_coyote_timer -= delta
	if input_enabled and Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = Tuning.jump_buffer
	else:
		_jump_buffer_timer -= delta


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := Tuning.gravity
	if velocity.y < 0.0:
		g *= Tuning.fall_gravity_mult
	velocity.y -= g * delta


func _try_jump() -> void:
	# 先行入力（ボタンが少し早い）とコヨーテタイム（崖から少し遅い）の両方を許す
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = Tuning.jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_rising_from_jump = true


func _apply_jump_cut() -> void:
	if not _rising_from_jump:
		return
	if velocity.y <= 0.0:
		_rising_from_jump = false
	elif not (input_enabled and Input.is_action_pressed("jump")):
		velocity.y *= Tuning.jump_cut
		_rising_from_jump = false


func _apply_horizontal(delta: float) -> void:
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back", Tuning.stick_deadzone)
	var dir := transform.basis * Vector3(input.x, 0.0, input.y)
	var target := Vector2(dir.x, dir.z) * Tuning.max_speed
	var current := Vector2(velocity.x, velocity.z)

	var rate: float
	if is_on_floor():
		rate = Tuning.ground_accel if input != Vector2.ZERO else Tuning.ground_decel
	else:
		rate = Tuning.air_accel if input != Vector2.ZERO else Tuning.air_decel
		# 空中では向きだけ変え、持ち込んだ速さは削らない
		if input != Vector2.ZERO and current.length() > target.length():
			target = target.normalized() * current.length()

	current = current.move_toward(target, rate * delta)
	velocity.x = current.x
	velocity.z = current.y


func _update_camera(delta: float) -> void:
	camera.fov = Tuning.fov
	var speed := horizontal_speed()
	var bob_y := 0.0
	if is_on_floor() and speed > 0.5 and Tuning.head_bob > 0.0:
		_bob_phase += speed * BOB_FREQ * delta
		bob_y = sin(_bob_phase) * Tuning.head_bob
	camera.position.y = lerpf(camera.position.y, bob_y, minf(1.0, 15.0 * delta))
