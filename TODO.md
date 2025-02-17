# TODO

## Updating
* Blocking: Update on mod config reload
* Blocking: Update on techs researched ("if unlocked" and if tech unlocks recipes only)
* Graceful upgrade with "defunct" combinators

## Copy-paste and all that
* Blocking: Copy / paste items support
* Blocking: Undo / redo support
* Paste blueprint over existing items support

## GUI and features
* Make "show all recipes" exclusive with other options?
* Right-alias support in the matrix builder
* Configurable: output all qualities when fluid output selected?

## Lua cleanup
* Blocking: make sure we aren't leaving dead tags in storage, or hack it with a display screen
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