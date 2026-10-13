import Foundation

/// Adds and removes the hooks that report agent activity to Auto mode
/// (`AgentActivity`). Claude Code reads `~/.claude/settings.json` (the
/// terminal CLI and the Claude app's Code tab); Codex reads
/// `~/.codex/hooks.json` (the CLI, the Codex app and the IDE extension).
/// Both files use the same shape:
///
///     {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "..."}]}]}}
///
/// Only entries whose command runs this app with `--agent` are ours; every
/// other key and hook is kept. The file is backed up once, before the first
/// change, next to itself.
struct AgentHooks: Sendable {
    let name: String
    let source: String
    let file: URL
    /// Hook event, whether it reports busy (true) or idle (false), and the
    /// matcher, if the event takes one.
    let events: [(event: String, busy: Bool, matcher: String?)]

    static func claude(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AgentHooks {
        AgentHooks(
            name: "Claude Code",
            source: "claude",
            file: home.appendingPathComponent(".claude/settings.json"),
            events: [("UserPromptSubmit", true, nil), ("PreToolUse", true, nil), ("PostToolUse", true, nil),
                     ("Stop", false, nil), ("Notification", false, "permission_prompt|idle_prompt"), ("SessionEnd", false, nil)]
        )
    }

    static func codex(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AgentHooks {
        AgentHooks(
            name: "Codex",
            source: "codex",
            file: home.appendingPathComponent(".codex/hooks.json"),
            events: [("UserPromptSubmit", true, nil), ("PreToolUse", true, nil),
                     ("Stop", false, nil), ("PermissionRequest", false, nil)]
        )
    }

    static func command(binary: String, busy: Bool, source: String) -> String {
        "'\(binary.replacingOccurrences(of: "'", with: "'\\''"))' --agent \(busy ? "busy" : "idle") --source \(source)"
    }

    static func isOurs(_ command: String) -> Bool {
        command.contains("Insomnia") && command.contains(" --agent ")
    }

    var backup: URL { file.appendingPathExtension("insomnia-backup") }

    var isInstalled: Bool {
        guard let root = try? read() else { return false }
        return events.allSatisfy { e in
            Self.entries(root, e.event).contains { Self.commands($0).contains(where: Self.isOurs) }
        }
    }

    func install(binary: String) throws {
        var root = try read()
        Self.strip(&root)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for e in events {
            var list = hooks[e.event] as? [[String: Any]] ?? []
            var entry: [String: Any] = ["hooks": [["type": "command", "command": Self.command(binary: binary, busy: e.busy, source: source), "timeout": 5]]]
            if let matcher = e.matcher { entry["matcher"] = matcher }
            list.append(entry)
            hooks[e.event] = list
        }
        root["hooks"] = hooks
        try write(root)
    }

    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var root = try read()
        Self.strip(&root)
        try write(root)
    }

    // MARK: Private

    private func read() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        if data.isEmpty { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file.path])
        }
        return root
    }

    private func write(_ root: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: file.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: file, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
    }

    private static func entries(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    private static func commands(_ entry: [String: Any]) -> [String] {
        (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
    }

    /// Removes our hooks, then any entry and event left empty by that.
    private static func strip(_ root: inout [String: Any]) {
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = list.compactMap { entry in
                guard let inner = entry["hooks"] as? [[String: Any]] else { return entry }
                let rest = inner.filter { !isOurs($0["command"] as? String ?? "") }
                if rest.count == inner.count { return entry }
                if rest.isEmpty { return nil }
                var e = entry
                e["hooks"] = rest
                return e
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
    }
}
