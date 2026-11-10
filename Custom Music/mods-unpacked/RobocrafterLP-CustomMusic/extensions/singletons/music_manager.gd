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
# - RESUME: remember the last played track and its position; the next game
#   start continues exactly there (position saved every few seconds)
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
const CONFIG_KEY_RESUME := "RESUME"
const RESUME_STATE_PATH := "user://custom_music_resume.cfg"
const RESUME_SAVE_INTERVAL := 5.0

var _config: ModConfig
var _custom_tracks: Array = []
var _track_names: Dictionary = {}
var _play_queue: Array = []
var _mode_replace: bool = true
var _shuffle: bool = true
var _resume_enabled: bool = true
var _resume_track: String = ""
var _resume_position: float = 0.0
var _resume_applied: bool = false
var _current_track_name: String = ""
var _resume_save_timer: Timer


# Extended func's
func _ready() -> void:
	._ready()  # vanilla: creates player + tween, connects "finished" -> on_track_finished -> play()
	_read_config()
	var mods_config_interface = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")

	if mods_config_interface != null:
		var _error = mods_config_interface.connect("setting_changed", self, "on_custom_music_setting_changed")

	ensure_music_folder()
	load_custom_tracks()
	_load_resume_state()
	_start_resume_save_timer()
	ModLoaderLog.info("Custom music active (mode: " + ("Ersetzt" if _mode_replace else "Erweitert") + ", shuffle: " + ("an" if _shuffle else "aus") + ", tracks: " + str(_custom_tracks.size()) + ")", RobocrafterLP_CustomMusic_LOG_NAME)


# Fully replaces vanilla play(): the queue refills itself every cycle,
# so the music never stops, no matter the settings. On the very first
# call of a session, the resume feature (1.1.0) moves the last session's
# track to the front of the queue and plays it from the saved position.
func play(volume: float = player.volume_db) -> void:
	var resume_pos: float = -1.0

	if not _resume_applied:
		resume_pos = _prepare_resume()

	if _play_queue.empty():
		_fill_play_queue()

		if _play_queue.empty():
			player.stop()
			return

	var next_stream = _play_queue.pop_front()

	# Avoid immediate repeats when there is more than one track;
	# with a single track the same stream replays forever. Skipped on
	# resume so the saved track is really the one that plays.
	if resume_pos < 0.0 and next_stream == player.stream and not _play_queue.empty():
		var swap_stream = _play_queue.pop_front()
		_play_queue.push_back(next_stream)
		next_stream = swap_stream

	player.stream = next_stream
	player.volume_db = -20
	_current_track_name = _queue_track_name(next_stream)

	if resume_pos >= 0.0:
		player.play(resume_pos)
	else:
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
	elif setting_name == CONFIG_KEY_RESUME:
		_resume_enabled = is_resume_value(value)
		ModLoaderLog.info("Resume changed to " + str(value), RobocrafterLP_CustomMusic_LOG_NAME)
	elif setting_name == CONFIG_KEY_IMPORT_PATH:
		open_music_folder()

	if _config != null:
		if setting_name == CONFIG_KEY_MUSIC_MODE or setting_name == CONFIG_KEY_SHUFFLE or setting_name == CONFIG_KEY_RESUME or setting_name == CONFIG_KEY_IMPORT_PATH:
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
		var full_path = MUSIC_IMPORT_DIR.plus_file(ogg_file)
		var stream = AudioStreamOGGVorbis.new()
		var file = File.new()

		if file.open(full_path, File.READ) != OK:
			ModLoaderLog.error("Cannot open track: " + ogg_file, RobocrafterLP_CustomMusic_LOG_NAME)
			continue

		var bytes = file.get_buffer(file.get_len())
		file.close()

		# 1.0.1 fix: stream.load_from_file() returns OK in Brotato's Godot
		# 3.7.dev build but produces a stream WITHOUT data ("This
		# AudioStreamOGGVorbis does not have an audio file assigned to it"
		# at instance_playback). The canonical way is reading the bytes and
		# assigning the "data" property: set_data() validates the vorbis
		# stream inside the engine and leaves data empty on invalid input.
		stream.data = bytes

		if stream.data.empty():
			ModLoaderLog.error("Track is not valid OGG Vorbis (renamed MP3/Opus?), skipped: " + ogg_file, RobocrafterLP_CustomMusic_LOG_NAME)
		else:
			_custom_tracks.append(stream)
			_track_names[stream] = ogg_file
			ModLoaderLog.info("Loaded track: " + ogg_file + " (" + str(bytes.size()) + " bytes)", RobocrafterLP_CustomMusic_LOG_NAME)

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

	if _config.data.has(CONFIG_KEY_RESUME):
		_resume_enabled = is_resume_value(_config.data[CONFIG_KEY_RESUME])


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


# --- Resume (1.1.0): continue the last session's track at the saved position.
# The position is written to user://custom_music_resume.cfg every
# RESUME_SAVE_INTERVAL seconds while an identifiable track plays. On the
# next game start, the saved track moves to the front of the first play
# queue and continues from that position. Custom tracks are identified by
# their file name, vanilla/DLC tracks by their resource path (vanilla
# tracks without a resource path simply do not update the state file).

func is_resume_value(value) -> bool:
	return value == true


func _start_resume_save_timer() -> void:
	_resume_save_timer = Timer.new()
	_resume_save_timer.wait_time = RESUME_SAVE_INTERVAL
	_resume_save_timer.autostart = true
	var _error = _resume_save_timer.connect("timeout", self, "_on_resume_save_timer_timeout")
	add_child(_resume_save_timer)


func _on_resume_save_timer_timeout() -> void:
	_save_resume_state()


func _load_resume_state() -> void:
	_resume_track = ""
	_resume_position = 0.0
	var state_file: ConfigFile = ConfigFile.new()

	if state_file.load(RESUME_STATE_PATH) != OK:
		return

	var saved_track = state_file.get_value("resume", "track", "")
	var saved_position = state_file.get_value("resume", "position", 0.0)

	if typeof(saved_track) == TYPE_STRING and typeof(saved_position) == TYPE_REAL:
		_resume_track = String(saved_track)
		_resume_position = float(saved_position)

	if _resume_track != "" and _resume_position > 0.0:
		ModLoaderLog.info("Resume found last session at: " + _resume_track + " (" + _format_seconds(_resume_position) + ")", RobocrafterLP_CustomMusic_LOG_NAME)


func _save_resume_state() -> void:
	if not _resume_enabled:
		return

	# Nothing identifiable is playing: keep the previous state file
	# (e.g. a vanilla track without resource_path does not overwrite it).
	if not player.playing or _current_track_name == "":
		return

	var position: float = player.get_playback_position()

	if position <= 0.0:
		return

	var state_file: ConfigFile = ConfigFile.new()
	state_file.set_value("resume", "track", _current_track_name)
	state_file.set_value("resume", "position", position)
	var _error = state_file.save(RESUME_STATE_PATH)


func _prepare_resume() -> float:
	# Runs once per session (first play() call).
	_resume_applied = true

	if not _resume_enabled or _resume_track == "" or _resume_position <= 0.0:
		_resume_track = ""
		_resume_position = 0.0
		return -1.0

	if _play_queue.empty():
		_fill_play_queue()

	if _play_queue.empty():
		ModLoaderLog.info("Resume skipped: play queue is empty", RobocrafterLP_CustomMusic_LOG_NAME)
		return -1.0

	var found_index: int = -1

	for i in range(_play_queue.size()):
		if _queue_track_name(_play_queue[i]) == _resume_track:
			found_index = i
			break

	var resume_position: float = _resume_position
	var resume_track: String = _resume_track
	_resume_track = ""
	_resume_position = 0.0

	if found_index < 0:
		ModLoaderLog.info("Resume: '" + resume_track + "' not found in the current queue, starting fresh", RobocrafterLP_CustomMusic_LOG_NAME)
		return -1.0

	var resume_stream = _play_queue[found_index]
	_play_queue.remove(found_index)
	_play_queue.push_front(resume_stream)
	ModLoaderLog.info("Resume: continuing '" + resume_track + "' at " + _format_seconds(resume_position), RobocrafterLP_CustomMusic_LOG_NAME)
	return resume_position


func _queue_track_name(stream) -> String:
	if _track_names.has(stream):
		return String(_track_names[stream])

	# Vanilla/DLC tracks: identify by resource path (empty for custom
	# streams, which are covered by the lookup above).
	var res_path: String = String(stream.resource_path)
	return res_path


func _format_seconds(seconds: float) -> String:
	var total: int = int(seconds)
	var mins: int = total / 60
	var secs: int = total % 60
	return str(mins) + ":" + ("%02d" % secs)
