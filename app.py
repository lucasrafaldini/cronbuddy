import customtkinter as ctk
import tkinter.messagebox as messagebox
from cron_manager import CronManager
from script_manager import ScriptManager
from ui_components import JobDialog, ScriptDialog

ctk.set_appearance_mode("System")
ctk.set_default_color_theme("blue")

class CronBuddyApp(ctk.CTk):
    def __init__(self, is_test_mode=False):
        super().__init__()
        
        self.is_test_mode = is_test_mode
        self.title("CronBuddy - macOS Cron Manager")
        self.geometry("900x600")
        
        self.cron_manager = CronManager()
        
        import os
        base_script_dir = os.path.expanduser("~/CronBuddyScripts")
        self.shell_manager = ScriptManager(scripts_dir=os.path.join(base_script_dir, "shell"))
        self.python_manager = ScriptManager(scripts_dir=os.path.join(base_script_dir, "python"))
        self.log_manager = ScriptManager(scripts_dir=os.path.join(base_script_dir, "logs"))
        
        template_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates")
        self.template_manager = ScriptManager(scripts_dir=template_dir)
        
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)
        
        # Sidebar
        self.sidebar = ctk.CTkFrame(self, width=200, corner_radius=0)
        self.sidebar.grid(row=0, column=0, sticky="nsew")
        
        self.logo_label = ctk.CTkLabel(self.sidebar, text="CronBuddy", font=ctk.CTkFont(size=20, weight="bold"))
        self.logo_label.pack(pady=20, padx=20)
        
        self.btn_add_job = ctk.CTkButton(self.sidebar, text="Add Cron Job", command=self.add_job)
        self.btn_add_job.pack(pady=10, padx=20)
        
        self.btn_files = ctk.CTkButton(self.sidebar, text="File Manager", command=self.manage_files)
        self.btn_files.pack(pady=10, padx=20)
        
        self.btn_refresh = ctk.CTkButton(self.sidebar, text="Refresh", command=self.refresh_jobs)
        self.btn_refresh.pack(pady=10, padx=20)
        
        # Main View
        self.main_view = ctk.CTkScrollableFrame(self)
        self.main_view.grid(row=0, column=1, sticky="nsew", padx=20, pady=20)
        
        self.refresh_jobs()

    def refresh_jobs(self):
        for widget in self.main_view.winfo_children():
            widget.destroy()
            
        jobs = self.cron_manager.get_jobs()
        if not jobs:
            lbl = ctk.CTkLabel(self.main_view, text="No cron jobs found.", font=ctk.CTkFont(size=16))
            lbl.pack(pady=20)
            return
            
        for job in jobs:
            card_color = ("#e8e8e8", "#2b2b2b") # light mode, dark mode
            frame = ctk.CTkFrame(self.main_view, fg_color=card_color, corner_radius=10)
            frame.pack(fill="x", pady=10, padx=10)
            
            # Left Container for Text
            left_frame = ctk.CTkFrame(frame, fg_color="transparent")
            left_frame.pack(side="left", fill="both", expand=True, padx=15, pady=15)
            
            # Header: Status + Comment + Schedule
            header_frame = ctk.CTkFrame(left_frame, fg_color="transparent")
            header_frame.pack(fill="x")
            
            status_text = "🟢 Active" if job['enabled'] else "🔴 Paused"
            status_color = "#5cb85c" if job['enabled'] else "#d9534f"
            lbl_status = ctk.CTkLabel(header_frame, text=status_text, text_color=status_color, font=ctk.CTkFont(weight="bold", size=12))
            lbl_status.pack(side="left", padx=(0, 10))
            
            comment_text = job['comment'] if job['comment'] else "Untitled Job"
            lbl_comment = ctk.CTkLabel(header_frame, text=comment_text, font=ctk.CTkFont(weight="bold", size=16))
            lbl_comment.pack(side="left")
            
            lbl_schedule = ctk.CTkLabel(header_frame, text=f" ⏱ {job['schedule']} ", font=ctk.CTkFont(size=12, family="Courier"), fg_color=("#d0d0d0", "#444444"), corner_radius=6)
            lbl_schedule.pack(side="left", padx=15)
            
            # Body: Command
            command_frame = ctk.CTkFrame(left_frame, fg_color=("#dcdcdc", "#1f1f1f"), corner_radius=6)
            command_frame.pack(fill="x", pady=(10, 0))
            
            lbl_cmd = ctk.CTkLabel(command_frame, text=job['command'], font=ctk.CTkFont(family="Courier", size=13), justify="left", anchor="w")
            lbl_cmd.pack(fill="x", padx=10, pady=5)
            
            # Right side buttons
            right_frame = ctk.CTkFrame(frame, fg_color="transparent")
            right_frame.pack(side="right", padx=15, pady=15)
            
            toggle_text = "Pause" if job['enabled'] else "Resume"
            toggle_color = "#f0ad4e" if job['enabled'] else "#5cb85c"
            btn_toggle = ctk.CTkButton(right_frame, text=toggle_text, width=70, fg_color=toggle_color, command=lambda j=job: self.toggle_job(j))
            btn_toggle.pack(side="left", padx=5)
            
            btn_edit = ctk.CTkButton(right_frame, text="Edit", width=70, fg_color=("#3a7ebf", "#1f538d"), command=lambda j=job: self.edit_job(j))
            btn_edit.pack(side="left", padx=5)

            btn_delete = ctk.CTkButton(right_frame, text="Delete", width=70, fg_color="#d9534f", hover_color="#c9302c", command=lambda c=job['comment']: self.delete_job(c))
            btn_delete.pack(side="left", padx=5)

    def add_job(self):
        dialog = JobDialog(self, self.cron_manager, is_test_mode=self.is_test_mode)
        self.wait_window(dialog)
        if dialog.result:
            self.refresh_jobs()
            
    def edit_job(self, job):
        dialog = JobDialog(self, self.cron_manager, job=job, title="Edit Cron Job", is_test_mode=self.is_test_mode)
        self.wait_window(dialog)
        if dialog.result:
            self.refresh_jobs()
            
    def delete_job(self, comment):
        if messagebox.askyesno("Confirm", f"Are you sure you want to delete job '{comment}'?"):
            self.cron_manager.remove_job(comment)
            self.refresh_jobs()
            
    def toggle_job(self, job):
        if job['enabled']:
            self.cron_manager.disable_job(job['comment'])
        else:
            self.cron_manager.enable_job(job['comment'])
        self.refresh_jobs()

    def manage_files(self):
        window = ctk.CTkToplevel(self)
        window.title("File Manager (Scripts, Templates & Logs)")
        window.geometry("700x500")
        window.grab_set()
        
        tabview = ctk.CTkTabview(window)
        tabview.pack(fill="both", expand=True, padx=20, pady=10)
        
        tab_shell = tabview.add("Shell Scripts")
        tab_python = tabview.add("Python Scripts")
        tab_logs = tabview.add("Logs")
        tab_templates = tabview.add("Templates")
        
        self._build_file_manager_tab(window, tab_shell, self.shell_manager)
        self._build_file_manager_tab(window, tab_python, self.python_manager)
        self._build_file_manager_tab(window, tab_logs, self.log_manager)
        self._build_file_manager_tab(window, tab_templates, self.template_manager)

    def _build_file_manager_tab(self, window, parent_tab, manager):
        list_frame = ctk.CTkScrollableFrame(parent_tab)
        list_frame.pack(fill="both", expand=True, padx=10, pady=10)
        
        def refresh_scripts():
            for w in list_frame.winfo_children():
                w.destroy()
            scripts = manager.get_scripts()
            if not scripts:
                lbl = ctk.CTkLabel(list_frame, text="No files found.", font=ctk.CTkFont(size=14, slant="italic"))
                lbl.pack(pady=20)
                
            for s in scripts:
                f = ctk.CTkFrame(list_frame)
                f.pack(fill="x", pady=5)
                l = ctk.CTkLabel(f, text=s['name'], font=ctk.CTkFont(weight="bold"))
                l.pack(side="left", padx=10)
                
                bd = ctk.CTkButton(f, text="Delete", width=50, fg_color="#d9534f", hover_color="#c9302c", command=lambda name=s['name']: delete_script(name))
                bd.pack(side="right", padx=5, pady=5)
                
                be = ctk.CTkButton(f, text="Edit", width=50, command=lambda name=s['name']: edit_script(name))
                be.pack(side="right", padx=5, pady=5)
                
        def add_script():
            d = ScriptDialog(window, manager, title="New File")
            window.wait_window(d)
            if d.result:
                refresh_scripts()
                
        def edit_script(name):
            d = ScriptDialog(window, manager, filename=name, title="Edit File")
            window.wait_window(d)
            if d.result:
                refresh_scripts()
                
        def delete_script(name):
            if messagebox.askyesno("Confirm", f"Delete file '{name}'?"):
                manager.delete_script(name)
                refresh_scripts()
                
        add_btn = ctk.CTkButton(parent_tab, text="New File", command=add_script)
        add_btn.pack(pady=10)
        
        refresh_scripts()

if __name__ == "__main__":
    import subprocess
    import sys
    import os
    
    # Launch menubar in background (it has a lock so it won't duplicate)
    menubar_path = os.path.join(os.path.dirname(__file__), "menubar.py")
    subprocess.Popen([sys.executable, menubar_path])
    
    is_test_mode = "--test" in sys.argv
    
    app = CronBuddyApp(is_test_mode=is_test_mode)
    app.mainloop()
