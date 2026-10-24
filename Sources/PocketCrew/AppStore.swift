import Foundation
import SwiftUI

enum AppRole: String, CaseIterable, Identifiable {
  case parent, child
  var id: String { rawValue }
}
enum AppDestination: String, CaseIterable, Identifiable {
  case home, work, payday, jars, family, settings, profile
  var id: String { rawValue }
  var title: String { self == .work ? "Tasks" : self == .jars ? "Jars" : rawValue.capitalized }
  var section: AppDestination {
    switch self {
    case .payday: .jars
    case .family, .profile: .settings
    default: self
    }
  }
  var icon: String {
    switch self {
    case .home: "house.fill"
    case .work: "checkmark.circle.fill"
    case .payday: "sparkles"
    case .jars: "shippingbox.fill"
    case .family: "person.2.fill"
    case .settings: "gearshape.fill"
    case .profile: "person.crop.circle.fill"
    }
  }
}

@MainActor
final class AppStore: ObservableObject {
  @Published private(set) var state: PocketCrewState
  @Published private(set) var role: AppRole = .parent
  @Published var destination: AppDestination = .home
  @Published private(set) var selectedChildId: UUID
  @Published var toast: ToastMessage?
  @Published private(set) var sessionUnlocked = false
  private let repository: PocketCrewRepository
  private let credentialVault: CredentialVault
  private var cloudChangeHandler: ((PocketCrewState) -> Void)?
  private var authenticatedGuardianId: UUID?
  private var authenticatedGuardianEmail: String?

  init(
    repository: PocketCrewRepository = LocalJSONRepository(),
    credentialVault: CredentialVault = CredentialVault()
  ) {
    self.repository = repository
    self.credentialVault = credentialVault
    let loaded = (try? repository.load()) ?? DemoData.make()
    self.state = loaded
    let stored = UserDefaults.standard.string(forKey: "selectedChildId").flatMap(
      UUID.init(uuidString:))
    self.selectedChildId =
      loaded.children.contains(where: { $0.id == stored }) ? stored! : loaded.children[0].id
    if loaded.family.id == DemoData.familyId {
      credentialVault.ensureDefaults(for: loaded)
    }
  }

  var selectedChild: ChildProfile {
    state.children.first(where: { $0.id == selectedChildId }) ?? state.children[0]
  }
  var profilePasscodesReady: Bool {
    credentialVault.contains(.parent, familyId: state.family.id)
      && state.children.allSatisfy {
        credentialVault.contains(.child($0.id), familyId: state.family.id)
      }
  }
  var guardianId: UUID {
    authenticatedGuardianId
      ?? state.members.first(where: { $0.role == .guardian && $0.inviteState == "active" })?.userId
      ?? DemoData.mayaId
  }
  var guardianDisplayName: String {
    state.users.first(where: { $0.id == guardianId })?.displayName
      ?? state.users.first?.displayName
      ?? "Parent"
  }
  var destinations: [AppDestination] {
    [.home, .work, .jars, .settings]
  }
  var shoppingEntries: [ShoppingEntry] {
    (state.shoppingEntries ?? []).sorted { $0.createdAt > $1.createdAt }
  }

  func selectChild(_ id: UUID) {
    guard sessionUnlocked, role == .parent else { return }
    setSelectedChild(id)
  }
  func viewChildAsParent(_ id: UUID) throws {
    try requireParent()
    guard state.children.contains(where: { $0.id == id }) else {
      throw PocketCrewError.notFound("child profile")
    }
    setSelectedChild(id)
    role = .child
    destination = .home
  }
  private func setSelectedChild(_ id: UUID) {
    guard state.children.contains(where: { $0.id == id }) else { return }
    selectedChildId = id
    UserDefaults.standard.set(id.uuidString, forKey: "selectedChildId")
  }
  func unlock(profileName: String, passcode: String) throws {
    let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw PocketCrewError.invalid("Enter your profile name and passcode.") }
    func matches(_ candidate: String) -> Bool {
      candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        .compare(name, options: [.caseInsensitive]) == .orderedSame
    }
    var targets: [ProfileAccessTarget] = []
    if matches(guardianDisplayName) || matches("Parent") { targets.append(.parent) }
    targets += state.children.filter { $0.status == "active" && matches($0.name) }.map { .child($0.id) }
    let verified = targets.filter { credentialVault.verify(passcode, target: $0, familyId: state.family.id) }
    guard verified.count == 1, let target = verified.first else {
      throw PocketCrewError.invalid("That profile name and passcode didn’t match. Try again.")
    }
    try unlock(target, passcode: passcode)
  }

  func unlock(_ target: ProfileAccessTarget, passcode: String) throws {
    guard credentialVault.verify(passcode, target: target, familyId: state.family.id) else {
      throw PocketCrewError.invalid("That passcode didn’t match. Try again.")
    }
    switch target {
    case .parent:
      role = .parent
    case .child(let childId):
      guard state.children.contains(where: { $0.id == childId }) else {
        throw PocketCrewError.notFound("child profile")
      }
      setSelectedChild(childId)
      role = .child
    }
    destination = .home
    sessionUnlocked = true
  }
  func lock() {
    sessionUnlocked = false
    toast = nil
  }

  func dismissWorkPresets() throws {
    try requireParent()
    state.family.workPresetsDismissed = true
    state.family.updatedAt = Date()
    try persist(success: "Presets are always available from Work → Show presets.")
  }
  func setAuthenticatedGuardian(id: UUID, email: String) {
    authenticatedGuardianId = id
    authenticatedGuardianEmail = email
  }

  func connectCloud(
    state cloudState: PocketCrewState, guardianId: UUID, guardianEmail: String,
    onChange: @escaping (PocketCrewState) -> Void
  ) {
    setAuthenticatedGuardian(id: guardianId, email: guardianEmail)
    state = cloudState
    let identityChanged = mergeAuthenticatedGuardian()
    if let firstChild = state.children.first,
      !state.children.contains(where: { $0.id == selectedChildId })
    {
      selectedChildId = firstChild.id
      UserDefaults.standard.set(firstChild.id.uuidString, forKey: "selectedChildId")
    }
    cloudChangeHandler = onChange
    sessionUnlocked = false
    destination = .home
    try? repository.save(state)
    if identityChanged { cloudChangeHandler?(state) }
  }

  func refreshCloud(state cloudState: PocketCrewState) {
    if role == .child && !cloudState.children.contains(where: { $0.id == selectedChildId }) {
      sessionUnlocked = false
    }
    state = cloudState
    let identityChanged = mergeAuthenticatedGuardian()
    if let firstChild = state.children.first,
      !state.children.contains(where: { $0.id == selectedChildId })
    {
      setSelectedChild(firstChild.id)
    }
    try? repository.save(state)
    if identityChanged { cloudChangeHandler?(state) }
    toast = ToastMessage(text: "Family updated from another device", isError: false)
  }

  func disconnectCloud() {
    cloudChangeHandler = nil
    authenticatedGuardianId = nil
    authenticatedGuardianEmail = nil
    state = DemoData.make()
    selectedChildId = state.children[0].id
    credentialVault.ensureDefaults(for: state)
    try? repository.save(state)
    lock()
  }

  func clearCloudAccountData() {
    credentialVault.clear(familyId: state.family.id)
    try? repository.delete()
  }

  /// Reconciles a pending email-only co-parent entry with the authenticated Supabase user ID.
  private func mergeAuthenticatedGuardian() -> Bool {
    guard let authenticatedGuardianId, let authenticatedGuardianEmail else { return false }
    let normalizedEmail = authenticatedGuardianEmail.lowercased()
    if let userIndex = state.users.firstIndex(where: { $0.id == authenticatedGuardianId }) {
      var changed = false
      if state.users[userIndex].email?.lowercased() != normalizedEmail {
        state.users[userIndex].email = normalizedEmail
        changed = true
      }
      if state.users[userIndex].status != "active" {
        state.users[userIndex].status = "active"
        changed = true
      }
      if !state.members.contains(where: {
        $0.userId == authenticatedGuardianId && $0.role == .guardian
      }) {
        let now = Date()
        state.members.append(
          FamilyMember(
            id: UUID(), createdAt: now, updatedAt: now, createdBy: authenticatedGuardianId,
            familyId: state.family.id, userId: authenticatedGuardianId, childId: nil,
            role: .guardian, inviteState: "active"))
        changed = true
      }
      return changed
    }

    let now = Date()
    if let pendingUserIndex = state.users.firstIndex(where: {
      $0.email?.lowercased() == normalizedEmail && $0.status == "invited"
    }) {
      let pending = state.users[pendingUserIndex]
      let pendingId = pending.id
      state.users[pendingUserIndex] = User(
        id: authenticatedGuardianId, createdAt: pending.createdAt, updatedAt: now,
        createdBy: pending.createdBy, displayName: pending.displayName,
        email: normalizedEmail, status: "active")
      if let memberIndex = state.members.firstIndex(where: { $0.userId == pendingId }) {
        state.members[memberIndex].userId = authenticatedGuardianId
        state.members[memberIndex].inviteState = "active"
        state.members[memberIndex].updatedAt = now
      }
    } else {
      state.users.append(
        User(
          id: authenticatedGuardianId, createdAt: now, updatedAt: now,
          createdBy: authenticatedGuardianId, displayName: "Co-parent",
          email: normalizedEmail, status: "active"))
      state.members.append(
        FamilyMember(
          id: UUID(), createdAt: now, updatedAt: now, createdBy: authenticatedGuardianId,
          familyId: state.family.id, userId: authenticatedGuardianId, childId: nil,
          role: .guardian, inviteState: "active"))
    }
    return true
  }

  func configureDevicePasscodes(parent: String, children: [UUID: String]) throws {
    guard !profilePasscodesReady else {
      throw PocketCrewError.invalid("Passcodes are already configured on this device.")
    }
    guard parent.isFourDigitPasscode,
      state.children.allSatisfy({ children[$0.id]?.isFourDigitPasscode == true })
    else {
      throw PocketCrewError.invalid("Choose a four-digit passcode for every profile.")
    }
    credentialVault.set(passcode: parent, for: .parent, familyId: state.family.id)
    for child in state.children {
      credentialVault.set(
        passcode: children[child.id]!, for: .child(child.id), familyId: state.family.id)
    }
    state.audit.append(
      AuditEvent(
        id: UUID(), createdAt: Date(), updatedAt: Date(), createdBy: guardianId,
        familyId: state.family.id, actorId: guardianId, action: "device.passcodes_configured",
        entityType: "Family", entityId: state.family.id, detail: nil))
    try persist(success: "Profile passcodes secured on this device")
  }

  func cacheCloudProofReferences(from sharedState: PocketCrewState) {
    var changed = false
    for sharedSubmission in sharedState.submissions {
      guard let path = sharedSubmission.proofImage?.storagePath,
        let index = state.submissions.firstIndex(where: { $0.id == sharedSubmission.id }),
        var localProof = state.submissions[index].proofImage,
        localProof.storagePath != path
      else { continue }
      localProof.storagePath = path
      state.submissions[index].proofImage = localProof
      changed = true
    }
    if changed { try? repository.save(state) }
  }
  func verifyParentPasscode(_ passcode: String) -> Bool {
    credentialVault.verify(passcode, target: .parent, familyId: state.family.id)
  }
  func demoPasscodeHint(for target: ProfileAccessTarget) -> String? {
    guard state.family.id == DemoData.familyId else { return nil }
    guard !UserDefaults.standard.bool(forKey: demoHintChangedKey(for: target)) else { return nil }
    switch target {
    case .parent: return "2468"
    case .child(DemoData.jordanId): return "1212"
    case .child(DemoData.rileyId): return "0808"
    default: return nil
    }
  }
  func item(for assignment: WorkAssignment) -> WorkItem? {
    state.workItems.first { $0.id == assignment.workItemId }
  }
  func child(_ id: UUID?) -> ChildProfile? { state.children.first { $0.id == id } }
  func submission(for assignmentId: UUID) -> WorkSubmission? {
    state.submissions.last { $0.assignmentId == assignmentId }
  }
  func split(for childId: UUID) -> SplitRule? { state.splits.first { $0.childId == childId } }
  func goal(for childId: UUID) -> SavingsGoal? {
    state.goals.first { $0.childId == childId && $0.featured && $0.status == .active }
  }
  func balance(_ jar: JarKind, childId: UUID) -> Money {
    FinanceEngine.jarBalance(in: state, childId: childId, jar: jar)
  }
  func pending(childId: UUID? = nil) -> Money {
    FinanceEngine.pendingEarnings(in: state, childId: childId)
  }

  func createWork(
    type: WorkType, title: String, instructions: String, category: String, childId: UUID?,
    recurrence: Recurrence, dueAt: Date, minutes: Int?, reward: Money, proof: Bool, claimable: Bool,
    checklist: [String]
  ) throws {
    try requireParent()
    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw PocketCrewError.invalid("Give the work a clear title.")
    }
    guard type == .responsibility || reward > 0 else {
      throw PocketCrewError.invalid("Set a reward greater than $0 for a paid gig.")
    }
    let now = Date()
    let workId = UUID()
    let fixedReward = type == .responsibility ? 0 : reward
    state.workItems.append(
      WorkItem(
        id: workId, createdAt: now, updatedAt: now, createdBy: guardianId,
        familyId: state.family.id, type: type, title: title, instructions: instructions,
        category: category, rewardCents: fixedReward, recurrence: recurrence, proofRequired: proof,
        claimable: claimable, checklist: checklist, lifecycleStatus: "active"))
    state.assignments.append(
      WorkAssignment(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, workItemId: workId,
        familyId: state.family.id, childId: childId, dueAt: dueAt, rewardSnapshotCents: fixedReward,
        status: childId == nil ? .available : .assigned, checklistDone: [],
        estimatedMinutes: minutes))
    state.audit.append(
      AuditEvent(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
        familyId: state.family.id, actorId: guardianId, action: "work.created",
        entityType: "WorkItem", entityId: workId, detail: type.rawValue))
    try persist(success: type == .gig ? "Gig added to the crew" : "Responsibility added")
  }

  func start(_ assignmentId: UUID) throws {
    try requireChild()
    guard let index = state.assignments.firstIndex(where: { $0.id == assignmentId }) else {
      throw PocketCrewError.notFound("work item")
    }
    guard
      state.assignments[index].childId == nil
        || state.assignments[index].childId == selectedChildId
    else { throw PocketCrewError.invalid("That work belongs to another child.") }
    guard [.available, .assigned, .redoRequested].contains(state.assignments[index].status) else {
      throw PocketCrewError.invalid("That work cannot be started right now.")
    }
    state.assignments[index].childId = selectedChildId
    state.assignments[index].status = .inProgress
    state.assignments[index].updatedAt = Date()
    try persist(success: "Ready when you are")
  }
  func toggleStep(_ step: String, assignmentId: UUID) throws {
    try requireChild()
    guard let index = state.assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
    guard state.assignments[index].childId == selectedChildId else {
      throw PocketCrewError.invalid("That work belongs to another child.")
    }
    if state.assignments[index].checklistDone.contains(step) {
      state.assignments[index].checklistDone.removeAll { $0 == step }
    } else {
      state.assignments[index].checklistDone.append(step)
    }
    state.assignments[index].updatedAt = Date()
    try persist()
  }
  func submit(_ assignmentId: UUID, note: String, proof: ProofImage?) throws {
    try requireChild()
    try FinanceEngine.submit(
      assignmentId: assignmentId, childId: selectedChildId, note: note, proof: proof, state: &state)
    try persist(success: "Sent to your grown-up for review")
  }
  func approve(_ submissionId: UUID) throws {
    try requireParent()
    try FinanceEngine.approve(submissionId: submissionId, guardianId: guardianId, state: &state)
    try persist(success: "Approved — great work!")
  }
  func decide(_ submissionId: UUID, decision: DecisionKind, reason: String) throws {
    try requireParent()
    try FinanceEngine.decide(
      submissionId: submissionId, guardianId: guardianId, decision: decision, reason: reason,
      state: &state)
    try persist(success: decision == .redoRequested ? "Kind redo note sent" : "Decision recorded")
  }
  func runPayday(early: Bool) throws -> Payday {
    try requireParent()
    let key = "payday:\(state.schedule.nextPaydayAt.ISO8601Format())"
    let payday = try FinanceEngine.runPayday(
      guardianId: guardianId, idempotencyKey: key, early: early, state: &state)
    try persist(success: "Payday complete — jars filled!")
    return payday
  }
  func record(childId: UUID, jar: JarKind, amount: Money, category: LedgerCategory, reason: String)
    throws
  {
    try requireParent()
    try FinanceEngine.record(
      childId: childId, jar: jar, amount: amount, category: category, reason: reason,
      guardianId: guardianId, state: &state)
    try persist(success: "Entry added to the ledger")
  }
  func addMoney(childId: UUID, amount: Money, reason: String) throws {
    try requireParent()
    guard state.children.contains(where: { $0.id == childId }), let rule = split(for: childId),
      amount > 0, amount <= 100_000_000,
      [rule.spendPercent, rule.savePercent, rule.givePercent].allSatisfy({ (0...100).contains($0) }) else {
      throw PocketCrewError.invalid("Choose a child and a positive amount up to 1,000,000.")
    }
    let parts = try FinanceEngine.split(total: amount, rule: rule)
    var updated = state
    for (jar, value) in [(JarKind.spend, parts.spend), (.save, parts.save), (.give, parts.give)] where value > 0 {
      try FinanceEngine.record(childId: childId, jar: jar, amount: value, category: .adjustment,
        reason: "Money added · \(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Parent deposit" : reason)", guardianId: guardianId, state: &updated)
    }
    state = updated
    try persist(success: "Money added and split between jars")
  }
  func selectChildJars(_ childId: UUID) throws {
    try requireParent()
    guard state.children.contains(where: { $0.id == childId }) else { throw PocketCrewError.notFound("child") }
    selectedChildId = childId
  }
  func addShoppingProduct(
    _ product: ShoppingProduct, for childId: UUID, destination: ShoppingEntryStatus
  ) throws {
    guard destination == .wishlist || destination == .awaitingApproval else {
      throw PocketCrewError.invalid("Choose Wishlist or Cart for this item.")
    }
    guard state.children.contains(where: { $0.id == childId }) else {
      throw PocketCrewError.notFound("child profile")
    }
    guard product.priceCents > 0, product.matchesCurrency(state.family.currency) else {
      throw PocketCrewError.invalid("This item needs a valid price in your family’s currency.")
    }
    let actorId: UUID
    if role == .child {
      try requireChild()
      guard childId == selectedChildId else {
        throw PocketCrewError.invalid("You can only add items to your own list.")
      }
      actorId = selectedChildId
    } else {
      try requireParent()
      actorId = guardianId
    }
    let existing = (state.shoppingEntries ?? []).contains {
      $0.childId == childId && $0.product.id == product.id
        && [.wishlist, .awaitingApproval].contains($0.status)
    }
    guard !existing else {
      throw PocketCrewError.invalid("That item is already on this child’s wishlist or cart.")
    }
    let now = Date()
    let entry = ShoppingEntry(
      id: UUID(), createdAt: now, updatedAt: now, createdBy: actorId,
      familyId: state.family.id, childId: childId, product: product, status: destination,
      childNote: nil, parentNote: nil, resolvedAt: nil, ledgerTransactionId: nil)
    var entries = state.shoppingEntries ?? []
    entries.append(entry)
    state.shoppingEntries = entries
    appendShoppingAudit(
      action: destination == .wishlist ? "shopping.wishlist_added" : "shopping.cart_requested",
      entry: entry, actorId: actorId)
    try persist(success: destination == .wishlist ? "Added to wishlist" : "Sent for approval")
  }

  func moveShoppingEntryToCart(_ entryId: UUID) throws {
    guard var entries = state.shoppingEntries,
      let index = entries.firstIndex(where: { $0.id == entryId && $0.status == .wishlist })
    else { throw PocketCrewError.notFound("wishlist item") }
    let actorId: UUID
    if role == .child {
      try requireChild()
      guard entries[index].childId == selectedChildId else {
        throw PocketCrewError.invalid("You can only change your own wishlist.")
      }
      actorId = selectedChildId
    } else {
      try requireParent()
      actorId = guardianId
    }
    entries[index].status = .awaitingApproval
    entries[index].updatedAt = Date()
    state.shoppingEntries = entries
    appendShoppingAudit(action: "shopping.cart_requested", entry: entries[index], actorId: actorId)
    try persist(success: "Moved to cart for parent approval")
  }

  func removeShoppingEntry(_ entryId: UUID) throws {
    guard var entries = state.shoppingEntries,
      let index = entries.firstIndex(where: {
        $0.id == entryId && [.wishlist, .awaitingApproval].contains($0.status)
      })
    else { throw PocketCrewError.notFound("shopping item") }
    let actorId: UUID
    if role == .child {
      try requireChild()
      guard entries[index].childId == selectedChildId else {
        throw PocketCrewError.invalid("You can only change your own shopping list.")
      }
      actorId = selectedChildId
    } else {
      try requireParent()
      actorId = guardianId
    }
    entries[index].status = .removed
    entries[index].updatedAt = Date()
    entries[index].resolvedAt = Date()
    state.shoppingEntries = entries
    appendShoppingAudit(action: "shopping.item_removed", entry: entries[index], actorId: actorId)
    try persist(success: "Item removed")
  }

  /// Records a simulated family purchase. It never places an order with Amazon or another store.
  func updateShoppingPrice(_ entryId: UUID, priceCents: Money, reason: String) throws {
    try requireParent()
    let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    guard priceCents > 0, priceCents <= 100_000_000 else {
      throw PocketCrewError.invalid("Enter a price between 0.01 and 1,000,000.")
    }
    guard !reason.isEmpty else { throw PocketCrewError.invalid("Add a reason for the price change.") }
    guard var entries = state.shoppingEntries,
      let index = entries.firstIndex(where: {
        $0.id == entryId && [.wishlist, .awaitingApproval].contains($0.status)
      }) else { throw PocketCrewError.invalid("Only wishlist and pending cart prices can be changed.") }
    guard entries[index].product.matchesCurrency(state.family.currency) else {
      throw PocketCrewError.invalid("The item currency must match your family currency.")
    }
    let oldPrice = entries[index].product.priceCents
    entries[index].product.priceCents = priceCents
    entries[index].updatedAt = Date()
    entries[index].parentNote = "Price set by parent: \(reason)"
    state.shoppingEntries = entries
    state.audit.append(AuditEvent(
      id: UUID(), createdAt: Date(), updatedAt: Date(), createdBy: guardianId,
      familyId: state.family.id, actorId: guardianId, action: "shopping.price_changed",
      entityType: "ShoppingEntry", entityId: entryId,
      detail: "\(oldPrice) → \(priceCents) cents. \(reason)"))
    try persist(success: "Item price updated — no money deducted")
  }

  func approveShoppingPurchase(_ entryId: UUID) throws {
    try requireParent()
    guard var entries = state.shoppingEntries,
      let index = entries.firstIndex(where: { $0.id == entryId && $0.status == .awaitingApproval })
    else { throw PocketCrewError.notFound("cart request") }
    let entry = entries[index]
    guard entry.product.matchesCurrency(state.family.currency) else {
      throw PocketCrewError.invalid("This item’s currency does not match your family. Search for it again before approving.")
    }
    guard entry.product.priceCents > 0 else {
      throw PocketCrewError.invalid("This item needs a valid price before it can be approved.")
    }
    try FinanceEngine.record(
      childId: entry.childId, jar: .spend, amount: -entry.product.priceCents, category: .spend,
      reason: "Shopping purchase · \(entry.product.title)", guardianId: guardianId, state: &state)
    let transactionId = state.ledger.last?.id
    entries[index].status = .purchased
    entries[index].updatedAt = Date()
    entries[index].resolvedAt = Date()
    entries[index].ledgerTransactionId = transactionId
    state.shoppingEntries = entries
    appendShoppingAudit(action: "shopping.purchase_approved", entry: entries[index], actorId: guardianId)
    try persist(success: "Approved — Spend was updated")
  }

  func giftShoppingItem(_ entryId: UUID) throws {
    try requireParent()
    guard var entries = state.shoppingEntries,
      let index = entries.firstIndex(where: {
        $0.id == entryId && [.wishlist, .awaitingApproval].contains($0.status)
      })
    else { throw PocketCrewError.notFound("shopping item") }
    entries[index].status = .gifted
    entries[index].updatedAt = Date()
    entries[index].resolvedAt = Date()
    entries[index].parentNote = "Given by a parent — no Spend deducted."
    state.shoppingEntries = entries
    appendShoppingAudit(action: "shopping.item_gifted", entry: entries[index], actorId: guardianId)
    try persist(success: "Marked as a parent gift — no money deducted")
  }

  func declineShoppingItem(_ entryId: UUID, reason: String) throws {
    try requireParent()
    let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanReason.isEmpty else {
      throw PocketCrewError.invalid("Add a kind reason so the child understands the decision.")
    }
    guard var entries = state.shoppingEntries,
      let index = entries.firstIndex(where: { $0.id == entryId && $0.status == .awaitingApproval })
    else { throw PocketCrewError.notFound("cart request") }
    entries[index].status = .declined
    entries[index].updatedAt = Date()
    entries[index].resolvedAt = Date()
    entries[index].parentNote = cleanReason
    state.shoppingEntries = entries
    appendShoppingAudit(action: "shopping.purchase_declined", entry: entries[index], actorId: guardianId)
    try persist(success: "The shopping request was updated")
  }
  func updateSplit(childId: UUID, spend: Int, save: Int, give: Int) throws {
    try requireParent()
    try FinanceEngine.setSplit(
      childId: childId, spend: spend, save: save, give: give, guardianId: guardianId, state: &state)
    try persist(success: "Jar split updated")
  }
  func updateSchedule(frequency: PaydayFrequency, date: Date, customDays: Int? = nil) throws {
    try requireParent()
    if frequency == .custom && !(1...365).contains(customDays ?? 0) {
      throw PocketCrewError.invalid("Choose a whole number from 1 to 365 days.")
    }
    state.schedule.frequency = frequency
    state.schedule.customDays = frequency == .custom ? customDays : nil
    state.schedule.nextPaydayAt = date
    state.schedule.updatedAt = Date()
    try persist(success: "Payday schedule updated")
  }
  func addChild(_ child: ChildSetupDraft) throws {
    try requireParent()
    let cleanName = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty else {
      throw PocketCrewError.invalid("Add the child’s name.")
    }
    guard child.passcode.isFourDigitPasscode else {
      throw PocketCrewError.invalid("Choose a four-digit passcode for this child.")
    }
    guard child.splitTotal == 100,
      [child.spendPercent, child.savePercent, child.givePercent].allSatisfy({ 0...100 ~= $0 })
    else {
      throw PocketCrewError.invalid("Spend, Save, and Give must total 100%.")
    }
    let passcodeIsUsed = credentialVault.verify(
      child.passcode, target: .parent, familyId: state.family.id)
      || state.children.contains {
        credentialVault.verify(child.passcode, target: .child($0.id), familyId: state.family.id)
      }
    guard !passcodeIsUsed else {
      throw PocketCrewError.invalid("Choose a passcode that no other family profile uses.")
    }
    let now = Date()
    let childId = child.id
    guard !state.children.contains(where: { $0.id == childId }) else {
      throw PocketCrewError.invalid("That child profile was already added.")
    }
    state.children.append(
      ChildProfile(
        id: childId, createdAt: now, updatedAt: now, createdBy: guardianId,
        familyId: state.family.id, name: cleanName, ageRange: child.ageRange,
        avatarSymbol: child.avatarSymbol, avatarHex: child.avatarHex, status: "active"))
    state.members.append(
      FamilyMember(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
        familyId: state.family.id, userId: nil, childId: childId, role: .child,
        inviteState: "active"))
    state.splits.append(
      SplitRule(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, childId: childId,
        spendPercent: child.spendPercent, savePercent: child.savePercent,
        givePercent: child.givePercent))
    state.matchRules.append(
      ParentMatchRule(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, childId: childId,
        enabled: false, percent: 10, capCents: nil))
    for jar in JarKind.allCases {
      state.jars.append(
        JarAccount(
          id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
          familyId: state.family.id, childId: childId, kind: jar, status: "active"))
    }
    state.audit.append(
      AuditEvent(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
        familyId: state.family.id, actorId: guardianId, action: "child.created",
        entityType: "ChildProfile", entityId: childId,
        detail: "Created \(cleanName) with a \(child.spendPercent)/\(child.savePercent)/\(child.givePercent) split"))
    credentialVault.set(
      passcode: child.passcode, for: .child(childId), familyId: state.family.id)
    try persist(success: "\(cleanName) joined the crew")
  }

  func addChild(
    name: String, ageRange: String, passcode: String, color: String = "86BBD8",
    avatarSymbol: String = "star.fill", spend: Int = 50, save: Int = 40, give: Int = 10
  ) throws {
    try addChild(
      ChildSetupDraft(
        name: name, ageRange: ageRange, avatarSymbol: avatarSymbol, avatarHex: color,
        passcode: passcode, spendPercent: spend, savePercent: save, givePercent: give))
  }

  func removeChild(_ childId: UUID, parentPasscode: String) throws {
    try requireParent()
    guard verifyParentPasscode(parentPasscode) else {
      throw PocketCrewError.invalid("The parent passcode didn’t match.")
    }
    guard let child = child(childId) else { throw PocketCrewError.notFound("child") }
    guard state.children.count > 1 else {
      throw PocketCrewError.invalid("Keep at least one child in the family.")
    }
    guard [JarKind.spend, .save, .give].allSatisfy({ balance($0, childId: childId) == 0 }),
      pending(childId: childId) == 0 else {
      throw PocketCrewError.invalid("Settle this child’s jar balances and pending earnings first.")
    }
    guard !state.assignments.contains(where: {
      $0.childId == childId && ![WorkStatus.approved, .paid, .rejected].contains($0.status)
    }) else { throw PocketCrewError.invalid("Finish or review this child’s open work first.") }
    guard !(state.shoppingEntries ?? []).contains(where: {
      $0.childId == childId && $0.status == .awaitingApproval
    }) else { throw PocketCrewError.invalid("Review this child’s cart first.") }
    let previous = state
    state.archivedChildren = (state.archivedChildren ?? []) + [child]
    state.children.removeAll { $0.id == childId }
    state.members.removeAll { $0.childId == childId }
    let now = Date()
    state.audit.append(AuditEvent(id: UUID(), createdAt: now, updatedAt: now,
      createdBy: guardianId, familyId: state.family.id, actorId: guardianId,
      action: "child.removed", entityType: "ChildProfile", entityId: childId,
      detail: "Removed \(child.name); historical records preserved"))
    do { try persist(success: "Child removed; past records kept") }
    catch { state = previous; throw error }
    if selectedChildId == childId, let first = state.children.first { setSelectedChild(first.id) }
  }

  func updateChild(
    childId: UUID, name: String, ageRange: String, avatarSymbol: String, avatarHex: String,
    spend: Int, save: Int, give: Int
  ) throws {
    try requireParent()
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty else { throw PocketCrewError.invalid("Add the child’s name.") }
    guard spend + save + give == 100, [spend, save, give].allSatisfy({ 0...100 ~= $0 }) else {
      throw PocketCrewError.invalid("Spend, Save, and Give must total 100%.")
    }
    guard let childIndex = state.children.firstIndex(where: { $0.id == childId }),
      let splitIndex = state.splits.firstIndex(where: { $0.childId == childId })
    else { throw PocketCrewError.notFound("child profile") }
    let now = Date()
    state.children[childIndex].name = cleanName
    state.children[childIndex].ageRange = ageRange
    state.children[childIndex].avatarSymbol = avatarSymbol
    state.children[childIndex].avatarHex = avatarHex
    state.children[childIndex].updatedAt = now
    state.splits[splitIndex].spendPercent = spend
    state.splits[splitIndex].savePercent = save
    state.splits[splitIndex].givePercent = give
    state.splits[splitIndex].updatedAt = now
    state.audit.append(
      AuditEvent(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
        familyId: state.family.id, actorId: guardianId, action: "child.updated",
        entityType: "ChildProfile", entityId: childId,
        detail: "Updated profile and \(spend)/\(save)/\(give) split"))
    try persist(success: "\(cleanName)’s settings updated")
  }

  func createFamily(
    familyName: String, parentName: String, children: [ChildSetupDraft], currency: String,
    frequency: PaydayFrequency, parentPasscode: String
  ) throws {
    let cleanFamilyName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanParentName = parentName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanFamilyName.isEmpty, !cleanParentName.isEmpty, !children.isEmpty else {
      throw PocketCrewError.invalid("Add a family name, your name, and at least one child.")
    }
    guard children.allSatisfy(\.isComplete) else {
      throw PocketCrewError.invalid(
        "Every child needs a name, a four-digit passcode, and a jar split totaling 100%.")
    }
    guard parentPasscode.isFourDigitPasscode else {
      throw PocketCrewError.invalid("Choose a four-digit parent passcode.")
    }
    let allPasscodes = [parentPasscode] + children.map(\.passcode)
    guard Set(allPasscodes).count == allPasscodes.count else {
      throw PocketCrewError.invalid("Every parent and child profile needs a different passcode.")
    }
    guard Set(children.map(\.id)).count == children.count else {
      throw PocketCrewError.invalid("Each child profile must be unique.")
    }
    let previousFamilyId = state.family.id
    let now = Date()
    let familyId = UUID()
    let family = Family(
      id: familyId, createdAt: now, updatedAt: now, createdBy: guardianId, name: cleanFamilyName,
      timezone: TimeZone.current.identifier, currency: currency, locale: Locale.current.identifier,
      status: "active")
    let parent = User(
      id: guardianId, createdAt: now, updatedAt: now, createdBy: guardianId,
      displayName: cleanParentName, email: authenticatedGuardianEmail, status: "active")
    let childProfiles = children.map { child in
      ChildProfile(
        id: child.id, createdAt: now, updatedAt: now, createdBy: guardianId, familyId: familyId,
        name: child.name.trimmingCharacters(in: .whitespacesAndNewlines),
        ageRange: child.ageRange, avatarSymbol: child.avatarSymbol, avatarHex: child.avatarHex,
        status: "active")
    }
    let guardianMember = FamilyMember(
      id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, familyId: familyId,
      userId: guardianId, childId: nil, role: .guardian, inviteState: "active")
    let childMembers = children.map { child in
      FamilyMember(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, familyId: familyId,
        userId: nil, childId: child.id, role: .child, inviteState: "active")
    }
    state = PocketCrewState(
      version: 1, family: family, users: [parent], members: [guardianMember] + childMembers,
      children: childProfiles, workItems: [], assignments: [], submissions: [], decisions: [],
      schedule: PaydaySchedule(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, familyId: familyId,
        frequency: frequency, nextPaydayAt: DemoData.nextFriday()),
      earnings: [], paydays: [], paydayLines: [],
      jars: children.flatMap { child in
        JarKind.allCases.map { kind in
          JarAccount(
            id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
            familyId: familyId, childId: child.id, kind: kind, status: "active")
        }
      },
      ledger: [], goals: [],
      splits: children.map { child in
        SplitRule(
          id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, childId: child.id,
          spendPercent: child.spendPercent, savePercent: child.savePercent,
          givePercent: child.givePercent)
      },
      matchRules: children.map { child in
        ParentMatchRule(
          id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, childId: child.id,
          enabled: false, percent: 10, capCents: nil)
      },
      notifications: [],
      audit: [
        AuditEvent(
          id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, familyId: familyId,
          actorId: guardianId, action: "family.created", entityType: "Family",
          entityId: familyId, detail: "Created with \(children.count) child profile(s)")
      ])
    selectedChildId = children[0].id
    UserDefaults.standard.set(children[0].id.uuidString, forKey: "selectedChildId")
    credentialVault.clear(familyId: previousFamilyId)
    credentialVault.set(passcode: parentPasscode, for: .parent, familyId: familyId)
    for child in children {
      credentialVault.set(passcode: child.passcode, for: .child(child.id), familyId: familyId)
    }
    try persist()
  }

  func createFamily(
    familyName: String, parentName: String, childName: String, ageRange: String, currency: String,
    frequency: PaydayFrequency, spend: Int, save: Int, give: Int, parentPasscode: String,
    childPasscode: String
  ) throws {
    try createFamily(
      familyName: familyName, parentName: parentName,
      children: [
        ChildSetupDraft(
          name: childName, ageRange: ageRange, passcode: childPasscode,
          spendPercent: spend, savePercent: save, givePercent: give)
      ], currency: currency, frequency: frequency, parentPasscode: parentPasscode)
  }
  func updatePasscode(
    target: ProfileAccessTarget, currentParentPasscode: String, newPasscode: String
  ) throws {
    try requireParent()
    guard verifyParentPasscode(currentParentPasscode) else {
      throw PocketCrewError.invalid("The current parent passcode didn’t match.")
    }
    guard newPasscode.isFourDigitPasscode else {
      throw PocketCrewError.invalid("The new passcode must be exactly four digits.")
    }
    let otherTargets: [ProfileAccessTarget] = [.parent]
      + state.children.map { .child($0.id) }
    guard !otherTargets.contains(where: {
      $0 != target
        && credentialVault.verify(newPasscode, target: $0, familyId: state.family.id)
    }) else {
      throw PocketCrewError.invalid("Choose a passcode that no other family profile uses.")
    }
    credentialVault.set(passcode: newPasscode, for: target, familyId: state.family.id)
    if state.family.id == DemoData.familyId {
      UserDefaults.standard.set(true, forKey: demoHintChangedKey(for: target))
    }
    let now = Date()
    let entityId: UUID
    switch target {
    case .parent: entityId = guardianId
    case .child(let childId): entityId = childId
    }
    state.audit.append(
      AuditEvent(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
        familyId: state.family.id, actorId: guardianId, action: "profile.passcode_updated",
        entityType: "FamilyMember", entityId: entityId, detail: nil))
    try persist(success: "Passcode updated")
  }
  func setWorkLifecycle(_ workId: UUID, status: String) throws {
    try requireParent()
    guard let index = state.workItems.firstIndex(where: { $0.id == workId }) else { return }
    state.workItems[index].lifecycleStatus = status
    state.workItems[index].updatedAt = Date()
    state.audit.append(
      AuditEvent(
        id: UUID(), createdAt: Date(), updatedAt: Date(), createdBy: guardianId,
        familyId: state.family.id, actorId: guardianId, action: "work.\(status)",
        entityType: "WorkItem", entityId: workId, detail: nil))
    try persist(
      success: status == "paused"
        ? "Work paused" : status == "deleted" ? "Work removed" : "Work resumed")
  }
  func featureGoal(_ id: UUID) throws {
    guard sessionUnlocked else { throw PocketCrewError.invalid("Unlock your profile first.") }
    guard let goal = state.goals.first(where: { $0.id == id }), goal.status == .active else {
      throw PocketCrewError.invalid("Choose an approved, active goal.")
    }
    if role == .child && goal.childId != selectedChildId {
      throw PocketCrewError.invalid("Choose one of your own goals.")
    }
    for index in state.goals.indices where state.goals[index].childId == goal.childId {
      state.goals[index].featured = state.goals[index].id == id
      state.goals[index].updatedAt = Date()
    }
    try persist(success: "Featured goal updated")
  }
  func completeGoal(_ id: UUID) throws {
    try requireParent()
    guard let index = state.goals.firstIndex(where: { $0.id == id && $0.status == .active }) else {
      throw PocketCrewError.invalid("Choose an active goal that has not already been completed.")
    }
    let goal = state.goals[index]
    guard goal.targetCents > 0 else { throw PocketCrewError.invalid("This goal needs a positive target.") }
    try FinanceEngine.record(
      childId: goal.childId, jar: .spend, amount: -goal.targetCents, category: .spend,
      reason: "Goal completed · \(goal.title)", guardianId: guardianId, state: &state)
    state.goals[index].status = .completed
    state.goals[index].featured = false
    state.goals[index].updatedAt = Date()
    try persist(success: "Goal completed — \(goal.targetCents.currency()) deducted from Spend")
  }
  func removeGoal(_ id: UUID) throws {
    guard sessionUnlocked else { throw PocketCrewError.invalid("Unlock your profile first.") }
    guard let index = state.goals.firstIndex(where: { $0.id == id }), state.goals[index].status != .archived else {
      throw PocketCrewError.invalid("This goal is no longer available.")
    }
    guard role == .parent || state.goals[index].childId == selectedChildId else {
      throw PocketCrewError.invalid("You can only remove your own goals.")
    }
    state.goals[index].status = .archived
    state.goals[index].featured = false
    state.goals[index].updatedAt = Date()
    try persist(success: "Goal removed — your savings are unchanged")
  }
  func addGoal(
    childId: UUID, title: String, icon: String, target: Money, targetDate: Date?, proposed: Bool,
    shoppingProduct: ShoppingProduct? = nil
  ) throws {
    if proposed {
      try requireChild()
      guard childId == selectedChildId else {
        throw PocketCrewError.invalid("A child can only propose a goal for their own profile.")
      }
    } else {
      try requireParent()
    }
    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw PocketCrewError.invalid("Give the goal a name.")
    }
    guard target > 0 else { throw PocketCrewError.invalid("Set a target greater than $0.") }
    let now = Date()
    let hasFeatured = state.goals.contains {
      $0.childId == childId && $0.featured && $0.status == .active
    }
    state.goals.append(
      SavingsGoal(
        shoppingProduct: shoppingProduct,
        id: UUID(), createdAt: now, updatedAt: now, createdBy: proposed ? childId : guardianId,
        familyId: state.family.id, childId: childId, title: title, icon: icon, targetCents: target,
        allocatedCents: 0, targetDate: targetDate,
        priority: state.goals.filter { $0.childId == childId }.count + 1,
        featured: !hasFeatured && !proposed, status: proposed ? .proposed : .active))
    try persist(success: proposed ? "Goal idea sent to your grown-up" : "Savings goal created")
  }
  func proposeGig(title: String, note: String) throws {
    try requireChild()
    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw PocketCrewError.invalid("Give your gig idea a title.")
    }
    let now = Date()
    let workId = UUID()
    state.workItems.append(
      WorkItem(
        id: workId, createdAt: now, updatedAt: now, createdBy: selectedChildId,
        familyId: state.family.id, type: .gig, title: title, instructions: note,
        category: "Child idea", rewardCents: 0, recurrence: .once, proofRequired: false,
        claimable: false, checklist: [], lifecycleStatus: "proposed"))
    state.notifications.append(
      AppNotification(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: selectedChildId, userId: guardianId,
        title: "New gig idea from \(selectedChild.name)", body: title, readAt: nil))
    try persist(success: "Gig idea sent to your grown-up")
  }
  func approveGoal(_ goalId: UUID) throws {
    try requireParent()
    guard let index = state.goals.firstIndex(where: { $0.id == goalId && $0.status == .proposed })
    else { throw PocketCrewError.notFound("goal idea") }
    let hasFeatured = state.goals.contains {
      $0.childId == state.goals[index].childId && $0.featured && $0.status == .active
    }
    state.goals[index].status = .active
    state.goals[index].featured = !hasFeatured
    state.goals[index].updatedAt = Date()
    try persist(success: "Savings goal approved")
  }
  func approveGigProposal(_ workId: UUID, reward: Money, dueAt: Date) throws {
    try requireParent()
    guard reward > 0 else { throw PocketCrewError.invalid("Set a reward greater than $0.") }
    guard
      let index = state.workItems.firstIndex(where: {
        $0.id == workId && $0.lifecycleStatus == "proposed"
      })
    else { throw PocketCrewError.notFound("gig idea") }
    let childId = state.workItems[index].createdBy
    let now = Date()
    state.workItems[index].rewardCents = reward
    state.workItems[index].lifecycleStatus = "active"
    state.workItems[index].updatedAt = now
    state.assignments.append(
      WorkAssignment(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, workItemId: workId,
        familyId: state.family.id, childId: childId, dueAt: dueAt, rewardSnapshotCents: reward,
        status: .assigned, checklistDone: [], estimatedMinutes: nil))
    try persist(success: "Gig idea approved and assigned")
  }
  func inviteCoParent(name: String, email: String) throws {
    try requireParent()
    guard email.contains("@") else { throw PocketCrewError.invalid("Enter a valid email address.") }
    let now = Date()
    let userId = UUID()
    state.users.append(
      User(
        id: userId, createdAt: now, updatedAt: now, createdBy: guardianId,
        displayName: name.isEmpty ? "Co-parent" : name, email: email, status: "invited"))
    state.members.append(
      FamilyMember(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
        familyId: state.family.id, userId: userId, childId: nil, role: .guardian,
        inviteState: "pending"))
    try persist(success: "Co-parent invitation recorded")
  }
  func deleteLocalData() throws {
    try requireParent()
    credentialVault.clear(familyId: state.family.id)
    try repository.delete()
    toast = nil
  }
  func resetDemo() throws {
    credentialVault.clear(familyId: state.family.id)
    state = try repository.reset()
    selectedChildId = state.children[0].id
    clearDemoHintFlags()
    credentialVault.ensureDefaults(for: state)
    sessionUnlocked = false
    toast = ToastMessage(text: "Demo family restored", isError: false)
  }

  func show(error: Error) { toast = ToastMessage(text: error.localizedDescription, isError: true) }
  private func persist(success: String? = nil) throws {
    try repository.save(state)
    cloudChangeHandler?(state)
    if let success { toast = ToastMessage(text: success, isError: false) }
  }

  private func requireParent() throws {
    guard sessionUnlocked, role == .parent else {
      throw PocketCrewError.invalid("Unlock a parent profile to do that.")
    }
  }

  private func requireChild() throws {
    guard sessionUnlocked, role == .child else {
      throw PocketCrewError.invalid("Unlock a child profile to do that.")
    }
  }

  private func appendShoppingAudit(action: String, entry: ShoppingEntry, actorId: UUID) {
    let now = Date()
    state.audit.append(
      AuditEvent(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: actorId,
        familyId: state.family.id, actorId: actorId, action: action,
        entityType: "ShoppingEntry", entityId: entry.id,
        detail: "\(entry.product.title) · \(entry.product.priceCents) cents"))
  }

  private func demoHintChangedKey(for target: ProfileAccessTarget) -> String {
    "pocketcrew.demoHintChanged.\(target.id)"
  }

  private func clearDemoHintFlags() {
    UserDefaults.standard.removeObject(forKey: demoHintChangedKey(for: .parent))
    UserDefaults.standard.removeObject(forKey: demoHintChangedKey(for: .child(DemoData.jordanId)))
    UserDefaults.standard.removeObject(forKey: demoHintChangedKey(for: .child(DemoData.rileyId)))
  }
}

struct ToastMessage: Identifiable, Equatable {
  let id = UUID()
  let text: String
  let isError: Bool
}
