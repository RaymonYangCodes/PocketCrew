import SwiftUI

struct ParentHomeView: View {
  @EnvironmentObject private var store: AppStore
  @State private var createType: WorkType?
  @State private var reviewAssignment: WorkAssignment?
  @State private var transactionSheet = false
  @State private var addChildSheet = false
  @State private var showNotifications = false
  @State private var shoppingSheet = false

  private var pendingReviews: [WorkAssignment] {
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

  var body: some View {
    TourScrollView {
      VStack(alignment: .leading, spacing: 28) {
        HStack(alignment: .top) {
          PageHeader(
            eyebrow: Date().friendlyDate,
            title: "Hi, \(store.guardianDisplayName)",
            subtitle: "Here’s what’s moving in \(store.state.family.name).")
          Spacer()
          Button {
            showNotifications.toggle()
          } label: {
            ZStack(alignment: .topTrailing) {
              Image(systemName: "bell.fill").font(.title3).frame(width: 44, height: 44).background(
                .white, in: Circle())
              Circle().fill(Color.coral).frame(width: 10, height: 10).overlay(
                Circle().stroke(Color.oat, lineWidth: 2))
            }
          }.buttonStyle(.plain).popover(isPresented: $showNotifications) { notificationPopover }
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
          SummaryTile(
            icon: "checkmark.seal.fill", tint: .coral, value: "\(pendingReviews.count)",
            label: "Waiting for review")
          SummaryTile(
            icon: "sparkles", tint: .sunny, value: store.pending().currency(), label: "Next payday")
          SummaryTile(icon: "calendar", tint: .sky, value: "\(dueToday)", label: "Due today")
          SummaryTile(
            icon: "leaf.fill", tint: .evergreen, value: familySavings.currency(),
            label: "Family savings")
        }
        quickActions
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
              title: "Needs your review", action: { store.destination = .work },
              actionTitle: "Open work")
            if pendingReviews.isEmpty {
              PocketPanel {
                EmptyState(
                  icon: "hands.sparkles.fill", title: "All caught up",
                  message: "When someone submits work, it’ll land here for a kind, quick review.")
              }
            } else {
              ForEach(pendingReviews.prefix(3)) { assignment in
                ReviewRow(assignment: assignment) { reviewAssignment = assignment }
              }
            }
          }.frame(maxWidth: .infinity)
          VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Next payday")
            NextPaydayCard()
          }.frame(width: 350)
        }
        SectionHeading(title: "This week")
        PocketPanel {
          VStack(spacing: 0) {
            ForEach(Array(recentActivity.enumerated()), id: \.element.id) { index, event in
              ActivityRow(transaction: event)
              if index < recentActivity.count - 1 { Divider().padding(.leading, 46) }
            }
          }
        }
      }.padding(32).frame(maxWidth: 1220, alignment: .leading)
    }
    .sheet(item: $createType) { initial in CreateWorkSheetInitial(initialType: initial) }
    .sheet(item: $reviewAssignment) { assignment in
      if let submission = store.submission(for: assignment.id) {
        ReviewSheet(assignment: assignment, submission: submission)
      }
    }
    .sheet(isPresented: $transactionSheet) { TransactionSheet(initialCategory: .spend) }
    .sheet(isPresented: $addChildSheet) { AddChildSheet() }
    .sheet(isPresented: $shoppingSheet) { ShoppingCenterView() }
  }

  private var recentActivity: [LedgerTransaction] {
    Array(store.state.ledger.sorted { $0.createdAt > $1.createdAt }.prefix(6))
  }
  private var quickActions: some View {
    HStack(spacing: 10) {
      quick("Add gig", "sparkles") { createType = .gig }
      quick("Add responsibility", "house.fill") { createType = .responsibility }.walkthroughTarget("add-responsibility")
      quick("Add child", "person.badge.plus") { addChildSheet = true }
      quick("Record purchase", "cart.fill") { transactionSheet = true }
      quick("Shopping center", "storefront.fill") { shoppingSheet = true }.walkthroughTarget("shop-entry")
      Spacer()
    }
  }
  private func quick(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon).font(.subheadline.weight(.bold)).padding(.horizontal, 13)
        .frame(minHeight: 42).background(.white.opacity(0.8), in: Capsule()).overlay(
          Capsule().stroke(Color.ink.opacity(0.07)))
    }.buttonStyle(.plain)
  }
  private var notificationPopover: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(AppLanguage.text("What’s new")).font(.title2.weight(.black)).fontDesign(.rounded)
      ForEach(store.state.notifications.filter { $0.userId == store.guardianId }) { note in
        VStack(alignment: .leading, spacing: 3) {
          Text(note.title).fontWeight(.bold)
          Text(note.body).font(.caption).foregroundStyle(.secondary)
        }.padding(12).background(Color.oat, in: RoundedRectangle(cornerRadius: 12))
      }
    }.padding(20).frame(width: 330)
  }
}

struct SummaryTile: View {
  let icon: String
  let tint: Color
  let value: String
  let label: String
  var body: some View {
    PocketPanel(padding: 17) {
      HStack(spacing: 12) {
        Image(systemName: icon).foregroundStyle(tint == .sunny ? Color.ink : tint).font(.title3)
          .frame(width: 42, height: 42).background(
            tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 13))
        VStack(alignment: .leading, spacing: 1) {
          Text(value).font(.title2.weight(.black)).fontDesign(.rounded).monospacedDigit()
          Text(label).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
      }
    }
  }
}

struct ReviewRow: View {
  @EnvironmentObject private var store: AppStore
  let assignment: WorkAssignment
  let open: () -> Void
  var body: some View {
    PocketPanel(padding: 16) {
      HStack(spacing: 13) {
        if let child = store.child(assignment.childId) { AvatarView(child: child) }
        VStack(alignment: .leading, spacing: 4) {
          Text(store.item(for: assignment)?.title ?? "Work item").font(.headline.weight(.bold))
          HStack {
            TypeBadge(type: store.item(for: assignment)?.type ?? .responsibility)
            Text("· Submitted today").font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        if let item = store.item(for: assignment), item.type == .gig {
          Text(assignment.rewardSnapshotCents.currency()).font(.headline.weight(.black))
            .foregroundStyle(Color.evergreen)
        }
        Button("Review", action: open).buttonStyle(PrimaryButtonStyle())
      }
    }
  }
}

struct NextPaydayCard: View {
  @EnvironmentObject private var store: AppStore
  private var days: Int {
    max(
      0,
      Calendar.current.dateComponents(
        [.day], from: Calendar.current.startOfDay(for: Date()),
        to: Calendar.current.startOfDay(for: store.state.schedule.nextPaydayAt)
      ).day ?? 0)
  }
  var body: some View {
    PocketPanel {
      VStack(alignment: .leading, spacing: 17) {
        HStack {
          ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.sunny)
            Image(systemName: "sun.max.fill").foregroundStyle(Color.ink)
          }.frame(width: 48, height: 48)
          Spacer()
          Text(days == 0 ? "TODAY" : days == 1 ? "TOMORROW" : "IN \(days) DAYS").font(
            .caption.weight(.black)
          ).tracking(1).padding(.horizontal, 10).padding(.vertical, 6).background(
            Color.sunny.opacity(0.35), in: Capsule())
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(
            store.state.schedule.nextPaydayAt.formatted(
              .dateTime.weekday(.wide).month(.abbreviated).day())
          ).font(.title2.weight(.black)).fontDesign(.rounded)
          Text("\(store.pending().currency()) approved and ready").foregroundStyle(.secondary)
        }
        ForEach(store.state.children) { child in
          HStack {
            AvatarView(child: child, size: 28)
            Text(child.name).font(.subheadline.weight(.bold))
            Spacer()
            Text(store.pending(childId: child.id).currency()).fontWeight(.bold).monospacedDigit()
          }
        }
        Button {
          store.destination = .payday
        } label: {
          HStack {
            Text(AppLanguage.text("Review payday"))
            Spacer()
            Image(systemName: "arrow.right")
          }
        }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity)
      }
    }
  }
}

struct ChildHomeView: View {
  @EnvironmentObject private var store: AppStore
  @State private var selectedAssignment: WorkAssignment?
  @State private var shoppingSheet = false
  private var child: ChildProfile { store.selectedChild }
  private var today: [WorkAssignment] {
    store.state.assignments.filter {
      ($0.childId == child.id || ($0.childId == nil && store.item(for: $0)?.type == .gig))
        && ![.approved, .paid, .rejected].contains($0.status)
    }.sorted { $0.dueAt < $1.dueAt }
  }
  var body: some View {
    TourScrollView {
      VStack(alignment: .leading, spacing: 28) {
        HStack {
          AvatarView(child: child, size: 58)
          PageHeader(
            eyebrow: Date().friendlyDate, title: "Hey, \(child.name)!",
            subtitle: "One step at a time. Your crew is cheering you on.")
          Spacer()
        }
        HStack(alignment: .center, spacing: 18) {
          ChildPaydayHero().frame(maxWidth: .infinity)
          VStack(spacing: 12) {
            ForEach(JarKind.allCases) { jar in
              MiniJarCard(jar: jar, amount: store.balance(jar, childId: child.id))
            }
          }.frame(width: 280)
        }
        Button {
          shoppingSheet = true
        } label: {
          HStack {
            Label("Open PocketCrew Shop", systemImage: "storefront.fill")
            Spacer()
            Text("Wishlist · Ask to buy · Purchases").font(.caption).opacity(0.8)
            Image(systemName: "arrow.right")
          }
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(maxWidth: .infinity).walkthroughTarget("shop-entry")
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
              title: "Today", action: { store.destination = .work }, actionTitle: "See all work")
            if today.isEmpty {
              PocketPanel {
                EmptyState(
                  icon: "sun.max.fill", title: "Today is wide open",
                  message:
                    "There’s nothing due right now. Check Available gigs if you feel like earning.")
              }
            } else {
              ForEach(today.prefix(4)) { assignment in
                CompactWorkRow(assignment: assignment) { selectedAssignment = assignment }
              }
            }
          }.frame(maxWidth: .infinity)
          VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Your big goal")
            if let goal = store.goal(for: child.id) {
              GoalCard(goal: goal)
            } else {
              PocketPanel {
                EmptyState(
                  icon: "target", title: "Dream up a goal",
                  message:
                    "Propose something worth saving for and your grown-up can help set it up.")
              }
            }
          }.frame(width: 370)
        }
      }.padding(32).frame(maxWidth: 1160, alignment: .leading)
    }
    .sheet(item: $selectedAssignment) { WorkDetailSheet(assignment: $0) }
    .sheet(isPresented: $shoppingSheet) { ShoppingCenterView() }
  }
}

struct ChildPaydayHero: View {
  @EnvironmentObject private var store: AppStore
  private var days: Int {
    max(
      0,
      Calendar.current.dateComponents([.day], from: Date(), to: store.state.schedule.nextPaydayAt)
        .day ?? 0)
  }
  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.evergreen)
      Circle().fill(Color.sunny.opacity(0.9)).frame(width: 170).offset(x: 45, y: 65)
      Image(systemName: "sparkles").font(.system(size: 68)).foregroundStyle(.white.opacity(0.14))
        .offset(x: -30, y: -50)
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Label("NEXT PAYDAY", systemImage: "calendar.badge.clock").font(.caption.weight(.black))
            .tracking(1.3)
          Spacer()
          Text(days == 0 ? "Today!" : "\(days) day\(days == 1 ? "" : "s")").font(
            .caption.weight(.black)
          ).padding(
            .horizontal, 11
          ).padding(.vertical, 6).background(.white.opacity(0.15), in: Capsule())
        }
        Spacer()
        VStack(alignment: .leading, spacing: 2) {
          Text(store.pending(childId: store.selectedChildId).currency()).font(
            .system(size: 46, weight: .black, design: .rounded)
          ).monospacedDigit()
          Text("approved and ready for your jars").foregroundStyle(.white.opacity(0.75))
        }
        Text(store.state.schedule.nextPaydayAt.friendlyDate).font(.headline.weight(.bold))
      }.foregroundStyle(.white).padding(24).frame(
        maxWidth: .infinity, minHeight: 230, alignment: .leading)
    }.accessibilityElement(children: .combine)
  }
}

struct MiniJarCard: View {
  @EnvironmentObject private var store: AppStore
  let jar: JarKind
  let amount: Money
  var body: some View {
    PocketPanel(padding: 13) {
      HStack {
        JarIcon(kind: jar, size: 40)
        VStack(alignment: .leading) {
          Text(jar.title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
          Text(
            amount.currency(code: store.state.family.currency, locale: store.state.family.locale)
          ).font(.title3.weight(.black)).monospacedDigit()
        }
        Spacer()
      }
    }
  }
}

struct CompactWorkRow: View {
  @EnvironmentObject private var store: AppStore
  let assignment: WorkAssignment
  let open: () -> Void
  var body: some View {
    PocketPanel(padding: 14) {
      HStack(spacing: 12) {
        Image(systemName: store.item(for: assignment)?.type == .gig ? "sparkles" : "checkmark")
          .font(.headline.weight(.bold)).foregroundStyle(
            store.item(for: assignment)?.type == .gig ? Color.evergreen : Color.sky
          ).frame(width: 42, height: 42).background(
            (store.item(for: assignment)?.type == .gig ? Color.evergreen : Color.sky).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 13))
        VStack(alignment: .leading, spacing: 3) {
          Text(store.item(for: assignment)?.title ?? "Work").font(.headline.weight(.bold))
          StatusBadge(status: assignment.status)
        }
        Spacer()
        if let item = store.item(for: assignment), item.type == .gig {
          Text(assignment.rewardSnapshotCents.currency()).font(.headline.weight(.black))
            .foregroundStyle(Color.evergreen)
        }
        Button(store.role == .child && assignment.status == .available ? "Claim" : "Open") {
          do {
            if store.role == .child && assignment.status == .available {
              try store.start(assignment.id)
            }
            open()
          } catch { store.show(error: error) }
        }.buttonStyle(
          SecondaryButtonStyle())
      }
    }
  }
}

struct GoalCard: View {
  @EnvironmentObject private var store: AppStore
  let goal: SavingsGoal
  private var progressAmount: Money {
    goal.featured ? max(0, store.balance(.spend, childId: goal.childId)) : goal.allocatedCents
  }
  private var progress: Double {
    min(1, Double(progressAmount) / Double(max(goal.targetCents, 1)))
  }
  var body: some View {
    PocketPanel {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          SavingsGoalArt(goal: goal, size: 52)
          VStack(alignment: .leading) {
            Text(goal.title).font(.title2.weight(.black)).fontDesign(.rounded)
            if let seller = goal.shoppingProduct?.merchant {
              Text("Sold by \(seller)").font(.caption).foregroundStyle(.secondary)
            }
            if let date = goal.targetDate {
              Text("Goal date · \(date.shortDate)").font(.caption).foregroundStyle(.secondary)
            }
          }
          Spacer()
        }
        VStack(alignment: .leading, spacing: 7) {
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(Color.evergreen.opacity(0.12))
              Capsule().fill(Color.evergreen).frame(width: geo.size.width * progress)
            }
          }.frame(height: 13)
          HStack {
            Text(progressAmount.currency()).fontWeight(.black)
            Spacer()
            Text("\(max(0, goal.targetCents - progressAmount).currency()) to go").font(
              .caption.weight(.bold)
            ).foregroundStyle(.secondary)
          }
        }
        if goal.featured {
          Text("\(Int(progress * 100))% · Based on your Spend balance. No money is moved.")
            .font(.caption).foregroundStyle(.secondary)
        }
        HStack {
          ForEach([25, 50, 75, 100], id: \.self) { milestone in
            Label(
              "\(milestone)%",
              systemImage: Int(progress * 100) >= milestone ? "checkmark.circle.fill" : "circle"
            ).font(.caption2.weight(.bold)).foregroundStyle(
              Int(progress * 100) >= milestone ? Color.evergreen : Color.secondary)
          }
        }
      }.accessibilityElement(children: .combine).accessibilityLabel(
        "\(goal.title), \(Int(progress * 100)) percent, \(max(0, goal.targetCents - progressAmount).currency()) remaining"
      )
    }
  }
}

struct ActivityRow: View {
  @EnvironmentObject private var store: AppStore
  let transaction: LedgerTransaction
  var body: some View {
    HStack(spacing: 12) {
      JarIcon(kind: transaction.jar, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(transaction.description).font(.subheadline.weight(.bold))
        HStack {
          Text(store.child(transaction.childId)?.name ?? "Child")
          Text("·")
          Text(transaction.createdAt.shortDate)
          Text("·")
          Text(transaction.jar.title)
        }.font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Text("\(transaction.amountCents >= 0 ? "+" : "−")\(abs(transaction.amountCents).currency())")
        .font(.subheadline.weight(.black)).foregroundStyle(
          transaction.amountCents >= 0 ? Color.evergreen : Color.ink
        ).monospacedDigit().accessibilityLabel(
          transaction.amountCents >= 0
            ? "Credit \(transaction.amountCents.currency())"
            : "Debit \(abs(transaction.amountCents).currency())")
    }.padding(.vertical, 10)
  }
}

struct CreateWorkSheetInitial: View {
  let initialType: WorkType
  var body: some View { CreateWorkSheet(initialType: initialType) }
}

struct AddChildSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var child = ChildSetupDraft.blank()
  @State private var error = ""
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Add a child").font(.largeTitle.weight(.black)).fontDesign(.rounded)
        Text(
          "Create an independent profile with its own passcode, avatar, and payday jar split."
        ).foregroundStyle(.secondary)
        ChildSettingsEditor(child: $child, title: "New child")
        if !error.isEmpty {
          Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
        }
        HStack {
          Spacer()
          Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
          Button(AppLanguage.text("Add Child")) {
            do {
              try store.addChild(child)
              dismiss()
            } catch { self.error = error.localizedDescription }
          }.buttonStyle(PrimaryButtonStyle()).disabled(!child.isComplete)
        }
      }.padding(28)
    }.frame(width: 620, height: 720).background(Color.oat)
  }
}

struct EditChildSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let childId: UUID
  @State private var draft: ChildSetupDraft
  @State private var error = ""

  init(child: ChildProfile, split: SplitRule) {
    childId = child.id
    _draft = State(
      initialValue: ChildSetupDraft(
        id: child.id, name: child.name, ageRange: child.ageRange,
        avatarSymbol: child.avatarSymbol, avatarHex: child.avatarHex,
        spendPercent: split.spendPercent, savePercent: split.savePercent,
        givePercent: split.givePercent))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Edit child settings").font(.largeTitle.weight(.black)).fontDesign(.rounded)
        Text("Changes apply only to this child. Their balances and history stay intact.")
          .foregroundStyle(.secondary)
        ChildSettingsEditor(child: $draft, title: draft.name, showsPasscode: false)
        if !error.isEmpty {
          Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
        }
        HStack {
          Spacer()
          Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
          Button(AppLanguage.text("Save changes")) { save() }.buttonStyle(PrimaryButtonStyle()).disabled(!isValid)
        }
      }.padding(28)
    }.frame(width: 620, height: 700).background(Color.oat)
  }

  private var isValid: Bool {
    !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && draft.splitTotal == 100
      && [draft.spendPercent, draft.savePercent, draft.givePercent].allSatisfy({ 0...100 ~= $0 })
  }

  private func save() {
    do {
      try store.updateChild(
        childId: childId, name: draft.name, ageRange: draft.ageRange,
        avatarSymbol: draft.avatarSymbol, avatarHex: draft.avatarHex,
        spend: draft.spendPercent, save: draft.savePercent, give: draft.givePercent)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct TransactionSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let initialCategory: LedgerCategory
  @State private var childId: UUID = DemoData.jordanId
  @State private var jar: JarKind = .spend
  @State private var amount = ""
  @State private var isDebit = true
  @State private var reason = ""
  @State private var pin = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(
        initialCategory == .spend
          ? "Record a purchase"
          : initialCategory == .save ? "Record a savings withdrawal" : "Add ledger entry"
      ).font(.largeTitle.weight(.black)).fontDesign(.rounded)
      Text("This updates your jar history. No real money is moved.").foregroundStyle(
        .secondary)
      Form {
        Picker("Child", selection: $childId) {
          ForEach(store.state.children) { Text($0.name).tag($0.id) }
        }
        Picker("Jar", selection: $jar) {
          ForEach(JarKind.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
        }
        TextField(AppLanguage.text("Amount"), text: $amount)
        Toggle("Subtract from the jar", isOn: $isDebit)
        TextField("Required reason or destination", text: $reason)
        SecureField(AppLanguage.text("Parent passcode"), text: $pin)
      }.formStyle(.grouped)
      if !error.isEmpty {
        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
      }
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button("Save to jar history") { save() }.buttonStyle(PrimaryButtonStyle()).disabled(
          reason.isEmpty || amount.isEmpty)
      }
    }.padding(28).frame(width: 540, height: 550).background(Color.oat).onAppear {
      childId = store.selectedChildId
      if initialCategory == .spend {
        jar = .spend
        isDebit = true
      } else if initialCategory == .save {
        jar = .save
        isDebit = true
      }
    }
  }
  private func save() {
    guard store.verifyParentPasscode(pin) else {
      error = "The parent passcode didn’t match."
      return
    }
    let cents = Int(((Double(amount) ?? 0) * 100).rounded()) * (isDebit ? -1 : 1)
    do {
      try store.record(
        childId: childId, jar: jar, amount: cents,
        category: isDebit ? LedgerCategory(rawValue: jar.rawValue) ?? .adjustment : .adjustment,
        reason: reason)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
