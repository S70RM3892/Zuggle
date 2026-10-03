@tool
extends Node3D
## パルクール場（夕方のビルの屋上）の飾り。起動時とエディタで開いたときに作る（保存はしない）。
##   グループ "platform"：上面の4辺に橙の線（乗れる足場の目印）
##   グループ "runwall"：長い2面に水色の線（壁走りできる壁の目印）
##   グループ "edge"：外周の手すりの上に白い線
## ほかに、床の目地（速さの目安）と、外周の小物（空調機・換気塔・給水タンク・アンテナ）を置く。
## 小物は外周の近くだけに置き、練習コースとテストの通り道には置かない。

const TRIM := 0.05 # 線の太さ (m)
const JOINT_STEP := 4.0 # 床の目地の間隔 (m)
const HALF := 30.0 # 床の半分の幅 (m)

const METAL := preload("res://materials/block.tres")
const CONCRETE := preload("res://materials/wall.tres")

# 小物：種類, 位置, 向き（度）
const PROPS := [
	["tank", Vector3(-25, 0, -25), 0.0],
	["ac", Vector3(24.5, 0, -26.5), 0.0],
	["ac", Vector3(21.0, 0, -26.5), 0.0],
	["ac", Vector3(26.5, 0, -22.0), 90.0],
	["vent", Vector3(-19, 0, -27.5), 0.0],
	["vent", Vector3(-16.5, 0, -27.5), 0.0],
	["vent", Vector3(27.5, 0, 6), 0.0],
	["vent", Vector3(27.5, 0, 9), 0.0],
	["ac", Vector3(-26.5, 0, 27.0), 90.0],
	["ac", Vector3(-26.5, 0, -6.0), 90.0],
	["antenna", Vector3(26, 0, 26), 0.0],
]

@export var platform_color := Color(1.0, 0.55, 0.2)
@export var runwall_color := Color(0.2, 0.85, 1.0)
@export var edge_color := Color(1.0, 0.9, 0.8)
@export var glow_energy := 3.0

var _beacon: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	var platform_mat := _neon(platform_color, glow_energy)
	var runwall_mat := _neon(runwall_color, glow_energy)
	var edge_mat := _neon(edge_color, glow_energy * 0.5)
	for n in _in_group("platform"):
		_trim_top(n, platform_mat)
	for n in _in_group("runwall"):
		_trim_runwall(n, runwall_mat)
	for n in _in_group("edge"):
		_strip(n, Vector3(0, n.size.y * 0.5, 0), n.size + Vector3(TRIM, TRIM - n.size.y, TRIM), edge_mat)
	_add_joints()
	_beacon = _neon(Color(1.0, 0.15, 0.1), 4.0)
	for p in PROPS:
		_add_prop(p[0], p[1], p[2])


func _process(delta: float) -> void:
	# アンテナの先の赤いランプをゆっくり点滅させる
	_t += delta
	if _beacon:
		_beacon.emission_energy_multiplier = 4.0 if fmod(_t, 1.6) < 0.25 else 0.3


## グループはエディタでも読めるように、木を直接たどって集める。
func _in_group(group: String) -> Array[CSGBox3D]:
	var out: Array[CSGBox3D] = []
	for n in find_children("*", "CSGBox3D", true, false):
		if n.is_in_group(group):
			out.append(n as CSGBox3D)
	return out


func _neon(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _trim_top(box: CSGBox3D, mat: Material) -> void:
	var s := box.size
	var y := s.y * 0.5
	_strip(box, Vector3(0, y, s.z * 0.5), Vector3(s.x + TRIM, TRIM, TRIM), mat)
	_strip(box, Vector3(0, y, -s.z * 0.5), Vector3(s.x + TRIM, TRIM, TRIM), mat)
	_strip(box, Vector3(s.x * 0.5, y, 0), Vector3(TRIM, TRIM, s.z + TRIM), mat)
	_strip(box, Vector3(-s.x * 0.5, y, 0), Vector3(TRIM, TRIM, s.z + TRIM), mat)


func _trim_runwall(box: CSGBox3D, mat: Material) -> void:
	var s := box.size
	for side in [-1.0, 1.0]:
		var z: float = side * (s.z * 0.5 + 0.005)
		_strip(box, Vector3(0, s.y * 0.5 - 0.25, z), Vector3(s.x, 0.12, 0.01), mat)
		_strip(box, Vector3(0, -s.y * 0.5 + 0.6, z), Vector3(s.x, 0.04, 0.01), mat)
		_strip(box, Vector3(0, s.y * 0.5, z), Vector3(s.x, TRIM, TRIM), mat)


func _strip(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	_mesh(parent, mesh, pos).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## 床の目地。暗い細い線を格子に並べる。走ったときに流れて見え、速さが分かる。
func _add_joints() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09)
	mat.roughness = 0.9
	var joints := Node3D.new()
	joints.name = "Joints"
	add_child(joints)
	var n := int(HALF * 2.0 / JOINT_STEP)
	for i in range(1, n):
		var c := -HALF + i * JOINT_STEP
		_strip(joints, Vector3(c, 0.003, 0), Vector3(0.05, 0.004, HALF * 2.0), mat)
		_strip(joints, Vector3(0, 0.003, c), Vector3(HALF * 2.0, 0.004, 0.05), mat)


func _add_prop(kind: String, pos: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Prop_%s" % kind
	body.position = pos
	body.rotation.y = deg_to_rad(yaw)
	add_child(body)
	match kind:
		"ac":
			_part(body, _box(Vector3(2.4, 1.3, 1.6), METAL), Vector3(0, 0.65, 0), true)
			_part(body, _cyl(0.5, 0.08, _dark()), Vector3(-0.55, 1.34, 0), false)
			_part(body, _cyl(0.5, 0.08, _dark()), Vector3(0.6, 1.34, 0), false)
			_part(body, _box(Vector3(0.1, 0.04, 0.02), _neon(Color(0.3, 1.0, 0.5), 3.0)), Vector3(0.95, 1.05, 0.81), false)
		"vent":
			_part(body, _cyl(0.32, 2.2, METAL), Vector3(0, 1.1, 0), true)
			_part(body, _cyl(0.5, 0.12, METAL), Vector3(0, 2.3, 0), false)
		"tank":
			for x in [-1.1, 1.1]:
				for z in [-1.1, 1.1]:
					_part(body, _box(Vector3(0.2, 1.6, 0.2), METAL), Vector3(x, 0.8, z), true)
			_part(body, _cyl(1.7, 2.6, CONCRETE), Vector3(0, 2.9, 0), true)
			_part(body, _cyl(1.75, 0.15, METAL), Vector3(0, 4.25, 0), false)
		"antenna":
			_part(body, _box(Vector3(0.8, 0.3, 0.8), METAL), Vector3(0, 0.15, 0), true)
			_part(body, _cyl(0.06, 9.0, METAL), Vector3(0, 4.8, 0), true)
			var lamp := SphereMesh.new()
			lamp.radius = 0.15
			lamp.height = 0.3
			lamp.material = _beacon
			_part(body, lamp, Vector3(0, 9.4, 0), false)


## 見た目を置き、collideなら同じ形の当たり判定も付ける。
func _part(body: StaticBody3D, mesh: Mesh, pos: Vector3, collide: bool) -> void:
	_mesh(body, mesh, pos)
	if not collide:
		return
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_convex_shape()
	shape.position = pos
	body.add_child(shape)


func _box(size: Vector3, mat: Material) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	return m


func _cyl(radius: float, height: float, mat: Material) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.material = mat
	return m


func _dark() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.06)
	m.metallic = 0.6
	m.roughness = 0.5
	return m
