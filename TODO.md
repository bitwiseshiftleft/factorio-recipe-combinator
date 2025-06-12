# TODO

* Update the thumbnail image

## Copy-paste and all that
* Update GUI if someone pastes over the item
* Fix rounding issues when copy-pasting a blueprint with grid coordinates
* Add indicator inserters to blueprint?
* Undo/redo paste settings

## Clarity
* Make in-game README / tips and tricks.
* Flesh out the package README

## GUI and features
* Make "show all recipes" and "show all valid" exclusive with other options?
* Right-alias support in the matrix builder
* Could in theory do ranged right-alias support e.g. select (i,j=i+1) or whatever from one combinator and have i<=x<=j instead of i=x.  In particular this would allow "x at only normal quality" vs "x at all qualities" on adjacent indices.
* Configurable: output all qualities when fluid output selected?
* Consider a flag for round up/down?  Up is nicer though because you can't round up to 0
* Or can you?  Test negative numbers too.
* Paste-entity-settings from a machine to a combinator, to set that machine?
* Add combinator description window.
* Maybe some kind of alphabet combinator mode?  Eg all fluids, all items, all (unlocked) recipes, all virtual signals, all targetables, all stack sizes, etc.
* Sectionize or otherwise hide components of the GUI.

## Lua cleanup
* Tighten up on_died to avoid leaving dead tags in storage (currently runs once every minute or so)
* Separate circuit.lua from recipe combinator matrix logic
* Add filters to events for performance

## Test
* Test test test
* Test again with no quality
* Test more with negative numbers.
* Test briefly that the caching system on divmod even works

## Py functionality
* Update on py TURD selected and similar events that unlock recipes.

## Speculative future features
* Deal with productivity bonuses (either inherent in the machine or with modules)
* Better graphics
* Deal with spoilage time increases from quality
* Allow to blacklist specific recipes
* Make power consumption real?  Eh, who even cares
* Give info about allowed fuels, or burnt fuel results.
* Deal with probabilities
* Option to export to vanilla combinator array
* Better matrix optimizer (e.g. if one column dominates another, then add an alias)