## VoiceChat: push-to-talk team voice (spec §15.4).
## Capture: AudioStreamMicrophone → muted "VoiceMic" bus with AudioEffectCapture → mono, resampled to
## 16 kHz → 20 ms frames of 8-bit µ-law (128 kbit/s; Godot has no Opus encoder). Transport:
##   • WebRTC data channels (unordered, no retransmits) to each human teammate, negotiated through the
##     game server (VoiceSignal). Built into web exports; on desktop it needs the webrtc-native
##     GDExtension, so `rtc_available` is probed at runtime.
##   • Fallback: VoiceData relayed by the match server to teammates when any channel is not open.
## Playback: one AudioStreamGenerator per speaker on the "Voice" bus (music ducks under it),
## per-player volume and mute stored in Settings ("comms").
class_name VoiceChat
extends Node

const RATE := 16000
const FRAME := 320  ## samples per 20 ms frame
const SIG_OFFER := 0
const SIG_ANSWER := 1
const SIG_ICE := 2

var my_id := -1
var teammates: Array[int] = []  ## human teammates (bots never talk)
var names: Dictionary = {}  ## id -> display name (mute / volume keys)
var send_message: Callable  ## func(msg: Dictionary) -> void, wired to Net
var rtc_available := false
var transmitting := false

var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _step := 1.0
var _phase := 0.0
var _prev := 0.0
var _pending := PackedFloat32Array()
var _seq := 0
var _speakers: Dictionary = {}  ## id -> {player, playback, last_seq, last_ms}
var _rtc: Dictionary = {}  ## id -> {pc: WebRTCPeerConnection, ch: WebRTCDataChannel}


func _ready() -> void:
	var probe := WebRTCPeerConnection.new()
	rtc_available = probe.initialize({}) == OK
	probe.close()


# ------------------------------------------------------------------ team / connections

func set_team(p_my_id: int, ids: Array[int], p_names: Dictionary) -> void:
	my_id = p_my_id
	names = p_names
	teammates = ids
	for id: int in _rtc.keys():
		if not teammates.has(id):
			_close_peer(id)
	if not rtc_available:
		return
	# The lower id offers; both sides use a pre-negotiated channel (id 1), so no in-band handshake.
	for id: int in teammates:
		if id > my_id and not _rtc.has(id):
			var pc := _new_peer(id)
			pc.create_offer()


func _new_peer(id: int) -> WebRTCPeerConnection:
	var pc := WebRTCPeerConnection.new()
	var cfg: Dictionary = {}
	var stun := str(Settings.get_value("comms", "stun_server"))
	if stun != "":
		cfg["iceServers"] = [{"urls": [stun]}]
	pc.initialize(cfg)
	var ch := pc.create_data_channel("voice", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	pc.session_description_created.connect(func(type: String, sdp: String) -> void:
		pc.set_local_description(type, sdp)
		_signal(id, SIG_OFFER if type == "offer" else SIG_ANSWER, sdp))
	pc.ice_candidate_created.connect(func(mid: String, index: int, cand: String) -> void:
		_signal(id, SIG_ICE, "%s\n%d\n%s" % [mid, index, cand]))
	_rtc[id] = {"pc": pc, "ch": ch}
	return pc


func _close_peer(id: int) -> void:
	var e: Dictionary = _rtc.get(id, {})
	if e.has("pc"):
		(e["pc"] as WebRTCPeerConnection).close()
	_rtc.erase(id)


func _signal(to_id: int, kind: int, sdp: String) -> void:
	if send_message.is_valid():
		send_message.call({"type": "VoiceSignal", "fromId": 0, "toId": to_id, "kind": kind, "sdp": sdp})


func on_signal(msg: Dictionary) -> void:
	if not rtc_available:
		return
	var from := int(msg["fromId"])
	if not teammates.has(from):
		return
	var kind := int(msg["kind"])
	var pc: WebRTCPeerConnection
	if _rtc.has(from):
		pc = _rtc[from]["pc"]
	else:
		pc = _new_peer(from)
	match kind:
		SIG_OFFER:
			pc.set_remote_description("offer", str(msg["sdp"]))
		SIG_ANSWER:
			pc.set_remote_description("answer", str(msg["sdp"]))
		SIG_ICE:
			var parts := str(msg["sdp"]).split("\n", true, 2)
			if parts.size() == 3:
				pc.add_ice_candidate(parts[0], int(parts[1]), parts[2])


func _channel_open(id: int) -> bool:
	var e: Dictionary = _rtc.get(id, {})
	return e.has("ch") and (e["ch"] as WebRTCDataChannel).get_ready_state() == WebRTCDataChannel.STATE_OPEN


# ------------------------------------------------------------------ capture + send

func _ensure_mic() -> void:
	if _mic != null:
		return
	var bus := AudioServer.get_bus_index("VoiceMic")
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "VoiceMic")
		AudioServer.set_bus_mute(bus, true)  # no local monitoring
		AudioServer.add_bus_effect(bus, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = &"VoiceMic"
	add_child(_mic)
	_mic.play()  # web: this is where the browser asks for microphone permission
	_step = AudioServer.get_mix_rate() / float(RATE)


func set_transmitting(on: bool) -> void:
	if on and not bool(Settings.get_value("comms", "voice_enabled")):
		return
	if on:
		_ensure_mic()
		_capture.clear_buffer()
	transmitting = on


func _process(_delta: float) -> void:
	for id: int in _rtc:
		var e: Dictionary = _rtc[id]
		(e["pc"] as WebRTCPeerConnection).poll()
		var ch: WebRTCDataChannel = e["ch"]
		while ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN and ch.get_available_packet_count() > 0:
			var pkt := ch.get_packet()
			if pkt.size() > 2:
				_receive(id, pkt.decode_u16(0), pkt.slice(2))
	if _capture == null:
		return
	var n := _capture.get_frames_available()
	if n == 0:
		return
	var buf := _capture.get_buffer(n)
	if not transmitting:
		return
	# Mono + linear-interpolation resample to 16 kHz.
	for f: Vector2 in buf:
		var s := (f.x + f.y) * 0.5
		while _phase < 1.0:
			_pending.append(lerpf(_prev, s, _phase))
			_phase += _step
		_phase -= 1.0
		_prev = s
	while _pending.size() >= FRAME:
		_send_frame(Ulaw.encode(_pending.slice(0, FRAME)))
		_pending = _pending.slice(FRAME)


func _send_frame(data: PackedByteArray) -> void:
	_seq = (_seq + 1) & 0xFFFF
	var all_rtc := not teammates.is_empty()
	for id: int in teammates:
		all_rtc = all_rtc and _channel_open(id)
	if all_rtc:
		var pkt := PackedByteArray([_seq & 0xFF, _seq >> 8])
		pkt.append_array(data)
		for id: int in teammates:
			(_rtc[id]["ch"] as WebRTCDataChannel).put_packet(pkt)
	elif send_message.is_valid() and not teammates.is_empty():
		send_message.call({"type": "VoiceData", "playerId": 0, "seq": _seq, "data": data})


# ------------------------------------------------------------------ receive + playback

func on_voice_data(msg: Dictionary) -> void:
	_receive(int(msg["playerId"]), int(msg["seq"]), msg["data"])


func _receive(from: int, seq: int, data: PackedByteArray) -> void:
	if is_muted(from) or data.is_empty():
		return
	var sp: Dictionary = _speakers.get(from, {})
	if sp.is_empty():
		sp = _new_speaker(from)
	if int(sp["last_seq"]) == seq:
		return  # same frame via relay and data channel
	sp["last_seq"] = seq
	sp["last_ms"] = Time.get_ticks_msec()
	var pb: AudioStreamGeneratorPlayback = sp["playback"]
	if pb.get_frames_available() < data.size():
		return
	var frames := PackedVector2Array()
	frames.resize(data.size())
	for i: int in data.size():
		var v := Ulaw.decode(data[i])
		frames[i] = Vector2(v, v)
	pb.push_buffer(frames)


func _new_speaker(id: int) -> Dictionary:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.4
	var p := AudioStreamPlayer.new()
	p.stream = gen
	p.bus = &"Voice"
	add_child(p)
	p.play()
	var sp := {"player": p, "playback": p.get_stream_playback(), "last_seq": -1, "last_ms": 0}
	_speakers[id] = sp
	apply_volume(id)
	return sp


## Ids heard in the last 250 ms (HUD speaking indicator).
func speaking() -> Array[int]:
	var out: Array[int] = []
	var now := Time.get_ticks_msec()
	for id: int in _speakers:
		if now - int(_speakers[id]["last_ms"]) < 250:
			out.append(id)
	return out


func _key(id: int) -> String:
	return str(names.get(id, id))


func is_muted(id: int) -> bool:
	return (Settings.get_value("comms", "muted") as Array).has(_key(id))


func set_muted(id: int, muted: bool) -> void:
	var list: Array = (Settings.get_value("comms", "muted") as Array).duplicate()
	list.erase(_key(id))
	if muted:
		list.append(_key(id))
	Settings.set_value("comms", "muted", list)


## Per-player volume, 0..1 linear (Settings "comms.volumes": name -> volume).
func set_volume(id: int, linear: float) -> void:
	var vols: Dictionary = (Settings.get_value("comms", "volumes") as Dictionary).duplicate()
	vols[_key(id)] = clampf(linear, 0.0, 1.0)
	Settings.set_value("comms", "volumes", vols)
	apply_volume(id)


func apply_volume(id: int) -> void:
	if not _speakers.has(id):
		return
	var v := float((Settings.get_value("comms", "volumes") as Dictionary).get(_key(id), 1.0))
	(_speakers[id]["player"] as AudioStreamPlayer).volume_db = linear_to_db(maxf(v, 0.0001))
