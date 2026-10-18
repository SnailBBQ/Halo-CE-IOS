Put your tag files in this folder (you can delete this file).

Each file's path is the path of the map's tag it replaces, then its group's extension.
Examples (note the forward slashes; the game's own tag names use backslashes):

  tags/sound/sfx/weapons/assault rifle/fire.sound
  tags/characters/cyborg/bitmaps/cyborg.bitmap
  tags/ui/hud/hud_item_messages.unicode_string_list
  tags/characters/cyborg/cyborg.gbxmodel

Rules in one breath:
  * Only sounds (.sound), bitmaps (.bitmap), text (.unicode_string_list, .string_list) and
    models (.gbxmodel or .model) are read. Anything else in tags/ is ignored.
  * A file replaces a tag the map ALREADY has, by name. A mod cannot add tags: a new
    biped, weapon or map object will never appear.
  * A model must keep the map's skeleton, markers and regions, and may only name shaders
    the map has. See docs/ios/MOD_FORMAT.md.
  * Files must be Halo PC tag files (what the Halo Editing Kit or Invader writes).
