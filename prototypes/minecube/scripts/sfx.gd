class_name Sfx
extends Node

## 音效池。素材与许可见 assets/sfx/CREDITS.md。
## 揭示是最高频的操作，所以揭示音只有 96 毫秒，连点也不会糊。

const STREAM_REVEAL: AudioStream = preload("res://assets/sfx/reveal.mp3")
const STREAM_FLOOD: AudioStream = preload("res://assets/sfx/flood.mp3")
const STREAM_FLAG: AudioStream = preload("res://assets/sfx/flag.mp3")
const STREAM_BOOM: AudioStream = preload("res://assets/sfx/boom.mp3")
const STREAM_WIN: AudioStream = preload("res://assets/sfx/win.mp3")
const STREAM_UI: AudioStream = preload("res://assets/sfx/ui_click.mp3")

const POOL_SIZE := 8

var muted := false

var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_players.append(p)


func toggle_mute() -> bool:
	muted = not muted
	return muted


func reveal() -> void:
	_play(STREAM_REVEAL, -9.0, randf_range(0.94, 1.06))


## 一次展开的格子越多，音越高、越亮
func flood(opened_count: int) -> void:
	var t := clampf(float(opened_count) / 24.0, 0.0, 1.0)
	_play(STREAM_FLOOD, -10.0 + 4.5 * t, 0.92 + 0.42 * t)


func flag() -> void:
	_play(STREAM_FLAG, -7.0, randf_range(0.9, 1.1))


func unflag() -> void:
	_play(STREAM_FLAG, -9.0, randf_range(0.78, 0.86))


func chord() -> void:
	_play(STREAM_FLOOD, -6.0, 1.28)


func boom() -> void:
	_play(STREAM_BOOM, -3.0, 1.0)


func win() -> void:
	_play(STREAM_WIN, -6.0, 1.0)


func ui() -> void:
	_play(STREAM_UI, -13.0, 1.0)


func _play(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if muted or stream == null or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.play()
