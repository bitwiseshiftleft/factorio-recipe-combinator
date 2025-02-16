# TODO

Logic bug: shadowing recipes.
Suppose you have {foundry, furnace} selected and ask for steel-plate.
The foundry overrides the furnace, so you get info on steel-plate-casting.
But if you ask for quality-steel-plate, you get nothing.  This is because
the foundry overrides the furnace, but sets FLAG_NORMAL_INPUT; but there is
no FLAG_ONLY_NOT_NORMAL_INPUT.

* Matrix class so the Lua will be nicer

* Quality indicator: output a signal "Q" or so whose quality is set to the recipe quality, for downstream use
* Undo / redo support
* Copy / paste items support
* Spoilage support
* Make "show all recipes" exclusive with other options
* Multiply and negate support
* Separate red/green output support??
* Right-alias support
* Limit to unlocked recipes only
* Test test test
* Test again with no quality

Speculative future features
* Deal with probabilities
* Deal with productivity bonuses (either inherent in the machine or with modules)
* Better graphics
* Export to vanilla combinator array
* Constant combinators (list all fluids/items/recipes/recipes for certain machines/...)
* Some kind of matrix optimizer (e.g. if one column dominates another, then add an alias)