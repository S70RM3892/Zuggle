class_name Player
extends CharacterBody3D
## 一人称プレイヤー。M1：走り・ジャンプ・コヨーテタイム・先行入力。M2：壁走り。M3：画面揺れ。
## 大原則：動作を切り替えても水平方向の速度を落とさない。

const PITCH_LIMIT := deg_to_rad(89.0)
const BOB_FREQ := 1.6 # 1mあたりの揺れの位相（ラジアン）
const RESPAWN_Y := -20.0
const WALL_REACH := 0.5 # 体の表面から何mまでの壁を壁走りの対象にするか
const WALL_MAX_NORMAL_Y := 0.3 # 法線がこれより上下を向いていたら壁とみなさない
const WALL_STICK := 1.0 # 壁走り中に壁へ押し付ける速度 (m/s)
const WALL_PUSH_OFF := 1.0 # 時間切れで壁から離れるときの速度 (m/s)
const WORLD_LAYER := 1 # 壁走りの対象にする層。ダミー（層2）では壁走りしない

## falseの間は入力を読まない（デバッグUIを開いているときなど）
var input_enabled := true

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _rising_from_jump := false
var _bob_phase := 0.0
var _spawn_transform: Transform3D

var _wallrunning := false
var _wallrun_time := 0.0
var _wallrun_speed := 0.0
var _wall_normal := Vector3.ZERO
var _wall_dir := Vector3.ZERO # 壁に沿って進む向き（水平・単位ベクトル）
var _blocked_wall_normal := Vector3.ZERO # 着地するまで同じ壁には入り直さない

var _trauma := 0.0 # 画面揺れの元。0〜1。揺れの大きさはこの2乗
var _shake_time := 0.0
var _roll := 0.0
var _noise := FastNoiseLite.new()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var _body_radius: float = ($Collision.shape as CapsuleShape3D).radius


func _ready() -> void:
	_spawn_transform = global_transform
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0


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
	if _wallrunning:
		_apply_wallrun(delta)
	else:
		_apply_gravity(delta)
		_try_jump()
		_apply_jump_cut()
		_apply_horizontal(delta)
	var before := velocity
	move_and_slide()
	if _wallrunning:
		_check_wallrun_end()
	else:
		_try_start_wallrun(before)
	_update_camera(delta)
	if global_position.y < RESPAWN_Y:
		respawn()


func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	head.rotation = Vector3.ZERO
	_wallrunning = false
	_blocked_wall_normal = Vector3.ZERO
	_trauma = 0.0


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 画面揺れを足す。ランダムではなくノイズで滑らかに揺らし、時間で減衰させる。
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func trauma() -> float:
	return _trauma


func is_wall_running() -> bool:
	return _wallrunning


func wallrun_time_left() -> float:
	return maxf(0.0, Tuning.wallrun_max_time - _wallrun_time) if _wallrunning else 0.0


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
		_blocked_wall_normal = Vector3.ZERO
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


func _try_start_wallrun(before: Vector3) -> void:
	if is_on_floor():
		return
	# 壁に当たるとmove_and_slideで壁向きの成分が消えるので、動く前の速度で判定する
	var h := Vector3(before.x, 0.0, before.z)
	var speed := h.length()
	if speed < maxf(Tuning.wallrun_min_speed, 0.01):
		return
	var dir := h / speed
	var n := _find_side_wall(dir)
	if n == Vector3.ZERO or n.dot(_blocked_wall_normal) > 0.9:
		return
	# 0なら壁と平行、1なら正面衝突。負なら壁から離れている
	var into := -dir.dot(n)
	if into < -0.1 or into > sin(deg_to_rad(Tuning.wallrun_max_angle)):
		return
	_wallrunning = true
	_wallrun_time = 0.0
	_wallrun_speed = speed # 進入時の速さを、向きだけ壁沿いに変えて保つ
	_wall_normal = n
	_wall_dir = _along_wall(n, dir)
	_rising_from_jump = false
	velocity.y = Tuning.wallrun_up_speed


func _apply_wallrun(delta: float) -> void:
	_wallrun_time += delta
	var h := _wall_dir * _wallrun_speed - _wall_normal * WALL_STICK
	velocity.x = h.x
	velocity.z = h.z
	velocity.y -= Tuning.gravity * Tuning.wallrun_gravity_mult * delta


func _check_wallrun_end() -> void:
	if is_on_floor():
		_end_wallrun()
	elif _wallrun_time >= Tuning.wallrun_max_time:
		# 仕様：上限を超えたら落下する。壁から少し離して貼り付き直しを防ぐ
		_end_wallrun()
		velocity += _wall_normal * WALL_PUSH_OFF
	elif _input_direction().dot(_wall_normal) > 0.5:
		# 壁と反対へスティックを倒したら離れる
		_end_wallrun()
	elif horizontal_speed() < _wallrun_speed * 0.5:
		# 前の障害物にぶつかって止められた。速さは戻さない
		_wallrunning = false
		_blocked_wall_normal = _wall_normal
	else:
		var n := _cast_wall(-_wall_normal)
		if n == Vector3.ZERO:
			# 壁が終わった：勢いを保ったまま抜ける
			_end_wallrun()
		else:
			# 曲がった壁にも沿えるように、毎フレーム法線を取り直す
			_wall_normal = n
			_wall_dir = _along_wall(n, _wall_dir)


## 壁走りをやめる。壁へ押し付けていた分を消し、壁沿いの速さはそのまま持ち出す。
func _end_wallrun() -> void:
	_wallrunning = false
	_blocked_wall_normal = _wall_normal
	var h := _wall_dir * _wallrun_speed
	velocity.x = h.x
	velocity.z = h.z


## 進行方向の左右にある壁の法線（水平・単位ベクトル）。なければZERO。
func _find_side_wall(dir: Vector3) -> Vector3:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		# CSGの壁はCollisionObject3Dではないので、層はプロパティとして読む
		var body := c.get_collider()
		if body == null or not (int(body.get("collision_layer")) & WORLD_LAYER):
			continue
		var n := _flat_wall_normal(c.get_normal())
		if n != Vector3.ZERO:
			return n
	var right := dir.cross(Vector3.UP)
	var n := _cast_wall(right)
	if n == Vector3.ZERO:
		n = _cast_wall(-right)
	return n


func _cast_wall(direction: Vector3) -> Vector3:
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * (_body_radius + WALL_REACH), WORLD_LAYER)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	return _flat_wall_normal(hit.normal)


func _flat_wall_normal(n: Vector3) -> Vector3:
	if absf(n.y) > WALL_MAX_NORMAL_Y:
		return Vector3.ZERO
	return Vector3(n.x, 0.0, n.z).normalized()


func _along_wall(n: Vector3, prefer: Vector3) -> Vector3:
	var t := Vector3.UP.cross(n).normalized()
	return t if t.dot(prefer) >= 0.0 else -t


func _input_direction() -> Vector3:
	if not input_enabled:
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back", Tuning.stick_deadzone)
	return transform.basis * Vector3(input.x, 0.0, input.y)


func _update_camera(delta: float) -> void:
	camera.fov = Tuning.fov
	var speed := horizontal_speed()
	var bob_y := 0.0
	if is_on_floor() and speed > 0.5 and Tuning.head_bob > 0.0:
		_bob_phase += speed * BOB_FREQ * delta
		bob_y = sin(_bob_phase) * Tuning.head_bob
	camera.position.y = lerpf(camera.position.y, bob_y, minf(1.0, 15.0 * delta))
	# 壁走り中は壁と反対側へ少し傾ける
	var roll := 0.0
	if _wallrunning:
		roll = -_wall_normal.dot(global_transform.basis.x) * deg_to_rad(Tuning.wallrun_tilt)
	_roll = lerpf(_roll, roll, minf(1.0, 10.0 * delta))
	# 画面揺れ（トラウマ値の減衰方式）：揺れ = トラウマ²、向きはノイズで滑らかに
	_trauma = maxf(0.0, _trauma - Tuning.shake_decay * delta)
	_shake_time += delta * Tuning.shake_freq
	var shake := _trauma * _trauma * deg_to_rad(Tuning.shake_max_angle)
	camera.rotation = Vector3(
		shake * _noise.get_noise_2d(_shake_time, 0.0),
		shake * _noise.get_noise_2d(_shake_time, 100.0),
		_roll + shake * 0.5 * _noise.get_noise_2d(_shake_time, 200.0))
