class_name QuestionManager extends Node

# Core Data
var question_indices: Dictionary = {}  # {q_num: {period_key: String, index: int}}
var wrong_questions: Array[int] = []
var loaded_periods: Array[String] = []

# Period Storage (lazy-loaded)
var periods := {
	"y1_t1": [], "y1_t2": [], "y2_t1": [], "y2_t2": [],
	"y3_t1": [], "y3_t2": [], "y4_t1": [], "y4_t2": []
}

# Advanced Indexing
var period_indices := {} # {period_key: Array[int]} - questions by period
var subject_indices := {} # {period_key: {subject: Array[int]}} - questions by period and subject

# Configs
var progress_config := ConfigFile.new()
var save_dirty := false
var is_saving := false

# Signals
signal question_answered(q_num: int, correct: bool)
signal loading_period(period_key: String)
signal period_loaded(period_key: String)

const PROGRESS_PATH = "user://questions_progress.cfg"

const PERIOD_PATHS := {
	"y1_t1": "res://questions/y1_t1.json",
	"y1_t2": "res://questions/y1_t2.json",
	"y2_t1": "res://questions/y2_t1.json",
	"y2_t2": "res://questions/y2_t2.json",
	"y3_t1": "res://questions/y3_t1.json",
	"y3_t2": "res://questions/y3_t2.json",
	"y4_t1": "res://questions/y4_t1.json",
	"y4_t2": "res://questions/y4_t2.json"
}

#__________________FUNCTIONS____________________
func _ready() -> void:
	# Initialize the indices
	for period_key in periods.keys():
		period_indices[period_key] = []
		subject_indices[period_key] = {}
	
	load_progress()
	setup_auto_save()

func setup_auto_save() -> void:
	get_tree().root.tree_exiting.connect(save_progress_sync)
	var timer := Timer.new()
	timer.wait_time = 30
	timer.autostart = true
	timer.timeout.connect(save_progress)
	add_child(timer)

func load_period(period_key: String) -> bool:
	if periods[period_key].size() > 0:
		return true  # Already loaded
	
	if loaded_periods.has(period_key):
		return true
		
	emit_signal("loading_period", period_key)
	
	var cfg_path := "user://%s.cfg" % period_key
	var cfg := ConfigFile.new()
	
	# Try config first
	if cfg.load(cfg_path) == OK:
		for section in cfg.get_sections():
			var q_num := int(section)
			var subject = cfg.get_value(section, "subject", "general")
			
			periods[period_key].append(QS.new({
				"question": cfg.get_value(section, "question", ""),
				"right_answer": cfg.get_value(section, "right_answer", ""),
				"wrong_answers": cfg.get_value(section, "wrong_answers", []),
				"tier": cfg.get_value(section, "tier", 1),
				"subject": subject,
				"period": period_key
			}))
			question_indices[q_num] = {"period_key": period_key, "index": periods[period_key].size() - 1}
			
			# Add to indices
			_index_question(q_num, period_key, subject)
		
		loaded_periods.append(period_key)
		emit_signal("period_loaded", period_key)
		return true
	
	# Load from JSON
	if not FileAccess.file_exists(PERIOD_PATHS[period_key]):
		push_error("Missing period file: ", period_key)
		return false
		
	var file := FileAccess.open(PERIOD_PATHS[period_key], FileAccess.READ)
	if !file:
		push_error("Failed to open period file: ", period_key)
		return false
	
	var json_text := file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("JSON parsing error: ", json.get_error_message(), " at line ", json.get_error_line())
		return false
		
	var json_data = json.get_data()
	if typeof(json_data) != TYPE_DICTIONARY:
		push_error("Invalid JSON structure in: ", period_key)
		return false
	
	# Process and save config
	var new_cfg := ConfigFile.new()
	for q_num_str in json_data:
		var q_num := int(q_num_str)
		var data: Dictionary = json_data[q_num_str]
		data["period"] = period_key
		
		var subject = data.get("subject", "general")
		
		periods[period_key].append(QS.new(data))
		question_indices[q_num] = {"period_key": period_key, "index": periods[period_key].size() - 1}
		
		# Add to indices
		_index_question(q_num, period_key, subject)
		
		for key in data:
			new_cfg.set_value(q_num_str, key, data[key])
	
	var save_result = new_cfg.save(cfg_path)
	if save_result != OK:
		push_warning("Failed to save config: ", period_key, " Error: ", save_result)
	
	loaded_periods.append(period_key)
	emit_signal("period_loaded", period_key)
	return true

func _index_question(q_num: int, period_key: String, subject: String) -> void:
	# Add to period index
	if !period_indices.has(period_key):
		period_indices[period_key] = []
	period_indices[period_key].append(q_num)
	
	# Add to subject index
	if !subject_indices.has(period_key):
		subject_indices[period_key] = {}
	if !subject_indices[period_key].has(subject):
		subject_indices[period_key][subject] = []
	subject_indices[period_key][subject].append(q_num)

func get_question(number: int) -> QS:
	var info: Dictionary = question_indices.get(number, {})
	if info.is_empty():
		return null
		
	if !load_period(info.period_key):
		return null
		
	return periods[info.period_key][info.index]

func load_progress() -> void:
	if progress_config.load(PROGRESS_PATH) != OK:
		return
	
	# Preload question indices from progress file
	for section in progress_config.get_sections():
		var q_num := int(section)
		var period_key = progress_config.get_value(section, "period", "")
		if period_key.is_empty():
			continue
			
		if !periods.has(period_key):
			push_warning("Unknown period key in progress: ", period_key)
			continue
			
		# Create placeholder for the question index
		if !question_indices.has(q_num):
			# We'll fill in the index when the period is actually loaded
			question_indices[q_num] = {"period_key": period_key, "index": -1}

func apply_progress_data() -> void:
	# This should be called after periods are loaded
	for section in progress_config.get_sections():
		var q_num := int(section)
		var qs := get_question(q_num)
		if !qs:
			continue
		
		qs.answered_counter = progress_config.get_value(section, "answered", 0)
		qs.wrong_answer_counter = progress_config.get_value(section, "wrong", 0)
		qs.interval = progress_config.get_value(section, "interval", 0)
		qs.ease = progress_config.get_value(section, "ease", 2.5)
		qs.due_date = progress_config.get_value(section, "due_date", 0)
		qs.correct_streak = progress_config.get_value(section, "correct_streak", 0)

func answer_question(q_num: int, answer: String) -> bool:
	var qs := get_question(q_num)
	if !qs:
		return false
	
	var now := Time.get_unix_time_from_system()
	var correct := answer == qs.right_answer
	
	if correct:
		qs.answered_counter += 1
		qs.correct_streak += 1
		match qs.correct_streak:
			1: qs.interval = 1
			2: qs.interval = 6
			_: qs.interval = ceili(qs.interval * qs.ease)
		qs.ease = maxf(qs.ease + 0.1, 1.3)
	else:
		_handle_wrong_answer(q_num)
		qs.wrong_answer_counter += 1
		qs.correct_streak = 0
		qs.interval = 1
		qs.ease = maxf(qs.ease - 0.2, 1.3)
	
	qs.due_date = now + (qs.interval * 86400)
	update_progress(q_num, qs)
	emit_signal("question_answered", q_num, correct)
	return correct

func update_progress(q_num: int, qs: QS) -> void:
	progress_config.set_value(str(q_num), "answered", qs.answered_counter)
	progress_config.set_value(str(q_num), "wrong", qs.wrong_answer_counter)
	progress_config.set_value(str(q_num), "interval", qs.interval)
	progress_config.set_value(str(q_num), "ease", qs.ease)
	progress_config.set_value(str(q_num), "due_date", qs.due_date)
	progress_config.set_value(str(q_num), "correct_streak", qs.correct_streak)
	progress_config.set_value(str(q_num), "period", qs.period)
	save_dirty = true

func save_progress() -> void:
	if is_saving or !save_dirty:
		return
		
	is_saving = true
	
	var thread = Thread.new()
	if thread.start(save_progress_thread.bind(progress_config.duplicate(), PROGRESS_PATH)) != OK:
		push_error("Could not start thread")
		is_saving = false
		return
		
	thread.wait_to_finish()
	save_dirty = false
	is_saving = false

func save_progress_thread(cfg: ConfigFile, path: String) -> void:
	cfg.save(path)

func save_progress_sync() -> void:
	if save_dirty:
		progress_config.save(PROGRESS_PATH)
		save_dirty = false

func _handle_wrong_answer(q_num: int) -> void:
	var idx := wrong_questions.find(q_num)
	if idx != -1:
		wrong_questions.remove_at(idx)
	wrong_questions.push_front(q_num)

# Random question methods with O(1) retrieval time
func get_random_questions_from_period(period_key: String, count: int) -> Array[int]:
	# Ensure period is loaded
	if !load_period(period_key):
		return []
	
	var result: Array[int] = []
	if period_indices[period_key].size() == 0:
		return result
		
	# Create a shuffled copy of the period questions
	var available = period_indices[period_key].duplicate()
	available.shuffle()
	
	# Take up to 'count' questions
	var to_take = min(count, available.size())
	for i in range(to_take):
		result.append(available[i])
		
	return result

func get_random_questions_by_subject(period_key: String, subject: String, count: int) -> Array[int]:
	# Ensure period is loaded
	if !load_period(period_key):
		return []
	
	var result: Array[int] = []
	
	# Check if subject exists in this period
	if !subject_indices.has(period_key) or !subject_indices[period_key].has(subject):
		return result
		
	if subject_indices[period_key][subject].size() == 0:
		return result
		
	# Create a shuffled copy of the subject questions
	var available = subject_indices[period_key][subject].duplicate()
	available.shuffle()
	
	# Take up to 'count' questions
	var to_take = min(count, available.size())
	for i in range(to_take):
		result.append(available[i])
		
	return result
	
func get_recent_wrong_questions(period_key: String, subject: String, count: int) -> Array[int]:
	# Ensure period is loaded
	if !load_period(period_key):
		return []
	
	var result: Array[int] = []
	
	# First check if we have questions for this period/subject combination
	if !subject_indices.has(period_key) or !subject_indices[period_key].has(subject):
		return result
	
	# Create a set of valid question numbers for fast lookups
	var valid_questions = {}
	for q_num in subject_indices[period_key][subject]:
		valid_questions[q_num] = true
	
	# Go through wrong questions and filter by our criteria
	for q_num in wrong_questions:
		# Check if this question belongs to our target period and subject
		if valid_questions.has(q_num):
			result.append(q_num)
			# Stop once we have enough questions
			if result.size() >= count:
				break
	
	return result

# Helper function to get all available subjects in a period
func get_subjects_in_period(period_key: String) -> Array:
	if !load_period(period_key):
		return []
		
	if !subject_indices.has(period_key):
		return []
		
	return subject_indices[period_key].keys()
