# The client side of directory/'s room-code API (scripts/net/directory.gd).
#
# directory/ is a separate Node service with its own test suite
# (directory/test.js) — this does not run it. What's proven here is
# `Directory_`'s own HTTPClient state machine against a REAL socket, so a
# hand-rolled fake HTTP/1.1 server stands in for it: enough of the protocol
# to answer exactly what `Directory_.register()`/`lookup()` send, over
# 127.0.0.1, using Godot's real network stack rather than mocking HTTPClient
# itself.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Directory_ := preload("res://scripts/net/directory.gd")

const TEST_PORT := 47698


func _init() -> void:
	var t := T_.new("directory")
	_test_parses_urls(t)
	await _test_register_over_a_real_socket(t)
	await _test_lookup_over_a_real_socket(t)
	await _test_a_failed_lookup(t)
	await _test_unreachable_directory(t)
	quit(t.finish())


func _test_parses_urls(t: T_) -> void:
	var d := Directory_.new()
	var plain: Dictionary = d._parse_url("http://example.com")
	t.eq(plain.get("host"), "example.com", "bare http host")
	t.eq(plain.get("port"), 80, "defaults to port 80")
	t.eq(plain.get("tls"), false, "and no TLS")

	var secure: Dictionary = d._parse_url("https://example.com")
	t.eq(secure.get("port"), 443, "https defaults to 443")
	t.eq(secure.get("tls"), true, "and TLS on")

	var with_port: Dictionary = d._parse_url("http://127.0.0.1:8420")
	t.eq(with_port.get("host"), "127.0.0.1", "an explicit host")
	t.eq(with_port.get("port"), 8420, "and an explicit port")

	var with_path: Dictionary = d._parse_url("http://host:1234/whatever")
	t.eq(with_path.get("port"), 1234, "a trailing path is dropped, not parsed as part of the port")

	t.eq(d._parse_url("ws://host:1234"), {}, "a ws:// URL is rejected, not silently misread")
	t.eq(d._parse_url("not a url"), {}, "junk is rejected")


func _test_register_over_a_real_socket(t: T_) -> void:
	var srv := _FakeServer.new()
	if not t.ok(srv.listen(TEST_PORT), "the fake directory listens"):
		return

	var d := Directory_.new()
	# A Dictionary, not a plain local — a lambda captures an outer local by
	# value, so reassigning it inside the callback would never be seen out
	# here; mutating a shared container is what other suites in this repo
	# already do for the same reason (test_netplay.gd's `heard["a"] = s`).
	var got := {"code": "", "failed": ""}
	d.registered.connect(func(c: String): got["code"] = c)
	d.register_failed.connect(func(r: String): got["failed"] = r)
	d.register("http://127.0.0.1:%d" % TEST_PORT, "ws://203.0.113.5:47600",
		"Carlos's game")

	for _i in 200:
		srv.poll('{"code":"AB3XQ"}')
		d.poll()
		if not String(got["code"]).is_empty() or not String(got["failed"]).is_empty():
			break
		await process_frame

	t.eq(got["failed"], "", "registering did not fail (%s)" % got["failed"])
	t.eq(got["code"], "AB3XQ", "the code the fake server returned comes back")
	t.eq(srv.last_method, "POST", "registering POSTs")
	t.eq(srv.last_path, "/rooms", "to /rooms")
	var sent: Dictionary = JSON.parse_string(srv.last_body)
	t.eq(sent.get("url"), "ws://203.0.113.5:47600", "carrying the server url")
	t.eq(sent.get("name"), "Carlos's game", "and the display name")
	t.eq(d.last_code, "AB3XQ", "Directory_ remembers the code for the next heartbeat")
	srv.stop()


func _test_lookup_over_a_real_socket(t: T_) -> void:
	var srv := _FakeServer.new()
	if not t.ok(srv.listen(TEST_PORT + 1), "the fake directory listens"):
		return

	var d := Directory_.new()
	var got := {"url": "", "name": ""}
	d.looked_up.connect(func(u: String, n: String): got["url"] = u; got["name"] = n)
	d.lookup("http://127.0.0.1:%d" % (TEST_PORT + 1), "ab3xq")

	var json := '{"url":"ws://203.0.113.5:47600","name":"Carlos\'s game"}'
	for _i in 200:
		srv.poll(json)
		d.poll()
		if not String(got["url"]).is_empty():
			break
		await process_frame

	t.eq(got["url"], "ws://203.0.113.5:47600", "the looked-up url comes back")
	t.eq(got["name"], "Carlos's game", "and the name")
	t.eq(srv.last_method, "GET", "looking up GETs")
	t.eq(srv.last_path, "/rooms/AB3XQ", "the path uppercases the code")
	srv.stop()


func _test_a_failed_lookup(t: T_) -> void:
	var srv := _FakeServer.new()
	if not t.ok(srv.listen(TEST_PORT + 2), "the fake directory listens"):
		return

	var d := Directory_.new()
	var got := {"failed": ""}
	d.lookup_failed.connect(func(r: String): got["failed"] = r)
	d.lookup("http://127.0.0.1:%d" % (TEST_PORT + 2), "ZZZZZ")

	for _i in 200:
		srv.poll_status(404, '{"error":"no such room"}')
		d.poll()
		if not String(got["failed"]).is_empty():
			break
		await process_frame

	t.eq(got["failed"], "no such room", "a 404's own error message surfaces")
	srv.stop()


func _test_unreachable_directory(t: T_) -> void:
	var d := Directory_.new()
	var got := {"failed": ""}
	d.register_failed.connect(func(r: String): got["failed"] = r)
	# Nothing is listening on this port — the point of the test.
	d.register("http://127.0.0.1:%d" % (TEST_PORT + 3), "ws://x:1", "x")

	for _i in 200:
		d.poll()
		if not String(got["failed"]).is_empty():
			break
		await process_frame

	t.ok(not String(got["failed"]).is_empty(),
		"an unreachable directory fails rather than hanging forever")


## A minimal HTTP/1.1 server: enough to read one request's method, path and
## body, and answer with one canned JSON response, then close. Not a general
## test double — just what Directory_'s own two calls actually send.
class _FakeServer:
	var _tcp := TCPServer.new()
	var _conn: StreamPeerTCP = null
	var _buf := PackedByteArray()
	var _responded := false
	var last_method := ""
	var last_path := ""
	var last_body := ""

	func listen(port: int) -> bool:
		return _tcp.listen(port, "127.0.0.1") == OK

	## Accepts a connection if one is pending, reads what it can, and once a
	## full request (headers + any body Content-Length promised) has arrived,
	## sends `json_body` back as a 200 OK exactly once.
	func poll(json_body: String) -> void:
		poll_status(200, json_body)

	func poll_status(status: int, json_body: String) -> void:
		if _responded:
			return
		if _conn == null and _tcp.is_connection_available():
			_conn = _tcp.take_connection()
		if _conn == null:
			return
		_conn.poll()
		var avail := _conn.get_available_bytes()
		if avail > 0:
			_buf.append_array(_conn.get_data(avail)[1])
		var header_end := _find(_buf, "\r\n\r\n")
		if header_end < 0:
			return
		var head := _buf.slice(0, header_end).get_string_from_utf8()
		var lines := head.split("\r\n")
		var request_line := lines[0].split(" ")
		last_method = request_line[0] if request_line.size() > 0 else ""
		last_path = request_line[1] if request_line.size() > 1 else ""
		var content_length := 0
		for line in lines:
			if line.to_lower().begins_with("content-length:"):
				content_length = int(line.split(":")[1].strip_edges())
		var body_start := header_end + 4
		if _buf.size() - body_start < content_length:
			return # body still arriving
		last_body = _buf.slice(body_start, body_start + content_length) \
			.get_string_from_utf8()

		var body_bytes := json_body.to_utf8_buffer()
		var status_text := "OK" if status == 200 else "Not Found"
		var resp := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" \
			% [status, status_text, body_bytes.size(), json_body]
		_conn.put_data(resp.to_utf8_buffer())
		_responded = true

	func stop() -> void:
		if _conn != null:
			_conn.disconnect_from_host()
		_tcp.stop()

	static func _find(haystack: PackedByteArray, needle: String) -> int:
		var n := needle.to_utf8_buffer()
		for i in haystack.size() - n.size() + 1:
			var ok := true
			for j in n.size():
				if haystack[i + j] != n[j]:
					ok = false
					break
			if ok:
				return i
		return -1
