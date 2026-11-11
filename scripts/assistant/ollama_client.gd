class_name OllamaClient
extends Node
## Talks to a local Ollama server. Localhost only: no cloud, no keys, no telemetry.
## Every failure (server not running, model missing, timeout, bad JSON, empty
## reply) is reported as reply(false, "") so the caller can use the offline fallback.

signal reply(ok: bool, text: String)

const HOST_URL := "http://127.0.0.1:11434/api/chat"
const MODEL := "qwen2.5:1.5b"
const TIMEOUT_SECONDS := 25.0
const MAX_TOKENS := 160
const TEMPERATURE := 0.2
const KEEP_ALIVE := "10m"

var _request: HTTPRequest
var _warm_request: HTTPRequest
var _busy: bool = false
var _warmed_up: bool = false


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = TIMEOUT_SECONDS
	_request.request_completed.connect(_on_completed)
	add_child(_request)

	_warm_request = HTTPRequest.new()
	_warm_request.timeout = TIMEOUT_SECONDS
	add_child(_warm_request)


## Sends the chat messages. Returns false if a request is already running or
## could not be started; in that case no reply signal is emitted.
func ask(messages: Array) -> bool:
	if _busy:
		return false
	var error := _request.request(HOST_URL, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(_body(messages, MAX_TOKENS)))
	if error != OK:
		return false
	_busy = true
	return true


## Loads the model into memory in the background the first time ORACLE opens,
## so the first real question is not slow. The result is ignored.
func warm_up() -> void:
	if _warmed_up:
		return
	_warmed_up = true
	var messages := [{"role": "user", "content": "Reply with the single word: ready"}]
	_warm_request.request(HOST_URL, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(_body(messages, 1)))


func _body(messages: Array, max_tokens: int) -> Dictionary:
	return {
		"model": MODEL,
		"messages": messages,
		"stream": false,
		"keep_alive": KEEP_ALIVE,
		"options": {"temperature": TEMPERATURE, "num_predict": max_tokens},
	}


func _on_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		reply.emit(false, "")
		return
	var text := OracleLogic.parse_ollama_response(body.get_string_from_utf8())
	reply.emit(not text.is_empty(), text)
