class_name FlickDetector
extends RefCounted
## 右スティックの「弾き」を見つける（M4 アナログ斬り）。
## スティックが中心付近（INNER未満）を離れてから、受付時間のうちに外周（OUTER以上）まで届いたら弾きとみなす。
## 向きは弾き始め（中心付近を最後に通った位置）から弾き終わりへの向き、速さは移動量 ÷ かかった時間。
## ゆっくり倒しただけでは出ない。1回弾いたら、中心付近へ戻すまで次は出ない。

const INNER := 0.3
const OUTER := 0.85

var _armed := false # 中心付近を通るまでは弾きとみなさない（倒したまま斬撃モードに入ったときなど）
var _start := Vector2.ZERO
var _start_t := 0.0
var _t := 0.0


## v：スティックの位置（右が+x、下が+y）。弾きが出たら {"dir": 画面上の向き（上が+y）, "speed": 毎秒の移動量}。
func feed(v: Vector2, delta: float, window: float) -> Dictionary:
	_t += delta
	if v.length() < INNER:
		_armed = true
		_start = v
		_start_t = _t
		return {}
	if not _armed or v.length() < OUTER:
		return {}
	_armed = false
	var elapsed := maxf(_t - _start_t, delta)
	if elapsed > window:
		return {}
	var move := v - _start
	return {"dir": Vector2(move.x, -move.y).normalized(), "speed": move.length() / elapsed}


## 斬撃モードを抜けたら呼ぶ。次は中心付近へ戻してから。
func reset() -> void:
	_armed = false
