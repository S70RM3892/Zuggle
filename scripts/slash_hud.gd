extends Control
## 斬撃モードの表示（M4）。画面中央に円とスティックの位置、弾いた直後は斬った向きの線を出す。

const RADIUS := 44.0
const TRAIL_TIME := 0.25 # 斬った向きの線を出している時間 (秒)

@export var weapon_path: NodePath

@onready var _weapon: Weapon = get_node(weapon_path)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	if _weapon.slash_mode_active():
		draw_arc(c, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
		draw_circle(c + _weapon.slash_stick() * RADIUS, 4.0, Color(1, 1, 1, 0.8))
	var s: Dictionary = _weapon.last_slash
	if s.is_empty():
		return
	var age := (Time.get_ticks_msec() - int(s.at)) / 1000.0
	if age > TRAIL_TIME:
		return
	var d := Vector2(s.dir.x, -s.dir.y) # 画面の座標は下が+y
	var length := RADIUS * (1.2 + 1.6 * float(s.strength))
	var a := 1.0 - age / TRAIL_TIME
	draw_line(c - d * length * 0.5, c + d * length * 0.5, Color(0.6, 0.95, 1.0, 0.9 * a), 2.0 + 4.0 * float(s.strength), true)
