import CryptoKit
import Foundation

/// User-requested, no-Keychain persistence. These are unencrypted bearer tokens,
/// protected by owner-only filesystem permissions, not by profile PINs.
final class SessionFileStorage: @unchecked Sendable {
  private let directory: URL
  private let lock = NSLock()

  init(directory: URL? = nil) {
    self.directory = directory ?? FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("PocketCrew/AuthSession", isDirectory: true)
  }
  private func location(_ key: String) -> URL {
    let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(name + ".session")
  }
  private func prepare() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    var url = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }
  func store(key: String, value: Data) throws {
    lock.lock(); defer { lock.unlock() }
    try prepare()
    let file = location(key)
    try value.write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
  func retrieve(key: String) throws -> Data? {
    lock.lock(); defer { lock.unlock() }
    let file = location(key)
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    try prepare()
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    return try Data(contentsOf: file)
  }
  func remove(key: String) throws {
    lock.lock(); defer { lock.unlock() }
    let file = location(key)
    if FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
  }
}
