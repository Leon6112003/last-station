class_name KnowledgeBase
extends RefCounted
## Loads the developer-written manuals from res://data/game_knowledge.json.
## Each record is {id, title, text, keywords}. The Manuals panel shows them,
## and the ORACLE retriever (Milestone 4) searches them.

const DEFAULT_PATH := "res://data/game_knowledge.json"
const MAX_TEXT_LENGTH := 450


## Returns the valid records in file order. Invalid entries are skipped with a
## warning, and a missing or unreadable file gives an empty list (never a crash).
static func load_records(path: String = DEFAULT_PATH) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("Knowledge base not found: %s" % path)
		return []
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_warning("Knowledge base is not a JSON array: %s" % path)
		return []

	var records: Array = []
	for entry in parsed:
		if is_valid_record(entry):
			records.append(entry)
		else:
			push_warning("Skipping invalid knowledge record: %s" % str(entry))
	return records


static func is_valid_record(entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	var record: Dictionary = entry
	for key in ["id", "title", "text"]:
		if typeof(record.get(key)) != TYPE_STRING or (record[key] as String).is_empty():
			return false
	return typeof(record.get("keywords")) == TYPE_ARRAY
