from typing import Any

from crontab import CronSlices, CronTab

from logger import logger


class CronManager:
    """Manages system cron jobs using the python-crontab library."""

    def __init__(self) -> None:
        """Initializes the CronManager with the current user's crontab."""
        try:
            self.cron = CronTab(user=True)
        except Exception as e:
            logger.error(f"Failed to initialize CronTab: {e}")
            # Fallback to empty crontab if system access is restricted
            self.cron = CronTab(tab="")

    def refresh(self) -> None:
        """Refreshes the crontab from the system."""
        try:
            self.cron = CronTab(user=True)
        except Exception as e:
            logger.error(f"Failed to refresh CronTab: {e}")

    def get_jobs(self) -> list[dict[str, Any]]:
        """Retrieves all cron jobs for the current user.

        Returns:
            A list of dictionaries representing cron jobs.
        """
        self.refresh()
        jobs = []
        for job in self.cron:
            jobs.append({
                'id': job.comment if job.comment else str(hash(job.command)),
                'command': job.command,
                'schedule': job.slices.render(),
                'enabled': job.is_enabled(),
                'comment': job.comment,
                'raw': job
            })
        logger.info(f"Retrieved {len(jobs)} cron jobs.")
        return jobs

    def add_job(self, command: str, schedule: str, comment: str = "") -> Any:
        """Adds a new cron job.

        Args:
            command: The command to execute.
            schedule: The cron schedule string (e.g., '* * * * *').
            comment: An optional comment to identify the job.

        Returns:
            The newly created CronItem.
        """
        try:
            job = self.cron.new(command=command, comment=comment)
            job.setall(schedule)
            self.cron.write()
            logger.info(f"Added job: {comment} ({command}) with schedule {schedule}")
            return job
        except Exception as e:
            logger.error(f"Failed to add job {comment}: {e}")
            raise

    def edit_job(
        self, old_comment: str, new_command: str, new_schedule: str, new_comment: str = ""
    ) -> Any | None:
        """Edits an existing cron job identified by its comment.

        Args:
            old_comment: The current comment of the job.
            new_command: The new command to execute.
            new_schedule: The new cron schedule.
            new_comment: The new comment for the job.

        Returns:
            The modified CronItem, or None if not found.
        """
        jobs = list(self.cron.find_comment(old_comment))
        if jobs:
            job = jobs[0]
            job.set_command(new_command)
            job.setall(new_schedule)
            job.set_comment(new_comment)
            self.cron.write()
            logger.info(f"Edited job {old_comment} -> {new_comment}")
            return job
        
        logger.warning(f"Job with comment '{old_comment}' not found for editing.")
        return None

    def enable_job(self, comment: str) -> bool:
        """Enables a cron job.

        Args:
            comment: The comment identifying the job.

        Returns:
            True if successful, False otherwise.
        """
        jobs = list(self.cron.find_comment(comment))
        if jobs:
            jobs[0].enable()
            self.cron.write()
            logger.info(f"Enabled job: {comment}")
            return True
        return False
        
    def disable_job(self, comment: str) -> bool:
        """Disables a cron job.

        Args:
            comment: The comment identifying the job.

        Returns:
            True if successful, False otherwise.
        """
        jobs = list(self.cron.find_comment(comment))
        if jobs:
            jobs[0].enable(False)
            self.cron.write()
            logger.info(f"Disabled job: {comment}")
            return True
        return False

    def remove_job(self, comment: str) -> bool:
        """Removes a cron job.

        Args:
            comment: The comment identifying the job.

        Returns:
            True if successful, False otherwise.
        """
        jobs = list(self.cron.find_comment(comment))
        if jobs:
            self.cron.remove(jobs[0])
            self.cron.write()
            logger.info(f"Removed job: {comment}")
            return True
        return False

    def is_valid_schedule(self, schedule: str) -> bool:
        """Validates a cron schedule string.

        Args:
            schedule: The schedule string to validate.

        Returns:
            True if valid, False otherwise.
        """
        try:
            CronSlices(schedule)
            return True
        except Exception:
            return False
