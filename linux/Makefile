.PHONY: test run install uninstall

test:
	PYTHONPATH=. pytest -v tests

run:
	PYTHONPATH=. python3 -m cronbuddy_linux

install:
	bash install.sh

uninstall:
	rm -f "$(HOME)/.local/bin/cronbuddy" "$(HOME)/.local/bin/cronbuddy-linux" "$(HOME)/.local/share/applications/cronbuddy.desktop" "$(HOME)/.local/share/icons/hicolor/256x256/apps/cronbuddy.png"
	rm -rf "$(HOME)/.local/share/cronbuddy-app"
