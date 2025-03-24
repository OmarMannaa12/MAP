class_name q_set extends RefCounted

enum q_types {
	Choices,
	Writting,
	
}
var q: String 					#The question

var r_choice: String				#The right answer
var w_choices: Array[String]		#The wrong answer

var tier: int
var subject
var period: int

func init(input_str: String) -> void:
	var regex := RegEx.new()
	regex.compile("<(\\w+)>(.*?)<\\1>")  # Match tag-content pairs
	
	for match_result in regex.search_all(input_str):
		var tag := match_result.get_string(1).to_lower()
		var content := match_result.get_string(2).strip_edges()
		
		match tag:
			"q": q = content
			"r": r_choice = content
			"w": w_choices.append(content)
			"s": subject = content
			"p": period = int(content)
