class_name Weapon
extends Node3D
## 一人称の手と武器。通常攻撃（X / 左クリック）の振り、当たり判定、伸び縮み、壁へのめり込み防止、
## ナイフ回し（Y / F）。M4：アナログ斬り（RT / 右クリックを押しながら右スティック / マウスを弾く）。
## 手は Swing/HandModel（骨入りのメカの手）、武器は Swing/Grip の下に置く。
## res://models/weapon.glb があればそれを、なければ箱の剣を使う。
## 当たり判定は見た目のメッシュを使わず、Swing の前(-Z)へ伸ばした細長い箱で取る。

enum State { IDLE, WINDUP, ACTIVE, RECOVERY, INSPECT }

# 指の曲げ角（度）。各指は付け根・中・先の3関節。正で手のひら側へ曲がる
const CURL_GRIP := {
	"index": [80.0, 95.0, 55.0], "middle": [80.0, 95.0, 55.0], "ring": [82.0, 95.0, 55.0],
	"pinky": [85.0, 95.0, 55.0], "thumb": [25.0, 45.0, 40.0],
}
# ナイフを回している間：人差し指は輪に通したまま、ほかの指を開いて刃の通り道を空ける
const CURL_SPIN := {
	"index": [70.0, 90.0, 50.0], "middle": [15.0, 10.0, 5.0], "ring": [20.0, 10.0, 5.0],
	"pinky": [25.0, 10.0, 5.0], "thumb": [5.0, 10.0, 10.0],
}
const INSPECT_TIME := 1.0
const SPIN_TURNS := 2.0
const POSE_INSPECT := Vector3(8.0, 12.0, 30.0) # 回す間は少し持ち上げ、ひねって見せる

const MODEL_PATH := "res://models/weapon.glb"
const HURTBOX_LAYER := 2 # ダミーなど、斬られる側の当たり判定の層
const HIT_THICKNESS := 0.35
const RETRACT_REACH := 1.0 # 目の前の壁がこれより近いと武器を引っ込める (m)
const RETRACT_MAX := 0.45
const SQUASH_STIFFNESS := 300.0
const SQUASH_DAMPING := 18.0

# 振りの姿勢（度）：x=刃先の上下、y=刃先の左右（正で左）、z=ひねり
# 肘（拳の後ろ ELBOW の位置）を中心に回すので、前腕は肘の方を向いたまま拳が弧を描く
const POSE_IDLE := Vector3(15.0, 10.0, 0.0)
const POSE_WINDUP := Vector3(5.0, -60.0, -80.0) # 右から左へ振るときの構え。左から振るときは左右を反転
const POSE_FOLLOW := Vector3(-5.0, 60.0, -80.0)
const ELBOW := Vector3(0.0, 0.0, 0.35)
const SLASH_WINDUP := 0.03 # アナログ斬りはスティックを弾く動きが振りかぶりなので短い
const MOUSE_RETURN := 6.0 # マウスで動かした仮想スティックが中心へ戻る速さ (/秒)

## Meshyのモデルを読み込んだとき、長さと向きを自動で合わせる。Gripの位置と向きは手で微調整する
@export var auto_fit := true
## 自動で合わせた結果、柄と刃先が逆になっていたらオンにする
@export var flip_model := false
## Meshyのモデルを合わせるときの、柄頭から刃先までの長さ (m)
@export var model_length := 1.12
## 握る位置から柄頭までの長さ (m)
@export var grip_back := 0.12
## 判定の箱の長さ (m)。見た目の刃より少し長くして当てやすくする
@export var hit_length := 1.4

var state := State.IDLE
var swing_count := 0
var inspect_count := 0
var slash_count := 0
## 直前のアナログ斬り：dir（画面上の向き、上が+y）、strength（0〜1）、roll（振りの面の傾き、ラジアン）、at（msec）
var last_slash := {}
var using_model := false

var _t := 0.0
var _buffer := 0.0
var _sign := 1.0 # 1：右から左へ、-1：左から右へ。1振りごとに入れ替える
var _from := POSE_IDLE
var _pose := POSE_IDLE
var _hit_ids := {}
var _retract := 0.0
var _squash := 0.0
var _squash_vel := 0.0
var _base_position: Vector3
var _player: Player
var _grip_rest: Transform3D
var _spin_pivot := Vector3.ZERO # ナイフを回す軸（輪の中心）。Gripの座標
var _spin := 0.0 # ナイフの回転（ラジアン）
var _open := 0.0 # 指の開き。0で握る、1でナイフ回しの形
var _skeleton: Skeleton3D
var _analog := false # いまの振りがアナログ斬りか
var _slash_dir := Vector2.ZERO
var _slash_strength := 0.0
var _roll := 0.0 # 振りの面を視線の軸まわりに傾ける角度
var _roll_from := 0.0
var _roll_target := 0.0
var _flick := FlickDetector.new()
var _slash_buffer := 0.0
var _pending_slash := {}
var _mouse_stick := Vector2.ZERO
var _stick := Vector2.ZERO

@onready var swing: Node3D = $Swing
@onready var grip: Node3D = $Swing/Grip


func _ready() -> void:
	_base_position = position
	_player = _find_player()
	_grip_rest = grip.transform
	_spin_pivot = Vector3(0.0, 0.0, grip_back - 0.02)
	if ResourceLoader.exists(MODEL_PATH):
		_use_model(load(MODEL_PATH))
	var skels := find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skeleton = skels[0]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and slash_mode_active():
		# マウスは仮想スティックとして扱う。素早く動かすと端まで届いて弾きになる
		_mouse_stick = (_mouse_stick + event.relative / maxf(Tuning.slash_mouse_px, 1.0)).limit_length(1.0)


func _physics_process(delta: float) -> void:
	if _player and _player.input_enabled and Input.is_action_just_pressed("attack"):
		_buffer = Tuning.attack_buffer
	else:
		_buffer -= delta
	_read_flick(delta)
	var can_start := state == State.IDLE or state == State.RECOVERY or state == State.INSPECT
	if _slash_buffer > 0.0 and can_start:
		_slash_buffer = 0.0
		_buffer = 0.0
		_start_slash(_pending_slash.dir, _pending_slash.strength)
	elif _buffer > 0.0 and can_start:
		_buffer = 0.0
		_start_swing() # ナイフ回しの途中でも攻撃を優先する
	elif state == State.IDLE and _player and _player.input_enabled and Input.is_action_just_pressed("inspect"):
		_start_inspect()
	_advance(delta)
	if state == State.ACTIVE:
		_check_hits()
	_update_squash(delta)
	_update_retract(delta)
	_apply_pose()
	_apply_hand()


func is_attacking() -> bool:
	return state == State.WINDUP or state == State.ACTIVE or state == State.RECOVERY


func is_inspecting() -> bool:
	return state == State.INSPECT


func is_slashing() -> bool:
	return _analog and is_attacking()


func slash_mode_active() -> bool:
	return _player != null and _player.slash_mode()


## 斬撃モード中のスティック（マウスの仮想スティックを足したもの）。右が+x、下が+y。HUD用
func slash_stick() -> Vector2:
	return _stick


## 斬撃モードの間、スティックの弾きを見つけてアナログ斬りを出す（振っている途中なら先行入力にする）。
func _read_flick(delta: float) -> void:
	_mouse_stick = _mouse_stick.move_toward(Vector2.ZERO, MOUSE_RETURN * delta)
	_slash_buffer -= delta
	if not slash_mode_active():
		_flick.reset()
		_mouse_stick = Vector2.ZERO
		_stick = Vector2.ZERO
		return
	var v := Input.get_vector("look_left", "look_right", "look_up", "look_down", Tuning.stick_deadzone)
	_stick = (v + _mouse_stick).limit_length(1.0)
	var f := _flick.feed(_stick, delta, Tuning.slash_window)
	if f.is_empty():
		return
	var strength := clampf(f.speed / maxf(Tuning.slash_full_speed, 0.01), 0.0, 1.0)
	_pending_slash = {"dir": f.dir, "strength": strength}
	_slash_buffer = Tuning.attack_buffer


## 判定の箱のワールド座標での姿勢。握る位置から Swing の前(-Z)へ伸ばす。
func hitbox_transform() -> Transform3D:
	var g := swing.global_transform.orthonormalized()
	return Transform3D(g.basis, g * Vector3(0.0, 0.0, -hit_length * 0.5))


## ナイフ回し：輪に通した人差し指を軸に、ナイフを2回転させて握り直す。
func _start_inspect() -> void:
	inspect_count += 1
	_from = _pose
	_t = 0.0
	state = State.INSPECT


## アナログ斬り：dirは画面上で刃を動かす向き（上が+y）、strengthは弾きの強さ（0〜1）。
## 通常攻撃の振り（右から左）を、視線の軸まわりに傾けて dir の向きにする。手首が裏返らないよう、
## 右へ斬るときは左から右の振りを使い、傾きは±90度に収める。
func _start_slash(dir: Vector2, strength: float) -> void:
	slash_count += 1
	_begin_swing(1.0 if dir.x <= 0.0 else -1.0)
	_analog = true
	_slash_dir = dir
	_slash_strength = strength
	# 右から左の振り(-1, 0)を角度rollだけ反時計回りに回すと(-cos, -sin)、左から右なら(cos, sin)
	_roll_target = atan2(-dir.y, -dir.x) if _sign > 0.0 else atan2(dir.y, dir.x)
	last_slash = {"dir": dir, "strength": strength, "roll": _roll_target, "at": Time.get_ticks_msec()}


func _start_swing() -> void:
	swing_count += 1
	_begin_swing(-_sign if swing_count > 1 else 1.0)


func _begin_swing(sign_: float) -> void:
	_sign = sign_
	_analog = false
	_roll_from = _roll
	_roll_target = 0.0
	_hit_ids.clear()
	_from = _pose
	_t = 0.0
	_spin = 0.0 # 回している途中なら握り直してから振る
	_open = 0.0
	state = State.WINDUP


func _advance(delta: float) -> void:
	if state == State.IDLE:
		_pose = POSE_IDLE
		_roll = 0.0
		return
	_t += delta
	var windup := _mirror(POSE_WINDUP)
	var follow := _mirror(POSE_FOLLOW)
	var windup_time := SLASH_WINDUP if _analog else Tuning.attack_windup
	var active_time := _active_time()
	match state:
		State.WINDUP:
			var x := _ratio(windup_time)
			_pose = _from.lerp(windup, _ease_out(x))
			_roll = lerp_angle(_roll_from, _roll_target, _ease_out(x))
			if x >= 1.0:
				_next(State.ACTIVE)
				HitFeel.play_swing()
		State.ACTIVE:
			# 判定の間は一定の速さで振り抜く
			_pose = windup.lerp(follow, _ratio(active_time))
			_roll = _roll_target
			if _t >= active_time:
				_next(State.RECOVERY)
		State.RECOVERY:
			var x := _ratio(Tuning.attack_recovery)
			_pose = follow.lerp(POSE_IDLE, smoothstep(0.0, 1.0, x))
			_roll = lerp_angle(_roll_target, 0.0, smoothstep(0.0, 1.0, x))
			if x >= 1.0:
				_analog = false
				_next(State.IDLE)
		State.INSPECT:
			var x := _ratio(INSPECT_TIME)
			# 指を開く(0〜0.15) → 回す(0.1〜0.8) → 握り直す(0.75〜1.0)
			_open = smoothstep(0.0, 0.15, x) * (1.0 - smoothstep(0.75, 1.0, x))
			_spin = TAU * SPIN_TURNS * smoothstep(0.1, 0.8, x)
			var lift := sin(PI * x)
			_pose = _from.lerp(POSE_IDLE, minf(1.0, x * 4.0)).lerp(POSE_INSPECT, lift)
			if x >= 1.0:
				_spin = 0.0
				_open = 0.0
				_next(State.IDLE)


## 判定の時間。アナログ斬りは強く弾くほど速く振り抜く。
func _active_time() -> float:
	if not _analog:
		return Tuning.attack_active
	return lerpf(Tuning.slash_active_slow, Tuning.slash_active_fast, _slash_strength)


func _next(s: State) -> void:
	state = s
	_t = 0.0


func _ratio(duration: float) -> float:
	return 1.0 if duration <= 0.0 else clampf(_t / duration, 0.0, 1.0)


func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)


func _mirror(p: Vector3) -> Vector3:
	return p if _sign > 0.0 else Vector3(p.x, -p.y, -p.z)


func _check_hits() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(HIT_THICKNESS, HIT_THICKNESS, hit_length)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = hitbox_transform()
	query.collision_mask = HURTBOX_LAYER
	if _player:
		query.exclude = [_player.get_rid()]
	for result in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var target: Object = result.collider
		if target == null or not target.has_method("take_hit"):
			continue
		var id := target.get_instance_id()
		if _hit_ids.has(id):
			continue # 1振りで同じ相手には1回だけ当てる
		_hit_ids[id] = true
		_hit(target, query.transform.origin)


func _hit(target: Object, blade_mid: Vector3) -> void:
	var at: Vector3 = target.get("global_position")
	var speed := _player.horizontal_speed() if _player else 0.0
	var power := HitFeel.power_for(speed)
	# 斬った向き：前へ押し出しつつ、振り抜いた側へ流す
	var cam := get_viewport().get_camera_3d().global_transform.basis
	var forward := Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var side := Vector3(cam.x.x, 0.0, cam.x.z).normalized() * -_sign
	var dir := forward + side * 0.5
	if _analog:
		# 威力 = 基本威力 × (1 + 速度 / 最高速度)。アナログ斬りは弾きの強さで基本威力が変わる
		power *= lerpf(Tuning.slash_power_min, Tuning.slash_power_max, _slash_strength)
		# 弾いた向きへ流す。上下の成分はダミーの潰れ方に使う
		dir = forward + (cam.x * _slash_dir.x + cam.y * _slash_dir.y) * 0.7
	target.call("take_hit", dir, power, Vector3(at.x, blade_mid.y, at.z))
	_squash_vel -= Tuning.weapon_squash * power * sqrt(SQUASH_STIFFNESS)
	HitFeel.on_hit(power, _player)


func _update_squash(delta: float) -> void:
	_squash_vel += (-SQUASH_STIFFNESS * _squash - SQUASH_DAMPING * _squash_vel) * delta
	_squash = clampf(_squash + _squash_vel * delta, -0.5, 0.5)


## 目の前に壁があれば、近さに応じて武器を手前へ引っ込める。
func _update_retract(delta: float) -> void:
	var target := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		var from := cam.global_position
		var query := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * RETRACT_REACH, 1)
		if _player:
			query.exclude = [_player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			target = clampf(RETRACT_REACH - from.distance_to(hit.position), 0.0, RETRACT_MAX)
	_retract = lerpf(_retract, target, minf(1.0, 20.0 * delta))


func retract_amount() -> float:
	return _retract


func _apply_pose() -> void:
	var rot := Vector3(deg_to_rad(_pose.x), deg_to_rad(_pose.y), deg_to_rad(_pose.z))
	# 引っ込めるときは刃先を上へ逃がす
	rot.x += _retract / RETRACT_MAX * deg_to_rad(40.0)
	# 体積を保ったまま刃の向き(Z)に伸び縮みさせる
	var sz := 1.0 + _squash
	var sxy := 1.0 / sqrt(sz)
	var b := Basis.from_euler(rot)
	# アナログ斬りは振りの面ごと視線の軸(Z)まわりに傾ける。軸は肘を通るので肘の位置は変わらない
	b = Basis(Vector3.BACK, _roll) * b
	swing.transform = Transform3D(b * Basis.from_scale(Vector3(sxy, sxy, sz)), ELBOW - b * ELBOW)
	position = _base_position + Vector3(0.0, -_retract * 0.2, _retract)


## 指の曲げとナイフの回転を反映する。
func _apply_hand() -> void:
	var spin := Transform3D(Basis(Vector3.RIGHT, _spin), Vector3.ZERO)
	grip.transform = _grip_rest * Transform3D(Basis.IDENTITY, _spin_pivot) * spin * Transform3D(Basis.IDENTITY, -_spin_pivot)
	if _skeleton == null:
		return
	for finger in CURL_GRIP:
		var closed: Array = CURL_GRIP[finger]
		var opened: Array = CURL_SPIN[finger]
		for k in 3:
			var idx := _skeleton.find_bone("%s_%d" % [finger, k + 1])
			if idx < 0:
				continue
			var angle := deg_to_rad(lerpf(closed[k], opened[k], _open))
			var rest := _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
			_skeleton.set_bone_pose_rotation(idx, rest * Quaternion(Vector3.RIGHT, angle))


func _find_player() -> Player:
	var n := get_parent()
	while n and not (n is Player):
		n = n.get_parent()
	return n as Player


## Meshyで作ったGLBを箱の剣と差し替える。
func _use_model(scene: PackedScene) -> void:
	if scene == null:
		return
	var model := scene.instantiate() as Node3D
	if model == null:
		return
	grip.add_child(model)
	$Swing/Grip/BoxSword.queue_free()
	using_model = true
	if auto_fit:
		_fit(model)


## 一番長い辺を刃の向き(-Z)にそろえ、柄頭から刃先までをmodel_lengthにする。
## 元のモデルで長い辺の小さい側を柄とみなす（立てて作った剣なら下が柄）。
func _fit(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var rel: Transform3D = grip.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		var b: AABB = rel * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or box.get_longest_axis_size() <= 0.0:
		return
	var rot: Basis
	match box.get_longest_axis_index():
		Vector3.AXIS_X:
			rot = Basis(Vector3.UP, PI / 2) # +X → -Z
		Vector3.AXIS_Y:
			rot = Basis(Vector3.RIGHT, -PI / 2) # +Y → -Z
		_:
			rot = Basis(Vector3.UP, PI) # +Z → -Z
	if flip_model:
		rot = Basis(Vector3.UP, PI) * rot
	var s := model_length / box.get_longest_axis_size()
	var b := rot.scaled(Vector3.ONE * s)
	var moved := Transform3D(b, Vector3.ZERO) * box
	var center := moved.get_center()
	var offset := Vector3(-center.x, -center.y, grip_back - moved.end.z)
	model.transform = Transform3D(b, offset) * model.transform
	_spin_pivot = _find_ring_center(model)


## 柄頭の側（Gripの+Z端）にある輪の中心。柄頭から全長の1割の範囲の頂点の中心をとる。
func _find_ring_center(model: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	var from_z := grip_back - model_length * 0.1
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		var rel: Transform3D = grip.global_transform.affine_inverse() * mesh_i.global_transform
		for si in mesh_i.mesh.get_surface_count():
			for v in mesh_i.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = rel * v
				if p.z < from_z:
					continue
				box = AABB(p, Vector3.ZERO) if first else box.expand(p)
				first = false
	return Vector3(0.0, 0.0, grip_back - 0.02) if first else box.get_center()
