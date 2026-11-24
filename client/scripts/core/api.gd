## Autoload: HTTP client for the backend API (spec §14.1): guest/email auth with stored rotating
## refresh token, profile, party, matchmaking queue, agent select and match history.
extends Node

signal session_changed

const SESSION_PATH := "user://session.cfg"

var base_url := "http://127.0.0.1:7351"
var access_token := ""
var refresh_token := ""
var profile: Dictionary = {}
var online := false
var last_error := ""


func _ready() -> void:
	if OS.has_feature("web"):
		var host: Variant = JavaScriptBridge.eval("location.hostname || '127.0.0.1'", true)
		var api: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('api') || ''", true)
		base_url = str(api) if str(api) != "" else "http://%s:7351" % str(host)
	var args := Game.parse_user_args(OS.get_cmdline_user_args())
	if args.has("api"):
		base_url = str(args["api"])
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) == OK:
		refresh_token = str(cfg.get_value("session", "refresh", ""))


## Refreshes a stored session or creates a guest account. Returns true when signed in.
func ensure_session() -> bool:
	if refresh_token != "":
		var r := await request("POST", "/auth/refresh", {"refreshToken": refresh_token}, false)
		if r.get("ok", false):
			_take_tokens(r["body"])
			return true
	var g := await request("POST", "/auth/guest", {}, false)
	if g.get("ok", false):
		_take_tokens(g["body"])
		return true
	online = false
	return false


func login(email: String, password: String) -> bool:
	var r := await request("POST", "/auth/login", {"email": email, "password": password}, false)
	if r.get("ok", false):
		_take_tokens(r["body"])
	return r.get("ok", false)


func register(email: String, password: String, player_name: String) -> bool:
	var r := await request("POST", "/auth/register", {"email": email, "password": password, "name": player_name}, false)
	if r.get("ok", false):
		_take_tokens(r["body"])
	return r.get("ok", false)


## OAuth providers the server has enabled ("google", "discord").
func oauth_providers() -> PackedStringArray:
	var r := await request("GET", "/auth/oauth/providers", null, false)
	var out := PackedStringArray()
	if r.get("ok", false) and r["body"] is Dictionary:
		for p: Variant in (r["body"] as Dictionary).get("providers", []):
			out.append(str(p))
	return out


## OAuth sign-in: opens the provider page in the system browser (or a new tab on web) and polls the
## server until the sign-in completes. Returns true when signed in; false on cancel/timeout.
func oauth_login(provider: String) -> bool:
	var r := await request("POST", "/auth/oauth/start", {"provider": provider}, false)
	if not r.get("ok", false):
		return false
	var session := str(r["body"]["session"])
	OS.shell_open(str(r["body"]["url"]))
	for _i: int in 90:  # up to 3 minutes
		await get_tree().create_timer(2.0).timeout
		var p := await request("GET", "/auth/oauth/poll?session=%s" % session.uri_encode(), null, false)
		if not p.get("ok", false):
			return false
		var status := str((p["body"] as Dictionary).get("status", ""))
		if status == "ok":
			_take_tokens(p["body"]["tokens"])
			return true
		if status != "pending":
			last_error = str((p["body"] as Dictionary).get("error", "sign-in failed"))
			return false
	last_error = "sign-in timed out"
	return false


func _take_tokens(body: Dictionary) -> void:
	access_token = str(body["accessToken"])
	refresh_token = str(body["refreshToken"])
	profile = body["account"]
	online = true
	var cfg := ConfigFile.new()
	cfg.set_value("session", "refresh", refresh_token)
	cfg.save(SESSION_PATH)
	session_changed.emit()


func display_name() -> String:
	return "%s#%s" % [profile.get("name", "Player"), profile.get("tag", "0000")] if not profile.is_empty() else "Offline"


## Binary GET (replays). Returns the raw bytes, empty on failure (see last_error).
func download(path: String) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = 30.0
	http.body_size_limit = 64 * 1024 * 1024
	add_child(http)
	var headers := PackedStringArray()
	if access_token != "":
		headers.append("authorization: Bearer %s" % access_token)
	var err := http.request(base_url + path, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		last_error = error_string(err)
		return PackedByteArray()
	var res: Array = await http.request_completed
	http.queue_free()
	if int(res[1]) != 200:
		last_error = "replay unavailable (%d)" % int(res[1])
		return PackedByteArray()
	return res[3]


## JSON request. Returns {ok, status, body}. Retries once after refreshing an expired access token.
func request(method: String, path: String, body: Variant = null, auth: bool = true) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var headers := PackedStringArray(["content-type: application/json"])
	if auth and access_token != "":
		headers.append("authorization: Bearer %s" % access_token)
	var m: int = {"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT, "DELETE": HTTPClient.METHOD_DELETE}[method]
	var err := http.request(base_url + path, headers, m, JSON.stringify(body) if body != null else "")
	if err != OK:
		http.queue_free()
		last_error = error_string(err)
		return {"ok": false, "status": 0, "body": {}}
	var res: Array = await http.request_completed
	http.queue_free()
	var status := int(res[1])
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if text != "" else {}
	if status == 401 and auth and refresh_token != "" and path != "/auth/refresh":
		var r := await request("POST", "/auth/refresh", {"refreshToken": refresh_token}, false)
		if r.get("ok", false):
			_take_tokens(r["body"])
			return await request(method, path, body, auth)
	if status == 0:
		last_error = "server unreachable"
	elif status >= 400 and parsed is Dictionary:
		last_error = str((parsed as Dictionary).get("error", status))
	return {"ok": status >= 200 and status < 300, "status": status, "body": parsed if parsed != null else {}}
