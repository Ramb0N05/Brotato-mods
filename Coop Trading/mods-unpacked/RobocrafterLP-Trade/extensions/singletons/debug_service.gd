extends "res://singletons/debug_service.gd"


func _ready():
	ModLoaderMod.install_script_extension(ModLoaderMod.get_unpacked_dir().plus_file("RobocrafterLP-Trade/extensions/ui/menus/ingame/coop_upgrades_ui_player_container.gd"))
	ModLoaderMod.install_script_extension(ModLoaderMod.get_unpacked_dir().plus_file("RobocrafterLP-Trade/extensions/ui/menus/ingame/upgrades_ui.gd"))
