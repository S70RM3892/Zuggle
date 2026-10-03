class_name Weapon
extends Node3D
## 一人称の手と武器。通常攻撃（X / 左クリック）の振り、当たり判定、伸び縮み、壁へのめり込み防止、
## ナイフ回し（Y / F）。M4：アナログ斬り（RT / 右クリックを押しながら右スティック / マウスを弾く）。
## 手は Swing/HandModel（骨入りのメカの手）、武器は Swing/Grip の下に置く。
## res://models/weapon.glb があればそれを、なければ箱の剣を使う。
## 当たり判定は見た目のメッシュを使わず、Swing の前(-Z)へ伸ばした細長い箱で取る。

enum State { IDLE, WINDUP, ACTIVE, RECOVERY, INSPECT }

# 指の曲げ角（度）。各指は付け根・中・先の3関節。正で手のひら側へ曲がる。値は tools/rig/solve_grip.tscn で求める
# 中指〜小指：円柱を握ったときの実測（Ishii ら 2019、CTで直径10mmと60mm）を柄の太さ（人の手なら直径約30mm）で内挿
# 人差し指：輪に通して付け根を90度曲げる
const CURL_GRIP := {
	"index": [90.0, 83.0, 43.1], "middle": [64.3, 82.6, 52.9], "ring": [61.8, 86.3, 45.4],
	"pinky": [52.8, 69.4, 51.8], "thumb": [0.0, 40.0, 80.0],
}
# ナイフを回している間：人差し指は輪に通したまま（握りと同じ）。ほかの指は、ナイフを1周させても
# どの向きでも刃が当たらない所へ逃がす（tools/rig/solve_grip.tscn で確かめた形）
const CURL_SPIN := {
	"index": [90.0, 83.0, 43.1], "middle": [-10.0, 10.0, 0.0], "ring": [-10.0, 0.0, 10.0],
	"pinky": [0.0, 10.0, 0.0], "thumb": [0.0, 20.0, 20.0],
}
# 親指は曲げ（握り）を CURL_GRIP の代わりにここで持ち、付け根を横へ振る角度（骨のZ軸まわり）と
# ひねる角度（骨のY軸まわり。親指の対立）も足す。握りでは人差し指の中節の上にかぶせる
@export var thumb_grip := Vector3(0.0, 40.0, 80.0)
@export var thumb_across := 0.0
@export var thumb_across_spin := -30.0
@export var thumb_twist := -60.0
## ナイフの輪の穴の中心（Gripの座標）。輪を人差し指に通す位置とナイフ回しの軸。tools/rig/solve_grip で求める。
## 0なら柄頭の側の頂点からおおまかに求める
@export var ring_center := Vector3.ZERO
## 輪の中心を人差し指の基節のどこに置くか（付け根の節0〜中の節1）。指が輪に食い込まない範囲で一番根元
@export var ring_along := 0.65
# ナイフ眺め（Y / F）：刃を見せる → 返して裏を見せる → 人差し指を軸に回す → 握り直して構えに戻る
const INSPECT_TIME := 2.4
const SPIN_TURNS := 2.0
# 姿勢のキー：[時刻（INSPECT_TIMEに対する割合）, rot, pos, 手首の曲げ（度。x=内へ、y=上へ）]
const INSPECT_KEYS := [
	[0.14, Vector3(10.0, 6.0, 30.0), Vector3(-0.05, 0.05, -0.02), Vector3(70.0, 10.0, 0.0)], # 手首を内へ曲げ、刃の面をこちらへ向ける
	[0.30, Vector3(14.0, 8.0, 15.0), Vector3(-0.05, 0.055, -0.03), Vector3(60.0, 20.0, 0.0)], # 少し傾けて眺める
	[0.40, Vector3(10.0, 4.0, 140.0), Vector3(-0.05, 0.04, -0.02), Vector3(50.0, 0.0, 0.0)], # 手のひらを上へ返して裏の面
	[0.48, Vector3(10.0, 8.0, 15.0), Vector3(-0.04, 0.04, -0.02), Vector3.ZERO], # 回す構え
	[0.80, Vector3(9.0, 10.0, 20.0), Vector3(-0.04, 0.045, -0.02), Vector3.ZERO],
	[0.86, Vector3(2.0, 8.0, 4.0), Vector3(-0.02, 0.0, -0.04), Vector3(-12.0, 0.0, 0.0)], # 握り直して手首を軽く振る
	[1.0, IDLE_ROT, Vector3.ZERO, Vector3.ZERO],
]
const SPIN_FROM := 0.48 # 回し始め・終わり（割合）
const SPIN_TO := 0.82
# ナイフの回り方：指ではじいた勢いで回り、刃先が上へ行くときは重さで遅く、下るときは速くなる。
# 指の摩擦で少しずつ遅くなり、最後は指で受け止めて止める
const SPIN_FLICK := 0.12 # はじいて最高速になるまでの角度（ラジアン）
const SPIN_GRAVITY := 0.22 # 刃先の高さ1あたりの速さ²の減り（はじいた直後の速さ²を1とする）
const SPIN_FRICTION := 0.035 # 1ラジアンあたりの速さ²の減り
const SPIN_CATCH := 0.6 # 受け止めて止めるまでの角度（ラジアン）
const SPIN_STEPS := 256
const OPEN_FROM := 0.43 # 指を開き始め・閉じ終わり（割合）
const OPEN_TO := 0.86

const MODEL_PATH := "res://models/weapon.glb"
const WEAPON_GLOW := preload("res://models/weapon_emission.png")
const HAND_GLOW := preload("res://models/hand_emission.png")
const VIEW_LAYER := 2 # 手と武器だけの描画の層。手元用の補助光（ViewLight）はこの層だけを照らす
const HURTBOX_LAYER := 2 # ダミーなど、斬られる側の当たり判定の層
const HIT_THICKNESS := 0.35
const RETRACT_REACH := 1.0 # 目の前の壁がこれより近いと武器を引っ込める (m)
const RETRACT_MAX := 0.45
const SQUASH_STIFFNESS := 300.0
const SQUASH_DAMPING := 18.0

# 姿勢：rot＝肘（拳の後ろ ELBOW）を中心にした回転（度。x=刃先の上下、y=刃先の左右（正で左）、z=ひねり）、
# pos＝拳の位置のずれ (m)。肘を中心に回すので、前腕は肘の方を向いたまま拳が弧を描く
const ELBOW := Vector3(0.0, 0.0, 0.35)
# 構え：手のひらを少し返して刃の平らな面をカメラへ向け、反りが見えるようにする。刃先は照準の左下に置き、照準をふさがない
const IDLE_ROT := Vector3(15.0, 20.0, 45.0)

# 3連の型。振りかぶり → 中間（ここを通る弧）→ 振り終わり → 行き過ぎ の順に通る。
# side：斬った向き（1で右から左、-1で左から右、0で正面）。ダミーを流す向きに使う
const PATTERNS := [
	{ # 1. 袈裟斬り：右上から左下へ
		"windup": [Vector3(14.0, -24.0, -62.0), Vector3(-0.03, 0.03, 0.05)],
		"mid": [Vector3(4.0, 6.0, -80.0), Vector3(-0.02, 0.0, -0.12)],
		"finish": [Vector3(-12.0, 40.0, -92.0), Vector3(-0.03, -0.02, -0.03)],
		"follow": [Vector3(-16.0, 47.0, -96.0), Vector3(-0.04, -0.03, -0.01)],
		"side": 1.0,
	},
	{ # 2. 逆袈裟：左下から右上へ
		"windup": [Vector3(-6.0, 30.0, 70.0), Vector3(-0.02, 0.0, 0.04)],
		"mid": [Vector3(4.0, 4.0, 84.0), Vector3(-0.01, 0.0, -0.06)],
		"finish": [Vector3(18.0, -30.0, 94.0), Vector3(0.03, 0.03, -0.03)],
		"follow": [Vector3(22.0, -36.0, 98.0), Vector3(0.04, 0.04, -0.01)],
		"side": -1.0,
	},
	{ # 3. 突き上げ：下から前へ突き出し、刃を引っ掛けて上へ抜く
		"windup": [Vector3(-38.0, 8.0, 8.0), Vector3(0.0, -0.07, 0.07)],
		"mid": [Vector3(0.0, 4.0, -6.0), Vector3(-0.02, -0.01, -0.1)],
		"finish": [Vector3(40.0, 0.0, -24.0), Vector3(0.0, 0.05, -0.05)],
		"follow": [Vector3(46.0, 0.0, -28.0), Vector3(0.0, 0.07, -0.03)],
		"side": 0.0,
	},
]
# アナログ斬りの振り：右から左への水平な振り。視線の軸まわりに傾けて、弾いた向きにする。
# 左から右へ斬るときは左右を反転した振り（_mirror_pattern）を使う
const SLASH_PATTERN := {
	"windup": [Vector3(5.0, -60.0, -80.0), Vector3(0.0, 0.0, 0.03)],
	"mid": [Vector3(2.0, 0.0, -82.0), Vector3(0.0, 0.0, -0.1)],
	"finish": [Vector3(-5.0, 60.0, -80.0), Vector3(0.0, 0.0, -0.02)],
	"follow": [Vector3(-8.0, 66.0, -82.0), Vector3(0.0, 0.0, 0.0)],
	"side": 1.0,
}
const SLASH_WINDUP := 0.03 # アナログ斬りはスティックを弾く動きが振りかぶりなので短い
const MOUSE_RETURN := 6.0 # マウスで動かした仮想スティックが中心へ戻る速さ (/秒)
const COMBO_RESET := 0.5 # 振り終わってからこれだけ空くと1の型に戻る (秒)
const FOLLOW_PART := 0.35 # 戻りのうち、行き過ぎに使う割合

# 構えの揺れ
const SWAY_LOOK := 2.0 # 視点の回転の速さ1ラジアン/秒あたりの遅れ (度)
const SWAY_MAX := 6.0
const SWAY_STIFFNESS := 120.0
const SWAY_DAMPING := 14.0
const BOB_FREQ := 1.5 # 1mあたりの手の揺れの位相（ラジアン）
const BOB_AMOUNT := Vector2(0.012, 0.008)
const LAND_KICK := 0.012 # 着地の速さ1m/sあたりの沈み込み (m/s)

# 斬撃の残光：Swing の前(-Z)に沿った帯を、振っている間だけ残す
const TRAIL_NEAR := 0.6
const TRAIL_FAR := 0.9
const TRAIL_LIFE := 0.08 # 秒
const TRAIL_COLOR := Color(0.55, 0.9, 1.0)

## Meshyのモデルを読み込んだとき、長さと向きを自動で合わせる。Gripの位置と向きは手で微調整する
@export var auto_fit := true
## 自動で合わせた結果、柄と刃先が逆になっていたらオンにする
@export var flip_model := false
## Meshyのモデルを合わせるときの、柄頭から刃先までの長さ (m)
@export var model_length := 1.12
## 握る位置から柄頭までの長さ (m)
@export var grip_back := 0.12
## 判定の箱の長さ (m)。見た目の刃より少し長くして当てやすくする
@export var hit_length := 1.4

var state := State.IDLE
var swing_count := 0
var inspect_count := 0
var using_model := false
var slash_count := 0
## 直前のアナログ斬り：dir（画面上の向き、上が+y）、strength（0〜1）、roll（振りの面の傾き、ラジアン）、at（msec）
var last_slash := {}

var _t := 0.0
var _buffer := 0.0
var combo := 0 # 今の振りの型（PATTERNS の番号）
var _since_swing := 99.0
var _pattern: Dictionary = PATTERNS[0] # 今の振り
var _analog := false # いまの振りがアナログ斬りか
var _slash_dir := Vector2.ZERO
var _slash_strength := 0.0
var _roll := 0.0 # 振りの面を視線の軸まわりに傾ける角度
var _roll_from := 0.0
var _roll_target := 0.0
var _flick := FlickDetector.new()
var _slash_buffer := 0.0
var _pending_slash := {}
var _mouse_stick := Vector2.ZERO
var _stick := Vector2.ZERO
var _from_rot := IDLE_ROT
var _from_pos := Vector3.ZERO
var _rot := IDLE_ROT # 今の姿勢
var _pos := Vector3.ZERO
var _bend := Vector3.ZERO # 手首の曲げ（度）。x=内へ、y=上へ
var _settle_rot := Vector3.ZERO # 構えに戻るときの、ばねで揺れる残り
var _settle_rot_vel := Vector3.ZERO
var _settle_pos := Vector3.ZERO
var _settle_pos_vel := Vector3.ZERO
var _sway := Vector2.ZERO # 視点の回転に遅れる量（度）
var _sway_vel := Vector2.ZERO
var _last_cam_basis := Basis.IDENTITY
var _bob_phase := 0.0
var _land := 0.0
var _land_vel := 0.0
var _was_on_floor := true
var _last_fall_speed := 0.0
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_points: Array = [] # [根元, 先, 経過秒]
var _hit_ids := {}
var _retract := 0.0
var _squash := 0.0
var _squash_vel := 0.0
var _base_position: Vector3
var _player: Player
var _grip_rest: Transform3D
var _spin_pivot := Vector3.ZERO # ナイフを回す軸（輪の中心）。Gripの座標
var _spin_axis := Vector3.RIGHT # ナイフを回す軸の向き（輪の穴の向き＝刃の面の法線）。Gripの座標
var _blade_dir := Vector3.UP # 刃先が曲がっていく向き。Gripの座標
var _wrist := Vector3.ZERO # 手首の位置と前腕の向き（ひねりの軸）。Swingの座標
var _forearm := Vector3.FORWARD
var _spin := 0.0 # ナイフの回転（ラジアン）
var _spin_time := PackedFloat32Array() # 回転角を SPIN_STEPS 等分したときの、そこまでの時間（0〜1）
var _open := 0.0 # 指の開き。0で握る、1でナイフ回しの形
var _skeleton: Skeleton3D

@onready var swing: Node3D = $Swing
@onready var grip: Node3D = $Swing/Grip


func _ready() -> void:
	_base_position = position
	_player = _find_player()
	_grip_rest = grip.transform
	_spin_pivot = Vector3(0.0, 0.0, grip_back - 0.02)
	if ResourceLoader.exists(MODEL_PATH):
		_use_model(load(MODEL_PATH))
		_add_glow(grip, WEAPON_GLOW, 4.0)
	_add_glow($Swing/HandModel, HAND_GLOW, 2.5)
	for mi in swing.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1 | VIEW_LAYER
	var skels := find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skeleton = skels[0]
	_fit_to_hand()
	_make_trail()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and slash_mode_active():
		# マウスは仮想スティックとして扱う。素早く動かすと端まで届いて弾きになる
		_mouse_stick = (_mouse_stick + event.relative / maxf(Tuning.slash_mouse_px, 1.0)).limit_length(1.0)


func _physics_process(delta: float) -> void:
	if _player and _player.input_enabled and Input.is_action_just_pressed("attack"):
		_buffer = Tuning.attack_buffer
	else:
		_buffer -= delta
	_read_flick(delta)
	var can_start := state == State.IDLE or state == State.RECOVERY or state == State.INSPECT
	if _slash_buffer > 0.0 and can_start:
		_slash_buffer = 0.0
		_buffer = 0.0
		_start_slash(_pending_slash.dir, _pending_slash.strength)
	elif _buffer > 0.0 and can_start:
		_buffer = 0.0
		_start_swing() # ナイフ回しの途中でも攻撃を優先する
	elif state == State.IDLE and _player and _player.input_enabled and Input.is_action_just_pressed("inspect"):
		_start_inspect()
	if not is_attacking():
		_since_swing += delta # 振り終わってからの時間
	_advance(delta)
	if state == State.ACTIVE:
		_check_hits()
	_update_settle(delta)
	_update_sway(delta)
	_update_squash(delta)
	_update_retract(delta)
	_apply_pose()
	_apply_hand()
	_update_trail(delta)


func is_attacking() -> bool:
	return state == State.WINDUP or state == State.ACTIVE or state == State.RECOVERY


func is_inspecting() -> bool:
	return state == State.INSPECT


func is_slashing() -> bool:
	return _analog and is_attacking()


func slash_mode_active() -> bool:
	return _player != null and _player.slash_mode()


## 斬撃モード中のスティック（マウスの仮想スティックを足したもの）。右が+x、下が+y。HUD用
func slash_stick() -> Vector2:
	return _stick


## 斬撃モードの間、スティックの弾きを見つけてアナログ斬りを出す（振っている途中なら先行入力にする）。
func _read_flick(delta: float) -> void:
	_mouse_stick = _mouse_stick.move_toward(Vector2.ZERO, MOUSE_RETURN * delta)
	_slash_buffer -= delta
	if not slash_mode_active():
		_flick.reset()
		_mouse_stick = Vector2.ZERO
		_stick = Vector2.ZERO
		return
	var v := Input.get_vector("look_left", "look_right", "look_up", "look_down", Tuning.stick_deadzone)
	_stick = (v + _mouse_stick).limit_length(1.0)
	var f := _flick.feed(_stick, delta, Tuning.slash_window)
	if f.is_empty():
		return
	var strength := clampf(f.speed / maxf(Tuning.slash_full_speed, 0.01), 0.0, 1.0)
	_pending_slash = {"dir": f.dir, "strength": strength}
	_slash_buffer = Tuning.attack_buffer


## 握った状態のナイフ（Grip）の姿勢と、ナイフ回しの軸。どちらも Swing の座標。
func grip_rest() -> Transform3D:
	return _grip_rest


func spin_axis() -> Vector3:
	return (_grip_rest.basis * _spin_axis).normalized()


## 判定の箱のワールド座標での姿勢。握る位置から Swing の前(-Z)へ伸ばす。
func hitbox_transform() -> Transform3D:
	var g := swing.global_transform.orthonormalized()
	return Transform3D(g.basis, g * Vector3(0.0, 0.0, -hit_length * 0.5))


## ナイフ回し：輪に通した人差し指を軸に、ナイフを2回転させて握り直す。
func _start_inspect() -> void:
	inspect_count += 1
	_spin_time.clear() # 回し始めの手の向きで作り直す
	_capture_from()
	_t = 0.0
	state = State.INSPECT


## アナログ斬り：dirは画面上で刃を動かす向き（上が+y）、strengthは弾きの強さ（0〜1）。
## 水平な振り（右から左）を、視線の軸まわりに傾けて dir の向きにする。手首が裏返らないよう、
## 右へ斬るときは左から右の振りを使い、傾きは±90度に収める。
func _start_slash(dir: Vector2, strength: float) -> void:
	slash_count += 1
	var right_to_left := dir.x <= 0.0
	_begin_swing(SLASH_PATTERN if right_to_left else _mirror_pattern(SLASH_PATTERN))
	_analog = true
	_slash_dir = dir
	_slash_strength = strength
	# 右から左の振り(-1, 0)を角度rollだけ反時計回りに回すと(-cos, -sin)、左から右なら(cos, sin)
	_roll_target = atan2(-dir.y, -dir.x) if right_to_left else atan2(dir.y, dir.x)
	last_slash = {"dir": dir, "strength": strength, "roll": _roll_target, "at": Time.get_ticks_msec()}


func _start_swing() -> void:
	swing_count += 1
	combo = (combo + 1) % PATTERNS.size() if _since_swing < COMBO_RESET and swing_count > 1 else 0
	_begin_swing(PATTERNS[combo])


func _begin_swing(pattern: Dictionary) -> void:
	_pattern = pattern
	_since_swing = 0.0
	_analog = false
	_roll_from = _roll
	_roll_target = 0.0
	_hit_ids.clear()
	_capture_from()
	_trail_points.clear()
	_t = 0.0
	_spin = 0.0 # 回している途中なら握り直してから振る
	_bend = Vector3.ZERO
	_open = 0.0
	state = State.WINDUP


func _advance(delta: float) -> void:
	if state == State.IDLE:
		_rot = IDLE_ROT
		_pos = Vector3.ZERO
		_roll = 0.0
		return
	_t += delta
	var p := _pattern
	var windup_time := SLASH_WINDUP if _analog else Tuning.attack_windup
	var active_time := _active_time()
	match state:
		State.WINDUP:
			var x := _ease_out(_ratio(windup_time))
			_set_pose(_from_rot.lerp(p.windup[0], x), _from_pos.lerp(p.windup[1], x))
			_roll = lerp_angle(_roll_from, _roll_target, x)
			if _t >= windup_time:
				_next(State.ACTIVE)
				HitFeel.play_swing()
		State.ACTIVE:
			# 判定の間は、中間を通る弧に沿って振り抜く。入りで加速し、終わりで少し緩める
			var x := _snap(_ratio(active_time))
			_set_pose(_arc(p.windup[0], p.mid[0], p.finish[0], x), _arc(p.windup[1], p.mid[1], p.finish[1], x))
			_roll = _roll_target
			if _t >= active_time:
				_next(State.RECOVERY)
		State.RECOVERY:
			# 行き過ぎてから構えに戻る。最後はばねで落ち着かせる（_update_settle）
			var x := _ratio(Tuning.attack_recovery)
			if x < FOLLOW_PART:
				var k := _ease_out(x / FOLLOW_PART)
				_set_pose(Vector3(p.finish[0]).lerp(p.follow[0], k), Vector3(p.finish[1]).lerp(p.follow[1], k))
			else:
				var k := smoothstep(0.0, 1.0, (x - FOLLOW_PART) / (1.0 - FOLLOW_PART))
				_set_pose(Vector3(p.follow[0]).lerp(IDLE_ROT, k), Vector3(p.follow[1]).lerp(Vector3.ZERO, k))
			_roll = lerp_angle(_roll_target, 0.0, smoothstep(0.0, 1.0, x))
			if x >= 1.0:
				_analog = false
				_next(State.IDLE)
				_kick_settle(p)
		State.INSPECT:
			var x := _ratio(INSPECT_TIME)
			_open = smoothstep(OPEN_FROM, OPEN_FROM + 0.05, x) * (1.0 - smoothstep(OPEN_TO - 0.04, OPEN_TO, x))
			_spin = _spin_angle(clampf((x - SPIN_FROM) / (SPIN_TO - SPIN_FROM), 0.0, 1.0)) if x > SPIN_FROM else 0.0
			var keys: Array = [[0.0, _from_rot, _from_pos, Vector3.ZERO]] + INSPECT_KEYS
			_set_pose(_track(keys, 1, x), _track(keys, 2, x))
			_bend = _track(keys, 3, x)
			if x >= 1.0:
				_spin = 0.0
				_open = 0.0
				_bend = Vector3.ZERO
				_next(State.IDLE)


## 回す速さの表を作る。回転角θでの速さωを、はじいた勢い・刃先の高さ・摩擦・受け止めから決め、
## dθ/ω を足し合わせて「θまで回るのにかかる時間」を求める。
func _build_spin_table() -> void:
	var total := TAU * SPIN_TURNS
	# 上向きをGripの座標に直す。刃（Gripの-Z）は輪の軸 _spin_axis まわりに回る
	var up: Vector3 = ((grip.get_parent() as Node3D).global_basis.orthonormalized() * _grip_rest.basis.orthonormalized()).inverse() * Vector3.UP
	var blade := Vector3.FORWARD
	var h0 := up.dot(blade)
	_spin_time.resize(SPIN_STEPS + 1)
	_spin_time[0] = 0.0
	var dth := total / SPIN_STEPS
	var acc := 0.0
	for i in SPIN_STEPS:
		var th := (i + 0.5) * dth
		var h := up.dot(blade.rotated(_spin_axis, th))
		var w := sqrt(maxf(1.0 - SPIN_GRAVITY * (h - h0) - SPIN_FRICTION * th, 0.06))
		w *= lerpf(0.35, 1.0, smoothstep(0.0, SPIN_FLICK, th)) # はじく
		w *= lerpf(0.15, 1.0, smoothstep(0.0, SPIN_CATCH, total - th)) # 受け止める
		acc += dth / w
		_spin_time[i + 1] = acc
	for i in SPIN_STEPS + 1:
		_spin_time[i] /= acc


## 回し始めてからの時間の割合 p（0〜1）での回転角。
func _spin_angle(p: float) -> float:
	if _spin_time.is_empty():
		_build_spin_table()
	var i := clampi(_spin_time.bsearch(p) - 1, 0, SPIN_STEPS - 1)
	var span := _spin_time[i + 1] - _spin_time[i]
	var f := 0.0 if span <= 0.0 else clampf((p - _spin_time[i]) / span, 0.0, 1.0)
	return (i + f) * TAU * SPIN_TURNS / SPIN_STEPS


## 判定の時間。アナログ斬りは強く弾くほど速く振り抜く。
func _active_time() -> float:
	if not _analog:
		return Tuning.attack_active
	return lerpf(Tuning.slash_active_slow, Tuning.slash_active_fast, _slash_strength)


## 振りを左右反転する（刃先の左右とひねり、拳の左右のずれを逆にする）。
func _mirror_pattern(p: Dictionary) -> Dictionary:
	var m := {"side": -float(p.side)}
	for key in ["windup", "mid", "finish", "follow"]:
		var r: Vector3 = p[key][0]
		var q: Vector3 = p[key][1]
		m[key] = [Vector3(r.x, -r.y, -r.z), Vector3(-q.x, q.y, q.z)]
	return m


## キー列の field 番目（1：rot、2：pos）を時刻 x でなめらかにつなぐ（Catmull-Rom）。
func _track(keys: Array, field: int, x: float) -> Vector3:
	var i := 0
	while i < keys.size() - 2 and x > keys[i + 1][0]:
		i += 1
	var t0: float = keys[i][0]
	var t1: float = keys[i + 1][0]
	var u := clampf((x - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
	var p1: Vector3 = keys[i][field]
	var p2: Vector3 = keys[i + 1][field]
	var p0: Vector3 = keys[i - 1][field] if i > 0 else p1
	var p3: Vector3 = keys[i + 2][field] if i + 2 < keys.size() else p2
	var u2 := u * u
	return 0.5 * (2.0 * p1 + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u2 * u)


func _set_pose(rot: Vector3, pos: Vector3) -> void:
	_rot = rot
	_pos = pos


## 今見えている姿勢（ばねの残りも含む）から次の動きを始める。
func _capture_from() -> void:
	_from_rot = _rot + _settle_rot
	_from_pos = _pos + _settle_pos
	_settle_rot = Vector3.ZERO
	_settle_rot_vel = Vector3.ZERO
	_settle_pos = Vector3.ZERO
	_settle_pos_vel = Vector3.ZERO


## 構えに戻った瞬間、振った向きの勢いを少し残して揺らす。
func _kick_settle(p: Dictionary) -> void:
	var dir: Vector3 = Vector3(p.follow[0]) - IDLE_ROT
	_settle_rot_vel = dir.normalized() * -60.0
	_settle_pos_vel = Vector3(p.follow[1]).normalized() * -0.15


func _update_settle(delta: float) -> void:
	const K := 220.0
	const D := 16.0
	_settle_rot_vel += (-K * _settle_rot - D * _settle_rot_vel) * delta
	_settle_rot += _settle_rot_vel * delta
	_settle_pos_vel += (-K * _settle_pos - D * _settle_pos_vel) * delta
	_settle_pos += _settle_pos_vel * delta


## 視点を回すと手が遅れてついてくる。走ると8の字に揺れ、着地で沈む。
func _update_sway(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or delta <= 0.0:
		return
	var b := cam.global_transform.basis.orthonormalized()
	var rel := _last_cam_basis.inverse() * b
	_last_cam_basis = b
	var e := rel.get_euler()
	var target := Vector2(
		clampf(-e.y / delta * SWAY_LOOK, -SWAY_MAX, SWAY_MAX),
		clampf(-e.x / delta * SWAY_LOOK, -SWAY_MAX, SWAY_MAX))
	if absf(e.y) > 0.5 or absf(e.x) > 0.5:
		target = Vector2.ZERO # 生まれ直しなどで大きく飛んだときは揺らさない
	_sway_vel += (SWAY_STIFFNESS * (target - _sway) - SWAY_DAMPING * _sway_vel) * delta
	_sway += _sway_vel * delta
	if _player == null:
		return
	var on_floor := _player.is_on_floor()
	var speed := _player.horizontal_speed()
	if on_floor:
		_bob_phase += speed * BOB_FREQ * delta
	if on_floor and not _was_on_floor:
		_land_vel -= clampf(_last_fall_speed, 0.0, 20.0) * LAND_KICK * 20.0
	_was_on_floor = on_floor
	_last_fall_speed = -_player.velocity.y
	_land_vel += (-260.0 * _land - 18.0 * _land_vel) * delta
	_land += _land_vel * delta


func _bob() -> Vector3:
	if _player == null or not _player.is_on_floor():
		return Vector3.ZERO
	var k := clampf(_player.horizontal_speed() / maxf(Tuning.max_speed, 0.01), 0.0, 1.0)
	return Vector3(sin(_bob_phase) * BOB_AMOUNT.x, -absf(cos(_bob_phase)) * BOB_AMOUNT.y, 0.0) * k


func _next(s: State) -> void:
	state = s
	_t = 0.0


func _ratio(duration: float) -> float:
	return 1.0 if duration <= 0.0 else clampf(_t / duration, 0.0, 1.0)


func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)


## 入りで加速して振り抜き、終わりで少し緩める。
func _snap(x: float) -> float:
	return x * x * (3.0 - 2.0 * x) * 0.6 + x * x * 0.4


## a から c へ、t=0.5 で b を通る2次曲線。
func _arc(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	var ctrl := b * 2.0 - (a + c) * 0.5
	var u := 1.0 - t
	return a * u * u + ctrl * 2.0 * u * t + c * t * t


func _check_hits() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(HIT_THICKNESS, HIT_THICKNESS, hit_length)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = hitbox_transform()
	query.collision_mask = HURTBOX_LAYER
	if _player:
		query.exclude = [_player.get_rid()]
	for result in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var target: Object = result.collider
		if target == null or not target.has_method("take_hit"):
			continue
		var id := target.get_instance_id()
		if _hit_ids.has(id):
			continue # 1振りで同じ相手には1回だけ当てる
		_hit_ids[id] = true
		_hit(target, query.transform.origin)


func _hit(target: Object, blade_mid: Vector3) -> void:
	var at: Vector3 = target.get("global_position")
	var speed := _player.horizontal_speed() if _player else 0.0
	var power := HitFeel.power_for(speed)
	# 斬った向き：前へ押し出しつつ、振り抜いた側へ流す
	var cam := get_viewport().get_camera_3d().global_transform.basis
	var forward := Vector3(-cam.z.x, 0.0, -cam.z.z).normalized()
	var side := Vector3(cam.x.x, 0.0, cam.x.z).normalized() * -float(_pattern.side)
	var dir := forward + side * 0.5
	if _analog:
		# 威力 = 基本威力 × (1 + 速度 / 最高速度)。アナログ斬りは弾きの強さで基本威力が変わる
		power *= lerpf(Tuning.slash_power_min, Tuning.slash_power_max, _slash_strength)
		# 弾いた向きへ流す。上下の成分はダミーの潰れ方に使う
		dir = forward + (cam.x * _slash_dir.x + cam.y * _slash_dir.y) * 0.7
	target.call("take_hit", dir, power, Vector3(at.x, blade_mid.y, at.z))
	_squash_vel -= Tuning.weapon_squash * power * sqrt(SQUASH_STIFFNESS)
	HitFeel.on_hit(power, _player)


func _update_squash(delta: float) -> void:
	_squash_vel += (-SQUASH_STIFFNESS * _squash - SQUASH_DAMPING * _squash_vel) * delta
	_squash = clampf(_squash + _squash_vel * delta, -0.5, 0.5)


## 目の前に壁があれば、近さに応じて武器を手前へ引っ込める。
func _update_retract(delta: float) -> void:
	var target := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		var from := cam.global_position
		var query := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * RETRACT_REACH, 1)
		if _player:
			query.exclude = [_player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			target = clampf(RETRACT_REACH - from.distance_to(hit.position), 0.0, RETRACT_MAX)
	_retract = lerpf(_retract, target, minf(1.0, 20.0 * delta))


func retract_amount() -> float:
	return _retract


func _apply_pose() -> void:
	var r := _rot + _settle_rot + Vector3(_sway.y, _sway.x, -_sway.x * 0.6)
	# 引っ込めるときは刃先を上へ逃がす
	var pitch := deg_to_rad(r.x) + _retract / RETRACT_MAX * deg_to_rad(40.0)
	# x・y は肘を中心に、z（ひねり）は前腕の軸まわりに手首を中心に回す
	var b := Basis.from_euler(Vector3(pitch, deg_to_rad(r.y), 0.0))
	var arm := Transform3D(b, ELBOW - b * ELBOW + _pos + _settle_pos)
	var tw := Basis(_forearm, deg_to_rad(r.z))
	var twist := Transform3D(tw, _wrist - tw * _wrist)
	# 体積を保ったまま刃の向き(Z)に伸び縮みさせる
	var sz := 1.0 + _squash
	var sxy := 1.0 / sqrt(sz)
	# 手首の曲げ：前腕に垂直な2軸まわりに、手首を中心に回す
	var side := _forearm.cross(Vector3.UP).normalized()
	var up := side.cross(_forearm).normalized()
	var bb := Basis(up, deg_to_rad(_bend.x)) * Basis(side, deg_to_rad(_bend.y))
	var bend := Transform3D(bb, _wrist - bb * _wrist)
	# アナログ斬りは振りの面ごと視線の軸(Z)まわりに傾ける。軸は肘を通るので肘の位置は変わらない
	var roll := Transform3D(Basis(Vector3.BACK, _roll), Vector3.ZERO)
	swing.transform = roll * arm * twist * bend * Transform3D(Basis.from_scale(Vector3(sxy, sxy, sz)), Vector3.ZERO)
	position = _base_position + Vector3(0.0, -_retract * 0.2 + _land, _retract) + _bob()


## 指の曲げとナイフの回転を反映する。
func _apply_hand() -> void:
	var spin := Transform3D(Basis(_spin_axis, _spin), Vector3.ZERO)
	grip.transform = _grip_rest * Transform3D(Basis.IDENTITY, _spin_pivot) * spin * Transform3D(Basis.IDENTITY, -_spin_pivot)
	_pose_fingers()


func _pose_fingers() -> void:
	if _skeleton == null:
		return
	for finger in CURL_GRIP:
		var closed: Array = CURL_GRIP[finger] if finger != "thumb" else [thumb_grip.x, thumb_grip.y, thumb_grip.z]
		var opened: Array = CURL_SPIN[finger]
		for k in 3:
			var idx := _skeleton.find_bone("%s_%d" % [finger, k + 1])
			if idx < 0:
				continue
			var angle := deg_to_rad(lerpf(closed[k], opened[k], _open))
			var rest := _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
			var q := Quaternion(Vector3.RIGHT, angle)
			if finger == "thumb" and k == 0:
				q = Quaternion(Vector3.BACK, deg_to_rad(lerpf(thumb_across, thumb_across_spin, _open))) * q
				q = Quaternion(Vector3.UP, deg_to_rad(thumb_twist)) * q
			_skeleton.set_bone_pose_rotation(idx, rest * q)


## 色テクスチャから抜き出した水色・マゼンタの線（*_emission.png）を光らせる。
func _add_glow(root: Node, tex: Texture2D, energy: float) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		for i in mesh_i.mesh.get_surface_count():
			var mat := mesh_i.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			mat = mat.duplicate()
			mat.emission_enabled = true
			mat.emission = Color.BLACK # 既定（足し算）では「発光色＋テクスチャ」なので、テクスチャだけで光らせる
			mat.emission_texture = tex
			mat.emission_energy_multiplier = energy
			mesh_i.set_surface_override_material(i, mat)


func _make_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	_trail.mesh = _trail_mesh
	_trail.top_level = true # 頂点をワールド座標で置く
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(TRAIL_COLOR.r * 1.6, TRAIL_COLOR.g * 1.6, TRAIL_COLOR.b * 1.6)
	m.no_depth_test = false
	_trail.material_override = m
	add_child(_trail)


## 振っている間は刃の通り道を記録し、古いものから消えていく帯として描く。
func _update_trail(delta: float) -> void:
	if _trail == null:
		return
	_trail.global_transform = Transform3D.IDENTITY
	for p in _trail_points:
		p[2] += delta
	while not _trail_points.is_empty() and _trail_points[0][2] > TRAIL_LIFE:
		_trail_points.pop_front()
	if state == State.ACTIVE or (state == State.RECOVERY and _t < Tuning.attack_recovery * FOLLOW_PART * 0.5):
		var g := swing.global_transform
		_trail_points.append([g * Vector3(0, 0, -TRAIL_NEAR), g * Vector3(0, 0, -TRAIL_FAR), 0.0])
	_trail_mesh.clear_surfaces()
	var n := _trail_points.size()
	if n < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var p: Array = _trail_points[i]
		var life: float = 1.0 - p[2] / TRAIL_LIFE
		var head := float(i) / float(n - 1) # 新しい側ほど明るい
		var a := clampf(life * (0.25 + 0.75 * head), 0.0, 1.0)
		_trail_mesh.surface_set_color(Color(1, 1, 1, 0.0))
		_trail_mesh.surface_add_vertex(p[0])
		_trail_mesh.surface_set_color(Color(1, 1, 1, a * 0.6))
		_trail_mesh.surface_add_vertex(p[1])
	_trail_mesh.surface_end()


func _find_player() -> Player:
	var n := get_parent()
	while n and not (n is Player):
		n = n.get_parent()
	return n as Player


## Meshyで作ったGLBを箱の剣と差し替える。
func _use_model(scene: PackedScene) -> void:
	if scene == null:
		return
	var model := scene.instantiate() as Node3D
	if model == null:
		return
	grip.add_child(model)
	$Swing/Grip/BoxSword.queue_free()
	using_model = true
	if auto_fit:
		_fit(model)


## 一番長い辺を刃の向き(-Z)にそろえ、柄頭から刃先までをmodel_lengthにする。
## 元のモデルで長い辺の小さい側を柄とみなす（立てて作った剣なら下が柄）。
func _fit(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var rel: Transform3D = grip.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		var b: AABB = rel * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or box.get_longest_axis_size() <= 0.0:
		return
	var rot: Basis
	match box.get_longest_axis_index():
		Vector3.AXIS_X:
			rot = Basis(Vector3.UP, PI / 2) # +X → -Z
		Vector3.AXIS_Y:
			rot = Basis(Vector3.RIGHT, -PI / 2) # +Y → -Z
		_:
			rot = Basis(Vector3.UP, PI) # +Z → -Z
	if flip_model:
		rot = Basis(Vector3.UP, PI) * rot
	var s := model_length / box.get_longest_axis_size()
	var b := rot.scaled(Vector3.ONE * s)
	var moved := Transform3D(b, Vector3.ZERO) * box
	var center := moved.get_center()
	var offset := Vector3(-center.x, -center.y, grip_back - moved.end.z)
	model.transform = Transform3D(b, offset) * model.transform
	_spin_pivot = ring_center if ring_center != Vector3.ZERO else _find_ring_center(model)
	_blade_dir = _find_blade_dir(model)
	_spin_axis = _blade_dir.cross(Vector3.BACK).normalized()


## 刃先の側（全長の後ろ半分）の頂点が、柄の軸からどちらへ寄っているか。カランビットの刃が曲がる向き。
func _find_blade_dir(model: Node3D) -> Vector3:
	var sum := Vector2.ZERO
	var to_z := grip_back - model_length * 0.6
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		var rel: Transform3D = grip.global_transform.affine_inverse() * mesh_i.global_transform
		for si in mesh_i.mesh.get_surface_count():
			for v in mesh_i.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = rel * v
				if p.z < to_z:
					sum += Vector2(p.x - _spin_pivot.x, p.y - _spin_pivot.y)
	return Vector3.UP if sum.length() < 0.0001 else Vector3(sum.x, sum.y, 0.0).normalized()


## 握った指の形から、ナイフを持たせる位置と向きを決める（カランビットの標準の握り＝逆手）。
## - 人差し指の基節（index_1〜index_2）の上に輪の中心を置く（ring_along）。輪の穴の軸は人差し指の向きにそろえる
## - 柄は、中指〜小指が曲がってできる「筒」の中心をなるべく通る向きにする。人差し指の付け根から
##   小指側の手のひらの付け根へ斜めに渡る（握り込みの対角線）
## - 刃は小指の側から出て、内側の弧を拳の前(-Z)へ向ける
func _fit_to_hand() -> void:
	if _skeleton == null or not using_model:
		return
	_open = 0.0
	_pose_fingers()
	var to_swing := swing.global_transform.affine_inverse() * _skeleton.global_transform
	var hand := to_swing * _skeleton.get_bone_global_pose(_skeleton.find_bone("hand"))
	_wrist = hand.origin
	_forearm = hand.basis.y.normalized()
	var a := _joint(to_swing, "index_1")
	var b := _joint(to_swing, "index_2")
	var ring := a.lerp(b, ring_along)
	var down := Vector3.ZERO # 輪から刃の出る側へ
	for f in ["middle", "ring", "pinky"]:
		down += _finger_hollow(to_swing, f) - ring
	if down.length() < 0.001:
		return
	down = down.normalized()
	var z := -down # Gripの+Z（柄頭の側）
	var d := (a - b).normalized() # 輪の穴の軸。人差し指の向きを、柄と直交するように少し倒す
	var x := (d - z * d.dot(z)).normalized()
	var y := z.cross(x) # 刃の曲がる向き
	if y.dot(Vector3.FORWARD) < 0.0:
		x = -x
		y = -y
	# モデルの軸（輪の穴の向き・刃の曲がる向き・柄の向き Z）を、手の軸に合わせる
	var src := Basis(_spin_axis, _blade_dir, Vector3.BACK)
	var dst := Basis(x, y, z)
	var rot := dst * src.inverse()
	_grip_rest = Transform3D(rot, ring - rot * _spin_pivot)
	grip.transform = _grip_rest


func _joint(to_swing: Transform3D, bone: String) -> Vector3:
	return to_swing * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)).origin


## 曲げた指（付け根・中・先の節と指先）が囲む多角形の重心。柄はここを通るとよい
func _finger_hollow(to_swing: Transform3D, finger: String) -> Vector3:
	var p: Array[Vector3] = [_joint(to_swing, finger + "_1"), _joint(to_swing, finger + "_2"), _joint(to_swing, finger + "_3")]
	p.append(p[2] + (p[2] - p[1]) * 0.9) # 指先
	var sum := Vector3.ZERO
	var area := 0.0
	for i in [1, 2]:
		var t := (p[i] - p[0]).cross(p[i + 1] - p[0]).length() * 0.5
		sum += (p[0] + p[i] + p[i + 1]) / 3.0 * t
		area += t
	return sum / area if area > 0.0 else (p[0] + p[1] + p[2] + p[3]) * 0.25


## 柄頭の側（Gripの+Z端）にある輪の中心。柄頭から全長の1割の範囲の頂点の中心をとる。
func _find_ring_center(model: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	var from_z := grip_back - model_length * 0.1
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		var rel: Transform3D = grip.global_transform.affine_inverse() * mesh_i.global_transform
		for si in mesh_i.mesh.get_surface_count():
			for v in mesh_i.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = rel * v
				if p.z < from_z:
					continue
				box = AABB(p, Vector3.ZERO) if first else box.expand(p)
				first = false
	return Vector3(0.0, 0.0, grip_back - 0.02) if first else box.get_center()
