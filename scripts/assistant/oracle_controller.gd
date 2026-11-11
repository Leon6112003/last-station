class_name OracleController
extends Node
## Runs one ORACLE question at a time: clean it, retrieve manual excerpts,
## optionally ask the local model, and emit what the player should see.
##
## It has no reference to GameManager. The only game information it can read is
## the sanitized snapshot returned by `snapshot_provider`, and the only thing it
## produces is display text (the `answered` signal).

signal answered(result: Dictionary)
signal busy_changed(is_busy: bool)

var records: Array = []
## Callable that returns a Dictionary of the allowed snapshot values.
var snapshot_provider: Callable = Callable()
## Anything with `ask(messages) -> bool` and a `reply(ok, text)` signal.
## null means "no model": every answer is the offline fallback.
var client: Node = null
var busy: bool = false

var _pending_excerpts: Array = []
var _pending_question: String = ""
var _pending_grounding: String = ""
var _pending_shown: String = ""


func set_client(new_client: Node) -> void:
	if client != null and client.reply.is_connected(_on_reply):
		client.reply.disconnect(_on_reply)
	client = new_client
	if client != null:
		client.reply.connect(_on_reply)


## Starts the model in the background the first time the panel opens.
func warm_up() -> void:
	if client != null and client.has_method("warm_up"):
		client.warm_up()


## Returns true if the question was accepted. Ignored while another is running.
func ask(raw_question: String) -> bool:
	if busy:
		return false
	var question := OracleLogic.sanitize_question(raw_question)
	if question.is_empty():
		return false

	var excerpts := KnowledgeRetriever.retrieve(question, records)
	if OracleLogic.is_rule_question(excerpts):
		# Rules, orders and numbers are answered exactly in code, never by the model.
		answered.emit(OracleLogic.compose_exact(question, excerpts))
		return true
	if excerpts.is_empty() or client == null:
		_finish(excerpts, "", question)
		return true

	var snapshot := {}
	if snapshot_provider.is_valid():
		snapshot = snapshot_provider.call()
	# The model only sees the sentences that answer the question, and its answer
	# may only use numbers that were in what it was shown.
	var shown := OracleLogic.prompt_excerpts(question, excerpts)
	var messages := OracleLogic.build_messages(question, shown, snapshot)

	var shown_text := ""
	for entry in shown:
		shown_text += " " + entry["text"]
	_pending_shown = shown_text
	_pending_grounding = question + " " + JSON.stringify(OracleLogic.sanitize_snapshot(snapshot)) + shown_text

	_pending_excerpts = excerpts
	_pending_question = question
	_set_busy(true)
	if not client.ask(messages):
		_set_busy(false)
		_finish(excerpts, "", question)
	return true


func _on_reply(ok: bool, text: String) -> void:
	if not busy:
		return
	_set_busy(false)
	var usable := (ok and OracleLogic.is_grounded(text, _pending_grounding, _pending_question)
		and OracleLogic.covers_protocols(text, _pending_shown))
	_finish(_pending_excerpts, text if usable else "", _pending_question)


func _finish(excerpts: Array, model_text: String, question: String) -> void:
	_pending_excerpts = []
	_pending_question = ""
	_pending_grounding = ""
	_pending_shown = ""
	answered.emit(OracleLogic.compose_answer(excerpts, model_text, question))


func _set_busy(value: bool) -> void:
	busy = value
	busy_changed.emit(value)
