import Foundation
import Supabase
import SwiftUI

#if os(macOS)
extension SessionMemoryStorage: AuthLocalStorage {}
extension SessionFileStorage: AuthLocalStorage {}
#endif

struct PocketCrewCloudConfiguration: Equatable, Sendable {
  let projectURL: URL
  let publishableKey: String
  let redirectURL: URL

  static func load(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main
  ) -> PocketCrewCloudConfiguration? {
    let resourceValues: [String: String] = {
      guard let url = bundle.url(forResource: "CloudConfig", withExtension: "plist"),
        let data = try? Data(contentsOf: url),
        let values = try? PropertyListDecoder().decode([String: String].self, from: data)
      else { return [:] }
      return values
    }()
    func value(_ key: String) -> String? {
      let raw =
        environment[key] ?? bundle.object(forInfoDictionaryKey: key) as? String
        ?? resourceValues[key]
      guard let raw else { return nil }
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.contains("$("), !trimmed.hasPrefix("YOUR_") else {
        return nil
      }
      return trimmed
    }
    guard let urlString = value("POCKETCREW_SUPABASE_URL"),
      let projectURL = URL(string: urlString),
      let publishableKey = value("POCKETCREW_SUPABASE_PUBLISHABLE_KEY")
    else { return nil }
    let redirectURL =
      value("POCKETCREW_AUTH_REDIRECT_URL").flatMap(URL.init(string:))
      ?? URL(string: "pocketcrew://auth-callback")!
    return PocketCrewCloudConfiguration(
      projectURL: projectURL, publishableKey: publishableKey, redirectURL: redirectURL)
  }
}

struct CloudUserIdentity: Equatable, Sendable {
  let id: UUID
  let email: String
}

enum CloudAuthPhase: Equatable {
  case unconfigured
  case signedOut
  case working
  case confirmationSent(String)
  case signedIn(CloudUserIdentity)
}

enum CloudFamilyPhase: Equatable {
  case idle
  case loading
  case needsFamily
  case ready(name: String)
  case failed(String)
}

enum CloudSyncState: Equatable {
  case localOnly
  case saved(Date)
  case saving
  case failed(String)
}

private struct FamilyGuardianRow: Decodable {
  let familyId: UUID
  let role: String

  enum CodingKeys: String, CodingKey {
    case familyId = "family_id"
    case role
  }
}

private struct FamilySnapshotRow: Decodable {
  let familyId: UUID
  let revision: Int
  let state: PocketCrewState

  enum CodingKeys: String, CodingKey {
    case familyId = "family_id"
    case revision, state
  }
}

private struct RevisionResult: Decodable {
  let revision: Int
}

private struct CreateFamilyParameters: Encodable {
  let pFamilyId: UUID
  let pName: String
  let pTimezone: String
  let pCurrency: String
  let pState: PocketCrewState

  enum CodingKeys: String, CodingKey {
    case pFamilyId = "p_family_id"
    case pName = "p_name"
    case pTimezone = "p_timezone"
    case pCurrency = "p_currency"
    case pState = "p_state"
  }
}

private struct SaveFamilyParameters: Encodable {
  let pFamilyId: UUID
  let pExpectedRevision: Int
  let pState: PocketCrewState

  enum CodingKeys: String, CodingKey {
    case pFamilyId = "p_family_id"
    case pExpectedRevision = "p_expected_revision"
    case pState = "p_state"
  }
}

private struct AcceptInviteParameters: Encodable {
  let pToken: String

  enum CodingKeys: String, CodingKey {
    case pToken = "p_token"
  }
}

private struct InviteRequest: Encodable {
  let familyId: UUID
  let email: String
}

private struct InviteResponse: Decodable {
  let delivered: Bool
}

private struct DeleteAccountResponse: Decodable {
  let deleted: Bool
}

private struct ShoppingSearchRequest: Encodable {
  let query: String
  let currency: String
  let locale: String
}

private struct ShoppingSearchResponse: Decodable {
  let items: [ShoppingProduct]
}

@MainActor
final class CloudSessionStore: ObservableObject {
  @Published private(set) var authPhase: CloudAuthPhase
  @Published private(set) var familyPhase: CloudFamilyPhase = .idle
  @Published private(set) var syncState: CloudSyncState = .localOnly
  @Published private(set) var familyId: UUID?
  @Published private(set) var pendingInvitationToken: String?
  @Published private(set) var requiresPasswordUpdate = false
  @Published var usingDemo = false
  @Published var notice: String?

  let configuration: PocketCrewCloudConfiguration?
  private let client: SupabaseClient?
  private weak var appStore: AppStore?
  private var revision = 0
  private var pendingState: PocketCrewState?
  private var syncTask: Task<Void, Never>?
  private var authObserverTask: Task<Void, Never>?
  private var realtimeTask: Task<Void, Never>?
  private var catchUpTask: Task<Void, Never>?
  private var realtimeChannel: RealtimeChannelV2?
  private let defaults: UserDefaults
  private static let pendingInviteKey = "pocketcrew.pendingInvitationToken"

  init(
    configuration: PocketCrewCloudConfiguration? = .load(), defaults: UserDefaults = .standard
  ) {
    self.configuration = configuration
    self.defaults = defaults
    pendingInvitationToken = defaults.string(forKey: Self.pendingInviteKey)
    if let configuration {
      #if os(macOS)
      client = SupabaseClient(
        supabaseURL: configuration.projectURL, supabaseKey: configuration.publishableKey,
        options: .init(auth: .init(storage: SessionFileStorage())))
      #else
      client = SupabaseClient(
        supabaseURL: configuration.projectURL, supabaseKey: configuration.publishableKey)
      #endif
      authPhase = .signedOut
    } else {
      client = nil
      authPhase = .unconfigured
    }
    if let client {
      authObserverTask = Task { [weak self] in
        for await (event, session) in client.auth.authStateChanges {
          guard event == .passwordRecovery, let session else { continue }
          guard let self else { return }
          self.requiresPasswordUpdate = true
          await self.finishSignIn(session: session)
        }
      }
    }
  }

  deinit {
    authObserverTask?.cancel()
    realtimeTask?.cancel()
    catchUpTask?.cancel()
  }

  var isConfigured: Bool { configuration != nil }
  var hasUnsyncedChanges: Bool { pendingState != nil || syncTask != nil }
  var signedInUser: CloudUserIdentity? {
    guard case .signedIn(let user) = authPhase else { return nil }
    return user
  }

  func bind(to store: AppStore) {
    appStore = store
    if let user = signedInUser {
      store.setAuthenticatedGuardian(id: user.id, email: user.email)
    }
  }

  func restoreSession() async {
    guard let client else { return }
    guard !usingDemo else { return }
    do {
      let session = try await client.auth.session
      await finishSignIn(session: session)
    } catch {
      authPhase = .signedOut
      familyPhase = .idle
    }
  }

  func signUp(displayName: String, email: String, password: String) async {
    guard let client, let configuration else {
      showConfigurationNotice()
      return
    }
    await performAuth {
      let response = try await client.auth.signUp(
        email: email, password: password,
        data: ["display_name": .string(displayName)], redirectTo: configuration.redirectURL)
      if let session = response.session {
        await self.finishSignIn(session: session)
      } else {
        self.authPhase = .confirmationSent(email)
        self.notice = "Check \(email) to confirm the account, then return to PocketCrew."
      }
    }
  }

  func signIn(email: String, password: String) async {
    guard let client else {
      showConfigurationNotice()
      return
    }
    await performAuth {
      let session = try await client.auth.signIn(email: email, password: password)
      await self.finishSignIn(session: session)
    }
  }

  func signInWithGoogle() async {
    guard let client, let configuration else {
      showConfigurationNotice()
      return
    }
    await performAuth {
      let session = try await client.auth.signInWithOAuth(
        provider: .google, redirectTo: configuration.redirectURL, scopes: "openid email profile")
      await self.finishSignIn(session: session)
    }
  }

  func sendPasswordReset(email: String) async {
    guard let client, let configuration else {
      showConfigurationNotice()
      return
    }
    await performAuth(restorePhaseAfterSuccess: true) {
      try await client.auth.resetPasswordForEmail(email, redirectTo: configuration.redirectURL)
      self.notice = "A password-reset link is on its way to \(email)."
    }
  }

  func updateRecoveredPassword(_ password: String) async -> Bool {
    guard let client else {
      showConfigurationNotice()
      return false
    }
    guard password.count >= 8 else {
      notice = "Use at least 8 characters for the new password."
      return false
    }
    do {
      try await client.auth.update(user: UserAttributes(password: password))
      requiresPasswordUpdate = false
      notice = "Your password has been updated."
      return true
    } catch {
      notice = error.localizedDescription
      return false
    }
  }

  func handle(url: URL) async {
    guard url.scheme == configuration?.redirectURL.scheme else { return }
    if url.host == "invite",
      let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(
        where: { $0.name == "token" })?.value
    {
      rememberInvitation(token)
      if signedInUser != nil {
        do {
          try await acceptInvite(token: token)
        } catch {
          notice = error.localizedDescription
          await loadFamily()
        }
      }
      return
    }
    guard let client else { return }
    await performAuth {
      let session = try await client.auth.session(from: url)
      await self.finishSignIn(session: session)
    }
  }

  func signOut() async {
    guard let client else { return }
    await stopRealtime(using: client)
    do { try await client.auth.signOut(scope: .local) } catch { notice = error.localizedDescription }
    syncTask?.cancel()
    syncTask = nil
    pendingState = nil
    familyId = nil
    revision = 0
    requiresPasswordUpdate = false
    authPhase = .signedOut
    familyPhase = .idle
    syncState = .localOnly
    appStore?.disconnectCloud()
  }

  func enterDemo() {
    usingDemo = true
    familyPhase = .idle
    syncState = .localOnly
  }

  func leaveDemo() {
    usingDemo = false
  }

  func createFamily(using state: PocketCrewState) async throws {
    guard let client else { throw PocketCrewError.invalid("Cloud service is not configured.") }
    familyPhase = .loading
    notice = nil
    do {
      let sharedState = try await prepareCloudState(state)
      let results: [RevisionResult] =
        try await client.rpc(
          "create_family_account",
          params: CreateFamilyParameters(
            pFamilyId: sharedState.family.id, pName: sharedState.family.name,
            pTimezone: sharedState.family.timezone, pCurrency: sharedState.family.currency,
            pState: sharedState)
        ).execute().value
      guard let result = results.first else {
        throw PocketCrewError.invalid("The family could not be created.")
      }
      familyId = sharedState.family.id
      revision = result.revision
      attach(state)
    } catch {
      familyPhase = .needsFamily
      notice = error.localizedDescription
      throw error
    }
  }

  func acceptInvite(token: String) async throws {
    guard let client else { throw PocketCrewError.invalid("Cloud service is not configured.") }
    familyPhase = .loading
    notice = nil
    do {
      let results: [RevisionResult] =
        try await client.rpc(
          "accept_family_invite", params: AcceptInviteParameters(pToken: token)
        ).execute().value
      guard !results.isEmpty else {
        throw PocketCrewError.invalid("That invitation is not valid.")
      }
      clearRememberedInvitation()
      await loadFamily()
    } catch {
      familyPhase = .needsFamily
      notice = error.localizedDescription
      throw error
    }
  }

  func inviteGuardian(email: String) async throws {
    guard let client, let familyId else {
      throw PocketCrewError.invalid("Open a cloud family before inviting someone.")
    }
    let response: InviteResponse = try await client.functions.invoke(
      "send-family-invite", options: .init(body: InviteRequest(familyId: familyId, email: email)))
    guard response.delivered else {
      throw PocketCrewError.invalid("The invitation email could not be delivered.")
    }
    notice = "Invitation sent to \(email)."
  }

  /// Searches through PocketCrew's authenticated server adapter. SerpApi credentials remain in
  /// the Edge Function environment and are never shipped inside the native app.
  func searchShoppingProducts(query: String, currency: String, locale: String) async throws
    -> [ShoppingProduct]
  {
    guard let client, signedInUser != nil else {
      throw PocketCrewError.invalid("Sign in to a cloud family to search Google Shopping.")
    }
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleanQuery.count >= 2 else { return [] }
    do {
      let response: ShoppingSearchResponse = try await client.functions.invoke(
        "search-shopping-products",
        options: .init(
          body: ShoppingSearchRequest(
            query: String(cleanQuery.prefix(120)), currency: currency, locale: locale)))
      return response.items.filter { $0.priceCents > 0 && $0.matchesCurrency(currency) }
    } catch FunctionsError.httpError(let code, _) {
      // Never surface a raw service response: it can contain upstream request details.
      let message: String
      switch code {
      case 400:
        message = "Live shopping currently supports USD. Use at least two search characters and try again."
      case 401:
        message = "Your sign-in session needs refreshing. Ask a parent to sign out and sign in again."
      case 403:
        message = "Open your cloud family before using live shopping search."
      case 429:
        message = "The live-search allowance has been reached. Please try again later."
      case 404, 503:
        message = "Live shopping setup is not complete. A parent needs to check the Supabase search function and SerpApi secret."
      case 502:
        message = "Google Shopping search is temporarily unavailable. Please try again later."
      default:
        message = "Live shopping search couldn’t finish. Please try again later."
      }
      throw PocketCrewError.invalid(message)
    } catch {
      throw PocketCrewError.invalid("Live shopping couldn’t connect. Check your internet connection and try again.")
    }
  }

  func deleteAccount() async -> Bool {
    guard let client else {
      showConfigurationNotice()
      return false
    }
    do {
      let response: DeleteAccountResponse = try await client.functions.invoke("delete-account")
      guard response.deleted else {
        throw PocketCrewError.invalid("The account deletion was not confirmed.")
      }
      appStore?.clearCloudAccountData()
      await signOut()
      notice = "Your PocketCrew cloud account was deleted."
      return true
    } catch {
      notice = error.localizedDescription
      return false
    }
  }

  func reloadFamily() async {
    guard !hasUnsyncedChanges else {
      notice = "This device has an unsaved change. Retry it or choose Replace with cloud copy."
      return
    }
    await loadFamily()
  }

  func discardLocalChangesAndReload() async {
    guard syncTask == nil else {
      notice = "PocketCrew is still saving. Wait a moment and try again."
      return
    }
    pendingState = nil
    await loadFamily()
    if case .ready = familyPhase {
      notice = "This device now has the latest family copy."
    }
  }

  func retrySync() {
    guard pendingState != nil else { return }
    startSyncLoop()
  }

  func signedProofURL(for path: String) async -> URL? {
    guard let client else { return nil }
    return try? await client.storage.from("proof-images").createSignedURL(
      path: path, expiresIn: 300)
  }

  private func performAuth(
    restorePhaseAfterSuccess: Bool = false, operation: () async throws -> Void
  ) async {
    let previous = authPhase
    authPhase = .working
    notice = nil
    do {
      try await operation()
      if restorePhaseAfterSuccess { authPhase = previous }
    } catch {
      authPhase = previous == .unconfigured ? .unconfigured : .signedOut
      notice = error.localizedDescription
    }
  }

  private func finishSignIn(session: Session) async {
    usingDemo = false
    authPhase = .signedIn(
      CloudUserIdentity(id: session.user.id, email: session.user.email ?? "Signed-in guardian"))
    if let user = signedInUser {
      appStore?.setAuthenticatedGuardian(id: user.id, email: user.email)
    }
    if let token = pendingInvitationToken {
      do {
        try await acceptInvite(token: token)
      } catch {
        notice = error.localizedDescription
        await loadFamily()
      }
    } else {
      await loadFamily()
    }
  }

  private func loadFamily() async {
    guard let client, signedInUser != nil else { return }
    familyPhase = .loading
    do {
      let guardians: [FamilyGuardianRow] = try await client.from("family_guardians")
        .select("family_id,role").limit(1).execute().value
      guard let guardian = guardians.first else {
        familyId = nil
        familyPhase = .needsFamily
        return
      }
      let snapshots: [FamilySnapshotRow] = try await client.from("family_snapshots").select()
        .eq("family_id", value: guardian.familyId).limit(1).execute().value
      guard let snapshot = snapshots.first else {
        throw PocketCrewError.invalid("This family has no shared ledger yet.")
      }
      familyId = snapshot.familyId
      revision = snapshot.revision
      attach(snapshot.state)
    } catch {
      familyPhase = .failed(error.localizedDescription)
    }
  }

  private func attach(_ state: PocketCrewState) {
    guard let user = signedInUser else { return }
    appStore?.connectCloud(state: state, guardianId: user.id, guardianEmail: user.email) {
      [weak self] newState in
      self?.queueSave(newState)
    }
    familyPhase = .ready(name: state.family.name)
    syncState = .saved(Date())
    startRealtime(for: state.family.id)
  }

  private func startRealtime(for familyId: UUID) {
    guard let client else { return }
    catchUpTask?.cancel()
    catchUpTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.catchUpFamily()
        do { try await Task.sleep(for: .seconds(15)) } catch { return }
      }
    }
    realtimeTask?.cancel()
    if let oldChannel = realtimeChannel {
      Task { await client.removeChannel(oldChannel) }
    }
    realtimeChannel = nil
    realtimeTask = Task { [weak self, client] in
      let channel = client.channel("pocketcrew-family-\(familyId.uuidString.lowercased())")
      let updates = channel.postgresChange(
        UpdateAction.self, schema: "public", table: "family_snapshots",
        filter: .eq("family_id", value: familyId))
      do {
        try await channel.subscribeWithError()
        guard !Task.isCancelled else {
          await client.removeChannel(channel)
          return
        }
        self?.realtimeChannel = channel
        for await update in updates {
          guard !Task.isCancelled else { break }
          do {
            let snapshot: FamilySnapshotRow = try update.decodeRecord(
              decoder: PostgrestClient.Configuration.jsonDecoder)
            self?.receiveRealtime(snapshot)
          } catch {
            self?.notice = "A family update arrived but could not be opened."
          }
        }
      } catch {
        guard !Task.isCancelled else { return }
        self?.notice = "Live family updates are offline. You can still reload from Settings."
      }
    }
  }

  private func receiveRealtime(_ snapshot: FamilySnapshotRow) {
    guard !usingDemo else { return }
    guard snapshot.familyId == familyId, snapshot.revision > revision else { return }
    guard syncTask == nil, pendingState == nil else { return }
    revision = snapshot.revision
    appStore?.refreshCloud(state: snapshot.state)
    familyPhase = .ready(name: snapshot.state.family.name)
    syncState = .saved(Date())
  }

  private func stopRealtime(using client: SupabaseClient) async {
    catchUpTask?.cancel()
    catchUpTask = nil
    realtimeTask?.cancel()
    realtimeTask = nil
    if let realtimeChannel { await client.removeChannel(realtimeChannel) }
    realtimeChannel = nil
  }

  private func queueSave(_ state: PocketCrewState) {
    pendingState = state
    startSyncLoop()
  }

  // Fetch after reconnection and after saves: Realtime events may be missed while
  // suspended or intentionally skipped while this device has a pending write.
  private func catchUpFamily() async {
    guard let client, let requestedFamily = familyId, signedInUser != nil,
      !usingDemo, !hasUnsyncedChanges else { return }
    do {
      let snapshots: [FamilySnapshotRow] = try await client.from("family_snapshots")
        .select().eq("family_id", value: requestedFamily).limit(1).execute().value
      guard !Task.isCancelled, requestedFamily == familyId,
        let snapshot = snapshots.first else { return }
      receiveRealtime(snapshot)
    } catch {
      // Keep the last good copy. The next periodic fetch retries automatically.
    }
  }

  private func startSyncLoop() {
    guard syncTask == nil else { return }
    syncTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled, let state = self.pendingState {
        self.pendingState = nil
        self.syncState = .saving
        do {
          try await self.push(state)
          self.syncState = .saved(Date())
        } catch {
          if self.pendingState == nil { self.pendingState = state }
          self.syncState = .failed(error.localizedDescription)
          break
        }
      }
      self.syncTask = nil
      await self.catchUpFamily()
    }
  }

  private func push(_ state: PocketCrewState) async throws {
    guard let client, let familyId else {
      throw PocketCrewError.invalid("The cloud family is no longer connected.")
    }
    let sharedState = try await prepareCloudState(state)
    let results: [RevisionResult] =
      try await client.rpc(
        "save_family_snapshot",
        params: SaveFamilyParameters(
          pFamilyId: familyId, pExpectedRevision: revision, pState: sharedState)
      ).execute().value
    guard let result = results.first else {
      throw PocketCrewError.invalid("The cloud ledger did not confirm the save.")
    }
    revision = result.revision
  }

  private func prepareCloudState(_ state: PocketCrewState) async throws -> PocketCrewState {
    guard let client else { throw PocketCrewError.invalid("Cloud service is not configured.") }
    var result = state
    for index in result.submissions.indices {
      guard var proof = result.submissions[index].proofImage else { continue }
      if proof.storagePath == nil, let data = proof.bookmarkData {
        guard data.count <= 8_000_000 else {
          throw PocketCrewError.invalid("Proof images must be smaller than 8 MB.")
        }
        let fileExtension = safeImageExtension(for: proof.fileName)
        let path =
          "\(result.family.id.uuidString.lowercased())/\(result.submissions[index].id.uuidString.lowercased())/proof.\(fileExtension)"
        try await client.storage.from("proof-images").upload(
          path, data: data,
          options: FileOptions(
            cacheControl: "300", contentType: contentType(for: fileExtension),
            upsert: true))
        proof.storagePath = path
      }
      proof.bookmarkData = nil
      result.submissions[index].proofImage = proof
    }
    appStore?.cacheCloudProofReferences(from: result)
    return result
  }

  private func safeImageExtension(for fileName: String) -> String {
    switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
    case "png": "png"
    case "heic", "heif": "heic"
    default: "jpg"
    }
  }

  private func contentType(for fileExtension: String) -> String {
    switch fileExtension {
    case "png": "image/png"
    case "heic": "image/heic"
    default: "image/jpeg"
    }
  }

  private func showConfigurationNotice() {
    notice =
      "Cloud sign-in needs POCKETCREW_SUPABASE_URL and POCKETCREW_SUPABASE_PUBLISHABLE_KEY. Demo mode still works without them."
  }

  private func rememberInvitation(_ token: String) {
    pendingInvitationToken = token
    defaults.set(token, forKey: Self.pendingInviteKey)
  }

  private func clearRememberedInvitation() {
    pendingInvitationToken = nil
    defaults.removeObject(forKey: Self.pendingInviteKey)
  }
}
