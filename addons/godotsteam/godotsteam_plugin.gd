@tool
class_name GodotSteamPlugin
extends EditorPlugin

const EDITOR_PANEL = preload("uid://cyniebd6yahu5")

static var dock_frame

var link_changelog: String = "[url=https://godotsteam.com/changelog/gdextension/]changelog[/url]"
var link_website: String = "[url=https://godotsteam.com]website[/url]"
var steamworks_dock: Control


static func get_dock_frame() -> Control:
	return dock_frame


func _enable_plugin() -> void:
	print("GodotSteam GDExtension updater functionality enabled")


func _disable_plugin() -> void:
	print("GodotSteam GDEXtension updater functionality disabled")


func _enter_tree() -> void:
	print_rich("GodotSteam v%s | %s | %s" % [Steam.get_godotsteam_version(), link_website, link_changelog])
	add_project_settings()
	add_steamworks_dock()


func _exit_tree() -> void:
	remove_steamworks_dock()


func _make_visible(visible) -> void:
	if steamworks_dock:
		steamworks_dock.set_visible(visible)


func add_project_settings() -> void:
	if not ProjectSettings.has_setting("steam/updates/godotsteam/check_for_updates"):
		ProjectSettings.set_setting("steam/updates/godotsteam/check_for_updates", true)
	ProjectSettings.add_property_info({
		"name": "steam/updates/godotsteam/check_for_updates",
		"type": TYPE_BOOL
	})
	ProjectSettings.set_initial_value("steam/updates/godotsteam/check_for_updates", true)
	ProjectSettings.set_as_basic("steam/updates/godotsteam/check_for_updates", true)
	if not ProjectSettings.has_setting("steam/updates/godotsteam/update_channel"):
		ProjectSettings.set_setting("steam/updates/godotsteam/update_channel", 0)
	ProjectSettings.add_property_info({
		"name": "steam/updates/godotsteam/update_channel",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Community, Sponsors"
	})
	ProjectSettings.set_initial_value("steam/updates/godotsteam/update_channel", 0)
	ProjectSettings.set_as_basic("steam/updates/godotsteam/update_channel", true)


func add_steamworks_dock() -> void:
	steamworks_dock = EDITOR_PANEL.instantiate()
	add_control_to_bottom_panel(steamworks_dock, "Steamworks")
	dock_frame = steamworks_dock


func remove_steamworks_dock() -> void:
	remove_control_from_bottom_panel(steamworks_dock)
	steamworks_dock.queue_free()
	steamworks_dock = null
	dock_frame = null
