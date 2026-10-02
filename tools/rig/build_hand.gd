extends Node
## models/hand.glb（骨なし）に骨格と重みを付けて models/hand_rigged.scn に保存する。
## 関節の位置と頂点ごとの骨は tools/rig/analyze_hand.py が rig.json に書き出す。
## 実行：godot --headless --path . res://tools/rig/build_hand.tscn
##
## できるシーン：Hand(Node3D) → Model(向きと大きさ) → Skeleton3D → Mesh
## Hand の座標では -Z が指先、+Y が親指側、-X が手のひら側。原点はナイフの柄を握る位置。

const SRC := "res://models/hand.glb"
const JSON_PATH := "res://tools/rig/rig.json"
const OUT := "res://models/hand_rigged.scn"
const SCALE := 0.19 # 手のひらの幅0.64 → 約0.12m（ナイフの柄に合わせる）
const PALM_OFFSET := 0.18 # 握る位置：指の付け根から手のひら側へ（モデルの単位）
const GRIP_BACK := 0.05
const CELL := 0.01 # 頂点を探す格子の大きさ（モデルの単位） # 握る位置：指の付け根から手首側へ（モデルの単位）


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	var joints: Dictionary = data.joints
	var bone_names: Array = data.bones
	var key_map: Dictionary = data.map
	var fr: Dictionary = joints.frame
	var c := _v(fr.c)
	var a := _v(fr.a) # 指先→前腕
	var b := _v(fr.b) # 親指側
	var cc := _v(fr.cc) # 手の甲側（手のひらは -cc）

	var src: Node3D = load(SRC).instantiate()
	var mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays := mi.mesh.surface_get_arrays(0)
	var material := mi.get_active_material(0)

	# 頂点ごとの骨（位置で引く）
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(verts.size() * 4)
	weights.resize(verts.size() * 4)
	# 取り込み時に頂点位置が圧縮されて少しずれるので、格子で近い点を探す
	var grid := {}
	for key in key_map:
		var parts: PackedStringArray = key.split(",")
		var q := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		var cell := Vector3i((q / CELL).floor())
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append([q, int(key_map[key])])
	var missing := 0
	for i in verts.size():
		var p := verts[i]
		var base := Vector3i((p / CELL).floor())
		var best := INF
		var bi := 0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					for e in grid.get(base + Vector3i(dx, dy, dz), []):
						var d: float = p.distance_squared_to(e[0])
						if d < best:
							best = d
							bi = e[1]
		if best > CELL * CELL:
			missing += 1
		bones[i * 4] = bi
		weights[i * 4] = 1.0
	print("頂点 %d、近くに元の頂点がなかった頂点 %d" % [verts.size(), missing])
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)

	# 骨格：各骨はY軸が骨の向き、Z軸が手のひら側。X軸まわりの正の回転で手のひら側へ曲がる
	var palm := -cc
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	var globals := {}
	var heads := {"hand": _v(joints.wrist)}
	var tails := {"hand": (_v(joints.middle[0]))}
	for f in ["index", "middle", "ring", "pinky", "thumb"]:
		var j: Array = joints[f]
		for k in 3:
			heads["%s_%d" % [f, k + 1]] = _v(j[k])
			tails["%s_%d" % [f, k + 1]] = _v(j[k + 1])
	for name in bone_names:
		var idx := skel.add_bone(name)
		var parent := -1
		if name != "hand":
			var parts: PackedStringArray = name.split("_")
			var n := int(parts[1])
			parent = skel.find_bone("hand") if n == 1 else skel.find_bone("%s_%d" % [parts[0], n - 1])
			skel.set_bone_parent(idx, parent)
		var g := _bone_frame(heads[name], tails[name], palm)
		globals[name] = g
		var local: Transform3D = g if parent < 0 else (globals[bone_names[parent]] as Transform3D).affine_inverse() * g
		skel.set_bone_rest(idx, local)
		skel.set_bone_pose(idx, local)

	var skin := Skin.new()
	for name in bone_names:
		skin.add_named_bind(name, (globals[name] as Transform3D).affine_inverse())

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mesh
	mesh_node.skin = skin

	# モデルの座標 → 手の座標：a→+Z、b→+Y、cc→+X
	var basis := Basis(Vector3(cc.x, b.x, a.x), Vector3(cc.y, b.y, a.y), Vector3(cc.z, b.z, a.z)).scaled(Vector3.ONE * SCALE)
	var mcp := (_v(joints.index[0]) + _v(joints.middle[0]) + _v(joints.ring[0]) + _v(joints.pinky[0])) / 4.0
	var grip := mcp + palm * PALM_OFFSET + a * GRIP_BACK
	var model := Node3D.new()
	model.name = "Model"
	model.transform = Transform3D(basis, -(basis * grip))

	var root := Node3D.new()
	root.name = "Hand"
	root.add_child(model)
	model.owner = root
	model.add_child(skel)
	skel.owner = root
	skel.add_child(mesh_node)
	mesh_node.owner = root
	mesh_node.skeleton = NodePath("..")

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT)
	print("保存 %s：%s" % [OUT, error_string(err)])
	get_tree().quit(0 if err == OK and missing < verts.size() / 100 else 1)


func _v(arr) -> Vector3:
	return Vector3(arr[0], arr[1], arr[2])


func _bone_frame(head: Vector3, tail: Vector3, palm: Vector3) -> Transform3D:
	var y := (tail - head).normalized()
	var z := (palm - y * palm.dot(y)).normalized()
	var x := y.cross(z).normalized()
	z = x.cross(y)
	return Transform3D(Basis(x, y, z), head)
