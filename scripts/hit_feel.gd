extends Node
## 当たった瞬間の誇張をまとめて出す（自動読み込みの `HitFeel`）。
## 威力の計算、ヒットストップ、振動、効果音。画面揺れはプレイヤーのカメラが持つ。

const SAMPLE_RATE := 22050

## 直近のヒットの威力（調整パネルの表示用）
var last_power := 0.0

var _stop_token := 0
var _hit_player: AudioStreamPlayer
var _swing_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hit_player = _make_player(_synth_hit())
	_swing_player = _make_player(_synth_swing())


## 仕様の式：威力 = 基本威力 × (1 + 現在の速度 / 最高速度)。速度の比は0〜1に収める。
## 基本威力は1なので、止まっていれば1、最高速度なら2。
func power_for(speed: float) -> float:
	return 1.0 + clampf(speed / maxf(Tuning.max_speed, 0.01), 0.0, 1.0)


## 威力を0〜1に直したもの。演出の割り振りに使う。
func strength_of(power: float) -> float:
	return clampf(power - 1.0, 0.0, 1.0)


## 当たった瞬間の演出をまとめて出す。画面揺れはplayerに頼む。
func on_hit(power: float, player: Node) -> void:
	last_power = power
	var k := strength_of(power)
	hitstop(lerpf(Tuning.hitstop_min, Tuning.hitstop_max, k))
	rumble(power)
	if player and player.has_method("add_trauma"):
		player.add_trauma(Tuning.shake_trauma * power * 0.5)
	_play(_hit_player, linear_to_db(lerpf(0.6, 1.0, k)))


func play_swing() -> void:
	_play(_swing_player, -8.0)


## 世界全体を止める。止めている間は物理も止まるので、現実の時間で戻す。
func hitstop(duration: float) -> void:
	if duration <= 0.0:
		return
	_stop_token += 1
	var token := _stop_token
	Engine.time_scale = 0.0
	await get_tree().create_timer(duration, true, false, true).timeout
	# 止めている間に次のヒットが来たら、そちらの終わりまで待つ
	if token == _stop_token:
		Engine.time_scale = 1.0


func is_stopped() -> bool:
	return Engine.time_scale == 0.0


## 振動は短く、威力に比例させる。弱いヒットは弱モーターだけ、強いほど強モーターが加わる。
func rumble(power: float) -> void:
	var s := Tuning.rumble_strength
	if s <= 0.0:
		return
	var weak := clampf(s * power * 0.5, 0.0, 1.0)
	var strong := clampf(s * strength_of(power), 0.0, 1.0)
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, weak, strong, Tuning.rumble_duration)


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.max_polyphony = 4
	add_child(p)
	return p


## 同じ音の繰り返しに聞こえないよう、毎回ピッチを少しずらす。
func _play(p: AudioStreamPlayer, volume_db: float) -> void:
	var spread := Tuning.sfx_pitch_spread
	p.pitch_scale = 1.0 + randf_range(-spread, spread)
	p.volume_db = volume_db
	p.play()


## 打撃音：低いドンと、短いノイズのザッを重ねる。音素材を持たずに済むよう、その場で作る。
func _synth_hit() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.18)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		phase += TAU * lerpf(140.0, 55.0, minf(t / 0.12, 1.0)) / SAMPLE_RATE
		var thump := sin(phase) * exp(-t * 22.0)
		var crack := randf_range(-1.0, 1.0) * exp(-t * 60.0)
		samples[i] = thump * 0.8 + crack * 0.5
	return _to_wav(samples)


## 風切り音：ノイズを山なりの音量でなぞる。
func _synth_swing() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.14)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var smooth := 0.0
	for i in n:
		var x := float(i) / n
		smooth = lerpf(smooth, randf_range(-1.0, 1.0), 0.25) # ざっくり高域を落とす
		samples[i] = smooth * sin(PI * x) * 0.6
	return _to_wav(samples)


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
