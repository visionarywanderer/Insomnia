import Foundation

// Entry point. A one-shot command-line mode is answered here, before AppKit
// or SwiftUI start, so backstop.sh can borrow the app's kernel-level
// identity check (see ResumeFrozenCommand), which ends itself when its
// lifetime is up. Anything else starts the menu bar app.
// An agent hook (`AgentHooks`) reporting busy or idle for Auto mode.
if CommandLine.arguments.dropFirst().first == "--agent" {
    exit(AgentActivity.run(Array(CommandLine.arguments.dropFirst()), stdin: AgentActivity.readHookInput(), paths: .fromEnvironment()))
}
if let output = ResumeFrozenCommand.run(Array(CommandLine.arguments.dropFirst()), endAfter: ResumeFrozenCommand.endProcess) {
    for line in output.lines { print(line) }
    exit(output.status)
}
InsomniaApp.main()
