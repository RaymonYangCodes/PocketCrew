import SwiftUI

struct JarsView: View {
  @EnvironmentObject private var store: AppStore
  @State private var search = ""
  @State private var filter: LedgerCategory?
  @State private var goalSheet = false
  @State private var addMoneySheet = false
  @State private var selectedTransaction: LedgerTransaction?
  @State private var goalToRemove: SavingsGoal?
  private var child: ChildProfile { store.selectedChild }
  private var transactions: [LedgerTransaction] {
    store.state.ledger.filter { transaction in
      transaction.childId == child.id && (filter == nil || transaction.category == filter)
        && (search.isEmpty || transaction.description.localizedCaseInsensitiveContains(search))
    }.sorted { $0.createdAt > $1.createdAt }
  }
  var body: some View {
    TourScrollView {
      VStack(alignment: .leading, spacing: 26) {
        HStack(alignment: .bottom) {
          PageHeader(
            eyebrow: "Your jars", title: store.role == .child ? "My Jars" : "Family Jars",
            subtitle:
              "See your balances and goals.")
          Spacer()
          if store.role == .parent {
            Button(AppLanguage.text("Add Money")) { addMoneySheet = true }.buttonStyle(PrimaryButtonStyle())
          }
          Button {
            goalSheet = true
          } label: {
            Label(store.role == .parent ? "Add goal" : "Suggest a goal", systemImage: "plus")
          }.buttonStyle(PrimaryButtonStyle()).walkthroughTarget("add-goal")
        }
        if store.role == .parent {
          Picker("Child", selection: Binding(get: { store.selectedChildId }, set: { id in
            do { try store.selectChildJars(id) } catch { store.show(error: error) }
          })) {
            ForEach(store.state.children) { Text($0.name).tag($0.id) }
          }
        }
        HStack(spacing: 16) {
          ForEach(JarKind.allCases) { kind in
            JarCard(
              kind: kind, amount: store.balance(kind, childId: child.id),
              recent: store.state.ledger.filter { $0.childId == child.id && $0.jar == kind }.sorted
              { $0.createdAt > $1.createdAt }.first)
          }
        }
          HStack(alignment: .top, spacing: 18) {
            if let goal = store.goal(for: child.id) {
            VStack(alignment: .leading, spacing: 14) {
              SectionHeading(title: "My big goal")
              GoalCard(goal: goal)
            }.frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 14) {
              SectionHeading(title: "Wins")
              wins
            }.frame(width: 340)
          }
        PocketPanel {
          VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Your goals")
            Text("Your big goal shows how close your Spend jar is to the target. Spending from that jar lowers the progress.")
              .font(.caption).foregroundStyle(.secondary)
            let goals = store.state.goals.filter { $0.childId == child.id && $0.status != .archived }
            if goals.isEmpty { Text("Goals your grown-up says yes to will appear here.").foregroundStyle(.secondary) }
            ForEach(goals) { goal in
              HStack {
                SavingsGoalArt(goal: goal, size: 36)
                Text(goal.title).fontWeight(.semibold)
                Spacer()
                if goal.featured { Label(AppLanguage.text("Big goal"), systemImage: "star.fill").foregroundStyle(Color.evergreen) }
                else if goal.status == .active {
                  Button(AppLanguage.text("Make my big goal")) {
                    do { try store.featureGoal(goal.id) } catch { store.show(error: error) }
                  }.buttonStyle(SecondaryButtonStyle())
                }
                Button(AppLanguage.text("Remove goal"), role: .destructive) { goalToRemove = goal }.foregroundStyle(.red)
              }
            }
          }
        }.walkthroughTarget("featured-goals")
        HStack {
          SectionHeading(title: "Jar history")
          Spacer()
          TextField("Find something in your jars", text: $search).textFieldStyle(.roundedBorder).frame(
            width: 240).walkthroughTarget("history-search")
        }
        FlowLayout(spacing: 7) {
          Button(AppLanguage.text("All")) { filter = nil }.buttonStyle(FilterPill(active: filter == nil))
          ForEach(LedgerCategory.allCases) { category in
            Button(category.title) { filter = category }.buttonStyle(
              FilterPill(active: filter == category))
          }
        }
        PocketPanel {
          if transactions.isEmpty {
            EmptyState(
              icon: "list.bullet.rectangle", title: "Nothing here yet",
              message:
                "Try another search or filter. New payday deposits and jar activity will appear here."
            )
          } else {
            VStack(spacing: 0) {
              ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                Button {
                  selectedTransaction = transaction
                } label: {
                  LedgerRow(transaction: transaction, resultingBalance: balance(after: transaction))
                }.buttonStyle(.plain)
                if index < transactions.count - 1 { Divider().padding(.leading, 48) }
              }
            }
          }
        }
      }.padding(32).frame(maxWidth: 1180, alignment: .leading)
    }
    .sheet(isPresented: $goalSheet) { GoalSheet(proposed: store.role != .parent) }
    .sheet(isPresented: $addMoneySheet) { AddMoneySheet() }
    .sheet(item: $selectedTransaction) { TransactionDetailSheet(transaction: $0) }
    .alert("Remove this savings goal?", isPresented: Binding(get: { goalToRemove != nil }, set: { if !$0 { goalToRemove = nil } })) {
      Button(AppLanguage.text("Cancel"), role: .cancel) { goalToRemove = nil }
      Button(AppLanguage.text("Remove goal"), role: .destructive) {
        if let goal = goalToRemove {
          do { try store.removeGoal(goal.id) } catch { store.show(error: error) }
        }
        goalToRemove = nil
      }
    } message: {
      Text("The goal will be archived. Your savings and transaction history will stay unchanged. You can choose another featured goal afterward.")
    }
  }
  private var wins: some View {
    PocketPanel {
      let completed = store.state.goals.filter {
        $0.childId == child.id && $0.status == .completed
      }
      if completed.isEmpty {
        EmptyState(
          icon: "trophy.fill", title: "Wins live here",
          message: "Complete a savings goal and it’ll stay here to celebrate.")
      } else {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(completed) { goal in
            HStack {
              SavingsGoalArt(goal: goal, size: 40)
              VStack(alignment: .leading) {
                Text(goal.title).fontWeight(.bold)
                Text("Completed · \(goal.targetCents.currency())")
                  .font(.caption).foregroundStyle(
                  .secondary)
              }
              Spacer()
              Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.sunny)
            }
          }
        }
      }
    }
  }
  private func balance(after transaction: LedgerTransaction) -> Money {
    store.state.ledger.filter {
      $0.childId == transaction.childId && $0.jar == transaction.jar
        && $0.createdAt <= transaction.createdAt
    }.reduce(0) { $0 + $1.amountCents }
  }
}

struct JarCard: View {
  let kind: JarKind
  let amount: Money
  let recent: LedgerTransaction?
  private var tint: Color {
    switch kind {
    case .spend: .coral
    case .save: .evergreen
    case .give: .sky
    }
  }
  private var caption: String {
    switch kind {
    case .spend: "Ready for purchases"
    case .save: "Reserved for your goals"
    case .give: "For generosity and gifts"
    }
  }
  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      PocketPanel {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            JarIcon(kind: kind, size: 50)
            Spacer()
            Text(kind.title.uppercased()).font(.caption.weight(.black)).tracking(1.1)
              .foregroundStyle(tint)
          }
          VStack(alignment: .leading, spacing: 3) {
            Text(amount.currency()).font(.system(size: 32, weight: .black, design: .rounded))
              .monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
          }
          Divider()
          if let recent {
            Text("Latest · \(recent.description)").font(.caption).lineLimit(1).foregroundStyle(
              Color.ink.opacity(0.6))
          } else {
            Text("No activity yet").font(.caption).foregroundStyle(.secondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      Circle().fill(tint.opacity(0.08)).frame(width: 100).offset(x: 32, y: 35)
    }.frame(maxWidth: .infinity).walkthroughTarget("jar-" + kind.rawValue)
  }
}

struct FilterPill: ButtonStyle {
  let active: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.caption.weight(.bold)).foregroundStyle(
      active ? .white : Color.ink.opacity(0.7)
    ).padding(.horizontal, 12).frame(minHeight: 34).background(
      active ? Color.evergreen : .white, in: Capsule()
    ).opacity(configuration.isPressed ? 0.75 : 1)
  }
}

struct LedgerRow: View {
  let transaction: LedgerTransaction
  let resultingBalance: Money
  var body: some View {
    HStack(spacing: 12) {
      JarIcon(kind: transaction.jar, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(transaction.description).font(.subheadline.weight(.bold))
        Text(
          "\(transaction.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(transaction.jar.title) · Balance \(resultingBalance.currency())"
        ).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(
          "\(transaction.amountCents >= 0 ? "+" : "−")\(abs(transaction.amountCents).currency())"
        ).font(.headline.weight(.black)).foregroundStyle(
          transaction.amountCents >= 0 ? Color.evergreen : Color.ink
        ).monospacedDigit()
        Text(transaction.category.title).font(.caption2).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 10).contentShape(Rectangle())
  }
}

struct SavingsGoalArt: View {
  let goal: SavingsGoal
  let size: CGFloat
  var body: some View {
    if let product = goal.shoppingProduct {
      ShoppingProductArt(product: product, size: size)
    } else {
      Text(goal.icon).font(.system(size: size * 0.75))
    }
  }
}

struct GoalSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let proposed: Bool
  private let goalChildId: UUID?
  private let product: ShoppingProduct?
  @State private var title = ""
  @State private var icon = "🎯"
  @State private var amount = ""
  @State private var hasDate = true
  @State private var date = Calendar.current.date(byAdding: .month, value: 2, to: Date())!
  @State private var error = ""
  init(proposed: Bool, childId: UUID? = nil, product: ShoppingProduct? = nil) {
    self.proposed = proposed
    self.goalChildId = childId
    self.product = product
    _title = State(initialValue: product?.title ?? "")
    if let product {
      _amount = State(initialValue: "\(product.priceCents / 100).\(String(format: "%02d", product.priceCents % 100))")
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(proposed ? "Propose a savings goal" : "Create a savings goal").font(
        .largeTitle.weight(.black)
      ).fontDesign(.rounded)
      Text(
        proposed
          ? "Your grown-up will see the idea before it becomes active."
          : "Save deposits will flow to the featured goal."
      ).foregroundStyle(.secondary)
      Form {
        TextField(AppLanguage.text("Goal title"), text: $title)
        if let product {
          HStack {
            Text("Goal photo")
            Spacer()
            ShoppingProductArt(product: product, size: 56)
          }
          LabeledContent("Seller", value: product.merchant ?? "Seller not provided")
          LabeledContent("Item price", value: product.formattedPrice(
            fallbackCurrency: store.state.family.currency, locale: store.state.family.locale))
        } else {
          TextField("Emoji or icon", text: $icon)
        }
        TextField(AppLanguage.text("Target amount"), text: $amount)
        Toggle("Set a target date", isOn: $hasDate)
        if hasDate { DatePicker("Target date", selection: $date, displayedComponents: .date) }
      }.formStyle(.grouped)
      if !error.isEmpty { Text(error).foregroundStyle(Color.coral) }
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button(proposed ? "Send idea" : "Create goal") { save() }.buttonStyle(PrimaryButtonStyle())
      }
    }.padding(28).frame(width: 520, height: product == nil ? 500 : 620).background(Color.oat)
  }
  private func save() {
    let clean = amount.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.range(of: "^[0-9]+([.][0-9]{1,2})?$", options: .regularExpression) != nil,
      let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")),
      value > 0, value <= 1_000_000 else {
      error = "Enter a positive target with up to two decimal places, like 12.99."
      return
    }
    let cents = NSDecimalNumber(decimal: value * 100).intValue
    do {
      try store.addGoal(
        childId: goalChildId ?? store.selectedChildId, title: title, icon: icon.isEmpty ? "🎯" : icon,
        target: cents, targetDate: hasDate ? date : nil, proposed: proposed,
        shoppingProduct: product)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct TransactionDetailSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let transaction: LedgerTransaction
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        JarIcon(kind: transaction.jar, size: 56)
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }.buttonStyle(.plain)
      }
      Text(transaction.description).font(.largeTitle.weight(.black)).fontDesign(.rounded)
      Text("\(transaction.amountCents >= 0 ? "+" : "−")\(abs(transaction.amountCents).currency())")
        .font(.system(size: 36, weight: .black, design: .rounded)).foregroundStyle(
          transaction.amountCents >= 0 ? Color.evergreen : Color.ink)
      Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 12) {
        detail("Date", transaction.createdAt.formatted(date: .long, time: .shortened))
        detail("Child", store.child(transaction.childId)?.name ?? "—")
        detail("Jar", transaction.jar.title)
        detail("Type", transaction.category.title)
        if let payday = transaction.paydayId {
          detail("Payday", String(payday.uuidString.prefix(8)))
        }
        detail("Record ID", String(transaction.id.uuidString.prefix(8)))
      }
      PocketPanel {
        Label(
          "Financial records are append-only. Corrections use a reversing entry instead of changing history.",
          systemImage: "lock.doc.fill"
        ).font(.caption).foregroundStyle(.secondary)
      }
    }.padding(28).frame(width: 500, height: 500, alignment: .topLeading).background(Color.oat)
  }
  private func detail(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).fontWeight(.semibold).textSelection(.enabled)
    }
  }
}

struct ProfileView: View {
  @EnvironmentObject private var store: AppStore
  @State private var proposeGig = false
  var body: some View {
    TourScrollView {
      VStack(alignment: .leading, spacing: 26) {
        PageHeader(
          eyebrow: "Your space", title: "Profile",
          subtitle: "See your settings and share a new idea with your grown-up.")
        PocketPanel {
          HStack(spacing: 18) {
            AvatarView(child: store.selectedChild, size: 74)
            VStack(alignment: .leading, spacing: 4) {
              Text(store.selectedChild.name).font(.largeTitle.weight(.black)).fontDesign(.rounded)
              Text("Age \(store.selectedChild.ageRange) · \(store.state.family.name)")
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
              proposeGig = true
            } label: {
              Label(AppLanguage.text("Suggest a gig"), systemImage: "lightbulb.fill")
            }.buttonStyle(PrimaryButtonStyle()).walkthroughTarget("propose-gig")
          }
        }
        if let split = store.split(for: store.selectedChildId) {
          PocketPanel {
            VStack(alignment: .leading, spacing: 16) {
              SectionHeading(title: "How your jars fill up")
              HStack {
                splitView(.spend, split.spendPercent)
                splitView(.save, split.savePercent)
                splitView(.give, split.givePercent)
              }
              Text("A grown-up manages this split. You can always ask why it’s set this way.").font(
                .caption
              ).foregroundStyle(.secondary)
            }
          }
        }
        PocketPanel {
          VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Keeping you safe")
            Label("No child email needed", systemImage: "person.crop.circle.badge.checkmark")
            Label(
              "Proof images stay private to your family",
              systemImage: "photo.badge.shield.checkmark.fill")
            Label("No sibling rankings or public leaderboards", systemImage: "person.2.slash.fill")
          }.font(.body.weight(.semibold))
        }
      }.padding(32).frame(maxWidth: 1000, alignment: .leading)
    }.sheet(isPresented: $proposeGig) { GigProposalSheet() }
  }
  private func splitView(_ kind: JarKind, _ percent: Int) -> some View {
    HStack {
      JarIcon(kind: kind)
      VStack(alignment: .leading) {
        Text(kind.title).fontWeight(.bold)
        Text("\(percent)%").font(.title2.weight(.black))
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct GigProposalSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var note = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Share a gig idea").font(.largeTitle.weight(.black)).fontDesign(.rounded)
      Text(
        "What useful job could you do? Your grown-up chooses whether to add it and what the reward should be."
      ).foregroundStyle(.secondary)
      TextField("Gig idea", text: $title).textFieldStyle(.roundedBorder)
      TextField("Why it would help (optional)", text: $note, axis: .vertical).lineLimit(3...5)
        .textFieldStyle(.roundedBorder)
      if !error.isEmpty { Text(error).foregroundStyle(Color.coral) }
      Spacer()
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button(AppLanguage.text("Send idea")) {
          do {
            try store.proposeGig(title: title, note: note)
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(PrimaryButtonStyle())
      }
    }.padding(28).frame(width: 520, height: 420).background(Color.oat)
  }
}
