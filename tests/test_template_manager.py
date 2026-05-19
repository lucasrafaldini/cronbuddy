from template_manager import TemplateManager


def test_template_parsing(tmp_path):
    # Setup dummy templates
    template_dir = tmp_path / "templates"
    template_dir.mkdir()
    
    # Template 1: Single line
    t1 = template_dir / "ping.sh"
    t1.write_text("# NAME: Ping Google\nping -c 4 google.com")
    
    # Template 2: Multi line
    t2 = template_dir / "backup.sh"
    t2.write_text("# NAME: Backup DB\necho 'backing up'\necho 'done'")
    
    # Template 3: Generic name from filename
    t3 = template_dir / "clear_logs.sh"
    t3.write_text("rm -rf /tmp/logs/*")
    
    # Template 4: Python in subfolder
    python_dir = template_dir / "python"
    python_dir.mkdir()
    t4 = python_dir / "hello.py"
    t4.write_text("# NAME: Hello Python\nprint('hello')")
    
    # Template 5: Python on root
    t5 = template_dir / "root_test.py"
    t5.write_text("print('root')")

    manager = TemplateManager(templates_dir=str(template_dir))
    # We need to hack the internal path for testing because TemplateManager 
    # uses os.path.dirname(os.path.abspath(__file__)) to find templates
    manager.templates_dir = str(template_dir)
    
    templates = manager.get_templates()
    
    assert "Ping Google" in templates
    assert templates["Ping Google"] == "ping -c 4 google.com"
    
    assert "Backup DB" in templates # Matches the # NAME: header
    assert templates["Backup DB"].startswith("bash")
    
    assert "Clear Logs" in templates
    assert templates["Clear Logs"] == "rm -rf /tmp/logs/*"
    
    assert "Hello Python" in templates
    assert templates["Hello Python"] == f"/usr/bin/python3 {t4}"
    
    assert "Root Test" in templates
    assert templates["Root Test"] == f"/usr/bin/python3 {t5}"
