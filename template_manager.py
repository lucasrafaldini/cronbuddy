import os

from logger import logger


class TemplateManager:
    """Manages command templates stored as shell or text files."""

    def __init__(self, templates_dir: str = "templates") -> None:
        """Initializes the TemplateManager.

        Args:
            templates_dir: The name of the templates directory relative to this file.
        """
        base_dir = os.path.dirname(os.path.abspath(__file__))
        self.templates_dir = os.path.join(base_dir, templates_dir)
        self._ensure_dir()

    def _ensure_dir(self) -> None:
        """Ensures that the templates directory exists."""
        if not os.path.exists(self.templates_dir):
            try:
                os.makedirs(self.templates_dir)
                logger.info(f"Created templates directory: {self.templates_dir}")
            except Exception as e:
                logger.error(f"Failed to create templates directory {self.templates_dir}: {e}")

    def get_templates(self) -> dict[str, str]:
        """Parses all template files and returns a mapping of display names to commands.

        Returns:
            A dictionary where keys are display names and values are commands.
        """
        self._ensure_dir()
        templates = {}
        try:
            for filename in os.listdir(self.templates_dir):
                if filename.endswith(".sh") or filename.endswith(".txt"):
                    filepath = os.path.join(self.templates_dir, filename)
                    display_name, command = self._parse_template(filepath, filename)
                    if display_name and command:
                        templates[display_name] = command
            logger.info(f"Loaded {len(templates)} templates.")
        except Exception as e:
            logger.error(f"Failed to load templates: {e}")
            
        return templates

    def _parse_template(self, filepath: str, filename: str) -> tuple[str | None, str | None]:
        """Parses a single template file.

        Args:
            filepath: Path to the template file.
            filename: Name of the template file.

        Returns:
            A tuple of (display_name, command).
        """
        display_name = filename.replace(".sh", "").replace(".txt", "").replace("_", " ").title()
        command_lines = []
        
        try:
            with open(filepath) as f:
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
        except Exception as e:
            logger.error(f"Error parsing template {filename}: {e}")
            return None, None
