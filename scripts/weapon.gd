class_name Weapon
extends Node3D
## 一人称の手と武器。通常攻撃（X / 左クリック）の振り、当たり判定、伸び縮み、壁へのめり込み防止、
## ナイフ回し（Y / F）。
## 手は Swing/HandModel（骨入りのメカの手）、武器は Swing/Grip の下に置く。
## res://models/weapon.glb があればそれを、なければ箱の剣を使う。
## 当たり判定は見た目のメッシュを使わず、Swing の前(-Z)へ伸ばした細長い箱で取る。

enum State { IDLE, WINDUP, ACTIVE, RECOVERY, INSPECT }

# 指の曲げ角（度）。各指は付け根・中・先の3関節。正で手のひら側へ曲がる
const CURL_GRIP := {
	"index": [80.0, 95.0, 55.0], "middle": [80.0, 95.0, 55.0], "ring": [82.0, 95.0, 55.0],
	"pinky": [85.0, 95.0, 55.0], "thumb": [30.0, 25.0, 25.0],
}
# ナイフを回している間：人差し指は輪に通したまま、ほかの指を開いて刃の通り道を空ける
const CURL_SPIN := {
	"index": [70.0, 90.0, 50.0], "middle": [15.0, 10.0, 5.0], "ring": [20.0, 10.0, 5.0],
	"pinky": [25.0, 10.0, 5.0], "thumb": [5.0, 10.0, 10.0],
}
# 親指の付け根のひねり（度）：y=骨の軸まわり、z=手のひらの面の中で人差し指の側へ。
# 曲げるだけでは親指が手のひらの前へまっすぐ突き出るので、指の上を横切るように寄せる
const THUMB_TURN_GRIP := Vector2(-25.0, 40.0)
const THUMB_TURN_SPIN := Vector2(-5.0, 10.0)
const INSPECT_TIME := 1.0
const SPIN_TURNS := 2.0
const POSE_INSPECT := Vector3(8.0, 12.0, 30.0) # 回す間は少し持ち上げ、ひねって見せる
# ナイフの回り方：指ではじいた勢いで回り、刃先が上へ行くときは重さで遅く、下るときは速くなる。
# 指の摩擦で少しずつ遅くなり、最後は指で受け止めて止める
const SPIN_FLICK := 0.12 # はじいて最高速になるまでの角度（ラジアン）
const SPIN_GRAVITY := 0.22 # 刃先の高さ1あたりの速さ²の減り（はじいた直後の速さ²を1とする）
const SPIN_FRICTION := 0.035 # 1ラジアンあたりの速さ²の減り
const SPIN_CATCH := 0.6 # 受け止めて止めるまでの角度（ラジアン）
const SPIN_STEPS := 256

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
var _spin_time := PackedFloat32Array() # 回転角を SPIN_STEPS 等分したときの、そこまでの時間（0〜1）
var _skeleton: Skeleton3D

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


func _physics_process(delta: float) -> void:
	if _player and _player.input_enabled and Input.is_action_just_pressed("attack"):
		_buffer = Tuning.attack_buffer
	else:
		_buffer -= delta
	if _buffer > 0.0 and (state == State.IDLE or state == State.RECOVERY or state == State.INSPECT):
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


## 判定の箱のワールド座標での姿勢。握る位置から Swing の前(-Z)へ伸ばす。
func hitbox_transform() -> Transform3D:
	var g := swing.global_transform.orthonormalized()
	return Transform3D(g.basis, g * Vector3(0.0, 0.0, -hit_length * 0.5))


## ナイフ回し：輪に通した人差し指を軸に、ナイフを2回転させて握り直す。
func _start_inspect() -> void:
	inspect_count += 1
	_build_spin_table()
	_from = _pose
	_t = 0.0
	state = State.INSPECT


func _start_swing() -> void:
	swing_count += 1
	_sign = -_sign if swing_count > 1 else 1.0
	_hit_ids.clear()
	_from = _pose
	_t = 0.0
	_spin = 0.0 # 回している途中なら握り直してから振る
	_open = 0.0
	state = State.WINDUP


func _advance(delta: float) -> void:
	if state == State.IDLE:
		_pose = POSE_IDLE
		return
	_t += delta
	var windup := _mirror(POSE_WINDUP)
	var follow := _mirror(POSE_FOLLOW)
	match state:
		State.WINDUP:
			var x := _ratio(Tuning.attack_windup)
			_pose = _from.lerp(windup, _ease_out(x))
			if x >= 1.0:
				_next(State.ACTIVE)
				HitFeel.play_swing()
		State.ACTIVE:
			# 判定の間は一定の速さで振り抜く
			_pose = windup.lerp(follow, _ratio(Tuning.attack_active))
			if _t >= Tuning.attack_active:
				_next(State.RECOVERY)
		State.RECOVERY:
			var x := _ratio(Tuning.attack_recovery)
			_pose = follow.lerp(POSE_IDLE, smoothstep(0.0, 1.0, x))
			if x >= 1.0:
				_next(State.IDLE)
		State.INSPECT:
			var x := _ratio(INSPECT_TIME)
			# 指を開く(0〜0.15) → 回す(0.1〜0.8) → 握り直す(0.75〜1.0)
			_open = smoothstep(0.0, 0.15, x) * (1.0 - smoothstep(0.75, 1.0, x))
			_spin = _spin_angle(clampf((x - 0.1) / 0.7, 0.0, 1.0))
			var lift := sin(PI * x)
			_pose = _from.lerp(POSE_IDLE, minf(1.0, x * 4.0)).lerp(POSE_INSPECT, lift)
			if x >= 1.0:
				_spin = 0.0
				_open = 0.0
				_next(State.IDLE)


## 回す速さの表を作る。回転角θでの速さωを、はじいた勢い・刃先の高さ・摩擦・受け止めから決め、
## dθ/ω を足し合わせて「θまで回るのにかかる時間」を求める。
func _build_spin_table() -> void:
	var total := TAU * SPIN_TURNS
	# 刃先(Gripの-Z)の高さ。回転軸はGripのX。上向きをGripの座標に直す
	var up := (swing.global_basis.orthonormalized() * _grip_rest.basis.orthonormalized()).inverse() * Vector3.UP
	var h0 := -up.z
	_spin_time.resize(SPIN_STEPS + 1)
	_spin_time[0] = 0.0
	var dth := total / SPIN_STEPS
	var acc := 0.0
	for i in SPIN_STEPS:
		var th := (i + 0.5) * dth
		var h := up.y * sin(th) - up.z * cos(th)
		var w2 := 1.0 - SPIN_GRAVITY * (h - h0) - SPIN_FRICTION * th
		var w := sqrt(maxf(w2, 0.06))
		w *= lerpf(0.35, 1.0, smoothstep(0.0, SPIN_FLICK, th)) # はじく
		w *= lerpf(0.15, 1.0, smoothstep(0.0, SPIN_CATCH, total - th)) # 受け止める
		acc += dth / w
		_spin_time[i + 1] = acc
	for i in SPIN_STEPS + 1:
		_spin_time[i] /= acc


## 回し始めてからの時間の割合 p（0〜1）での回転角。
func _spin_angle(p: float) -> float:
	if _spin_time.is_empty():
		_build_spin_table()
	var i := clampi(_spin_time.bsearch(p) - 1, 0, SPIN_STEPS - 1)
	var span := _spin_time[i + 1] - _spin_time[i]
	var f := 0.0 if span <= 0.0 else clampf((p - _spin_time[i]) / span, 0.0, 1.0)
	return (i + f) * TAU * SPIN_TURNS / SPIN_STEPS


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
	target.call("take_hit", forward + side * 0.5, power, Vector3(at.x, blade_mid.y, at.z))
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
			var euler := Vector3(lerpf(closed[k], opened[k], _open), 0.0, 0.0)
			if finger == "thumb" and k == 0:
				var turn := THUMB_TURN_GRIP.lerp(THUMB_TURN_SPIN, _open)
				euler = Vector3(euler.x, turn.x, turn.y)
			var rest := _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
			_skeleton.set_bone_pose_rotation(idx, rest * Quaternion.from_euler(euler * PI / 180.0))


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
