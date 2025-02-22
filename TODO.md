# TODO

## Updating
* Blocking: Update on mod config reload
* Blocking: Update on techs researched ("if unlocked" and if tech unlocks recipes only)
* Graceful upgrade with "defunct" combinators

## Copy-paste and all that
* Blocking: Undo / redo support
* Blocking: update GUI if someone pastes over the item
* Blocking: diagnose rounding issues in blueprint pasting
* Add indicator inserters to blueprint?

## GUI and features
* Make "show all recipes" exclusive with other options?
* Right-alias support in the matrix builder
* Could in theory do ranged right-alias support e.g. select (i,j=i+1) or whatever from one combinator and have i<=x<=j instead of i=x.  In particular this would allow "x at only normal quality" vs "x at all qualities" on adjacent indices.
* Configurable: output all qualities when fluid output selected?

## Lua cleanup
* Blocking: make sure we aren't leaving dead tags in storage, or hack it with garbage collection on load
* Separate circuit.lua from recipe combinator matrix logic

## Test
* Blocking: Test test test
* Blocking: Test again with no quality

## Py functionality
* Make a "commit" button for py, for perf reasons?  Eh, probably good enough for now (TM)
* Update on py TURD selected or similar

## Packaging
* Blocking: flesh out the README
* Blocking: make a screenshot and thumbnail
* Package and upload

## Speculative future features
* Deal with spoilage time increases from quality
* Deal with probabilities
* Deal with productivity bonuses (either inherent in the machine or with modules)
* Better graphics
* Export to vanilla combinator array
* Constant combinators (list all fluids/items/recipes/recipes for certain machines/...)
* Some kind of matrix optimizer (e.g. if one column dominates another, then add an alias)