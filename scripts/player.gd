class_name Player
extends CharacterBody3D
## 一人称プレイヤー。走り・ジャンプ・コヨーテタイム・先行入力・壁走り（方向転換・壁ジャンプ）・
## スライディング・しゃがみ・壁登り・画面揺れ。
## 左手・右手のアクション（縁掴み・ポール回り・ボールト・壁押し）は子の HandActions が持ち、
## 動いている間だけ take_control() で体の動きを預かる。
## 大原則：動作を切り替えても水平方向の速度を落とさない。

const PITCH_LIMIT := deg_to_rad(89.0)
const BOB_FREQ := 1.6 # 1mあたりの揺れの位相（ラジアン）
const RESPAWN_Y := -20.0
const WALL_REACH := 0.5 # 体の表面から何mまでの壁を壁走りの対象にするか
const WALL_MAX_NORMAL_Y := 0.3 # 法線がこれより上下を向いていたら壁とみなさない
const WALL_STICK := 1.0 # 壁走り中に壁へ押し付ける速度 (m/s)
const WALL_PUSH_OFF := 1.0 # 時間切れで壁から離れるときの速度 (m/s)
const WALL_JUMP_MIN_OUT := 0.35 # スティックで向きを決めても、壁から離れる成分はこれ以上残す
const WORLD_LAYER := 1 # 壁走りの対象にする層。ダミー（層2）では壁走りしない
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.0
const HEAD_HEIGHT := 0.75 # 立っているときの頭の高さ（体の中心から）
const CROUCH_HEAD_DROP := 0.8 # しゃがむと目線がどれだけ下がるか
const WALL_CLIMB_MIN_INPUT := 0.5 # 壁登り：壁へ向けてスティックをどれだけ倒していれば登るか

## falseの間は入力を読まない（デバッグUIを開いているときなど）
var input_enabled := true

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _rising_from_jump := false
var _bob_phase := 0.0
var _spawn_transform: Transform3D

var _wallrunning := false
var _wallrun_time := 0.0
var _wallrun_speed := 0.0 # 進入時の速さ。方向転換しても最後はこの速さに戻す
var _wall_along := 0.0 # 壁沿いの速度（_wall_dir向きが正）。方向転換の途中で負になったら向きを入れ替える
var _wall_coyote_timer := 0.0 # 壁から離れた直後も少しの間は壁ジャンプできる
var _last_wall_normal := Vector3.ZERO
var _wall_normal := Vector3.ZERO
var _wall_dir := Vector3.ZERO # 壁に沿って進む向き（水平・単位ベクトル）
var _blocked_wall_normal := Vector3.ZERO # 着地するまで同じ壁には入り直さない

var _trauma := 0.0 # 画面揺れの元。0〜1。揺れの大きさはこの2乗
var _shake_time := 0.0
var _roll := 0.0
var _noise := FastNoiseLite.new()

var _sliding := false
var _crouching := false # 体が低い状態（スライディング中も真）
var _crouch_buffer := 0.0 # 空中でしゃがみを押したら、着地した瞬間にスライディングへ入る
var _slide_cooldown := 0.0 # スライディングの加速を連打で重ねないための待ち
var _slide_time := 0.0
var _crouch_amount := 0.0 # 目線の下がり具合（0〜1）。見た目用になめらかに追う

var _climbing := false
var _climb_time := 0.0
var _climbed_wall_normal := Vector3.ZERO # 着地するまで同じ壁は登り直さない

var _controller: Object = null # 手のアクションが体を動かしている間はここに入る
var _was_on_floor := true
var _landed := false # このフレームで着地したか（見た目用）

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var _collision: CollisionShape3D = $Collision
@onready var _shape: CapsuleShape3D = ($Collision.shape as CapsuleShape3D).duplicate()
@onready var _body_radius: float = _shape.radius


func _ready() -> void:
	_spawn_transform = global_transform
	_collision.shape = _shape
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
	if _controller != null:
		# 縁掴み・ボールト・ポール回りの間は、手のアクションが体を動かす
		_controller.call("drive", delta)
		_update_camera(delta)
		return
	_update_crouch(delta)
	if _wallrunning:
		_apply_wallrun(delta)
		if _jump_buffer_timer > 0.0:
			_wall_jump(_wall_normal)
	elif _climbing:
		_apply_climb(delta)
		if _jump_buffer_timer > 0.0:
			_climbing = false
			_wall_jump(_wall_normal)
	else:
		_apply_gravity(delta)
		_try_jump()
		_apply_jump_cut()
		if _sliding:
			_apply_slide(delta)
		else:
			_apply_horizontal(delta)
	var before := velocity
	move_and_slide()
	_landed = is_on_floor() and not _was_on_floor
	_was_on_floor = is_on_floor()
	if _wallrunning:
		_check_wallrun_end()
	elif _climbing:
		_check_climb_end()
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
	_climbing = false
	_blocked_wall_normal = Vector3.ZERO
	_climbed_wall_normal = Vector3.ZERO
	_wall_coyote_timer = 0.0
	_trauma = 0.0
	_sliding = false
	_crouch_buffer = 0.0
	_slide_cooldown = 0.0
	_set_crouched(false)
	_crouch_amount = 0.0
	if _controller != null and _controller.has_method("cancel"):
		_controller.call("cancel")
	_controller = null


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


func is_sliding() -> bool:
	return _sliding


func is_crouching() -> bool:
	return _crouching


func is_climbing() -> bool:
	return _climbing


func is_controlled() -> bool:
	return _controller != null


func just_landed() -> bool:
	return _landed


## 目線の下がり具合（0〜1）。足の見た目に使う。
func crouch_amount() -> float:
	return _crouch_amount


## 壁走り・壁登り中の壁の法線。どちらでもなければZERO。
func wall_normal() -> Vector3:
	return _wall_normal if (_wallrunning or _climbing) else Vector3.ZERO


## 壁走り中に壁沿いに進む向き。
func wall_direction() -> Vector3:
	return _wall_dir if _wallrunning else Vector3.ZERO


## 足元の位置（体の中心から立った高さの半分だけ下）。
func feet_position() -> Vector3:
	return global_position - Vector3(0.0, STAND_HEIGHT * 0.5, 0.0)


## 体の向き（水平・単位ベクトル）。
func facing() -> Vector3:
	var f := -global_transform.basis.z
	return Vector3(f.x, 0.0, f.z).normalized()


func body_radius() -> float:
	return _body_radius


## 手のアクションに体を預ける。controller は drive(delta) を持ち、終わったら release_control() を呼ぶ。
func take_control(controller: Object) -> void:
	_controller = controller
	_wallrunning = false
	_climbing = false
	_sliding = false
	_rising_from_jump = false
	_set_crouched(false)


## 体を返す。持ち出す速度を渡す。
func release_control(exit_velocity: Vector3) -> void:
	_controller = null
	velocity = exit_velocity
	_jump_buffer_timer = 0.0
	_was_on_floor = false


## 壁走り・壁登りを止めて、その壁には着地するまで入り直さない。壁押しで使う。
func leave_wall(n: Vector3) -> void:
	_wallrunning = false
	_climbing = false
	_blocked_wall_normal = n
	_climbed_wall_normal = n
	_wall_coyote_timer = 0.0
	_rising_from_jump = false


## 体の向きを水平に回す（ポール回りでカメラをついて行かせる）。
func turn(yaw: float) -> void:
	rotate_y(yaw)


## 立ち上がれるか（頭の上が空いているか）。
func can_stand_at(center: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = _body_radius
	shape.height = STAND_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = WORLD_LAYER
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


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
		_climbed_wall_normal = Vector3.ZERO
	else:
		_coyote_timer -= delta
	_wall_coyote_timer -= delta
	_slide_cooldown -= delta
	if input_enabled and Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = Tuning.jump_buffer
	else:
		_jump_buffer_timer -= delta
	if input_enabled and Input.is_action_just_pressed("crouch"):
		_crouch_buffer = Tuning.slide_buffer
	else:
		_crouch_buffer -= delta


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
		if _crouching and not can_stand_at(_stand_center()):
			return # 低い天井の下では跳ばない
		velocity.y = Tuning.jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_rising_from_jump = true
		# スライディングから跳んでも速さはそのまま持ち出す（スライドジャンプ）
		_sliding = false
		_set_crouched(false)
	elif _jump_buffer_timer > 0.0 and _wall_coyote_timer > 0.0:
		_wall_jump(_last_wall_normal)


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
	var top := Tuning.crouch_speed if _crouching and is_on_floor() else Tuning.max_speed
	var target := Vector2(dir.x, dir.z) * top
	var current := Vector2(velocity.x, velocity.z)

	var rate: float
	if is_on_floor():
		rate = Tuning.ground_accel if input != Vector2.ZERO else Tuning.ground_decel
		# 最高速度を超えて着地しても、走り続けていれば一気には削らない（勢いを次の動きへ持ち込む）
		if input != Vector2.ZERO and current.length() > top:
			var keep := maxf(top, current.length() - Tuning.ground_overspeed_decel * delta)
			target = target.normalized() * keep
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
	if into > sin(deg_to_rad(Tuning.wallrun_max_angle)):
		_try_start_climb(n)
		return
	if into < -0.1:
		return
	_wallrunning = true
	_wallrun_time = 0.0
	_wallrun_speed = speed # 進入時の速さを、向きだけ壁沿いに変えて保つ
	_wall_along = speed
	_wall_normal = n
	_wall_dir = _along_wall(n, dir)
	_rising_from_jump = false
	# 壁に入る前に押したジャンプで、入った瞬間に壁ジャンプしないようにする
	_jump_buffer_timer = 0.0
	_sliding = false
	_set_crouched(false)
	velocity.y = Tuning.wallrun_up_speed


func _apply_wallrun(delta: float) -> void:
	_wallrun_time += delta
	# 方向転換：進む向きと逆へスティックを倒すと、壁沿いに減速して折り返す。折り返した後は元の速さまで戻す
	var target := _wallrun_speed
	if _input_direction().dot(_wall_dir) < -0.5:
		target = -_wallrun_speed
	_wall_along = move_toward(_wall_along, target, Tuning.wallrun_turn_accel * delta)
	if _wall_along < 0.0:
		_wall_dir = -_wall_dir
		_wall_along = -_wall_along
	var h := _wall_dir * _wall_along - _wall_normal * WALL_STICK
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
	elif _wall_along > 1.0 and horizontal_speed() < _wall_along * 0.5:
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
	_last_wall_normal = _wall_normal
	_wall_coyote_timer = Tuning.coyote_time
	var h := _wall_dir * _wall_along
	velocity.x = h.x
	velocity.z = h.z


## 壁登り：壁へ正面から当たり、壁へ向けてスティックを倒していたら、壁を蹴って真上へ駆け上がる。
## 速さは上向きへ変わる。登った先の縁は左手で掴む。
func _try_start_climb(n: Vector3) -> void:
	if n.dot(_climbed_wall_normal) > 0.9 or velocity.y < Tuning.wallclimb_min_vy:
		return
	if _input_direction().dot(-n) < WALL_CLIMB_MIN_INPUT:
		return
	_climbing = true
	_climb_time = 0.0
	_wall_normal = n
	_climbed_wall_normal = n
	_rising_from_jump = false
	_jump_buffer_timer = 0.0
	_sliding = false
	_set_crouched(false)
	velocity = Vector3(0.0, maxf(velocity.y, Tuning.wallclimb_speed), 0.0) - n * WALL_STICK


func _apply_climb(delta: float) -> void:
	_climb_time += delta
	velocity.x = -_wall_normal.x * WALL_STICK
	velocity.z = -_wall_normal.z * WALL_STICK
	velocity.y -= Tuning.gravity * Tuning.wallclimb_gravity_mult * delta


func _check_climb_end() -> void:
	if is_on_floor():
		_climbing = false
	elif velocity.y <= 0.0 or _climb_time >= Tuning.wallclimb_max_time:
		# 登り切れなかった：壁から少し離して落とす
		_climbing = false
		velocity += _wall_normal * WALL_PUSH_OFF * 0.5
		velocity.y = minf(velocity.y, 0.0)
	elif _input_direction().dot(_wall_normal) > 0.5:
		_climbing = false
	elif _cast_wall(-_wall_normal) == Vector3.ZERO:
		# 壁の上端を越えた：前へ少し押し出して上に乗せる
		_climbing = false
		velocity += -_wall_normal * Tuning.wallclimb_top_push


## 壁ジャンプ：壁から離れる向きと上へ跳ぶ。スティックを倒していればその向きへ跳び、速さは落とさない。
func _wall_jump(n: Vector3) -> void:
	var h := _wall_dir * _wall_along if _wallrunning else Vector3(velocity.x, 0.0, velocity.z)
	var out := h + n * Tuning.wall_jump_push
	var input := _input_direction()
	if input.length() > 0.1:
		# 壁へ向かう分は取り除き、必ず壁から離れる成分を残す
		var d := input.normalized()
		var side := d - n * d.dot(n)
		d = (side + n * maxf(d.dot(n), WALL_JUMP_MIN_OUT)).normalized()
		out = d * out.length()
	velocity = Vector3(out.x, Tuning.wall_jump_up, out.z)
	_wallrunning = false
	_climbing = false
	_blocked_wall_normal = n
	_wall_coyote_timer = 0.0
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_rising_from_jump = true


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


## しゃがみボタンとスライディング。走っていて押す（空中で押して着地する）とスライディング、
## 遅いときはしゃがみ歩き。低い天井の下では立ち上がらない。
func _update_crouch(delta: float) -> void:
	var held := input_enabled and Input.is_action_pressed("crouch")
	if is_on_floor():
		# 押した直後か、押しっぱなしで着地した瞬間（スライドホップ）ならスライディング
		var wants := _crouch_buffer > 0.0 or (held and _landed)
		if not _sliding and wants and horizontal_speed() >= Tuning.slide_min_speed:
			_start_slide()
		elif _sliding and (not held and _slide_time >= Tuning.slide_min_time or horizontal_speed() < Tuning.slide_end_speed):
			_sliding = false
		if not _sliding:
			if held:
				_set_crouched(true)
			elif _crouching and can_stand_at(_stand_center()):
				_set_crouched(false)
	elif not held and not _sliding and _crouching and can_stand_at(_stand_center()):
		_set_crouched(false)
	if _sliding:
		_slide_time += delta


func _start_slide() -> void:
	_sliding = true
	_slide_time = 0.0
	_crouch_buffer = 0.0
	_set_crouched(true)
	# 加速は待ち時間が明けているときだけ。連打では重ならない
	if _slide_cooldown <= 0.0:
		var h := Vector3(velocity.x, 0.0, velocity.z)
		var boosted := minf(h.length() + Tuning.slide_boost, maxf(Tuning.slide_boost_cap, h.length()))
		h = h.normalized() * boosted
		velocity.x = h.x
		velocity.z = h.z
		_slide_cooldown = Tuning.slide_boost_cooldown


## スライディング中：向きはほぼ保ったまま、少しずつ減速する。スティックで少しだけ曲がれる。
func _apply_slide(delta: float) -> void:
	var h := Vector2(velocity.x, velocity.z)
	var speed := maxf(0.0, h.length() - Tuning.slide_friction * delta)
	var dir := h.normalized() if h.length() > 0.01 else Vector2.ZERO
	var wish := _input_direction()
	var w := Vector2(wish.x, wish.z)
	if w.length() > 0.1 and dir != Vector2.ZERO:
		var angle := dir.angle_to(w.normalized())
		var step := deg_to_rad(Tuning.slide_steer) * delta
		dir = dir.rotated(clampf(angle, -step, step))
	h = dir * speed
	velocity.x = h.x
	velocity.z = h.y


func _set_crouched(on: bool) -> void:
	if _shape == null or _crouching == on:
		_crouching = on
		return
	_crouching = on
	# 足の位置を変えずに体を縮める：中心を下げる
	_shape.height = CROUCH_HEIGHT if on else STAND_HEIGHT
	_collision.position.y = -(STAND_HEIGHT - CROUCH_HEIGHT) * 0.5 if on else 0.0


func _stand_center() -> Vector3:
	return global_position


func _update_camera(delta: float) -> void:
	camera.fov = Tuning.fov
	var crouch_target := 1.0 if _crouching else 0.0
	_crouch_amount = move_toward(_crouch_amount, crouch_target, delta / maxf(Tuning.crouch_cam_time, 0.01))
	head.position.y = HEAD_HEIGHT - CROUCH_HEAD_DROP * smoothstep(0.0, 1.0, _crouch_amount)
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
	elif _sliding:
		roll = deg_to_rad(Tuning.slide_tilt)
	_roll = lerpf(_roll, roll, minf(1.0, 10.0 * delta))
	# 画面揺れ（トラウマ値の減衰方式）：揺れ = トラウマ²、向きはノイズで滑らかに
	_trauma = maxf(0.0, _trauma - Tuning.shake_decay * delta)
	_shake_time += delta * Tuning.shake_freq
	var shake := _trauma * _trauma * deg_to_rad(Tuning.shake_max_angle)
	camera.rotation = Vector3(
		shake * _noise.get_noise_2d(_shake_time, 0.0),
		shake * _noise.get_noise_2d(_shake_time, 100.0),
		_roll + shake * 0.5 * _noise.get_noise_2d(_shake_time, 200.0))
