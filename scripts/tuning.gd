extends Node
## 手触りに関わる値をまとめて持つ。デバッグUIのスライダーはSPECSから自動で作られる。
## 値を決めたら、ここの初期値を書き換え、仕様書の改善ログに残す。

# key, 表示名, 最小, 最大, 刻み
const SPECS := [
	["max_speed", "最高速度 (m/s)", 2.0, 20.0, 0.1],
	["ground_accel", "地上の加速 (m/s²)", 5.0, 200.0, 1.0],
	["ground_decel", "地上の減速 (m/s²)", 5.0, 200.0, 1.0],
	["air_accel", "空中の加速 (m/s²)", 0.0, 100.0, 1.0],
	["air_decel", "空中の減速 (m/s²)", 0.0, 50.0, 0.5],
	["jump_velocity", "ジャンプ初速 (m/s)", 2.0, 15.0, 0.1],
	["gravity", "重力 (m/s²)", 5.0, 60.0, 0.5],
	["fall_gravity_mult", "落下時の重力倍率", 1.0, 4.0, 0.05],
	["jump_cut", "ボタンを離した時の上昇維持率", 0.0, 1.0, 0.05],
	["coyote_time", "コヨーテタイム (秒)", 0.0, 0.3, 0.01],
	["jump_buffer", "先行入力の受付 (秒)", 0.0, 0.3, 0.01],
	["stick_deadzone", "スティックのデッドゾーン", 0.0, 0.5, 0.01],
	["look_speed", "右スティックの視点速度 (度/秒)", 30.0, 600.0, 5.0],
	["look_curve", "右スティックの応答カーブ", 1.0, 3.0, 0.1],
	["mouse_sensitivity", "マウス感度 (度/px)", 0.01, 0.5, 0.01],
	["fov", "視野角 (度)", 60.0, 120.0, 1.0],
	["head_bob", "頭の揺れ (m, 0でオフ)", 0.0, 0.1, 0.005],
	["wallrun_min_speed", "壁走りに入る最低速度 (m/s)", 0.0, 15.0, 0.1],
	["wallrun_max_angle", "壁走りに入れる壁との角度 (度)", 10.0, 90.0, 1.0],
	["wallrun_max_time", "壁走りの継続時間の上限 (秒)", 0.2, 5.0, 0.05],
	["wallrun_up_speed", "壁走り開始時の上向き速度 (m/s)", 0.0, 8.0, 0.1],
	["wallrun_gravity_mult", "壁走り中の重力倍率", 0.0, 1.0, 0.01],
	["wallrun_tilt", "壁走り中のカメラの傾き (度, 0でオフ)", 0.0, 20.0, 0.5],
]

var max_speed := 8.0
var ground_accel := 60.0
var ground_decel := 50.0
var air_accel := 20.0
var air_decel := 0.0 # 0なら空中で勢いが落ちない（大原則）
var jump_velocity := 6.5
var gravity := 16.0
var fall_gravity_mult := 1.6
var jump_cut := 0.5
var coyote_time := 0.10
var jump_buffer := 0.12
var stick_deadzone := 0.15
var look_speed := 220.0
var look_curve := 1.6
var mouse_sensitivity := 0.12
var fov := 90.0
var head_bob := 0.015
var wallrun_min_speed := 4.0
var wallrun_max_angle := 60.0 # 壁に対して正面に近い角度で当たったら壁走りにしない
var wallrun_max_time := 1.75 # 初代Titanfallの値
var wallrun_up_speed := 2.0
var wallrun_gravity_mult := 0.25
var wallrun_tilt := 6.0 # 一人称では酔いに直結するので控えめ

var _defaults := {}


func _ready() -> void:
	for spec in SPECS:
		_defaults[spec[0]] = get(spec[0])


func reset_all() -> void:
	for key in _defaults:
		set(key, _defaults[key])


## 改善ログに貼るための「key = 値」一覧。
func dump() -> String:
	var lines := PackedStringArray()
	for spec in SPECS:
		lines.append("%s = %s" % [spec[0], str(get(spec[0]))])
	return "\n".join(lines)
