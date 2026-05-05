import customtkinter as ctk
import tkinter.messagebox as messagebox
import datetime
from template_manager import TemplateManager

class JobDialog(ctk.CTkToplevel):
    def __init__(self, parent, cron_manager, job=None, title="Add Cron Job", is_test_mode=False):
        super().__init__(parent)
        self.title(title)
        self.geometry("500x500")
        self.cron_manager = cron_manager
        self.job = job
        self.result = False
        
        # Command Section
        self.command_label = ctk.CTkLabel(self, text="Command/Script to execute:")
        self.command_label.pack(pady=(15, 0), padx=20, anchor="w")
        
        self.template_manager = TemplateManager()
        self.dynamic_templates = self.template_manager.get_templates()
        
        template_names = ["Choose a Command Template..."] + list(self.dynamic_templates.keys())
        
        self.template_var = ctk.StringVar(value="Choose a Command Template...")
        self.template_menu = ctk.CTkOptionMenu(self, variable=self.template_var, command=self.on_template_select, values=template_names, width=460)
        self.template_menu.pack(pady=5, padx=20)
        
        self.command_entry = ctk.CTkEntry(self, width=460)
        self.command_entry.pack(pady=5, padx=20)
        
        # Schedule Section
        self.schedule_label = ctk.CTkLabel(self, text="Cron Schedule (e.g., * * * * * or @reboot):")
        self.schedule_label.pack(pady=(15, 0), padx=20, anchor="w")
        
        presets = [
            "Choose a Time Preset...",
            "Every Minute",
            "Every Hour",
            "Every Day at Midnight",
            "Every Sunday at Midnight",
            "Every 1st of the Month",
            "On System Boot"
        ]
        
        if is_test_mode:
            presets.append("One Minute From Now (Test)")
            
        self.schedule_preset_var = ctk.StringVar(value="Choose a Time Preset...")
        self.schedule_preset_menu = ctk.CTkOptionMenu(self, variable=self.schedule_preset_var, command=self.on_schedule_select, values=presets, width=460)
        self.schedule_preset_menu.pack(pady=5, padx=20)
        
        self.schedule_entry = ctk.CTkEntry(self, width=460)
        self.schedule_entry.pack(pady=5, padx=20)
        
        # Comment Section
        self.comment_label = ctk.CTkLabel(self, text="Description (Comment/ID):")
        self.comment_label.pack(pady=(15, 0), padx=20, anchor="w")
        
        self.comment_entry = ctk.CTkEntry(self, width=460)
        self.comment_entry.pack(pady=5, padx=20)
        
        self.save_btn = ctk.CTkButton(self, text="Save Job", command=self.save)
        self.save_btn.pack(pady=25)
        
        if self.job:
            self.command_entry.insert(0, self.job['command'])
            self.schedule_entry.insert(0, self.job['schedule'])
            self.comment_entry.insert(0, self.job['comment'])
            self.comment_entry.configure(state="disabled")

        self.grab_set()
        
    def on_template_select(self, choice):
        if choice in self.dynamic_templates:
            self.command_entry.delete(0, "end")
            self.command_entry.insert(0, self.dynamic_templates[choice])
            self.template_var.set("Choose a Command Template...")
            
    def on_schedule_select(self, choice):
        schedules = {
            "Every Minute": "* * * * *",
            "Every Hour": "0 * * * *",
            "Every Day at Midnight": "0 0 * * *",
            "Every Sunday at Midnight": "0 0 * * 0",
            "Every 1st of the Month": "0 0 1 * *",
            "On System Boot": "@reboot"
        }
        if choice == "One Minute From Now (Test)":
            dt = datetime.datetime.now() + datetime.timedelta(minutes=1)
            cron_str = f"{dt.minute} {dt.hour} {dt.day} {dt.month} *"
            self.schedule_entry.delete(0, "end")
            self.schedule_entry.insert(0, cron_str)
            self.schedule_preset_var.set("Choose a Time Preset...")
        elif choice in schedules:
            self.schedule_entry.delete(0, "end")
            self.schedule_entry.insert(0, schedules[choice])
            self.schedule_preset_var.set("Choose a Time Preset...")
            
    def save(self):
        command = self.command_entry.get().strip()
        schedule = self.schedule_entry.get().strip()
        comment = self.comment_entry.get().strip()
        
        if not command or not schedule:
            messagebox.showerror("Error", "Command and Schedule are required.")
            return
            
        if not self.cron_manager.is_valid_schedule(schedule):
            messagebox.showerror("Error", "Invalid Cron Schedule.")
            return
            
        if self.job:
            self.cron_manager.edit_job(self.job['comment'], command, schedule, self.job['comment'])
        else:
            if not comment:
                comment = "CronBuddy_" + str(hash(command + schedule))
            self.cron_manager.add_job(command, schedule, comment)
            
        self.result = True
        self.destroy()

class ScriptDialog(ctk.CTkToplevel):
    def __init__(self, parent, script_manager, filename="", title="Script Editor"):
        super().__init__(parent)
        self.title(title)
        self.geometry("600x500")
        self.script_manager = script_manager
        self.filename = filename
        self.result = False
        
        self.filename_label = ctk.CTkLabel(self, text="Filename (e.g. backup.sh):")
        self.filename_label.pack(pady=(10, 0), padx=20, anchor="w")
        
        self.filename_entry = ctk.CTkEntry(self, width=560)
        self.filename_entry.pack(pady=5, padx=20)
        
        self.content_label = ctk.CTkLabel(self, text="Script Content:")
        self.content_label.pack(pady=(10, 0), padx=20, anchor="w")
        
        self.content_text = ctk.CTkTextbox(self, width=560, height=300)
        self.content_text.pack(pady=5, padx=20)
        
        self.save_btn = ctk.CTkButton(self, text="Save Script", command=self.save)
        self.save_btn.pack(pady=10)
        
        if self.filename:
            self.filename_entry.insert(0, self.filename)
            self.filename_entry.configure(state="disabled")
            content = self.script_manager.get_script_content(self.filename)
            self.content_text.insert("1.0", content)
            
        self.grab_set()
        
    def save(self):
        filename = self.filename_entry.get().strip()
        content = self.content_text.get("1.0", "end-1c")
        
        if not filename:
            messagebox.showerror("Error", "Filename is required.")
            return
            
        filepath = self.script_manager.create_or_edit_script(filename, content)
        messagebox.showinfo("Success", f"Script saved and made executable at:\n{filepath}")
        self.result = True
        self.destroy()
