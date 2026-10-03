class_name Player
extends CharacterBody3D
## 一人称プレイヤー。M1：走り・ジャンプ・コヨーテタイム・先行入力。M2：壁走り（方向転換・壁ジャンプ）。M3：画面揺れ。
## 追加：よじ登り・スーパーグライド・スライディング。
## 大原則：動作を切り替えても水平方向の速度を落とさない（よじ登りだけは壁に止められた分が落ちる）。

## 動きの技の結果（スーパーグライドの成否と間の長さなど）。HUDが表示する
signal move_tech(text: String, success: bool)

const PITCH_LIMIT := deg_to_rad(89.0)
const BOB_FREQ := 1.6 # 1mあたりの揺れの位相（ラジアン）
const RESPAWN_Y := -20.0
const WALL_REACH := 0.5 # 体の表面から何mまでの壁を壁走りの対象にするか
const WALL_MAX_NORMAL_Y := 0.3 # 法線がこれより上下を向いていたら壁とみなさない
const WALL_STICK := 1.0 # 壁走り中に壁へ押し付ける速度 (m/s)
const WALL_PUSH_OFF := 1.0 # 時間切れで壁から離れるときの速度 (m/s)
const WALL_JUMP_MIN_OUT := 0.35 # スティックで向きを決めても、壁から離れる成分はこれ以上残す
const WORLD_LAYER := 1 # 壁走りの対象にする層。ダミー（層2）では壁走りしない
const MANTLE_REACH := 0.4 # 体の表面から何m先の壁までよじ登りの対象にするか
const MANTLE_MIN_HEIGHT := 0.3 # これより低い段差はよじ登らない（足から測る）
const MANTLE_DEPTH := 0.3 # 段差の上面を探す位置：壁の面から奥へ
const MANTLE_FACING := 0.8 # 壁へ向けた入力がこれ以上正面（cos）のときだけよじ登る
const MANTLE_RISE := 0.6 # よじ登りのうち、体を持ち上げる時間の割合。残りで縁を越える
const GLIDE_HINT_TIME := 0.3 # これ以内のずれなら、スーパーグライドの失敗として何が悪かったかを出す

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

var _time := 0.0 # 物理の時計（入力を押した時刻を比べるのに使う）
var _jump_at := -INF
var _crouch_at := -INF

var _mantling := false
var _mantle_t := 0.0
var _mantle_dir := Vector3.ZERO # 登る向き（水平・単位ベクトル。壁へ向かう向き）
var _mantle_from := Vector3.ZERO
var _mantle_top := 0.0 # 持ち上げ終わったときの体の中心の高さ（足が縁を越える）
var _mantle_to := Vector3.ZERO # 登り終わりの体の中心
var _glide_open := -INF # スーパーグライドの受付（縁を越え始めてから、登り切った少し後まで）
var _glide_close := -INF
var _glide_upgrade_until := -INF # 受付中にジャンプした直後。この時刻までにしゃがめばスーパーグライドになる
var _glide_reported := true # 1回のよじ登りで結果を1度だけ出す

var _sliding := false
var _slide_on_land := false # 空中でしゃがみを押した。着地したらスライディングに入る
var _was_on_floor := false
var _head_base := Vector3.ZERO
var _speed_fov := 0.0

var _trauma := 0.0 # 画面揺れの元。0〜1。揺れの大きさはこの2乗
var _shake_time := 0.0
var _roll := 0.0
var _noise := FastNoiseLite.new()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var _body_radius: float = ($Collision.shape as CapsuleShape3D).radius
@onready var _body_half: float = ($Collision.shape as CapsuleShape3D).height * 0.5


func _ready() -> void:
	_spawn_transform = global_transform
	_head_base = head.position
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
	_time += delta
	_update_timers(delta)
	_handle_glide_inputs()
	if _mantling:
		_apply_mantle(delta)
	elif _wallrunning:
		_apply_wallrun(delta)
		if _jump_buffer_timer > 0.0:
			_wall_jump(_wall_normal)
	else:
		_handle_crouch()
		_apply_gravity(delta)
		_try_jump()
		_apply_jump_cut()
		if _sliding:
			_apply_slide(delta)
		else:
			_apply_horizontal(delta)
	var before := velocity
	move_and_slide()
	if _mantling:
		_check_mantle_end()
	elif _wallrunning:
		_check_wallrun_end()
	elif not _try_start_mantle():
		_try_start_wallrun(before)
	_update_slide()
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
	_mantling = false
	_glide_close = -INF
	_glide_upgrade_until = -INF
	_sliding = false
	_slide_on_land = false
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


func is_mantling() -> bool:
	return _mantling


func is_sliding() -> bool:
	return _sliding


## いまスーパーグライドの受付中か（縁を越え始めてから、登り切った少し後まで）
func superglide_window() -> bool:
	return _in_glide_window()


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
	if input_enabled and Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = Tuning.jump_buffer
		_jump_at = _time
	else:
		_jump_buffer_timer -= delta
	if input_enabled and Input.is_action_just_pressed("crouch"):
		_crouch_at = _time


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
		# スライディング中に跳んでも水平の速さはそのまま（スライディングジャンプ）
		velocity.y = Tuning.jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_rising_from_jump = true
		_sliding = false
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
	# 跳んだフレームはまだ床の上と判定されるが、地上の減速はかけない（跳んだ瞬間に速さを落とさない）
	if is_on_floor() and velocity.y <= 0.0:
		rate = Tuning.ground_accel if input != Vector2.ZERO else Tuning.ground_decel
	else:
		rate = Tuning.air_accel if input != Vector2.ZERO else Tuning.air_decel
		# 空中では向きだけ変え、持ち込んだ速さは削らない
		if input != Vector2.ZERO and current.length() > target.length():
			target = target.normalized() * current.length()

	current = current.move_toward(target, rate * delta)
	velocity.x = current.x
	velocity.z = current.y


# ---------------------------------------------------------------- よじ登り・スーパーグライド

## 空中で、スティックを前の壁へ向けて倒していて、その壁の上に立てる段差が手の届く高さにあればよじ登る。
func _try_start_mantle() -> bool:
	if is_on_floor() or not input_enabled:
		return false
	var wish := _input_direction()
	if wish.length() < 0.5:
		return false
	wish = Vector3(wish.x, 0.0, wish.z).normalized()
	var space := get_world_3d().direct_space_state
	var feet := global_position.y - _body_half
	# 低い段差は体の中心より下にしかないので、膝の高さでも探る
	var wall := {}
	for y in [global_position.y, feet + MANTLE_MIN_HEIGHT + 0.1]:
		var from := Vector3(global_position.x, y, global_position.z)
		var ray := PhysicsRayQueryParameters3D.create(from, from + wish * (_body_radius + MANTLE_REACH), WORLD_LAYER)
		ray.exclude = [get_rid()]
		wall = space.intersect_ray(ray)
		if not wall.is_empty():
			break
	if wall.is_empty():
		return false
	var n := _flat_wall_normal(wall.normal)
	# 壁へほぼ正面から押しているときだけ。斜めなら壁走りに任せる
	if n == Vector3.ZERO or wish.dot(-n) < MANTLE_FACING:
		return false
	# 壁の少し奥を上から下へ探り、上面（立てる面）の高さを取る。上限より高い壁なら上から探っても壁の中で、当たらない
	var probe: Vector3 = wall.position - n * MANTLE_DEPTH
	var down := PhysicsRayQueryParameters3D.create(
		Vector3(probe.x, feet + Tuning.mantle_max_height + 0.05, probe.z),
		Vector3(probe.x, feet + MANTLE_MIN_HEIGHT, probe.z), WORLD_LAYER)
	down.exclude = [get_rid()]
	var top := space.intersect_ray(down)
	if top.is_empty() or top.normal.y < 0.7:
		return false
	var ledge: float = top.position.y
	# 登った先に体が収まるか
	var to := Vector3(probe.x, ledge + _body_half + 0.02, probe.z)
	var shape := PhysicsShapeQueryParameters3D.new()
	shape.shape = $Collision.shape
	shape.transform = Transform3D(Basis.IDENTITY, to)
	shape.collision_mask = WORLD_LAYER
	shape.exclude = [get_rid()]
	if not space.intersect_shape(shape, 1).is_empty():
		return false
	_start_mantle(-n, ledge, to)
	return true


func _start_mantle(dir: Vector3, ledge: float, to: Vector3) -> void:
	_mantling = true
	_mantle_t = 0.0
	_mantle_dir = dir
	_mantle_from = global_position
	_mantle_top = maxf(ledge + _body_half + 0.05, global_position.y)
	_mantle_to = to
	_glide_open = _time + Tuning.mantle_time * MANTLE_RISE
	_glide_close = _time + Tuning.mantle_time + Tuning.superglide_grace
	_glide_upgrade_until = -INF
	_glide_reported = false
	_jump_buffer_timer = 0.0 # 登っている途中に押したジャンプで、登り切った瞬間に跳ばない
	_rising_from_jump = false
	_sliding = false
	_slide_on_land = false


## 体を真上へ持ち上げてから、縁の向こうへ運ぶ。目標の位置を追う速度にしてmove_and_slideで動かす。
func _apply_mantle(delta: float) -> void:
	_mantle_t += delta
	var rise := Tuning.mantle_time * MANTLE_RISE
	var target: Vector3
	if _mantle_t < rise:
		var x := smoothstep(0.0, 1.0, _mantle_t / rise)
		target = Vector3(_mantle_from.x, lerpf(_mantle_from.y, _mantle_top, x), _mantle_from.z)
	else:
		var x := smoothstep(0.0, 1.0, minf(1.0, (_mantle_t - rise) / maxf(Tuning.mantle_time - rise, 0.001)))
		var over_from := Vector3(_mantle_from.x, _mantle_top, _mantle_from.z)
		target = over_from.lerp(_mantle_to, x)
	velocity = (target - global_position) / delta


func _check_mantle_end() -> void:
	if _mantle_t >= Tuning.mantle_time:
		_mantling = false
		velocity = _mantle_dir * Tuning.mantle_exit_speed
		apply_floor_snap() # 登った面にすぐ立たせる


func _in_glide_window() -> bool:
	return _time >= _glide_open and _time <= _glide_close


## スーパーグライド：よじ登りで縁を越える間（と登り切った少し後）に、ジャンプとしゃがみをほぼ同時に押す。
## どちらが先でもよく、間がsuperglide_gap以内なら成功。ジャンプだけなら普通に跳ぶ（よじ登りジャンプ）。
func _handle_glide_inputs() -> void:
	if not input_enabled:
		return
	var jumped := _jump_at == _time
	var crouched := _crouch_at == _time
	if not (jumped or crouched):
		_report_glide_miss()
		return
	if jumped and _mantling and _time < _glide_open:
		_jump_buffer_timer = 0.0
		_report_glide("早すぎ：縁を越え始めるまで %d ms 待つ" % _ms(_glide_open - _time), false)
		return
	if crouched and _time <= _glide_upgrade_until:
		_superglide(_time - _jump_at)
	elif jumped and _in_glide_window():
		var gap := _time - _crouch_at
		if gap <= Tuning.superglide_gap:
			_superglide(gap)
		else:
			_mantle_jump()
			_glide_upgrade_until = _time + Tuning.superglide_gap
			if gap <= GLIDE_HINT_TIME:
				_report_glide("しゃがみが %d ms 早い（%d ms以内）" % [_ms(gap), _ms(Tuning.superglide_gap)], false)
	elif crouched and _time - _jump_at <= GLIDE_HINT_TIME and _jump_at >= _glide_open and _jump_at <= _glide_close:
		_report_glide("しゃがみが %d ms 遅い（%d ms以内）" % [_ms(_time - _jump_at), _ms(Tuning.superglide_gap)], false)


## よじ登りの受付を何も押さずに過ぎたとき、少し遅れて押していたら「遅すぎ」と出す
func _report_glide_miss() -> void:
	if _glide_reported or _time <= _glide_close:
		return
	var late := maxf(_jump_at, _crouch_at) - _glide_close
	if late > 0.0 and late <= GLIDE_HINT_TIME:
		_report_glide("遅すぎ：登り切ってから %d ms 以内" % _ms(Tuning.superglide_grace), false)
	elif _time - _glide_close > GLIDE_HINT_TIME:
		_glide_reported = true


func _mantle_jump() -> void:
	_mantling = false
	_glide_close = minf(_glide_close, _time) # 跳んだら受付を閉じる（空中でもう一度跳べないように）
	var h := _glide_direction() * maxf(Tuning.mantle_exit_speed, horizontal_speed())
	velocity = Vector3(h.x, Tuning.jump_velocity, h.z)
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_rising_from_jump = true


func _superglide(gap: float) -> void:
	_mantling = false
	_glide_close = minf(_glide_close, _time)
	_glide_upgrade_until = -INF
	var h := _glide_direction() * maxf(Tuning.superglide_speed, horizontal_speed())
	velocity = Vector3(h.x, Tuning.superglide_up, h.z)
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_rising_from_jump = false
	_slide_on_land = true # しゃがんだまま着地してスライディングへつなぐ
	_report_glide("スーパーグライド！（間 %d ms）" % _ms(absf(gap)), true)
	HitFeel.on_superglide()


## スティックを倒していればその向き、倒していなければ登った向きへ飛ぶ
func _glide_direction() -> Vector3:
	var wish := _input_direction()
	wish.y = 0.0
	return wish.normalized() if wish.length() > 0.1 else _mantle_dir


func _report_glide(text: String, success: bool) -> void:
	_glide_reported = true
	move_tech.emit(text, success)


func _ms(seconds: float) -> int:
	return roundi(seconds * 1000.0)


# ---------------------------------------------------------------- スライディング

## しゃがみ：走っていればスライディング。スライディング中なら立つ。空中なら着地でスライディングに入る予約。
func _handle_crouch() -> void:
	if _crouch_at != _time or _time <= _glide_close + Tuning.superglide_gap:
		return
	if _sliding:
		_sliding = false
	elif is_on_floor():
		if horizontal_speed() >= Tuning.slide_min_speed:
			_sliding = true
	else:
		_slide_on_land = true


## スライディング：入力では加速しない。速さはslide_frictionでゆっくり落ち、向きはスティックで少しだけ曲げられる。
func _apply_slide(delta: float) -> void:
	var h := Vector2(velocity.x, velocity.z)
	var speed := h.length()
	if speed < 0.01:
		return
	var dir := h / speed
	var wish := _input_direction()
	if wish.length() > 0.1:
		dir = dir.move_toward(Vector2(wish.x, wish.z).normalized(), Tuning.slide_steer * delta).normalized()
	speed = maxf(0.0, speed - Tuning.slide_friction * delta)
	velocity.x = dir.x * speed
	velocity.z = dir.y * speed


func _update_slide() -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and _slide_on_land:
		_slide_on_land = false
		if horizontal_speed() >= Tuning.slide_min_speed:
			_sliding = true
	if _sliding and (not on_floor or horizontal_speed() < Tuning.slide_end_speed):
		_sliding = false # 空中へ出ても速さは保つ
	if on_floor and not _sliding and velocity.y <= 0.0: # 跳んだフレームはまだ床の上と判定される
		_slide_on_land = false
	_was_on_floor = on_floor


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
	_wallrunning = false
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


func _update_camera(delta: float) -> void:
	var speed := horizontal_speed()
	# 最高速度を超えた分だけ視野を広げ、速さを感じさせる（スーパーグライドで最大）
	var over := clampf((speed - Tuning.max_speed) / maxf(Tuning.superglide_speed - Tuning.max_speed, 0.01), 0.0, 1.0)
	_speed_fov = lerpf(_speed_fov, Tuning.speed_fov * over, minf(1.0, 8.0 * delta))
	camera.fov = Tuning.fov + _speed_fov
	var drop := Tuning.slide_camera_drop if _sliding else 0.0
	head.position.y = lerpf(head.position.y, _head_base.y - drop, minf(1.0, 12.0 * delta))
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
