extends Node
## Handles sending scores to Quiver Leaderboards (https://quiver.dev/leaderboards/).
## Requires installation of the Quiver Player Accounts plugin.
##
## This class handles populating leaderboards, which can be configured on the Quiver website.
## Leaderboards can have different update strategies:
## * All scores: Records all posted scores
## * Best score: Only record each player's best score
## * Latest score: Only record each player's latest score
## * Cumulative score: Record the cumulative (sum) of each player's scores
##
## If a score fails to post, this class will handle retries.
## If the game is exited, this class will handle saving scores to disk for a later retry.

enum ScoreFilter {ALL, PLAYER, NEARBY}
enum NearbyAnchor {BEST, LATEST}

## The server host
const SERVER_PATH := "https://quiver.dev"

## URLs for posting and retrieving scores
const POST_SCORE_PATH := "/leaderboards/%s/scores/post/"
const GET_SCORES_PATH := "/leaderboards/%s/scores/"
const GET_PLAYER_SCORES_PATH := "/leaderboards/%s/scores/player/"
const GET_NEARBY_SCORES_PATH := "/leaderboards/%s/scores/nearby/"
const MIN_UNIX_TIME := 0
const MAX_UNIX_TIME := 2147483647.0

var auth_token = ProjectSettings.get_setting("quiver/general/auth_token", "")
var _http_request_busy = false

@onready var http_request := $HTTPRequest


func _ready() -> void:
	if not get_tree().root.has_node("PlayerAccounts"):
		printerr("[Quiver Leaderboards] PlayerAccounts plugin must be installed to use Leaderboards. See documentation for details.")


## Posts a score from a guest player to the leaderboard with the given leaderboard ID.
## Note that if the player isn't logged in, this plugin will automatically create a guest account for them.
##
## leaderboard_id: string. Corresponds to the a leaderboard created on the Quiver website.
## You can get the ID from the Leaderboards dashboard.
## score: float. Expects a float, but it's fine to use integers as well.
## nickname: string (optional). A nickname to associate with this score.
## metadata: Dictionary (optional). A dictionary with additional information associated with this score.
##
## Returns a boolean indicating whether this operation completed successfully or not.
func post_guest_score(leaderboard_id: String, score: float, nickname: String = "", metadata: Dictionary = {}) -> bool:
	if not PlayerAccounts.is_logged_in():
		var success: bool = await PlayerAccounts.register_guest()
		if not success:
			return false

	if _http_request_busy:
		printerr("Couldn't post score because request is in progress")
		return false

	_http_request_busy = true
	var url = SERVER_PATH + (POST_SCORE_PATH % leaderboard_id)
	var error = http_request.request(
		url,
		["Authorization: Token " + PlayerAccounts.player_token],
		HTTPClient.METHOD_POST,
		JSON.stringify({
			"score": float(score),
			"nickname": nickname,
			"timestamp": Time.get_unix_time_from_system(),
			"metadata": metadata,
		})
	)
	if error != OK:
		_http_request_busy = false
		printerr("[Quiver Leaderboards] There was an error posting a score.")
		return false
	else:
		var response = await http_request.request_completed
		_http_request_busy = false
		var response_code = response[1]
		if response_code < 200 and response_code >= 300:
			printerr("[Quiver Leaderboards] There was an error posting a score.")
			return false
	return true


func post_score(leaderboard_id: String, score: float) -> bool:
	printerr("[Quiver Leaderboards] This isn't implemented yet!")
	return false


## Get scores at the given offset, with the number of scores returned determined by the limit.
##
## leaderboard_id: int. Corresponds to the a leaderboard created on the Quiver website.
## You can get the ID from the Leaderboards dashboard.
## The offset must be an integer zero or greater.
## The limit must be an integer between 1 and 50.
## The start and end times are floats that denote Unix timestamps in seconds and will
## restrict scores to this time period.
##
## Returns a dictionary, with keys "scores", "has_more_scores", and "error".
## "scores" contains an ordered array of dictionary with the score data at the given offset.
##   The score data contains the keys:
##     "name": A string. Can be blank if no nickname was provided when this score was posted.
##     "score": A float.
##     "rank": An int. The global rank of this score given this particular query and relative
##       to the time period, if any.
##     "timestamp": A float. The UNIX time in seconds when this score was posted.
##     "metadata": A dictionary. Includes any metadata that was attached to this score when it was posted.
## "has_more_scores" is a Boolean specifying whether there are more available scores to fetch.
## "error" is a string with an error message if present or empty otherwise
## Example return value:
## {
##   "scores: [
##     {"name": "Aang", "score": 500, "rank": 1, timestamp: 1706824170.389251, metadata: {}},
##     {"name": "Katara", "score": 300, "rank": 2, timestamp: 1706821234.123456, metadata: {}}
##   ],
##   "has_more_scores": false,
##   "error": ""
## }
func get_scores(leaderboard_id: String, offset: int = 0, limit: int = 10, start_time=MIN_UNIX_TIME, end_time=MAX_UNIX_TIME) -> Dictionary:
	if not _validate_score_params(offset, limit):
		return {"scores": [], "has_more_scores": false, "error": "Error validating parameters"}
	var query_string := "?offset=%d&limit=%d&start_time=%f&end_time=%f" % [offset, limit, start_time, end_time]
	return await _get_scores_base(leaderboard_id, auth_token, GET_SCORES_PATH, query_string)


## Get scores for the current guest player or logged in player.
## The number of scores returned is determined by the update strategy used by the leaderboard;
## Leaderboards using "All scores" update strategy can return zero, one, or multiple scores,
## whereas all other strategies will return an array empty array or an array with one score.
##
## leaderboard_id: int. Corresponds to the a leaderboard created on the Quiver website.
## You can get the ID from the Leaderboards dashboard.
## The offset must be an integer zero or greater.
## The limit must be an integer between 1 and 50.
## The start and end times are floats that denote Unix timestamps in seconds and will
## restrict scores to this time period.
##
## Return value is the same as get_scores()
func get_player_scores(leaderboard_id, offset=0, limit=10, start_time=MIN_UNIX_TIME, end_time=MAX_UNIX_TIME) -> Dictionary:
	if not _validate_score_params(offset, limit):
		return {"scores": [], "has_more_scores": false, "error": "Error validating parameters"}
	if not PlayerAccounts.player_token:
		return {"scores": [], "has_more_scores": false, "error": "No logged in player"}
	var query_string := "?offset=%d&limit=%d&start_time=%f&end_time=%f" % [offset, limit, start_time, end_time]
	return await _get_scores_base(leaderboard_id, PlayerAccounts.player_token, GET_PLAYER_SCORES_PATH, query_string)


## Get scores near the score of the current guest player or logged in player.
##
## leaderboard_id: int. Corresponds to the a leaderboard created on the Quiver website.
## You can get the ID from the Leaderboards dashboard.
## The nearby_count must be an integer between 1 and 25 and will return that number of scores
## above and below the current player's score.
## The anchor will determine which score to use as the reference score when using the
## "All scores" update strategy.
##    NearbyAnchor.BEST will fetch scores near the player's best score
##    NearbyAnchor.LATEST will fetch scores near the player's latest score
##    Note that this parameter doesn't have an effect when other strategies are used.
## The start and end times are floats that denote Unix timestamps in seconds and will
## restrict scores to this time period.
##
## Return value is the same as get_scores()
func get_nearby_scores(leaderboard_id, nearby_count=5, anchor=NearbyAnchor.BEST, start_time=MIN_UNIX_TIME, end_time=MAX_UNIX_TIME) -> Dictionary:
	if nearby_count <= 0 or nearby_count > 25:
		printerr("[Quiver Leaderboards] Nearby count must be between 1 and 25")
		return {"scores": [], "has_more_scores": false, "error": "Error validating parameters"}
	if not PlayerAccounts.player_token:
		return {"scores": [], "has_more_scores": false, "error": "No logged in player"}
	var anchor_string := "best"
	if anchor == NearbyAnchor.BEST:
		anchor_string = "best"
	elif anchor == NearbyAnchor.LATEST:
		anchor_string = "latest"
	var query_string := "?nearby_count=%d&anchor=%s&start_time=%f&end_time=%f" % [nearby_count, anchor_string, start_time, end_time]
	return await _get_scores_base(leaderboard_id, PlayerAccounts.player_token, GET_NEARBY_SCORES_PATH, query_string)


func _validate_score_params(offset: int, limit: int):
	if offset < 0:
		printerr("[Quiver Leaderboards] Offset must be a positive number")
		return false
	if limit <= 0 or limit > 50:
		printerr("[Quiver Leaderboards] The limit must be between 1 and 50.")
		return false
	return true


func _get_scores_base(leaderboard_id: String, token: String, path: String, query_string: String = ""):
	var scores := []
	var has_more_scores := false
	if not token:
		printerr("[Quiver Leaderboards] Can't fetch scores due to missing token")
		return {"scores": [], "has_more_scores": false, "error": "Missing token"}
	if _http_request_busy:
		printerr("Couldn't get scores because request is in progress")
		return {"scores": [], "has_more_scores": false, "error": "Fetch request already in progres"}

	_http_request_busy = true
	var url = SERVER_PATH + path % leaderboard_id + query_string
	var error = http_request.request(
		url,
		["Authorization: Token " + token],
		HTTPClient.METHOD_GET
	)
	var error_msg := ""
	if error != OK:
		printerr("[Quiver Leaderboards] There was an error fetching scores.")
		error_msg = "Request failed"
	else:
		var response = await http_request.request_completed
		var response_code = response[1]
		if response_code >= 200 and response_code <= 299:
			var body = response[3]
			var parsed_data = JSON.parse_string(body.get_string_from_utf8())
			if parsed_data is Dictionary:
				scores = parsed_data["scores"]
				if parsed_data["next_url"]:
					has_more_scores = true
			else:
				printerr("[Quiver Leaderboards] There was an error while parsing score data")
				error_msg = "Error parsing response"
		else:
			printerr("[Quiver Leaderboards] There was an error fetching scores.")
			error_msg = "Request failed, HTTP code %d" % response_code
	_http_request_busy = false
	return {"scores": scores, "has_more_scores": has_more_scores, "error": error_msg}
