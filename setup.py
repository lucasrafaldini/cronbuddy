from setuptools import setup

APP = ['menubar.py']
DATA_FILES = [
    'templates',
    'app.py',
    'cron_manager.py',
    'script_manager.py',
    'template_manager.py',
    'ui_components.py',
    'logger.py'
]
OPTIONS = {
    'argv_emulation': True,
    'plist': {
        'LSUIElement': True,  # This makes the app a background/menubar app
        'CFBundleName': "CronBuddy",
        'CFBundleDisplayName': "CronBuddy",
        'CFBundleIdentifier': "com.lucasrafaldini.cronbuddy",
        'CFBundleVersion': "0.1.0",
        'CFBundleShortVersionString': "0.1.0",
    },
    'packages': ['rumps', 'customtkinter', 'crontab', 'PIL'],
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
)
