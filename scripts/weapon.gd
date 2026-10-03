class_name Weapon
extends Node3D
## 一人称の手と武器。通常攻撃（X / 左クリック）の振り、当たり判定、伸び縮み、壁へのめり込み防止、
## ナイフ回し（Y / F）、斬撃の軌跡、視点を回したときの手の遅れ。
## 手は Swing/HandModel（骨入りのメカの手）、武器は Swing/Grip の下に置く。
## res://models/weapon.glb があればそれを、なければ箱の剣を使う。
## 当たり判定は見た目のメッシュを使わず、Swing の前(-Z)へ伸ばした細長い箱で取る。

enum State { IDLE, WINDUP, ACTIVE, RECOVERY, INSPECT }

# 指の曲げ角（度）。各指は [付け根, 中, 先] の3関節で、正で手のひら側へ曲がる。
# 親指は付け根を横へ振る角度とひねる角度も持つ：[付け根, 中, 先, 横, ひねり]
# 値は tools/rig/solve_grip.tscn で求める（カランビットの標準の握り。README参照）
# 握り：人差し指を輪に根元まで通し、残り3本で柄を握り込み、親指を人差し指の上にかぶせる
const CURL_GRIP := {
	"index": [90.0, 83.0, 43.1], "middle": [64.3, 82.6, 52.9], "ring": [61.8, 86.3, 45.4],
	"pinky": [52.8, 69.4, 51.8], "thumb": [0.0, 40.0, 80.0, 0.0, -60.0],
}
# ナイフを回している間：人差し指は輪に通したまま、ほかの指は1周のどの向きでも刃が当たらない所へ逃がす
const CURL_SPIN := {
	"index": [90.0, 83.0, 43.1], "middle": [-10.0, 10.0, 0.0], "ring": [-10.0, 0.0, 10.0],
	"pinky": [0.0, 10.0, 0.0], "thumb": [0.0, 20.0, 20.0, -30.0, -60.0],
}
const INSPECT_TIME := 1.0
const SPIN_TURNS := 2.0
const POSE_INSPECT := Vector3(40.0, 25.0, -55.0) # 回す間は少し持ち上げ、刃の面をカメラへ向けて見せる

const MODEL_PATH := "res://models/weapon.glb"
const HURTBOX_LAYER := 2 # ダミーなど、斬られる側の当たり判定の層
const HIT_THICKNESS := 0.35
const RETRACT_REACH := 1.0 # 目の前の壁がこれより近いと武器を引っ込める (m)
const RETRACT_MAX := 0.45
const SQUASH_STIFFNESS := 300.0
const SQUASH_DAMPING := 18.0
const TRAIL_LIFE := 0.12 # 斬撃の軌跡が消えるまで（秒）
const TRAIL_COLOR := Color(0.45, 0.85, 1.0) # Neon Talonの光に合わせた水色
const SWAY_LAG := 0.012 # 視点を回す速さ(rad/s)に対する手の遅れ(rad)。右スティック全開(220度/秒)で約2.6度
const SWAY_MAX := 4.0 # 手の遅れの上限（度）
const SWAY_FOLLOW := 14.0 # 手が遅れから戻る速さ (/秒)

# 振りの姿勢（度）：x=刃先の上下、y=刃先の左右（正で左）、z=ひねり
# 肘（拳の後ろ ELBOW の位置）を中心に回すので、前腕は肘の方を向いたまま拳が弧を描く
# 構え：刃の平らな面をカメラへ向けて、反りが読めるようにする。刃先は照準の左下に置き、照準をふさがない
const POSE_IDLE := Vector3(30.0, 30.0, -40.0)
# 振り：右上で振りかぶり、画面の中央を斜めに通って左下へ振り抜く。刃は振る向きの先に立てる
const POSE_WINDUP := Vector3(35.0, -45.0, -70.0) # 右から左へ振るときの構え。左から振るときは左右を反転
const POSE_FOLLOW := Vector3(0.0, 50.0, -95.0)
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
## ナイフの輪の穴の中心（Gripの座標）。ナイフ回しはここを軸に回す。tools/rig/solve_grip で求める
@export var ring_center := Vector3.ZERO

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
var _spin := 0.0 # ナイフの回転（ラジアン）
var _open := 0.0 # 指の開き。0で握る、1でナイフ回しの形
var _skeleton: Skeleton3D
var _blade_tip := Vector3(0.0, 0.0, -1.0) # 刃先（Gripの座標）
var _blade_base := Vector3(0.0, 0.0, -0.4) # 軌跡の内側の端（Gripの座標）
var _trail: MeshInstance3D
var _trail_mesh := ImmediateMesh.new()
var _trail_material := StandardMaterial3D.new()
var _trail_points: Array = [] # [刃元, 刃先, 経過秒, 明るさ]（カメラの座標）
var _sway := Vector2.ZERO # 手の遅れ（x：上下、y：左右。ラジアン）
var _last_look := Vector2.ZERO
var _look_ready := false

@onready var swing: Node3D = $Swing
@onready var grip: Node3D = $Swing/Grip


func _ready() -> void:
	_base_position = position
	_player = _find_player()
	_grip_rest = grip.transform
	if ResourceLoader.exists(MODEL_PATH):
		_use_model(load(MODEL_PATH))
	var skels := find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skeleton = skels[0]
	_find_blade_tip()
	_make_trail()


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
	_update_sway(delta)
	_apply_pose()
	_apply_hand()
	_update_trail(delta)


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
			_spin = TAU * SPIN_TURNS * smoothstep(0.1, 0.8, x)
			var lift := sin(PI * x)
			_pose = _from.lerp(POSE_IDLE, minf(1.0, x * 4.0)).lerp(POSE_INSPECT, lift)
			if x >= 1.0:
				_spin = 0.0
				_open = 0.0
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


func trail_point_count() -> int:
	return _trail_points.size()


func sway_amount() -> float:
	return _sway.length()


## 視点を回すと、手が少し遅れてついてくる（武器が画面に貼り付いて見えないように）。
## 歩きの揺れは手に足さない：頭の揺れと二重になると酔いやすい（Xbox Accessibility Guideline 117）。
func _update_sway(delta: float) -> void:
	if _player == null or delta <= 0.0:
		return
	var look := Vector2(_player.head.rotation.x, _player.rotation.y)
	if not _look_ready:
		_last_look = look
		_look_ready = true
	var rate := Vector2(look.x - _last_look.x, wrapf(look.y - _last_look.y, -PI, PI)) / delta
	_last_look = look
	var target := (-rate * SWAY_LAG * Tuning.hand_sway).limit_length(deg_to_rad(SWAY_MAX))
	_sway = _sway.lerp(target, minf(1.0, SWAY_FOLLOW * delta))


func _apply_pose() -> void:
	var rot := Vector3(deg_to_rad(_pose.x), deg_to_rad(_pose.y), deg_to_rad(_pose.z))
	# 引っ込めるときは刃先を上へ逃がす
	rot.x += _retract / RETRACT_MAX * deg_to_rad(40.0)
	# 体積を保ったまま刃の向き(Z)に伸び縮みさせる
	var sz := 1.0 + _squash
	var sxy := 1.0 / sqrt(sz)
	var b := Basis.from_euler(rot)
	swing.transform = Transform3D(b * Basis.from_scale(Vector3(sxy, sxy, sz)), ELBOW - b * ELBOW)
	# 手の遅れはカメラを中心に回して、画面の上で手がずれて見えるようにする
	var sway := Basis.from_euler(Vector3(_sway.x, _sway.y, 0.0))
	transform = Transform3D(sway, sway * (_base_position + Vector3(0.0, -_retract * 0.2, _retract)))


## 指の曲げとナイフの回転を反映する。ナイフは輪の穴の軸（GripのX）まわりに回す。
func _apply_hand() -> void:
	var spin := Transform3D(Basis(Vector3.RIGHT, _spin), Vector3.ZERO)
	grip.transform = _grip_rest * Transform3D(Basis.IDENTITY, ring_center) * spin * Transform3D(Basis.IDENTITY, -ring_center)
	if _skeleton == null:
		return
	for finger in CURL_GRIP:
		var closed: Array = CURL_GRIP[finger]
		var opened: Array = CURL_SPIN[finger]
		var a: Array = []
		for k in closed.size():
			a.append(deg_to_rad(lerpf(closed[k], opened[k], _open)))
		for k in 3:
			var idx := _skeleton.find_bone("%s_%d" % [finger, k + 1])
			if idx < 0:
				continue
			_skeleton.set_bone_pose_rotation(idx, _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion() * finger_rotation(a, k))


## 指の関節の回転（骨の休みの姿勢からの差）。a はラジアン。
## 付け根(k=0)だけ、a[3]で横へ振り（骨のZ軸まわり）、a[4]でひねる（骨のY軸まわり）
static func finger_rotation(a: Array, k: int) -> Quaternion:
	var q := Quaternion(Vector3.RIGHT, a[k])
	if k == 0 and a.size() > 3:
		q = Quaternion(Vector3.BACK, a[3]) * q
	if k == 0 and a.size() > 4:
		q = Quaternion(Vector3.UP, a[4]) * q
	return q


## 刃先：刃のメッシュの頂点のうちGripの-Z（刃の向き）に一番遠いもの。軌跡の内側は輪と刃先の間にとる
func _find_blade_tip() -> void:
	var root: Node = grip.get_child(grip.get_child_count() - 1) if using_model else grip.get_node_or_null("BoxSword")
	if root == null:
		return
	var best := INF
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		if mesh_i.mesh == null:
			continue
		var rel: Transform3D = grip.global_transform.affine_inverse() * mesh_i.global_transform
		for si in mesh_i.mesh.get_surface_count():
			for v in mesh_i.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = rel * v
				if p.z < best:
					best = p.z
					_blade_tip = p
	_blade_base = ring_center.lerp(_blade_tip, 0.45)


## 斬撃の軌跡：振りの判定中、刃元と刃先の通った跡を帯にして描き、すぐ消す。
## カメラの座標で持つので、走っていても帯は画面に付いてくる。速いほど（威力が高いほど）明るい。
func _make_trail() -> void:
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_material.vertex_color_use_as_albedo = true
	_trail = MeshInstance3D.new()
	_trail.name = "SlashTrail"
	_trail.mesh = _trail_mesh
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child.call_deferred(_trail)


func _update_trail(delta: float) -> void:
	for p in _trail_points:
		p[2] += delta
	while not _trail_points.is_empty() and _trail_points[0][2] > TRAIL_LIFE:
		_trail_points.pop_front()
	if state == State.ACTIVE and Tuning.slash_trail > 0.0:
		var to_cam: Transform3D = get_parent().global_transform.affine_inverse() * grip.global_transform
		var speed := _player.horizontal_speed() if _player else 0.0
		var bright := lerpf(0.45, 1.0, HitFeel.strength_of(HitFeel.power_for(speed))) * Tuning.slash_trail
		_trail_points.append([to_cam * _blade_base, to_cam * _blade_tip, 0.0, bright])
	_trail_mesh.clear_surfaces()
	if _trail_points.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_material)
	for p in _trail_points:
		var a: float = (1.0 - p[2] / TRAIL_LIFE) * p[3]
		_trail_mesh.surface_set_color(Color(TRAIL_COLOR, a * 0.15))
		_trail_mesh.surface_add_vertex(p[0])
		_trail_mesh.surface_set_color(Color(TRAIL_COLOR, a))
		_trail_mesh.surface_add_vertex(p[1])
	_trail_mesh.surface_end()


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

