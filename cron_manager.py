import os
from crontab import CronTab

class CronManager:
    def __init__(self):
        # We use the current user's crontab
        self.cron = CronTab(user=True)
    
    def refresh(self):
        self.cron = CronTab(user=True)
    
    def get_jobs(self):
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
        return jobs
    
    def add_job(self, command, schedule, comment=""):
        job = self.cron.new(command=command, comment=comment)
        job.setall(schedule)
        self.cron.write()
        return job

    def edit_job(self, old_comment, new_command, new_schedule, new_comment=""):
        # We find by comment (as an ID)
        jobs = list(self.cron.find_comment(old_comment))
        if jobs:
            job = jobs[0]
            job.set_command(new_command)
            job.setall(new_schedule)
            job.set_comment(new_comment)
            self.cron.write()
            return job
        return None

    def enable_job(self, comment):
        jobs = list(self.cron.find_comment(comment))
        if jobs:
            jobs[0].enable()
            self.cron.write()
            return True
        return False
        
    def disable_job(self, comment):
        jobs = list(self.cron.find_comment(comment))
        if jobs:
            jobs[0].enable(False)
            self.cron.write()
            return True
        return False

    def remove_job(self, comment):
        jobs = list(self.cron.find_comment(comment))
        if jobs:
            self.cron.remove(jobs[0])
            self.cron.write()
            return True
        return False

    def is_valid_schedule(self, schedule):
        # Basic validation, python-crontab handles parsing
        from crontab import CronSlices
        try:
            CronSlices(schedule)
            return True
        except Exception:
            return False
