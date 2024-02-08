extends Node

var player_nickname: String = ["Aang", "Katara", "Zuko", "Toph", "Azula", "Sokka", "Iroh", "Appa", "Ozai"].pick_random()

@onready var get_nearby_scores_btn = %GetNearbyScoresButton
@onready var get_player_scores_btn = %GetCurrentPlayerScoresButton
@onready var id_line_edit := %IdLineEdit
@onready var leaderboard_ui := %LeaderboardUI
@onready var status_label := %StatusLabel
@onready var vbox := %VBoxContainer

func _ready() -> void:
	status_label.text = ""
	if not get_tree().root.has_node("PlayerAccounts"):
		status_label.text = "PlayerAccounts plugin must be installed to use Leaderboards. See documentation."
	else:
		if PlayerAccounts.is_logged_in():
			status_label.text = "Player is logged in."
			get_player_scores_btn.disabled = false
			get_nearby_scores_btn.disabled = false
		else:
			status_label.text = "Player is not logged in."


func _on_id_line_edit_text_changed(new_text: String) -> void:
	leaderboard_ui.leaderboard_id = new_text


func _on_post_score_button_pressed() -> void:
	status_label.text = "Posting score..."
	if not ProjectSettings.has_setting("quiver/general/auth_token"):
		status_label.text = "Auth token not set"
		return
	if not id_line_edit.text:
		status_label.text = "Please set a valid leaderboard ID"
		return
	var success := await Leaderboards.post_guest_score(id_line_edit.text, randi_range(1, 1000), player_nickname)
	await leaderboard_ui.refresh_scores()
	if success:
		status_label.text = "Successfully posted a score."
	else:
		status_label.text = "Failed to post score."
	get_player_scores_btn.disabled = false
	get_nearby_scores_btn.disabled = false


func _on_get_scores_button_pressed() -> void:
	leaderboard_ui.scores_label.text = "All Scores"
	leaderboard_ui.score_filter = Leaderboards.ScoreFilter.ALL
	status_label.text = "Fetching all scores..."
	if not ProjectSettings.has_setting("quiver/general/auth_token"):
		status_label.text = "Auth token not set"
		return
	if not id_line_edit.text:
		status_label.text = "Please set a valid leaderboard ID"
		return
	await leaderboard_ui.refresh_scores()
	status_label.text = "Successfully fetched scores."


func _on_get_scores_current_player_button_pressed() -> void:
	leaderboard_ui.scores_label.text = "Current Player's Scores"
	leaderboard_ui.score_filter = Leaderboards.ScoreFilter.PLAYER
	status_label.text = "Fetching scores for current player..."
	if not ProjectSettings.has_setting("quiver/general/auth_token"):
		status_label.text = "Auth token not set"
		return
	if not id_line_edit.text:
		status_label.text = "Please set a valid leaderboard ID"
		return
	await leaderboard_ui.refresh_scores()
	status_label.text = "Successfully fetched player scores."


func _on_get_nearby_scores_button_pressed() -> void:
	leaderboard_ui.scores_label.text = "Nearby Scores"
	leaderboard_ui.score_filter = Leaderboards.ScoreFilter.NEARBY
	status_label.text = "Fetching nearby scores..."
	if not ProjectSettings.has_setting("quiver/general/auth_token"):
		status_label.text = "Auth token not set"
		return
	if not id_line_edit.text:
		status_label.text = "Please set a valid leaderboard ID"
		return
	await leaderboard_ui.refresh_scores()
	status_label.text = "Successfully fetched nearby scores."


func _on_quit_button_pressed() -> void:
	PlayerAccounts.logout()
	get_tree().quit()


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		PlayerAccounts.logout()
		get_tree().quit()
