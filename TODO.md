# TODO

* Blocking: Divide round up rounds -1/2 to +1

## Copy-paste and all that
* Update GUI if someone pastes over the item
* Fix rounding issues when copy-pasting a blueprint with grid coordinates
* Add indicator inserters to blueprint?
* Undo/redo paste settings

## GUI and features
* Make "show all recipes" and "show all valid" exclusive with other options?
* Right-alias support in the matrix builder
* Could in theory do ranged right-alias support e.g. select (i,j=i+1) or whatever from one combinator and have i<=x<=j instead of i=x.  In particular this would allow "x at only normal quality" vs "x at all qualities" on adjacent indices.
* Configurable: output all qualities when fluid output selected?
* Consider a flag for round up/down.  Up is nicer though because you can't round up to 0
* Or can you?  Test negative numbers too.
* Paste-entity-settings from a machine to a combinator, to set that machine?
* Add combinator description.

## Lua cleanup
* Tighten up on_died to avoid leaving dead tags in storage (currently clean one tick after on_load anyway)
* Separate circuit.lua from recipe combinator matrix logic
* Add filters to events for performance

## Test
* Test test test
* Test again with no quality
* Test briefly that the caching system on divmod even works

## Py functionality
* Make a "commit" button for py, for perf reasons?  Eh, probably good enough for now (TM)
* Update on py TURD selected or similar

## Packaging
* Blocking: flesh out the README
* Blocking: make a screenshot and thumbnail
* Package and upload

## Speculative future features
* Deal with spoilage time increases from quality
* Allow to blacklist specific recipes
* Make power consumption real?
* Give info about allowed fuels, or burnt fuel results.
* Deal with probabilities
* Deal with productivity bonuses (either inherent in the machine or with modules)
* Better graphics
* Export to vanilla combinator array
* Some kind of matrix optimizer (e.g. if one column dominates another, then add an alias)