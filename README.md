
# Quiver Leaderboards
[Quiver Leaderboards](https://quiver.dev/leaderboards/) allows you to easily create global leaderboards for games made with the [Godot engine](https://godotengine.org).

## Features
* Create one or more leaderboards for each of your Godot games and integrate in just minutes.
* Choose from several update strategies for each leaderboard:
	* "All scores": Stores all scores from every player.
	* "Best score": Store each player's best score.
	* "Latest score": Store each player's latest score. Newer scores will overwrite previous ones.
	* "Cumulative score": Stores the sum of each player's scores. Individual scores are not retained.
* Use the customizable, built-in Godot UI component to display your leaderboard or build your own.
* Fetch scores based on time so you can do daily, weekly, or monthly leaderboards.
* Fetch nearby scores so your players get context on how they are doing relative to other player's with similar scores.
* Use our web dashboard to view and manage scores.

## Prerequisites
This plugin requires Godot 4.0 or later. It's been designed to work with GDScript. We'll add support for other languages in the future. This plugin also depends on the [Quiver Player Accounts plugin](https://github.com/quiver-dev/quiver-player-accounts-godot-plugin). You can find instructions to install it below.

## Installation

### Install the plugins
* This plugin depends on Quiver Player Accounts. You can install the plugin for Player Accounts by grabbing it from the Godot Asset Library or copying the `quiver_player_accounts` directory in the [Quiver Player Accounts Github repo](https://github.com/quiver-dev/quiver-player-accounts-godot-plugin) to the `/addons/` directory in your project root.
* Grab the Leaderboards plugin from the Godot Asset Library (use the AssetLib view in the Godot editor) or copy the `quiver_leaderboards` directory in the [Github repo](https://github.com/quiver-dev/quiver-leaderboards-godot-plugin) to the `/addons/` directory in your project root.
* Go to your Project Settings -> Plugins and make sure the Quiver Player Accounts and Quiver Leaderboards plugins are both enabled.
* Close Project Settings and reopen it again. Go to the General tab and you should see a new "Quiver" section at the bottom of the left window.

### Configure the plugins
* Create an account on [quiver.dev](https://quiver.dev), if you haven't already.
* [Create a project](https://quiver.dev/projects/up/) on Quiver associated with your game, if you haven't already.
* Go to your project's leaderboards dashboard on the [Quiver Leaderboards page](https://quiver.dev/leaderboards/), go to the Settings tab, and copy the authentication token and then go to your Godot editor -> Project Settings -> Quiver -> General and paste your auth token.
* Next, create a new test leaderboard. Call it whatever you'd like. After you create it, copy the leaderboard's ID from the Leaderboard settings page.

### Test it!
* Somewhere in your game's code, add the following code: `await Leaderboards.post_guest_score(<your leaderboard id>, 100, "Test Player")`
* Once you've run the code, [view the dashboard](https://quiver.dev/leaderboards/) to see the new score.

## Usage
The `Leaderboards` autoload is added to your project automatically when you enable the plugin.

### Posting a score

To post a score for a guest player account, call:

	await Leaderboards.post_guest_score(leaderboard_id, score, nickname, metadata, timestamp, automatically_retry)

where:

* `leaderboard_id` is a required string which can be found on the [Leaderboards dashboard](https://quiver.dev/leaderboards/).
`score` is a required numeric value representing the score.
`nickname` is an optional string with a maximum length of 15 associated with the given player. You can choose to have your players set the nickname once or to set it every time they post a score. The nickname doesn't have to be unique.
`metadata` is an optional dictionary containing any metadata associated with the score
`timestamp` is an optional float in Unix time in seconds describing when this score was created on the client. If not provided, it will default to the player's current time.
`automatically_retry` is an optional bool for whether the plugin should continue to retry posting the score in the event of a network connection or server error. Defaults to true (this is probably what you want).

Returns a boolean indicating whether this operation was a success. **Important:** Since this function is a coroutine, you have to call it with `await` to get the return value.

Here's an example:

	var success: bool = await Leaderboards.post_guest_score(<your leaderboard id>, 100, "Test Player")


#### _A note about guest player accounts:_

This function will automatically create a guest account behind the scenes for the current player if the player doesn't already have one. The player will remain logged into their guest account from their current device and subsequent calls to `post_guest_score()` will reuse the same player account. There's no way to log in to a guest account from multiple devices and if a guest player is ever logged out, they will not be logged in again. Note that Quiver doesn't support registered users yet, but will do so in the future.


### Fetching scores

You can either handle fetching scores manually and create your own UI, or you can use our `LeaderboardUI` component and customize it.

#### Using the built-in UI

If you'd like to use the built-in UI, simply add an instance of `LeaderboardUI` scene to somewhere in your game. The `LeaderboardUI` is of type `Control` and comes with several export variables that you can use to customize its behavior:

* `leaderboard_id`: required String, corresponding to the leaderboard's ID presented in the Leaderboard dashboard.
* `score_filter`: an enum determining how to filter the returned scores. Possible values are:
	* `Leaderboards.ScoreFilter.ALL`: returns all scores (the default value)
	* `Leaderboards.ScoreFilter.PLAYER` returns the current player's scores. Requires the players to be logged in. Will return a maximum of one score unless using the "All scores" leaderboard update strategy.
	* `Leaderboards.ScoreFilter.NEARBY`: returns one of the current player's score and the closest `nearby_count` scores above it and `nearby_count` scores below it. The player's score that is chosen to be used is determined by `nearby_anchor`. Requires the players to be logged in. Will return a maximum of one score unless using the "All scores" leaderboard update strategy.
* `score_offset`: The index of the score to start fetching from, so 0 will return the first score and so on. Defaults to 0.
* `score_limit`: The maximum number of scores to return. Must be between 1 and 50. Defaults to 10.
* `nearby_count`: The number of scores to fetch above and below a given player's score when using the nearby score filter. Must be between 1 and 25. Defaults to 5.
* `nearby_anchor`: An enum determining which player score if using the nearby score filter. Only applicable if using the "All scores" leaderboard update strategy. Options are:
	* `Leaderboards.NearbyAnchor.BEST`: Use the player's best score (the default).
	* `Leaderboards.NearbyAnchor.LATEST`: Use the player's most recent score.
* `current_player_highlight_color`: a color value. Determines what color to highlight the current player's score. Defaults to a greenish color (#005216).

If you'd like to customize the appearance the LeaderboardUI scene, your best best is to use Godot's [custom themes feature](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_theme_editor.html).

#### Using the API

If you'd like to like to use our API directly to create your leaderboard UI, you can use the following functions:

##### Get all scores

	get_scores(leaderboard_id, offset, limit, start_time, end_time)

This fetches all scores from the given leaderboard using the following parameters:

* `leaderboard_id`: required String, corresponding to the leaderboard's ID presented in the Leaderboard dashboard.
* `offset`: optional integer. The index of the score to start fetching from, so 0 will return the first score and so on. Defaults to 0.
* `limit`: optional integer. The maximum number of scores to return. Must be between 1 and 50. Defaults to 10.
* `start_time`: optional float, representing Unix time in seconds. Fetches all scores after this time. Defaults to the minimum Unix time.
* `end_time`: optional float, representing Unix time in seconds. Fetches all scores before this time. Defaults to the maximum Unix time.

Returns a dictionary. **Important:** This is a coroutine, so it must be called with the `await` keyword. The returned dictionary contains the following keys:
* `scores`: An array of score data. Each element in the array is a dictionary with the following keys:
	*  `name`: A string. Can be blank if no nickname was provided when this score was posted
	* `score`: A float.
	* `rank`: An int. The global rank of this score given this particular query and relative to the time period, if any.
	* `timestamp`: A float. The UNIX time in seconds when this score was posted.
	* `metadata`: A dictionary. Includes any metadata that was attached to this score when it was posted.
 `is_current_player`: A bool. Returns true if the current player is logged in and this score belongs
	to that player.
* `has_more_scores`: Whether there are more scores beyond the given results

##### Get current player's scores

	get_player_scores(leaderboard_id, offset, limit, start_time, end_time)

This fetches the current player's scores from the given leaderboard. See `get_scores` to see the parameters and return value. The current player must be logged in to use this call. Note that this a coroutine, so it must be called with `await`.

##### Get scores nearby to this player's score

	get_nearby_scores(leaderboard_id, nearby_count, anchor, start_time, end_time)

This fetches the scores near the current player's score. See `get_scores` to see information about `leaderboard_id`, `start_time`, `end_time`, and the return value. The current player must be logged in to use this call. The other parameters are as follows:

* `nearby_count`: an optional int. The number of scores to fetch above and below a given player's score. Must be between 1 and 25. Defaults to 5.
* `anchor`: enum value of either `Leaderboards.NearbyAnchor.BEST` or `Leaderboards.NearbyAnchor.LATEST`. `BEST` will fetch the scores near the current player's best score. `LATEST` will fetch scores near the current player's latest score. Note this is only applicable if using the "All scores" leaderboard update strategy. The default is `BEST`.

Note that this a coroutine, so it must be called with `await`.


## More Information

### Notes and Limitations

* Currently this only supports tracking scores from guest players, i.e. players with guest players and not players with login credentials. That will change as we launch our full Player Accounts feature in a future update.
* Player's will be automatically logged in as a guest user when they post their first score. Their guest account will be preserved on the given device unless you manually log them out via an API call or their credential file is deleted. If you ever need to check if a user is logged in or to register a user as a guest player manually, you can use this code:

	  # Check if logged in
	  if not PlayerAccounts.is_logged_in():
		# Register them as a guest if not logged in
		var success: bool = await PlayerAccounts.register_guest()

* Note that like all similar leaderboard systems, Quiver can't verify that a given score is legitimate. We recommend you put processes in place to check if a given score is possible (you can use the metadata field for example). You can then use the web dashboard to delete any spurious scores.

### Troubleshooting

* If you run into issues, please post a message on [our Discord](https://discord.gg/NawdMR497X) or [contact us](https://quiver.dev/contact/).

### License

MIT License
