import pytest
from unittest.mock import MagicMock, patch
from cron_manager import CronManager

@pytest.fixture
def mock_cron():
    with patch('cron_manager.CronTab') as mock:
        yield mock

def test_cron_manager_get_jobs(mock_cron):
    mock_job = MagicMock()
    mock_job.command = "ls"
    mock_job.comment = "test"
    mock_job.slices.render.return_value = "* * * * *"
    mock_job.is_enabled.return_value = True
    
    mock_cron.return_value.__iter__.return_value = [mock_job]
    
    manager = CronManager()
    jobs = manager.get_jobs()
    
    assert len(jobs) == 1
    assert jobs[0]['command'] == "ls"
    assert jobs[0]['comment'] == "test"

def test_add_job(mock_cron):
    manager = CronManager()
    manager.add_job("ls", "* * * * *", "test_job")
    
    mock_cron.return_value.new.assert_called_with(command="ls", comment="test_job")
    mock_cron.return_value.write.assert_called()

def test_edit_job(mock_cron):
    mock_job = MagicMock()
    mock_cron.return_value.find_comment.return_value = [mock_job]
    
    manager = CronManager()
    manager.edit_job("old", "new_cmd", "0 0 * * *", "new_comment")
    
    mock_job.set_command.assert_called_with("new_cmd")
    mock_job.set_comment.assert_called_with("new_comment")
    mock_cron.return_value.write.assert_called()

def test_enable_disable_job(mock_cron):
    mock_job = MagicMock()
    mock_cron.return_value.find_comment.return_value = [mock_job]
    
    manager = CronManager()
    manager.enable_job("test")
    mock_job.enable.assert_called_with()
    
    manager.disable_job("test")
    mock_job.enable.assert_called_with(False)

def test_remove_job(mock_cron):
    mock_job = MagicMock()
    mock_cron.return_value.find_comment.return_value = [mock_job]
    
    manager = CronManager()
    manager.remove_job("test")
    mock_cron.return_value.remove.assert_called_with(mock_job)

def test_is_valid_schedule():
    manager = CronManager()
    assert manager.is_valid_schedule("* * * * *") is True
    assert manager.is_valid_schedule("invalid") is False
    assert manager.is_valid_schedule("@reboot") is True
