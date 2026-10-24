import SwiftUI

struct PaydayView: View {
  @EnvironmentObject private var store: AppStore
  @State private var reviewing = false
  @State private var confirmation = false
  @State private var receipt: Payday?

  private var approvedTotal: Money { store.pending() }
  private var awaitingTotal: Money {
    store.state.assignments.filter { $0.status == .awaitingApproval }.reduce(0) { sum, assignment in
      sum + ((store.item(for: assignment)?.type == .gig) ? assignment.rewardSnapshotCents : 0)
    }
  }
  private var possibleTotal: Money { approvedTotal + awaitingTotal }
  private var isEarly: Bool { !Calendar.current.isDateInToday(store.state.schedule.nextPaydayAt) }

  var body: some View {
    TourScrollView {
      VStack(alignment: .leading, spacing: 26) {
        HStack(alignment: .bottom) {
          PageHeader(
            eyebrow: reviewing && store.role == .parent ? "Final check" : "Money day",
            title: reviewing && store.role == .parent ? "Payday review" : "Upcoming payday",
            subtitle: store.role == .parent
              ? "Only approved, unpaid gigs enter payday."
              : "Approved gig money waits here until your family runs payday.")
          Spacer()
          if store.role == .parent {
            Button(reviewing ? "Back to preview" : "Review payday") {
              withAnimation(.easeInOut(duration: 0.2)) { reviewing.toggle() }
            }.buttonStyle(
              reviewing
                ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle())
            ).disabled(approvedTotal == 0).walkthroughTarget("review-payday")
          }
        }
        if reviewing && store.role == .parent { reviewContent } else { upcomingContent }
      }.padding(32).frame(maxWidth: 1180, alignment: .leading)
    }
    .sheet(isPresented: $confirmation) {
      PaydayConfirmationSheet(early: isEarly) { payday in
        receipt = payday
        confirmation = false
      }
    }
    .sheet(item: $receipt) { PaydayReceiptView(payday: $0) }
  }

  private var upcomingContent: some View {
    VStack(alignment: .leading, spacing: 22) {
      ZStack(alignment: .trailing) {
        RoundedRectangle(cornerRadius: 28).fill(Color.evergreen)
        Circle().fill(Color.sunny).frame(width: 280).offset(x: 75, y: 90)
        Image(systemName: "calendar.badge.clock").font(.system(size: 110, weight: .bold))
          .foregroundStyle(.white.opacity(0.12)).padding(.trailing, 130)
        HStack {
          VStack(alignment: .leading, spacing: 12) {
            Text(store.state.schedule.nextPaydayAt.friendlyDate).font(
              .system(size: 38, weight: .black, design: .rounded))
            Text(countdownText).font(.headline).foregroundStyle(.white.opacity(0.74))
            HStack(spacing: 26) {
              totalStat("Approved", approvedTotal)
              totalStat("Awaiting", awaitingTotal)
              totalStat("Possible", possibleTotal)
            }.padding(.top, 12)
          }
          Spacer()
        }.foregroundStyle(.white).padding(30)
      }.frame(minHeight: 230).walkthroughTarget("payday-summary")
      SectionHeading(title: "By child")
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 390), spacing: 16)], spacing: 16) {
        ForEach(store.state.children) { child in ChildPaydayPreview(child: child) }
      }
      PocketPanel {
        Label(
          "PocketCrew records a family ledger for learning. It doesn’t hold money or connect to a bank in this version.",
          systemImage: "info.circle.fill"
        ).foregroundStyle(Color.ink.opacity(0.65))
      }
    }
  }

  private var reviewContent: some View {
    HStack(alignment: .top, spacing: 20) {
      VStack(alignment: .leading, spacing: 16) {
        SectionHeading(title: "Ready for your jars")
        ForEach(store.state.children) { child in
          let childEarnings = store.state.earnings.filter {
            $0.childId == child.id && $0.status == .approvedUnpaid
          }
          if !childEarnings.isEmpty {
            PocketPanel {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  AvatarView(child: child)
                  Text(child.name).font(.title3.weight(.black))
                  Spacer()
                  Text(childEarnings.reduce(0) { $0 + $1.amountCents }.currency()).font(
                    .title2.weight(.black)
                  ).foregroundStyle(Color.evergreen)
                }
                Divider()
                ForEach(childEarnings) { earning in
                  HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.evergreen)
                    Text(title(for: earning))
                    Spacer()
                    Text(earning.amountCents.currency()).fontWeight(.bold)
                  }
                }
              }
            }
          }
        }
        if !unresolvedAssignments.isEmpty {
          SectionHeading(title: "Still waiting")
          PocketPanel {
            VStack(spacing: 0) {
              ForEach(unresolvedAssignments) { assignment in
                HStack {
                  Image(systemName: "clock.fill").foregroundStyle(Color.sky)
                  VStack(alignment: .leading) {
                    Text(store.item(for: assignment)?.title ?? "Submission").fontWeight(.bold)
                    Text(AppLanguage.text("Waiting for a grown-up")).font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer()
                  if store.item(for: assignment)?.type == .gig {
                    Text(assignment.rewardSnapshotCents.currency()).fontWeight(.bold)
                  }
                }.padding(.vertical, 9)
              }
            }
          }
        }
      }.frame(maxWidth: .infinity)
      PocketPanel {
        VStack(alignment: .leading, spacing: 18) {
          Text("PAYDAY TOTAL").font(.caption.weight(.black)).tracking(1.2).foregroundStyle(
            Color.evergreen)
          Text(approvedTotal.currency()).font(.system(size: 40, weight: .black, design: .rounded))
            .monospacedDigit()
          Divider()
          ForEach(store.state.children) { child in
            if store.pending(childId: child.id) > 0 { allocationSummary(child) }
          }
          Divider()
          let match = totalMatch
          HStack {
            Text("Approved gigs")
            Spacer()
            Text(approvedTotal.currency()).fontWeight(.bold)
          }
          HStack {
            Text("Extra from your grown-up")
            Spacer()
            Text("+\(match.currency())").fontWeight(.bold).foregroundStyle(Color.evergreen)
          }
          Button {
            confirmation = true
          } label: {
            HStack {
              Label(isEarly ? "Pay now" : "Pay now", systemImage: "sparkles")
              Spacer()
              Image(systemName: "arrow.right")
            }
          }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity)
          if isEarly {
            Label(
              "This is before the scheduled date. You’ll confirm once more.",
              systemImage: "clock.badge.exclamationmark"
            ).font(.caption).foregroundStyle(.secondary)
          }
        }
      }.frame(width: 360)
    }
  }

  private var unresolvedAssignments: [WorkAssignment] {
    store.state.assignments.filter { $0.status == .awaitingApproval }
  }
  private var countdownText: String {
    let days = max(
      0,
      Calendar.current.dateComponents([.day], from: Date(), to: store.state.schedule.nextPaydayAt)
        .day ?? 0)
    return days == 0 ? "It’s payday!" : "\(days) day\(days == 1 ? "" : "s") to go"
  }
  private func totalStat(_ label: String, _ amount: Money) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label.uppercased()).font(.caption2.weight(.black)).tracking(1)
      Text(amount.currency()).font(.title2.weight(.black)).monospacedDigit()
    }
  }
  private func title(for earning: Earning) -> String {
    store.state.assignments.first(where: { $0.id == earning.assignmentId }).flatMap(
      store.item(for:))?.title ?? "Approved gig"
  }
  private func allocation(for child: ChildProfile) -> (
    spend: Money, save: Money, give: Money, match: Money
  ) {
    guard let rule = store.split(for: child.id),
      let base = try? FinanceEngine.split(total: store.pending(childId: child.id), rule: rule)
    else { return (0, 0, 0, 0) }
    let matchRule = store.state.matchRules.first { $0.childId == child.id && $0.enabled }
    var match = matchRule.map { base.save * $0.percent / 100 } ?? 0
    if let cap = matchRule?.capCents { match = min(match, cap) }
    return (base.spend, base.save, base.give, match)
  }
  private var totalMatch: Money {
    store.state.children.reduce(0) { $0 + allocation(for: $1).match }
  }
  private func allocationSummary(_ child: ChildProfile) -> some View {
    let value = allocation(for: child)
    return VStack(alignment: .leading, spacing: 9) {
      HStack {
        AvatarView(child: child, size: 28)
        Text(child.name).font(.headline)
        Spacer()
        Text(store.pending(childId: child.id).currency()).fontWeight(.black)
      }
      HStack(spacing: 8) {
        allocationPill(.spend, value.spend)
        allocationPill(.save, value.save + value.match)
        allocationPill(.give, value.give)
      }
    }
  }
  private func allocationPill(_ kind: JarKind, _ amount: Money) -> some View {
    HStack(spacing: 5) {
      Image(systemName: kind.icon)
      Text(amount.currency()).monospacedDigit()
    }.font(.caption.weight(.bold)).foregroundStyle(
      kind == .save ? Color.evergreen : Color.ink.opacity(0.7)
    ).padding(.horizontal, 8).padding(.vertical, 6).background(Color.oat, in: Capsule())
  }
}

struct ChildPaydayPreview: View {
  @EnvironmentObject private var store: AppStore
  let child: ChildProfile
  private var rule: SplitRule? { store.split(for: child.id) }
  private var allocation: (Money, Money, Money) {
    guard let rule,
      let split = try? FinanceEngine.split(total: store.pending(childId: child.id), rule: rule)
    else { return (0, 0, 0) }
    return (split.spend, split.save, split.give)
  }
  var body: some View {
    PocketPanel {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          AvatarView(child: child)
          VStack(alignment: .leading) {
            Text(child.name).font(.title3.weight(.black))
            Text("\(store.pending(childId: child.id).currency()) approved").foregroundStyle(
              .secondary)
          }
          Spacer()
        }
        Divider()
        if let rule {
          HStack {
            splitCell(.spend, rule.spendPercent, allocation.0)
            splitCell(.save, rule.savePercent, allocation.1)
            splitCell(.give, rule.givePercent, allocation.2)
          }
        }
      }
    }
  }
  private func splitCell(_ kind: JarKind, _ percent: Int, _ amount: Money) -> some View {
    HStack(spacing: 8) {
      JarIcon(kind: kind, size: 34)
      VStack(alignment: .leading, spacing: 1) {
        Text("\(kind.title) · \(percent)%").font(.caption.weight(.bold))
        Text(amount.currency()).font(.headline.weight(.black)).monospacedDigit()
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct PaydayConfirmationSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let early: Bool
  let completed: (Payday) -> Void
  @State private var pin = ""
  @State private var confirmEarly = false
  @State private var error = ""
  @State private var processing = false
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Image(systemName: early ? "clock.badge.exclamationmark.fill" : "lock.shield.fill").font(
        .system(size: 38)
      ).foregroundStyle(early ? Color.coral : Color.evergreen)
      Text(early ? "Pay now, before payday?" : "Ready to pay now?").font(.largeTitle.weight(.black))
        .fontDesign(.rounded)
      Text(
        early
          ? "Approved earnings will move now instead of \(store.state.schedule.nextPaydayAt.friendlyDate). Unresolved submissions stay out."
          : "This creates an immutable payday record and posts exact jar transactions. It can’t be paid twice."
      ).foregroundStyle(.secondary)
      if early { Toggle("I understand this is an early payday", isOn: $confirmEarly) }
      SecureField(AppLanguage.text("Parent passcode"), text: $pin).textFieldStyle(.roundedBorder)
      if let hint = store.demoPasscodeHint(for: .parent) {
        Text("Demo parent passcode: \(hint)").font(.caption.weight(.bold)).foregroundStyle(
          .secondary)
      }
      if !error.isEmpty {
        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
      }
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button {
          run()
        } label: {
          if processing {
            ProgressView().controlSize(.small)
          } else {
            Text(early ? "Confirm early payday" : "Pay now")
          }
        }.buttonStyle(PrimaryButtonStyle()).disabled(
          pin.isEmpty || (early && !confirmEarly) || processing)
      }
    }.padding(30).frame(width: 520, height: early ? 430 : 390).background(Color.oat)
  }
  private func run() {
    guard store.verifyParentPasscode(pin) else {
      error = "The parent passcode didn’t match."
      return
    }
    processing = true
    do {
      let payday = try store.runPayday(early: early)
      completed(payday)
    } catch {
      self.error = error.localizedDescription
      processing = false
    }
  }
}

struct PaydayReceiptView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let payday: Payday
  @State private var filled = false
  private var lines: [PaydayLineItem] {
    store.state.paydayLines.filter { $0.paydayId == payday.id }
  }
  var body: some View {
    VStack(spacing: 24) {
      ZStack {
        Circle().fill(Color.sunny).frame(width: 74, height: 74).scaleEffect(filled ? 1 : 0.4)
        Image(systemName: "sparkles").font(.system(size: 34, weight: .bold)).foregroundStyle(
          Color.ink)
      }
      VStack(spacing: 5) {
        Text("Payday complete!").font(.system(size: 38, weight: .black, design: .rounded))
        Text(
          "\(payday.totalEarningsCents.currency()) earned + \(payday.totalMatchCents.currency()) family match"
        ).foregroundStyle(.secondary)
      }
      HStack(spacing: 14) {
        receiptJar(.spend, lines.reduce(0) { $0 + $1.spendCents })
        receiptJar(.save, lines.reduce(0) { $0 + $1.saveCents + $1.matchCents })
        receiptJar(.give, lines.reduce(0) { $0 + $1.giveCents })
      }
      PocketPanel {
        HStack {
          Image(systemName: "doc.text.fill").foregroundStyle(Color.evergreen)
          VStack(alignment: .leading) {
            Text("Receipt saved").fontWeight(.bold)
            Text(payday.processedAt.formatted(date: .long, time: .shortened)).font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text("ID · \(payday.id.uuidString.prefix(8))").font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
      Button(AppLanguage.text("Done")) { dismiss() }.buttonStyle(PrimaryButtonStyle())
    }.padding(36).frame(width: 680, height: 570).background(Color.oat).onAppear {
      if reduceMotion {
        filled = true
      } else {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.1)) { filled = true }
      }
    }
  }
  private func receiptJar(_ kind: JarKind, _ amount: Money) -> some View {
    VStack(spacing: 10) {
      JarIcon(kind: kind, size: 54)
      Text(kind.title).font(.headline)
      Text(amount.currency()).font(.title2.weight(.black)).monospacedDigit()
    }.padding(18).frame(maxWidth: .infinity).background(
      .white, in: RoundedRectangle(cornerRadius: 20)
    ).scaleEffect(filled ? 1 : 0.88).opacity(filled ? 1 : 0)
  }
}
