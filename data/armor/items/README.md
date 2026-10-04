# Armor Item Definitions

Place `ArmorItemData` resources (`.tres` or `.res`) in this folder or subfolders.

Each item can define category, condition, generic attributes, future effect data, and metadata without changing the core armor system.

Items are drawn by `ArmorArt` (`scenes/items/armor/armor_art.gd`), keyed by the item id without its `_mkN` suffix (`frosty_shield_mk2` draws `frosty_shield` at mark 2). An id without a design there falls back to its category's starter piece.
