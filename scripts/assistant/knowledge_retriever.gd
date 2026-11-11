class_name KnowledgeRetriever
extends RefCounted
## Deterministic keyword retrieval over the manuals (no embeddings, no server).
##
## 1. Lowercase the question, split into words, drop punctuation and stop words.
## 2. Score every record: +3 for each question word found in its title or
##    keywords, +1 for each question word found in its text.
## 3. Sort by score (highest first), ties broken by record id, keep the top 3
##    with a positive score, and cut each text to 450 characters.
## Words are lightly normalised (a trailing "s" is dropped) so "valves" matches "valve".

const MAX_RESULTS := 3
const MAX_EXCERPT := 450

const STOP_WORDS := [
	"a", "an", "the", "is", "are", "was", "were", "be", "been", "to", "of", "in", "on", "at",
	"for", "and", "or", "do", "does", "did", "i", "me", "my", "you", "your", "it", "its",
	"this", "that", "these", "those", "what", "how", "can", "could", "should", "would",
	"with", "by", "from", "as", "about", "there", "if", "then", "so", "we", "us", "please",
	"tell", "which", "when", "where", "who", "why", "will", "have", "has", "get",
]


## Returns up to MAX_RESULTS entries of {id, title, text, score}, best first.
## Returns an empty array when nothing matches.
static func retrieve(question: String, records: Array, max_results: int = MAX_RESULTS) -> Array:
	var tokens := tokenize(question)
	if tokens.is_empty():
		return []

	var scored: Array = []
	for record in records:
		var title_and_keywords := {}
		for word in tokenize(record["title"]):
			title_and_keywords[word] = true
		for keyword in record["keywords"]:
			for word in tokenize(str(keyword)):
				title_and_keywords[word] = true
		var body := {}
		for word in tokenize(record["text"], false):
			body[word] = true

		var score := 0
		for token in tokens:
			if title_and_keywords.has(token):
				score += 3
			if body.has(token):
				score += 1
		if score > 0:
			scored.append({
				"id": record["id"],
				"title": record["title"],
				"text": excerpt(record["text"]),
				"score": score,
			})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return String(a["id"]) < String(b["id"]))
	return scored.slice(0, max_results)


## Lowercase words with punctuation removed. Stop words are removed from
## questions; pass remove_stop_words = false when indexing record text.
static func tokenize(text: String, remove_stop_words: bool = true) -> Array[String]:
	var cleaned := ""
	for character in text.to_lower():
		cleaned += character if _is_word_character(character) else " "
	var words: Array[String] = []
	for raw in cleaned.split(" ", false):
		var word := _normalize(raw)
		if word.is_empty():
			continue
		if remove_stop_words and STOP_WORDS.has(word):
			continue
		words.append(word)
	return words


static func excerpt(text: String) -> String:
	if text.length() <= MAX_EXCERPT:
		return text
	return text.substr(0, MAX_EXCERPT - 3).strip_edges() + "..."


static func _is_word_character(character: String) -> bool:
	var code := character.unicode_at(0)
	return (code >= 97 and code <= 122) or (code >= 48 and code <= 57)


static func _normalize(word: String) -> String:
	if word.length() > 3 and word.ends_with("s") and not word.ends_with("ss"):
		return word.left(word.length() - 1)
	return word
