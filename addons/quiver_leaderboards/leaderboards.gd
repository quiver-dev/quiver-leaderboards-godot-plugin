extends Node
## Handles sending scores to Quiver Leaderboards (https://quiver.dev/leaderboards/).
## Requires installation of the Quiver Player Accounts plugin.
##
## This class handles populating leaderboards, which can be configured on the Quiver website.
## Leaderboards can have different update strategies:
## * All scores: Records all posted scores
## * Best score: Only record each player's best score
## * Latest score: Only record each player's latest score
## * Cumulative score: Record the sum of each player's scores
##
## If a score fails to post, this class can be configured to handle retries.
## If the game is exited, this class will handle saving scores to disk for a later retry.

enum ScoreFilter {ALL, PLAYER, NEARBY}
enum NearbyAnchor {BEST, LATEST}

## This controls the maximum size of the request queue that is saved to disk
## in the situation the scores weren't able to be successfully posted.
## In pathological cases, we drop the lowest scores if the queue grows too big.
const MAX_FAILED_QUEUE_SIZE := 20

const MAX_RETRY_TIME_SECONDS := 60

## The file to store queue scores that weren't able to be sent due to network or server issues
const FAILED_QUEUE_FILE_NAME := "user://leaderboards_queue"

## The server host
const SERVER_PATH := "https://quiver.dev"

## URLs for posting and retrieving scores
const POST_SCORE_PATH := "/leaderboards/%s/scores/post/"
const GET_SCORES_PATH := "/leaderboards/%s/scores/"
const GET_SCORES_WITH_PLAYER_PATH = "/leaderboards/%s/scores-with-player/"
const GET_PLAYER_SCORES_PATH := "/leaderboards/%s/scores/player/"
const GET_NEARBY_SCORES_PATH := "/leaderboards/%s/scores/nearby/"
const MIN_UNIX_TIME := 0
const MAX_UNIX_TIME := 2147483647.0

var auth_token := ProjectSettings.get_setting("quiver/general/auth_token", "")
var _failed_queue: Array[Dictionary] = []
var _failed_queue_file: FileAccess = null
var _http_request_busy: = false
var _retry_time := 2.0

@onready var http_request := $HTTPRequest
@onready var retry_timer := $RetryTimer


func _ready() -> void:
	if not get_tree().root.has_node("PlayerAccounts"):
		printerr("[Quiver Leaderboards] PlayerAccounts plugin must be installed to use Leaderboards. See documentation for details.")

	await PlayerAccounts.ready

	_load_failed_queue_from_disk()
	if not _failed_queue.is_empty():
		_process_failed_queue()


## Posts a score from a guest player to the leaderboard with the given leaderboard ID.
## Note that if the player isn't logged in, this plugin will automatically create a guest account for them.
##
## leaderboard_id: string. Corresponds to the a leaderboard created on the Quiver website.
## You can get the ID from the Leaderboards dashboard.
## score: float. Expects a float, but it's fine to use integers as well.
## nickname: string (optional). A nickname to associate with this score.
## metadata: Dictionary (optional). A dictionary with additional information associated with this score.
## timestamp: float (optional). If provided, uses this as the score's timestamp, otherwise uses the current time
## automatically_retry: bool (default true). If true, the client will automatically handle retrying score posting
## in the case of network or server failure.
##
## Returns a boolean indicating whether this operation completed successfully or not.
## If this operation failed and automatically_retry is true, you do not need to post it again.
## The built-in retry mechanism will try again until the operation succeeeds, even across game restarts.
func post_guest_score(leaderboard_id: String, score: float, nickname := "", metadata := {}, timestamp := 0.0, automatically_retry := true) -> bool:
	var retry := automatically_retry

	var success := true

	if success and nickname.length() > 15:
		success = false
		printerr("Couldn't post score because nickname is greater than 15 characters")
		# Don't retry since this will never work
		retry = false

	if success and not PlayerAccounts.is_logged_in():
		success = await PlayerAccounts.register_guest()
		if not success:
			printerr("Couldn't register guest account")

	if success and _http_request_busy:
		printerr("Couldn't post score because request is in progress")
		success = false

	if success:
		_http_request_busy = true
		var url = SERVER_PATH + (POST_SCORE_PATH % leaderboard_id)
		if timestamp == 0.0:
			timestamp = Time.get_unix_time_from_system()
		var error = http_request.request(
			url,
			["Authorization: Token " + PlayerAccounts.player_token],
			HTTPClient.METHOD_POST,
			JSON.stringify({
				"score": float(score),
				"nickname": nickname,
				"timestamp": timestamp,
				"metadata": metadata,
				"checksum": str(int(score) + int(timestamp)).md5_text()
			})
		)
		if error != OK:
			printerr("[Quiver Leaderboards] There was an error posting a score.")
			success = false
		else:
			var response = await http_request.request_completed
			var response_code = response[1]
			if response_code >= 500:
				printerr("[Quiver Leaderboards] There was an error posting a score.")
				success = false
			# A 4xx error means retrying this request is futile, so we should drop it,
			# regardless of the automatically_retry option.
			elif response_code >= 400:
				printerr("[Quiver Leaderboards] There was an irrecoverable error posting a score.")
				retry = false
				success = false
		_http_request_busy = false

	if not success and retry:
		_handle_failed_post("guest", leaderboard_id, float(score), nickname, metadata, timestamp)

	return success


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
##     "is_current_player": A bool. Returns true if the current player is logged in and this score belongs
##        to that player.
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
func get_scores(leaderboard_id: String, offset := 0, limit := 10, start_time := MIN_UNIX_TIME, end_time := MAX_UNIX_TIME) -> Dictionary:
	if not _validate_score_params(offset, limit):
		return {"scores": [], "has_more_scores": false, "error": "Error validating parameters"}
	var query_string := "?offset=%d&limit=%d&start_time=%f&end_time=%f" % [offset, limit, start_time, end_time]
	var path_to_use := GET_SCORES_PATH
	var token = auth_token
	# If we have a logged in player, we use a separate URL and player's auth token
	# to fetch results with
	if PlayerAccounts.player_token:
		path_to_use = GET_SCORES_WITH_PLAYER_PATH
		token = PlayerAccounts.player_token
	return await _get_scores_base(leaderboard_id, token, path_to_use, query_string)


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
func get_player_scores(leaderboard_id: String, offset := 0, limit := 10, start_time := MIN_UNIX_TIME, end_time := MAX_UNIX_TIME) -> Dictionary:
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
func get_nearby_scores(leaderboard_id: String, nearby_count := 5, anchor := NearbyAnchor.BEST, start_time := MIN_UNIX_TIME, end_time := MAX_UNIX_TIME) -> Dictionary:
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


func _get_scores_base(leaderboard_id: String, token: String, path: String, query_string := ""):
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


func _load_failed_queue_from_disk():
	var f = FileAccess.open(FAILED_QUEUE_FILE_NAME, FileAccess.READ)
	if f:
		while true:
			var line := f.get_line()
			if not line:
				break
			var failed_score = JSON.parse_string(line)
			_failed_queue.append(failed_score)


func _process_failed_queue():
	if not _failed_queue.is_empty():
		var score_to_retry = _failed_queue.back()
		var success := await post_guest_score(
			score_to_retry["leaderboard_id"],
			score_to_retry["score"],
			score_to_retry["nickname"],
			score_to_retry["metadata"],
			score_to_retry["timestamp"],
			false
		)
		# If we fail to post the score again, let's exponentially back off retrying
		if not success:
			_retry_time = min(_retry_time * 2.0, MAX_RETRY_TIME_SECONDS)
			retry_timer.start(_retry_time)
		# Otherwise, we process the next item or clean up all the queue file
		# if we've finished processing the queue
		else:
			_retry_time = 2.0
			_failed_queue.pop_back()
			if _failed_queue.is_empty():
				if _failed_queue_file:
					_failed_queue_file.close()
				DirAccess.remove_absolute(FAILED_QUEUE_FILE_NAME)
			else:
				retry_timer.start(_retry_time)


## Sorts the failed queue with the worst scores in the beginning of the queue
## and the best at the end.
func _failed_queue_sort(a, b):
	if a["score"] < b["score"]:
		return true
	elif a["score"] > b["score"]:
		return false
	else:
		if a["timestamp"] < b["timestamp"]:
			return false
		else:
			return true


func _handle_failed_post(type: String, leaderboard_id: String, score: float, nickname: String, metadata: Dictionary, timestamp: float):
	# If the score fails to post, we immediately queue it up for retry and save it to disk.
	# The reason we do both is we don't want to risk losing score data if the game unexpectedly quits.
	var failed_score := {"type": type, "leaderboard_id": leaderboard_id, "score": score, "nickname": nickname, "metadata": metadata, "timestamp": timestamp}
	_failed_queue.append(failed_score)

	# If we exceed our maximum queue size, we'll drop the lowest score and
	# rewrite the queue to the file.
	if _failed_queue.size() > MAX_FAILED_QUEUE_SIZE:
		# Sort with the worst scores first
		_failed_queue.sort_custom(_failed_queue_sort)
		# Drop the worst score
		var dropped_score = _failed_queue.pop_front()
		# Rewrite the queue file
		if _failed_queue_file:
			_failed_queue_file.close()
		_failed_queue_file = FileAccess.open(FAILED_QUEUE_FILE_NAME, FileAccess.WRITE)
		if _failed_queue_file:
			for score_data in _failed_queue:
				_failed_queue_file.store_line(JSON.stringify(score_data))
			_failed_queue_file.close()
		else:
			printerr("[Quiver Leaderboards] Failed to save failed request to disk.")
	else:
		if not _failed_queue_file:
			if FileAccess.file_exists(FAILED_QUEUE_FILE_NAME):
				_failed_queue_file = FileAccess.open(FAILED_QUEUE_FILE_NAME, FileAccess.READ_WRITE)
				_failed_queue_file.seek_end()
			else:
				_failed_queue_file = FileAccess.open(FAILED_QUEUE_FILE_NAME, FileAccess.WRITE)
		if _failed_queue_file:
			_failed_queue_file.store_line(JSON.stringify(failed_score))
			_failed_queue_file.flush()
		else:
			printerr("[Quiver Leaderboards] Failed to save failed request to disk.")
	if retry_timer.is_stopped():
		_process_failed_queue()


func _on_retry_timer_timeout() -> void:
	_process_failed_queue()
