import Foundation

@main
struct EngineChecks {
  static func main() throws {
    let sessionMemory = SessionMemoryStorage()
    let credential = Data("test-session-only".utf8)
    try sessionMemory.store(key: "session", value: credential)
    guard try sessionMemory.retrieve(key: "session") == credential,
      try SessionMemoryStorage().retrieve(key: "session") == nil else {
      fatalError("Session credentials must stay within one storage instance")
    }
    try sessionMemory.remove(key: "session")
    guard try sessionMemory.retrieve(key: "session") == nil else {
      fatalError("Sign-out must remove the session credential")
    }
    try tenDollarGigApprovesExactlyOnce()
    try paydaySplitsAndCannotDuplicate()
    try responsibilityNeverCreatesMoney()
    try redoReturnsWorkWithNote()
    try purchaseAndWithdrawalRules()
    try splitValidationAndRounding()
    try profilePasscodesStayIsolated()
    try workPresetLibraryIsSafeAndUseful()
    print("✓ 8 PocketCrew engine, preset, and access scenarios passed")
  }

  private static func cleanState() -> PocketCrewState {
    var state = DemoData.make()
    state.assignments = []
    state.submissions = []
    state.decisions = []
    state.earnings = []
    state.paydays = []
    state.paydayLines = []
    state.ledger = []
    state.audit = []
    state.goals = state.goals.map { value in
      var copy = value
      copy.allocatedCents = 0
      return copy
    }
    return state
  }

  private static func addWork(
    type: WorkType, reward: Money, childId: UUID, state: inout PocketCrewState
  ) -> WorkAssignment {
    let workId = UUID()
    let assignmentId = UUID()
    let now = Date()
    state.workItems.append(
      WorkItem(
        id: workId, createdAt: now, updatedAt: now, createdBy: DemoData.mayaId,
        familyId: state.family.id, type: type,
        title: type == .gig ? "Test gig" : "Test responsibility", instructions: "Do the test work",
        category: "Test", rewardCents: reward, recurrence: .once, proofRequired: false,
        claimable: false, checklist: [], lifecycleStatus: "active"))
    let assignment = WorkAssignment(
      id: assignmentId, createdAt: now, updatedAt: now, createdBy: DemoData.mayaId,
      workItemId: workId, familyId: state.family.id, childId: childId, dueAt: now,
      rewardSnapshotCents: type == .gig ? reward : 0, status: .inProgress, checklistDone: [],
      estimatedMinutes: 10)
    state.assignments.append(assignment)
    return assignment
  }

  private static func submitAndApprove(
    _ assignment: WorkAssignment, childId: UUID, state: inout PocketCrewState
  ) throws -> UUID {
    try FinanceEngine.submit(
      assignmentId: assignment.id, childId: childId, note: "Done", proof: nil, state: &state)
    guard let submissionId = state.submissions.last?.id else {
      throw CheckFailure("Submission was not created")
    }
    try FinanceEngine.approve(
      submissionId: submissionId, guardianId: DemoData.mayaId, state: &state)
    return submissionId
  }

  private static func tenDollarGigApprovesExactlyOnce() throws {
    var state = cleanState()
    let assignment = addWork(type: .gig, reward: 1_000, childId: DemoData.jordanId, state: &state)
    let submissionId = try submitAndApprove(assignment, childId: DemoData.jordanId, state: &state)
    try FinanceEngine.approve(
      submissionId: submissionId, guardianId: DemoData.mayaId, state: &state)
    try expect(state.earnings.count == 1, "Approval created more than one earning")
    try expect(
      FinanceEngine.pendingEarnings(in: state, childId: DemoData.jordanId) == 1_000,
      "$10 gig did not add exactly $10")
  }

  private static func paydaySplitsAndCannotDuplicate() throws {
    var state = cleanState()
    let assignment = addWork(type: .gig, reward: 1_000, childId: DemoData.jordanId, state: &state)
    _ = try submitAndApprove(assignment, childId: DemoData.jordanId, state: &state)
    let first = try FinanceEngine.runPayday(
      guardianId: DemoData.mayaId, idempotencyKey: "test-payday", early: false, state: &state)
    try expect(
      FinanceEngine.jarBalance(in: state, childId: DemoData.jordanId, jar: .spend) == 500,
      "Spend allocation was not $5")
    try expect(
      FinanceEngine.jarBalance(in: state, childId: DemoData.jordanId, jar: .save) == 440,
      "Save plus 10% parent match was not $4.40")
    try expect(
      FinanceEngine.jarBalance(in: state, childId: DemoData.jordanId, jar: .give) == 100,
      "Give allocation was not $1")
    let transactionCount = state.ledger.count
    let retry = try FinanceEngine.runPayday(
      guardianId: DemoData.mayaId, idempotencyKey: "test-payday", early: false, state: &state)
    try expect(
      first.id == retry.id && state.paydays.count == 1 && state.ledger.count == transactionCount,
      "Payday retry duplicated financial records")
  }

  private static func responsibilityNeverCreatesMoney() throws {
    var state = cleanState()
    let assignment = addWork(
      type: .responsibility, reward: 1_000, childId: DemoData.jordanId, state: &state)
    _ = try submitAndApprove(assignment, childId: DemoData.jordanId, state: &state)
    try expect(state.earnings.isEmpty && state.ledger.isEmpty, "A responsibility generated money")
  }

  private static func redoReturnsWorkWithNote() throws {
    var state = cleanState()
    let assignment = addWork(type: .gig, reward: 1_000, childId: DemoData.jordanId, state: &state)
    try FinanceEngine.submit(
      assignmentId: assignment.id, childId: DemoData.jordanId, note: "Done", proof: nil,
      state: &state)
    guard let submission = state.submissions.last else { throw CheckFailure("Submission missing") }
    try FinanceEngine.decide(
      submissionId: submission.id, guardianId: DemoData.mayaId, decision: .redoRequested,
      reason: "Please check the corner.", state: &state)
    try expect(
      state.assignments.last?.status == .redoRequested
        && state.decisions.last?.reason == "Please check the corner.",
      "Redo did not preserve its note")
  }

  private static func purchaseAndWithdrawalRules() throws {
    var state = cleanState()
    try FinanceEngine.record(
      childId: DemoData.jordanId, jar: .spend, amount: 2_000, category: .adjustment,
      reason: "Opening balance", guardianId: DemoData.mayaId, state: &state)
    try FinanceEngine.record(
      childId: DemoData.jordanId, jar: .save, amount: 1_000, category: .adjustment,
      reason: "Opening savings", guardianId: DemoData.mayaId, state: &state)
    try FinanceEngine.record(
      childId: DemoData.jordanId, jar: .spend, amount: -500, category: .spend, reason: "Book",
      guardianId: DemoData.mayaId, state: &state)
    try expect(
      FinanceEngine.jarBalance(in: state, childId: DemoData.jordanId, jar: .spend) == 1_500,
      "Purchase did not reduce Spend correctly")
    try expect(
      FinanceEngine.jarBalance(in: state, childId: DemoData.jordanId, jar: .save) == 1_000,
      "Purchase changed Save")
    var rejected = false
    do {
      try FinanceEngine.record(
        childId: DemoData.jordanId, jar: .save, amount: -1_001, category: .save, reason: "Too much",
        guardianId: DemoData.mayaId, state: &state)
    } catch { rejected = true }
    try expect(rejected, "Oversized savings withdrawal was accepted")
  }

  private static func splitValidationAndRounding() throws {
    var state = cleanState()
    var rejected = false
    do {
      try FinanceEngine.setSplit(
        childId: DemoData.jordanId, spend: 50, save: 50, give: 10, guardianId: DemoData.mayaId,
        state: &state)
    } catch { rejected = true }
    try expect(rejected, "A split over 100% was accepted")
    let rule = SplitRule(
      id: UUID(), createdAt: Date(), updatedAt: Date(), createdBy: DemoData.mayaId,
      childId: DemoData.jordanId, spendPercent: 33, savePercent: 33, givePercent: 34)
    let split = try FinanceEngine.split(total: 101, rule: rule)
    try expect(
      split.spend + split.save + split.give == 101 && split.spend == 34,
      "Cent remainder did not reconcile to Spend")
  }

  private static func profilePasscodesStayIsolated() throws {
    let suiteName = "PocketCrewChecks-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw CheckFailure("Could not create isolated credential storage")
    }
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let vault = CredentialVault(defaults: defaults)
    let state = DemoData.make()
    vault.ensureDefaults(for: state)
    try expect(
      vault.verify("2468", target: .parent, familyId: state.family.id),
      "Parent passcode did not unlock the parent profile")
    try expect(
      vault.verify("1212", target: .child(DemoData.jordanId), familyId: state.family.id),
      "Jordan's passcode did not unlock Jordan")
    try expect(
      !vault.verify("0808", target: .child(DemoData.jordanId), familyId: state.family.id),
      "Riley's passcode unlocked Jordan's profile")
    try expect(
      !vault.verify("1212", target: .child(DemoData.rileyId), familyId: state.family.id),
      "Jordan's passcode unlocked Riley's profile")
    try expect(
      !vault.verify("1212", target: .parent, familyId: state.family.id),
      "A child passcode unlocked the parent profile")
  }

  private static func workPresetLibraryIsSafeAndUseful() throws {
    let presets = WorkPreset.library
    try expect(presets.count >= 12, "The starter work library is too small")
    try expect(
      Set(presets.map(\.id)).count == presets.count, "Work presets contain duplicate IDs")
    try expect(
      presets.filter({ $0.type == .responsibility }).allSatisfy({ $0.rewardCents == 0 }),
      "A responsibility preset included a reward")
    try expect(
      presets.filter({ $0.type == .gig }).allSatisfy({ $0.rewardCents > 0 && $0.rewardCents < 300 }),
      "Every paid gig preset must have a positive reward below $3")
    try expect(
      presets.allSatisfy({ !$0.title.isEmpty && !$0.instructions.isEmpty }),
      "A work preset is missing editable starter content")
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(message) }
  }
}

struct CheckFailure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
