class_name QS extends RefCounted
enum QuestionType {CHOICES, WRITING}

# Anki-like properties
var interval: int = 0  # Days between reviews
var ease: float = 2.5  # Easiness factor (default Anki value)
var due_date: int = 0  # Unix timestamp of next review
var correct_streak: int = 0  # Consecutive correct answers

# Existing properties
var question: String
var right_answer: String
var wrong_answers: Array[String]
var tier: int
var subject: String
var period: int
var answered_counter: int = 0
var wrong_answer_counter: int = 0

func _init(data: Dictionary):
	question = data.get("question", "") as String
	right_answer = data.get("right_answer", "") as String
	wrong_answers = data.get("wrong_answers", []) as Array[String]
	tier = int(data.get("tier", 1))
	subject = data.get("subject", "general") as String
	period = int(data.get("period", 0))
	
	# Initialize Anki-like properties from data if they exist
	interval = int(data.get("interval", 0))
	ease = float(data.get("ease", 2.5))
	due_date = int(data.get("due_date", 0))
	correct_streak = int(data.get("correct_streak", 0))
