import CronBuddyCore
import Foundation

/// cron and launchd start this same executable to run jobs. Those invocations
/// never touch AppKit; everything else launches the menu bar app.
@main
enum Entry {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: Launcher.runJobFlag), index + 1 < arguments.count {
            exit(ScheduledRun.run(jobID: arguments[index + 1], paths: .standard))
        }
        if let legacy = LegacyRun.parse(arguments) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            exit(LegacyRun.run(command: legacy.command, name: legacy.name, home: home))
        }
        CronBuddyApp.main()
    }
}
