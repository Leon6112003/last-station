extends SceneTree
## Uses the REAL Ollama client against 127.0.0.1:11434. With Ollama not running
## (the expected case here) the request must fail cleanly and ORACLE must fall
## back to the manuals. If Ollama IS running, the test reports that and checks
## the reply is still well-formed instead.
## Run:  godot --headless --path . -s res://tests/test_ollama_down.gd

var _failures: int = 0


func _initialize() -> void:
	var records := KnowledgeBase.load_records()
	var controller := OracleController.new()
	controller.records = records
	root.add_child(controller)
	var client := OllamaClient.new()
	root.add_child(client)
	controller.set_client(client)
	await process_frame

	var state := {"done": false, "result": {}}
	controller.answered.connect(func(r: Dictionary) -> void:
		state["done"] = true
		state["result"] = r)

	_check(controller.ask("How is my score calculated?"), "the question is accepted")
	_check(controller.busy, "the controller is busy while the request runs")

	for i in 600:  # up to 30 s (the client times out at 25 s)
		if state["done"]:
			break
		await create_timer(0.05).timeout
	_check(state["done"], "an answer arrived (no hang, no crash)")

	var result: Dictionary = state["result"]
	_check(not controller.busy, "the controller is free again")
	_check(not result.is_empty() and not result["sources"].is_empty(), "the manual excerpts are shown either way")
	if result.get("mode", "") == "basic":
		print("      Ollama is not reachable: ORACLE used Basic Manual Mode (expected).")
		_check(result["header"] == OracleLogic.HEADER_BASIC and str(result["answer"]).contains("(From the manual:"), "the fallback is labelled and answers from the best manual entry")
	else:
		print("      Ollama IS running: got a local answer: ", str(result["answer"]).left(120))
		_check(result["header"] == OracleLogic.HEADER_LOCAL and str(result["answer"]).length() <= OracleLogic.MAX_ANSWER, "the local answer is labelled and within the length limit")

	# A second question works after a failure.
	state["done"] = false
	_check(controller.ask("How do I retry?"), "a second question is accepted after the first")
	for i in 600:
		if state["done"]:
			break
		await create_timer(0.05).timeout
	_check(state["done"], "the second answer also arrived")

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
