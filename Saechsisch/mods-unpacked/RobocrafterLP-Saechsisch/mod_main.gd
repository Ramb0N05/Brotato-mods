extends Node

# Sächsisches Sprachpaket für Brotato (RobocrafterLP-Saechsisch)
#
# Funktionsweise:
# 1. Baut zur Laufzeit ein Godot-Translation-Objekt mit Locale "de_AT"
#    (Sächsisch). Exakter Locale-Treffer = Sächsisch, Near-Match-Fallback
#    ("de") = offizielles Deutsch für alle nicht übersetzten Keys.
# 2. Trägt "de_AT" in ProgressData.languages ein, damit Sächsisch im
#    Sprachmenü auftaucht. Deutsch bleibt unberührt.
# 3. Liest zur Laufzeit alle Item-/Waffen-Keys aus ItemService aus und
#    sächsischt unbekannte Keys (Primal Dread) über eine Zuordnungstabelle
#    englischer Anzeigenamen. Nicht zugeordnete Keys werden geloggt.
#
# Parser-Regeln für Brotato 1.2 beachtet: keine :=-Typinferenz aus
# Methodenaufrufen, globalen Klassen oder Vergleichen.

const MOD_ID = "RobocrafterLP-Saechsisch"
const MOD_LOG_NAME = "RobocrafterLP-Saechsisch:Main"
const SAXON_LOCALE = "de_AT"

var mod_dir_path = ""
var _saxon_translation: Translation = null
var _pd_name_map: Dictionary = {}
var _wait_timer: Timer = null
var _setup_done: bool = false


func _init() -> void:
	mod_dir_path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_ID)


func _ready() -> void:
	ModLoaderLog.info("Sächsisches Sprachpaket - veel Dankesche!", MOD_LOG_NAME)
	_load_saxon_translation()
	_start_singleton_wait()


func _load_saxon_translation() -> void:
	var file: File = File.new()
	var json_path: String = mod_dir_path.plus_file("translations").plus_file("saechsisch.json")
	var err: int = file.open(json_path, File.READ)
	if err != OK:
		ModLoaderLog.error("Kann saechsisch.json nicht oeffnen: " + json_path, MOD_LOG_NAME)
		return
	var json_text: String = file.get_as_text()
	file.close()
	var parse_result: JSONParseResult = JSON.parse(json_text)
	if parse_result.error != OK:
		ModLoaderLog.error("saechsisch.json hat einen JSON-Fehler (Zeile " + str(parse_result.error_line) + ")", MOD_LOG_NAME)
		return
	var data = parse_result.result
	if typeof(data) != TYPE_DICTIONARY:
		ModLoaderLog.error("saechsisch.json ist kein JSON-Objekt", MOD_LOG_NAME)
		return
	var trn: Translation = Translation.new()
	trn.set_locale(SAXON_LOCALE)
	var nb_keys: int = 0
	var nb_names: int = 0
	if data.has("keys") and typeof(data["keys"]) == TYPE_DICTIONARY:
		var key_dict: Dictionary = data["keys"]
		for k in key_dict:
			trn.add_message(k, str(key_dict[k]))
			nb_keys += 1
	if data.has("names") and typeof(data["names"]) == TYPE_DICTIONARY:
		var name_dict: Dictionary = data["names"]
		for n in name_dict:
			_pd_name_map[_normalize(n)] = str(name_dict[n])
			nb_names += 1
	TranslationServer.add_translation(trn)
	_saxon_translation = trn
	ModLoaderLog.info(str(nb_keys) + " Keys und " + str(nb_names) + " Namens-Zuordnungen registriert (Locale " + SAXON_LOCALE + ")", MOD_LOG_NAME)


func _start_singleton_wait() -> void:
	_wait_timer = Timer.new()
	_wait_timer.wait_time = 0.5
	_wait_timer.one_shot = false
	_wait_timer.autostart = false
	_wait_timer.connect("timeout", self, "_on_wait_timer_timeout")
	add_child(_wait_timer)
	_wait_timer.start()


func _on_wait_timer_timeout() -> void:
	if _setup_done:
		return
	if _saxon_translation == null:
		return
	var progress_data: Node = get_node_or_null("/root/ProgressData")
	if progress_data == null:
		return
	var item_service: Node = get_node_or_null("/root/ItemService")
	if item_service == null:
		return
	if _wait_timer != null:
		_wait_timer.stop()
	_setup_done = true
	_register_language(progress_data)
	_apply_runtime_names(item_service)


func _register_language(progress_data: Node) -> void:
	var languages = progress_data.get("languages")
	if typeof(languages) == TYPE_ARRAY:
		if not languages.has(SAXON_LOCALE):
			languages.append(SAXON_LOCALE)
			ModLoaderLog.info("Saechsisch ist jetzt im Sprachmenue (Locale " + SAXON_LOCALE + ")", MOD_LOG_NAME)
		else:
			ModLoaderLog.info("Saechsisch war schon im Sprachmenue", MOD_LOG_NAME)
	else:
		ModLoaderLog.error("ProgressData.languages ist kein Array - Sprachmenue-Eintrag nicht moeglich", MOD_LOG_NAME)


func _apply_runtime_names(item_service: Node) -> void:
	var nb_applied: int = 0
	var missing: Array = []
	var items = item_service.get("items")
	var weapons = item_service.get("weapons")
	if typeof(items) == TYPE_ARRAY:
		nb_applied += _scan_list(items, missing)
	if typeof(weapons) == TYPE_ARRAY:
		nb_applied += _scan_list(weapons, missing)
	ModLoaderLog.info(str(nb_applied) + " DLC-Namen zur Laufzeit saechsisch gemacht", MOD_LOG_NAME)
	if missing.size() > 0:
		ModLoaderLog.info("Ohne saechsischen Namen geblieben: " + str(missing), MOD_LOG_NAME)


func _scan_list(content_list: Array, missing: Array) -> int:
	var nb_applied: int = 0
	for data in content_list:
		if data == null:
			continue
		var name_prop = data.get("name")
		if typeof(name_prop) != TYPE_STRING:
			continue
		var key: String = name_prop
		if key == "":
			continue
		var existing: String = _saxon_translation.get_message(key)
		if existing != "":
			continue
		var stripped: String = key
		if stripped.begins_with("ITEM_"):
			stripped = stripped.substr(5, stripped.length() - 5)
		elif stripped.begins_with("WEAPON_"):
			stripped = stripped.substr(7, stripped.length() - 7)
		var norm: String = _normalize(stripped)
		var saxon: String = _lookup_saxon(norm)
		if saxon != "":
			_saxon_translation.add_message(key, saxon)
			nb_applied += 1
		else:
			if not missing.has(key):
				missing.append(key)
	return nb_applied


func _lookup_saxon(norm: String) -> String:
	if _pd_name_map.has(norm):
		return _pd_name_map[norm]
	# Suffix-Varianten (z.B. ITEM_X_MECHA / ITEM_X_MUTANT)
	if norm.ends_with("mecha"):
		var base_mecha: String = norm.substr(0, norm.length() - 5)
		if _pd_name_map.has(base_mecha):
			return _pd_name_map[base_mecha]
	if norm.ends_with("mutant"):
		var base_mutant: String = norm.substr(0, norm.length() - 6)
		if _pd_name_map.has(base_mutant):
			return _pd_name_map[base_mutant]
	# Praefix-Varianten (z.B. ITEM_MECA_EVOLVED_LEAP / ITEM_MUT_EVOLVED_LEAP,
	# verifiziert im 1.0.0-Testlog)
	if norm.begins_with("meca"):
		var pre_meca: String = norm.substr(4, norm.length() - 4)
		if _pd_name_map.has(pre_meca):
			return _pd_name_map[pre_meca]
	if norm.begins_with("mut"):
		var pre_mut: String = norm.substr(3, norm.length() - 3)
		if _pd_name_map.has(pre_mut):
			return _pd_name_map[pre_mut]
	return ""


func _normalize(s: String) -> String:
	var lower: String = s.to_lower()
	var out: String = ""
	var i: int = 0
	while i < lower.length():
		var c: String = lower.substr(i, 1)
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		i += 1
	return out
