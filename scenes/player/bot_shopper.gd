class_name BotShopper
extends RefCounted

## Spends the bot's coins between sets in shop-enabled duels. It sees its own fresh round offers,
## prefers filling empty equipment slots, then clear upgrades, and equips what it buys.
## Harder bots shop more and pick better; easy bots buy a single affordable item at random.

const META_VALUE: StringName = &"bot_value"
const UPGRADE_MARGIN: int = 3


static func shop(slot: int, difficulty: int) -> void:
	var budget: int = OnlineMatch.get_coin_balance(slot)
	if budget < GameSettings.SHOP_MIN_PRICE:
		return
	var offers: Array[Dictionary] = RoundRewardInventory.generate_offers_for_bot()
	var max_purchases: int = 1
	match difficulty:
		BotBrain.Difficulty.NORMAL:
			max_purchases = 2
		BotBrain.Difficulty.HARD:
			max_purchases = 3
	if difficulty == BotBrain.Difficulty.EASY:
		offers.shuffle()
	else:
		offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _desire(slot, a) > _desire(slot, b))
	var purchases: int = 0
	for offer in offers:
		if purchases >= max_purchases:
			break
		var price: int = int(offer.get("price", 0))
		if price <= 0 or price > budget or _desire(slot, offer) <= 0.0:
			continue
		if not OnlineMatch.spend_coins_for_slot(slot, price):
			continue
		budget -= price
		purchases += 1
		_equip(slot, offer, price)


## How much an offer is worth to the bot right now: empty slots first, then upgrades over what it wears.
static func _desire(slot: int, offer: Dictionary) -> float:
	var price: int = int(offer.get("price", 0))
	var current_value: int = _current_value(slot, offer)
	if current_value < 0:
		return 100.0 + float(price)
	if price < current_value + UPGRADE_MARGIN:
		return 0.0
	return float(price - current_value)


## -1 when the matching equipment slot is empty, else the value of the equipped item.
static func _current_value(slot: int, offer: Dictionary) -> int:
	var item_variant: Variant = offer.get("item", null)
	if StringName(str(offer.get("type", ""))) == RoundRewardInventory.REWARD_EXTENSION:
		var extension: WeaponExtensionItem = item_variant as WeaponExtensionItem
		if extension == null:
			return 10000
		var equipped: WeaponExtensionItem = ExtensionInventory.get_equipped_item_for_player(slot, extension.get_slot())
		return -1 if equipped == null else int(equipped.get_meta(META_VALUE, GameSettings.SHOP_MIN_PRICE))
	var armor: ArmorItemData = item_variant as ArmorItemData
	if armor == null:
		return 10000
	var worn: ArmorItemData = ArmorInventory.get_equipped_item_for_player(slot, armor.category)
	return -1 if worn == null else int(worn.get_meta(META_VALUE, GameSettings.SHOP_MIN_PRICE))


static func _equip(slot: int, offer: Dictionary, price: int) -> void:
	var item_variant: Variant = offer.get("item", null)
	if StringName(str(offer.get("type", ""))) == RoundRewardInventory.REWARD_EXTENSION:
		var extension: WeaponExtensionItem = item_variant as WeaponExtensionItem
		if extension == null:
			return
		extension.set_meta(META_VALUE, price)
		if ExtensionInventory.add_item_for_player(slot, extension):
			ExtensionInventory.equip_item_for_player(slot, extension)
		return
	var armor: ArmorItemData = item_variant as ArmorItemData
	if armor == null:
		return
	armor.set_meta(META_VALUE, price)
	ArmorInventory.equip_for_player(slot, armor)
