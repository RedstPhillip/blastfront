# Weapon Extensions Developer Guide

This guide explains how the weapon extension foundation works and how to add new MK1 extensions safely.

The goal of the system is that most extensions can be added by creating one `.tres` definition file and, optionally, one visual scene plus one reusable behavior/effect class.

## Architecture

Weapon extensions are split into data, runtime inventory/loadout state, visuals, projectile behaviors, and hit effects.

Core files:

- `res://scenes/weapons/extensions/weapon_extension_definition.gd`
  Defines one extension type. This is the main data model used by `.tres` extension files.
- `res://scenes/weapons/extensions/weapon_extension_item.gd`
  Runtime instance of an extension definition with a concrete condition value.
- `res://scenes/weapons/extensions/extension_condition.gd`
  Condition tiers, tier colors, condition clamping, and random condition rolling.
- `res://autoload/extension_inventory.gd`
  Loads extension definitions, creates demo inventory items, stores equipped slots, merges stats, and syncs loadouts through `OnlineMatch`.
- `res://scenes/hands/gun/gun.gd`
  Reads equipped extension stats and applies them to fire interval and projectile data.
- `res://scenes/projectiles/projectile.gd`
  Stores projectile tags/effects and runs behavior hooks every physics tick.
- `res://scenes/network/projectile_sync.gd`
  Spawns network projectiles with extension data and applies extension effects on hit.

UI and visuals:

- `res://scenes/menus/extensions/ExtensionWorkbench.tscn`
  Intermission extension page with inventory cards, three slots, and weapon preview.
- `res://scenes/weapons/extensions/WeaponPreview2D.tscn`
  Reuses the same socket layout as the real gun for preview visuals.
- `res://scenes/weapons/extensions/weapon_extension_visuals.gd`
  Spawns visual scenes into `middle`, `ammo`, and `front` sockets.
- `res://scenes/hands/gun/gun.tscn`
  Real gun scene with `MiddleSocket`, `AmmoSocket`, and `FrontSocket`.

Behaviors and effects:

- `res://scenes/weapons/extensions/extension_behavior.gd`
  Base class for projectile behavior that runs during flight.
- `res://scenes/weapons/extensions/extension_behavior_registry.gd`
  Maps projectile tags such as `homing` to behavior instances.
- `res://scenes/weapons/extensions/extension_effect.gd`
  Base class for effects applied when a projectile hits a player.
- `res://scenes/weapons/extensions/extension_effect_registry.gd`
  Maps effect names such as `fire` or `poison` to effect instances.

## Slot Types

Each extension belongs to exactly one slot.

- `middle`
  For changes in the middle/top of the weapon, such as scopes, sights, reload brackets, stabilizers.
- `ammo`
  For ammo type changes, such as fire ammo, poison ammo, freeze ammo, explosive ammo.
- `front`
  For front-mounted weapon changes, such as long barrels, suppressors, muzzle devices.

The current slot keys are defined in `WeaponExtensionDefinition`:

```gdscript
const SLOT_MIDDLE: StringName = &"middle"
const SLOT_AMMO: StringName = &"ammo"
const SLOT_FRONT: StringName = &"front"
```

Do not invent new slot strings in extension files unless the slot system is intentionally expanded.

## Condition System

Every `WeaponExtensionItem` has a `condition` from `0.0` to `100.0`.

Condition tiers:

- `90-100`: Factory New, gold, 3%
- `75-90`: Barely Used, purple, 12%
- `55-75`: Field-Tested, blue, 25%
- `35-55`: Well-Worn, green, 30%
- `0-35`: Battle Scarred, gray, currently rolled between `10-30`, 30%

Condition affects numeric values when these are enabled on the definition:

```gdscript
condition_scales_attributes = true
condition_scales_projectile_effects = true
minimum_condition_factor = 0.35
```

Example:

- An extension gives `projectile_speed = 160.0`.
- Condition is `80`.
- Minimum factor is `0.35`.
- Effective multiplier is between `0.35` and `1.0`, based on condition.
- The final modifier is less than `160.0`, but not completely destroyed.

Use `minimum_condition_factor` to control how bad a damaged extension can get.

## What An Extension Definition Can Change

An extension `.tres` can define:

- `extension_id`
  Unique stable ID. Used for save/load and online loadout sync.
- `display_name`
  UI name.
- `slot_key`
  `middle`, `ammo`, or `front`.
- `mark`
  Currently `1` for MK1.
- `description`
  Developer/player description.
- `default_condition`
  Condition used for demo inventory item creation.
- `minimum_condition_factor`
  Lower bound for condition scaling.
- `attribute_modifiers`
  Numeric stat modifications merged by `ExtensionInventory`.
- `projectile_tags`
  Behavior tags used by `ExtensionBehaviorRegistry`.
- `projectile_effects`
  Hit effects and behavior payload data.
- `visual_scene`
  Optional visual scene spawned onto the weapon socket.
- `icon_color`
  UI color for inventory cards.

Current known attribute keys used by `gun.gd`:

```gdscript
"fire_interval"              # Added to fire interval. Negative means faster shooting.
"damage"                     # Added to projectile damage.
"projectile_speed"           # Added to muzzle speed.
"projectile_gravity"         # Added to projectile gravity.
"projectile_linear_damping"  # Added to projectile damping.
"projectile_max_distance"    # Added to max distance.
```

New attribute keys can be added later, but they do nothing until code reads them.

## Add A Simple Stat Extension

Use this path pattern:

```text
res://scenes/weapons/extensions/my_extension_mk1.tres
```

Steps:

1. Duplicate an existing `.tres`, such as `long_barrel_mk1.tres`.
2. Change `extension_id` to a unique ID.
3. Change `display_name`.
4. Set `slot_key`.
5. Set `mark = 1`.
6. Fill `attribute_modifiers`.
7. Optional: assign a `visual_scene`.
8. Add the `.tres` path to `EXTENSION_DEFINITION_PATHS` in `autoload/extension_inventory.gd`.

Example shape for a front barrel:

```gdscript
extension_id = "example_barrel_mk1"
display_name = "Example Barrel MK1"
slot_key = "front"
mark = 1
default_condition = 70.0
minimum_condition_factor = 0.35
attribute_modifiers = {
	"projectile_speed": 120.0,
	"projectile_max_distance": 180.0
}
projectile_tags = Array[String]([])
projectile_effects = {}
```

## Add Ammo With A Hit Effect

Ammo effects usually use `projectile_effects`.

Example shape for fire ammo:

```gdscript
extension_id = "example_fire_ammo_mk1"
display_name = "Example Fire Ammo MK1"
slot_key = "ammo"
mark = 1
minimum_condition_factor = 0.25
attribute_modifiers = {
	"damage": -1.0
}
projectile_tags = Array[String]([])
projectile_effects = {
	"fire": {
		"damage_per_hit": 3.0
	}
}
```

What happens:

1. `ExtensionInventory` merges `projectile_effects`.
2. `gun.gd` writes them onto the projectile.
3. On hit, `ExtensionEffectRegistry.apply_projectile_effects()` loops through the effect names.
4. The registered `FireEffect` handles the `"fire"` dictionary.

To create a new hit effect:

1. Create a script in `res://scenes/weapons/extensions/effects/`.
2. Extend `ExtensionEffect`.
3. Implement `apply(target: Player, effect_data: Dictionary, projectile: Node = null)`.
4. Register it in `extension_effect_registry.gd`.
5. Reference it by name in `projectile_effects`.

Example effect script shape:

```gdscript
class_name SlowEffect
extends ExtensionEffect


func apply(target: Player, effect_data: Dictionary, _projectile: Node = null) -> void:
	if target == null:
		return

	var duration: float = float(effect_data.get("duration", 0.0))
	var strength: float = float(effect_data.get("strength", 0.0))
	# Apply slow through a future status component here.
```

Registry entry:

```gdscript
const SLOW_EFFECT_SCRIPT: Script = preload("res://scenes/weapons/extensions/effects/slow_effect.gd")

static var effects: Dictionary = {
	&"fire": FIRE_EFFECT_SCRIPT.new(),
	&"poison": POISON_EFFECT_SCRIPT.new(),
	&"slow": SLOW_EFFECT_SCRIPT.new(),
}
```

## Add A Projectile Behavior

Projectile behaviors run every physics tick while the projectile exists.

Use behaviors for things like:

- homing
- bouncing
- piercing
- gravity bending
- orbiting
- acceleration
- wave movement

The existing hook is:

```gdscript
ExtensionBehaviorRegistry.update_projectile_behaviors(self, delta)
```

This runs inside `Projectile._physics_process()`.

Example shape for a homing scope or homing ammo:

```gdscript
extension_id = "example_homing_scope_mk1"
display_name = "Example Homing Scope MK1"
slot_key = "middle"
mark = 1
projectile_tags = Array[String](["homing"])
projectile_effects = {
	"homing": {
		"strength": 1.4
	}
}
```

Important detail:

`projectile_tags` activates the behavior. `projectile_effects["homing"]` provides data to that behavior.

To create a new behavior:

1. Create a script in `res://scenes/weapons/extensions/behaviors/`.
2. Extend `ExtensionBehavior`.
3. Implement `update(projectile: Projectile, delta: float, effect_data: Dictionary = {})`.
4. Register it in `extension_behavior_registry.gd`.
5. Add its tag to `projectile_tags` in an extension `.tres`.
6. Add optional tuning data under the same key in `projectile_effects`.

Example behavior script shape:

```gdscript
class_name AcceleratingBehavior
extends ExtensionBehavior


func update(projectile: Projectile, delta: float, effect_data: Dictionary = {}) -> void:
	if projectile == null:
		return

	var acceleration: float = float(effect_data.get("acceleration", 0.0))
	if acceleration <= 0.0:
		return

	projectile.velocity += projectile.direction * acceleration * delta
```

Registry entry:

```gdscript
const ACCELERATING_BEHAVIOR_SCRIPT: Script = preload("res://scenes/weapons/extensions/behaviors/accelerating_behavior.gd")

static var behaviors: Dictionary = {
	&"homing": HOMING_BEHAVIOR_SCRIPT.new(),
	&"accelerating": ACCELERATING_BEHAVIOR_SCRIPT.new(),
}
```

## Add A Visual Attachment

Visuals are normal Godot scenes. Prefer building them with nodes.

Recommended path:

```text
res://scenes/weapons/extensions/visuals/my_extension_visual.tscn
```

Rules:

- Root should usually be `Node2D`.
- Keep it local around `(0, 0)`.
- The socket decides placement.
- Do not script visuals unless the visual itself needs animation or logic.
- Reuse Godot nodes like `Polygon2D`, `Sprite2D`, `Line2D`, `CPUParticles2D`.

Then assign the scene in the extension definition:

```gdscript
visual_scene = ExtResource("2_visual")
```

Socket placement:

- `middle` uses `MiddleSocket`.
- `ammo` uses `AmmoSocket`.
- `front` uses `FrontSocket`.

Both the real gun and the preview use `WeaponExtensionVisuals`, so one visual scene automatically works in-game and in the intermission workbench.

## Register The Extension Definition

Every extension definition must be added to:

```gdscript
const EXTENSION_DEFINITION_PATHS: Array[String] = [
	"res://scenes/weapons/extensions/red_dot_sight_mk1.tres",
	"res://scenes/weapons/extensions/cryo_rounds_mk1.tres",
	"res://scenes/weapons/extensions/long_barrel_mk1.tres",
	"res://scenes/weapons/extensions/my_new_extension_mk1.tres",
]
```

This is currently in:

```text
res://autoload/extension_inventory.gd
```

If the path is not added there, the extension will not appear in the demo inventory and cannot be equipped through the current workbench.

## Data Flow

High-level data flow:

```text
.tres WeaponExtensionDefinition
        |
        v
ExtensionInventory loads definitions
        |
        v
WeaponExtensionItem adds concrete condition
        |
        v
Player equips item into one of three slots
        |
        v
ExtensionInventory merges stats/tags/effects
        |
        v
gun.gd builds projectile data
        |
        v
Projectile stores extension_tags and extension_effects
        |
        v
BehaviorRegistry updates projectile during flight
EffectRegistry applies hit effects on player hit
```

Online loadout flow:

```text
ExtensionInventory.serialize_loadout_for_player()
        |
        v
OnlineMatch.set_local_extension_loadout()
        |
        v
OnlineMatch state sync
        |
        v
ExtensionInventory.apply_online_loadouts()
```

Only IDs and condition values are synced. The receiving side loads the actual definitions locally.

## Naming Conventions

Use stable lowercase IDs:

```text
fire_ammo_mk1
homing_scope_mk1
long_barrel_mk1
```

Use matching file names:

```text
fire_ammo_mk1.tres
homing_scope_mk1.tres
long_barrel_mk1.tres
```

Use clear script names:

```text
fire_effect.gd
homing_behavior.gd
accelerating_behavior.gd
```

## Current Examples

Existing extension definitions:

- `red_dot_sight_mk1.tres`
  Middle/top slot, modifies fire interval, has a sight visual.
- `cryo_rounds_mk1.tres`
  Ammo slot, carries a future `freeze` projectile effect payload.
- `long_barrel_mk1.tres`
  Front slot, modifies projectile speed, gravity, and range.

Existing behavior/effect templates:

- `homing_behavior.gd`
  Demonstrates a flight behavior that steers toward the nearest enemy.
- `fire_effect.gd`
  Demonstrates hit-effect registration and direct damage application.
- `poison_effect.gd`
  Minimal hit-effect template.

## Common Pitfalls

Use explicit types in GDScript. Avoid `:=` where Godot cannot infer types.

Good:

```gdscript
var effect_name: StringName = StringName(str(raw_effect_name))
var effect_data: Dictionary = {}
var strength: float = float(effect_data.get("strength", 0.0))
```

Avoid:

```gdscript
var effect_name := raw_effect_name
```

Keep IDs stable. If an extension ID changes, saved or synced loadouts using the old ID will no longer resolve.

Keep behavior tags and effect names exact. `"fire"` and `"Fire"` are different names.

Do not put all extension logic in `gun.gd` or `projectile.gd`. Add reusable behavior/effect scripts and register them.

Do not add a new slot by only typing a new string in a `.tres`. Slots are validated by `WeaponExtensionDefinition.is_valid_slot()`.

Remember that condition scaling affects numeric values inside `attribute_modifiers` and, if enabled, nested numeric values inside `projectile_effects`.

## Checklist For A New Extension

Use this checklist for each new extension:

- Create or duplicate a `.tres` under `res://scenes/weapons/extensions/`.
- Set unique `extension_id`.
- Set `display_name`.
- Set `slot_key` to `middle`, `ammo`, or `front`.
- Set `mark = 1`.
- Set `default_condition` and `minimum_condition_factor`.
- Add `attribute_modifiers` if it changes weapon stats.
- Add `projectile_tags` if it needs flight behavior.
- Add `projectile_effects` if it needs hit effects or behavior tuning data.
- Create a visual scene under `visuals/` if it should change the weapon visually.
- Assign `visual_scene` in the `.tres`.
- Add the `.tres` path to `EXTENSION_DEFINITION_PATHS`.
- If a new behavior is needed, create it and register it in `ExtensionBehaviorRegistry`.
- If a new hit effect is needed, create it and register it in `ExtensionEffectRegistry`.
- Open Godot and check that there are no import/script errors.
- Test drag-and-drop in the intermission extension workbench.
- Test shooting with the extension equipped.
