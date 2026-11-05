SCRATCH ?= $(HOME)/Library/Caches/cronbuddy-build
SWIFT_FLAGS = --scratch-path "$(SCRATCH)"

.PHONY: build test run app dmg install clean

clean-forks:
	@find Sources Tests -name '._*' -delete 2>/dev/null || true

build: clean-forks
	swift build $(SWIFT_FLAGS)

test: clean-forks
	swift test $(SWIFT_FLAGS)

run: app
	open build/CronBuddy.app

app:
	scripts/build-app.sh

dmg:
	DMG=1 scripts/build-app.sh

install: app
	rm -rf /Applications/CronBuddy.app
	cp -R build/CronBuddy.app /Applications/
	open /Applications/CronBuddy.app

clean:
	rm -rf build "$(SCRATCH)"
