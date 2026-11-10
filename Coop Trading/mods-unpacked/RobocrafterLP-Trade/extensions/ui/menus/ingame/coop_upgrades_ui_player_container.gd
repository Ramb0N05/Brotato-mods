extends CoopUpgradesUIPlayerContainer

signal item_trade_button_pressed(item_data)

# 1.3.3: give-buttons are gated per item now, mirroring the shop rules
# (RunData.is_item_trade_restricted / is_item_deferred_next_wave_blocked /
# limited-item checks incl. locked shelf copies). The press handler re-checks
# as a backstop because receiver state can change between waves.

var _trade_buttons := {}


func _ready()->void :
	var buttons = _take_button.get_parent().duplicate()
	_take_button.get_parent().get_parent().add_child(buttons)
	_take_button.get_parent().get_parent().move_child(buttons, _take_button.get_parent().get_index() + 1)
	for child in buttons.get_children():
		child.free()

	var player_count = RunData.get_player_count()
	for _player_index in player_count:
		if _player_index != player_index:
			var test = _take_button.get_stylebox("normal").duplicate()
			var button = _take_button.duplicate()
			button.text = "TRADE_GIVE_TO_PLAYER_BUTTON_%s" % str(_player_index + 1)
			button.name = "%%_p%s" % (_player_index + 1)
			button.disconnect("pressed", self, "_on_TakeButton_pressed")
			button.connect("pressed", self, "_on_item_trade_button_pressed" + str(_player_index + 1))
			button.set_script(preload("res://ui/menus/global/my_menu_button.gd"))
			button.add_stylebox_override("normal", test)
			buttons.add_child(button)
			_trade_buttons[_player_index] = button


func show_item(item_data: ItemParentData) -> void :
	.show_item(item_data)
	_update_trade_buttons_visibility()


func _update_trade_buttons_visibility() -> void :
	# Hide the give-buttons for items that must not change owner and for
	# limited items the target cannot receive (owned + locked copies count).
	if _trade_buttons.empty():
		return
	for target_index in _trade_buttons.keys():
		var button = _trade_buttons[target_index]
		if not is_instance_valid(button):
			continue
		button.visible = _can_give_item_to(_item_data, target_index)


func _can_give_item_to(item_data, to: int) -> bool:
	if RunData.get("is_trade_items_over_limit") == true:
		return true
	if not (item_data is ItemData):
		return false
	if RunData.is_item_trade_restricted(item_data):
		return false
	if RunData.is_item_deferred_next_wave_blocked(item_data):
		return false
	if item_data.max_nb != -1:
		if RunData.get_remaining_max_nb_item_with_locked(item_data, to) <= 0:
			return false
	return true


func _on_item_trade_button_pressed1() -> void:
	_on_item_trade_button_pressed(0)

func _on_item_trade_button_pressed2() -> void:
	_on_item_trade_button_pressed(1)

func _on_item_trade_button_pressed3() -> void:
	_on_item_trade_button_pressed(2)

func _on_item_trade_button_pressed4() -> void:
	_on_item_trade_button_pressed(3)

func _on_item_trade_button_pressed(to: int):
	if _button_pressed:return 
	_button_pressed = true
	_button_delay_timer.start()

	if !RunData.is_can_trade_item(_item_data, to) or !_can_give_item_to(_item_data, to):
		SoundManager.play(Utils.get_rand_element(Player.new().hurt_sounds), 0, 0.0, true)
		return

	# Lockmittel (item_lure): its extra_loot_aliens_next_wave trigger must not
	# fire because of the gift. The take signal below is processed
	# synchronously (main.gd on_item_box_take_button_pressed -> RunData.add_item),
	# so the receiver's value is armed by the time emit_signal returns.
	var lure_pre_value = null
	if _item_data is ItemData and _item_data.my_id == "item_lure":
		var to_effects = RunData.get_player_effects(to)
		if to_effects != null:
			lure_pre_value = to_effects[Keys.extra_loot_aliens_next_wave_hash]

	if _things_to_process_container:
		_things_to_process_container.consumables.remove_element(_consumable_data)
	emit_signal("item_trade_button_pressed", _item_data, to)

	if lure_pre_value != null:
		var to_effects = RunData.get_player_effects(to)
		if to_effects != null and to_effects[Keys.extra_loot_aliens_next_wave_hash] != lure_pre_value:
			to_effects[Keys.extra_loot_aliens_next_wave_hash] = lure_pre_value
			ModLoaderLog.info("crate trade: lure next-wave effect suppressed for P%d" % (to + 1), "RobocrafterLP-Trade:CoopUpgradesUIPlayerContainer")
