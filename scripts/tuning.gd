extends Node
## 手触りに関わる値をまとめて持つ。デバッグUIのスライダーはSPECSから自動で作られる。
## 値を決めたら、ここの初期値を書き換え、仕様書（docs/SPEC.md）の改善ログに残す。

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
	["ground_overspeed_decel", "最高速度を超えた分の地上での減り (m/s²)", 0.0, 60.0, 0.5],
	["slide_min_speed", "スライディングに入る最低速度 (m/s)", 0.0, 12.0, 0.1],
	["slide_boost", "スライディングの加速 (m/s)", 0.0, 6.0, 0.1],
	["slide_boost_cap", "スライディングの加速で届く上限 (m/s)", 5.0, 25.0, 0.5],
	["slide_boost_cooldown", "スライディングの加速の待ち (秒)", 0.0, 3.0, 0.05],
	["slide_friction", "スライディングの減速 (m/s²)", 0.0, 20.0, 0.25],
	["slide_steer", "スライディング中に曲がる速さ (度/秒)", 0.0, 180.0, 5.0],
	["slide_end_speed", "この速さを下回るとスライディング終了 (m/s)", 0.0, 8.0, 0.1],
	["slide_min_time", "ボタンを離してもスライディングを続ける最短 (秒)", 0.0, 1.0, 0.05],
	["slide_buffer", "しゃがみの先行入力（着地でスライディング）(秒)", 0.0, 0.5, 0.01],
	["slide_tilt", "スライディング中のカメラの傾き (度, 0でオフ)", 0.0, 10.0, 0.5],
	["crouch_speed", "しゃがみ歩きの速さ (m/s)", 1.0, 6.0, 0.1],
	["crouch_cam_time", "しゃがむ・立つときの目線の移動時間 (秒)", 0.02, 0.4, 0.01],
	["wallclimb_speed", "壁登りの上向き速度 (m/s)", 0.0, 12.0, 0.1],
	["wallclimb_gravity_mult", "壁登り中の重力倍率", 0.0, 1.5, 0.05],
	["wallclimb_max_time", "壁登りの継続時間の上限 (秒)", 0.1, 2.0, 0.05],
	["wallclimb_min_vy", "壁登りに入れる最低の上下速度 (m/s)", -10.0, 5.0, 0.25],
	["wallclimb_top_push", "壁の上端を越えたときの前への押し出し (m/s)", 0.0, 6.0, 0.1],
	["hard_landing_speed", "着地：これ以上の落下の速さで強い着地 (m/s)", 6.0, 30.0, 0.5],
	["hard_landing_keep", "強い着地で残る水平速度の割合", 0.0, 1.0, 0.05],
	["hard_landing_time", "強い着地で体勢を崩している時間 (秒)", 0.0, 1.5, 0.05],
	["roll_window", "受け身：着地の何秒前までのBを受け付けるか (秒)", 0.0, 0.6, 0.01],
	["roll_late", "受け身：着地の後に押しても間に合う時間 (秒)", 0.0, 0.3, 0.01],
	["roll_time", "受け身の長さ (秒)", 0.1, 1.2, 0.05],
	["roll_min_speed", "受け身で前へ出る最低の速さ (m/s)", 0.0, 10.0, 0.1],
	["land_dip", "着地で視点が前へ倒れる角度 (度, 0でオフ)", 0.0, 60.0, 1.0],
	["land_shake", "強い着地の画面揺れ (0でオフ)", 0.0, 1.0, 0.01],
	["hand_buffer", "手のアクションの先行入力 (秒)", 0.0, 0.4, 0.01],
	["ledge_reach_top", "縁掴み：手が届く高さ（足元から）(m)", 1.5, 3.5, 0.05],
	["ledge_reach_bottom", "縁掴み：これより低い縁は掴まない（足元から）(m)", 0.0, 1.5, 0.05],
	["ledge_reach_dist", "縁掴み：壁までの距離（体の表面から）(m)", 0.2, 1.5, 0.05],
	["mantle_time", "縁から登り切るまでの時間 (秒)", 0.1, 0.8, 0.01],
	["mantle_keep", "縁掴み・壁の上端越えで持ち出す水平速度の割合", 0.0, 1.0, 0.05],
	["mantle_min_exit", "縁掴みの後の最低の前向き速度 (m/s)", 0.0, 10.0, 0.1],
	["pole_reach", "ポール：手が届く距離（ポールの中心から）(m)", 0.4, 2.5, 0.05],
	["pole_radius", "ポール：回る半径 (m)", 0.3, 1.5, 0.05],
	["pole_min_speed", "ポール：回る最低速度 (m/s)", 0.0, 12.0, 0.1],
	["pole_max_time", "ポール：掴んでいられる上限 (秒)", 0.2, 3.0, 0.05],
	["pole_gravity_mult", "ポール：掴んでいる間の重力倍率", 0.0, 1.0, 0.01],
	["pole_release_boost", "ポール：離すときの加速 (m/s)", 0.0, 6.0, 0.1],
	["pole_release_up", "ポール：離すときの上向き速度 (m/s)", 0.0, 8.0, 0.1],
	["pole_camera_follow", "ポール：回る分だけ視点も回す割合", 0.0, 1.0, 0.05],
	["vault_reach", "ボールト：障害物までの距離（体の表面から）(m)", 0.2, 2.0, 0.05],
	["vault_min_height", "ボールト：越えられる最低の高さ (m)", 0.0, 1.0, 0.05],
	["vault_max_height", "ボールト：越えられる最高の高さ (m)", 0.5, 2.0, 0.05],
	["vault_time", "ボールトの時間 (秒)", 0.1, 0.8, 0.01],
	["vault_boost", "ボールトの加速 (m/s)", 0.0, 6.0, 0.1],
	["vault_min_exit", "ボールトの後の最低の前向き速度 (m/s)", 0.0, 10.0, 0.1],
	["wall_push_reach", "壁押し：壁までの距離（体の表面から）(m)", 0.2, 2.0, 0.05],
	["wall_push_speed", "壁押し：壁から離れる速さ (m/s)", 0.0, 15.0, 0.1],
	["wall_push_up", "壁押し：上向き速度 (m/s)", 0.0, 10.0, 0.1],
	["hand_reach_time", "手を伸ばして届くまでの時間 (秒)", 0.02, 0.3, 0.01],
	["hand_return_time", "手が戻るまでの時間 (秒)", 0.05, 0.6, 0.01],
	["arm_swing", "走るときの腕の振り (m, 0でオフ)", 0.0, 0.2, 0.005],
	["leg_swing", "走るときの脚の振り (度)", 0.0, 80.0, 1.0],
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
	["sfx_volume", "パルクールの効果音の音量 (0でオフ)", 0.0, 1.0, 0.05],
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
var ground_overspeed_decel := 4.0 # 12 m/sで着地しても、走り続ければ1秒で8 m/sへ戻る
var slide_min_speed := 5.0
var slide_boost := 2.5
var slide_boost_cap := 12.0 # 加速だけでこれ以上にはならない（勢いを持ち込んだ分は削らない）
var slide_boost_cooldown := 1.0 # Titanfall 2のスライドブーストと同じく、連打では重ならない
var slide_friction := 4.0
var slide_steer := 45.0
var slide_end_speed := 3.5
var slide_min_time := 0.35
var slide_buffer := 0.2
var slide_tilt := 3.0
var crouch_speed := 3.0
var crouch_cam_time := 0.12
var wallclimb_speed := 6.5
var wallclimb_gravity_mult := 0.55 # 約2.4m登れる
var wallclimb_max_time := 0.75
var wallclimb_min_vy := -3.0 # 落ち始めてすぐなら登れる。深く落ちていたら登れない
var wallclimb_top_push := 2.5
var hard_landing_speed := 13.5 # 約3.6mの落下。2mの台から跳び降りても（約3.3m）強い着地にはならない
var hard_landing_keep := 0.3
var hard_landing_time := 0.4
var roll_window := 0.3
var roll_late := 0.08
var roll_time := 0.45
var roll_min_speed := 4.0
var land_dip := 25.0 # 一回転させると酔うので、うなずく程度
var land_shake := 0.3
var hand_buffer := 0.15
var ledge_reach_top := 2.3 # 片手を上へ伸ばした指先の高さ
var ledge_reach_bottom := 0.6
var ledge_reach_dist := 0.7
var mantle_time := 0.32
var mantle_keep := 0.85
var mantle_min_exit := 3.0
var pole_reach := 1.2
var pole_radius := 0.7
var pole_min_speed := 5.0
var pole_max_time := 1.2
var pole_gravity_mult := 0.15
var pole_release_boost := 1.5
var pole_release_up := 3.0
var pole_camera_follow := 1.0
var vault_reach := 0.9
var vault_min_height := 0.3
var vault_max_height := 1.3
var vault_time := 0.3
var vault_boost := 1.5
var vault_min_exit := 4.0
var wall_push_reach := 0.8
var wall_push_speed := 6.0
var wall_push_up := 3.0
var hand_reach_time := 0.07
var hand_return_time := 0.18
var arm_swing := 0.06
var leg_swing := 40.0
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
var sfx_volume := 0.8
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
