class_name Dummy
extends StaticBody3D
## HPを持たない練習用ダミー。当たった位置と斬った向きに応じて吹き飛び、よろけ、元の位置に戻る。
## 当たり判定（StaticBody）は動かさず、見た目（Visual）だけをばねで揺らす。
## 見た目はMeshy製の訓練ロボット（models/dummy.glb）。当たると白く光らせる（素材に重ねる半透明の白）。

const HEIGHT := 1.8
const FLASH_TIME := 0.08

var hit_count := 0

var _offset := Vector3.ZERO # 見た目の水平方向のずれ
var _offset_vel := Vector3.ZERO
var _lean := Vector3.ZERO # 傾き。向きが倒れる向き、長さが角度（ラジアン）
var _lean_vel := Vector3.ZERO
var _squash := 0.0 # 正で縦に伸び、負で縮む
var _squash_vel := 0.0
var _flash := 0.0
var _flash_material: StandardMaterial3D

@onready var visual: Node3D = $Visual


func _ready() -> void:
	# どんなモデルでも光らせられるよう、元の素材は触らずに白を重ねる。ダミーごとに作るのでほかに移らない
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_material.albedo_color = Color(1, 1, 1, 0)
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = _flash_material


## dir：斬った向き。水平の成分で吹き飛び、下向きの成分ほど強く潰れる。point：当たった位置（ワールド座標）。
func take_hit(dir: Vector3, power: float, point: Vector3) -> void:
	hit_count += 1
	var down := clampf(-dir.normalized().y, 0.0, 1.0)
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	_offset_vel += dir * Tuning.dummy_knockback * power
	# 高いところに当たるほど大きくよろける
	var height := clampf((point.y - global_position.y) / HEIGHT, 0.2, 1.0)
	_lean_vel += dir * Tuning.dummy_tilt * power * height
	# まず潰れて、行き過ぎて伸びてから戻る
	_squash_vel -= Tuning.dummy_squash * power * (1.0 + down) * sqrt(Tuning.dummy_stiffness)
	_flash = FLASH_TIME


## 見た目が元の位置からどれだけずれているか（テスト・調整用）。
func visual_offset() -> Vector3:
	return _offset


func lean_angle() -> float:
	return _lean.length()


func _physics_process(delta: float) -> void:
	var k := Tuning.dummy_stiffness
	var c := Tuning.dummy_damping
	# 減衰つきのばね。半陰的オイラー法で積分する
	_offset_vel += (-k * _offset - c * _offset_vel) * delta
	_offset += _offset_vel * delta
	_lean_vel += (-k * _lean - c * _lean_vel) * delta
	_lean += _lean_vel * delta
	_squash_vel += (-k * _squash - c * _squash_vel) * delta
	_squash += _squash_vel * delta
	_squash = clampf(_squash, -0.6, 1.0)
	_flash = maxf(0.0, _flash - delta)
	_apply_visual()


func _apply_visual() -> void:
	var basis := Basis.IDENTITY
	var angle := minf(_lean.length(), deg_to_rad(70.0))
	if angle > 0.0001:
		# 上向きの軸が倒れる向きへ傾くように回す
		basis = Basis(Vector3.UP.cross(_lean.normalized()), angle)
	# 体積を保つ：縦に s 倍なら横は 1/√s 倍
	var sy := 1.0 + _squash
	var sxz := 1.0 / sqrt(sy)
	visual.transform = Transform3D(basis * Basis.from_scale(Vector3(sxz, sy, sxz)), _offset)
	_flash_material.albedo_color.a = 0.4 if _flash > 0.0 else 0.0
