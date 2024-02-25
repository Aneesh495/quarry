-- Quarry embedded HTTP analytics server
-- Non-blocking HTTP 1.1 daemon serving REST API endpoints and web dashboard.

local C = require("src.common.c").C
local alloc = require("src.common.alloc")
local cat = require("src.storage/catalog")

local server = {}

server.DEFAULT_PORT = 8080

struct HttpServer {
    port: uint16,
    server_fd: int32,
    is_running: bool
}

terra HttpServer:init(port: uint16)
    self.port = port
    self.server_fd = -1
    self.is_running = false
end

terra HttpServer:build_json_response(body: &int8, out_buf: &int8, max_len: C.size_t) : int32
    var body_len = C.strlen(body)
    return C.snprintf(out_buf, max_len,
        "HTTP/1.1 200 OK\r\n" ..
        "Content-Type: application/json\r\n" ..
        "Content-Length: %lu\r\n" ..
        "Access-Control-Allow-Origin: *\r\n" ..
        "Connection: close\r\n\r\n" ..
        "%s", body_len, body)
end

terra HttpServer:build_html_response(html: &int8, out_buf: &int8, max_len: C.size_t) : int32
    var html_len = C.strlen(html)
    return C.snprintf(out_buf, max_len,
        "HTTP/1.1 200 OK\r\n" ..
        "Content-Type: text/html; charset=utf-8\r\n" ..
        "Content-Length: %lu\r\n" ..
        "Connection: close\r\n\r\n" ..
        "%s", html_len, html)
end

server.HttpServer = HttpServer
return server
