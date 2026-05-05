import os
import stat

class ScriptManager:
    def __init__(self, scripts_dir="~/CronBuddyScripts"):
        self.scripts_dir = os.path.expanduser(scripts_dir)
        self._ensure_dir()

    def _ensure_dir(self):
        if not os.path.exists(self.scripts_dir):
            os.makedirs(self.scripts_dir)

    def get_scripts(self):
        self._ensure_dir()
        scripts = []
        for filename in os.listdir(self.scripts_dir):
            filepath = os.path.join(self.scripts_dir, filename)
            if os.path.isfile(filepath):
                scripts.append({
                    'name': filename,
                    'path': filepath
                })
        return scripts

    def create_or_edit_script(self, filename, content):
        self._ensure_dir()
        filepath = os.path.join(self.scripts_dir, filename)
        
        # Write content
        with open(filepath, 'w') as f:
            f.write(content)
            
        # Make executable
        st = os.stat(filepath)
        os.chmod(filepath, st.st_mode | stat.S_IEXEC)
        
        return filepath

    def get_script_content(self, filename):
        filepath = os.path.join(self.scripts_dir, filename)
        if os.path.exists(filepath):
            with open(filepath, 'r') as f:
                return f.read()
        return ""

    def delete_script(self, filename):
        filepath = os.path.join(self.scripts_dir, filename)
        if os.path.exists(filepath):
            os.remove(filepath)
            return True
        return False
