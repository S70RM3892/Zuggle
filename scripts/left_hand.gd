class_name LeftHand
extends Node3D
## 空いている左手。パルクールの動きに合わせて、縁・壁・床へ手を伸ばす（M5）。
##   vault：低い障害物の上に手のひらをついて跳び越える
##   mantle：縁に指を掛け、体を引き上げながら押し下げる
##   wall：壁走り中、左の壁に手のひらを添える（右の壁には届かないので構えのまま）
##   push：壁ジャンプで壁を突き放す
##   slide：スライディング中、低く横へ構えて体を支える
## 何もしていないときは画面の外（左下）へ下げて隠す。
## 手のモデルは右手（Swing/HandModel と同じ）を X で反転して使う。
## このノードの座標では -Z が指先、+Y が親指側、+X が手のひら側。

const GLOW := preload("res://models/hand_emission.png")
const VIEW_LAYER := 2 # 手元用の補助光（ViewLight）が照らす層

const SHOULDER := Vector3(-0.22, -0.28, 0.05) # 肩の位置（カメラの座標）。手はここから REACH 以内に置く
const REACH := 0.72
const MIN_FORWARD := 0.14 # 手はカメラよりこれだけ前に置く（顔に重ならない）
const MAX_DOWN := 0.62 # 視線から下へ tan(32度) までに収める。縁が足元にあっても手が画面に映る
const HIDDEN := Vector3(-0.32, -0.85, -0.2)
const SLIDE_POS := Vector3(-0.3, -0.3, -0.45)
const MOVE_RATE := 22.0 # 手を伸ばす速さ (/秒)
const RETURN_RATE := 9.0 # 構えに戻す速さ (/秒)

# 指の曲げ角（度）。付け根・中・先。0で開く。HOOKは縁に指を掛ける形
const CURL_OPEN := {
	"index": [8.0, 6.0, 4.0], "middle": [6.0, 6.0, 4.0], "ring": [8.0, 8.0, 4.0],
	"pinky": [10.0, 8.0, 4.0], "thumb": [10.0, 10.0, 5.0],
}
const CURL_HOOK := {
	"index": [55.0, 70.0, 40.0], "middle": [55.0, 70.0, 40.0], "ring": [55.0, 70.0, 40.0],
	"pinky": [55.0, 70.0, 40.0], "thumb": [25.0, 25.0, 15.0],
}

var kind := "" # 今の動き（Player.left_hand_target の kind）

var _player: Player
var _skeleton: Skeleton3D
var _pos := HIDDEN
var _quat := Quaternion.IDENTITY
var _curl := 0.0 # 0：開く、1：縁に掛ける


func _ready() -> void:
	var n := get_parent()
	while n and not (n is Player):
		n = n.get_parent()
	_player = n as Player
	for mi in find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		mesh_i.layers = 1 | VIEW_LAYER
		for i in mesh_i.mesh.get_surface_count():
			var mat := mesh_i.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			mat = mat.duplicate()
			mat.emission_enabled = true
			mat.emission = Color.BLACK
			mat.emission_texture = GLOW
			mat.emission_energy_multiplier = 2.5
			mesh_i.set_surface_override_material(i, mat)
	var skels := find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skeleton = skels[0]
	_quat = _hand_basis(Vector3.RIGHT, Vector3(0, 0.3, -1)).get_rotation_quaternion()
	position = _pos
	visible = false


func _process(delta: float) -> void:
	var cam := get_parent() as Node3D
	if _player == null or cam == null:
		return
	var t := _player.left_hand_target()
	kind = t.get("kind", "")
	var to_cam := cam.global_transform.affine_inverse()
	var inv := cam.global_basis.orthonormalized().inverse()
	var target := HIDDEN
	var palm := Vector3.RIGHT
	var fingers := Vector3(0.2, 0.3, -1.0)
	var curl := 0.3
	var rate := MOVE_RATE
	match kind:
		"vault", "mantle":
			target = to_cam * (t.point as Vector3)
			palm = inv * Vector3.DOWN
			fingers = inv * (t.dir as Vector3)
			curl = 0.15 if kind == "vault" else 0.85
		"wall", "push":
			if (to_cam * (t.point as Vector3)).x < 0.0: # 左の壁だけ。右の壁へは届かない
				target = to_cam * (t.point as Vector3)
				palm = inv * -(t.normal as Vector3)
				fingers = inv * ((t.dir as Vector3) * 0.8 + Vector3.UP * 0.6) if kind == "wall" else inv * Vector3.UP
				curl = 0.05
		"slide":
			target = SLIDE_POS
			palm = Vector3.DOWN
			fingers = Vector3(-0.4, 0.0, -1.0)
			curl = 0.2
		_:
			rate = RETURN_RATE
	if target != HIDDEN:
		target = _clamp_reach(target)
	var k := minf(1.0, rate * delta)
	_pos = _pos.lerp(target, k)
	_quat = _quat.slerp(_hand_basis(palm, fingers).get_rotation_quaternion(), k)
	_curl = lerpf(_curl, curl, k)
	transform = Transform3D(Basis(_quat), _pos)
	# 下げきったら描かない
	visible = target != HIDDEN or _pos.distance_to(HIDDEN) > 0.05
	_pose_fingers()


## 手のひらの向き palm と指先の向き fingers から、このノードの向きを作る（どちらもカメラの座標）。
func _hand_basis(palm: Vector3, fingers: Vector3) -> Basis:
	var z := -fingers.normalized()
	var x := palm - z * palm.dot(z)
	if x.length() < 0.01:
		x = z.cross(Vector3.UP)
	x = x.normalized()
	return Basis(x, z.cross(x), z)


## 腕の長さより遠い所へは届かない。顔の前に重ならないよう少し前へ出し、画面の下へ外れないようにする。
func _clamp_reach(p: Vector3) -> Vector3:
	var from := p - SHOULDER
	if from.length() > REACH:
		p = SHOULDER + from.normalized() * REACH
	p.z = minf(p.z, -MIN_FORWARD)
	p.y = maxf(p.y, p.z * MAX_DOWN)
	return p


func _pose_fingers() -> void:
	if _skeleton == null:
		return
	for finger in CURL_OPEN:
		var opened: Array = CURL_OPEN[finger]
		var hooked: Array = CURL_HOOK[finger]
		for i in 3:
			var idx := _skeleton.find_bone("%s_%d" % [finger, i + 1])
			if idx < 0:
				continue
			var rest := _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
			_skeleton.set_bone_pose_rotation(idx, rest * Quaternion(Vector3.RIGHT, deg_to_rad(lerpf(opened[i], hooked[i], _curl))))
