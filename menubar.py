import os
import subprocess
import sys
from typing import Any

import rumps


class CronBuddyStatusBarApp(rumps.App):
    """The macOS Menu Bar application for CronBuddy."""

    def __init__(self) -> None:
        """Initializes the status bar app."""
        super().__init__("⏱️")
        self.menu = ["Open CronBuddy", "Quit CronBuddy"]

    @rumps.clicked("Open CronBuddy")
    def open_app(self, _: Any) -> None:
        """Launches the main CronBuddy application."""
        # We launch app.py using the same python executable (venv)
        app_path = os.path.join(os.path.dirname(__file__), "app.py")
        cmd = [sys.executable, app_path]
        if "--test" in sys.argv:
            cmd.append("--test")
        subprocess.Popen(cmd)

    @rumps.clicked("Quit CronBuddy")
    def quit_app(self, _: Any) -> None:
        """Quits the application."""
        rumps.quit_application()

if __name__ == "__main__":
    import socket
    
    # Ensure only one instance of the menubar runs
    lock_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        lock_socket.bind(("127.0.0.1", 19999))
    except OSError:
        print("Menubar is already running.")
        sys.exit(0)
        
    # We must call rumps.App running to start the event loop
    app = CronBuddyStatusBarApp()
    app.quit_button = None # we created our own custom quit button for better naming
    app.run()
