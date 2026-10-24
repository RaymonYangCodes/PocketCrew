import Foundation

enum DemoData {
  static let familyId = uuid(1), mayaId = uuid(2), alexId = uuid(3), jordanId = uuid(4),
    rileyId = uuid(5)

  static func make() -> PocketCrewState {
    let now = Date()
    let familyId = Self.familyId
    let maya = mayaId
    let children = [
      ChildProfile(
        id: jordanId, createdAt: days(-90), updatedAt: now, createdBy: maya, familyId: familyId,
        name: "Jordan", ageRange: "9–12", avatarSymbol: "figure.basketball", avatarHex: "86BBD8",
        status: "active"),
      ChildProfile(
        id: rileyId, createdAt: days(-90), updatedAt: now, createdBy: maya, familyId: familyId,
        name: "Riley", ageRange: "6–8", avatarSymbol: "star.fill", avatarHex: "F6C453",
        status: "active"),
    ]
    let items = [
      item(
        20, .responsibility, "Make the bed", "Straighten the sheets and arrange the pillows.",
        "Bedroom", 0, .daily, false, false, ["Pull up the sheets", "Place the pillows"]),
      item(
        21, .responsibility, "Pack school bag", "Check tomorrow’s schedule and pack what you need.",
        "School", 0, .daily, false, false, ["Homework folder", "Water bottle"]),
      item(
        22, .responsibility, "Feed the dog", "One scoop of food and fresh water for Pepper.",
        "Pets", 0, .daily, false, false, []),
      item(
        23, .gig, "Wash the car", "Wash, rinse, and dry the family car.", "Outside", 1_200, .once,
        true, true, ["Wash outside", "Rinse", "Dry windows"]),
      item(
        24, .gig, "Organize the pantry", "Group similar foods and place older items in front.",
        "Kitchen", 800, .once, true, false, ["Group cans", "Check dates", "Wipe one shelf"]),
      item(
        25, .gig, "Vacuum the living room", "Vacuum the rug, edges, and under the coffee table.",
        "Cleaning", 400, .weekly, false, false, ["Clear the floor", "Vacuum rug", "Vacuum edges"]),
      item(
        26, .gig, "Rake the leaves", "Gather the leaves by the back fence into the green bin.",
        "Outside", 1_000, .once, true, false, []),
      item(
        27, .gig, "Help plan and cook dinner", "Pick a side dish and help make it with a parent.",
        "Kitchen", 600, .weekly, false, false, ["Choose a side", "Help prep", "Clear the counter"]),
    ]
    let assignments = [
      assignment(40, 20, jordanId, 0, 0, .assigned, ["Pull up the sheets"]),
      assignment(41, 21, rileyId, 0, 0, .inProgress, ["Homework folder"]),
      assignment(42, 22, jordanId, 0, 0, .awaitingApproval, []),
      assignment(43, 23, nil, 2, 1_200, .available, []),
      assignment(
        44, 24, jordanId, 1, 800, .awaitingApproval,
        ["Group cans", "Check dates", "Wipe one shelf"]),
      assignment(
        45, 25, rileyId, 0, 400, .approved, ["Clear the floor", "Vacuum rug", "Vacuum edges"]),
      assignment(46, 26, jordanId, 3, 1_000, .redoRequested, []),
      assignment(
        47, 27, rileyId, -3, 600, .paid, ["Choose a side", "Help prep", "Clear the counter"]),
    ]
    let submissions = [
      submission(60, 42, jordanId, "Pepper ate everything!", .pending, false),
      submission(61, 44, jordanId, "I put snacks low enough for Riley too.", .pending, true),
      submission(62, 45, rileyId, "I got under the table.", .approved, false),
      submission(63, 46, jordanId, "All done by the fence.", .redoRequested, true),
      submission(64, 47, rileyId, "I made the salad.", .approved, false),
    ]
    let firstPayday = uuid(80)
    let lastPayday = uuid(81)
    let paydays = [
      Payday(
        id: firstPayday, createdAt: days(-14), updatedAt: days(-14), createdBy: maya,
        familyId: familyId, scheduledFor: days(-14), processedAt: days(-14), status: "processed",
        idempotencyKey: "seed-first", totalEarningsCents: 5_500, totalMatchCents: 0, early: false),
      Payday(
        id: lastPayday, createdAt: days(-7), updatedAt: days(-7), createdBy: maya,
        familyId: familyId, scheduledFor: days(-7), processedAt: days(-7), status: "processed",
        idempotencyKey: "seed-last", totalEarningsCents: 4_500, totalMatchCents: 160, early: false),
    ]
    let currentEarning = Earning(
      id: uuid(70), createdAt: days(-1), updatedAt: now, createdBy: maya, familyId: familyId,
      childId: rileyId, assignmentId: uuid(45), submissionId: uuid(62), amountCents: 400,
      status: .approvedUnpaid, paydayId: nil)
    let paidEarning = Earning(
      id: uuid(71), createdAt: days(-7), updatedAt: days(-7), createdBy: maya, familyId: familyId,
      childId: rileyId, assignmentId: uuid(47), submissionId: uuid(64), amountCents: 600,
      status: .paid, paydayId: lastPayday)
    let lines = [
      line(90, firstPayday, jordanId, [], 3_500, 1_750, 1_400, 350, 0, -14),
      line(91, firstPayday, rileyId, [], 2_000, 1_200, 600, 200, 0, -14),
      line(92, lastPayday, jordanId, [], 4_000, 2_000, 1_600, 400, 160, -7),
      line(93, lastPayday, rileyId, [paidEarning.id], 500, 300, 150, 50, 0, -7),
    ]
    let ledger = [
      transaction(
        100, jordanId, .spend, 1_750, .payday, "Payday deposit · Spend", -14, firstPayday),
      transaction(101, jordanId, .save, 1_400, .payday, "Payday deposit · Save", -14, firstPayday),
      transaction(102, jordanId, .give, 350, .payday, "Payday deposit · Give", -14, firstPayday),
      transaction(103, rileyId, .spend, 1_200, .payday, "Payday deposit · Spend", -14, firstPayday),
      transaction(104, rileyId, .save, 600, .payday, "Payday deposit · Save", -14, firstPayday),
      transaction(105, rileyId, .give, 200, .payday, "Payday deposit · Give", -14, firstPayday),
      transaction(106, jordanId, .spend, 2_000, .payday, "Payday deposit · Spend", -7, lastPayday),
      transaction(107, jordanId, .save, 1_600, .payday, "Payday deposit · Save", -7, lastPayday),
      transaction(108, jordanId, .save, 160, .payday, "Parent savings match", -7, lastPayday),
      transaction(109, jordanId, .give, 400, .payday, "Payday deposit · Give", -7, lastPayday),
      transaction(110, rileyId, .spend, 300, .payday, "Payday deposit · Spend", -7, lastPayday),
      transaction(111, rileyId, .save, 150, .payday, "Payday deposit · Save", -7, lastPayday),
      transaction(112, rileyId, .give, 50, .payday, "Payday deposit · Give", -7, lastPayday),
      transaction(
        113, jordanId, .save, 5_240, .adjustment, "Moved birthday money to Save", -5, nil),
      transaction(114, jordanId, .spend, -1_290, .spend, "Graphic novel", -3, nil),
      transaction(115, jordanId, .give, -90, .give, "School food drive", -2, nil),
      transaction(116, rileyId, .save, 1_650, .adjustment, "Saved gift money", -6, nil),
      transaction(117, rileyId, .spend, -280, .spend, "Sticker pack", -4, nil),
      transaction(118, rileyId, .give, -30, .give, "Library collection", -1, nil),
    ]
    let jars = children.flatMap { child in
      JarKind.allCases.enumerated().map { offset, kind in
        JarAccount(
          id: uuid(130 + (child.id == jordanId ? 0 : 10) + offset), createdAt: days(-90),
          updatedAt: now, createdBy: maya, familyId: familyId, childId: child.id, kind: kind,
          status: "active")
      }
    }
    let shoppingEntries = [
      ShoppingEntry(
        id: uuid(190), createdAt: days(-4), updatedAt: days(-3), createdBy: jordanId,
        familyId: familyId, childId: jordanId,
        product: ShoppingProduct(
          id: "demo-graphic-novel", source: .pocketCrew, title: "Graphic novel",
          detail: "A new story for the weekend", category: "Books", symbol: "books.vertical.fill",
          priceCents: 1_290, imageURL: nil, productURL: nil),
        status: .purchased, childNote: nil, parentNote: nil, resolvedAt: days(-3),
        ledgerTransactionId: uuid(114)),
      ShoppingEntry(
        id: uuid(191), createdAt: days(-2), updatedAt: days(-2), createdBy: rileyId,
        familyId: familyId, childId: rileyId,
        product: ShoppingProduct(
          id: "demo-dino-puzzle", source: .pocketCrew, title: "Dinosaur puzzle",
          detail: "A colorful 100-piece puzzle", category: "Games", symbol: "puzzlepiece.fill",
          priceCents: 1_199, imageURL: nil, productURL: nil),
        status: .gifted, childNote: nil, parentNote: "Given by a parent — no Spend deducted.",
        resolvedAt: days(-2), ledgerTransactionId: nil),
      ShoppingEntry(
        id: uuid(192), createdAt: days(-1), updatedAt: days(-1), createdBy: jordanId,
        familyId: familyId, childId: jordanId,
        product: ShoppingProduct(
          id: "demo-headphones", source: .pocketCrew, title: "Colorful wireless headphones",
          detail: "Comfortable volume-limited headphones", category: "Tech", symbol: "headphones",
          priceCents: 2_999, imageURL: nil, productURL: nil),
        status: .wishlist, childNote: nil, parentNote: nil, resolvedAt: nil,
        ledgerTransactionId: nil),
      ShoppingEntry(
        id: uuid(193), createdAt: now, updatedAt: now, createdBy: rileyId,
        familyId: familyId, childId: rileyId,
        product: ShoppingProduct(
          id: "demo-card-game", source: .pocketCrew, title: "Family card game",
          detail: "A quick strategy game for the whole crew", category: "Games",
          symbol: "suit.club.fill", priceCents: 999, imageURL: nil, productURL: nil),
        status: .awaitingApproval, childNote: nil, parentNote: nil, resolvedAt: nil,
        ledgerTransactionId: nil),
    ]
    return PocketCrewState(
      version: 1,
      family: Family(
        id: familyId, createdAt: days(-90), updatedAt: now, createdBy: maya, name: "The Parkers",
        timezone: "America/Los_Angeles", currency: "USD", locale: "en_US", status: "active"),
      users: [
        User(
          id: maya, createdAt: days(-90), updatedAt: now, createdBy: maya, displayName: "Maya",
          email: "maya@example.com", status: "active"),
        User(
          id: alexId, createdAt: days(-7), updatedAt: now, createdBy: maya, displayName: "Alex",
          email: "alex@example.com", status: "invited"),
      ],
      members: [
        FamilyMember(
          id: uuid(10), createdAt: days(-90), updatedAt: now, createdBy: maya, familyId: familyId,
          userId: maya, childId: nil, role: .guardian, inviteState: "active"),
        FamilyMember(
          id: uuid(11), createdAt: days(-7), updatedAt: now, createdBy: maya, familyId: familyId,
          userId: alexId, childId: nil, role: .guardian, inviteState: "pending"),
        FamilyMember(
          id: uuid(12), createdAt: days(-90), updatedAt: now, createdBy: maya, familyId: familyId,
          userId: nil, childId: jordanId, role: .child, inviteState: "active"),
        FamilyMember(
          id: uuid(13), createdAt: days(-90), updatedAt: now, createdBy: maya, familyId: familyId,
          userId: nil, childId: rileyId, role: .child, inviteState: "active"),
      ],
      children: children, workItems: items, assignments: assignments, submissions: submissions,
      decisions: [
        ApprovalDecision(
          id: uuid(65), createdAt: days(-1), updatedAt: days(-1), createdBy: maya,
          submissionId: uuid(63), guardianId: maya, decision: .redoRequested,
          reason: "Nice start! Please gather the small pile beside the gate too.")
      ],
      schedule: PaydaySchedule(
        id: uuid(15), createdAt: days(-90), updatedAt: now, createdBy: maya, familyId: familyId,
        frequency: .weekly, nextPaydayAt: nextFriday()),
      earnings: [currentEarning, paidEarning], paydays: paydays, paydayLines: lines, jars: jars,
      ledger: ledger,
      goals: [
        goal(150, jordanId, "Headphones", "🎧", 14_000, 8_400, 45, 1, true, .active),
        goal(151, jordanId, "Bike upgrades", "🚲", 6_000, 0, nil, 2, false, .proposed),
        goal(152, rileyId, "Scooter helmet", "🛴", 6_000, 2_400, 30, 1, true, .active),
        goal(153, rileyId, "Dinosaur book", "🦕", 1_800, 1_800, nil, 2, false, .completed),
      ],
      splits: [
        SplitRule(
          id: uuid(160), createdAt: days(-90), updatedAt: now, createdBy: maya, childId: jordanId,
          spendPercent: 50, savePercent: 40, givePercent: 10),
        SplitRule(
          id: uuid(161), createdAt: days(-90), updatedAt: now, createdBy: maya, childId: rileyId,
          spendPercent: 60, savePercent: 30, givePercent: 10),
      ],
      matchRules: [
        ParentMatchRule(
          id: uuid(170), createdAt: days(-90), updatedAt: now, createdBy: maya, childId: jordanId,
          enabled: true, percent: 10, capCents: 200),
        ParentMatchRule(
          id: uuid(171), createdAt: days(-90), updatedAt: now, createdBy: maya, childId: rileyId,
          enabled: false, percent: 10, capCents: 100),
      ],
      notifications: [
        AppNotification(
          id: uuid(180), createdAt: now, updatedAt: now, createdBy: maya, userId: maya,
          title: "Two items need a look",
          body: "Jordan submitted the pantry and Pepper’s dinner is ready to review.", readAt: nil),
        AppNotification(
          id: uuid(181), createdAt: days(-1), updatedAt: days(-1), createdBy: maya,
          userId: jordanId, title: "One small redo", body: "Check the note on Rake the leaves.",
          readAt: nil),
      ], audit: [], shoppingEntries: shoppingEntries
    )
  }

  private static func item(
    _ n: Int, _ type: WorkType, _ title: String, _ instructions: String, _ category: String,
    _ reward: Money, _ recurrence: Recurrence, _ proof: Bool, _ claimable: Bool,
    _ checklist: [String]
  ) -> WorkItem {
    WorkItem(
      id: uuid(n), createdAt: days(-30), updatedAt: Date(), createdBy: mayaId, familyId: familyId,
      type: type, title: title, instructions: instructions, category: category, rewardCents: reward,
      recurrence: recurrence, proofRequired: proof, claimable: claimable, checklist: checklist,
      lifecycleStatus: "active")
  }
  private static func assignment(
    _ n: Int, _ work: Int, _ child: UUID?, _ dueDays: Int, _ reward: Money, _ status: WorkStatus,
    _ done: [String]
  ) -> WorkAssignment {
    WorkAssignment(
      id: uuid(n), createdAt: days(-3), updatedAt: Date(), createdBy: mayaId,
      workItemId: uuid(work), familyId: familyId, childId: child, dueAt: days(dueDays, hour: 18),
      rewardSnapshotCents: reward, status: status, checklistDone: done,
      estimatedMinutes: reward > 0 ? 30 : 10)
  }
  private static func submission(
    _ n: Int, _ assignment: Int, _ child: UUID, _ note: String, _ status: SubmissionStatus,
    _ proof: Bool
  ) -> WorkSubmission {
    WorkSubmission(
      id: uuid(n), createdAt: days(-1), updatedAt: Date(), createdBy: child,
      assignmentId: uuid(assignment), childId: child,
      submittedAt: days(status == .pending ? 0 : -1), note: note,
      proofImage: proof ? ProofImage(fileName: "proof-photo.jpg", bookmarkData: nil) : nil,
      status: status)
  }
  private static func line(
    _ n: Int, _ payday: UUID, _ child: UUID, _ earnings: [UUID], _ gross: Money, _ spend: Money,
    _ save: Money, _ give: Money, _ match: Money, _ age: Int
  ) -> PaydayLineItem {
    PaydayLineItem(
      id: uuid(n), createdAt: days(age), updatedAt: days(age), createdBy: mayaId, paydayId: payday,
      childId: child, earningIds: earnings, grossCents: gross, spendCents: spend, saveCents: save,
      giveCents: give, matchCents: match)
  }
  private static func transaction(
    _ n: Int, _ child: UUID, _ jar: JarKind, _ amount: Money, _ category: LedgerCategory,
    _ description: String, _ age: Int, _ payday: UUID?
  ) -> LedgerTransaction {
    LedgerTransaction(
      id: uuid(n), createdAt: days(age), updatedAt: days(age), createdBy: mayaId,
      familyId: familyId, childId: child, jar: jar, amountCents: amount, category: category,
      description: description, paydayId: payday, workItemId: nil, reversesTransactionId: nil)
  }
  private static func goal(
    _ n: Int, _ child: UUID, _ title: String, _ icon: String, _ target: Money, _ allocated: Money,
    _ targetDays: Int?, _ priority: Int, _ featured: Bool, _ status: GoalStatus
  ) -> SavingsGoal {
    SavingsGoal(
      id: uuid(n), createdAt: days(-30), updatedAt: Date(), createdBy: mayaId, familyId: familyId,
      childId: child, title: title, icon: icon, targetCents: target, allocatedCents: allocated,
      targetDate: targetDays.map { days($0) }, priority: priority, featured: featured,
      status: status)
  }
  static func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
  }
  static func days(_ offset: Int, hour: Int = 12) -> Date {
    var components = DateComponents()
    components.day = offset
    let date = Calendar.current.date(byAdding: components, to: Date()) ?? Date()
    return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
  }
  static func nextFriday() -> Date {
    var calendar = Calendar.current
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
    let today = Date()
    let weekday = calendar.component(.weekday, from: today)
    let delta = (6 - weekday + 7) % 7
    return calendar.date(
      bySettingHour: 17, minute: 0, second: 0,
      of: calendar.date(byAdding: .day, value: delta, to: today)!)!
  }
}
