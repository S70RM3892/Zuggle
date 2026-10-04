extends Node
## パルクールの手応え（自動読み込みの `ParkourFeel`）。手のアクションと着地の効果音と振動。
## 何をしたかを手の見た目に加えて音と振動でも返す（仕様の柱2「手は意思」）。
## 音は起動時にその場で作る。音量（sfx_volume）と振動（rumble_strength）は調整パネルで0にできる。

## テスト用。最後に出した手応えの名前と、出した回数
var last_event := ""
var count := 0

# 名前 → {player, db, pitch, weak, strong, time}
var _events := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 3892 # 毎回同じ音にする
	# 名前, 音, 音量(dB), ピッチ, 弱モーター, 強モーター, 振動の長さ(秒)
	_add("grab", _synth_grab(), -3.0, 1.0, 0.25, 0.35, 0.08) # 縁・ポールを掴む
	_add("plant", _synth_plant(), -5.0, 1.0, 0.3, 0.1, 0.06) # ボールト・壁押しで手をつく
	_add("land", _synth_land(), -6.0, 1.0, 0.25, 0.0, 0.05) # ふつうの着地
	_add("hard_land", _synth_land(), 0.0, 0.75, 0.7, 1.0, 0.2) # 強い着地：同じ音を低く大きく
	_add("roll", _synth_roll(), -3.0, 1.0, 0.35, 0.15, 0.25) # 受け身
	_add("slide", _synth_slide(), -7.0, 1.0, 0.15, 0.0, 0.12) # スライディング
	_add("whiff", _synth_whiff(), -14.0, 1.0, 0.0, 0.0, 0.0) # 空振り


## 手応えを出す。strength（0〜1）で音量と振動を弱める。
func play(event: String, strength := 1.0) -> void:
	if not _events.has(event):
		push_warning("ParkourFeel: 知らない手応え %s" % event)
		return
	var e: Dictionary = _events[event]
	strength = clampf(strength, 0.0, 1.0)
	last_event = event
	count += 1
	var volume := Tuning.sfx_volume * strength
	if volume > 0.001:
		var p: AudioStreamPlayer = e.player
		var spread := Tuning.sfx_pitch_spread
		p.pitch_scale = e.pitch * (1.0 + _rng.randf_range(-spread, spread)) # 同じ音の繰り返しに聞こえないように
		p.volume_db = e.db + linear_to_db(volume)
		p.play()
	_rumble(e.weak * strength, e.strong * strength, e.time)


## 弱モーターは軽い手応え、強モーターは重い衝撃。どちらも短く。
func _rumble(weak: float, strong: float, duration: float) -> void:
	var s := Tuning.rumble_strength
	if s <= 0.0 or duration <= 0.0 or (weak <= 0.0 and strong <= 0.0):
		return
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, clampf(weak * s, 0.0, 1.0), clampf(strong * s, 0.0, 1.0), duration)


func _add(event: String, wav: AudioStreamWAV, db: float, pitch: float, weak: float, strong: float, time: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = wav
	p.max_polyphony = 3
	add_child(p)
	_events[event] = {"player": p, "db": db, "pitch": pitch, "weak": weak, "strong": strong, "time": time}


## 低い音の打撃：位相 phase のサイン波を decay で減衰させる。周波数は呼ぶ側で下げていく。
func _thump(t: float, phase: float, decay: float) -> float:
	return sin(phase) * exp(-t * decay)


## 機械の手で掴む：金属のカチッ（倍音の合わない高い音を速く減衰）と、低いドッ。
func _synth_grab() -> AudioStreamWAV:
	var s := Synth.buffer(0.2)
	var partials := [[1150.0, 38.0], [1780.0, 46.0], [2470.0, 55.0], [3310.0, 70.0]]
	var phase := 0.0
	for i in s.size():
		var t := float(i) / Synth.SAMPLE_RATE
		var ring := 0.0
		for p in partials:
			ring += sin(TAU * p[0] * t) * exp(-t * p[1])
		phase += TAU * lerpf(130.0, 70.0, minf(t / 0.08, 1.0)) / Synth.SAMPLE_RATE
		var click := _rng.randf_range(-1.0, 1.0) * exp(-t * 400.0)
		s[i] = ring * 0.35 + _thump(t, phase, 28.0) * 0.8 + click * 0.4
	return Synth.to_wav(Synth.normalize(s))


## 手をつく：こもったノイズのペタッと、短いドッ。
func _synth_plant() -> AudioStreamWAV:
	var s := Synth.buffer(0.14)
	var smooth := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / Synth.SAMPLE_RATE
		smooth = lerpf(smooth, _rng.randf_range(-1.0, 1.0), 0.35) # 高い音を落とす
		phase += TAU * 95.0 / Synth.SAMPLE_RATE
		s[i] = smooth * exp(-t * 48.0) + _thump(t, phase, 32.0) * 0.6
	return Synth.to_wav(Synth.normalize(s))


## 着地：足の裏で受ける低いドンと、靴が擦れるザッ。
func _synth_land() -> AudioStreamWAV:
	var s := Synth.buffer(0.28)
	var smooth := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / Synth.SAMPLE_RATE
		phase += TAU * lerpf(100.0, 45.0, minf(t / 0.15, 1.0)) / Synth.SAMPLE_RATE
		smooth = lerpf(smooth, _rng.randf_range(-1.0, 1.0), 0.2)
		s[i] = _thump(t, phase, 15.0) + smooth * exp(-t * 30.0) * 0.5
	return Synth.to_wav(Synth.normalize(s))


## 受け身：床に手と肩をつくドッのあと、体が転がるゴロッ（山なりのこもったノイズ）。
func _synth_roll() -> AudioStreamWAV:
	var length := 0.45
	var s := Synth.buffer(length)
	var smooth := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / Synth.SAMPLE_RATE
		phase += TAU * lerpf(90.0, 50.0, minf(t / 0.1, 1.0)) / Synth.SAMPLE_RATE
		smooth = lerpf(smooth, _rng.randf_range(-1.0, 1.0), 0.12)
		var tumble := smooth * sin(PI * t / length) * (0.7 + 0.3 * sin(TAU * 9.0 * t))
		s[i] = _thump(t, phase, 25.0) * 0.8 + tumble * 1.4
	return Synth.to_wav(Synth.normalize(s))


## スライディング：床を擦るシャーッ。立ち上がりは速く、ゆっくり消える。
func _synth_slide() -> AudioStreamWAV:
	var s := Synth.buffer(0.5)
	var smooth := 0.0
	for i in s.size():
		var t := float(i) / Synth.SAMPLE_RATE
		smooth = lerpf(smooth, _rng.randf_range(-1.0, 1.0), 0.5)
		s[i] = smooth * minf(1.0, t / 0.02) * exp(-t * 5.0)
	return Synth.to_wav(Synth.normalize(s, 0.7))


## 空振り：手が空を切るヒュッ。
func _synth_whiff() -> AudioStreamWAV:
	var length := 0.12
	var s := Synth.buffer(length)
	var smooth := 0.0
	for i in s.size():
		var t := float(i) / Synth.SAMPLE_RATE
		smooth = lerpf(smooth, _rng.randf_range(-1.0, 1.0), 0.25)
		s[i] = smooth * sin(PI * t / length)
	return Synth.to_wav(Synth.normalize(s, 0.6))
