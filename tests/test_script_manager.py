import os
import pytest
from script_manager import ScriptManager

def test_script_manager_ensures_dir(tmp_path):
    scripts_dir = tmp_path / "scripts"
    _ = ScriptManager(scripts_dir=str(scripts_dir))
    assert os.path.exists(scripts_dir)

def test_create_and_get_script(tmp_path):
    manager = ScriptManager(scripts_dir=str(tmp_path))
    filename = "test.sh"
    content = "#!/bin/bash\necho hello"
    
    manager.create_or_edit_script(filename, content)
    
    assert manager.get_script_content(filename) == content
    scripts = manager.get_scripts()
    assert len(scripts) == 1
    assert scripts[0]['name'] == filename

def test_get_nonexistent_script(tmp_path):
    manager = ScriptManager(scripts_dir=str(tmp_path))
    assert manager.get_script_content("ghost.sh") == ""

def test_delete_script(tmp_path):
    manager = ScriptManager(scripts_dir=str(tmp_path))
    filename = "test.sh"
    manager.create_or_edit_script(filename, "test")
    
    assert manager.delete_script(filename) is True
    assert manager.delete_script(filename) is False
    assert manager.get_script_content(filename) == ""
