# The client side of directory/'s room-code lookup — see directory/README.md
# for the service this talks to.
#
# RefCounted and manually polled, like every other net class here
# (client.gd, server.gd, discovery.gd) — nothing in scripts/net/ depends on
# being a Node in the tree, and this should not be the first exception.
# HTTPRequest needs a scene tree to drive itself; HTTPClient does not, and is
# built exactly for a caller that wants to poll it, so that is what this
# wraps.
#
# ONE request in flight at a time. A host registers once, then re-registers
# (heartbeats) on a timer main.gd owns; a joiner looks a code up once. Nothing
# about this feature needs two requests running at once, so a single small
# state machine is simpler than a queue.
extends RefCounted

signal registered(code: String)
signal register_failed(reason: String)
signal looked_up(url: String, name: String)
signal lookup_failed(reason: String)

enum _Op { NONE, REGISTER, LOOKUP }
enum _Step { IDLE, RESOLVING, CONNECTING, REQUESTING, READING, DONE }

# Re-register this often while hosting, well inside directory/'s 60s TTL —
# see directory/server.js's own TTL_MS comment.
const HEARTBEAT_SECONDS := 20.0

var _http := HTTPClient.new()
var _op: int = _Op.NONE
var _step: int = _Step.IDLE
var _host := ""
var _port := 80
var _use_tls := false
var _path := ""
var _body := ""
var _response := PackedByteArray()
var _last_code := ""

## Set by main.gd once it has a code back from `registered`, and re-sent on
## every heartbeat so the SAME room is refreshed rather than a new one minted
## each time — see directory/server.js's own "heartbeat keeps the same code"
## behaviour.
var last_code: String:
	get: return _last_code


func register(directory_url: String, server_url: String,
		display_name: String = "") -> void:
	var body := {"url": server_url, "name": display_name}
	if not _last_code.is_empty():
		body["code"] = _last_code
	_start(_Op.REGISTER, directory_url, "/rooms", JSON.stringify(body))


func lookup(directory_url: String, code: String) -> void:
	_start(_Op.LOOKUP, directory_url,
		"/rooms/%s" % code.strip_edges().to_upper(), "")


func _start(op: int, directory_url: String, path: String, body: String) -> void:
	var parsed := _parse_url(directory_url)
	if parsed.is_empty():
		_fail(op, "not a valid http(s) URL: %s" % directory_url)
		return
	_op = op
	_host = parsed["host"]
	_port = parsed["port"]
	_use_tls = parsed["tls"]
	_path = path
	_body = body
	_response = PackedByteArray()
	var err := _http.connect_to_host(_host, _port,
		TLSOptions.client() if _use_tls else null)
	if err != OK:
		_fail(op, "cannot resolve %s: %s" % [_host, error_string(err)])
		return
	_step = _Step.CONNECTING


## Drive the request forward. Call every frame while an operation is in
## flight — `busy()` says whether one is.
func poll() -> void:
	if _step == _Step.IDLE or _step == _Step.DONE:
		return
	_http.poll()
	var status := _http.get_status()

	match _step:
		_Step.CONNECTING:
			if status == HTTPClient.STATUS_CONNECTED:
				_send_request()
			elif status == HTTPClient.STATUS_CANT_CONNECT \
					or status == HTTPClient.STATUS_CANT_RESOLVE \
					or status == HTTPClient.STATUS_CONNECTION_ERROR \
					or status == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR \
					or status == HTTPClient.STATUS_DISCONNECTED:
				_fail(_op, "cannot reach the directory (%s)" % _host)

		_Step.REQUESTING:
			if status == HTTPClient.STATUS_BODY:
				_step = _Step.READING
			elif status == HTTPClient.STATUS_CONNECTED:
				# A response with no body at all — still worth reading the
				# response code, but there is nothing more to poll for.
				_finish()
			elif status == HTTPClient.STATUS_CONNECTION_ERROR \
					or status == HTTPClient.STATUS_DISCONNECTED:
				_fail(_op, "connection lost mid-request")

		_Step.READING:
			# Only ever read a chunk while the client is actually IN the body
			# — asking otherwise is a Godot-side error, not just an empty
			# result. Once status moves past BODY, everything that was
			# coming has arrived.
			if status == HTTPClient.STATUS_BODY:
				var chunk := _http.read_response_body_chunk()
				if not chunk.is_empty():
					_response.append_array(chunk)
			else:
				_finish()


func busy() -> bool:
	return _step != _Step.IDLE and _step != _Step.DONE


func _send_request() -> void:
	var headers := PackedStringArray()
	var method := HTTPClient.METHOD_GET
	if _op == _Op.REGISTER:
		method = HTTPClient.METHOD_POST
		headers.append("Content-Type: application/json")
		headers.append("Content-Length: %d" % _body.to_utf8_buffer().size())
	var err := _http.request(method, _path, headers, _body)
	if err != OK:
		_fail(_op, "request failed: %s" % error_string(err))
		return
	_step = _Step.REQUESTING


func _finish() -> void:
	var code := _http.get_response_code()
	var op := _op
	_step = _Step.DONE
	_op = _Op.NONE

	var text := _response.get_string_from_utf8()
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	var body: Dictionary = parsed if parsed is Dictionary else {}

	if code < 200 or code >= 300:
		_fail(op, String(body.get("error", "directory returned %d" % code)))
		return

	match op:
		_Op.REGISTER:
			_last_code = String(body.get("code", ""))
			if _last_code.is_empty():
				_fail(op, "the directory did not return a code")
				return
			registered.emit(_last_code)
		_Op.LOOKUP:
			var url := String(body.get("url", ""))
			if url.is_empty():
				_fail(op, "the directory's answer had no url")
				return
			looked_up.emit(url, String(body.get("name", "")))


func _fail(op: int, reason: String) -> void:
	_step = _Step.DONE
	_op = _Op.NONE
	match op:
		_Op.REGISTER: register_failed.emit(reason)
		_Op.LOOKUP: lookup_failed.emit(reason)


## "http://host:port", "https://host" (port 443 implied), etc. Returns {} for
## anything else — a caller passing a bare host or a ws:// URL by mistake
## should get a clear failure, not a guess.
static func _parse_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"):
		return {}
	var rest := url.substr(8 if tls else 7)
	# Drop a trailing path — this class always supplies its own.
	var slash := rest.find("/")
	if slash >= 0:
		rest = rest.substr(0, slash)
	var host := rest
	var port := 443 if tls else 80
	var colon := rest.rfind(":")
	if colon >= 0:
		host = rest.substr(0, colon)
		var port_str := rest.substr(colon + 1)
		if not port_str.is_valid_int():
			return {}
		port = int(port_str)
	if host.is_empty():
		return {}
	return {"host": host, "port": port, "tls": tls}
