class_name Weapon
extends Node3D
## 一人称の手と武器。通常攻撃（X / 左クリック）の振り、当たり判定、伸び縮み、壁へのめり込み防止。
## 見た目は Swing/Grip の下に置く。res://models/weapon.glb があればそれを、なければ箱の剣を使う。
## 当たり判定は見た目のメッシュを使わず、刃に沿わせた細長い箱で取る。

enum State { IDLE, WINDUP, ACTIVE, RECOVERY }

const MODEL_PATH := "res://models/weapon.glb"
const HURTBOX_LAYER := 2 # ダミーなど、斬られる側の当たり判定の層
const HIT_LENGTH := 1.4 # 判定の箱の長さ（見た目の刃1.0mより少し長くして当てやすくする）
const HIT_THICKNESS := 0.35
const BLADE_LENGTH := 1.0
const HANDLE_BACK := 0.12 # 握る位置から柄頭までの長さ
const RETRACT_REACH := 1.0 # 目の前の壁がこれより近いと武器を引っ込める (m)
const RETRACT_MAX := 0.45
const SQUASH_STIFFNESS := 300.0
const SQUASH_DAMPING := 18.0

# 振りの姿勢（度）：x=刃先の上下、y=刃先の左右（正で左）、z=ひねり
const POSE_IDLE := Vector3(35.0, 15.0, -10.0)
const POSE_WINDUP := Vector3(5.0, -80.0, -80.0) # 右から左へ振るときの構え。左から振るときは左右を反転
const POSE_FOLLOW := Vector3(-5.0, 80.0, -80.0)

## Meshyのモデルを読み込んだとき、長さと向きを自動で合わせる。Gripの位置と向きは手で微調整する
@export var auto_fit := true
## 自動で合わせた結果、柄と刃先が逆になっていたらオンにする
@export var flip_model := false

var state := State.IDLE
var swing_count := 0
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

@onready var swing: Node3D = $Swing
@onready var grip: Node3D = $Swing/Grip


func _ready() -> void:
	_base_position = position
	_player = _find_player()
	if ResourceLoader.exists(MODEL_PATH):
		_use_model(load(MODEL_PATH))


func _physics_process(delta: float) -> void:
	if _player and _player.input_enabled and Input.is_action_just_pressed("attack"):
		_buffer = Tuning.attack_buffer
	else:
		_buffer -= delta
	if _buffer > 0.0 and (state == State.IDLE or state == State.RECOVERY):
		_buffer = 0.0
		_start_swing()
	_advance(delta)
	if state == State.ACTIVE:
		_check_hits()
	_update_squash(delta)
	_update_retract(delta)
	_apply_pose()


func is_attacking() -> bool:
	return state != State.IDLE


## 刃に沿わせた判定の箱のワールド座標での姿勢。Gripの -Z が刃の向き。
func hitbox_transform() -> Transform3D:
	var g := grip.global_transform.orthonormalized()
	return Transform3D(g.basis, g * Vector3(0.0, 0.0, -HIT_LENGTH * 0.5))


func _start_swing() -> void:
	swing_count += 1
	_sign = -_sign if swing_count > 1 else 1.0
	_hit_ids.clear()
	_from = _pose
	_t = 0.0
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
	shape.size = Vector3(HIT_THICKNESS, HIT_THICKNESS, HIT_LENGTH)
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
	swing.transform = Transform3D(Basis.from_euler(rot) * Basis.from_scale(Vector3(sxy, sxy, sz)), Vector3.ZERO)
	position = _base_position + Vector3(0.0, -_retract * 0.2, _retract)


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


## 一番長い辺を刃の向き(-Z)にそろえ、柄頭から刃先までを決まった長さにする。
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
	var s := (BLADE_LENGTH + HANDLE_BACK) / box.get_longest_axis_size()
	var b := rot.scaled(Vector3.ONE * s)
	var moved := Transform3D(b, Vector3.ZERO) * box
	var center := moved.get_center()
	var offset := Vector3(-center.x, -center.y, HANDLE_BACK - moved.end.z)
	model.transform = Transform3D(b, offset) * model.transform
