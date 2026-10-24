import SwiftUI

struct MobileHomeView: View {
  @EnvironmentObject private var store: AppStore
  @State private var shoppingSheet = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if store.role == .parent { parentHome } else { childHome }
      }.padding(16)
    }
    .background(Color.oat).pocketCrewInlineTitle()
    .sheet(isPresented: $shoppingSheet) { ShoppingCenterView() }
  }

  private var parentHome: some View {
    Group {
      VStack(alignment: .leading, spacing: 5) {
        Text(Date().friendlyDate.uppercased()).font(.caption2.bold()).tracking(1.1)
          .foregroundStyle(Color.evergreen)
        Text("Hi, \(store.guardianDisplayName)")
          .font(.largeTitle.bold()).fontDesign(.rounded)
        Text("Here’s what’s moving in \(store.state.family.name).").foregroundStyle(.secondary)
      }
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        metric("Needs review", "\(reviewAssignments.count)", "checkmark.seal.fill", .coral)
        metric("Next payday", store.pending().currency(), "sparkles", .sunny)
        metric("Due today", "\(dueToday)", "calendar", .sky)
        metric("Family savings", familySavings.currency(), "leaf.fill", .evergreen)
      }
      Button {
        shoppingSheet = true
      } label: {
        Label("Open PocketCrew Shop", systemImage: "storefront.fill")
          .frame(maxWidth: .infinity, minHeight: 44)
      }.buttonStyle(.borderedProminent)
      HStack {
        Text("Needs your review").font(.title2.bold()).fontDesign(.rounded)
        Spacer()
        Button("Open work") { store.destination = .work }.font(.subheadline.bold())
      }
      if reviewAssignments.isEmpty {
        MobileCard { Label("All caught up", systemImage: "checkmark.circle.fill").font(.headline) }
      } else {
        ForEach(reviewAssignments.prefix(3)) { assignment in
          MobileReviewRow(assignment: assignment)
        }
      }
      MobilePaydaySummary()
      Text("Recent activity").font(.title2.bold()).fontDesign(.rounded)
      MobileCard {
        VStack(spacing: 0) {
          ForEach(store.state.ledger.sorted { $0.createdAt > $1.createdAt }.prefix(5)) { item in
            MobileTransactionRow(transaction: item)
            if item.id
              != store.state.ledger.sorted(by: { $0.createdAt > $1.createdAt }).prefix(5).last?.id
            {
              Divider()
            }
          }
        }
      }
    }
  }

  private var childHome: some View {
    Group {
      HStack(spacing: 12) {
        AvatarView(child: store.selectedChild, size: 54)
        VStack(alignment: .leading) {
          Text("Hey, \(store.selectedChild.name)!").font(.largeTitle.bold()).fontDesign(.rounded)
          Text("Your crew is cheering you on.").foregroundStyle(.secondary)
        }
      }
      ZStack(alignment: .bottomTrailing) {
        RoundedRectangle(cornerRadius: 24).fill(Color.evergreen)
        Circle().fill(Color.sunny.opacity(0.85)).frame(width: 130).offset(x: 40, y: 45)
        VStack(alignment: .leading, spacing: 8) {
          Label("NEXT PAYDAY", systemImage: "calendar.badge.clock").font(.caption.bold()).tracking(
            1)
          Spacer()
          Text(store.pending(childId: store.selectedChildId).currency()).font(
            .system(size: 42, weight: .black, design: .rounded))
          Text("approved and ready for your jars").font(.subheadline).opacity(0.78)
          Text(store.state.schedule.nextPaydayAt.friendlyDate).font(.subheadline.bold())
        }.foregroundStyle(.white).padding(20).frame(
          maxWidth: .infinity, minHeight: 210, alignment: .leading)
      }
      HStack(spacing: 9) {
        ForEach(JarKind.allCases) { jar in
          VStack(spacing: 7) {
            JarIcon(kind: jar, size: 38)
            Text(jar.title).font(.caption.bold())
            Text(store.balance(jar, childId: store.selectedChildId).currency()).font(
              .subheadline.bold())
          }.padding(.vertical, 12).frame(maxWidth: .infinity).background(
            .white, in: RoundedRectangle(cornerRadius: 17))
        }
      }
      Button {
        shoppingSheet = true
      } label: {
        HStack {
          Label("PocketCrew Shop", systemImage: "storefront.fill")
          Spacer()
          Text("Wishlist · Cart").font(.caption)
          Image(systemName: "arrow.right")
        }.frame(minHeight: 44)
      }.buttonStyle(.borderedProminent)
      HStack {
        Text("Today").font(.title2.bold())
        Spacer()
        Button("See all") { store.destination = .work }
      }
      ForEach(childAssignments.prefix(4)) { assignment in MobileWorkRow(assignment: assignment) }
      if let goal = store.goal(for: store.selectedChildId) { MobileGoalCard(goal: goal) }
    }
  }

  private var reviewAssignments: [WorkAssignment] {
    store.state.assignments.filter { $0.status == .awaitingApproval }
  }
  private var dueToday: Int {
    store.state.assignments.filter {
      Calendar.current.isDateInToday($0.dueAt)
        && ![.approved, .paid, .rejected].contains($0.status)
    }.count
  }
  private var familySavings: Money {
    store.state.children.reduce(0) { $0 + store.balance(.save, childId: $1.id) }
  }
  private var childAssignments: [WorkAssignment] {
    store.state.assignments.filter {
      ($0.childId == store.selectedChildId || $0.childId == nil)
        && ![.approved, .paid, .rejected].contains($0.status)
    }
  }

  private func metric(_ title: String, _ value: String, _ symbol: String, _ color: Color)
    -> some View
  {
    MobileCard {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: symbol).foregroundStyle(color)
        Text(value).font(.title2.bold()).monospacedDigit()
        Text(title).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

struct MobileReviewRow: View {
  @EnvironmentObject private var store: AppStore
  let assignment: WorkAssignment
  @State private var review = false
  var body: some View {
    MobileCard {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(store.item(for: assignment)?.title ?? "Work").font(.headline)
          Text(store.child(assignment.childId)?.name ?? "Child").font(.caption).foregroundStyle(
            .secondary)
        }
        Spacer()
        Button("Review") { review = true }.buttonStyle(.borderedProminent)
      }
    }.sheet(isPresented: $review) {
      if let submission = store.submission(for: assignment.id) {
        MobileReviewSheet(assignment: assignment, submission: submission)
      }
    }
  }
}

struct MobilePaydaySummary: View {
  @EnvironmentObject private var store: AppStore
  var body: some View {
    MobileCard {
      VStack(alignment: .leading, spacing: 12) {
        Label("NEXT PAYDAY", systemImage: "sun.max.fill").font(.caption.bold()).foregroundStyle(
          Color.evergreen)
        Text(store.state.schedule.nextPaydayAt.friendlyDate).font(.title2.bold()).fontDesign(
          .rounded)
        Text("\(store.pending().currency()) approved and ready").foregroundStyle(.secondary)
        ForEach(store.state.children) { child in
          HStack {
            Text(child.name)
            Spacer()
            Text(store.pending(childId: child.id).currency()).bold()
          }
        }
        Button("Review payday") { store.destination = .payday }.buttonStyle(.borderedProminent)
      }
    }
  }
}

struct MobileGoalCard: View {
  let goal: SavingsGoal
  private var progress: Double {
    min(1, Double(goal.allocatedCents) / Double(max(goal.targetCents, 1)))
  }
  var body: some View {
    MobileCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("YOUR BIG GOAL").font(.caption.bold()).tracking(1).foregroundStyle(Color.evergreen)
        HStack {
          Text(goal.icon).font(.largeTitle)
          Text(goal.title).font(.title2.bold())
        }
        ProgressView(value: progress).tint(Color.evergreen)
        HStack {
          Text(goal.allocatedCents.currency()).bold()
          Spacer()
          Text("\((goal.targetCents - goal.allocatedCents).currency()) to go").font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

struct MobileTransactionRow: View {
  @EnvironmentObject private var store: AppStore
  let transaction: LedgerTransaction
  var body: some View {
    HStack(spacing: 10) {
      JarIcon(kind: transaction.jar, size: 34)
      VStack(alignment: .leading) {
        Text(transaction.description).font(.subheadline.bold())
        Text(
          "\(store.child(transaction.childId)?.name ?? "Child") · \(transaction.createdAt.shortDate)"
        ).font(.caption2).foregroundStyle(.secondary)
      }
      Spacer()
      Text("\(transaction.amountCents >= 0 ? "+" : "−")\(abs(transaction.amountCents).currency())")
        .font(.subheadline.bold()).foregroundStyle(
          transaction.amountCents >= 0 ? Color.evergreen : Color.ink)
    }.padding(.vertical, 9)
  }
}
