import sys

from setuptools import setup

APP = ["menubar.py"]

# Only include py2app configuration if py2app command is invoked
if "py2app" in sys.argv:
    DATA_FILES = [
        "templates",
        "app.py",
        "cron_manager.py",
        "script_manager.py",
        "template_manager.py",
        "ui_components.py",
        "job_runner.py",
        "logger.py",
        "assets",
    ]
    OPTIONS = {
        "argv_emulation": True,
        "plist": {
            "LSUIElement": True,  # This makes the app a background/menubar app
            "CFBundleName": "CronBuddy",
            "CFBundleDisplayName": "CronBuddy",
            "CFBundleIdentifier": "com.lucasrafaldini.cronbuddy",
            "CFBundleVersion": "0.1.0",
            "CFBundleShortVersionString": "0.1.0",
        },
        "packages": ["rumps", "customtkinter", "crontab", "PIL"],
        "iconfile": "assets/app_icon.icns",
    }
    setup_kwargs = {
        "app": APP,
        "data_files": DATA_FILES,
        "options": {"py2app": OPTIONS},
    }
else:
    # Bypass setuptools flat-layout package discovery error by specifying empty packages/modules
    setup_kwargs = {
        "packages": [],
        "py_modules": [],
    }

setup(**setup_kwargs)
