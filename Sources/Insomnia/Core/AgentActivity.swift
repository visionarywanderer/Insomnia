import Darwin
import Foundation

/// What an agent hook last said about one agent session: working, or done
/// and waiting. Written by `Insomnia --agent busy|idle --source <name>`,
/// which Claude Code and Codex hooks run (`AgentHooks`), one file per agent
/// session in `agents/` under the support folder.
struct AgentReport: Codable, Equatable, Identifiable, Sendable {
    var source: String
    var session: String
    var busy: Bool
    /// The agent process the hook ran under, and its identity, so a report
    /// from an agent that crashed or was killed stops counting.
    var pid: Int32
    var identity: ProcessIdentity?
    var updatedAt: Date

    var id: String { "\(source)-\(session)" }
}

enum AgentActivity {
    /// A busy report not refreshed for this long stops counting. Claude Code
    /// does not run its Stop hook when the user interrupts a turn, and every
    /// tool call refreshes a working agent's report.
    static let busyLease: TimeInterval = 30 * 60
    /// Reports older than this are deleted when read.
    static let keepFor: TimeInterval = 24 * 3600

    static func directory(_ paths: Paths) -> URL {
        paths.appSupport.appendingPathComponent("agents", isDirectory: true)
    }

    // MARK: Command

    /// `--agent busy|idle --source <name>`, with the hook's JSON on stdin.
    /// Always exits 0 once the arguments parse: a hook that fails would
    /// show up as an error in the agent, and nothing here is worth that.
    static func run(_ args: [String], stdin: Data, paths: Paths, now: Date = Date(), owner: Int32 = agentPID()) -> Int32 {
        guard args.count >= 2, args[0] == "--agent", let busy = ["busy": true, "idle": false][args[1]] else {
            FileHandle.standardError.write(Data("usage: Insomnia --agent busy|idle --source <name>\n".utf8))
            return 64
        }
        let source = value(after: "--source", in: args) ?? "agent"
        let session = sessionID(from: stdin) ?? "pid-\(owner)"
        let report = AgentReport(
            source: source,
            session: session,
            busy: busy,
            pid: owner,
            identity: identity(of: owner),
            updatedAt: now
        )
        do {
            try Store(paths: paths).write(report, to: file(for: report, paths: paths))
        } catch {
            FileHandle.standardError.write(Data("insomnia: \(error.localizedDescription)\n".utf8))
        }
        return 0
    }

    /// The hook's JSON from stdin, or nothing after a second: a hook runner
    /// that keeps stdin open must never hang the agent. Nothing is read
    /// from a terminal.
    static func readHookInput(timeout: TimeInterval = 1) -> Data {
        guard isatty(STDIN_FILENO) == 0 else { return Data() }
        let box = DataBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = FileHandle.standardInput.readDataToEndOfFile()
            done.signal()
        }
        return done.wait(timeout: .now() + timeout) == .success ? box.data : Data()
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    /// Claude Code and Codex both send `session_id`.
    static func sessionID(from json: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        for key in ["session_id", "sessionId", "thread_id", "conversation_id"] {
            if let id = object[key] as? String, !id.isEmpty { return id }
        }
        return nil
    }

    static func file(for report: AgentReport, paths: Paths) -> URL {
        directory(paths).appendingPathComponent("\(safe(report.source))-\(safe(report.session)).json")
    }

    /// Letters, digits, dot, dash and underscore; anything else becomes a
    /// dash, so an id can never name a path outside the folder.
    static func safe(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let mapped = String(s.unicodeScalars.prefix(80).map { allowed.contains($0) && $0.isASCII ? Character($0) : "-" })
        return mapped.hasPrefix(".") ? "-" + mapped.dropFirst() : mapped
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    // MARK: Owner

    /// Hooks run through a shell; the agent is the first ancestor that is
    /// not one.
    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "login"]

    static func agentPID(from start: Int32 = getppid()) -> Int32 {
        var pid = start
        var hops = 0
        while hops < 5, shells.contains(name(of: pid)),
              case let .present(state) = SignalProcessControl.processTableState(pid: pid), state.ppid > 1 {
            pid = state.ppid
            hops += 1
        }
        return pid
    }

    static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func identity(of pid: Int32) -> ProcessIdentity? {
        guard case let .present(state) = SignalProcessControl.processTableState(pid: pid) else { return nil }
        return state.identity
    }

    // MARK: Reading

    /// Still the same process as when the report was written.
    static func isAlive(_ report: AgentReport, lookup: (Int32) -> ProcessLookup = SignalProcessControl.processTableState) -> Bool {
        guard case let .present(state) = lookup(report.pid) else { return false }
        return report.identity == nil || state.identity == report.identity
    }

    /// The agents working right now: busy, alive and refreshed within the
    /// lease. Deletes reports whose agent is gone or that are old.
    static func busyAgents(paths: Paths, now: Date, alive: (AgentReport) -> Bool = { isAlive($0) }) -> [AgentReport] {
        let dir = directory(paths)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let store = Store(paths: paths)
        var busy: [AgentReport] = []
        for url in files where url.pathExtension == "json" {
            guard let report = try? store.read(AgentReport.self, from: url) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let age = now.timeIntervalSince(report.updatedAt)
            guard alive(report), age < keepFor else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            if report.busy, age < busyLease { busy.append(report) }
        }
        return busy.sorted { $0.updatedAt < $1.updatedAt }
    }
}
