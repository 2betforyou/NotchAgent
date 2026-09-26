import Foundation

/// Git worktrees let several agents work on separate branches of one repository at once
/// without touching each other's files. NotchAgent only runs plain `git worktree` commands;
/// it never forces a removal, so uncommitted work cannot be deleted by accident.
enum Worktree {
    enum Failure: LocalizedError {
        case gitMissing, git(String)
        var errorDescription: String? {
            switch self {
            case .gitMissing: L("git을 찾을 수 없습니다. Xcode Command Line Tools 또는 Homebrew git을 설치하세요.", "git was not found. Install the Xcode Command Line Tools or Homebrew git.")
            case .git(let message): message
            }
        }
    }

    static func isRepository(_ path: String) -> Bool { Workspaces.gitBranch(at: path) != nil }
    /// A linked worktree has a `.git` *file* pointing at the main repository.
    static func isLinked(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let dotGit = URL(fileURLWithPath: path).appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
    /// `<parent>/<repo>.worktrees/<branch>` keeps worktrees beside the repository, not inside it.
    static func defaultPath(repository: String, branch: String) -> String {
        let repo = URL(fileURLWithPath: repository)
        let folder = branch.map { $0 == "/" || $0 == " " || $0 == ":" ? "-" : $0 }
        return repo.deletingLastPathComponent()
            .appendingPathComponent(repo.lastPathComponent + ".worktrees")
            .appendingPathComponent(String(folder)).path
    }

    /// Creates the worktree on a new branch, or checks out the branch if it already exists.
    static func create(repository: String, branch: String) throws -> String {
        let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.git(L("브랜치 이름을 입력하세요.", "Enter a branch name.")) }
        _ = try git(["check-ref-format", "--branch", name], in: repository, fallback: L("'\(name)'은(는) 사용할 수 없는 브랜치 이름입니다.", "'\(name)' is not a valid branch name."))
        let path = defaultPath(repository: repository, branch: name)
        guard !FileManager.default.fileExists(atPath: path) else { throw Failure.git(L("이미 같은 이름의 폴더가 있습니다: \(path)", "A folder with that name already exists: \(path)")) }
        let exists = (try? git(["rev-parse", "--verify", "--quiet", "refs/heads/" + name], in: repository)) != nil
        _ = try git(exists ? ["worktree", "add", path, name] : ["worktree", "add", "-b", name, path], in: repository)
        return path
    }
    /// Removes a linked worktree. Git refuses when it has uncommitted changes; that is surfaced as is.
    static func remove(_ path: String) throws {
        let common = try git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: path)
        let main = URL(fileURLWithPath: common).deletingLastPathComponent().path
        _ = try git(["worktree", "remove", path], in: main,
                    fallback: L("worktree에 커밋하지 않은 변경이 있어 제거하지 않았습니다. 변경을 커밋하거나 정리한 뒤 다시 시도하세요.", "The worktree has uncommitted changes, so it was not removed. Commit or clean up the changes and try again."))
    }

    /// Runs git and returns trimmed stdout; throws with git's message (or `fallback`) on failure.
    @discardableResult
    static func git(_ arguments: [String], in directory: String, fallback: String? = nil) throws -> String {
        guard let git = ShellSafety.executable("git") else { throw Failure.gitMissing }
        let process = Process(), out = Pipe(), err = Pipe()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = ["-C", directory] + arguments
        process.environment = ShellSafety.environment().merging(["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"]) { $1 }
        process.standardOutput = out; process.standardError = err
        try process.run()
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let error = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.git(fallback ?? (message.isEmpty ? L("git 명령이 실패했습니다.", "The git command failed.") : message))
        }
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
