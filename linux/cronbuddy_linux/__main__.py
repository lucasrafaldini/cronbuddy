"""Allow running via `python3 -m cronbuddy_linux`."""

from .cli import main

if __name__ == "__main__":
    raise SystemExit(main())
