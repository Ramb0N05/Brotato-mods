extends CoopItemPopup

# RobocrafterLP-Trade — shop item popup extension for Brotato 1.2.0.1 (Primal Dread)
#
# Compatibility notes (game 1.2.0.1, Mod Loader 6.3.0):
#  - The 1.2 popup scene adds the native Mechanize button (_upgrade_button) and the
#    meca effect choice UI (_effect_choice_container / _effect_button_0 / _effect_button_1)
#    between the classic buttons. Trade buttons are therefore inserted BEFORE the
#    cancel button and never patch native focus neighbours permanently: the only
#    temporarily patched native properties are cancel.focus_neighbour_top and the
#    bottom neighbour of the closest focusable control above the trade buttons,
#    both saved and restored.
#  - Trade execution no longer lives in a CoopShop script extension. The whole
#    transfer runs here (RunData.remove_weapon/add_weapon, remove_item/add_item),
#    shop services are found by probing the node tree upwards. Signals are still
#    emitted first so other mods can intercept.
#  - Weapon eligibility uses the int effect keys (Keys.*_hash) as required since
#    1.1; the old string-key copy of _can_weapon_be_bought crashed at runtime and
#    made weapon trades impossible.

signal weapon_trade_button_pressed_coop(weapon_data, from_player_index, to_player_index)
signal item_trade_button_pressed_coop(item_data, from_player_index, to_player_index)

const LOG_NAME := "RobocrafterLP-Trade:CoopItemPopup"

# Items with special per-player mounting/balance that must never change owner.
# Hourglass excluded as well (same reasoning as the reference gift mod).
const NO_TRADE_ITEM_IDS := ["item_celery_tea", "item_lure", "item_peacock", "item_hourglass"]

# Effects that only apply on the next wave: trading them away mid-wave breaks them.
const DEFERRED_NEXT_WAVE_KEYS := [
	"hp_start_next_wave",
	"extra_enemies_next_wave",
	"extra_loot_aliens_next_wave",
	"extra_elite_next_wave_chance",
	"gain_random_primary_stats_on_go_to_next_wave"
]

var _trade_buttons := {}
var _vanilla_cancel_top := NodePath()
var _cancel_top_patched := false
var _vanilla_above_bottom := NodePath()
var _above_button_path := NodePath()
var _above_bottom_patched := false
var _sell_mod_checked := false
var _sell_mod_present := false


func _ready() -> void:
	call_deferred("_trade_ready")


func _trade_ready() -> void:
	if not _is_coop():
		return
	_ensure_trade_buttons()


func _is_coop() -> bool:
	return RunData.is_coop_run and RunData.get_player_count() > 1


# ---------------------------------------------------------------- refresh hooks
# Main hook is _update_button_visibilities (called by the game whenever popup
# content or focus changes). focus()/hide()/display_element() are additional
# triggers so visibility follows popup state even if the main hook is renamed.

func display_element(element: InventoryElement) -> void:
	.display_element(element)
	_refresh_trade_buttons()


func focus() -> void:
	.focus()
	_refresh_trade_buttons()


func hide(_player_index := -1) -> void:
	.hide(_player_index)
	_hide_all_trade_buttons()
	_restore_native_focus()


func _update_button_visibilities() -> void:
	var item_data = get("_item_data")
	if _is_tradeable(item_data) and _is_coop():
		if item_data is WeaponData:
			# Weapon popups keep the full native button set (Combine/Mechanize/
			# Recycle/Cancel) working; trade buttons are shown on top of it.
			._update_button_visibilities()
			_update_weapon_trade_overlay()
			return
		_update_item_trade_buttons()
		return

	._update_button_visibilities()
	_hide_all_trade_buttons()
	_restore_native_focus()


func should_show_buttons(item_data: ItemParentData, focused: bool) -> bool:
	if _is_coop() and _is_tradeable(item_data) and item_data is ItemData:
		var enabled = get("buttons_enabled")
		return (enabled == null or bool(enabled)) and focused
	return .should_show_buttons(item_data, focused)


# ---------------------------------------------------------------- button creation

func _get_anchor_button() -> Button:
	for member in ["_discard_button", "_cancel_button"]:
		var button = get(member)
		if button is Button and is_instance_valid(button) and button.get_parent() != null:
			return button
	return null


func _get_button_parent() -> Node:
	var anchor = _get_anchor_button()
	if anchor != null:
		return anchor.get_parent()
	return null


func _get_insert_index(parent: Node) -> int:
	# Trade buttons sit right before the cancel button: the native baked focus
	# chain (Combine -> Mechanize -> Recycle -> Cancel -> Mechanize) stays intact.
	var cancel = get("_cancel_button")
	if cancel is Button and cancel.get_parent() == parent:
		return cancel.get_index()
	return parent.get_child_count()


func _ensure_trade_buttons() -> void:
	if not _is_coop():
		return
	var parent = _get_button_parent()
	if parent == null:
		return

	for target_index in RunData.get_player_count():
		if target_index == player_index:
			continue
		if _trade_buttons.has(target_index) and is_instance_valid(_trade_buttons[target_index]):
			continue
		var trade_button = _create_trade_button(target_index)
		if trade_button == null:
			return
		_trade_buttons[target_index] = trade_button
		parent.add_child(trade_button)
		parent.move_child(trade_button, _get_insert_index(parent))


func _create_trade_button(target_player_index: int) -> Button:
	var cancel = get("_cancel_button")
	var anchor = _get_anchor_button()
	if not (cancel is Button) and anchor == null:
		return null
	if cancel is Button and not is_instance_valid(cancel):
		return null
	var template: Button = cancel if cancel is Button else anchor

	var trade_button: Button

	# Build from the game's own menu button script when available (cleanest
	# theme integration, no duplicated scene connections to clean up).
	if ResourceLoader.exists("res://ui/menus/global/my_menu_button.gd"):
		trade_button = load("res://ui/menus/global/my_menu_button.gd").new()
		trade_button.theme = template.theme
		var template_font = template.get_font("font")
		if template_font != null:
			trade_button.add_font_override("font", template_font)
		var normal_style = template.get_stylebox("normal")
		if normal_style != null:
			trade_button.add_stylebox_override("normal", normal_style.duplicate())
		trade_button.rect_min_size = template.rect_min_size
		trade_button.size_flags_horizontal = template.size_flags_horizontal
		trade_button.size_flags_vertical = template.size_flags_vertical
	else:
		trade_button = template.duplicate()
		for child in trade_button.get_children():
			child.free()
		for connection in trade_button.get_signal_connection_list("pressed"):
			trade_button.disconnect("pressed", connection.target, connection.method)

	trade_button.name = "TradeToPlayer" + str(target_player_index + 1)
	trade_button.text = "TRADE_GIVE_TO_PLAYER_BUTTON_%s" % str(target_player_index + 1)
	trade_button.focus_mode = Control.FOCUS_NONE
	trade_button.hint_tooltip = ""

	if trade_button.is_connected("pressed", self, "_on_TradeButton_pressed_coop"):
		trade_button.disconnect("pressed", self, "_on_TradeButton_pressed_coop")
	trade_button.connect("pressed", self, "_on_TradeButton_pressed_coop", [target_player_index])
	trade_button.hide()
	return trade_button


# ---------------------------------------------------------------- visibility

func _is_tradeable(item_data) -> bool:
	if item_data == null:
		return false
	if item_data is CharacterData or item_data is ConsumableData or item_data is UpgradeData:
		return false
	if item_data is ItemData:
		if "character" in item_data.my_id:
			return false
		if item_data.my_id in NO_TRADE_ITEM_IDS:
			return false
	if _has_deferred_next_wave_effect(item_data):
		return false
	return true


static func _has_deferred_next_wave_effect(item_data) -> bool:
	if item_data == null or item_data.get("effects") == null:
		return false
	for effect in item_data.effects:
		if effect.key in DEFERRED_NEXT_WAVE_KEYS:
			return true
		if effect.custom_key == "stats_next_wave":
			return true
	return false


func _hide_all_trade_buttons() -> void:
	for target_index in _trade_buttons.keys():
		var trade_button: Button = _trade_buttons[target_index]
		if is_instance_valid(trade_button):
			trade_button.hide()
			trade_button.focus_mode = Control.FOCUS_NONE


func _update_weapon_trade_overlay() -> void:
	_ensure_trade_buttons()
	var enabled = get("buttons_enabled")
	var focused = get("_focused")
	if enabled == null or not bool(enabled) or focused == null or not bool(focused):
		_hide_all_trade_buttons()
		_restore_native_focus()
		return
	# While the native meca effect choice is open the effect buttons own the
	# popup navigation; trade buttons must not compete with them.
	var effect_choice = get("_effect_choice_container")
	if effect_choice is Control and is_instance_valid(effect_choice) and effect_choice.visible:
		_hide_all_trade_buttons()
		_restore_native_focus()
		return
	_update_trade_button_states()
	_wire_weapon_trade_focus()


func _update_item_trade_buttons() -> void:
	_ensure_trade_buttons()
	_hide_native_action_buttons()

	var enabled = get("buttons_enabled")
	var focused = get("_focused")
	var cancel = get("_cancel_button")

	if enabled == null or not bool(enabled) or focused == null or not bool(focused):
		if cancel is Button:
			cancel.hide()
			cancel.focus_mode = Control.FOCUS_NONE
		_hide_all_trade_buttons()
		_restore_native_focus()
		return

	if cancel is Button:
		cancel.show()
		cancel.focus_mode = Control.FOCUS_ALL
	_update_trade_button_states()
	_wire_item_trade_focus()


func _hide_native_action_buttons() -> void:
	# Item mode is fully managed by the trade flow: hide the weapon-only action
	# buttons (combine/discard/mechanize). The sell mod RobocrafterLP-ItemSelling
	# hooks its sell button into the discard button, so keep that one visible.
	for member in ["_combine_button", "_upgrade_button"]:
		var button = get(member)
		if button is Button and is_instance_valid(button):
			button.hide()
			button.focus_mode = Control.FOCUS_NONE
	var discard = get("_discard_button")
	if discard is Button and is_instance_valid(discard) and not _is_sell_mod_present():
		discard.hide()
		discard.focus_mode = Control.FOCUS_NONE


func _is_sell_mod_present() -> bool:
	if _sell_mod_checked:
		return _sell_mod_present
	_sell_mod_checked = true
	var store = get_node_or_null("/root/ModLoaderStore")
	if store == null or not ("mod_data" in store):
		return false
	var mod_data = store.get("mod_data")
	_sell_mod_present = mod_data is Dictionary and mod_data.has("RobocrafterLP-ItemSelling")
	return _sell_mod_present


func _update_trade_button_states() -> void:
	var item_data = get("_item_data")
	var own_index = player_index

	for target_index in _trade_buttons.keys():
		var trade_button: Button = _trade_buttons[target_index]
		if not is_instance_valid(trade_button):
			_trade_buttons.erase(target_index)
			continue
		if target_index == own_index or target_index >= RunData.get_player_count():
			trade_button.hide()
			trade_button.focus_mode = Control.FOCUS_NONE
			continue

		var can_trade := _can_trade_to(item_data, target_index)
		trade_button.visible = _is_tradeable(item_data)
		trade_button.disabled = not can_trade
		trade_button.focus_mode = Control.FOCUS_ALL if can_trade else Control.FOCUS_NONE
		trade_button.modulate = Color(1, 1, 1, 1) if can_trade else Color(0.5, 0.5, 0.5, 1)


func _can_trade_to(item_data, target_player_index: int) -> bool:
	if item_data is WeaponData:
		return _can_weapon_be_received(item_data, target_player_index)
	if item_data is ItemData:
		if not RunData.is_can_trade_item(item_data, target_player_index):
			return false
		return _can_item_be_received(item_data, target_player_index)
	return false


func _can_item_be_received(item_data: ItemData, target_player_index: int) -> bool:
	var remaining = RunData.get_remaining_max_nb_item(item_data, target_player_index)
	return remaining > 0 or remaining == -1


# ---------------------------------------------------------------- focus wiring
# Own trade buttons only. Native focus neighbours are never overwritten
# permanently; the two temporary patches are saved and restored.

func _get_focusable_trade_buttons() -> Array:
	var buttons := []
	for trade_button in _trade_buttons.values():
		if is_instance_valid(trade_button) and trade_button.visible and not trade_button.disabled:
			buttons.push_back(trade_button)
	return buttons


func _wire_weapon_trade_focus() -> void:
	# Linear open chain: first trade button is reached from the closest focusable
	# control above, the last one hands over to cancel. Everything else is left
	# to the native baked chain so Mechanize stays fully reachable.
	var focus_buttons = _get_focusable_trade_buttons()
	if focus_buttons.empty():
		_restore_native_focus()
		return

	for i in focus_buttons.size():
		var button: Button = focus_buttons[i]
		button.focus_neighbour_top = NodePath()
		button.focus_neighbour_bottom = NodePath()
		button.focus_previous = NodePath()
		button.focus_next = NodePath()
		if i > 0:
			button.focus_neighbour_top = button.get_path_to(focus_buttons[i - 1])
			button.focus_previous = button.get_path_to(focus_buttons[i - 1])
		if i < focus_buttons.size() - 1:
			button.focus_neighbour_bottom = button.get_path_to(focus_buttons[i + 1])
			button.focus_next = button.get_path_to(focus_buttons[i + 1])
		button.focus_neighbour_left = NodePath(".")
		button.focus_neighbour_right = NodePath(".")

	var cancel = get("_cancel_button")
	if cancel is Button and cancel.visible:
		_patch_cancel_focus_top(focus_buttons[focus_buttons.size() - 1])
		# Deterministic handover: last trade button down -> cancel.
		focus_buttons[focus_buttons.size() - 1].focus_neighbour_bottom = focus_buttons[focus_buttons.size() - 1].get_path_to(cancel)
	_patch_above_button_bottom(focus_buttons[0])


func _wire_item_trade_focus() -> void:
	# Item mode manages every visible button itself: closed loop over the trade
	# buttons plus cancel.
	var focus_buttons = _get_focusable_trade_buttons()
	if focus_buttons.empty():
		_restore_native_focus()
		return

	var buttons = focus_buttons.duplicate()
	var cancel = get("_cancel_button")
	var cancel_appended := false
	if cancel is Button and cancel.visible:
		buttons.push_back(cancel)
		cancel_appended = true

	for i in buttons.size():
		var button: Button = buttons[i]
		var previous_button: Button = buttons[(i - 1 + buttons.size()) % buttons.size()]
		var next_button: Button = buttons[(i + 1) % buttons.size()]
		if _trade_buttons.values().has(button):
			button.focus_neighbour_top = button.get_path_to(previous_button)
			button.focus_neighbour_bottom = button.get_path_to(next_button)
			button.focus_neighbour_left = NodePath(".")
			button.focus_neighbour_right = NodePath(".")
			button.focus_previous = button.get_path_to(previous_button)
			button.focus_next = button.get_path_to(next_button)

	if cancel_appended:
		_patch_cancel_focus_top(buttons[buttons.size() - 2])


func _patch_cancel_focus_top(last_trade_button: Button) -> void:
	var cancel = get("_cancel_button")
	if not (cancel is Button) or last_trade_button == null or not is_instance_valid(last_trade_button):
		return
	if not _cancel_top_patched:
		_vanilla_cancel_top = cancel.focus_neighbour_top
		_cancel_top_patched = true
	cancel.focus_neighbour_top = cancel.get_path_to(last_trade_button)


func _patch_above_button_bottom(first_trade_button: Button) -> void:
	if first_trade_button == null or not is_instance_valid(first_trade_button):
		return
	var parent = first_trade_button.get_parent()
	if parent == null:
		return
	var above: Control = null
	for i in range(first_trade_button.get_index() - 1, -1, -1):
		var child = parent.get_child(i)
		if child is Control and is_instance_valid(child) and child.visible and child.focus_mode != Control.FOCUS_NONE:
			above = child
			break
	if above == null:
		return
	# The control above can change with combine/mechanize visibility: restore the
	# old patch first, then save and apply the new one.
	if _above_bottom_patched:
		var previous = get_node_or_null(_above_button_path)
		if previous is Control:
			previous.focus_neighbour_bottom = _vanilla_above_bottom
	_vanilla_above_bottom = above.focus_neighbour_bottom
	_above_button_path = get_path_to(above)
	_above_bottom_patched = true
	above.focus_neighbour_bottom = above.get_path_to(first_trade_button)
	first_trade_button.focus_neighbour_top = first_trade_button.get_path_to(above)


func _restore_native_focus() -> void:
	if _cancel_top_patched:
		var cancel = get("_cancel_button")
		if cancel is Button:
			cancel.focus_neighbour_top = _vanilla_cancel_top
		_cancel_top_patched = false
	if _above_bottom_patched:
		var previous = get_node_or_null(_above_button_path)
		if previous is Control:
			previous.focus_neighbour_bottom = _vanilla_above_bottom
		_above_bottom_patched = false


func _refresh_trade_buttons() -> void:
	if not is_inside_tree() or not is_instance_valid(self):
		return
	if not _is_coop():
		return
	var item_data = get("_item_data")
	if _is_tradeable(item_data):
		call_deferred("_update_button_visibilities")


# ---------------------------------------------------------------- trade trigger

func _on_TradeButton_pressed_coop(to_player_index: int) -> void:
	var trade_button = _trade_buttons.get(to_player_index)
	if trade_button is Button and trade_button.disabled:
		return

	var item_data = get("_item_data")
	if item_data == null:
		return

	# Dual channel: emit the signal for other mods; if nobody listens, the
	# transfer is executed right here.
	if item_data is WeaponData:
		if get_signal_connection_list("weapon_trade_button_pressed_coop").empty():
			_execute_trade(item_data, to_player_index)
		else:
			emit_signal("weapon_trade_button_pressed_coop", item_data, player_index, to_player_index)
	elif item_data is ItemData:
		if get_signal_connection_list("item_trade_button_pressed_coop").empty():
			_execute_trade(item_data, to_player_index)
		else:
			emit_signal("item_trade_button_pressed_coop", item_data, player_index, to_player_index)


# ---------------------------------------------------------------- weapon eligibility
# Same semantics as the original mod's _can_weapon_be_bought, but with the int
# effect keys required since game 1.1 (get_player_effect(key: int, ...)).

func _can_weapon_be_received(weapon_data: WeaponData, player_index: int) -> bool:
	var min_weapon_tier = RunData.get_player_effect(Keys.min_weapon_tier_hash, player_index)
	var max_weapon_tier = RunData.get_player_effect(Keys.max_weapon_tier_hash, player_index)
	var no_melee_weapons = RunData.get_player_effect_bool(Keys.no_melee_weapons_hash, player_index)
	var no_ranged_weapons = RunData.get_player_effect_bool(Keys.no_ranged_weapons_hash, player_index)
	var no_duplicate_weapons = RunData.get_player_effect_bool(Keys.no_duplicate_weapons_hash, player_index)
	var lock_current_weapons = RunData.get_player_effect_bool(Keys.lock_current_weapons_hash, player_index)

	var weapon_type = weapon_data.type
	var weapons = RunData.get_player_weapons(player_index)
	var weapon_slot_available: bool = RunData.has_weapon_slot_available(weapon_data, player_index)

	var player_has_weapon := false
	for weapon in weapons:
		if weapon.my_id == weapon_data.my_id:
			player_has_weapon = true
			break

	var player_has_weapon_family := false
	if weapon_data.weapon_id in RunData.get_unique_weapon_ids(player_index):
		player_has_weapon_family = true

	if weapon_data.tier > max_weapon_tier or weapon_data.tier < min_weapon_tier:
		return false

	if no_melee_weapons and weapon_type == WeaponType.MELEE:
		return false

	if no_ranged_weapons and weapon_type == WeaponType.RANGED:
		return false

	if lock_current_weapons and not weapon_slot_available:
		return false

	if player_has_weapon and not weapon_slot_available and weapon_data.upgrades_into != null and weapon_data.upgrades_into.tier <= max_weapon_tier:
		return true

	if no_duplicate_weapons and player_has_weapon_family:
		return false

	return weapon_slot_available


# ---------------------------------------------------------------- transfer

func _execute_trade(item_data, to_player_index: int) -> void:
	if item_data == null:
		return
	var own_index = player_index
	if not _is_valid_trade_target(own_index, to_player_index):
		return
	if not _can_trade_to(item_data, to_player_index):
		ModLoaderLog.info("trade: target P%d cannot receive '%s', aborted." % [to_player_index + 1, item_data.my_id], LOG_NAME)
		return

	var is_weapon := item_data is WeaponData

	# Popup/focus cleanup: reset_focus is the game's own cancel/combine/recycle
	# finisher and hides the popup for the owning player.
	var shop = _find_ancestor("_ancestor_is_shop")
	var popup_manager = shop.get("_popup_manager") if shop != null else null
	if popup_manager != null and popup_manager.has_method("reset_focus"):
		popup_manager.reset_focus(own_index)
	var own_container = _get_player_container(own_index)
	if own_container != null and own_container.has_method("on_hide_focused_inventory_popup"):
		own_container.on_hide_focused_inventory_popup()
	_clear_player_focus(own_index)

	# Remember focus positions for both players, restore after the transfer.
	var source_gear = own_container.get("player_gear_container") if own_container != null else null
	if source_gear != null and not is_instance_valid(source_gear):
		source_gear = null
	var source_focus_index = _get_inventory_element_index(_elements_of(source_gear, is_weapon), item_data)

	var transfer_ok := false
	if is_weapon:
		transfer_ok = _transfer_weapon(item_data, own_index, to_player_index)
	else:
		transfer_ok = _transfer_item(item_data, own_index, to_player_index)
	if not transfer_ok:
		return

	_refresh_after_trade(own_index, to_player_index, is_weapon)

	if source_gear != null:
		call_deferred("_restore_focus_after_trade", own_index, source_focus_index, is_weapon)

	_play_trade_sound()


func _is_valid_trade_target(source_player_index: int, target_player_index: int) -> bool:
	var player_count = RunData.get_player_count()
	if player_count < 2:
		return false
	if source_player_index < 0 or source_player_index >= player_count:
		return false
	if target_player_index < 0 or target_player_index >= player_count:
		return false
	return source_player_index != target_player_index


func _refresh_after_trade(from_player_index: int, to_player_index: int, is_weapon: bool) -> void:
	# Target player: gear + stats + focus restore.
	var target_container = _get_player_container(to_player_index)
	var target_gear = target_container.get("player_gear_container") if target_container != null else null
	if target_gear != null and not is_instance_valid(target_gear):
		target_gear = null
	if target_gear != null:
		var target_focus_index = _get_player_inventory_focus_index(to_player_index, _elements_of(target_gear, is_weapon))
		if target_focus_index != -1:
			_clear_player_focus(to_player_index)
		if is_weapon and target_gear.has_method("set_weapons_data"):
			target_gear.set_weapons_data(RunData.get_player_weapons(to_player_index))
		elif not is_weapon and target_gear.has_method("set_items_data"):
			target_gear.set_items_data(RunData.get_player_items(to_player_index))
		if target_focus_index != -1:
			call_deferred("_restore_focus_after_trade", to_player_index, target_focus_index, is_weapon)
	if target_container != null and target_container.has_method("update_stats"):
		target_container.update_stats()

	# Source player: gear + stats.
	var from_container = _get_player_container(from_player_index)
	var from_gear = from_container.get("player_gear_container") if from_container != null else null
	if from_gear != null and not is_instance_valid(from_gear):
		from_gear = null
	if from_gear != null:
		if is_weapon and from_gear.has_method("set_weapons_data"):
			from_gear.set_weapons_data(RunData.get_player_weapons(from_player_index))
		elif not is_weapon and from_gear.has_method("set_items_data"):
			from_gear.set_items_data(RunData.get_player_items(from_player_index))
	if from_container != null and from_container.has_method("update_stats"):
		from_container.update_stats()

	# Shop shelves depend on owned items (buy states, duplicates): reload both.
	for container in [from_container, target_container]:
		if container == null:
			continue
		var shop_items = container.get("shop_items_container")
		if shop_items != null and shop_items.has_method("reload_shop_items"):
			shop_items.reload_shop_items()


func _transfer_weapon(weapon: WeaponData, from_player_index: int, to_player_index: int) -> bool:
	if not (RunData.has_method("remove_weapon") and RunData.has_method("add_weapon")):
		ModLoaderLog.error("trade: RunData.remove_weapon/add_weapon unavailable. Aborted.", LOG_NAME)
		return false
	if RunData.has_method("player_has_weapon_slots") and not RunData.player_has_weapon_slots(to_player_index):
		ModLoaderLog.info("trade: target P%d weapon slots full, aborted." % (to_player_index + 1), LOG_NAME)
		return false

	# ProjectileEffect guard: remove_weapon unapplies effects; for projectile
	# effects whose tracked value is <= the effect value, unapply would divide by
	# zero. Temporarily detach them and clear the source player's leftover data.
	var dangerous := []
	var safe_effects := []
	for effect in weapon.effects:
		if effect is ProjectileEffect:
			var tracked_values = RunData.get_player_effect(effect.key_hash, from_player_index)
			if not tracked_values.empty() and tracked_values[0] <= effect.value:
				dangerous.append(effect)
				continue
		safe_effects.append(effect)

	var original_effects = weapon.effects
	weapon.effects = safe_effects
	RunData.remove_weapon(weapon, from_player_index)
	weapon.effects = original_effects
	for effect in dangerous:
		var tracked_values = RunData.get_player_effect(effect.key_hash, from_player_index)
		if not tracked_values.empty():
			tracked_values.resize(0)

	# add_weapon duplicates internally; meca_power/meca_rank travel with the copy.
	RunData.add_weapon(weapon, to_player_index)

	ModLoaderLog.info("trade: weapon '%s' P%d -> P%d ok" % [weapon.my_id, from_player_index + 1, to_player_index + 1], LOG_NAME)
	return true


func _transfer_item(item_data: ItemData, from_player_index: int, to_player_index: int) -> bool:
	if not (RunData.has_method("remove_item") and RunData.has_method("add_item")):
		ModLoaderLog.error("trade: RunData.remove_item/add_item unavailable. Aborted.", LOG_NAME)
		return false

	# Same ProjectileEffect guard as the weapon path.
	var dangerous := []
	var safe_effects := []
	for effect in item_data.effects:
		if effect is ProjectileEffect:
			var tracked_values = RunData.get_player_effect(effect.key_hash, from_player_index)
			if not tracked_values.empty() and tracked_values[0] <= effect.value:
				dangerous.append(effect)
				continue
		safe_effects.append(effect)

	var original_effects = item_data.effects
	item_data.effects = safe_effects
	RunData.remove_item(item_data, from_player_index)
	item_data.effects = original_effects
	for effect in dangerous:
		var tracked_values = RunData.get_player_effect(effect.key_hash, from_player_index)
		if not tracked_values.empty():
			tracked_values.resize(0)

	RunData.add_item(item_data, to_player_index)

	# remove_item_displayed does not restore appearances displaced by higher
	# priority items: rebuild the source player's look from its item list.
	_rebuild_appearances(from_player_index)

	ModLoaderLog.info("trade: item '%s' P%d -> P%d ok" % [item_data.my_id, from_player_index + 1, to_player_index + 1], LOG_NAME)
	return true


func _rebuild_appearances(player_index: int) -> void:
	if not (RunData.has_method("add_item_displayed") and RunData.get("players_data") != null):
		return
	var player_data = RunData.players_data[player_index]
	if player_data == null:
		return
	player_data.appearances.clear()
	for item in player_data.items:
		RunData.add_item_displayed(item, player_index)


# ---------------------------------------------------------------- ancestor probing
# CoopShopPlayerContainer (player_gear_container/shop_items_container/update_stats/
# on_hide_focused_inventory_popup) and CoopShop (_get_coop_player_container/
# _popup_manager/recycle_sounds) are NOT extended; they are found by member probe.

func _find_ancestor(checker: String) -> Node:
	var node = get_parent()
	while node != null:
		if node != self and call(checker, node):
			return node
		node = node.get_parent()
	return null


func _ancestor_is_player_container(node) -> bool:
	return node.get("player_gear_container") != null and node.get("item_popup") != null


func _ancestor_is_shop(node) -> bool:
	return node.has_method("_get_coop_player_container")


func _get_player_container(player_index: int):
	if player_index == get("player_index"):
		return _find_ancestor("_ancestor_is_player_container")
	var shop = _find_ancestor("_ancestor_is_shop")
	if shop != null:
		var container = shop.call("_get_coop_player_container", player_index)
		if container != null and is_instance_valid(container):
			return container
	return null


# ---------------------------------------------------------------- focus/sound helpers

func _elements_of(gear, is_weapon: bool):
	if gear == null or not is_instance_valid(gear):
		return null
	var inventory_container = gear.get("weapons_container") if is_weapon else gear.get("items_container")
	if inventory_container == null:
		return null
	return inventory_container.get("_elements")


func _get_inventory_element_index(inventory, item_data) -> int:
	if inventory == null:
		return 0
	for index in inventory.get_child_count():
		var element = inventory.get_child(index)
		if element != null and element.item == item_data:
			return index
	return 0


func _get_player_inventory_focus_index(player_index: int, inventory) -> int:
	if inventory == null:
		return -1
	if not Utils.has_method("get_focus_emulator"):
		return -1
	var focus_emulator = Utils.get_focus_emulator(player_index)
	if focus_emulator == null or focus_emulator.get("focused_control") == null:
		return -1
	var focused_control = focus_emulator.focused_control
	if not inventory.is_a_parent_of(focused_control):
		return -1
	return focused_control.get_index()


func _clear_player_focus(player_index: int) -> void:
	if not Utils.has_method("get_focus_emulator"):
		return
	var focus_emulator = Utils.get_focus_emulator(player_index)
	if focus_emulator != null:
		focus_emulator.set("focused_control", null)


func _restore_focus_after_trade(player_index: int, preferred_index: int, is_weapon: bool) -> void:
	var container = _get_player_container(player_index)
	var gear = container.get("player_gear_container") if container != null else null
	if gear != null:
		var inventory_container = gear.get("weapons_container") if is_weapon else gear.get("items_container")
		if inventory_container != null and inventory_container.has_method("get_element_count"):
			var element_count = inventory_container.get_element_count()
			if element_count > 0:
				var index = int(clamp(preferred_index, 0, element_count - 1))
				var element = inventory_container.get_element(index)
				if element != null and Utils.has_method("focus_player_control"):
					Utils.focus_player_control(element, player_index)
					return

	# Fallback: focus the player's Go button so focus never dangles.
	if container != null and container.get("go_button") != null and Utils.has_method("focus_player_control"):
		Utils.focus_player_control(container.go_button, player_index)


func _play_trade_sound() -> void:
	var shop = _find_ancestor("_ancestor_is_shop")
	var sounds = shop.get("recycle_sounds") if shop != null else null
	if sounds == null or not (sounds is Array) or sounds.empty():
		return
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager == null or not Utils.has_method("get_rand_element"):
		return
	if sound_manager.has_method("play"):
		sound_manager.play(Utils.get_rand_element(sounds), 0, 0.1, true)
