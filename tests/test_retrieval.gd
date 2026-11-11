extends SceneTree
## Keyword retrieval over the manuals (REQUIREMENTS.md G3 / J1).
## Run:  godot --headless --path . -s res://tests/test_retrieval.gd

var _failures: int = 0


func _initialize() -> void:
	var records := KnowledgeBase.load_records()
	_check(records.size() >= 14, "the knowledge base loads")

	_top(records, "How do I fix the power breakers?", "power_order")
	_top(records, "What are the oxygen valve settings in night mode?", "oxygen_table")
	_top(records, "How is my score calculated?", "scoring")
	_top(records, "What frequency do I transmit on the comms tuner?", "comms_formula")
	_top(records, "How do I retry?", "retry_rules")
	_top(records, "How long do I have before the oxygen runs out?", "reserve_timer")
	_top(records, "what does a surge cost", "mistake_penalties")

	var results := KnowledgeRetriever.retrieve("power breakers valve oxygen score retry frequency", records)
	_check(results.size() <= 3, "at most 3 results are returned (got %d)" % results.size())

	var first := KnowledgeRetriever.retrieve("How do I fix the power breakers?", records)
	var second := KnowledgeRetriever.retrieve("How do I fix the power breakers?", records)
	_check(first == second, "results are stable for the same question")
	var scores_sorted := true
	for i in range(1, first.size()):
		if first[i - 1]["score"] < first[i]["score"]:
			scores_sorted = false
	_check(scores_sorted and first[0]["score"] > 0, "results are sorted best first with positive scores")

	_check(KnowledgeRetriever.retrieve("What is the weather today?", records).is_empty(), "an unrelated question returns nothing")
	_check(KnowledgeRetriever.retrieve("", records).is_empty(), "an empty question returns nothing")
	_check(KnowledgeRetriever.retrieve("the a an is of", records).is_empty(), "a question of only stop words returns nothing")

	_check(KnowledgeRetriever.tokenize("The VALVES, settings!") == ["valve", "setting"], "tokenize lowercases, strips punctuation and stop words, and singularises")
	_check(KnowledgeRetriever.tokenize("   ").is_empty(), "tokenize of whitespace is empty")

	var fake_records := [
		{"id": "b_second", "title": "Alpha", "text": "zebra", "keywords": ["zebra"]},
		{"id": "a_first", "title": "Beta", "text": "zebra", "keywords": ["zebra"]},
	]
	var tie := KnowledgeRetriever.retrieve("zebra", fake_records)
	_check(tie.size() == 2 and tie[0]["id"] == "a_first", "equal scores are ordered by id")

	var long_record := [{"id": "long", "title": "Long", "text": "word ".repeat(200), "keywords": ["word"]}]
	var long_result := KnowledgeRetriever.retrieve("word", long_record)
	_check(long_result[0]["text"].length() <= 450, "excerpts are cut to 450 characters (got %d)" % long_result[0]["text"].length())

	# Basic Manual Mode picks the sentences that answer the question.
	_answer_has(records, "power breakers restore mode protocol B", "Protocol B, RESTORE", "Protocol A, RESTORE")
	_answer_has(records, "power breakers shed mode protocol A", "Protocol A, SHED", "Protocol B, SHED")
	_answer_has(records, "oxygen valves night mode protocol B", "Protocol B, NIGHT: 40, 50, 60.", "Protocol A, NIGHT")
	_answer_has(records, "what are the oxygen valve settings for emergency in protocol A", "Protocol A, EMERGENCY: 70, 80, 90.", "Protocol B, EMERGENCY")
	_answer_has(records, "comms frequency with 3 lit beacons protocol B", "130 MHz", "160 MHz")
	# With no protocol named, never show only one protocol.
	var no_protocol := OracleLogic.compose_answer(KnowledgeRetriever.retrieve("how do I fix the power breakers", records), "", "how do I fix the power breakers")["answer"] as String
	_check(no_protocol.contains("Protocol A, RESTORE") and no_protocol.contains("Protocol B, RESTORE"), "no protocol named: both protocols are shown for the breakers")
	var night := OracleLogic.compose_answer(KnowledgeRetriever.retrieve("oxygen valves night mode", records), "", "oxygen valves night mode")["answer"] as String
	_check(night.contains("Protocol A, NIGHT") and night.contains("Protocol B, NIGHT") and not night.contains("DAY"), "no protocol named: NIGHT is shown for both protocols and nothing else")
	_check(OracleLogic.detect_protocol("What about Protocol B?") == "B" and OracleLogic.detect_protocol("protocolA please") == "A" and OracleLogic.detect_protocol("no such thing") == "", "protocol A or B is detected in a question")
	_top(records, "hello", "help_topics")
	_top(records, "help", "help_topics")
	_top(records, "I am stuck, where do I start?", "first_steps")
	_check(OracleLogic.select_sentences("anything", "One short sentence.") == "One short sentence.", "a short entry is returned whole")

	# The flip order is worked out when the player gives the ratings they read.
	var given := "B1 is 277 V, B2 is 480 V, B3 is 208 V, B4 is 400 V. Protocol B, restore mode. Which first?"
	var order_b := OracleLogic.compose_exact(given, KnowledgeRetriever.retrieve(given, records))["answer"] as String
	_check(order_b.contains("flip: B2 (480 V), then B4 (400 V), then B1 (277 V), then B3 (208 V)."), "protocol B restore with the given ratings: highest first (B2, B4, B1, B3)")
	var given_a := "protocol A restore mode: B1 277 V, B2 480 V, B3 208 V, B4 400 V"
	var order_a := OracleLogic.compose_exact(given_a, KnowledgeRetriever.retrieve(given_a, records))["answer"] as String
	_check(order_a.contains("flip: B3 (208 V), then B1 (277 V), then B4 (400 V), then B2 (480 V)."), "protocol A restore with the given ratings: lowest first (B3, B1, B4, B2)")
	var given_shed := "protocol A shed mode, B1 is 120 V and B2 is 240 V"
	var order_shed := OracleLogic.compose_exact(given_shed, KnowledgeRetriever.retrieve(given_shed, records))["answer"] as String
	_check(order_shed.contains("flip: B2 (240 V), then B1 (120 V)."), "protocol A shed with two ratings: highest first (B2, B1)")
	var no_ratings := OracleLogic.compose_exact("protocol B restore mode power breakers", KnowledgeRetriever.retrieve("protocol B restore mode power breakers", records))["answer"] as String
	_check(not no_ratings.contains("With the ratings you gave"), "no order is invented when no ratings were given")

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _answer_has(records: Array, question: String, wanted: String, unwanted: String) -> void:
	var results := KnowledgeRetriever.retrieve(question, records)
	var answer: String = OracleLogic.compose_answer(results, "", question)["answer"]
	_check(answer.contains(wanted) and not answer.contains(unwanted), "\"%s\" answers with '%s' and not '%s'" % [question, wanted, unwanted])


func _top(records: Array, question: String, expected_id: String) -> void:
	var results := KnowledgeRetriever.retrieve(question, records)
	var got: String = results[0]["id"] if not results.is_empty() else "(nothing)"
	_check(got == expected_id, "\"%s\" -> %s (got %s)" % [question, expected_id, got])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
