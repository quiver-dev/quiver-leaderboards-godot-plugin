class_name LeaderboardUI
extends Control

## The Leaderboard ID can be found on the Quiver website
@export var leaderboard_id: String:
	set(id):
		leaderboard_id = id
		score_offset = 0
		#refresh_scores()
## All: Show all scores
## Player: Only current player's scores (requires player to be logged in)
## Nearby: Show scores close to current player's scores (requires player to be logged in)
@export var score_filter := Leaderboards.ScoreFilter.ALL:
	set(filter):
		score_filter = filter
		score_offset = 0
		#refresh_scores()
## The offset from the first high score
@export var score_offset := 0
## Fetch up to a maximum of this many scores.
@export_range(1, 50) var score_limit := 10
## Fetch this many scores below and this many scores above the player's score
## when using the nearby score filter.
@export_range(1, 25) var nearby_count := 5
## Sets whether scores are fetched near the player's best or latest score
## when using the nearby score filter.
## Only applicable when the leaderboard is using the "All scores" update strategy.
@export var nearby_anchor := Leaderboards.NearbyAnchor.BEST
## The color to highlight the current player's scores.
@export var current_player_highlight_color := Color("#005216")

@onready var next_button := %NextButton
@onready var prev_button := %PrevButton
@onready var score_list := %ScoreList
@onready var scores_label := %ScoresLabel
@onready var title_label := %TitleLabel


func _ready() -> void:
	score_list.set_column_expand_ratio(1, 3)
	var column_names := ["Rank", "Name", "Score"]
	for column_index in range(column_names.size()):
		var cname: String = column_names[column_index]
		score_list.set_column_title(column_index, cname)
		score_list.set_column_title_alignment(column_index, HORIZONTAL_ALIGNMENT_LEFT)
		column_index += 1
	if leaderboard_id:
		refresh_scores()


func refresh_scores():
	if not leaderboard_id:
		printerr("[Quiver Leaderboards] Scores couldn't be fetched since leaderboard ID not set in Leaderboard UI.")
		return

	prev_button.disabled = score_offset == 0
	next_button.disabled = true

	score_list.clear()
	var root: TreeItem = score_list.create_item()
	var score_data: Dictionary
	if score_filter == Leaderboards.ScoreFilter.ALL:
		score_data = await Leaderboards.get_scores(leaderboard_id, score_offset, score_limit)
	elif score_filter == Leaderboards.ScoreFilter.PLAYER:
		score_data = await Leaderboards.get_player_scores(leaderboard_id, score_offset, score_limit)
	elif score_filter == Leaderboards.ScoreFilter.NEARBY:
		score_data = await Leaderboards.get_nearby_scores(leaderboard_id, nearby_count, nearby_anchor)
	if score_data["scores"].size() > 0:
		for score in score_data["scores"]:
			var row: TreeItem = score_list.create_item(root)
			row.set_text(0, str(score["rank"]))
			row.set_text(1, str(score["name"]))
			row.set_text(2, str(score["score"]))
			if score["is_current_player"]:
				for i in range(3):
					row.set_custom_bg_color(i, current_player_highlight_color)
	else:
		var row: TreeItem = score_list.create_item(root)
		if score_data["error"]:
			row.set_text(0, "There was an error fetching scores.")
		else:
			row.set_text(0, "No scores were found")

	next_button.disabled = not score_data["has_more_scores"]


func _on_prev_button_pressed() -> void:
	if score_offset > 0:
		score_offset = max(0, score_offset - score_limit)
		refresh_scores()


func _on_next_button_pressed() -> void:
	score_offset = score_offset + score_limit
	refresh_scores()
