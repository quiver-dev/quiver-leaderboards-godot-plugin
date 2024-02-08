@tool
extends EditorPlugin

const AUTOLOAD_NAME := "Leaderboards"
const CUSTOM_PROPERTIES := [
	{"name": "quiver/general/auth_token", "default": "", "basic": true, "general": true},
]

func _enter_tree() -> void:
	for property in CUSTOM_PROPERTIES:
		var name = property["name"]
		var default = property["default"]
		var basic = property["basic"]
		if not ProjectSettings.has_setting(name):
			ProjectSettings.set_setting(name, default)
			ProjectSettings.set_initial_value(name, default)
			if basic:
				ProjectSettings.set_as_basic(name, true)
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/quiver_leaderboards/leaderboards.tscn")
	#add_custom_type("Leaderboard", "CanvasLayer", preload("res://addons/quiver_leaderboards/leaderboard_ui_helper.gd"), preload("res://icon.svg"))
	if not ProjectSettings.get_setting("quiver/general/auth_token"):
		printerr("[Quiver Leaderboards] Auth key hasn't been set for Quiver services.")


func _exit_tree() -> void:
	#remove_custom_type("Leaderboard")
	remove_autoload_singleton(AUTOLOAD_NAME)
	for property in CUSTOM_PROPERTIES:
		var name = property["name"]
		if not property["general"]:
			ProjectSettings.set_setting(name, null)
