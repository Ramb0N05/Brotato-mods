extends ShopItemsContainer

# RobocrafterLP-Trade - shop items container extension for Brotato 1.2.0.1
#
# 1.3.5: shop buy guard for limited items. Trades and crate gifts now use the
# plain owned-count limit check (the old 1.3.2 shelf rule that blocked
# receiving a limited item while the receiver's shop offered a copy is gone).
# Vanilla never re-checks max_nb at purchase time (base_shop
# .on_shop_item_bought deducts materials FIRST and then adds the item
# unconditionally), so this extension blocks BUYING (and stealing) a limited
# shelf copy while the player is already at max_nb. The guard mirrors the
# vanilla insufficient-currency guard: the click is swallowed BEFORE
# shop_item_bought / shop_item_stolen is emitted, so no materials are
# deducted and the shelf copy stays where it is.

const LOG_NAME := "RobocrafterLP-Trade:ShopItemsContainer"


func on_shop_item_buy_button_pressed(shop_item) -> void:
	if _is_item_blocked_by_limit(shop_item):
		return
	.on_shop_item_buy_button_pressed(shop_item)


func on_shop_item_steal_button_pressed(shop_item) -> void:
	if _is_item_blocked_by_limit(shop_item):
		return
	.on_shop_item_steal_button_pressed(shop_item)


func _is_item_blocked_by_limit(shop_item) -> bool:
	# True when shop_item is a limited ITEM the player already owns max_nb
	# copies of (possible after receiving a copy via trade/crate gift while
	# the shelf still offers one). Weapons are never limited by max_nb.
	if shop_item == null:
		return false
	var item_data = shop_item.get("item_data")
	if not (item_data is ItemData):
		return false
	if item_data is WeaponData:
		return false
	if item_data.max_nb == -1:
		return false
	if RunData.get_remaining_max_nb_item(item_data, player_index) > 0:
		return false
	ModLoaderLog.info("trade: shop buy blocked: '%s' over max_nb for P%d" % [item_data.my_id, player_index], LOG_NAME)
	emit_signal("shop_item_insufficient_currency", shop_item)
	return true
