class_name HandActions
extends Node
## 左手と右手のアクション。Player の子に置く。
## 左手（LB / Q / 右クリック）＝掴む：縁を掴んで登る（縁掴み）、縦のポールを掴んで回る（ポール回り）。
##   押しっぱなしにしておけば、届く縁やポールに来た瞬間に掴む。ポールは離すと手を放す。
## 右手（RB / E / 左クリック）＝押す：低い障害物に手をついて越える（ボールト）、壁を突き放す（壁押し）。
## 何もなければ空振り（手を伸ばして戻すだけ）。
## 縁掴み・ボールト・ポール回りの間は Player.take_control() で体の動きを預かる。
## 大原則どおり、どれも入る前の水平速度を出口へ持ち出す。

enum Side { LEFT, RIGHT }
enum Move { NONE, MANTLE, VAULT, POLE }

const WORLD_LAYER := 1
const FACE_MIN_DOT := 0.5 # 壁がこちらを向いている度合い。これより斜めの面は掴まない・越えない
const LEDGE_STEP := 0.2 # 縁を探すときに前へ飛ばす光線の間隔 (m)
const STAND_CLEAR := 0.95 # 縁の上に立つときの、上面から体の中心までの高さ
const PUSH_HOLD := 0.15 # 壁押しで手を壁に付けておく時間
const WHIFF_HOLD := 0.12

var move := Move.NONE
## テストと調整用。最後に出たアクションの名前（"ledge", "pole", "vault", "push", "whiff"）
var last_left := ""
var last_right := ""

var _player: Player
var _left_buffer := 0.0
var _right_buffer := 0.0
var _left_needs_release := false # 掴み終えたら、一度離すまで押しっぱなしでは掴まない
var _pushed_normal := Vector3.ZERO # 同じ壁は着地するまで1回だけ押せる
var _left_just_pressed := false
var _right_just_pressed := false

# 動作中の値
var _t := 0.0
var _duration := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _peak := 0.0
var _exit := Vector3.ZERO
var _prev_pos := Vector3.ZERO
var _pole: Node3D
var _pole_angle := 0.0
var _pole_dir := 1.0
var _pole_speed := 0.0
var _pole_r := 0.0
var _pole_vy := 0.0

# 手の見た目用。side → {point, palm, fingers, pose, time}
var _plants := {}


func _ready() -> void:
	_player = get_parent() as Player


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_read_input(delta)
	_age_plants(delta)
	if _player.is_on_floor():
		_pushed_normal = Vector3.ZERO
	if move != Move.NONE:
		return # 動作中は drive() が進める
	var left_held := _player.input_enabled and Input.is_action_pressed("hand_left")
	if not left_held:
		_left_needs_release = false
	if _left_buffer > 0.0 or (left_held and not _left_needs_release):
		if _try_ledge() or _try_pole():
			_left_buffer = 0.0
		elif _left_buffer > 0.0 and _left_just_pressed:
			_whiff(Side.LEFT)
			last_left = "whiff"
	if _right_buffer > 0.0:
		if _try_vault() or _try_wall_push():
			_right_buffer = 0.0
		elif _right_just_pressed:
			_whiff(Side.RIGHT)
			last_right = "whiff"



func _read_input(delta: float) -> void:
	var on := _player.input_enabled
	_left_just_pressed = on and Input.is_action_just_pressed("hand_left")
	_right_just_pressed = on and Input.is_action_just_pressed("hand_right")
	_left_buffer = Tuning.hand_buffer if _left_just_pressed else _left_buffer - delta
	_right_buffer = Tuning.hand_buffer if _right_just_pressed else _right_buffer - delta


## 手の見た目が向かう先。なければ空の辞書。
## point：手のひらの中心（ワールド）、palm：手のひらが向く向き、fingers：指先の向き、pose："grip" / "flat" / "open"
func plant(side: int) -> Dictionary:
	return _plants.get(side, {})


func is_busy() -> bool:
	return move != Move.NONE


## Player.respawn() から呼ばれる。
func cancel() -> void:
	move = Move.NONE
	_plants.clear()


## Player が体を預けている間、毎物理フレーム呼ぶ。
func drive(delta: float) -> void:
	_t += delta
	match move:
		Move.MANTLE:
			_drive_mantle()
		Move.VAULT:
			_drive_vault()
		Move.POLE:
			_drive_pole(delta)
	if move != Move.NONE and delta > 0.0:
		_player.velocity = (_player.global_position - _prev_pos) / delta
	_prev_pos = _player.global_position


# ---------- 左手：縁掴み ----------

## 前（壁走り・壁登り中は壁の側も）にある、手の届く縁を探して登る。
func _try_ledge() -> bool:
	var dirs: Array[Vector3] = []
	var wall := _player.wall_normal()
	if wall != Vector3.ZERO:
		dirs.append(-wall)
	dirs.append(_player.facing())
	var h := _hvel()
	if h.length() > 1.0:
		dirs.append(h.normalized())
	for dir in dirs:
		var ledge := find_ledge(dir)
		if not ledge.is_empty():
			_start_mantle(ledge)
			return true
	return false


## dir（水平・単位ベクトル）の先にある縁。{edge, normal, top}。なければ空。
func find_ledge(dir: Vector3) -> Dictionary:
	var feet := _player.feet_position()
	var reach := _player.body_radius() + Tuning.ledge_reach_dist
	var face := {}
	var y := Tuning.ledge_reach_bottom - 0.1
	while y <= Tuning.ledge_reach_top:
		face = _ray(feet + Vector3.UP * y, dir * reach)
		if not face.is_empty() and _faces(face.normal, dir):
			break
		face = {}
		y += LEDGE_STEP
	if face.is_empty():
		return {}
	var n := _flat(face.normal)
	var over: Vector3 = face.position - n * 0.15
	var top_hit := _ray(Vector3(over.x, feet.y + Tuning.ledge_reach_top + 0.3, over.z), Vector3.DOWN * (Tuning.ledge_reach_top + 0.3 - Tuning.ledge_reach_bottom))
	if top_hit.is_empty() or top_hit.normal.y < 0.7:
		return {}
	var top: float = top_hit.position.y
	var rise := top - feet.y
	if rise < Tuning.ledge_reach_bottom or rise > Tuning.ledge_reach_top:
		return {}
	var edge := Vector3(face.position.x, top, face.position.z)
	var stand := edge - n * (_player.body_radius() + 0.15) + Vector3.UP * STAND_CLEAR
	if not _player.can_stand_at(stand):
		return {}
	# 縁の上まで体を持ち上げる道が空いているか（頭の上に天井がないか）
	var center := _player.global_position
	if not _ray(center, Vector3.UP * maxf(0.0, stand.y - center.y)).is_empty():
		return {}
	return {"edge": edge, "normal": n, "top": top, "stand": stand}


func _start_mantle(ledge: Dictionary) -> void:
	var n: Vector3 = ledge.normal
	var entry := _player.carry_speed()
	var out := _player.facing()
	if out.dot(-n) < 0.3:
		out = -n
	_exit = out * maxf(entry * Tuning.mantle_keep, Tuning.mantle_min_exit)
	_from = _player.global_position
	_to = ledge.stand
	var rise := _to.y - _from.y
	_duration = Tuning.mantle_time * clampf(rise / 1.2, 0.6, 1.3)
	_begin(Move.MANTLE)
	last_left = "ledge"
	ParkourFeel.play("grab")
	var edge: Vector3 = ledge.edge
	_set_plant(Side.LEFT, edge - n * 0.06 + Vector3.UP * 0.03, Vector3.DOWN, -n, "grip", _duration + 0.05)


func _drive_mantle() -> void:
	var x := clampf(_t / _duration, 0.0, 1.0)
	# 先に引き上げ（0〜0.65）、上がり切る手前から前へ（0.35〜1）
	var up := 1.0 - pow(1.0 - minf(1.0, x / 0.65), 2.0)
	var fwd := smoothstep(0.35, 1.0, x)
	var p := Vector3(lerpf(_from.x, _to.x, fwd), lerpf(_from.y, _to.y, up), lerpf(_from.z, _to.z, fwd))
	_player.global_position = p
	if x >= 1.0:
		_finish(_exit)


# ---------- 左手：ポール回り ----------

func _try_pole() -> bool:
	var best: Node3D = null
	var best_d := INF
	var pos := _player.global_position
	var feet := _player.feet_position()
	for node in get_tree().get_nodes_in_group("pole"):
		var pole := node as Node3D
		if pole == null:
			continue
		var half := _pole_half_height(pole)
		var base := pole.global_position
		if feet.y < base.y - half - 0.5 or feet.y > base.y + half - 0.5:
			continue
		var d := Vector2(pos.x - base.x, pos.z - base.z).length()
		if d <= Tuning.pole_reach and d < best_d:
			best = pole
			best_d = d
	if best == null:
		return false
	_start_pole(best)
	return true


func _pole_half_height(pole: Node3D) -> float:
	var h = pole.get("height")
	return float(h) * 0.5 if h != null else 2.0


func _start_pole(pole: Node3D) -> void:
	_pole = pole
	var rel := _player.global_position - pole.global_position
	var r := Vector2(rel.x, rel.z)
	if r.length() < 0.05:
		r = Vector2(-_player.facing().x, -_player.facing().z) * 0.3
	_pole_angle = atan2(r.y, r.x)
	_pole_r = r.length()
	var h := _hvel()
	var v := Vector2(h.x, h.z)
	if v.length() < 0.5:
		v = Vector2(_player.facing().x, _player.facing().z)
	# 今の動きに沿う向きへ回る。r × v の符号で決める
	_pole_dir = 1.0 if r.cross(v) >= 0.0 else -1.0
	_pole_speed = maxf(h.length(), Tuning.pole_min_speed)
	_pole_vy = minf(_player.velocity.y, 1.0)
	_duration = Tuning.pole_max_time
	_begin(Move.POLE)
	last_left = "pole"
	ParkourFeel.play("grab")
	_update_pole_plant()


func _drive_pole(delta: float) -> void:
	var held := _player.input_enabled and Input.is_action_pressed("hand_left")
	var jumped := _player.input_enabled and Input.is_action_just_pressed("jump")
	_pole_r = move_toward(_pole_r, Tuning.pole_radius, 4.0 * delta)
	var step := _pole_dir * _pole_speed / maxf(_pole_r, 0.1) * delta
	_pole_angle += step
	_pole_vy -= Tuning.gravity * Tuning.pole_gravity_mult * delta
	var base := _pole.global_position
	var half := _pole_half_height(_pole)
	var p := Vector3(base.x + cos(_pole_angle) * _pole_r, _player.global_position.y + _pole_vy * delta, base.z + sin(_pole_angle) * _pole_r)
	p.y = clampf(p.y, base.y - half + 0.9, base.y + half + 0.4)
	var tangent := Vector3(-sin(_pole_angle), 0.0, cos(_pole_angle)) * _pole_dir
	if not _player.can_stand_at(p):
		_release_pole(tangent, false)
		return
	_player.global_position = p
	# rotate_y(a) は atan2(z, x) の角度を -a 動かすので、符号を反転して回る分だけ視点も回す
	_player.turn(-step * Tuning.pole_camera_follow)
	_update_pole_plant()
	if jumped or not held or _t >= _duration:
		_release_pole(tangent, jumped)


func _release_pole(tangent: Vector3, jumped: bool) -> void:
	var out := tangent * (_pole_speed + Tuning.pole_release_boost)
	out.y = maxf(Tuning.pole_release_up, Tuning.jump_velocity if jumped else 0.0)
	_finish(out)


func _update_pole_plant() -> void:
	var base := _pole.global_position
	var to_pole := Vector3(base.x, 0.0, base.z) - Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	to_pole = to_pole.normalized() if to_pole.length() > 0.01 else _player.facing()
	var radius := float(_pole.get("radius")) if _pole.get("radius") != null else 0.1
	var point := Vector3(base.x, _player.global_position.y + 0.45, base.z) - to_pole * (radius + 0.04)
	_set_plant(Side.LEFT, point, to_pole, Vector3.UP.cross(to_pole) * _pole_dir, "grip", 0.08)


# ---------- 右手：ボールト ----------

## 前の低い障害物に手をついて越える。奥が深ければその上に乗る。
func _try_vault() -> bool:
	var dirs: Array[Vector3] = [_player.facing()]
	var h := _hvel()
	if h.length() > 1.0:
		dirs.push_front(h.normalized())
	for dir in dirs:
		var v := find_vault(dir)
		if not v.is_empty():
			_start_vault(v)
			return true
	return false


## {face, normal, top, end}。なければ空。
func find_vault(dir: Vector3) -> Dictionary:
	var feet := _player.feet_position()
	var reach := _player.body_radius() + Tuning.vault_reach
	var face := _ray(feet + Vector3.UP * (Tuning.vault_min_height + 0.05), dir * reach)
	if face.is_empty() or not _faces(face.normal, dir):
		return {}
	var n := _flat(face.normal)
	var probe_top := feet.y + Tuning.vault_max_height + 0.4
	var near: Vector3 = face.position - n * 0.1
	var top_hit := _ray(Vector3(near.x, probe_top, near.z), Vector3.DOWN * (probe_top - feet.y - 0.05))
	if top_hit.is_empty() or top_hit.normal.y < 0.7:
		return {}
	var top: float = top_hit.position.y
	var height := top - feet.y
	if height < Tuning.vault_min_height or height > Tuning.vault_max_height:
		return {}
	# 奥行きを測る：上面が続く間は前へ。1.6mを超えたら「上に乗る」
	var depth := 0.0
	var over := false
	while depth < 1.6:
		depth += 0.2
		var p: Vector3 = face.position - n * depth
		var hit := _ray(Vector3(p.x, top + 0.3, p.z), Vector3.DOWN * 0.45)
		if hit.is_empty() or absf(hit.position.y - top) > 0.1:
			over = true
			break
	var r := _player.body_radius()
	var end: Vector3
	if over:
		end = face.position - n * (depth + r + 0.25)
		end.y = maxf(top + STAND_CLEAR * 0.6, _player.global_position.y)
	else:
		end = face.position - n * (r + 0.5)
		end.y = top + STAND_CLEAR
	var mid: Vector3 = face.position - n * minf(depth, 0.8) * 0.5
	mid.y = top + STAND_CLEAR
	if not _player.can_stand_at(end) or not _player.can_stand_at(mid):
		return {}
	return {"face": face.position, "normal": n, "top": top, "end": end, "over": over}


func _start_vault(v: Dictionary) -> void:
	var n: Vector3 = v.normal
	var entry := _hvel().length()
	_exit = -n * maxf(entry + Tuning.vault_boost, Tuning.vault_min_exit)
	_from = _player.global_position
	_to = v.end
	var top: float = v.top
	# 障害物の上を体の中心が上面＋STAND_CLEARで通るよう、弧の高さを決める
	_peak = maxf(0.0, top + STAND_CLEAR - lerpf(_from.y, _to.y, 0.5)) + 0.05
	var dist := Vector2(_to.x - _from.x, _to.z - _from.z).length()
	_duration = clampf(dist / maxf(entry, 1.0), 0.15, Tuning.vault_time)
	_begin(Move.VAULT)
	last_right = "vault"
	ParkourFeel.play("plant")
	var face: Vector3 = v.face
	var hand := Vector3(face.x, top + 0.03, face.z) - n * 0.2
	_set_plant(Side.RIGHT, hand, Vector3.DOWN, -n, "flat", _duration * 0.7)


func _drive_vault() -> void:
	var x := clampf(_t / _duration, 0.0, 1.0)
	var p := _from.lerp(_to, x)
	p.y += _peak * sin(PI * x)
	_player.global_position = p
	if x >= 1.0:
		_finish(_exit)


# ---------- 右手：壁押し ----------

## 横や前の壁を突き放して、壁から離れる向きへ加速する。壁沿いの勢いは保つ。
func _try_wall_push() -> bool:
	var hit := _find_push_wall()
	if hit.is_empty():
		return false
	var n: Vector3 = hit.normal
	var v := _player.velocity
	var along := _player.wall_direction()
	if along != Vector3.ZERO:
		# 壁走り中は、押し付けていた分を除いた壁沿いの速さで出る
		v = along * _hvel().dot(along) + Vector3.UP * v.y
	var into := v.dot(n)
	if into < 0.0:
		v -= n * into
	v += n * Tuning.wall_push_speed
	v.y = maxf(v.y, Tuning.wall_push_up)
	_player.leave_wall(n)
	_player.velocity = v
	_pushed_normal = n
	last_right = "push"
	ParkourFeel.play("plant")
	var p: Vector3 = hit.position
	_set_plant(Side.RIGHT, p + n * 0.04, -n, Vector3.UP, "flat", PUSH_HOLD)
	return true


func _find_push_wall() -> Dictionary:
	var center := _player.global_position + Vector3.UP * 0.3
	var wall := _player.wall_normal()
	var reach := _player.body_radius() + Tuning.wall_push_reach
	if wall != Vector3.ZERO and wall.dot(_pushed_normal) < 0.9:
		var hit := _ray(center, -wall * reach)
		if not hit.is_empty():
			return {"position": hit.position, "normal": wall}
	var f := _player.facing()
	var r := f.cross(Vector3.UP)
	var best := {}
	var best_d := INF
	for dir in [r, -r, f, (f + r).normalized(), (f - r).normalized()]:
		var hit := _ray(center, dir * reach)
		if hit.is_empty():
			continue
		var n := _flat(hit.normal)
		if n == Vector3.ZERO or n.dot(_pushed_normal) > 0.9:
			continue
		var d: float = center.distance_to(hit.position)
		if d < best_d:
			best_d = d
			best = {"position": hit.position, "normal": n}
	return best


# ---------- 共通 ----------

func _whiff(side: int) -> void:
	ParkourFeel.play("whiff")
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var b := cam.global_transform.basis
	var x := -0.18 if side == Side.LEFT else 0.18
	var p := cam.global_position - b.z * 0.62 + b.x * x - b.y * 0.05
	_set_plant(side, p, -b.z, (-b.z + b.y * 0.4).normalized(), "open", WHIFF_HOLD)


func _begin(m: int) -> void:
	move = m
	_t = 0.0
	_prev_pos = _player.global_position
	_player.take_control(self)


func _finish(exit_velocity: Vector3) -> void:
	# 左手で掴み終えたら、一度離すまで押しっぱなしでは掴まない。ボールトは右手なので左手はそのまま
	if move != Move.VAULT:
		_left_needs_release = true
	# 縁の上・障害物の上からは足場を蹴って跳べる。ポールは離すときに自分でジャンプを見る
	var grounded := move != Move.POLE
	move = Move.NONE
	_player.release_control(exit_velocity, grounded)


func _set_plant(side: int, point: Vector3, palm: Vector3, fingers: Vector3, pose: String, hold: float) -> void:
	_plants[side] = {"point": point, "palm": palm.normalized(), "fingers": fingers.normalized(), "pose": pose, "time": hold}


func _age_plants(delta: float) -> void:
	for side in _plants.keys():
		_plants[side].time -= delta
		if _plants[side].time <= 0.0:
			_plants.erase(side)


func _hvel() -> Vector3:
	return Vector3(_player.velocity.x, 0.0, _player.velocity.z)


func _ray(from: Vector3, motion: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + motion, WORLD_LAYER)
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(query)


func _flat(n: Vector3) -> Vector3:
	if absf(n.y) > 0.3:
		return Vector3.ZERO
	return Vector3(n.x, 0.0, n.z).normalized()


func _faces(n: Vector3, dir: Vector3) -> bool:
	var f := _flat(n)
	return f != Vector3.ZERO and f.dot(-dir) >= FACE_MIN_DOT
