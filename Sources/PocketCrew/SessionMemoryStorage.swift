import Foundation

/// Ephemeral credentials for ad-hoc macOS builds. Never writes tokens to disk
/// or weakens Keychain permissions. A new process requires a fresh sign-in.
final class SessionMemoryStorage: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Data] = [:]

  func store(key: String, value: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    values[key] = value
  }

  func retrieve(key: String) throws -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return values[key]
  }

  func remove(key: String) throws {
    lock.lock()
    defer { lock.unlock() }
    values.removeValue(forKey: key)
  }
}
