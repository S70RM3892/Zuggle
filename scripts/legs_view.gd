class_name LegsView
extends Node3D
## 仮の脚。Player の子に置き、箱（太もも・すね・足）を組んで動きに合わせて曲げる。
## 本物の脚のモデルが来たら差し替える。下を向くと見える。
## 股関節の角度は正で脚が前へ、膝の角度は正ですねが後ろへ曲がる。

const HIP_STAND := 0.92 # 足元から股関節までの高さ
const HIP_CROUCH := 0.38
const HIP_SPREAD := 0.11
const THIGH := 0.45
const SHIN := 0.45
const FOLLOW := 14.0 # 角度の追従の速さ

var _player: Player
var _actions: HandActions
var _legs := [] # [{hip: Node3D, knee: Node3D, hip_a, knee_a, splay}]
var _phase := 0.0
var _roll := 0.0


func _ready() -> void:
	_player = get_parent() as Player
	if _player:
		_actions = _player.get_node_or_null("HandActions") as HandActions
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.2)
	mat.roughness = 0.8
	var shoe := StandardMaterial3D.new()
	shoe.albedo_color = Color(0.85, 0.35, 0.2)
	for s in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(HIP_SPREAD * s, 0.0, 0.0)
		add_child(hip)
		_box(hip, Vector3(0.16, THIGH, 0.18), Vector3(0, -THIGH * 0.5, 0), mat)
		var knee := Node3D.new()
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		_box(knee, Vector3(0.13, SHIN, 0.14), Vector3(0, -SHIN * 0.5, 0), mat)
		_box(knee, Vector3(0.12, 0.08, 0.27), Vector3(0, -SHIN, -0.07), shoe)
		_legs.append({"hip": hip, "knee": knee, "hip_a": 0.0, "knee_a": 5.0, "splay": 0.0})


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)


func _process(delta: float) -> void:
	if _player == null:
		return
	var hip_h := lerpf(HIP_STAND, HIP_CROUCH, _player.crouch_amount())
	position = Vector3(0.0, -Player.STAND_HEIGHT * 0.5 + hip_h, 0.04)
	var speed := _player.horizontal_speed()
	var run := clampf(speed / maxf(Tuning.max_speed, 0.1), 0.0, 1.3)
	var swing := Tuning.leg_swing
	# [左の股関節, 左の膝, 右の股関節, 右の膝]
	var pose: Array
	var roll := 0.0
	var move := _actions.move if _actions else HandActions.Move.NONE
	if move == HandActions.Move.MANTLE:
		pose = [80.0, 110.0, 55.0, 95.0]
	elif move == HandActions.Move.VAULT:
		pose = [55.0, 25.0, 60.0, 35.0]
		roll = 35.0 # 脚を横へ流して越える
	elif move == HandActions.Move.POLE:
		pose = [40.0, 50.0, 15.0, 30.0]
	elif _player.is_rolling():
		pose = [105.0, 135.0, 95.0, 125.0] # 膝を抱えて転がる
	elif _player.is_sliding():
		# 前の脚を伸ばし、後ろの脚を畳む
		pose = [70.0, 110.0, 85.0, 5.0]
	elif _player.is_climbing() or _player.is_wall_running():
		_phase += 13.0 * delta
		var a := sin(_phase) * swing
		var bias := 30.0 if _player.is_climbing() else 10.0
		pose = [bias + a, 40.0 + maxf(0.0, -cos(_phase)) * 60.0, bias - a, 40.0 + maxf(0.0, cos(_phase)) * 60.0]
		if _player.is_wall_running():
			roll = -_player.wall_normal().dot(_player.global_transform.basis.x) * 12.0
	elif not _player.is_on_floor():
		pose = [35.0, 70.0, -10.0, 35.0]
	elif speed > 0.3:
		_phase += speed * 1.6 * delta
		var a := sin(_phase) * swing * run
		pose = [a, 10.0 + maxf(0.0, -cos(_phase)) * 70.0 * run, -a, 10.0 + maxf(0.0, cos(_phase)) * 70.0 * run]
	else:
		pose = [0.0, 5.0, 0.0, 5.0]
	if _player.is_crouching() and not _player.is_sliding() and not _player.is_rolling() and _player.is_on_floor():
		for i in [0, 2]:
			pose[i] = pose[i] + 70.0
			pose[i + 1] = pose[i + 1] + 80.0
	var k := minf(1.0, FOLLOW * delta)
	_roll = lerpf(_roll, roll, k)
	rotation.z = deg_to_rad(_roll)
	for i in 2:
		var leg: Dictionary = _legs[i]
		leg.hip_a = lerpf(leg.hip_a, pose[i * 2], k)
		leg.knee_a = lerpf(leg.knee_a, pose[i * 2 + 1], k)
		(leg.hip as Node3D).rotation.x = deg_to_rad(leg.hip_a)
		(leg.knee as Node3D).rotation.x = -deg_to_rad(leg.knee_a)
