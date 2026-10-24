import Foundation

enum FinanceEngine {
  static func jarBalance(in state: PocketCrewState, childId: UUID, jar: JarKind) -> Money {
    state.ledger.filter { $0.childId == childId && $0.jar == jar }.reduce(0) { $0 + $1.amountCents }
  }

  static func split(total: Money, rule: SplitRule) throws -> (
    spend: Money, save: Money, give: Money
  ) {
    guard rule.spendPercent + rule.savePercent + rule.givePercent == 100 else {
      throw PocketCrewError.invalid("Spend, Save, and Give must total 100%.")
    }
    let save = total * rule.savePercent / 100
    let give = total * rule.givePercent / 100
    return (total - save - give, save, give)  // deterministic remainder goes to Spend
  }

  static func pendingEarnings(in state: PocketCrewState, childId: UUID? = nil) -> Money {
    state.earnings.filter {
      $0.status == .approvedUnpaid && (childId == nil || $0.childId == childId)
    }.reduce(0) { $0 + $1.amountCents }
  }

  static func submit(
    assignmentId: UUID, childId: UUID, note: String, proof: ProofImage?,
    state: inout PocketCrewState
  ) throws {
    guard let assignmentIndex = state.assignments.firstIndex(where: { $0.id == assignmentId }),
      let work = state.workItems.first(where: {
        $0.id == state.assignments[assignmentIndex].workItemId
      })
    else {
      throw PocketCrewError.notFound("work item")
    }
    let assignment = state.assignments[assignmentIndex]
    guard assignment.childId == nil || assignment.childId == childId else {
      throw PocketCrewError.invalid("This work belongs to another child.")
    }
    guard !work.proofRequired || proof != nil else {
      throw PocketCrewError.invalid("Add a proof image before submitting this gig.")
    }
    guard assignment.checklistDone.count == work.checklist.count else {
      throw PocketCrewError.invalid("Finish each checklist step before submitting.")
    }
    let now = Date()
    if let existing = state.submissions.firstIndex(where: {
      $0.assignmentId == assignmentId && $0.status == .redoRequested
    }) {
      state.submissions[existing].status = .pending
      state.submissions[existing].note = note
      state.submissions[existing].proofImage = proof
      state.submissions[existing].submittedAt = now
      state.submissions[existing].updatedAt = now
    } else {
      state.submissions.append(
        WorkSubmission(
          id: UUID(), createdAt: now, updatedAt: now, createdBy: childId,
          assignmentId: assignmentId, childId: childId, submittedAt: now, note: note,
          proofImage: proof, status: .pending))
    }
    state.assignments[assignmentIndex].childId = childId
    state.assignments[assignmentIndex].status = .awaitingApproval
    state.assignments[assignmentIndex].updatedAt = now
  }

  static func approve(submissionId: UUID, guardianId: UUID, state: inout PocketCrewState) throws {
    guard let submissionIndex = state.submissions.firstIndex(where: { $0.id == submissionId })
    else { throw PocketCrewError.notFound("submission") }
    if state.submissions[submissionIndex].status == .approved { return }
    guard
      let assignmentIndex = state.assignments.firstIndex(where: {
        $0.id == state.submissions[submissionIndex].assignmentId
      }),
      let work = state.workItems.first(where: {
        $0.id == state.assignments[assignmentIndex].workItemId
      })
    else { throw PocketCrewError.notFound("work details") }
    let now = Date()
    let submission = state.submissions[submissionIndex]
    if work.type == .gig && !state.earnings.contains(where: { $0.submissionId == submissionId }) {
      state.earnings.append(
        Earning(
          id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
          familyId: state.family.id, childId: submission.childId,
          assignmentId: submission.assignmentId, submissionId: submissionId,
          amountCents: state.assignments[assignmentIndex].rewardSnapshotCents,
          status: .approvedUnpaid, paydayId: nil))
    }
    state.submissions[submissionIndex].status = .approved
    state.submissions[submissionIndex].updatedAt = now
    state.assignments[assignmentIndex].status = .approved
    state.assignments[assignmentIndex].updatedAt = now
    state.decisions.append(
      ApprovalDecision(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
        submissionId: submissionId, guardianId: guardianId, decision: .approved, reason: nil))
    state.audit.append(
      audit(
        action: "submission.approved", type: "WorkSubmission", entityId: submissionId,
        guardianId: guardianId, familyId: state.family.id))
  }

  static func decide(
    submissionId: UUID, guardianId: UUID, decision: DecisionKind, reason: String,
    state: inout PocketCrewState
  ) throws {
    guard decision != .approved else {
      return try approve(submissionId: submissionId, guardianId: guardianId, state: &state)
    }
    guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PocketCrewError.invalid("Add a kind, specific reason so they know what to do next.")
    }
    guard let submissionIndex = state.submissions.firstIndex(where: { $0.id == submissionId }),
      let assignmentIndex = state.assignments.firstIndex(where: {
        $0.id == state.submissions[submissionIndex].assignmentId
      })
    else { throw PocketCrewError.notFound("submission") }
    let now = Date()
    let status: SubmissionStatus = decision == .redoRequested ? .redoRequested : .rejected
    state.submissions[submissionIndex].status = status
    state.submissions[submissionIndex].updatedAt = now
    state.assignments[assignmentIndex].status =
      decision == .redoRequested ? .redoRequested : .rejected
    state.assignments[assignmentIndex].updatedAt = now
    state.decisions.append(
      ApprovalDecision(
        id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
        submissionId: submissionId, guardianId: guardianId, decision: decision, reason: reason))
    state.audit.append(
      audit(
        action: "submission.\(decision.rawValue)", type: "WorkSubmission", entityId: submissionId,
        guardianId: guardianId, familyId: state.family.id, detail: reason))
  }

  @discardableResult
  static func runPayday(
    guardianId: UUID, idempotencyKey: String, early: Bool, state: inout PocketCrewState
  ) throws -> Payday {
    if let existing = state.paydays.first(where: { $0.idempotencyKey == idempotencyKey }) {
      return existing
    }
    let included = state.earnings.filter { $0.status == .approvedUnpaid }
    guard !included.isEmpty else { throw PocketCrewError.nothingToPay }
    let now = Date()
    var nextDate = state.schedule.nextPaydayAt
    repeat {
      nextDate = try state.schedule.followingDate(after: nextDate, timezone: state.family.timezone)
    } while nextDate <= now
    let paydayId = UUID()
    var lines: [PaydayLineItem] = []
    var transactions: [LedgerTransaction] = []
    var totalMatch = 0
    for child in state.children {
      let earnings = included.filter { $0.childId == child.id }
      guard !earnings.isEmpty else { continue }
      guard let rule = state.splits.first(where: { $0.childId == child.id }) else {
        throw PocketCrewError.invalid("\(child.name) needs a jar split before payday.")
      }
      let gross = earnings.reduce(0) { $0 + $1.amountCents }
      let allocation = try split(total: gross, rule: rule)
      let matchRule = state.matchRules.first(where: { $0.childId == child.id && $0.enabled })
      var match = matchRule.map { allocation.save * $0.percent / 100 } ?? 0
      if let cap = matchRule?.capCents { match = min(match, cap) }
      totalMatch += match
      lines.append(
        PaydayLineItem(
          id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, paydayId: paydayId,
          childId: child.id, earningIds: earnings.map(\.id), grossCents: gross,
          spendCents: allocation.spend, saveCents: allocation.save, giveCents: allocation.give,
          matchCents: match))
      let allocations: [(JarKind, Money, String)] = [
        (.spend, allocation.spend, "Payday deposit · Spend"),
        (.save, allocation.save, "Payday deposit · Save"),
        (.give, allocation.give, "Payday deposit · Give"), (.save, match, "Parent savings match"),
      ]
      transactions += allocations.filter { $0.1 > 0 }.map { jar, amount, description in
        LedgerTransaction(
          id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId,
          familyId: state.family.id, childId: child.id, jar: jar, amountCents: amount,
          category: .payday, description: description, paydayId: paydayId, workItemId: nil,
          reversesTransactionId: nil)
      }
      if let goalIndex = state.goals.firstIndex(where: {
        $0.childId == child.id && $0.featured && $0.status == .active
      }) {
        state.goals[goalIndex].allocatedCents = min(
          state.goals[goalIndex].targetCents,
          state.goals[goalIndex].allocatedCents + allocation.save + match)
        state.goals[goalIndex].updatedAt = now
      }
    }
    let payday = Payday(
      id: paydayId, createdAt: now, updatedAt: now, createdBy: guardianId,
      familyId: state.family.id, scheduledFor: state.schedule.nextPaydayAt, processedAt: now,
      status: "processed", idempotencyKey: idempotencyKey,
      totalEarningsCents: included.reduce(0) { $0 + $1.amountCents }, totalMatchCents: totalMatch,
      early: early)
    for index in state.earnings.indices
    where included.contains(where: { $0.id == state.earnings[index].id }) {
      state.earnings[index].status = .paid
      state.earnings[index].paydayId = paydayId
      state.earnings[index].updatedAt = now
    }
    for index in state.assignments.indices
    where included.contains(where: { $0.assignmentId == state.assignments[index].id }) {
      state.assignments[index].status = .paid
      state.assignments[index].updatedAt = now
    }
    state.paydays.append(payday)
    state.schedule.nextPaydayAt = nextDate
    state.schedule.updatedAt = now
    state.paydayLines += lines
    state.ledger += transactions
    state.audit.append(
      audit(
        action: "payday.processed", type: "Payday", entityId: paydayId, guardianId: guardianId,
        familyId: state.family.id, detail: payday.totalEarningsCents.currency()))
    return payday
  }

  static func record(
    childId: UUID, jar: JarKind, amount: Money, category: LedgerCategory, reason: String,
    guardianId: UUID, state: inout PocketCrewState
  ) throws {
    guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PocketCrewError.invalid("Add a reason for this entry.")
    }
    if amount < 0 && jarBalance(in: state, childId: childId, jar: jar) + amount < 0 {
      throw PocketCrewError.insufficientFunds(jar)
    }
    let now = Date()
    let transactionId = UUID()
    state.ledger.append(
      LedgerTransaction(
        id: transactionId, createdAt: now, updatedAt: now, createdBy: guardianId,
        familyId: state.family.id, childId: childId, jar: jar, amountCents: amount,
        category: category, description: reason, paydayId: nil, workItemId: nil,
        reversesTransactionId: nil))
    state.audit.append(
      audit(
        action: "ledger.entry_created", type: "LedgerTransaction", entityId: transactionId,
        guardianId: guardianId, familyId: state.family.id, detail: "\(jar.rawValue) \(amount)"))
  }

  static func setSplit(
    childId: UUID, spend: Int, save: Int, give: Int, guardianId: UUID, state: inout PocketCrewState
  ) throws {
    guard spend + save + give == 100 else {
      throw PocketCrewError.invalid("Spend, Save, and Give must total 100%.")
    }
    guard spend >= 0, save >= 0, give >= 0 else {
      throw PocketCrewError.invalid("Split percentages cannot be negative.")
    }
    guard let index = state.splits.firstIndex(where: { $0.childId == childId }) else {
      throw PocketCrewError.notFound("split rule")
    }
    state.splits[index].spendPercent = spend
    state.splits[index].savePercent = save
    state.splits[index].givePercent = give
    state.splits[index].updatedAt = Date()
    state.audit.append(
      audit(
        action: "split.updated", type: "SplitRule", entityId: state.splits[index].id,
        guardianId: guardianId, familyId: state.family.id))
  }

  private static func audit(
    action: String, type: String, entityId: UUID, guardianId: UUID, familyId: UUID,
    detail: String? = nil
  ) -> AuditEvent {
    let now = Date()
    return AuditEvent(
      id: UUID(), createdAt: now, updatedAt: now, createdBy: guardianId, familyId: familyId,
      actorId: guardianId, action: action, entityType: type, entityId: entityId, detail: detail)
  }
}
