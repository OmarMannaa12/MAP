extends Node

var questions := {}  # {int: QS}

func _ready():
	var file = FileAccess.open("res://questions.txt", FileAccess.READ)
	if not file:
		push_error("Failed to open questions file")
		return

	# Read entire file content at once for optimal performance
	var content := file.get_as_text()
	file.close()

	# Regex to extract question blocks and numbers
	var block_regex := RegEx.new()
	block_regex.compile("<(\\d+)>(.*?)<\/\\1>", RegEx.MULTILINE | RegEx.DOTALL)
	
	for match_result in block_regex.search_all(content):
		var q_num := match_result.get_string(1).to_int()
		var q_content := match_result.get_string(2).strip_edges()
		
		# Create and initialize question object
		var qs := QS.new()
		qs.init(q_content)
		questions[q_num] = qs

func get_question(number: int) -> QS:
	return questions.get(number)
