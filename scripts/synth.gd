class_name Synth
## 効果音をその場で作るための道具。音素材を持たずに済む（HitFeel・ParkourFeel が使う）。

const SAMPLE_RATE := 22050


## 長さ seconds の空の波形。
static func buffer(seconds: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(SAMPLE_RATE * seconds))
	return samples


## いちばん大きいところが peak になるようにそろえる。
static func normalize(samples: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var top := 0.0
	for v in samples:
		top = maxf(top, absf(v))
	if top > 0.0:
		for i in samples.size():
			samples[i] *= peak / top
	return samples


static func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
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
