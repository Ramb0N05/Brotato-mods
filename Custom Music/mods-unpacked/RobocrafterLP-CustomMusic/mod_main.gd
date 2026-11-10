extends Node

const RobocrafterLP_CustomMusic_ID = "RobocrafterLP-CustomMusic"
const RobocrafterLP_CustomMusic_DIR := RobocrafterLP_CustomMusic_ID
const RobocrafterLP_CustomMusic_LOG_NAME := RobocrafterLP_CustomMusic_ID + ":Main"

const MUSIC_IMPORT_DIR := "user://music"


var mod_dir_path := ""
var extensions_dir_path := ""


# Extended func's
func _init() -> void:
	mod_dir_path = ModLoaderMod.get_unpacked_dir().plus_file(RobocrafterLP_CustomMusic_DIR)
	# Add extensions
	install_script_extensions()
	# Patch the real import folder into the ModOptions config schema
	patch_import_path_in_config_schema()


func _ready() -> void:
	ModLoaderLog.info("Ready!", RobocrafterLP_CustomMusic_LOG_NAME)
	_config(RobocrafterLP_CustomMusic_ID, RobocrafterLP_CustomMusic_LOG_NAME)


# Custom func's
func install_script_extensions() -> void:
	extensions_dir_path = mod_dir_path.plus_file("extensions")

	var extensions = [
		"singletons/music_manager.gd"
	]

	for extension in extensions:
		ModLoaderMod.install_script_extension(extensions_dir_path.plus_file(extension))


func patch_import_path_in_config_schema() -> void:
	# dami-ModOptions renders option rows straight from the manifest config
	# schema (titles are plain labels, not translated). The manifest is a
	# static file, so the real absolute import path is patched in here.
	# All ModConfigs share the same schema Dictionary reference (see
	# ModConfig._init), so the patched title reaches the ModOptions UI
	# before it builds its rows (this runs during mod loading, ModOptions
	# builds its UI in its own _ready afterwards).
	var global_path = ProjectSettings.globalize_path(MUSIC_IMPORT_DIR)
	var mod_data = ModLoaderStore.mod_data.get(RobocrafterLP_CustomMusic_ID)

	if mod_data == null or mod_data.manifest.config_schema.empty():
		ModLoaderLog.warning("Could not patch config schema (mod data or schema missing).", RobocrafterLP_CustomMusic_LOG_NAME)
		return

	var properties = mod_data.manifest.config_schema.get("properties")

	if properties == null or not properties.has("MUSIC_IMPORT_PATH"):
		ModLoaderLog.warning("Could not patch config schema (MUSIC_IMPORT_PATH missing).", RobocrafterLP_CustomMusic_LOG_NAME)
		return

	properties.MUSIC_IMPORT_PATH.title = "Import-Ordner: " + global_path
	ModLoaderLog.info("Custom music import folder: " + global_path, RobocrafterLP_CustomMusic_LOG_NAME)


func _config(mod_id: String, mod_log: String) -> void: # Defaults for Mods Options
	var data = ModLoaderStore.mod_data[mod_id]

	if data != null:
		var version = data.manifest.version_number
		ModLoaderLog.info("Current Version is %s." % version, mod_log)
		var config = ModLoaderConfig.get_config(mod_id, version)

		if config == null:
			var defaultConfig = ModLoaderConfig.get_default_config(mod_id)
			if defaultConfig != null:
				config = ModLoaderConfig.create_config(mod_id, version, defaultConfig.data)
			else:
				config = ModLoaderConfig.create_config(mod_id, version, {})

		if config != null and ModLoaderConfig.get_current_config_name(mod_id) != version:
			ModLoaderConfig.set_current_config(config)
			if config.is_valid():
				config.save_to_file()
				ModLoaderLog.info("Save config to : %s" % config.save_path, mod_log)
