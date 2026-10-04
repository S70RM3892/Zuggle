class_name HandsView
extends Node3D
## 一人称の両手の見た目。Camera3D の子に置き、子の HandL / HandR を動かす。
## 左手は右手のモデルを左右反転して使う。
## ふだんは画面の下の端で、走ると腕を振る。手のアクション（HandActions.plant）があると、
## その場所へ素早く手を伸ばして掴む・つく。壁走り中は壁の側の手を壁に添え、壁登り中は両手で壁を叩く。
## 受け身・強い着地では両手を前の床につく。

## 手の座標：-Z が指先、+Y が親指側、-X が手のひら側（右手）。原点は握りこぶしの中心
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

# 構え（右手、カメラの座標）。左手はxを反転する
const REST_POS := Vector3(0.28, -0.33, -0.36)
const REST_PALM := Vector3(-0.8, -0.6, 0.0)
const REST_FINGERS := Vector3(0.0, 0.25, -1.0)
const AIR_RAISE := Vector3(0.05, 0.07, 0.02) # 空中では少し広げて持ち上げる（バランスを取る）
const SLIDE_DROP := Vector3(0.08, -0.25, 0.1) # スライディング中は画面の外へ

# 指の曲げ（度）。付け根・中・先
const CURLS := {
	"relax": {"index": [35.0, 45.0, 30.0], "middle": [40.0, 50.0, 30.0], "ring": [45.0, 55.0, 30.0], "pinky": [50.0, 55.0, 30.0], "thumb": [15.0, 20.0, 15.0]},
	"open": {"index": [5.0, 5.0, 5.0], "middle": [5.0, 5.0, 5.0], "ring": [8.0, 5.0, 5.0], "pinky": [10.0, 5.0, 5.0], "thumb": [0.0, 5.0, 5.0]},
	"flat": {"index": [0.0, 0.0, 0.0], "middle": [0.0, 0.0, 0.0], "ring": [0.0, 0.0, 0.0], "pinky": [0.0, 0.0, 0.0], "thumb": [10.0, 0.0, 0.0]},
	"grip": {"index": [70.0, 85.0, 55.0], "middle": [72.0, 85.0, 55.0], "ring": [74.0, 85.0, 55.0], "pinky": [76.0, 85.0, 55.0], "thumb": [30.0, 40.0, 35.0]},
}
const FINGERS := ["index", "middle", "ring", "pinky", "thumb"]

var _player: Player
var _actions: HandActions
var _hands := {}
var _pos := {}
var _rot := {}
var _curl := {}
var _skeletons := {}
var _phase := 0.0

@onready var _camera: Camera3D = get_parent() as Camera3D


func _ready() -> void:
	_player = _find_player()
	if _player:
		_actions = _player.get_node_or_null("HandActions") as HandActions
	_hands[HandActions.Side.LEFT] = $HandL
	_hands[HandActions.Side.RIGHT] = $HandR
	for side in _hands:
		var skels: Array = (_hands[side] as Node).find_children("*", "Skeleton3D", true, false)
		_skeletons[side] = skels[0] if not skels.is_empty() else null
		var rest := _rest(side)
		_pos[side] = rest.origin
		_rot[side] = rest.basis.get_rotation_quaternion()
		_curl[side] = _copy_curl("relax")
		_apply(side)


func _process(delta: float) -> void:
	if _player == null:
		return
	var speed := _player.horizontal_speed()
	if _player.is_on_floor() and not _player.is_sliding():
		_phase += speed * 1.6 * delta
	elif _player.is_wall_running() or _player.is_climbing():
		_phase += 12.0 * delta
	for side in _hands:
		var target := _target(side)
		var planted: bool = target.planted
		var time := Tuning.hand_reach_time if planted else Tuning.hand_return_time
		# 指数で追う：time 秒でほぼ届く
		var k := 1.0 - exp(-delta * 4.0 / maxf(time, 0.01))
		var t: Transform3D = target.transform
		_pos[side] = (_pos[side] as Vector3).lerp(t.origin, k)
		_rot[side] = (_rot[side] as Quaternion).slerp(t.basis.get_rotation_quaternion(), k)
		_blend_curl(side, target.pose, minf(1.0, k * 1.5))
		_apply(side)


## 今の手の位置（ワールド）。テスト用。
func hand_position(side: int) -> Vector3:
	return (_hands[side] as Node3D).global_position


## {transform（カメラの座標、反転前の回転）, planted, pose}
func _target(side: int) -> Dictionary:
	var plant := _actions.plant(side) if _actions else {}
	if not plant.is_empty():
		return {"transform": _to_camera(side, plant.point, plant.palm, plant.fingers), "planted": true, "pose": plant.pose}
	if (_player.is_rolling() or _player.is_hard_landing()) and _player.is_on_floor():
		return _floor_touch(side)
	var wall := _player.wall_normal()
	if wall != Vector3.ZERO:
		var touch := _wall_touch(side, wall)
		if not touch.is_empty():
			return touch
	var t := _rest(side)
	var s := -1.0 if side == HandActions.Side.LEFT else 1.0
	if _player.is_sliding():
		t.origin += Vector3(SLIDE_DROP.x * s, SLIDE_DROP.y, SLIDE_DROP.z)
	elif not _player.is_on_floor():
		t.origin += Vector3(AIR_RAISE.x * s, AIR_RAISE.y, AIR_RAISE.z)
	else:
		# 走ると左右交互に腕を振る。速いほど大きい
		var amount := clampf(_player.horizontal_speed() / maxf(Tuning.max_speed, 0.1), 0.0, 1.3) * Tuning.arm_swing
		var swing := sin(_phase + (PI if side == HandActions.Side.LEFT else 0.0))
		t.origin += Vector3(0.0, absf(swing) * amount * 0.5, -swing * amount)
	return {"transform": t, "planted": false, "pose": "relax"}


## 壁走り：壁の側の手を、少し前の壁に添える。壁登り：両手で交互に壁の上の方を叩く。
func _wall_touch(side: int, wall: Vector3) -> Dictionary:
	var right := _player.global_transform.basis.x
	var wall_on_right := wall.dot(right) < 0.0
	var chest := _player.global_position + Vector3.UP * 0.45
	var surface := chest - wall * (_player.body_radius() + 0.03)
	if _player.is_climbing():
		var s := -1.0 if side == HandActions.Side.LEFT else 1.0
		var along := Vector3.UP.cross(wall).normalized()
		var lift := 0.35 + 0.2 * sin(_phase + (PI if side == HandActions.Side.LEFT else 0.0))
		var p := surface + Vector3.UP * lift + along * (0.22 * s * signf(along.dot(right)))
		return {"transform": _to_camera(side, p + wall * 0.03, -wall, Vector3.UP), "planted": true, "pose": "flat"}
	if (side == HandActions.Side.RIGHT) != wall_on_right:
		return {}
	var ahead := _player.wall_direction() * 0.45
	var p := surface + ahead + Vector3.UP * 0.05
	var fingers := (Vector3.UP * 0.6 + _player.wall_direction()).normalized()
	return {"transform": _to_camera(side, p + wall * 0.03, -wall, fingers), "planted": true, "pose": "flat"}


## 受け身は平手で床を押さえて転がり、強い着地は指を開いて床を突く。
func _floor_touch(side: int) -> Dictionary:
	var s := -1.0 if side == HandActions.Side.LEFT else 1.0
	var f := _player.facing()
	var right := f.cross(Vector3.UP)
	var p := _player.feet_position() + f * 0.9 + right * (0.22 * s) + Vector3.UP * 0.04
	var pose := "flat" if _player.is_rolling() else "open"
	return {"transform": _to_camera(side, p, Vector3.DOWN, f), "planted": true, "pose": pose}


func _rest(side: int) -> Transform3D:
	var s := -1.0 if side == HandActions.Side.LEFT else 1.0
	var pos := Vector3(REST_POS.x * s, REST_POS.y, REST_POS.z)
	var palm := Vector3(REST_PALM.x * s, REST_PALM.y, REST_PALM.z)
	var fingers := Vector3(REST_FINGERS.x * s, REST_FINGERS.y, REST_FINGERS.z)
	return Transform3D(_basis(side, palm, fingers), pos)


## ワールドの点と向きから、カメラの座標の手の姿勢を作る。
func _to_camera(side: int, point: Vector3, palm: Vector3, fingers: Vector3) -> Transform3D:
	var inv := _camera.global_transform.affine_inverse()
	var b := inv.basis.orthonormalized()
	return Transform3D(_basis(side, b * palm, b * fingers), inv * point)


## 手のひらの向き palm と指先の向き fingers から回転を作る（反転は含めない）。
## 右手は手のひらが -X、左手は反転するので +X が手のひら。指先はどちらも -Z。
func _basis(side: int, palm: Vector3, fingers: Vector3) -> Basis:
	var p := palm.normalized()
	var f := (fingers - p * fingers.dot(p)).normalized()
	if f.length() < 0.5:
		f = Vector3.FORWARD
	var x := p if side == HandActions.Side.LEFT else -p
	var z := -f
	return Basis(x, z.cross(x), z).orthonormalized()


func _apply(side: int) -> void:
	var b := Basis(_rot[side] as Quaternion)
	if side == HandActions.Side.LEFT:
		b = b * MIRROR
	(_hands[side] as Node3D).transform = Transform3D(b, _pos[side])
	var skel: Skeleton3D = _skeletons[side]
	if skel == null:
		return
	var curl: Dictionary = _curl[side]
	for finger in FINGERS:
		var angles: Array = curl[finger]
		for k in 3:
			var idx := skel.find_bone("%s_%d" % [finger, k + 1])
			if idx < 0:
				continue
			var rest := skel.get_bone_rest(idx).basis.get_rotation_quaternion()
			skel.set_bone_pose_rotation(idx, rest * Quaternion(Vector3.RIGHT, deg_to_rad(angles[k])))


func _blend_curl(side: int, pose: String, k: float) -> void:
	var target: Dictionary = CURLS.get(pose, CURLS.relax)
	var curl: Dictionary = _curl[side]
	for finger in FINGERS:
		var a: Array = curl[finger]
		var b: Array = target[finger]
		for i in 3:
			a[i] = lerpf(a[i], b[i], k)


func _copy_curl(pose: String) -> Dictionary:
	var out := {}
	for finger in FINGERS:
		out[finger] = (CURLS[pose][finger] as Array).duplicate()
	return out


func _find_player() -> Player:
	var n := get_parent()
	while n and not (n is Player):
		n = n.get_parent()
	return n as Player
