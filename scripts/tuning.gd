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
	["wallrun_turn_accel", "壁走りの折り返しの速さ (m/s²)", 5.0, 200.0, 1.0],
	["wall_jump_push", "壁ジャンプの離れる速さ (m/s)", 0.0, 15.0, 0.1],
	["wall_jump_up", "壁ジャンプの上向き速度 (m/s)", 0.0, 15.0, 0.1],
	["mantle_max_height", "よじ登れる段差の高さ (m, 足から)", 0.5, 3.0, 0.05],
	["mantle_time", "よじ登りの時間 (秒)", 0.1, 1.0, 0.01],
	["mantle_exit_speed", "よじ登った直後の速さ (m/s)", 0.0, 10.0, 0.1],
	["superglide_speed", "スーパーグライドの速さ (m/s)", 5.0, 20.0, 0.1],
	["superglide_up", "スーパーグライドの上向き速度 (m/s)", 0.0, 8.0, 0.1],
	["superglide_gap", "スーパーグライド ジャンプとしゃがみの間 (秒)", 0.0, 0.2, 0.005],
	["superglide_grace", "スーパーグライド 登り切った後の受付 (秒)", 0.0, 0.3, 0.01],
	["slide_min_speed", "スライディングに入る最低速度 (m/s)", 0.0, 15.0, 0.1],
	["slide_end_speed", "スライディングが終わる速度 (m/s)", 0.0, 10.0, 0.1],
	["slide_friction", "スライディングの減速 (m/s²)", 0.0, 30.0, 0.5],
	["slide_steer", "スライディング中の曲がりやすさ", 0.0, 10.0, 0.1],
	["slide_camera_drop", "スライディング中に下げる目の高さ (m)", 0.0, 1.0, 0.05],
	["speed_fov", "最高速度を超えた分の視野角の広がり (度, 0でオフ)", 0.0, 20.0, 0.5],
	["attack_buffer", "攻撃の先行入力 (秒)", 0.0, 0.3, 0.01],
	["attack_windup", "攻撃の振りかぶり (秒)", 0.0, 0.3, 0.01],
	["attack_active", "攻撃の判定時間 (秒)", 0.02, 0.3, 0.01],
	["attack_recovery", "攻撃の戻り (秒)", 0.0, 0.5, 0.01],
	["hitstop_min", "ヒットストップ 威力最小 (秒)", 0.0, 0.3, 0.005],
	["hitstop_max", "ヒットストップ 威力最大 (秒)", 0.0, 0.3, 0.005],
	["shake_trauma", "画面揺れ 1発のトラウマ値 (0でオフ)", 0.0, 1.0, 0.01],
	["shake_max_angle", "画面揺れ 最大角度 (度)", 0.0, 10.0, 0.1],
	["shake_decay", "画面揺れ 減衰 (/秒)", 0.2, 6.0, 0.1],
	["shake_freq", "画面揺れ 周波数 (Hz)", 2.0, 60.0, 1.0],
	["rumble_strength", "振動の強さ (0でオフ)", 0.0, 1.0, 0.05],
	["rumble_duration", "振動の長さ (秒)", 0.02, 0.5, 0.01],
	["dummy_knockback", "ダミーの吹き飛び (m/s)", 0.0, 10.0, 0.1],
	["dummy_tilt", "ダミーのよろけ (rad/s)", 0.0, 10.0, 0.1],
	["dummy_stiffness", "ダミーの戻る強さ", 5.0, 300.0, 1.0],
	["dummy_damping", "ダミーの戻りの減衰", 0.0, 40.0, 0.5],
	["dummy_squash", "ダミーの伸び縮み", 0.0, 1.0, 0.01],
	["weapon_squash", "手・武器の伸び縮み", 0.0, 0.5, 0.01],
	["slash_trail", "斬撃の軌跡の明るさ (0でオフ)", 0.0, 1.5, 0.05],
	["hand_sway", "視点を回したときの手の遅れ (0でオフ)", 0.0, 3.0, 0.1],
	["superglide_hint", "スーパーグライドの受付中に照準を緑にする (0でオフ)", 0.0, 1.0, 1.0],
	["sfx_pitch_spread", "効果音のピッチのずれ (±)", 0.0, 0.3, 0.01],
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
var wallrun_turn_accel := 40.0 # 8 m/sなら約0.4秒で折り返す
var wall_jump_push := 5.0
var wall_jump_up := 6.0
var mantle_max_height := 2.0 # 目の高さ(1.65m)＋腕の届く分。ジャンプで届かない1.5mや2mの段にも登れる
var mantle_time := 0.4
var mantle_exit_speed := 4.0 # 登り切ると勢いが落ちる。スーパーグライドはこれを取り返す技
var superglide_speed := 10.9 # Apexは走り7.59 m/sに対して10.3 m/s（約1.36倍）。最高速度8 m/sの1.36倍
var superglide_up := 3.5 # 低く速く飛ぶ
var superglide_gap := 0.05 # Apexは2フレーム以内。パッドの指の転がしで出せる幅にする
var superglide_grace := 0.1
var slide_min_speed := 6.0
var slide_end_speed := 4.0
var slide_friction := 5.0
var slide_steer := 2.0
var slide_camera_drop := 0.5
var speed_fov := 6.0 # 一人称では酔いに直結するので控えめ
var attack_buffer := 0.12
var attack_windup := 0.05
var attack_active := 0.10
var attack_recovery := 0.15
var hitstop_min := 0.05 # 仕様の初期値50〜100msを威力で割り振る
var hitstop_max := 0.10
var shake_trauma := 0.35 # 一人称では酔いに直結するので小さめから
var shake_max_angle := 1.5
var shake_decay := 1.5
var shake_freq := 25.0
var rumble_strength := 0.8
var rumble_duration := 0.12
var dummy_knockback := 5.0
var dummy_tilt := 5.0
var dummy_stiffness := 80.0
var dummy_damping := 9.0 # 減衰比0.5前後。少し行き過ぎてから戻る
var dummy_squash := 0.25
var weapon_squash := 0.15
var slash_trail := 1.0
var hand_sway := 1.0
var superglide_hint := 1.0 # 練習用。受付の長さを体で覚えたら0にする
var sfx_pitch_spread := 0.08

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
