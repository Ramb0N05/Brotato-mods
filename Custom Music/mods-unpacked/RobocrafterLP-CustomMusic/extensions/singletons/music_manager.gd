extends "res://singletons/music_manager.gd"

# RobocrafterLP-CustomMusic
# Plays user-supplied .ogg tracks from user://music via the vanilla
# MusicManager player (music bus, volume fades and the "finished" -> play()
# loop all stay vanilla).
#
# Settings (dami-ModOptions):
# - MUSIC_MODE "Ersetzt Original-Tracks": only custom tracks play
#   "Erweitert Original-Tracks": custom tracks play together with the
#   vanilla + DLC tracks
# - SHUFFLE: random order or fixed order (vanilla tracks first, then custom
#   tracks alphabetically)
# - MUSIC_IMPORT_PATH: display row, toggle opens the folder in the file manager
#
# The playlist refills itself every cycle and repeats even with a single
# track, no matter what is configured (endless repetition). Vanilla
# play() actually dies when a one-track queue comes up (it pops null and
# leaves the stream empty), this override fixes that too.
#
# 1.2 parser notes: no ":=" inference from "==" comparisons on untyped
# fields and no ":=" inference from global singleton methods in this
# extension file (known 1.2.0.1 parse-error traps).

const RobocrafterLP_CustomMusic_ID = "RobocrafterLP-CustomMusic"
const RobocrafterLP_CustomMusic_LOG_NAME := RobocrafterLP_CustomMusic_ID + ":MusicManager"
const MUSIC_IMPORT_DIR := "user://music"

const MUSIC_MODE_REPLACE := "Ersetzt Original-Tracks"
const MUSIC_MODE_EXTEND := "Erweitert Original-Tracks"

const CONFIG_KEY_MUSIC_MODE := "MUSIC_MODE"
const CONFIG_KEY_SHUFFLE := "SHUFFLE"
const CONFIG_KEY_IMPORT_PATH := "MUSIC_IMPORT_PATH"

var _config: ModConfig
var _custom_tracks: Array = []
var _play_queue: Array = []
var _mode_replace: bool = true
var _shuffle: bool = true


# Extended func's
func _ready() -> void:
	._ready()  # vanilla: creates player + tween, connects "finished" -> on_track_finished -> play()
	_read_config()
	var mods_config_interface = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")

	if mods_config_interface != null:
		var _error = mods_config_interface.connect("setting_changed", self, "on_custom_music_setting_changed")

	ensure_music_folder()
	load_custom_tracks()
	ModLoaderLog.info("Custom music active (mode: " + ("Ersetzt" if _mode_replace else "Erweitert") + ", shuffle: " + ("an" if _shuffle else "aus") + ", tracks: " + str(_custom_tracks.size()) + ")", RobocrafterLP_CustomMusic_LOG_NAME)


# Fully replaces vanilla play(): the queue refills itself every cycle,
# so the music never stops, no matter the settings.
func play(volume: float = player.volume_db) -> void:
	if _play_queue.empty():
		_fill_play_queue()

		if _play_queue.empty():
			player.stop()
			return

	var next_stream = _play_queue.pop_front()

	# Avoid immediate repeats when there is more than one track;
	# with a single track the same stream replays forever.
	if next_stream == player.stream and not _play_queue.empty():
		var swap_stream = _play_queue.pop_front()
		_play_queue.push_back(next_stream)
		next_stream = swap_stream

	player.stream = next_stream
	player.volume_db = -20
	player.play()
	tween(volume)


# Custom func's
func on_custom_music_setting_changed(setting_name, value, mod_name) -> void:
	if mod_name != RobocrafterLP_CustomMusic_ID:
		return

	if setting_name == CONFIG_KEY_MUSIC_MODE:
		_mode_replace = is_replace_value(value)
		_play_queue = []
		ModLoaderLog.info("Music mode changed to " + str(value), RobocrafterLP_CustomMusic_LOG_NAME)
	elif setting_name == CONFIG_KEY_SHUFFLE:
		_shuffle = is_shuffle_value(value)
		_play_queue = []
		ModLoaderLog.info("Shuffle changed to " + str(value), RobocrafterLP_CustomMusic_LOG_NAME)
	elif setting_name == CONFIG_KEY_IMPORT_PATH:
		open_music_folder()

	if _config != null:
		if setting_name == CONFIG_KEY_MUSIC_MODE or setting_name == CONFIG_KEY_SHUFFLE or setting_name == CONFIG_KEY_IMPORT_PATH:
			_config.data[setting_name] = value
			var _save_error = _config.save_to_file()


func is_replace_value(value) -> bool:
	return value == MUSIC_MODE_REPLACE


func is_shuffle_value(value) -> bool:
	return value == true


func open_music_folder() -> void:
	ensure_music_folder()
	var global_path = ProjectSettings.globalize_path(MUSIC_IMPORT_DIR)
	OS.shell_open(global_path)
	ModLoaderLog.info("Opening music folder: " + global_path, RobocrafterLP_CustomMusic_LOG_NAME)


func ensure_music_folder() -> void:
	var dir = Directory.new()

	if not dir.dir_exists(MUSIC_IMPORT_DIR):
		var _error = dir.make_dir_recursive(MUSIC_IMPORT_DIR)
		ModLoaderLog.info("Created music folder: " + ProjectSettings.globalize_path(MUSIC_IMPORT_DIR), RobocrafterLP_CustomMusic_LOG_NAME)


func load_custom_tracks() -> void:
	_custom_tracks = []
	var dir = Directory.new()

	if dir.open(MUSIC_IMPORT_DIR) != OK:
		ModLoaderLog.error("Cannot open " + MUSIC_IMPORT_DIR, RobocrafterLP_CustomMusic_LOG_NAME)
		return

	var ogg_files: Array = []
	var ignored_files: Array = []
	dir.list_dir_begin(true, true)
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.to_lower().ends_with(".ogg"):
			ogg_files.append(file_name)
		else:
			ignored_files.append(file_name)
		file_name = dir.get_next()

	dir.list_dir_end()
	ogg_files.sort()

	for ogg_file in ogg_files:
		var stream = AudioStreamOGGVorbis.new()

		if stream.load_from_file(MUSIC_IMPORT_DIR.plus_file(ogg_file)) == OK:
			_custom_tracks.append(stream)
		else:
			ModLoaderLog.error("Failed to load track: " + ogg_file, RobocrafterLP_CustomMusic_LOG_NAME)

	if not ignored_files.empty():
		ModLoaderLog.warning("Ignored (not .ogg): " + str(ignored_files), RobocrafterLP_CustomMusic_LOG_NAME)

	ModLoaderLog.info("Loaded " + str(_custom_tracks.size()) + " custom tracks from " + MUSIC_IMPORT_DIR, RobocrafterLP_CustomMusic_LOG_NAME)


func _read_config() -> void:
	_config = ModLoaderConfig.get_current_config(RobocrafterLP_CustomMusic_ID)

	if _config == null:
		_config = ModLoaderConfig.get_default_config(RobocrafterLP_CustomMusic_ID)

	if _config == null or _config.data.empty():
		return

	if _config.data.has(CONFIG_KEY_MUSIC_MODE):
		_mode_replace = is_replace_value(_config.data[CONFIG_KEY_MUSIC_MODE])

	if _config.data.has(CONFIG_KEY_SHUFFLE):
		_shuffle = is_shuffle_value(_config.data[CONFIG_KEY_SHUFFLE])


func _fill_play_queue() -> void:
	_play_queue = []
	var pool: Array = []

	# Replace mode only makes sense with custom tracks - otherwise the
	# vanilla playlist keeps playing (never silence just because the
	# folder is empty)
	if _mode_replace and not _custom_tracks.empty():
		pool.append_array(_custom_tracks)
	else:
		pool.append_array(get_vanilla_tracks())
		pool.append_array(_custom_tracks)

	if pool.empty():
		return

	if _shuffle:
		pool.shuffle()

	_play_queue = pool


func get_vanilla_tracks() -> Array:
	# Vanilla set_shuffled_tracks() logic (1.2.0.1), but without shuffling
	var tracks: Array = []

	if ProgressData.settings.streamer_mode_tracks:
		tracks.append_array(new_tracks.duplicate())

	if ProgressData.settings.legacy_tracks:
		tracks.append_array(old_tracks.duplicate())

	for dlc_id in ProgressData.get_active_dlc_tracks():
		var dlc_data = ProgressData.get_dlc_data(dlc_id)

		if dlc_data:
			tracks.append_array(dlc_data.music_tracks.duplicate())

	return tracks
