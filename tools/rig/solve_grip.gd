extends Node
## カランビットの握りを、手とナイフの形から求める。
## 実行：godot --headless --path . res://tools/rig/solve_grip.tscn
## 撮影も：SHOT_DIR=build/shots xvfb-run godot --path . --rendering-driver opengl3 res://tools/rig/solve_grip.tscn
## 出力（貼り付け先）：
##   Grip の transform  → scenes/main.tscn の Player/Head/Camera3D/Hand/Swing/Grip
##   ring_center         → scenes/main.tscn の Hand
##   CURL_GRIP           → scripts/weapon.gd
##
## カランビットの標準の握り（逆手）：
## - 人差し指を輪に根元まで通す（輪は手のひらにできるだけ近く）。輪の穴の軸はほぼ人差し指の基節の向き
## - 残りの3本で柄を握り込む。刃は小指側から下へ出て、内側の弧（刃）を前へ向ける
## 求め方：
## 1. 指の曲げは、円柱を握ったときの実測（Ishii ら 2019、CTで直径10mmと60mm）を柄の太さで内挿する
## 2. 中指・薬指・小指が曲がってできる「筒」の中心を求める
## 3. 人差し指の基節の上に輪の中心を置き、そこから筒の中心をなるべく通るように柄の向きを決める
##    （人差し指の付け根から小指側の手のひらの付け根へ斜めに渡る、握り込みの対角線になる）
## 4. 輪の穴の軸は人差し指の向きに合わせる。柄と直交させるために傾けた分は、穴のゆるみに収まるかを確かめる

const SUBSAMPLE := 3 # 手の頂点を間引く
const CELL := 0.01 # ナイフの占有格子の大きさ（ナイフのモデルの単位）
const MARGIN := 0.002 # これより近づいたら触れたとみなす (m)

# 円柱を握ったときの指の曲げ（度）[付け根(MP), 中(PIP), 先(DIP)]。
# Ishii et al. 2019, Applied Bionics and Biomechanics, Table 2（10人の平均）
const GRIP_10MM := {
	"index": [65.6, 105.5, 48.2], "middle": [75.9, 104.8, 64.8], "ring": [76.6, 110.5, 57.2], "pinky": [64.1, 93.0, 65.8],
}
const GRIP_60MM := {
	"index": [39.7, 48.0, 35.2], "middle": [46.3, 48.1, 34.5], "ring": [38.7, 48.7, 27.1], "pinky": [35.2, 32.8, 30.0],
}
const HAND_SCALE := 1.4 # この手は人の手の約1.4倍（手のひらの幅 0.12m ÷ 0.085m）
const FINGERS := ["middle", "ring", "pinky"]
const INDEX_MP := [50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0, 85.0, 90.0]
const RING_AT := [0.45, 0.5, 0.55, 0.6, 0.65, 0.7] # 輪の中心を人差し指の基節のどこに置くか（付け根0〜中の関節1）
const MAX_SLACK := 15.0 # 輪の穴のゆるみで許す、穴の軸と人差し指の向きのずれ（度）
const MAX_INDEX_HITS := 8 # 人差し指の基節の頂点が輪に食い込んでよい数（間引いた頂点で数える）
const SPIN_STEPS := 24 # ナイフ回しの当たりを調べる向きの数
const THUMB_GAP := 0.022 # 親指の腹の中心を、人差し指の中節の軸からどれだけ外に置くか（指の半径の和）(m)

var _w: Weapon
var _skel: Skeleton3D
var _to_swing: Transform3D # 骨格の座標 → Swing の座標
var _bone_verts := {} # 骨の番号 → 骨のローカル座標の頂点（PackedVector3Array）
var _occ := {} # Vector2i → Vector2(zmin, zmax)（ナイフのモデルの座標）
var _cell_min := Vector2.ZERO
var _gw := 0 # 判定用の密な格子（周り1マスまで太らせたもの）
var _gh := 0
var _gzmin := PackedFloat32Array()
var _gzmax := PackedFloat32Array()
var _knife_to_swing := Transform3D.IDENTITY
var _swing_to_knife := Transform3D.IDENTITY
var _margin_k := 0.0 # MARGINをナイフの単位にしたもの
var _model: Node3D
var _ring_k := Vector3.ZERO # 輪の穴の中心（ナイフのモデルの座標）
var _curl := {}
var _spin_curl := {}


func _ready() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_w = scene.get_node("Player/Head/Camera3D/Hand")
	_w.set_physics_process(false)
	_skel = _w.find_children("*", "Skeleton3D", true, false)[0]
	_to_swing = _w.swing.global_transform.affine_inverse() * _skel.global_transform
	_model = _w.grip.get_child(_w.grip.get_child_count() - 1)
	_load_hand_verts()
	_build_knife_grid()
	await _run()
	get_tree().quit()


func _run() -> void:
	var ring := _find_ring()
	_ring_k = ring[0]
	var size := _handle_size()
	# 柄の断面（幅×厚み）を同じ周の長さの円に直し、人の手の大きさに戻して実測の間を内挿する
	var diameter := (size.x + size.y) * 2.0 / PI / HAND_SCALE
	var k := clampf((diameter - 0.010) / (0.060 - 0.010), 0.0, 1.0)
	print("輪の穴：半径 %.1f mm　柄：幅 %.1f mm × 厚み %.1f mm → 人の手なら直径 %.1f mm の円柱（10mmと60mmの間の %.2f）" % [
		ring[1] * _scale() * 1000.0, size.x * 1000.0, size.y * 1000.0, diameter * 1000.0, k])
	for name in GRIP_10MM:
		var a: Array = GRIP_10MM[name]
		var b: Array = GRIP_60MM[name]
		_curl[name] = [lerpf(a[0], b[0], k), lerpf(a[1], b[1], k), lerpf(a[2], b[2], k)]
		_set_curl(name, _curl[name])
	_curl["thumb"] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var tubes := []
	for name in FINGERS:
		tubes.append(_tube_center(name))
	# 柄が筒の中心を通るほどよく（ずれ1mmで1点）、輪が人差し指の根元に近いほどよい（基節の1割で1点）。
	# 人差し指が輪の内側に食い込む姿勢は選ばない
	var best := {}
	for mp in INDEX_MP:
		for f in RING_AT:
			var r := _try(mp, f, tubes)
			r.idx1 = _count_hits(_bone("index", 1))
			r.cost = r.err * 1000.0 + f * 10.0
			print("人差し指MP %d 輪 %.2f → 筒からのずれ %.1f mm、ゆるみ %.1f 度、傾き %.0f 度、人差し指の食い込み %d、点 %.1f" % [
				mp, f, r.err * 1000.0, r.slack, r.tilt, r.idx1, r.cost])
			if r.slack <= MAX_SLACK and r.idx1 <= MAX_INDEX_HITS and (best.is_empty() or r.cost < best.cost):
				best = r
	print("\n選んだ握り：人差し指MP %d 輪 %.2f（筒からのずれ %.1f mm、ゆるみ %.1f 度、柄の傾き %.0f 度、人差し指の食い込み %d）" % [
		best.mp, best.f, best.err * 1000.0, best.slack, best.tilt, best.idx1])
	_curl["index"][0] = best.mp
	_set_curl("index", _curl["index"])
	_place(best.f, tubes)
	_curl["thumb"] = _solve_thumb()
	_set_curl("thumb", _curl["thumb"])
	_report()
	_solve_spin()
	_print_outputs()
	var dir := OS.get_environment("SHOT_DIR")
	if dir != "":
		await _shots(dir)


## 柄の幅（ナイフのY方向）と厚み（Z方向）。輪と刃の間の範囲で測る (m)
func _handle_size() -> Vector2:
	var cols := {} # 列ごとの [ymin, ymax, zmin, zmax]
	var from := _ring_k.x * 0.25
	var to := _ring_k.x * 0.75
	for key in _occ:
		var x: float = _cell_min.x + (key.x + 0.5) * CELL
		if x < from or x > to:
			continue
		var yy: float = _cell_min.y + (key.y + 0.5) * CELL
		var c: Array = cols.get(key.x, [INF, -INF, INF, -INF])
		cols[key.x] = [minf(c[0], yy), maxf(c[1], yy), minf(c[2], _occ[key].x), maxf(c[3], _occ[key].y)]
	var widths := []
	var thick := []
	for c in cols.values():
		widths.append(c[1] - c[0] + CELL)
		thick.append(c[3] - c[2])
	widths.sort()
	thick.sort()
	return Vector2(widths[widths.size() / 2], thick[thick.size() / 2]) * _scale()


## 曲げた指（付け根・中の関節・先の関節・指先）が囲む多角形の重心。柄はここを通るとよい
func _tube_center(finger: String) -> Vector3:
	var pts: Array[Vector3] = [_joint(finger, 1), _joint(finger, 2), _joint(finger, 3), _tip(finger)]
	var c: Vector3 = (pts[0] + pts[1] + pts[2] + pts[3]) / 4.0
	var area := 0.0
	var sum := Vector3.ZERO
	for i in range(1, 3):
		var a: float = (pts[i] - pts[0]).cross(pts[i + 1] - pts[0]).length() * 0.5
		sum += (pts[0] + pts[i] + pts[i + 1]) / 3.0 * a
		area += a
	return sum / area if area > 0.0 else c


## 指先：末節の骨に付いた頂点のうち、骨の向きに一番遠いもの
func _tip(finger: String) -> Vector3:
	var b := _bone(finger, 3)
	var far := 0.0
	for v in _bone_verts[b]:
		far = maxf(far, v.y)
	return (_to_swing * _skel.get_bone_global_pose(b)) * Vector3(0.0, far, 0.0)


func _try(mp: float, f: float, tubes: Array) -> Dictionary:
	_set_curl("index", [mp, _curl["index"][1], _curl["index"][2]])
	var info := _place(f, tubes)
	info.mp = mp
	info.f = f
	return info


## 人差し指の基節の上（付け根から長さのf）に輪の中心を置き、筒の中心をなるべく通るように柄の向きを決める。
func _place(f: float, tubes: Array) -> Dictionary:
	var a := _joint("index", 1)
	var b := _joint("index", 2)
	var d := (b - a).normalized()
	var c := a + (b - a) * f
	# 輪から各筒の中心への向きの平均（遠い筒ほど向きが確かなので距離で重みづけ）
	var down := Vector3.ZERO
	for t in tubes:
		down += (t - c)
	down = down.normalized()
	var err := 0.0
	for t in tubes:
		var v: Vector3 = t - c
		err += (v - down * v.dot(down)).length()
	err /= tubes.size()
	var xk := -down # ナイフの+Xは刃から輪へ
	# 穴の軸を人差し指の向きにできるだけ合わせ、柄と直交させる
	var zk := (-d - xk * (-d).dot(xk)).normalized()
	var yk := zk.cross(xk)
	if yk.z < 0.0: # 刃の内側の弧（ナイフの-Y）を前(-Z)へ向ける
		zk = -zk
		yk = -yk
	var slack := rad_to_deg(acos(clampf(absf(zk.dot(d)), -1.0, 1.0)))
	var basis := Basis(xk, yk, zk).scaled(Vector3.ONE * _scale())
	_knife_to_swing = Transform3D(basis, c - basis * _ring_k)
	_swing_to_knife = _knife_to_swing.affine_inverse()
	var tilt := rad_to_deg(atan2(-down.z, -down.y)) # 0で真下、正で刃の側が後ろ
	return {"err": err, "slack": slack, "tilt": tilt}


## 親指は握り拳と同じく、人差し指の中節の外側（-X）にかぶせ、先を中指の方（下）へ向ける。
## 親指の付け根（CM関節）は曲げのほかに、横へ振る（内転・外転）とひねる（対立）も使う。
## 親指の腹（末節の中ほど）と指先が目標に一番近く、ナイフに食い込まない角度を総当たりで探す。
func _solve_thumb() -> Array:
	var i2 := _joint("index", 2)
	var i3 := _joint("index", 3)
	var pad_target := (i2 + i3) * 0.5 + Vector3(-1.0, 0.0, 0.0) * THUMB_GAP
	var tip_target := pad_target + Vector3(0.0, -0.015, 0.0)
	var t3 := _bone("thumb", 3)
	var tip_y := 0.0
	for v in _bone_verts[t3]:
		tip_y = maxf(tip_y, v.y)
	var cands := []
	for tw in range(-90, 91, 15):
		for sp in range(-60, 61, 15):
			for a in range(0, 61, 10):
				for b in range(0, 81, 10):
					for c in range(0, 81, 10):
						var pose := [float(a), float(b), float(c), float(sp), float(tw)]
						_set_curl("thumb", pose)
						var g := _to_swing * _skel.get_bone_global_pose(t3)
						var pad := g * Vector3(0.0, tip_y * 0.45, 0.0)
						var tip := g * Vector3(0.0, tip_y, 0.0)
						var cost := pad.distance_to(pad_target) + tip.distance_to(tip_target) * 0.5
						cands.append([cost, pose])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	for cand in cands.slice(0, 60):
		_set_curl("thumb", cand[1])
		var hits := 0
		for k in [1, 2, 3]:
			hits += _count_hits(_bone("thumb", k))
		if hits == 0:
			print("親指：%s（目標とのずれ %.1f mm）" % [cand[1], cand[0] * 1000.0])
			return cand[1]
	print("親指：ナイフに当たらない姿勢がない。一番近いものを使う")
	return cands[0][1]


## ナイフ回し：人差し指は輪に通したまま（握りと同じ）。ほかの指は刃の通り道から外へ逃がす。
## 輪の軸まわりにナイフを1周させ、どの向きでも刃が当たらない指の形を、なるべく軽く開いた形から探す。
func _solve_spin() -> void:
	var axis := _knife_to_swing.basis.z.normalized()
	var pivot := _knife_to_swing * _ring_k
	var base := _knife_to_swing
	var turns := []
	for step in SPIN_STEPS:
		var r := Transform3D(Basis(axis, TAU * step / SPIN_STEPS), Vector3.ZERO)
		turns.append(Transform3D(Basis.IDENTITY, pivot) * r * Transform3D(Basis.IDENTITY, -pivot) * base)
	_spin_curl["index"] = _curl["index"]
	for name in ["middle", "ring", "pinky"]:
		var cands := []
		for a in range(-30, 31, 10):
			for b in range(0, 41, 10):
				for c in range(0, 31, 10):
					cands.append([float(a), float(b), float(c)])
		_spin_curl[name] = _clear_pose(name, cands, [10.0, 10.0, 5.0], turns)
	var thumbs := []
	for tw in range(-90, 31, 30):
		for sp in range(-60, 61, 30):
			for a in range(0, 41, 20):
				for b in range(0, 41, 20):
					for c in range(0, 41, 20):
						thumbs.append([float(a), float(b), float(c), float(sp), float(tw)])
	_spin_curl["thumb"] = _clear_pose("thumb", thumbs, [0.0, 20.0, 20.0, 0.0, _curl["thumb"][4]], turns)
	_knife_to_swing = base
	_swing_to_knife = base.affine_inverse()
	for name in ["middle", "ring", "pinky", "thumb"]:
		_set_curl(name, _curl[name])


## candsのうち、1周のどの向きでも刃が当たらず、prefer（軽く開いた形）に一番近いもの
func _clear_pose(name: String, cands: Array, prefer: Array, turns: Array) -> Array:
	cands.sort_custom(func(x, y): return _pose_dist(x, prefer) < _pose_dist(y, prefer))
	var best: Array = cands[0]
	var best_hits := 1 << 30
	for pose in cands:
		_set_curl(name, pose)
		var hits := 0
		for t in turns:
			_knife_to_swing = t
			_swing_to_knife = t.affine_inverse()
			for k in [1, 2, 3]:
				hits += _count_hits(_bone(name, k))
			if hits >= best_hits:
				break
		if hits < best_hits:
			best_hits = hits
			best = pose
			if hits == 0:
				break
	print("ナイフ回しの%s：%s（刃が当たる頂点 %d）" % [name, best, best_hits])
	return best


func _pose_dist(a: Array, b: Array) -> float:
	var d := 0.0
	for i in a.size():
		d += absf(a[i] - b[i])
	return d


func _report() -> void:
	print("ナイフが食い込んでいる頂点（指の内側に隠れる分は見えない）：")
	for b in _skel.get_bone_count():
		var n := _count_hits(b)
		if n > 0:
			print("  %-9s %d / %d" % [_skel.get_bone_name(b), n, _bone_verts[b].size()])


## 握りを近くから6方向で撮る（xvfb-run で表示ありのときだけ）
func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_w.grip.transform = _knife_to_swing * _model.transform.affine_inverse()
	var cam := Camera3D.new()
	cam.near = 0.005
	cam.fov = 35.0
	_w.add_child(cam)
	cam.current = true
	var views := {
		"out": Vector3(0.45, 0.05, 0.0), "in": Vector3(-0.45, 0.05, 0.0), "front": Vector3(-0.1, 0.05, -0.45),
		"top": Vector3(0.0, 0.45, 0.0), "back": Vector3(0.1, 0.1, 0.45), "below": Vector3(-0.05, -0.45, -0.05),
	}
	for v in views:
		var g := _w.swing.global_transform
		var up := g.basis.y if v != "top" and v != "below" else -g.basis.z
		cam.look_at_from_position(g * views[v], g * Vector3(0.0, -0.03, 0.0), up)
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("grip_%s.png" % v))


func _scale() -> float:
	return _model.transform.basis.get_scale().x


func _print_outputs() -> void:
	var grip: Transform3D = _knife_to_swing * _model.transform.affine_inverse()
	var ring_grip: Vector3 = _model.transform * _ring_k
	print("\n--- scenes/main.tscn の Grip ---")
	print("transform = %s" % _tscn(grip))
	print("--- scenes/main.tscn の Hand ---")
	print("ring_center = Vector3(%.5f, %.5f, %.5f)" % [ring_grip.x, ring_grip.y, ring_grip.z])
	print("--- scripts/weapon.gd ---")
	var lines := PackedStringArray()
	for name in ["index", "middle", "ring", "pinky", "thumb"]:
		var a: Array = _curl[name]
		var nums := PackedStringArray()
		for x in a:
			nums.append("%.1f" % x)
		lines.append('"%s": [%s]' % [name, ", ".join(nums)])
	print("const CURL_GRIP := {\n\t" + ", ".join(lines) + ",\n}")
	lines.clear()
	for name in ["index", "middle", "ring", "pinky", "thumb"]:
		var a: Array = _spin_curl[name]
		var nums := PackedStringArray()
		for x in a:
			nums.append("%.1f" % x)
		lines.append('"%s": [%s]' % [name, ", ".join(nums)])
	print("const CURL_SPIN := {\n\t" + ", ".join(lines) + ",\n}")


func _tscn(t: Transform3D) -> String:
	var b := t.basis
	var v := [b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, t.origin.x, t.origin.y, t.origin.z]
	var parts := PackedStringArray()
	for x in v:
		parts.append(String.num(x, 6))
	return "Transform3D(%s)" % ", ".join(parts)


# ---------------------------------------------------------------- 手

func _load_hand_verts() -> void:
	var mi: MeshInstance3D = _skel.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var skin := mi.skin
	var binds := {}
	for i in skin.get_bind_count():
		binds[i] = [_skel.find_bone(skin.get_bind_name(i)), skin.get_bind_pose(i)]
	for i in range(0, verts.size(), SUBSAMPLE):
		var bi: int = bones[i * 4]
		var bone: int = binds[bi][0]
		if not _bone_verts.has(bone):
			_bone_verts[bone] = PackedVector3Array()
		_bone_verts[bone].append((binds[bi][1] as Transform3D) * verts[i])


## 骨のいまの姿勢での頂点（Swingの座標）
func _posed(bone: int) -> PackedVector3Array:
	var t := _to_swing * _skel.get_bone_global_pose(bone)
	var out := PackedVector3Array()
	for v in _bone_verts.get(bone, PackedVector3Array()):
		out.append(t * v)
	return out


## angles：度。並びは Weapon.CURL_GRIP と同じ（親指は横とひねりも）
func _set_curl(finger: String, angles: Array) -> void:
	var a := []
	for x in angles:
		a.append(deg_to_rad(x))
	for k in 3:
		var idx := _skel.find_bone("%s_%d" % [finger, k + 1])
		_skel.set_bone_pose_rotation(idx, _skel.get_bone_rest(idx).basis.get_rotation_quaternion() * Weapon.finger_rotation(a, k))
	_skel.force_update_all_bone_transforms()


func _bone(finger: String, k: int) -> int:
	return _skel.find_bone("%s_%d" % [finger, k])


func _joint(finger: String, k: int) -> Vector3:
	return (_to_swing * _skel.get_bone_global_pose(_bone(finger, k))).origin


# ---------------------------------------------------------------- ナイフ

## ナイフを平らな板とみなし、モデルのXY平面の格子ごとに厚み（Zの範囲）を持つ。
func _build_knife_grid() -> void:
	var mi: MeshInstance3D = _model.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var aabb := mi.mesh.get_aabb()
	_cell_min = Vector2(aabb.position.x, aabb.position.y)
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var lo := _cell(Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y))))
		var hi := _cell(Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y))))
		var zlo := minf(a.z, minf(b.z, c.z))
		var zhi := maxf(a.z, maxf(b.z, c.z))
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var key := Vector2i(x, y)
				var z: Vector2 = _occ.get(key, Vector2(INF, -INF))
				_occ[key] = Vector2(minf(z.x, zlo), maxf(z.y, zhi))
	# モデルの座標 → Gripの座標（_fitで決まる）
	var mesh_to_model: Transform3D = _model.global_transform.affine_inverse() * mi.global_transform
	assert(mesh_to_model.is_equal_approx(Transform3D.IDENTITY))
	_margin_k = MARGIN / _model.transform.basis.get_scale().x
	_gw = int(ceil(aabb.size.x / CELL)) + 3
	_gh = int(ceil(aabb.size.y / CELL)) + 3
	_build_dense()


func _build_dense() -> void:
	_gzmin.resize(_gw * _gh)
	_gzmax.resize(_gw * _gh)
	_gzmin.fill(INF)
	_gzmax.fill(-INF)
	for k in _occ:
		var z: Vector2 = _occ[k]
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var x: int = k.x + dx
				var y: int = k.y + dy
				if x < 0 or y < 0 or x >= _gw or y >= _gh:
					continue
				var i := y * _gw + x
				_gzmin[i] = minf(_gzmin[i], z.x - _margin_k)
				_gzmax[i] = maxf(_gzmax[i], z.y + _margin_k)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(((p - _cell_min) / CELL).floor())


## 輪の穴：外とつながっていない空きの格子のうち一番大きいかたまり。中心と内接円の半径（モデルの単位）
func _find_ring() -> Array:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for k in _occ:
		lo = Vector2i(mini(lo.x, k.x), mini(lo.y, k.y))
		hi = Vector2i(maxi(hi.x, k.x), maxi(hi.y, k.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var outside := {}
	var stack: Array[Vector2i] = [lo]
	outside[lo] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < lo.x or n.y < lo.y or n.x > hi.x or n.y > hi.y or outside.has(n) or _occ.has(n):
				continue
			outside[n] = true
			stack.append(n)
	var best := []
	var seen := {}
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var s := Vector2i(x, y)
			if _occ.has(s) or outside.has(s) or seen.has(s):
				continue
			var blob: Array[Vector2i] = []
			var st: Array[Vector2i] = [s]
			seen[s] = true
			while not st.is_empty():
				var c: Vector2i = st.pop_back()
				blob.append(c)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if _occ.has(n) or outside.has(n) or seen.has(n):
						continue
					seen[n] = true
					st.append(n)
			if blob.size() > best.size():
				best = blob
	var sum := Vector2.ZERO
	for c in best:
		sum += Vector2(c) + Vector2(0.5, 0.5)
	var center := _cell_min + sum / best.size() * CELL
	var radius := sqrt(best.size() * CELL * CELL / PI)
	var zs := Vector2(INF, -INF)
	for k in _occ:
		if (Vector2(k) * CELL + _cell_min).distance_to(center) < radius * 2.5:
			zs = Vector2(minf(zs.x, _occ[k].x), maxf(zs.y, _occ[k].y))
	return [Vector3(center.x, center.y, (zs.x + zs.y) * 0.5), radius]


## Swingの座標の点がナイフに食い込んでいるか（MARGINだけ太らせて判定）
func _hits_knife(p_swing: Vector3) -> bool:
	var p := _swing_to_knife * p_swing
	var x := int(floor((p.x - _cell_min.x) / CELL))
	var y := int(floor((p.y - _cell_min.y) / CELL))
	if x < 0 or y < 0 or x >= _gw or y >= _gh:
		return false
	var i := y * _gw + x
	return p.z >= _gzmin[i] and p.z <= _gzmax[i]


func _count_hits(bone: int) -> int:
	var n := 0
	for p in _posed(bone):
		if _hits_knife(p):
			n += 1
	return n
