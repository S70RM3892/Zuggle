extends Node
## リポジトリのすべての .gd を読み込み、読めないものを LINT FAIL として出す。
## 自動読み込み（Tuning・HitFeel）が効くようにシーンとして実行する：
##   godot --headless --path . res://tools/lint.tscn


func _ready() -> void:
	var failed := 0
	for path in _scripts("res://"):
		if path == get_script().resource_path:
			continue  # 実行中の自分を読み直すとVMが壊れる
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if script == null or not script.can_instantiate():
			print("LINT FAIL ", path)
			failed += 1
	print("lint: ok" if failed == 0 else "lint: %d FAILED" % failed)
	get_tree().quit(1 if failed > 0 else 0)


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			out.append_array(_scripts(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			out.append(dir.path_join(file))
	return out
