extends "res://singletons/run_data.gd"

const RobocrafterLP_Trade = "RobocrafterLP-Trade"
const trade_items_over_limit_config = "TRADE_ITEMS_OVER_LIMIT"

var coop_trading_config: ModConfig
var is_trade_items_over_limit: bool = false


# Extended func's
func _ready():
	var ModsConfigInterface = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")

	if ModsConfigInterface != null:
		ModsConfigInterface.connect("setting_changed", self, "on_coop_trading_setting_changed")
		coop_trading_config = ModLoaderConfig.get_current_config(RobocrafterLP_Trade)
		
	if coop_trading_config != null and trade_items_over_limit_config in coop_trading_config.data:
		is_trade_items_over_limit = coop_trading_config.data[trade_items_over_limit_config]


# Custom func's
func on_coop_trading_setting_changed(setting_name, value, mod_name): # Yes, func is called that because some conflicts happen here
	var config = ModLoaderConfig.get_current_config(RobocrafterLP_Trade)

	if setting_name == trade_items_over_limit_config:
		is_trade_items_over_limit = value
		if config != null:
			config.data[trade_items_over_limit_config] = value

func is_can_trade_item(object_data, player_index: int) -> bool:
	if self.is_trade_items_over_limit:
		return true
	
	if object_data is ItemData:
		if self.get_remaining_max_nb_item(object_data, player_index) > 0 or self.get_remaining_max_nb_item(object_data, player_index) == -1:
			return true
		else:
			return false
	else:
		return false

# ---------------------------------------------------------------- shared trade rules
# Single source of truth for the tradeability rules, used by BOTH trade
# surfaces (since 1.3.3): the shop item popup (coop_item_popup.gd) and the
# crate-opening dialog (coop_upgrades_ui_player_container.gd).

# Items that must never change owner (special per-player mounting/balance,
# same list as the reference gift mod KD-AGiftforMyFosterSon minus item_lure,
# which is tradeable since 1.3.3 with its next-wave effect suppressed).
const TRADE_NO_TRADE_ITEM_IDS := ["item_celery_tea", "item_peacock", "item_hourglass"]

# One-shot effects that only apply on the next wave. Vanilla consumes and
# RESETS these effect values at wave start (wave_manager.gd / main.gd) without
# ever re-applying them from the still-owned item, so they fire once per
# acquisition. Unapplying such an effect after it was consumed corrupts the
# stored player value (e.g. hp_start_next_wave 200% = double start HP), so
# items carrying them are not tradeable ...
const TRADE_DEFERRED_NEXT_WAVE_KEYS := [
	"hp_start_next_wave",
	"extra_enemies_next_wave",
	"extra_loot_aliens_next_wave",
	"extra_elite_next_wave_chance",
	"gain_random_primary_stats_on_go_to_next_wave"
]

# ... EXCEPT these two, explicitly tradeable by design (1.3.3):
# - item_weird_ghost (Seltsamer Geist): trading arms the 1-HP-next-wave
#   trigger on the receiver and disarms the sender; trading the ghost back
#   and forth (ping-pong) is intended behaviour.
# - item_lure (Lockmittel): tradeable, but its extra_loot_aliens_next_wave
#   trigger never fires because of a trade (suppressed on both sides).
const TRADE_DEFERRED_EXEMPT_ITEM_IDS := ["item_weird_ghost", "item_lure"]


func is_item_trade_restricted(item_data) -> bool:
	# True for items that must never change owner. Weapons are never
	# restricted by this list (same as before 1.3.3).
	if item_data == null or not (item_data is ItemData):
		return false
	return item_data.my_id in TRADE_NO_TRADE_ITEM_IDS


func is_item_deferred_next_wave_blocked(item_data) -> bool:
	# True for items with one-shot next-wave effects (see above), except the
	# explicitly exempted ones. Vanilla weapons never carry these keys.
	if item_data == null:
		return false
	if item_data is ItemData and item_data.my_id in TRADE_DEFERRED_EXEMPT_ITEM_IDS:
		return false
	if item_data.get("effects") == null:
		return false
	for effect in item_data.effects:
		if effect.key in TRADE_DEFERRED_NEXT_WAVE_KEYS:
			return true
		if effect.custom_key == "stats_next_wave":
			return true
	return false


func get_locked_shop_item_count(item_data: ItemData, player_index: int) -> int:
	# Copies of item_data currently LOCKED on the player's shop shelf. Locked
	# items persist into the next shop phase and can still be bought there.
	# 1.3.5: no longer used for limit checks (transfers count owned copies
	# only; the shop buy guard blocks buying a locked shelf copy while the
	# player is at max_nb). Kept as a helper for future/debug use.
	var count := 0
	if item_data == null:
		return 0
	for locked_item in self.get_player_locked_shop_items(player_index):
		if locked_item is Array and locked_item.size() > 0 and locked_item[0] is ItemData and locked_item[0].my_id_hash == item_data.my_id_hash:
			count += 1
	return count
