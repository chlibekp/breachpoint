## Autoload: binary WebSocket connection to the authoritative server (spec 13).
## Milestone 1: Hello/AuthOk handshake and RTT measurement. Prediction, interpolation and the
## reliable channel arrive in milestone 4 under scripts/net/.
extends Node

signal state_changed(state: int)
signal message_received(msg: Dictionary)
signal rtt_updated(rtt_ms: float)

enum State { OFFLINE, CONNECTING, HANDSHAKE, ONLINE, FAILED }

const PING_INTERVAL := 1.0
const CONNECT_TIMEOUT := 5.0

var state: State = State.OFFLINE
var player_id: int = -1
var display_name: String = ""
var server_tick: int = 0
var rtt_ms: float = -1.0
var last_error: String = ""
var token: String = ""  ## access token sent in Hello (empty = anonymous quick play)
var pending_ticket: String = ""  ## matchmaking join ticket for the next JoinMatch

var _ws: WebSocketPeer = null
var _ping_timer: float = 0.0
var _connect_timer: float = 0.0
var _nonce: int = 0


func connect_to(url: String) -> void:
	disconnect_from_server()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail("connect_to_url failed: %s" % error_string(err))
		return
	_connect_timer = 0.0
	_set_state(State.CONNECTING)


func disconnect_from_server() -> void:
	if _ws != null and state == State.ONLINE:
		send({"type": "Disconnect", "reason": "client_quit"})
		_ws.close(1000, "bye")
	_ws = null
	_set_state(State.OFFLINE)


func send(msg: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var bytes := Protocol.encode(msg)
	if not bytes.is_empty():
		_ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_connect_timer += delta
			if _connect_timer > CONNECT_TIMEOUT:
				_fail("timed out")
		WebSocketPeer.STATE_OPEN:
			if state == State.CONNECTING:
				_set_state(State.HANDSHAKE)
				var platform := "web" if OS.has_feature("web") else OS.get_name().to_lower()
				send({"type": "Hello", "protocolVersion": Protocol.PROTOCOL_VERSION, "token": token, "platform": platform})
			while _ws.get_available_packet_count() > 0:
				_handle(_ws.get_packet())
			if state == State.ONLINE:
				_ping_timer += delta
				if _ping_timer >= PING_INTERVAL:
					_ping_timer = 0.0
					_nonce += 1
					send({"type": "Ping", "nonce": _nonce, "clientTimeMs": _now_ms()})
		WebSocketPeer.STATE_CLOSED:
			var reason := _ws.get_close_reason()
			_fail(reason if reason != "" else "connection closed (%d)" % _ws.get_close_code())


func _handle(bytes: PackedByteArray) -> void:
	var msg := Protocol.decode(bytes)
	if msg.is_empty():
		push_warning("Net: dropped malformed packet (%d bytes)" % bytes.size())
		return
	match str(msg["type"]):
		"AuthOk":
			player_id = msg["playerId"]
			display_name = msg["displayName"]
			server_tick = msg["serverTick"]
			_set_state(State.ONLINE)
			_ping_timer = PING_INTERVAL  # ping immediately
		"Pong":
			# f32 round-trips the client clock with ~0.1 ms precision for the first ~30 min,
			# which is enough for a display RTT; the netcode clock sync uses ticks (milestone 4).
			rtt_ms = maxf(0.0, _now_ms() - float(msg["clientTimeMs"]))
			server_tick = msg["serverTick"]
			rtt_updated.emit(rtt_ms)
		"Disconnect":
			last_error = msg["reason"]
	message_received.emit(msg)


func _now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


func _fail(reason: String) -> void:
	last_error = reason
	_ws = null
	_set_state(State.FAILED)


func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)
