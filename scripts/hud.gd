extends CanvasLayer
## 画面の表示。動きの技の結果（スーパーグライドの成否と、ジャンプとしゃがみの間の長さ）を照準の少し上に出す。
## 手とナイフは画面の右下から中央下にあるので、文字は空の側に置いて重ねない。
## 失敗したときは何が悪かったか（早すぎ・遅すぎ・どちらが何ms早い）を出し、練習の手がかりにする。

const SHOW_TIME := 1.6
const FADE_TIME := 0.4
const DOT_COLOR := Color(1, 1, 1, 0.85)
const DOT_GLIDE := Color(0.4, 1.0, 0.5, 1.0)

@export var player_path: NodePath

var _label: Label
var _t := 0.0
var _player: Player

@onready var _dot: ColorRect = $CenterDot


func _ready() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.anchor_top = 0.5
	_label.anchor_bottom = 0.5
	_label.offset_left = -400.0
	_label.offset_right = 400.0
	_label.offset_top = -150.0
	_label.offset_bottom = -110.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.modulate.a = 0.0
	add_child(_label)
	_player = get_node_or_null(player_path)
	if _player:
		_player.move_tech.connect(_on_move_tech)


func _process(delta: float) -> void:
	_t -= delta
	_label.modulate.a = clampf(_t / FADE_TIME, 0.0, 1.0)
	# 練習用：スーパーグライドの受付中は照準の点を緑にする
	var hint := _player != null and Tuning.superglide_hint > 0.5 and _player.superglide_window()
	_dot.color = DOT_GLIDE if hint else DOT_COLOR


func _on_move_tech(text: String, success: bool) -> void:
	_label.text = text
	_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65) if success else Color(1.0, 0.82, 0.45))
	_t = SHOW_TIME


func last_text() -> String:
	return _label.text if _t > 0.0 else ""
