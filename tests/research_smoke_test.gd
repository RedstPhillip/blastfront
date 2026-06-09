extends Node

var _test_player: Player = null


func _ready() -> void:
	add_to_group(GameSettings.GAME_WORLD_GROUP)
	var original_marks: Dictionary = ResearchManager._local_marks.duplicate()
	var original_points: int = ResearchManager.research_points
	ResearchManager._local_marks.clear()
	ResearchManager.research_points = 100

	var definitions: Array[Dictionary] = ResearchManager.get_all_definitions()
	assert(definitions.size() == 18)
	assert(ResearchManager.is_research_available(ResearchManager.RECYCLING))
	assert(not ResearchManager.is_research_available(ResearchManager.DASHING))
	assert(not ResearchManager.is_research_available(ResearchManager.TIME_CONTROL))
	assert(not ResearchManager.is_research_available(ResearchManager.FASTER_CAPTURE))

	assert(ResearchManager.can_purchase(ResearchManager.RECYCLING))
	assert(not ResearchManager.can_purchase(ResearchManager.BLUEPRINT_STORAGE))
	ResearchManager._local_marks[str(ResearchManager.RECYCLING)] = 1
	assert(ResearchManager.can_purchase(ResearchManager.BLUEPRINT_STORAGE))
	assert(is_equal_approx(ResearchManager.get_recycling_refund_ratio(), 0.5))

	ResearchManager._local_marks[str(ResearchManager.BLUEPRINT_STORAGE)] = 3
	RoundRewardInventory._on_research_changed()
	assert(ResearchManager.get_blueprint_slot_count() == 4)
	assert(RoundRewardInventory.saved_rewards.size() == 4)

	ResearchManager._local_marks[str(ResearchManager.COIN_INTEREST)] = 3
	ResearchManager._local_marks[str(ResearchManager.CONDITION_WEAR)] = 3
	ResearchManager._local_marks[str(ResearchManager.UPGRADE_DISCOUNT)] = 3
	ResearchManager._local_marks[str(ResearchManager.BONUS_MARK)] = 3
	ResearchManager._local_marks[str(ResearchManager.LUCK)] = 3
	ResearchManager._local_marks[str(ResearchManager.RESEARCH_YIELD)] = 3
	assert(is_equal_approx(ResearchManager.get_coin_multiplier(), 1.15))
	assert(is_zero_approx(ResearchManager.get_condition_wear_multiplier()))
	assert(is_equal_approx(ResearchManager.get_upgrade_cost_multiplier(), 0.65))
	assert(is_equal_approx(ResearchManager.get_bonus_mark_chance(), 0.26))
	assert(ResearchManager.get_luck_level() == 3)
	assert(is_equal_approx(ResearchManager.get_research_point_multiplier(), 1.65))

	ResearchManager._local_marks[str(ResearchManager.LIFE_STEAL)] = 3
	ResearchManager._local_marks[str(ResearchManager.RAGE)] = 3
	ResearchManager._local_marks[str(ResearchManager.PASSIVE_HEALING)] = 3
	ResearchManager._local_marks[str(ResearchManager.PHOENIX)] = 1
	assert(is_equal_approx(ResearchManager.get_life_steal_ratio(), 0.16))
	assert(is_equal_approx(ResearchManager.get_rage_damage_multiplier(), 1.5))
	assert(is_equal_approx(ResearchManager.get_passive_healing_cap(), 1.0))
	assert(is_equal_approx(ResearchManager.get_passive_healing_rate(), 4.0))
	assert(ResearchManager.has_phoenix())

	var base_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	base_rng.seed = 8128
	var lucky_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	lucky_rng.seed = 8128
	var base_condition: float = ItemCondition.roll(base_rng)
	var lucky_condition: float = ItemCondition.roll_with_luck(lucky_rng, 3)
	assert(lucky_condition >= base_condition)

	var research_page_scene: PackedScene = load("res://scenes/ui/research/research_page.tscn") as PackedScene
	var research_page: Control = research_page_scene.instantiate() as Control
	add_child(research_page)
	await get_tree().process_frame
	assert(research_page.find_children("*", "ResearchNodeButton", true, false).size() == 18)
	research_page.queue_free()

	var loadout_page_scene: PackedScene = load("res://scenes/ui/loadout/loadout_page.tscn") as PackedScene
	var loadout_page: Control = loadout_page_scene.instantiate() as Control
	add_child(loadout_page)
	await get_tree().process_frame
	var offer_grid: GridContainer = loadout_page.find_child("OfferGrid", true, false) as GridContainer
	var recycler: RecyclerDropTarget = loadout_page.find_child("RecyclerDropTarget", true, false) as RecyclerDropTarget
	assert(offer_grid != null and offer_grid.visible)
	assert(offer_grid.columns == 2)
	assert(recycler != null and recycler.visible)
	for slot_name in ["SavedRewardOne", "SavedRewardTwo", "SavedRewardThree", "SavedRewardFour"]:
		var saved_slot: Control = loadout_page.find_child(slot_name, true, false) as Control
		assert(saved_slot != null and saved_slot.visible)

	ResearchManager._local_marks.erase(str(ResearchManager.BLUEPRINT_STORAGE))
	ResearchManager._local_marks.erase(str(ResearchManager.RECYCLING))
	ResearchManager.research_changed.emit()
	await get_tree().process_frame
	for slot_name in ["SavedRewardOne", "SavedRewardTwo", "SavedRewardThree", "SavedRewardFour"]:
		var saved_slot: Control = loadout_page.find_child(slot_name, true, false) as Control
		assert(saved_slot != null and not saved_slot.visible)
	assert(not recycler.visible)
	loadout_page.queue_free()

	var intermission_scene: PackedScene = load("res://scenes/menus/intermission_menu.tscn") as PackedScene
	var intermission: Control = intermission_scene.instantiate() as Control
	add_child(intermission)
	await get_tree().process_frame
	intermission.call("_set_page", 1)
	var intermission_research: Control = intermission.find_child("ResearchPage", true, false) as Control
	var intermission_status: Control = intermission.find_child("StatusPage", true, false) as Control
	var intermission_loadout: Control = intermission.find_child("LoadoutPage", true, false) as Control
	assert(intermission_research.visible)
	assert(not intermission_status.visible)
	assert(not intermission_loadout.visible)
	intermission.call("_set_page", -1)
	assert(intermission_loadout.visible)
	assert(not intermission_research.visible)
	intermission.queue_free()

	ResearchManager._local_marks[str(ResearchManager.RAGE)] = 3
	ResearchManager._local_marks[str(ResearchManager.LIFE_STEAL)] = 3
	ResearchManager._local_marks[str(ResearchManager.PHOENIX)] = 1
	var player_scene: PackedScene = load("res://scenes/player/player.tscn") as PackedScene
	var player: Player = player_scene.instantiate() as Player
	player.player_slot = GameSettings.PLAYER_ONE_SLOT
	_test_player = player
	add_child(player)
	await get_tree().process_frame
	var gun: Node = player.get_node("Gun")
	player.health_component.health = 20
	assert(int(gun.call("_get_modified_damage")) == 15)
	player.health_component.health = 50
	assert(ResearchManager.apply_local_life_steal(player.player_slot, 10) == 2)
	assert(player.health_component.health == 52)
	player.reset_research_round_state()
	player.health_component.health = 10
	player.health_component.damage(20)
	assert(player.health_component.health == 40)
	assert(not player.is_eliminated())
	player.queue_free()
	_test_player = null

	ResearchManager._local_marks[str(ResearchManager.RECYCLING)] = 1
	var original_offers: Array[Dictionary] = RoundRewardInventory.offers.duplicate(true)
	var original_balances: Dictionary = OnlineMatch.coin_balances.duplicate()
	OnlineMatch.coin_balances[NetworkSession.local_player_slot] = 0
	RoundRewardInventory.offers = [{"price": 10}]
	assert(RoundRewardInventory.recycle_reward(RoundRewardInventory.SOURCE_OFFER, 0) == 5)
	assert(OnlineMatch.get_local_coin_balance() == 5)
	assert(RoundRewardInventory.get_offer(0).is_empty())
	RoundRewardInventory.offers = original_offers
	OnlineMatch.coin_balances = original_balances

	ResearchManager._local_marks[str(ResearchManager.UPGRADE_DISCOUNT)] = 3
	assert(ExtensionInventory.get_merge_cost_for_next_mark(3) == 13)

	ResearchManager._local_marks = original_marks
	ResearchManager.research_points = original_points
	RoundRewardInventory._on_research_changed()
	await get_tree().process_frame
	await get_tree().process_frame
	print("RESEARCH_SMOKE_TEST_OK")
	get_tree().create_timer(1.0).timeout.connect(_finish_test)


func get_player_by_slot(slot: int) -> Player:
	if _test_player != null and _test_player.player_slot == slot:
		return _test_player
	return null


func _finish_test() -> void:
	get_tree().quit()
