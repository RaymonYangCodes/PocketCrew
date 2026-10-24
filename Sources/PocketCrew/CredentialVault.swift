import CryptoKit
import Foundation

enum ProfileAccessTarget: Hashable, Identifiable {
  case parent
  case child(UUID)

  var id: String {
    switch self {
    case .parent: "parent"
    case .child(let childId): "child-\(childId.uuidString)"
    }
  }
}

private struct StoredCredential: Codable {
  let salt: String
  let digest: String
}

struct CredentialVault {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func ensureDefaults(for state: PocketCrewState) {
    if credential(for: .parent, familyId: state.family.id) == nil {
      set(passcode: "2468", for: .parent, familyId: state.family.id)
    }
    for child in state.children
    where credential(for: .child(child.id), familyId: state.family.id) == nil {
      let demoCode =
        child.id == DemoData.jordanId ? "1212" : child.id == DemoData.rileyId ? "0808" : "1234"
      set(passcode: demoCode, for: .child(child.id), familyId: state.family.id)
    }
  }

  func verify(_ passcode: String, target: ProfileAccessTarget, familyId: UUID) -> Bool {
    guard let stored = credential(for: target, familyId: familyId) else { return false }
    return Self.digest(passcode: passcode, salt: stored.salt) == stored.digest
  }

  func contains(_ target: ProfileAccessTarget, familyId: UUID) -> Bool {
    credential(for: target, familyId: familyId) != nil
  }

  func set(passcode: String, for target: ProfileAccessTarget, familyId: UUID) {
    let salt = UUID().uuidString
    let stored = StoredCredential(salt: salt, digest: Self.digest(passcode: passcode, salt: salt))
    guard let data = try? JSONEncoder().encode(stored) else { return }
    defaults.set(data, forKey: key(for: target, familyId: familyId))
  }

  func clear(familyId: UUID) {
    let prefix = "pocketcrew.credential.\(familyId.uuidString)."
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
      defaults.removeObject(forKey: key)
    }
  }

  private func credential(for target: ProfileAccessTarget, familyId: UUID) -> StoredCredential? {
    guard let data = defaults.data(forKey: key(for: target, familyId: familyId)) else { return nil }
    return try? JSONDecoder().decode(StoredCredential.self, from: data)
  }

  private func key(for target: ProfileAccessTarget, familyId: UUID) -> String {
    "pocketcrew.credential.\(familyId.uuidString).\(target.id)"
  }

  private static func digest(passcode: String, salt: String) -> String {
    SHA256.hash(data: Data("\(salt):\(passcode)".utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

extension String {
  var isFourDigitPasscode: Bool {
    count == 4 && allSatisfy(\.isNumber)
  }
}
