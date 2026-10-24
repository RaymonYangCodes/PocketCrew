import Foundation

typealias Money = Int  // Integer cents, always.

enum MemberRole: String, Codable, CaseIterable { case guardian, child }
enum JarKind: String, Codable, CaseIterable, Identifiable {
  case spend, save, give
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var icon: String {
    switch self {
    case .spend: "wallet.bifold.fill"
    case .save: "leaf.fill"
    case .give: "heart.fill"
    }
  }
}
enum WorkType: String, Codable, CaseIterable, Identifiable {
  case responsibility, gig
  var id: String { rawValue }
  var title: String { self == .responsibility ? "Responsibility" : "Paid gig" }
}
enum WorkStatus: String, Codable, CaseIterable {
  case available, assigned, inProgress, awaitingApproval, redoRequested, approved, rejected, paid
  var title: String {
    switch self {
    case .available: "Available"
    case .assigned: "To do"
    case .inProgress: "Working on it"
    case .awaitingApproval: "Waiting for a grown-up"
    case .redoRequested: "Redo requested"
    case .approved: "Approved"
    case .rejected: "Not approved"
    case .paid: "Paid"
    }
  }
}
enum Recurrence: String, Codable, CaseIterable, Identifiable {
  case once, daily, weekly
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}
enum SubmissionStatus: String, Codable { case pending, approved, redoRequested, rejected }
enum DecisionKind: String, Codable { case approved, redoRequested, rejected }
enum EarningStatus: String, Codable { case approvedUnpaid, paid, reversed }
enum LedgerCategory: String, Codable, CaseIterable, Identifiable {
  case earning, payday, spend, save, give, adjustment
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}
enum GoalStatus: String, Codable { case active, completed, archived, proposed }
enum ShoppingProductSource: String, Codable {
  case pocketCrew, amazon, googleShopping

  var title: String {
    switch self {
    case .pocketCrew: "PocketCrew sample"
    case .amazon: "Amazon"
    case .googleShopping: "Google Shopping"
    }
  }
}
enum ShoppingEntryStatus: String, Codable, CaseIterable, Identifiable {
  case wishlist, awaitingApproval, purchased, gifted, declined, removed

  var id: String { rawValue }
  var title: String {
    switch self {
    case .wishlist: "Wishlist"
    case .awaitingApproval: "Waiting for a grown-up"
    case .purchased: "Purchased with Spend"
    case .gifted: "Gift from parent"
    case .declined: "Not approved"
    case .removed: "Removed"
    }
  }
}
enum PaydayFrequency: String, Codable, CaseIterable, Identifiable {
  case weekly, biweekly, twiceMonthly, monthly, custom
  var id: String { rawValue }
  var title: String {
    switch self {
    case .weekly: "Weekly"
    case .biweekly: "Every two weeks"
    case .twiceMonthly: "Twice monthly"
    case .monthly: "Monthly"
    case .custom: "Custom"
    }
  }
}

protocol TimestampedEntity: Codable, Identifiable {
  var id: UUID { get }
  var createdAt: Date { get }
  var updatedAt: Date { get set }
  var createdBy: UUID { get }
}

struct User: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  var displayName: String
  var email: String?
  var status: String
}
struct Family: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  var name: String
  var timezone: String
  var currency: String
  var locale: String
  var status: String
  var workPresetsDismissed: Bool? = nil
}
struct FamilyMember: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  var userId: UUID?
  var childId: UUID?
  var role: MemberRole
  var inviteState: String
}
struct ChildProfile: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  var name: String
  var ageRange: String
  var avatarSymbol: String
  var avatarHex: String
  var status: String
}

/// Parent-entered settings used when creating a child profile. Passcodes stay in the device
/// credential vault and are never serialized into `PocketCrewState` or sent to the cloud.
struct ChildSetupDraft: Identifiable, Equatable, Sendable {
  var id: UUID
  var name: String
  var ageRange: String
  var avatarSymbol: String
  var avatarHex: String
  var passcode: String
  var spendPercent: Int
  var savePercent: Int
  var givePercent: Int

  init(
    id: UUID = UUID(), name: String = "", ageRange: String = "9–12",
    avatarSymbol: String = "star.fill", avatarHex: String = "86BBD8", passcode: String = "",
    spendPercent: Int = 50, savePercent: Int = 40, givePercent: Int = 10
  ) {
    self.id = id
    self.name = name
    self.ageRange = ageRange
    self.avatarSymbol = avatarSymbol
    self.avatarHex = avatarHex
    self.passcode = passcode
    self.spendPercent = spendPercent
    self.savePercent = savePercent
    self.givePercent = givePercent
  }

  var splitTotal: Int { spendPercent + savePercent + givePercent }
  var isComplete: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && passcode.isFourDigitPasscode && splitTotal == 100
      && [spendPercent, savePercent, givePercent].allSatisfy({ 0...100 ~= $0 })
  }

  static let avatarSymbols = [
    "star.fill", "heart.fill", "bolt.fill", "leaf.fill", "pawprint.fill", "sparkles",
  ]
  static let avatarColors = ["86BBD8", "F6C453", "EF7C6A", "78C6A3", "B8A1E3", "F29E4C"]

  static func blank(position: Int = 0) -> ChildSetupDraft {
    ChildSetupDraft(
      avatarSymbol: avatarSymbols[position % avatarSymbols.count],
      avatarHex: avatarColors[position % avatarColors.count])
  }
}
struct WorkItem: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  var type: WorkType
  var title: String
  var instructions: String
  var category: String
  var rewardCents: Money
  var recurrence: Recurrence
  var proofRequired: Bool
  var claimable: Bool
  var checklist: [String]
  var lifecycleStatus: String
}

/// Editable starter content. Choosing a preset never creates work immediately; it only fills the
/// regular creation form so a guardian can change every field before saving.
struct WorkPreset: Identifiable, Hashable {
  let id: String
  let type: WorkType
  let title: String
  let instructions: String
  let category: String
  let rewardCents: Money
  let recurrence: Recurrence
  let estimatedMinutes: Int
  let proofRequired: Bool
  let claimable: Bool
  let checklist: [String]
  let symbol: String

  var presetCategory: String {
    switch category {
    case "School": return "Academic"
    case "Outdoor": return "Outdoors"
    case "Pets": return "Pet care"
    case "Academic", "Outdoors", "Exercise", "Creative", "Pet care": return category
    default: return "Household"
    }
  }

  static let library: [WorkPreset] = [
    WorkPreset(id: "dust-surfaces", type: .gig, title: "Dust reachable surfaces", instructions: "Use a soft cloth on reachable surfaces; leave fragile items alone.", category: "Household", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "sparkles"),
    WorkPreset(id: "sort-socks", type: .gig, title: "Match the socks", instructions: "Pair clean socks and put them in the right drawers.", category: "Household", rewardCents: 75, recurrence: .once, estimatedMinutes: 10, proofRequired: false, claimable: true, checklist: [], symbol: "tshirt.fill"),
    WorkPreset(id: "wipe-doors", type: .gig, title: "Wipe door handles", instructions: "Use a parent-approved damp cloth on reachable handles.", category: "Household", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "door.left.hand.open"),
    WorkPreset(id: "organize-games", type: .gig, title: "Organize board games", instructions: "Match pieces to boxes and stack the games neatly.", category: "Household", rewardCents: 150, recurrence: .once, estimatedMinutes: 20, proofRequired: false, claimable: true, checklist: [], symbol: "puzzlepiece.fill"),
    WorkPreset(id: "read-chapter", type: .gig, title: "Read and summarize a chapter", instructions: "Choose a book and share three things you learned.", category: "Academic", rewardCents: 150, recurrence: .once, estimatedMinutes: 20, proofRequired: false, claimable: true, checklist: [], symbol: "book.fill"),
    WorkPreset(id: "math-practice", type: .gig, title: "Practice math", instructions: "Spend 15 minutes on a parent-approved practice sheet and review mistakes.", category: "Academic", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "number"),
    WorkPreset(id: "spelling-practice", type: .gig, title: "Practice spelling", instructions: "Practice ten words and use each in a sentence.", category: "Academic", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "pencil"),
    WorkPreset(id: "science-journal", type: .gig, title: "Make a science journal page", instructions: "Observe something safe in nature, draw it, and describe what you notice.", category: "Academic", rewardCents: 200, recurrence: .once, estimatedMinutes: 25, proofRequired: false, claimable: true, checklist: [], symbol: "leaf.fill"),
    WorkPreset(id: "water-garden", type: .gig, title: "Water the garden", instructions: "Ask which plants need watering and use the agreed amount.", category: "Outdoors", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "drop.fill"),
    WorkPreset(id: "sweep-patio", type: .gig, title: "Sweep the patio", instructions: "Sweep the agreed area and collect the leaves and dust.", category: "Outdoors", rewardCents: 150, recurrence: .once, estimatedMinutes: 20, proofRequired: false, claimable: true, checklist: [], symbol: "sun.max.fill"),
    WorkPreset(id: "collect-toys", type: .gig, title: "Collect outdoor toys", instructions: "Collect your toys from the yard and put them away.", category: "Outdoors", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "basket.fill"),
    WorkPreset(id: "plant-seeds", type: .gig, title: "Plant some seeds", instructions: "With a grown-up, plant seeds, label them, and water gently.", category: "Outdoors", rewardCents: 200, recurrence: .once, estimatedMinutes: 25, proofRequired: false, claimable: true, checklist: [], symbol: "leaf.fill"),
    WorkPreset(id: "family-walk", type: .gig, title: "Take a family walk", instructions: "Take a comfortable 15-minute walk with your family; stop if you feel unwell.", category: "Exercise", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "figure.walk"),
    WorkPreset(id: "stretch-break", type: .gig, title: "Try a gentle stretch break", instructions: "Choose comfortable stretches with a grown-up. Never stretch through pain.", category: "Exercise", rewardCents: 75, recurrence: .once, estimatedMinutes: 10, proofRequired: false, claimable: true, checklist: [], symbol: "figure.flexibility"),
    WorkPreset(id: "dance-break", type: .gig, title: "Have a dance break", instructions: "Move to three favorite songs in a clear, safe space.", category: "Exercise", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "music.note"),
    WorkPreset(id: "ball-practice", type: .gig, title: "Practice throwing and catching", instructions: "Use a soft ball in a safe space and practice with a partner.", category: "Exercise", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "sportscourt.fill"),
    WorkPreset(id: "thank-you", type: .gig, title: "Write a thank-you card", instructions: "Write and decorate a thoughtful card for someone who helped you.", category: "Creative", rewardCents: 100, recurrence: .once, estimatedMinutes: 20, proofRequired: false, claimable: true, checklist: [], symbol: "envelope.fill"),
    WorkPreset(id: "draw-comic", type: .gig, title: "Draw a short comic", instructions: "Make a four-panel comic with a beginning, middle, and ending.", category: "Creative", rewardCents: 150, recurrence: .once, estimatedMinutes: 25, proofRequired: false, claimable: true, checklist: [], symbol: "paintbrush.fill"),
    WorkPreset(id: "pet-toys", type: .gig, title: "Sort the pet toys", instructions: "Sort safe toys and ask a grown-up to check damaged ones.", category: "Pet care", rewardCents: 100, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "pawprint.fill"),
    WorkPreset(id: "brush-pet", type: .gig, title: "Help brush the pet", instructions: "With a grown-up, gently brush a comfortable pet using the right brush.", category: "Pet care", rewardCents: 150, recurrence: .once, estimatedMinutes: 15, proofRequired: false, claimable: true, checklist: [], symbol: "pawprint.fill"),
    WorkPreset(
      id: "make-bed", type: .responsibility, title: "Make the bed",
      instructions: "Straighten the sheets, pull up the blanket, and arrange the pillows.",
      category: "Bedroom", rewardCents: 0, recurrence: .daily, estimatedMinutes: 5,
      proofRequired: false, claimable: false,
      checklist: ["Straighten sheets", "Pull up blanket", "Arrange pillows"],
      symbol: "bed.double.fill"),
    WorkPreset(
      id: "feed-pet", type: .responsibility, title: "Feed the pet",
      instructions: "Give the correct amount of food and refresh the water bowl.",
      category: "Pets", rewardCents: 0, recurrence: .daily, estimatedMinutes: 10,
      proofRequired: false, claimable: false,
      checklist: ["Add food", "Refresh water", "Put food away"], symbol: "pawprint.fill"),
    WorkPreset(
      id: "pack-school-bag", type: .responsibility, title: "Pack the school bag",
      instructions: "Check tomorrow’s schedule and pack homework, supplies, and water.",
      category: "School", rewardCents: 0, recurrence: .daily, estimatedMinutes: 10,
      proofRequired: false, claimable: false,
      checklist: ["Pack homework", "Pack supplies", "Fill water bottle"],
      symbol: "backpack.fill"),
    WorkPreset(
      id: "clear-table", type: .responsibility, title: "Clear the dinner table",
      instructions: "Bring dishes to the kitchen, wipe the table, and put leftovers away.",
      category: "Kitchen", rewardCents: 0, recurrence: .daily, estimatedMinutes: 15,
      proofRequired: false, claimable: false,
      checklist: ["Clear dishes", "Wipe table", "Put away leftovers"],
      symbol: "fork.knife"),
    WorkPreset(
      id: "tidy-bedroom", type: .responsibility, title: "Tidy the bedroom",
      instructions: "Put clothes, books, and toys back in their homes and clear the floor.",
      category: "Bedroom", rewardCents: 0, recurrence: .weekly, estimatedMinutes: 20,
      proofRequired: false, claimable: false,
      checklist: ["Put away clothes", "Return books and toys", "Clear floor"],
      symbol: "sparkles"),
    WorkPreset(
      id: "take-out-trash", type: .responsibility, title: "Take out the trash",
      instructions: "Tie the bag, place it in the outside bin, and add a fresh liner.",
      category: "Home", rewardCents: 0, recurrence: .weekly, estimatedMinutes: 10,
      proofRequired: false, claimable: false,
      checklist: ["Tie bag", "Take to outside bin", "Add fresh liner"],
      symbol: "trash.fill"),
    WorkPreset(
      id: "wash-car", type: .gig, title: "Wash the car",
      instructions: "Rinse, wash, and dry the outside of the family car without scratching it.",
      category: "Outdoor", rewardCents: 250, recurrence: .once, estimatedMinutes: 45,
      proofRequired: true, claimable: true,
      checklist: ["Rinse car", "Wash from top down", "Rinse and dry"], symbol: "car.fill"),
    WorkPreset(
      id: "organize-pantry", type: .gig, title: "Organize the pantry",
      instructions: "Group similar food, face labels forward, and flag anything expired.",
      category: "Kitchen", rewardCents: 200, recurrence: .once, estimatedMinutes: 35,
      proofRequired: true, claimable: true,
      checklist: ["Group similar items", "Face labels forward", "Flag expired food"],
      symbol: "cabinet.fill"),
    WorkPreset(
      id: "vacuum-living-room", type: .gig, title: "Vacuum the living room",
      instructions: "Move light items, vacuum the full floor and edges, then put everything back.",
      category: "Cleaning", rewardCents: 100, recurrence: .once, estimatedMinutes: 20,
      proofRequired: false, claimable: true,
      checklist: ["Clear the floor", "Vacuum floor and edges", "Put items back"],
      symbol: "wind"),
    WorkPreset(
      id: "rake-leaves", type: .gig, title: "Rake the leaves",
      instructions: "Rake leaves into piles, bag them, and leave the walkway clear.",
      category: "Outdoor", rewardCents: 250, recurrence: .once, estimatedMinutes: 45,
      proofRequired: true, claimable: true,
      checklist: ["Rake into piles", "Bag leaves", "Clear walkway"], symbol: "leaf.fill"),
    WorkPreset(
      id: "cook-dinner", type: .gig, title: "Help plan and cook dinner",
      instructions: "Choose a family-approved meal, help prepare it, and clean the work area.",
      category: "Kitchen", rewardCents: 200, recurrence: .once, estimatedMinutes: 45,
      proofRequired: false, claimable: true,
      checklist: ["Choose meal", "Help prepare food", "Clean work area"],
      symbol: "frying.pan.fill"),
    WorkPreset(
      id: "clean-fridge", type: .gig, title: "Clean the refrigerator",
      instructions: "With a parent, remove old food, wipe shelves, and organize what stays.",
      category: "Kitchen", rewardCents: 250, recurrence: .once, estimatedMinutes: 40,
      proofRequired: true, claimable: true,
      checklist: ["Check food with parent", "Wipe shelves", "Organize remaining food"],
      symbol: "refrigerator.fill"),
    WorkPreset(
      id: "fold-laundry", type: .gig, title: "Fold a load of laundry",
      instructions: "Fold one clean load neatly and place each stack in the right room.",
      category: "Laundry", rewardCents: 150, recurrence: .once, estimatedMinutes: 25,
      proofRequired: false, claimable: true,
      checklist: ["Sort items", "Fold neatly", "Deliver stacks"], symbol: "tshirt.fill"),
    WorkPreset(
      id: "weed-garden", type: .gig, title: "Weed the garden",
      instructions: "Pull weeds from the agreed garden area and collect them for disposal.",
      category: "Outdoor", rewardCents: 200, recurrence: .once, estimatedMinutes: 30,
      proofRequired: true, claimable: true,
      checklist: ["Confirm garden area", "Pull weeds by the roots", "Collect weeds"],
      symbol: "camera.macro"),
    WorkPreset(
      id: "organize-books", type: .gig, title: "Organize the bookshelf",
      instructions: "Remove loose items, group books in an agreed order, and dust the shelf.",
      category: "Organizing", rewardCents: 150, recurrence: .once, estimatedMinutes: 30,
      proofRequired: true, claimable: true,
      checklist: ["Remove loose items", "Group books", "Dust shelf"],
      symbol: "books.vertical.fill"),
    WorkPreset(
      id: "bike-check", type: .gig, title: "Clean and check the bikes",
      instructions: "Wipe down the family bikes and, with a parent, check tires and helmets.",
      category: "Outdoor", rewardCents: 200, recurrence: .once, estimatedMinutes: 35,
      proofRequired: true, claimable: true,
      checklist: ["Wipe frames", "Check tires with parent", "Match helmets"],
      symbol: "bicycle"),
  ]
}
struct WorkAssignment: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let workItemId: UUID
  let familyId: UUID
  var childId: UUID?
  var dueAt: Date
  let rewardSnapshotCents: Money
  var status: WorkStatus
  var checklistDone: [String]
  var estimatedMinutes: Int?
}
struct ProofImage: Codable, Hashable {
  var fileName: String
  /// Raw image data while it is available on the capturing device.
  var bookmarkData: Data?
  /// Family-scoped path in the private Supabase Storage bucket after cloud upload.
  var storagePath: String? = nil
}
struct WorkSubmission: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let assignmentId: UUID
  let childId: UUID
  var submittedAt: Date
  var note: String
  var proofImage: ProofImage?
  var status: SubmissionStatus
}
struct ApprovalDecision: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let submissionId: UUID
  let guardianId: UUID
  let decision: DecisionKind
  let reason: String?
}
struct PaydaySchedule: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  var frequency: PaydayFrequency
  var nextPaydayAt: Date
  var customDays: Int? = nil

  func followingDate(after date: Date, timezone: String) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone) ?? .current
    let result: Date?
    switch frequency {
    case .custom:
      guard let days = customDays, (1...365).contains(days) else {
        throw PocketCrewError.invalid("Choose a whole number from 1 to 365 days.")
      }
      result = calendar.date(byAdding: .day, value: days, to: date)
    case .weekly, .biweekly:
      result = calendar.date(byAdding: .day, value: frequency == .weekly ? 7 : 14, to: date)
    case .monthly: result = calendar.date(byAdding: .month, value: 1, to: date)
    case .twiceMonthly:
      let day = calendar.component(.day, from: date)
      result = calendar.date(byAdding: .day, value: day < 15 ? 15 - day : (calendar.range(of: .day, in: .month, for: date)!.count - day + 1), to: date)
    }
    guard let result else { throw PocketCrewError.invalid("Could not calculate the next payday.") }
    return result
  }
}
struct Earning: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  let childId: UUID
  let assignmentId: UUID
  let submissionId: UUID
  let amountCents: Money
  var status: EarningStatus
  var paydayId: UUID?
}
struct Payday: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  let scheduledFor: Date
  let processedAt: Date
  var status: String
  let idempotencyKey: String
  let totalEarningsCents: Money
  let totalMatchCents: Money
  let early: Bool
}
struct PaydayLineItem: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let paydayId: UUID
  let childId: UUID
  let earningIds: [UUID]
  let grossCents: Money
  let spendCents: Money
  let saveCents: Money
  let giveCents: Money
  let matchCents: Money
}
struct JarAccount: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  let childId: UUID
  let kind: JarKind
  var status: String
}
struct LedgerTransaction: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  let childId: UUID
  let jar: JarKind
  let amountCents: Money
  let category: LedgerCategory
  let description: String
  let paydayId: UUID?
  let workItemId: UUID?
  let reversesTransactionId: UUID?
}
struct SavingsGoal: TimestampedEntity, Hashable {
  var shoppingProduct: ShoppingProduct? = nil
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  let childId: UUID
  var title: String
  var icon: String
  var targetCents: Money
  var allocatedCents: Money
  var targetDate: Date?
  var priority: Int
  var featured: Bool
  var status: GoalStatus
}
struct SplitRule: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let childId: UUID
  var spendPercent: Int
  var savePercent: Int
  var givePercent: Int
}
struct ParentMatchRule: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let childId: UUID
  var enabled: Bool
  var percent: Int
  var capCents: Money?
}
struct AppNotification: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let userId: UUID
  let title: String
  let body: String
  var readAt: Date?
}
struct AuditEvent: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  let actorId: UUID
  let action: String
  let entityType: String
  let entityId: UUID
  let detail: String?
}

/// A point-in-time product snapshot. The app never treats an external product page as the
/// financial source of truth: the displayed title and integer-cent price are copied here when a
/// child adds an item to their wishlist or cart.
struct ShoppingProduct: Codable, Hashable, Identifiable {
  let id: String
  let source: ShoppingProductSource
  let title: String
  let detail: String
  let category: String
  let symbol: String
  var priceCents: Money
  let imageURL: String?
  let productURL: String?
  let currencyCode: String?
  let merchant: String?

  init(
    id: String, source: ShoppingProductSource, title: String, detail: String,
    category: String, symbol: String, priceCents: Money, imageURL: String?,
    productURL: String?, currencyCode: String? = nil, merchant: String? = nil
  ) {
    self.id = id
    self.source = source
    self.title = title
    self.detail = detail
    self.category = category
    self.symbol = symbol
    self.priceCents = priceCents
    self.imageURL = imageURL
    self.productURL = productURL
    self.currencyCode = currencyCode
    self.merchant = merchant
  }

  func formattedPrice(fallbackCurrency: String, locale: String) -> String {
    priceCents.currency(code: currencyCode ?? fallbackCurrency, locale: locale)
  }

  func matchesCurrency(_ currency: String) -> Bool {
    guard let currencyCode else { return source != .googleShopping }
    return currencyCode.uppercased() == currency.uppercased()
  }

  var externalProductURL: URL? {
    guard let productURL, let url = URL(string: productURL),
      url.scheme?.lowercased() == "https", url.host != nil,
      url.user == nil, url.password == nil else { return nil }
    return url
  }
}

struct ShoppingEntry: TimestampedEntity, Hashable {
  let id: UUID
  let createdAt: Date
  var updatedAt: Date
  let createdBy: UUID
  let familyId: UUID
  let childId: UUID
  var product: ShoppingProduct
  var status: ShoppingEntryStatus
  var childNote: String?
  var parentNote: String?
  var resolvedAt: Date?
  var ledgerTransactionId: UUID?
}

struct PocketCrewState: Codable, Equatable {
  var version: Int
  var family: Family
  var users: [User]
  var members: [FamilyMember]
  var children: [ChildProfile]
  var workItems: [WorkItem]
  var assignments: [WorkAssignment]
  var submissions: [WorkSubmission]
  var decisions: [ApprovalDecision]
  var schedule: PaydaySchedule
  var earnings: [Earning]
  var paydays: [Payday]
  var paydayLines: [PaydayLineItem]
  var jars: [JarAccount]
  var ledger: [LedgerTransaction]
  var goals: [SavingsGoal]
  var splits: [SplitRule]
  var matchRules: [ParentMatchRule]
  var notifications: [AppNotification]
  var audit: [AuditEvent]
  /// Optional keeps family snapshots created by older PocketCrew builds backward-compatible.
  var shoppingEntries: [ShoppingEntry]? = nil
  var archivedChildren: [ChildProfile]? = nil
}

enum PocketCrewError: LocalizedError, Equatable {
  case notFound(String)
  case invalid(String)
  case insufficientFunds(JarKind)
  case nothingToPay
  var errorDescription: String? {
    switch self {
    case .notFound(let thing): "We couldn't find that \(thing). Please try again."
    case .invalid(let message): message
    case .insufficientFunds(let jar): "That amount is more than the \(jar.title) balance."
    case .nothingToPay: "There are no approved earnings ready for payday."
    }
  }
}

extension Int {
  func currency(code: String = "USD", locale: String = "en_US") -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    formatter.locale = Locale(identifier: locale)
    return formatter.string(from: NSNumber(value: Double(self) / 100)) ?? "$0.00"
  }
}

extension Date {
  var shortDate: String { formatted(.dateTime.month(.abbreviated).day()) }
  var friendlyDate: String { formatted(.dateTime.weekday(.wide).month(.wide).day()) }
}
