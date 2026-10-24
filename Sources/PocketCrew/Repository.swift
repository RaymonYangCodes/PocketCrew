import Foundation

protocol PocketCrewRepository {
  func load() throws -> PocketCrewState
  func save(_ state: PocketCrewState) throws
  func reset() throws -> PocketCrewState
  func delete() throws
}

struct LocalJSONRepository: PocketCrewRepository {
  private let fileURL: URL
  init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
      return
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
    self.fileURL = base.appendingPathComponent("PocketCrew", isDirectory: true)
      .appendingPathComponent("family-ledger.json")
  }
  func load() throws -> PocketCrewState {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return try reset() }
    let data = try Data(contentsOf: fileURL)
    return try Self.decoder.decode(PocketCrewState.self, from: data)
  }
  func save(_ state: PocketCrewState) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try Self.encoder.encode(state)
    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
  }
  func reset() throws -> PocketCrewState {
    let state = DemoData.make()
    try save(state)
    return state
  }
  func delete() throws {
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try FileManager.default.removeItem(at: fileURL)
    }
  }
  static let encoder: JSONEncoder = {
    let value = JSONEncoder()
    value.dateEncodingStrategy = .iso8601
    value.outputFormatting = [.prettyPrinted, .sortedKeys]
    return value
  }()
  static let decoder: JSONDecoder = {
    let value = JSONDecoder()
    value.dateDecodingStrategy = .iso8601
    return value
  }()
}

/// Public client configuration only. Service-role keys must never ship in the app.
struct RemoteRepositoryConfiguration: Codable {
  let baseURL: URL
  let publicAnonymousKey: String
}
