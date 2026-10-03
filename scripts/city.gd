@tool
class_name City
extends Node3D
## 屋上のまわりのコンクリートジャングル（M5）。起動時とエディタで開いたときに表から作る（保存はしない）。
##
## 屋上（ホーム、x・z = -31〜31、上面 y=0）を、幅4mの路地で区切った12棟のビルが囲み、
## その外を高いビルの輪（内側の面は ±64）が閉じる。路地の底（通り）は y=-6。
## 落ちても死なず、路地の両側の壁を壁ジャンプで乗り継いで屋上へ登り直せる。
##
##   列・行の区切り：A = -60〜-35、B = -31〜-2、C = 2〜31、D = 35〜60（路地は -35〜-31、-2〜2、31〜35）
##   屋上の高さはビルごとに変え、高いビルの壁は壁走り、低いビルの屋上は跳び移り先になる
##   西の低いビル（W_Bottom、上面0）は練習コース：坂を滑り降り、パイプとダクトをくぐり、柵を乗り越える
##
## 当たり判定はすべて層1（壁走り・乗り越えの対象）。外周の見えない壁だけ層3。

const STREET_Y := -6.0
const RING_IN := 64.0
const RING_OUT := 74.0
const RING_SEG := 16.0 # 外周のビルの1棟の幅
const RING_HEIGHTS := [22.0, 30.0, 18.0, 34.0, 26.0, 20.0, 28.0, 24.0, 32.0, 19.0]
const TRIM := 0.05

const BUILDING := preload("res://materials/building.tres")
const METAL := preload("res://materials/block.tres")

# ビル：名前, x0, x1, z0, z1, 屋上の高さ
const BLOCKS := [
	["NW_Tower", -60.0, -35.0, -60.0, -35.0, 20.0],
	["N_Left", -31.0, -2.0, -60.0, -35.0, 5.0],
	["N_Right", 2.0, 31.0, -60.0, -35.0, -2.0],
	["NE_Tower", 35.0, 60.0, -60.0, -35.0, 14.0],
	["E_Top", 35.0, 60.0, -31.0, -2.0, 2.5],
	["E_Bottom", 35.0, 60.0, 2.0, 31.0, -2.5],
	["SE_Tower", 35.0, 60.0, 35.0, 60.0, 24.0],
	["S_Right", 2.0, 31.0, 35.0, 60.0, 12.0],
	["S_Left", -31.0, -2.0, 35.0, 60.0, -1.5],
	["SW_Tower", -60.0, -35.0, 35.0, 60.0, 18.0],
	["W_Bottom", -60.0, -35.0, 2.0, 31.0, 0.0],
	["W_Top", -60.0, -35.0, -31.0, -2.0, 3.5],
]

# 屋上の小屋（よじ登りの練習）：名前, x0, x1, z0, z1, 下, 上
const HUTS := [
	["Hut_NLeft", -22.0, -15.0, -52.0, -44.0, 5.0, 7.6],
	["Hut_NRight", 12.0, 18.0, -50.0, -44.0, -2.0, 0.4],
	["Hut_ETop", 44.0, 50.0, -20.0, -12.0, 2.5, 4.8],
	["Hut_SLeft", -20.0, -12.0, 44.0, 50.0, -1.5, 1.0],
	["Hut_WTop", -50.0, -44.0, -24.0, -18.0, 3.5, 5.8],
]

# 障害物（橙の縁）：名前, x0, x1, z0, z1, 下, 上
const PROPS := [
	# ホームの西の手すりから W_Bottom へ渡る板
	["Plank", -31.0, -35.0, 15.0, 16.2, -0.3, 0.0],
	# W_Top から坂の上へ渡る橋
	["SlideBridge", -58.0, -50.0, -2.0, 2.0, 3.2, 3.5],
	# 坂を降りた先：パイプ（スライディングでくぐる）→ ダクト（低いトンネル）→ 柵（乗り越え）
	["SlidePipe", -58.0, -50.0, 18.0, 18.4, 1.1, 1.45],
	["SlideDuct", -58.0, -50.0, 21.0, 27.0, 1.15, 2.1],
	["SlideFence", -58.0, -50.0, 29.0, 29.6, 0.0, 1.0],
	# 乗り越えの柵
	["Barrier1", -41.0, -40.4, 8.0, 24.0, 0.0, 1.0],
	["Barrier2", -46.0, -45.4, 8.0, 24.0, 0.0, 1.0],
]

# 坂：名前, x0, x1, z0, z1, 低い側の高さ, 高い側の高さ, 高い側（"+x" / "-x" / "+z" / "-z"）
const RAMPS := [
	["SlideRamp", -58.0, -50.0, 2.0, 14.0, 0.0, 3.5, "-z"],
]

@export var platform_color := Color(1.0, 0.55, 0.2)
@export var roof_edge_color := Color(1.0, 0.9, 0.8)
@export var glow_energy := 3.0


func _ready() -> void:
	for c in get_children():
		c.free()
	var prop_trim := _neon(platform_color, glow_energy)
	var roof_trim := _neon(roof_edge_color, glow_energy * 0.4)
	_box("Street", Vector3(-RING_OUT, STREET_Y - 1.0, -RING_OUT), Vector3(RING_OUT, STREET_Y, RING_OUT), BUILDING)
	for b in BLOCKS:
		var body := _box(b[0], Vector3(b[1], STREET_Y, b[3]), Vector3(b[2], b[5], b[4]), BUILDING)
		_trim_top(body, Vector3(b[2] - b[1], b[5] - STREET_Y, b[4] - b[3]), roof_trim)
	for h in HUTS:
		_box(h[0], Vector3(h[1], h[5], h[3]), Vector3(h[2], h[6], h[4]), BUILDING)
	for p in PROPS:
		var lo := Vector3(minf(p[1], p[2]), p[5], minf(p[3], p[4]))
		var hi := Vector3(maxf(p[1], p[2]), p[6], maxf(p[3], p[4]))
		_trim_top(_box(p[0], lo, hi, METAL), hi - lo, prop_trim)
	for r in RAMPS:
		_ramp(r)
	_add_ring()


## 外周のビルの輪。高さを変えながら隙間なく並べ、その外に見えない壁を立てる。
func _add_ring() -> void:
	var i := 0
	var x := -RING_OUT
	while x < RING_OUT - 0.01:
		var x1 := minf(x + RING_SEG, RING_OUT)
		_box("RingN%d" % i, Vector3(x, STREET_Y, -RING_OUT), Vector3(x1, _ring_h(i), -RING_IN), BUILDING)
		_box("RingS%d" % i, Vector3(x, STREET_Y, RING_IN), Vector3(x1, _ring_h(i + 3), RING_OUT), BUILDING)
		x = x1
		i += 1
	i = 0
	var z := -RING_IN
	while z < RING_IN - 0.01:
		var z1 := minf(z + RING_SEG, RING_IN)
		_box("RingE%d" % i, Vector3(RING_IN, STREET_Y, z), Vector3(RING_OUT, _ring_h(i + 5), z1), BUILDING)
		_box("RingW%d" % i, Vector3(-RING_OUT, STREET_Y, z), Vector3(-RING_IN, _ring_h(i + 7), z1), BUILDING)
		z = z1
		i += 1
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var body := StaticBody3D.new()
		body.name = "Bound"
		body.collision_layer = 4
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var along := Vector3(absf(side.z), 0, absf(side.x)) * RING_OUT * 2.0
		box.size = along + Vector3(absf(side.x), 0, absf(side.z)) + Vector3(0, 100, 0)
		shape.shape = box
		body.add_child(shape)
		body.position = side * (RING_OUT + 0.5) + Vector3(0, 40, 0)
		add_child(body)


func _ring_h(i: int) -> float:
	return RING_HEIGHTS[i % RING_HEIGHTS.size()]


## 角 lo〜hi の箱を、当たり判定つきで置く。
func _box(box_name: String, lo: Vector3, hi: Vector3, mat: Material) -> StaticBody3D:
	var size := hi - lo
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_mask = 0
	body.position = (lo + hi) * 0.5
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body


## 坂（三角柱）。高い側の縁が high の向きに来るよう回す。
func _ramp(r: Array) -> void:
	var lo := Vector3(r[1], r[5], r[3])
	var hi := Vector3(r[2], r[6], r[4])
	var along_x: bool = r[7].ends_with("x")
	var length: float = (hi.x - lo.x) if along_x else (hi.z - lo.z)
	var width: float = (hi.z - lo.z) if along_x else (hi.x - lo.x)
	var mesh := PrismMesh.new()
	mesh.left_to_right = 0.0 # 頂点が -X の側：-X が高い側
	mesh.size = Vector3(length, hi.y - lo.y, width)
	mesh.material = METAL
	var yaw: float = {"-x": 0.0, "+x": PI, "+z": PI / 2.0, "-z": -PI / 2.0}[r[7]]
	var body := StaticBody3D.new()
	body.name = r[0]
	body.collision_mask = 0
	body.position = Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
	body.rotation.y = yaw
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_convex_shape()
	body.add_child(shape)
	add_child(body)


func _neon(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## 上面の4辺に光る線を付ける（乗れる場所の目印）。
func _trim_top(body: Node3D, s: Vector3, mat: Material) -> void:
	var y := s.y * 0.5
	for e in [
		[Vector3(0, y, s.z * 0.5), Vector3(s.x + TRIM, TRIM, TRIM)],
		[Vector3(0, y, -s.z * 0.5), Vector3(s.x + TRIM, TRIM, TRIM)],
		[Vector3(s.x * 0.5, y, 0), Vector3(TRIM, TRIM, s.z + TRIM)],
		[Vector3(-s.x * 0.5, y, 0), Vector3(TRIM, TRIM, s.z + TRIM)],
	]:
		var mesh := BoxMesh.new()
		mesh.size = e[1]
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = e[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
