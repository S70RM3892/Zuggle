class_name Player
extends CharacterBody3D
## 一人称プレイヤー。M1：走り・ジャンプ・コヨーテタイム・先行入力。M2：壁走り（方向転換・壁ジャンプ）。M3：画面揺れ。
## M4：斬撃モード（RT / 右クリックを押している間）は、右スティックとマウスを視点ではなくアナログ斬りに使う。
## M5：スライディング（B / Ctrl / C）、左手での乗り越え・よじ登り（壁走り中に壁へ倒すと壁の上へ）。
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
const STAND_HEIGHT := 1.8 # 立っているときの体（カプセル）の高さ
const SLIDE_HEIGHT := 1.0 # スライディング中の体の高さ。足の位置は変えずに縮める
const EYE_STAND := 0.75 # 体の中心から目までの高さ
const EYE_SLIDE := -0.05 # スライディング中は足から0.85m
const SLIDE_STEER := 2.0 # スライディング中にスティックで向きを変える速さ（単位ベクトルの変化/秒）
const SLIDE_BUFFER := 0.2 # 着地前に押したスライディングを受け付ける時間 (秒)
const LEDGE_MIN := 0.15 # 足からこれより低い段は乗り越えの対象にしない (m)
const LEDGE_PROBE_IN := 0.3 # 縁から奥へこれだけ入った所で上面を探す (m)
const LEDGE_MAX_ANGLE := 50.0 # 壁の正面からこの角度以内へ向かっていれば乗り越える (度)
const LEDGE_WALLRUN_INTO := 0.5 # 壁走り中、スティックの壁へ向かう成分がこれ以上なら壁の上へよじ登る
const LEDGE_EXIT_MIN := 3.0 # よじ登った後に前へ進む最低の速さ (m/s)
const PUSH_TIME := 0.18 # 壁ジャンプで左手が壁を押している時間 (秒)

enum Ledge { NONE, VAULT, MANTLE }

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

var _sliding := false
var _slide_time := 0.0
var _slide_buffer := 0.0
var _eye := EYE_STAND

var _ledge := Ledge.NONE # 乗り越え・よじ登りの途中か
var _ledge_t := 0.0
var _ledge_time := 0.0
var _ledge_from := Vector3.ZERO
var _ledge_to := Vector3.ZERO
var _ledge_exit := Vector3.ZERO # 終わったときの速度
var _ledge_edge := Vector3.ZERO # 左手をつく縁（ワールド座標）
var _ledge_dir := Vector3.ZERO # 越える向き（水平・単位ベクトル）

var _push_timer := 0.0 # 壁ジャンプで壁を押した左手の残り時間
var _push_point := Vector3.ZERO
var _push_normal := Vector3.ZERO

var _trauma := 0.0 # 画面揺れの元。0〜1。揺れの大きさはこの2乗
var _shake_time := 0.0
var _roll := 0.0
var _noise := FastNoiseLite.new()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var _collision: CollisionShape3D = $Collision
@onready var _body_radius: float = ($Collision.shape as CapsuleShape3D).radius


func _ready() -> void:
	_spawn_transform = global_transform
	# スライディングで高さを変えるので、シーンの形を書き換えないよう複製する
	_collision.shape = _collision.shape.duplicate()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or slash_mode():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var deg_per_px := Tuning.mouse_sensitivity
		_rotate_view(-event.relative.x * deg_to_rad(deg_per_px), -event.relative.y * deg_to_rad(deg_per_px))


func _physics_process(delta: float) -> void:
	if input_enabled and not slash_mode():
		_process_stick_look(delta)
	_update_timers(delta)
	if _ledge != Ledge.NONE:
		# 乗り越え・よじ登りの間は決めた道筋をなぞる（当たり判定は始める前に確かめてある）
		_apply_ledge(delta)
		_update_camera(delta)
		return
	if _wallrunning:
		_apply_wallrun(delta)
		if _jump_buffer_timer > 0.0:
			_wall_jump(_wall_normal)
		elif _try_wallrun_mantle():
			_update_camera(delta)
			return
	elif _sliding:
		_apply_gravity(delta)
		_apply_slide(delta)
		if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and _has_headroom():
			_end_slide() # スライディングジャンプ：速さはそのまま跳ぶ
			_try_jump()
	else:
		_apply_gravity(delta)
		_try_jump()
		_apply_jump_cut()
		_apply_horizontal(delta)
	var before := velocity
	move_and_slide()
	if _wallrunning:
		_check_wallrun_end()
	elif _sliding:
		_check_slide_end()
	elif not _try_ledge(before):
		_try_start_wallrun(before)
		_try_start_slide()
	_update_camera(delta)
	if global_position.y < RESPAWN_Y:
		respawn()


func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	head.rotation = Vector3.ZERO
	_wallrunning = false
	_blocked_wall_normal = Vector3.ZERO
	_wall_coyote_timer = 0.0
	_trauma = 0.0
	_ledge = Ledge.NONE
	_push_timer = 0.0
	_slide_buffer = 0.0
	if _sliding:
		_end_slide()


## 斬撃モード：RT / 右クリックを押している間。右スティックとマウスがアナログ斬りになる。
func slash_mode() -> bool:
	return input_enabled and Input.is_action_pressed("slash_mode")


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## 画面揺れを足す。ランダムではなくノイズで滑らかに揺らし、時間で減衰させる。
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func trauma() -> float:
	return _trauma


func is_wall_running() -> bool:
	return _wallrunning


## 壁走り中の壁の法線（壁から離れる向き）。壁走りしていなければZERO。
func wall_normal() -> Vector3:
	return _wall_normal if _wallrunning else Vector3.ZERO


func is_sliding() -> bool:
	return _sliding


## 乗り越え（"vault"）・よじ登り（"mantle"）の途中ならその名前。ほかは空。
func ledge_kind() -> String:
	match _ledge:
		Ledge.VAULT:
			return "vault"
		Ledge.MANTLE:
			return "mantle"
	return ""


## 左手の行き先。kind：vault / mantle（縁に手をつく）、wall（壁走り中の壁）、push（壁ジャンプで壁を押す）、
## slide（床へ手を伸ばす）、空なら構えに戻す。point と normal はワールド座標（slideでは使わない）。
func left_hand_target() -> Dictionary:
	if _ledge != Ledge.NONE:
		return {"kind": ledge_kind(), "point": _ledge_edge, "normal": Vector3.UP, "dir": _ledge_dir,
			"progress": clampf(_ledge_t / maxf(_ledge_time, 0.001), 0.0, 1.0)}
	if _wallrunning:
		var eye := head.global_position
		return {"kind": "wall", "point": eye - _wall_normal * (_body_radius + 0.02) + _wall_dir * 0.35 - Vector3.UP * 0.2,
			"normal": _wall_normal, "dir": _wall_dir, "progress": 0.0}
	if _push_timer > 0.0:
		return {"kind": "push", "point": _push_point, "normal": _push_normal, "dir": Vector3.ZERO,
			"progress": 1.0 - _push_timer / PUSH_TIME}
	if _sliding:
		return {"kind": "slide", "point": Vector3.ZERO, "normal": Vector3.UP, "dir": Vector3.ZERO, "progress": 0.0}
	return {}


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
	_wall_coyote_timer -= delta
	_push_timer -= delta
	if input_enabled and Input.is_action_just_pressed("slide"):
		_slide_buffer = SLIDE_BUFFER
	else:
		_slide_buffer -= delta
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
	_wall_along = speed
	_wall_normal = n
	_wall_dir = _along_wall(n, dir)
	_rising_from_jump = false
	# 壁に入る前に押したジャンプで、入った瞬間に壁ジャンプしないようにする
	_jump_buffer_timer = 0.0
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
	_push_timer = PUSH_TIME
	_push_normal = n
	_push_point = head.global_position - n * (_body_radius + 0.02) - Vector3.UP * 0.15
	_wallrunning = false
	_blocked_wall_normal = n
	_wall_coyote_timer = 0.0
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_rising_from_jump = true


## スライディング：地上で最低速度以上なら、体を低くして滑る。始めに少し加速し、だんだん減速する。
func _try_start_slide() -> void:
	if _slide_buffer <= 0.0 or not is_on_floor() or horizontal_speed() < Tuning.slide_min_speed:
		return
	_slide_buffer = 0.0
	_sliding = true
	_slide_time = 0.0
	# 加速は最高速度＋加速分までにとどめる（連打で無限に速くならない）。それより速ければ速さを保つ
	var speed := horizontal_speed()
	var boosted := maxf(speed, minf(speed + Tuning.slide_boost, Tuning.max_speed + Tuning.slide_boost))
	var h := Vector2(velocity.x, velocity.z).normalized() * boosted
	velocity.x = h.x
	velocity.z = h.y
	_set_body_height(SLIDE_HEIGHT)


func _apply_slide(delta: float) -> void:
	_slide_time += delta
	var h := Vector2(velocity.x, velocity.z)
	if is_on_floor():
		# 下り坂では重力で加速し、上り坂では減速する
		var n := get_floor_normal()
		h += Vector2(n.x, n.z) * Tuning.gravity * Tuning.slide_slope_mult * delta
	var speed := move_toward(h.length(), 0.0, Tuning.slide_friction * delta)
	if not _has_headroom():
		speed = maxf(speed, Tuning.slide_end_speed) # 低い天井の下では止まらずに抜ける
	var dir := h.normalized() if h.length() > 0.01 else Vector2(-transform.basis.z.x, -transform.basis.z.z)
	var input := _input_direction()
	if input.length() > 0.1:
		var want := Vector2(input.x, input.z).normalized()
		if want.dot(dir) > -0.2: # 真後ろへ倒しても向きは変えない
			dir = dir.move_toward(want, SLIDE_STEER * delta).normalized()
	h = dir * speed
	velocity.x = h.x
	velocity.z = h.y


func _check_slide_end() -> void:
	if not _has_headroom():
		return
	if not is_on_floor() or horizontal_speed() < Tuning.slide_end_speed or _slide_time >= Tuning.slide_max_time:
		_end_slide()


func _end_slide() -> void:
	_sliding = false
	_set_body_height(STAND_HEIGHT)


## 足の位置を変えずに体の高さを変える。
func _set_body_height(height: float) -> void:
	(_collision.shape as CapsuleShape3D).height = height
	_collision.position.y = (height - STAND_HEIGHT) * 0.5


## 立ち上がれるか（立った体の形が何にも当たらないか）。
func _has_headroom() -> bool:
	return not _overlaps_standing(global_position)


func _overlaps_standing(center: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = _body_radius
	shape.height = STAND_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## 乗り越え・よじ登り：前の壁に当たり、その上面が手の届く高さにあれば、左手をついて上へ移る。
## 地上では低い段（乗り越え）だけ、空中では高い縁（よじ登り）まで。速さは落とさずに持ち出す。
func _try_ledge(before: Vector3) -> bool:
	var input := _input_direction()
	var h := Vector3(before.x, 0.0, before.z)
	var dir := Vector3.ZERO
	if input.length() > 0.1:
		dir = input.normalized()
	elif not is_on_floor() and h.length() > 1.0:
		dir = h.normalized() # 空中では勢いの向きでも縁をつかむ
	if dir == Vector3.ZERO:
		return false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider()
		if body == null or not (int(body.get("collision_layer")) & WORLD_LAYER):
			continue
		var n := _flat_wall_normal(c.get_normal())
		if n == Vector3.ZERO or -dir.dot(n) < cos(deg_to_rad(LEDGE_MAX_ANGLE)):
			continue
		var ledge := _probe_ledge(c.get_position(), n)
		if ledge.is_empty():
			continue
		if is_on_floor() and ledge.height > Tuning.vault_max_height:
			continue # 地上から高い縁へは跳ばないと届かない
		_start_ledge(ledge, maxf(h.length(), horizontal_speed()))
		return true
	return false


## 壁走り中にスティックを壁へ倒すと、手の届く高さの壁の上へよじ登る。
func _try_wallrun_mantle() -> bool:
	if _input_direction().dot(-_wall_normal) < LEDGE_WALLRUN_INTO:
		return false
	var ledge := _probe_ledge(global_position - _wall_normal * _body_radius, _wall_normal)
	if ledge.is_empty():
		return false
	_wallrunning = false
	_start_ledge(ledge, _wall_along)
	return true


## 壁の面上の点 contact（法線 n）から、上面の高さと立てる位置を探す。なければ空。
func _probe_ledge(contact: Vector3, n: Vector3) -> Dictionary:
	var feet := global_position.y - STAND_HEIGHT * 0.5
	var top_y := feet + Tuning.mantle_max_height + 0.05
	var space := get_world_3d().direct_space_state
	# 手の届く高さより上まで壁が続いていたら縁はない
	var high := Vector3(global_position.x, top_y, global_position.z)
	var q := PhysicsRayQueryParameters3D.create(high, high - n * (_body_radius + LEDGE_PROBE_IN + 0.2), WORLD_LAYER)
	q.exclude = [get_rid()]
	if not space.intersect_ray(q).is_empty():
		return {}
	var probe := Vector3(contact.x, 0.0, contact.z) - n * LEDGE_PROBE_IN
	q = PhysicsRayQueryParameters3D.create(Vector3(probe.x, top_y, probe.z), Vector3(probe.x, feet + LEDGE_MIN, probe.z), WORLD_LAYER)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.7:
		return {}
	var top: float = hit.position.y
	var target := Vector3(probe.x, top + STAND_HEIGHT * 0.5 + 0.05, probe.z)
	if _overlaps_standing(target):
		return {} # 上に立つ場所がない
	return {"height": top - feet, "target": target, "edge": Vector3(contact.x, top, contact.z), "dir": -n}


func _start_ledge(ledge: Dictionary, speed: float) -> void:
	if _sliding:
		_end_slide()
	_ledge = Ledge.VAULT if ledge.height <= Tuning.vault_max_height else Ledge.MANTLE
	_ledge_time = Tuning.vault_time if _ledge == Ledge.VAULT else Tuning.mantle_time
	_ledge_t = 0.0
	_ledge_from = global_position
	_ledge_to = ledge.target
	_ledge_dir = ledge.dir
	# 左手は縁の、体の中心より少し左につく
	_ledge_edge = ledge.edge + _ledge_dir.cross(Vector3.UP) * -0.12
	var exit_speed := maxf(speed, LEDGE_EXIT_MIN)
	_ledge_exit = _ledge_dir * exit_speed
	velocity = Vector3.ZERO
	_rising_from_jump = false
	_jump_buffer_timer = 0.0


## 先に上がり、上がりきる頃に前へ出る。縁の角を体が通り抜けないようにする。
func _apply_ledge(delta: float) -> void:
	_ledge_t += delta
	var x := clampf(_ledge_t / maxf(_ledge_time, 0.001), 0.0, 1.0)
	var up := 1.0 - pow(1.0 - minf(1.0, x / 0.6), 2.0)
	var fwd := smoothstep(0.35, 1.0, x)
	global_position = Vector3(
		lerpf(_ledge_from.x, _ledge_to.x, fwd),
		lerpf(_ledge_from.y, _ledge_to.y, up),
		lerpf(_ledge_from.z, _ledge_to.z, fwd))
	if x >= 1.0:
		_ledge = Ledge.NONE
		velocity = _ledge_exit
		_blocked_wall_normal = Vector3.ZERO
		_coyote_timer = Tuning.coyote_time # 上がった直後に跳べる
		move_and_slide()


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
	_eye = lerpf(_eye, EYE_SLIDE if _sliding else EYE_STAND, minf(1.0, 14.0 * delta))
	head.position.y = _eye
	if is_on_floor() and speed > 0.5 and Tuning.head_bob > 0.0 and not _sliding and _ledge == Ledge.NONE:
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
