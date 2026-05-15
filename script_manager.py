import os
import stat

from logger import logger


class ScriptManager:
    """Manages local script files and logs."""

    def __init__(self, scripts_dir: str = "~/CronBuddyScripts") -> None:
        """Initializes the ScriptManager.

        Args:
            scripts_dir: Path to the directory where scripts are stored.
        """
        self.scripts_dir = os.path.expanduser(scripts_dir)
        self._ensure_dir()

    def _ensure_dir(self) -> None:
        """Ensures that the scripts directory exists."""
        if not os.path.exists(self.scripts_dir):
            try:
                os.makedirs(self.scripts_dir)
                logger.info(f"Created directory: {self.scripts_dir}")
            except Exception as e:
                logger.error(f"Failed to create directory {self.scripts_dir}: {e}")

    def get_scripts(self) -> list[dict[str, str]]:
        """Lists all scripts in the managed directory.

        Returns:
            A list of dictionaries with script metadata (name and path).
        """
        self._ensure_dir()
        scripts = []
        try:
            for filename in os.listdir(self.scripts_dir):
                filepath = os.path.join(self.scripts_dir, filename)
                if os.path.isfile(filepath):
                    scripts.append({
                        'name': filename,
                        'path': filepath
                    })
        except Exception as e:
            logger.error(f"Failed to list scripts in {self.scripts_dir}: {e}")
            
        return scripts

    def create_or_edit_script(self, filename: str, content: str) -> str:
        """Creates or updates a script file and makes it executable.

        Args:
            filename: The name of the file.
            content: The script content.

        Returns:
            The absolute path to the created/edited script.
        """
        self._ensure_dir()
        filepath = os.path.join(self.scripts_dir, filename)
        
        try:
            # Write content
            with open(filepath, 'w') as f:
                f.write(content)
                
            # Make executable
            st = os.stat(filepath)
            os.chmod(filepath, st.st_mode | stat.S_IEXEC)
            
            logger.info(f"Saved and made executable: {filepath}")
            return filepath
        except Exception as e:
            logger.error(f"Failed to create/edit script {filename}: {e}")
            raise

    def get_script_content(self, filename: str) -> str:
        """Reads the content of a script file.

        Args:
            filename: The name of the script file.

        Returns:
            The file content, or an empty string if it doesn't exist.
        """
        filepath = os.path.join(self.scripts_dir, filename)
        if os.path.exists(filepath):
            try:
                with open(filepath) as f:
                    return f.read()
            except Exception as e:
                logger.error(f"Failed to read script {filename}: {e}")
        return ""

    def delete_script(self, filename: str) -> bool:
        """Deletes a script file.

        Args:
            filename: The name of the script to delete.

        Returns:
            True if deleted, False otherwise.
        """
        filepath = os.path.join(self.scripts_dir, filename)
        if os.path.exists(filepath):
            try:
                os.remove(filepath)
                logger.info(f"Deleted script: {filepath}")
                return True
            except Exception as e:
                logger.error(f"Failed to delete script {filename}: {e}")
                
        return False
