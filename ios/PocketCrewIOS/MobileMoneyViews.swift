import SwiftUI

struct MobilePaydayView: View {
  @EnvironmentObject private var store: AppStore
  @State private var confirm = false
  private var unresolved: [WorkAssignment] {
    store.state.assignments.filter { $0.status == .awaitingApproval }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Upcoming payday").font(.largeTitle.bold()).fontDesign(.rounded)
        Text(store.state.schedule.nextPaydayAt.friendlyDate).foregroundStyle(.secondary)
        MobileCard {
          VStack(alignment: .leading, spacing: 12) {
            Text(store.pending().currency()).font(
              .system(size: 42, weight: .black, design: .rounded))
            Text("approved and ready").foregroundStyle(.secondary)
            Divider()
            ForEach(store.state.children) { child in childPreview(child) }
          }
        }
        if !unresolved.isEmpty {
          Text("Awaiting approval—not included").font(.headline)
          ForEach(unresolved) { assignment in
            MobileCard {
              HStack {
                Image(systemName: "clock.fill").foregroundStyle(Color.sky)
                Text(store.item(for: assignment)?.title ?? "Submission")
                Spacer()
                if store.item(for: assignment)?.type == .gig {
                  Text(assignment.rewardSnapshotCents.currency()).bold()
                }
              }
            }
          }
        }
        if store.role == .parent {
          Button("Run \(isEarly ? "early " : "")payday") { confirm = true }.buttonStyle(
            PrimaryButtonStyle()
          ).frame(maxWidth: .infinity).disabled(store.pending() == 0)
        } else {
          Text("Your grown-up runs payday after approved gigs are ready.").font(.caption)
            .foregroundStyle(.secondary)
        }
      }.padding(16)
    }.background(Color.oat).sheet(isPresented: $confirm) { MobilePaydayConfirm(early: isEarly) }
  }
  private var isEarly: Bool { !Calendar.current.isDateInToday(store.state.schedule.nextPaydayAt) }
  private func childPreview(_ child: ChildProfile) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(child.name).font(.headline)
        Spacer()
        Text(store.pending(childId: child.id).currency()).bold()
      }
      if let rule = store.split(for: child.id),
        let split = try? FinanceEngine.split(total: store.pending(childId: child.id), rule: rule)
      {
        HStack {
          jarSplit(.spend, split.spend)
          jarSplit(.save, split.save)
          jarSplit(.give, split.give)
        }
      }
    }
  }
  private func jarSplit(_ jar: JarKind, _ amount: Money) -> some View {
    VStack {
      Image(systemName: jar.icon)
      Text(jar.title).font(.caption2)
      Text(amount.currency()).font(.caption.bold())
    }.frame(maxWidth: .infinity).padding(8).background(
      Color.oat, in: RoundedRectangle(cornerRadius: 12))
  }
}

struct MobilePaydayConfirm: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let early: Bool
  @State private var pin = ""
  @State private var acknowledged = false
  @State private var error = ""
  @State private var finished: Payday?
  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        if let payday = finished {
          Image(systemName: "sparkles").font(.system(size: 56)).foregroundStyle(Color.sunny)
          Text("Payday complete!").font(.largeTitle.bold()).fontDesign(.rounded)
          Text("\(payday.totalEarningsCents.currency()) flowed into the jars.").foregroundStyle(
            .secondary)
          Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        } else {
          Image(systemName: "lock.shield.fill").font(.system(size: 50)).foregroundStyle(
            Color.evergreen)
          Text(early ? "Run payday early?" : "Run payday?").font(.largeTitle.bold()).fontDesign(
            .rounded)
          Text("This creates an immutable receipt and cannot pay the same earning twice.")
            .multilineTextAlignment(.center).foregroundStyle(.secondary)
          if early { Toggle("I understand this is early", isOn: $acknowledged) }
          SecureField("Parent passcode", text: $pin).pocketCrewNumericKeyboard().textFieldStyle(
            .roundedBorder)
          if !error.isEmpty { Text(error).foregroundStyle(.red) }
          Button("Confirm payday") { run() }.buttonStyle(PrimaryButtonStyle()).disabled(
            pin.count != 4 || (early && !acknowledged))
        }
      }.padding(24).navigationTitle("Payday").pocketCrewInlineTitle().toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if finished == nil { Button("Cancel") { dismiss() } }
        }
      }
    }.presentationDetents([.medium])
  }
  private func run() {
    guard store.verifyParentPasscode(pin) else {
      error = "The parent passcode didn’t match."
      return
    }
    do { finished = try store.runPayday(early: early) } catch {
      self.error = error.localizedDescription
    }
  }
}

struct MobileJarsView: View {
  @EnvironmentObject private var store: AppStore
  @State private var search = ""
  private var transactions: [LedgerTransaction] {
    store.state.ledger.filter {
      $0.childId == store.selectedChildId
        && (search.isEmpty || $0.description.localizedCaseInsensitiveContains(search))
    }.sorted { $0.createdAt > $1.createdAt }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 15) {
        Text("Jars").font(.largeTitle.bold()).fontDesign(.rounded)
        ForEach(JarKind.allCases) { jar in
          MobileCard {
            HStack {
              JarIcon(kind: jar, size: 48)
              VStack(alignment: .leading) {
                Text(jar.title).font(.headline)
                Text(store.balance(jar, childId: store.selectedChildId).currency()).font(
                  .title.bold())
              }
              Spacer()
            }
          }
        }
        if let goal = store.goal(for: store.selectedChildId) { MobileGoalCard(goal: goal) }
        Text("Ledger & activity").font(.title2.bold())
        MobileCard {
          VStack(spacing: 0) {
            ForEach(transactions) {
              MobileTransactionRow(transaction: $0)
              Divider()
            }
          }
        }
      }.padding(16)
    }.background(Color.oat).searchable(text: $search, prompt: "Search activity")
  }
}

struct MobileProfileView: View {
  @EnvironmentObject private var store: AppStore
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        AvatarView(child: store.selectedChild, size: 76)
        Text(store.selectedChild.name).font(.largeTitle.bold()).fontDesign(.rounded)
        MobileCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Your payday split").font(.headline)
            if let split = store.split(for: store.selectedChildId) {
              HStack {
                Text("Spend \(split.spendPercent)%")
                Spacer()
                Text("Save \(split.savePercent)%")
                Spacer()
                Text("Give \(split.givePercent)%")
              }.font(.subheadline.bold())
            }
            Divider()
            Label("No child email needed", systemImage: "person.crop.circle.badge.checkmark")
            Label("No sibling leaderboards", systemImage: "person.2.slash.fill")
            Label("Private family data", systemImage: "lock.shield.fill")
          }
        }
      }.padding(16)
    }.background(Color.oat)
  }
}
