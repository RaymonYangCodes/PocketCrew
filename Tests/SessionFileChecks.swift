import Foundation

@main struct SessionFileChecks {
  static func main() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = SessionFileStorage(directory: directory)
    let token = Data("synthetic-session-only".utf8)
    try first.store(key: "../session", value: token)
    let restarted = SessionFileStorage(directory: directory)
    let restored = try restarted.retrieve(key: "../session")
    precondition(restored == token)
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    precondition(files.count == 1)
    let folderMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as! NSNumber
    let fileMode = try FileManager.default.attributesOfItem(atPath: files[0].path)[.posixPermissions] as! NSNumber
    precondition(folderMode.intValue == 0o700 && fileMode.intValue == 0o600)
    try restarted.remove(key: "../session")
    let removed = try first.retrieve(key: "../session")
    precondition(removed == nil)
    print("Session storage passed: restart, safe paths, owner-only permissions, sign-out removal.")
  }
}
