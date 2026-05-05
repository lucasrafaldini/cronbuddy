import os

class TemplateManager:
    def __init__(self, templates_dir="templates"):
        # We place the templates folder next to the main app file
        base_dir = os.path.dirname(os.path.abspath(__file__))
        self.templates_dir = os.path.join(base_dir, templates_dir)
        self._ensure_dir()

    def _ensure_dir(self):
        if not os.path.exists(self.templates_dir):
            os.makedirs(self.templates_dir)

    def get_templates(self):
        self._ensure_dir()
        templates = {}
        for filename in os.listdir(self.templates_dir):
            if filename.endswith(".sh") or filename.endswith(".txt"):
                filepath = os.path.join(self.templates_dir, filename)
                display_name, command = self._parse_template(filepath, filename)
                if command:
                    templates[display_name] = command
        return templates

    def _parse_template(self, filepath, filename):
        display_name = filename.replace(".sh", "").replace(".txt", "").replace("_", " ").title()
        command_lines = []
        
        with open(filepath, 'r') as f:
            lines = f.readlines()
            
        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue
                
            # If the first line is a comment starting with # NAME:, use it as title
            if stripped.startswith("# NAME:") and len(command_lines) == 0:
                display_name = stripped.replace("# NAME:", "").strip()
                continue
                
            # We ignore generic comments starting with # but keep the commands
            if stripped.startswith("#"):
                continue
                
            command_lines.append(stripped)
            
        if not command_lines:
            return None, None
            
        # If it's a multi-line script, it's safer to execute the script itself via bash
        if len(command_lines) > 1:
            return display_name, f"bash {filepath}"
            
        return display_name, command_lines[0]
