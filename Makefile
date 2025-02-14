VERSION=0.1.0
MODS_DIR="$(HOME)/Library/Application Support/factorio/mods"
FILES= info.json changelog.txt *.lua prototypes lualib graphics locale README.md LICENSE

all: mod
mod: build/recipe_combinator_$(VERSION).zip
run:
	open -a Factorio

clean:
	rm -fr build

build/recipe_combinator_$(VERSION).zip: $(FILES)
	rm -fr build
	mkdir -p build/recipe_combinator_$(VERSION)
	cp -r $(FILES) build/recipe_combinator_$(VERSION)
	cd build && zip -r recipe_combinator_$(VERSION).zip recipe_combinator_$(VERSION)

install: mod
	cp build/recipe_combinator_$(VERSION).zip $(MODS_DIR)/