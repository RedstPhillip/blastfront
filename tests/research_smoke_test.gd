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
	assert(ResearchManager.is_research_available(ResearchManager.FASTER_CAPTURE))

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

	ResearchManager._local_marks[str(ResearchManager.FASTER_CAPTURE)] = 3
	ResearchManager._local_marks[str(ResearchManager.CAPTURE_BONUS)] = 3
	ResearchManager._local_marks[str(ResearchManager.CAPTURE_RADIUS)] = 3
	assert(is_equal_approx(ResearchManager.get_capture_time_multiplier(), 0.55))
	assert(is_equal_approx(ResearchManager.get_capture_radius(), GameSettings.AIRDROP_BASE_CAPTURE_RADIUS + 68.0))
	assert(ResearchManager.get_capture_research_reward() == 8)

	ResearchManager._local_marks[str(ResearchManager.LIFE_STEAL)] = 3
	ResearchManager._local_marks[str(ResearchManager.RAGE)] = 3
	ResearchManager._local_marks[str(ResearchManager.PASSIVE_HEALING)] = 3
	ResearchManager._local_marks[str(ResearchManager.PHOENIX)] = 1
	assert(is_equal_approx(ResearchManager.get_life_steal_ratio(), 0.16))
	assert(is_equal_approx(ResearchManager.get_rage_damage_multiplier(), 1.5))
	assert(is_equal_approx(ResearchManager.get_passive_healing_cap(), 1.0))
	assert(is_equal_approx(ResearchManager.get_passive_healing_rate(), 4.0))
	assert(ResearchManager.has_phoenix())
	await _verify_world_scene_contract()

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
	var research_nodes: Array[Node] = research_page.find_children("*", "ResearchNodeButton", true, false)
	assert(research_nodes.size() == 18)
	for research_node in research_nodes:
		var icon_texture: TextureRect = research_node.find_child("IconTexture", true, false) as TextureRect
		assert(icon_texture != null)
		assert(icon_texture.texture != null)
	research_page.queue_free()

	var loadout_page_scene: PackedScene = load("res://scenes/ui/loadout/loadout_page.tscn") as PackedScene
	RoundRewardInventory.prepare_for_round(1)
	var loadout_page: Control = loadout_page_scene.instantiate() as Control
	add_child(loadout_page)
	await get_tree().process_frame
	var offer_grid: GridContainer = loadout_page.find_child("OfferGrid", true, false) as GridContainer
	var recycler: RecyclerDropTarget = loadout_page.find_child("RecyclerDropTarget", true, false) as RecyclerDropTarget
	assert(offer_grid != null and offer_grid.visible)
	assert(offer_grid.columns == 2)
	assert(recycler != null and recycler.visible)
	assert(recycler.get_global_rect().end.y <= 690.0)
	for recycler_child in recycler.find_children("*", "Control", true, false):
		assert((recycler_child as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var recycle_payload: Dictionary = {
		"type": &"round_reward",
		"source_kind": RoundRewardInventory.SOURCE_OFFER,
		"source_index": 0,
	}
	assert(recycler._can_drop_data(Vector2.ZERO, recycle_payload))
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
	var intermission_quests: ResearchQuestPanel = intermission.find_child("QuestPanel", true, false) as ResearchQuestPanel
	assert(intermission_quests != null)
	assert(intermission_research.visible)
	assert(not intermission_status.visible)
	assert(not intermission_loadout.visible)
	intermission.call("_set_page", 0)
	await get_tree().process_frame
	var ready_card: PanelContainer = intermission.find_child("ReadyCard", true, false) as PanelContainer
	assert(ready_card != null)
	assert(intermission_quests.get_global_rect().end.y <= ready_card.get_global_rect().end.y + 1.0)
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

	var remote_player: Player = player_scene.instantiate() as Player
	add_child(remote_player)
	remote_player.configure_remote_control(GameSettings.PLAYER_TWO_SLOT)
	remote_player.apply_remote_block_state(true, Vector2.LEFT, 1.0)
	remote_player._update_block_timers(remote_player.block_duration * 2.0)
	assert(remote_player.is_blocking())
	remote_player.apply_remote_block_state(false, Vector2.LEFT, 0.0)
	remote_player._update_block_timers(0.1)
	var progressed_cooldown_ratio: float = remote_player.get_block_cooldown_ratio()
	assert(progressed_cooldown_ratio > 0.0)
	remote_player.apply_remote_block_state(false, Vector2.LEFT, 0.0)
	assert(remote_player.get_block_cooldown_ratio() >= progressed_cooldown_ratio)
	remote_player.queue_free()

	var status_parent: Node = Node.new()
	var status_manager: StatusEffectManager = StatusEffectManager.new()
	status_parent.add_child(status_manager)
	add_child(status_parent)
	var poison_test_data: Dictionary = {
		"duration": 3.0,
		"damage_per_tick": 3,
		"tick_count": 3,
		"tick_interval": 1.0,
	}
	status_manager.apply_effect(&"poison", poison_test_data)
	status_manager.apply_effect(&"poison", poison_test_data)
	assert(status_manager.get_active_count() == 1)
	status_parent.queue_free()

	var projectile_sync_script: Script = load("res://scenes/network/projectile_sync.gd") as Script
	var projectile_sync: Node = projectile_sync_script.new() as Node
	var balanced_poison: Dictionary = projectile_sync.call(
		"_get_balanced_status_effect_data",
		&"poison",
		{"damage_per_tick": 4, "tick_count": 4, "duration": 3.2},
		["poison_rounds_mk1", "shotgun_mk1"]
	)
	assert(int(balanced_poison.get("damage_per_tick", 0)) == 3)
	assert(int(balanced_poison.get("tick_count", 0)) == 3)
	projectile_sync.free()

	assert(ResearchQuestManager.get_definitions_for_tier(ResearchQuestManager.TIER_EASY).size() >= 5)
	assert(ResearchQuestManager.get_definitions_for_tier(ResearchQuestManager.TIER_MEDIUM).size() >= 5)
	assert(ResearchQuestManager.get_definitions_for_tier(ResearchQuestManager.TIER_HARD).size() >= 5)
	var easy_quest_definition: Dictionary = ResearchQuestManager.get_definitions_for_tier(
		ResearchQuestManager.TIER_EASY
	)[0]
	assert(str(easy_quest_definition.get("title", "")).contains(" "))
	assert(str(easy_quest_definition.get("description", "")).is_empty())
	ResearchQuestManager.reset_match()
	ResearchQuestManager.assign_quests_for_next_set()
	var assigned_quests: Array[Dictionary] = ResearchQuestManager.get_local_quests()
	assert(assigned_quests.size() == 3)
	assert(StringName(str(assigned_quests[0].get("tier", ""))) == ResearchQuestManager.TIER_EASY)
	assert(StringName(str(assigned_quests[1].get("tier", ""))) == ResearchQuestManager.TIER_MEDIUM)
	assert(StringName(str(assigned_quests[2].get("tier", ""))) == ResearchQuestManager.TIER_HARD)
	var quest_reward_start: int = ResearchManager.research_points
	ResearchQuestManager._assignments_by_slot[NetworkSession.local_player_slot] = [{
		"id": "jump_test",
		"title": "Jump Test",
		"description": "Test quest",
		"tier": str(ResearchQuestManager.TIER_EASY),
		"event": str(ResearchQuestManager.EVENT_JUMP),
		"target": 2.0,
		"reward": 1,
		"progress": 0.0,
		"completed": false,
		"failed": false,
	}]
	ResearchQuestManager._active_set_has_quests = true
	ResearchQuestManager._apply_progress(NetworkSession.local_player_slot, ResearchQuestManager.EVENT_JUMP, 1.0)
	ResearchQuestManager._apply_progress(NetworkSession.local_player_slot, ResearchQuestManager.EVENT_JUMP, 1.0)
	assert(ResearchManager.research_points == quest_reward_start + 2)
	ResearchQuestManager._last_awarded_by_slot[NetworkSession.local_player_slot] = 6
	ResearchQuestManager._active_set_has_quests = false
	ResearchQuestManager._previous_phase = GameSettings.MATCH_PHASE_KILL_BANNER
	ResearchQuestManager._on_phase_changed(GameSettings.MATCH_PHASE_INTERMISSION)
	assert(ResearchQuestManager.get_last_awarded_points() == 6)

	var airdrop_scene: PackedScene = load("res://scenes/objectives/airdrop_crate.tscn") as PackedScene
	var airdrop: AirdropCrate = airdrop_scene.instantiate() as AirdropCrate
	add_child(airdrop)
	await get_tree().process_frame
	airdrop.apply_state({
		"phase": "landed",
		"capture_progress": 0.5,
		"local_capture_radius": 120.0,
		"local_reward": 7,
	})
	await get_tree().process_frame
	var capture_bar: ProgressBar = airdrop.find_child("CaptureBar", true, false) as ProgressBar
	var capture_ring: Line2D = airdrop.find_child("CaptureRing", true, false) as Line2D
	var crate_sprite: Sprite2D = airdrop.find_child("Crate", true, false) as Sprite2D
	assert(capture_bar != null and is_equal_approx(capture_bar.value, 50.0))
	assert(capture_ring != null and capture_ring.points.size() == 65)
	airdrop.apply_state({"phase": "captured"})
	assert(crate_sprite != null and not crate_sprite.visible)
	airdrop.queue_free()

	var original_network_mode: StringName = NetworkSession.mode
	var original_match_active: bool = NetworkSession._match_active
	var original_phase: StringName = OnlineMatch.phase
	var original_set_kills: Dictionary = OnlineMatch.set_kills.duplicate()
	var original_match_points: Dictionary = OnlineMatch.match_points.duplicate()
	var original_airdrop_deployed: bool = OnlineMatch.airdrop_deployed
	NetworkSession.mode = GameSettings.NETWORK_MODE_HOST
	NetworkSession._match_active = true
	OnlineMatch.phase = GameSettings.MATCH_PHASE_PLAYING_SET
	OnlineMatch.set_kills = GameSettings.default_score()
	OnlineMatch.match_points = GameSettings.default_score()
	OnlineMatch.airdrop_deployed = false

	var left_marker: Marker2D = Marker2D.new()
	left_marker.name = "AirdropPointLeft"
	left_marker.position = Vector2(-100.0, 0.0)
	add_child(left_marker)
	var center_marker: Marker2D = Marker2D.new()
	center_marker.name = "AirdropPointCenter"
	center_marker.position = Vector2.ZERO
	add_child(center_marker)
	var right_marker: Marker2D = Marker2D.new()
	right_marker.name = "AirdropPointRight"
	right_marker.position = Vector2(100.0, 0.0)
	add_child(right_marker)

	var capture_player: Player = player_scene.instantiate() as Player
	capture_player.player_slot = GameSettings.PLAYER_ONE_SLOT
	_test_player = capture_player
	add_child(capture_player)
	await get_tree().process_frame
	capture_player.global_position = Vector2.ZERO
	var airdrop_manager_script: Script = load("res://scenes/objectives/airdrop_manager.gd") as Script
	var airdrop_manager: AirdropManager = airdrop_manager_script.new() as AirdropManager
	add_child(airdrop_manager)
	await get_tree().process_frame
	assert(airdrop_manager._phase == AirdropManager.PHASE_INACTIVE)
	assert(not OnlineMatch.airdrop_deployed)
	OnlineMatch.set_kills = {
		GameSettings.PLAYER_ONE_SLOT: GameSettings.ONLINE_SET_KILLS_TO_WIN - 1,
		GameSettings.PLAYER_TWO_SLOT: GameSettings.ONLINE_SET_KILLS_TO_WIN - 1,
	}
	airdrop_manager._try_start_decision_drop()
	assert(airdrop_manager._phase == AirdropManager.PHASE_WARNING)
	assert(airdrop_manager._target_position.is_equal_approx(center_marker.global_position))
	assert(OnlineMatch.airdrop_deployed)

	airdrop_manager._clear_airdrop()
	airdrop_manager._drop_completed = false
	OnlineMatch.airdrop_deployed = false
	OnlineMatch.match_points = {
		GameSettings.PLAYER_ONE_SLOT: 0,
		GameSettings.PLAYER_TWO_SLOT: 1,
	}
	airdrop_manager._try_start_decision_drop()
	assert(airdrop_manager._target_position.is_equal_approx(left_marker.global_position))

	airdrop_manager._clear_airdrop()
	NetworkSession.mode = GameSettings.NETWORK_MODE_CLIENT
	airdrop_manager._phase = AirdropManager.PHASE_FALLING
	airdrop_manager._descent_progress = 0.1
	airdrop_manager._remote_descent_target = 0.55
	airdrop_manager._last_remote_packet_msec = Time.get_ticks_msec()
	airdrop_manager._process_remote(0.1)
	assert(airdrop_manager._descent_progress > 0.1)
	NetworkSession.mode = GameSettings.NETWORK_MODE_HOST

	airdrop_manager._phase = &"landed"
	airdrop_manager._target_position = Vector2.ZERO
	airdrop_manager._capture_progress = 0.0
	var capture_reward_start: int = ResearchManager.research_points
	airdrop_manager._update_capture(GameSettings.AIRDROP_BASE_CAPTURE_SECONDS)
	assert(airdrop_manager._phase == &"captured")
	assert(airdrop_manager._drop_completed)
	assert(ResearchManager.research_points == capture_reward_start + ResearchManager.get_capture_research_reward())
	await get_tree().create_timer(1.5).timeout
	airdrop_manager.queue_free()
	capture_player.queue_free()
	left_marker.queue_free()
	center_marker.queue_free()
	right_marker.queue_free()
	_test_player = null
	NetworkSession.mode = original_network_mode
	NetworkSession._match_active = original_match_active
	OnlineMatch.phase = original_phase
	OnlineMatch.set_kills = original_set_kills
	OnlineMatch.match_points = original_match_points
	OnlineMatch.airdrop_deployed = original_airdrop_deployed

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
	_verify_armor_merging()

	ResearchManager._local_marks[str(ResearchManager.RECYCLING)] = 3
	ResearchManager._local_marks[str(ResearchManager.BLUEPRINT_STORAGE)] = 3
	ResearchManager.research_points = 1
	NetworkSession._reset_equipment_progression(false)
	assert(ResearchManager._local_marks.is_empty())
	assert(ResearchManager.research_points == ResearchManager.DEFAULT_RESEARCH_POINTS)
	assert(ResearchManager.get_blueprint_slot_count() == 0)

	ResearchManager._local_marks = original_marks
	ResearchManager.research_points = original_points
	ResearchQuestManager.reset_match()
	RoundRewardInventory._on_research_changed()
	await get_tree().process_frame
	await get_tree().process_frame
	print("RESEARCH_SMOKE_TEST_OK")
	get_tree().create_timer(1.0).timeout.connect(_finish_test)


func get_player_by_slot(slot: int) -> Player:
	if _test_player != null and _test_player.player_slot == slot:
		return _test_player
	return null


func _verify_world_scene_contract() -> void:
	var locker_scene: PackedScene = load("res://scenes/menus/online_locker_room.tscn") as PackedScene
	var locker: Variant = locker_scene.instantiate()
	add_child(locker as Node)
	await get_tree().process_frame

	assert(locker.get_player_by_slot(GameSettings.PLAYER_ONE_SLOT) is Player)
	assert(locker.get_player_by_slot(GameSettings.PLAYER_TWO_SLOT) is Player)
	assert(locker.get_local_player() is Player)
	assert(locker.get_score_for_slot(GameSettings.PLAYER_ONE_SLOT) == 0)
	assert(not locker.is_match_over())
	assert(locker.get_winner_slot() == 0)
	locker.request_block_state(
		locker.get_local_player(),
		false,
		Vector2.LEFT,
		GameSettings.PLAYER_BLOCK_REMOTE_COOLDOWN_RATIO
	)
	locker.request_shot(
		locker.get_local_player(),
		Vector2(320.0, 430.0),
		Vector2.RIGHT,
		{"muzzle_speed": 120.0, "damage": 1, "max_distance": 20.0}
	)

	locker.queue_free()
	await get_tree().process_frame


func _verify_armor_merging() -> void:
	var original_armor_inventory: Array[ArmorItemData] = ArmorInventory.inventory.duplicate()
	var original_balances: Dictionary = OnlineMatch.coin_balances.duplicate()
	OnlineMatch.coin_balances[NetworkSession.local_player_slot] = 100

	var mk1_definition: ArmorItemData = ArmorInventory.get_definition(&"adrenaline_boots_mk1")
	var mk2_definition: ArmorItemData = ArmorInventory.get_definition(&"adrenaline_boots_mk2")
	assert(mk1_definition != null)
	assert(mk2_definition != null)

	var first_mk1: ArmorItemData = mk1_definition.duplicate(true) as ArmorItemData
	var second_mk1: ArmorItemData = mk1_definition.duplicate(true) as ArmorItemData
	first_mk1.condition = 80.0
	second_mk1.condition = 60.0
	ArmorInventory.inventory.clear()
	ArmorInventory.inventory.append(first_mk1)
	ArmorInventory.inventory.append(second_mk1)

	assert(ArmorInventory.can_merge_items(first_mk1, second_mk1))
	var mk2_item: ArmorItemData = ArmorInventory.try_merge_items_for_local(first_mk1, second_mk1)
	assert(mk2_item != null)
	assert(mk2_item.get_mark() == 2)
	assert(mk2_item.item_id == &"adrenaline_boots_mk2")
	assert(is_equal_approx(mk2_item.condition, 70.0))
	assert(ArmorInventory.inventory.size() == 1)
	assert(ArmorInventory.inventory[0] == mk2_item)

	var second_mk2: ArmorItemData = mk2_definition.duplicate(true) as ArmorItemData
	second_mk2.condition = 90.0
	ArmorInventory.inventory.append(second_mk2)
	var mk3_item: ArmorItemData = ArmorInventory.try_merge_items_for_local(mk2_item, second_mk2)
	assert(mk3_item != null)
	assert(mk3_item.get_mark() == 3)
	assert(mk3_item.item_id == &"adrenaline_boots_mk3")
	assert(is_equal_approx(mk3_item.condition, 80.0))
	assert(not ArmorInventory.can_merge_items(mk3_item, mk3_item.duplicate(true) as ArmorItemData))

	ArmorInventory.inventory = original_armor_inventory
	OnlineMatch.coin_balances = original_balances


func _finish_test() -> void:
	get_tree().quit()
