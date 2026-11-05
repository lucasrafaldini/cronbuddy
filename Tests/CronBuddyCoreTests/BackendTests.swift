import Foundation
import Testing
@testable import CronBuddyCore

private let paths = Paths(home: URL(fileURLWithPath: "/Users/test"))

@Suite struct CrontabTests {
    let job = Job(id: "abc123", name: "Backup", action: .shell(command: "echo hi"),
                  schedule: .daily(times: [TimeOfDay(hour: 21, minute: 0)]), backend: .cron)

    @Test func mergeKeepsUserLinesAndReplacesManagedOnes() {
        let existing = """
        MAILTO=""
        0 5 * * * /usr/local/bin/mine
        1 1 * * * '/old/cb-run' gone # cronbuddy:gone

        """
        let merged = CrontabBackend.merged(existing: existing, jobs: [job], paths: paths)
        #expect(merged == """
        MAILTO=""
        0 5 * * * /usr/local/bin/mine
        0 21 * * * '/Users/test/Library/Application Support/CronBuddy/bin/cb-run' abc123 # cronbuddy:abc123

        """)
    }

    @Test func pausedAndLaunchdJobsAreNotWritten() {
        var paused = job
        paused.isEnabled = false
        var launchd = job
        launchd.backend = .launchd
        #expect(CrontabBackend.merged(existing: "", jobs: [paused, launchd], paths: paths) == "")
    }

    @Test func externalEntries() {
        let text = """
        SHELL=/bin/bash
        # a comment
        */5 * * * * /usr/bin/true # CronBuddy_42
        @reboot /usr/local/bin/startup
        0 21 * * * '/x/cb-run' abc123 # cronbuddy:abc123
        not a cron line
        """
        let entries = CrontabBackend.externalEntries(in: text)
        #expect(entries.count == 2)
        #expect(entries[0].schedule == "*/5 * * * *")
        #expect(entries[0].command == "/usr/bin/true")
        #expect(entries[0].comment == "CronBuddy_42")
        #expect(entries[1].schedule == "@reboot")

        let removed = CrontabBackend.removing(entries[0], from: text)
        #expect(!removed.contains("/usr/bin/true"))
        #expect(removed.contains("@reboot"))
    }
}

@Suite struct ActionScriptTests {
    @Test func quoting() {
        #expect(Shell.quote("it's") == "'it'\\''s'")
    }

    @Test func rendersEachActionKind() {
        var job = Job(id: "x", name: "J", action: .shortcut(name: "Morning's Brief"), environment: ["CITY": "São Paulo", "bad-name": "x"])
        var script = ActionScript.render(job)
        #expect(script.hasPrefix("#!/bin/zsh\n"))
        #expect(script.contains("export CITY='São Paulo'"))
        #expect(!script.contains("bad-name"))
        #expect(script.contains("exec /usr/bin/shortcuts run 'Morning'\\''s Brief'"))

        job.action = .script(path: "/tmp/a b.py")
        script = ActionScript.render(job)
        #expect(script.contains("exec /usr/bin/env python3 '/tmp/a b.py' \"$@\""))

        job.action = .script(path: "/tmp/Flow.workflow")
        #expect(ActionScript.render(job).contains("exec /usr/bin/automator '/tmp/Flow.workflow'"))

        job.action = .appleScript(source: "beep")
        #expect(ActionScript.render(job).contains("/usr/bin/osascript <<'CRONBUDDY_APPLESCRIPT'\nbeep\nCRONBUDDY_APPLESCRIPT"))
    }

    @Test func wrapperRendersAbsolutePaths() {
        let wrapper = RunWrapper.render(paths: paths)
        #expect(wrapper.contains("ACTION='/Users/test/Library/Application Support/CronBuddy/actions'/\"$JOB_ID.sh\""))
        #expect(wrapper.contains("LOG_DIR='/Users/test/Library/Logs/CronBuddy'/\"$JOB_ID\""))
        #expect(wrapper.contains("{\\\"start\\\":$START"))
    }
}

@Suite struct ValidationTests {
    @Test func problems() {
        var job = Job(name: "", action: .shell(command: " "), schedule: .interval(minutes: 7), backend: .cron)
        #expect(job.problems.count == 3)
        job.name = "Ok"
        job.action = .shell(command: "true")
        job.backend = .launchd
        #expect(job.problems.isEmpty)
        job.environment = ["1BAD": "x"]
        #expect(job.problems.count == 1)
    }

    @Test func everyTemplateIsValidForLaunchdAndCron() {
        for template in Templates.all {
            var job = template.makeJob()
            if case .shortcut = job.action { job.action = .shortcut(name: "Example") }
            #expect(job.problems.isEmpty, "\(template.id): \(job.problems)")
            job.backend = .cron
            #expect(job.problems.isEmpty, "\(template.id) on cron: \(job.problems)")
        }
        #expect(Set(Templates.all.map(\.id)).count == Templates.all.count)
    }
}

@Suite struct RunHistoryTests {
    @Test func roundTripAndPrune() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "cronbuddy-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)

        for i in 0..<5 {
            let start = Date(timeIntervalSince1970: Double(1_000 + i * 60))
            try RunHistory.append(jobID: "j", start: start, end: start.addingTimeInterval(2),
                                  exitCode: i == 4 ? 1 : 0, output: "run \(i)", paths: paths)
        }
        var runs = RunHistory.load(jobID: "j", paths: paths)
        #expect(runs.count == 5)
        #expect(runs.first?.exitCode == 1)
        #expect(runs.first?.trigger == .manual)
        #expect(RunHistory.logText(runs.first!, paths: paths) == "run 4")

        RunHistory.prune(jobID: "j", keep: 2, paths: paths)
        runs = RunHistory.load(jobID: "j", paths: paths)
        #expect(runs.count == 2)
        let logs = try FileManager.default.contentsOfDirectory(atPath: paths.logDir(for: "j").path)
            .filter { $0.hasSuffix(".log") }
        #expect(logs.count == 2)
    }

    @Test func parsesWrapperLines() {
        let data = Data("""
        {"start":1700000000.25,"end":1700000003.5,"exit":2,"log":"20231114-221320-99.log","trigger":"schedule"}
        garbage
        """.utf8)
        let runs = RunHistory.parse(data, jobID: "w")
        #expect(runs.count == 1)
        #expect(runs[0].exitCode == 2)
        #expect(abs(runs[0].duration - 3.25) < 0.001)
    }
}

@Suite struct LauncherTests {
    let job = Job(id: "abc123", name: "Sync", action: .shell(command: "true"),
                  schedule: .hourly(minute: 0), backend: .cron)

    @Test func appLauncherGoesThroughLaunchServicesForCron() {
        let line = CrontabBackend.lines(for: job, paths: paths, launcher: .app(path: "/Applications/CronBuddy.app"))
        #expect(line == ["0 * * * * /usr/bin/open -g -W -n -a '/Applications/CronBuddy.app' --args --run-job abc123 # cronbuddy:abc123"])
    }

    @Test func appLauncherRunsTheBinaryDirectlyForLaunchd() throws {
        var launchdJob = job
        launchdJob.backend = .launchd
        let data = try LaunchdBackend.plistData(for: launchdJob, paths: paths, launcher: .app(path: "/Applications/CronBuddy.app"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["ProgramArguments"] as? [String] == ["/Applications/CronBuddy.app/Contents/MacOS/CronBuddy", "--run-job", "abc123"])
        #expect(plist["StartCalendarInterval"] as? [String: Int] == ["Minute": 0])
        #expect(plist["Label"] as? String == "com.lucasrafaldini.cronbuddy.job.abc123")
    }

    @Test func legacyLinesAreUnwrappedOnImport() {
        let text = "@hourly /usr/bin/open -g -W -n -a /Applications/CronBuddy.app --args --run 'env -u PYTHONHOME /usr/bin/python3 /Users/x/sync.py' --name 'Obsidian — Sincronizar projetos' # Obsidian — Sincronizar projetos"
        let entry = CrontabBackend.externalEntries(in: text).first
        #expect(entry?.isLegacyCronBuddy == true)
        #expect(entry?.command == "env -u PYTHONHOME /usr/bin/python3 /Users/x/sync.py")
        #expect(entry?.comment == "Obsidian — Sincronizar projetos")
        #expect(entry?.schedule == "@hourly")
    }

    @Test func legacyArgumentsAndLogNames() {
        let parsed = LegacyRun.parse(["/x/CronBuddy", "--run", "echo hi", "--name", "Obsidian — Sincronizar projetos"])
        #expect(parsed?.command == "echo hi")
        #expect(parsed?.name == "Obsidian — Sincronizar projetos")
        let date = Date(timeIntervalSince1970: 1_793_500_000)
        #expect(LegacyRun.logFileName(name: "Obsidian — Sincronizar projetos", now: date).hasPrefix("cronbuddy_Obsidian_Sincronizar_projetos_"))
    }

    @Test func shellWords() {
        #expect(ShellWords.split(#"a 'b c' "d \"e\"" f\ g"#) == ["a", "b c", #"d "e""#, "f g"])
        #expect(ShellWords.split("'unterminated") == nil)
    }

    @Test func scheduledRunRecordsOutputAndExitCode() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "cronbuddy-run-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        let job = Job(id: "run1", name: "Echo", action: .shell(command: "echo hello; echo oops >&2; exit 3"))
        try ActionScript.write(job, to: paths.actionScript(for: job.id))

        let code = ScheduledRun.run(jobID: job.id, paths: paths)
        #expect(code == 3)
        let runs = RunHistory.load(jobID: job.id, paths: paths)
        #expect(runs.count == 1)
        #expect(runs[0].exitCode == 3)
        #expect(runs[0].trigger == .schedule)
        #expect(RunHistory.logText(runs[0], paths: paths) == "hello\noops\n")
        #expect(!FileManager.default.fileExists(atPath: paths.runningMarker(for: job.id).path))
    }
}
