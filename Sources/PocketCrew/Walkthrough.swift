import SwiftUI

struct WalkthroughAnchors: PreferenceKey {
  static let defaultValue: [String: Anchor<CGRect>] = [:]
  static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
extension View {
  func walkthroughTarget(_ id: String) -> some View {
    anchorPreference(key: WalkthroughAnchors.self, value: .bounds) { [id: $0] }.id(id)
  }
}
extension Notification.Name {
  static let replayCrewWalkthrough = Notification.Name("pocketcrew.replayWalkthrough")
  static let crewTourTarget = Notification.Name("pocketcrew.tourTarget")
}
struct TourScrollView<Content: View>: View {
  @ViewBuilder let content: () -> Content
  var body: some View {
    ScrollViewReader { reader in
      ScrollView { content() }
        .onReceive(NotificationCenter.default.publisher(for: .crewTourTarget)) { note in
          if let target = note.object as? String { reader.scrollTo(target, anchor: .center) }
        }
    }
  }
}
struct CrewTourStep {
  let destination: AppDestination
  let target: String
  let title: String
  let text: String
  static func steps(parent: Bool) -> [Self] {
    let common: [Self] = [
      .init(destination: .home, target: "switch-profile", title: "Choose your profile", text: "Switch between people here. Parents can view their children without entering a child's passcode. Children cannot unlock a parent profile without its passcode."),
      .init(destination: .home, target: "home", title: "Home", text: "Your dashboard brings tasks, payday, jars and goals together."),
      .init(destination: .work, target: "work", title: "Tasks", text: "Find assigned responsibilities and paid gigs here."),
      .init(destination: .work, target: "task-segments", title: "My tasks, available gigs and completed tasks", text: "Use these tabs to switch lists. Claim an available gig, start an assigned task, then submit the finished task for review."),
      .init(destination: .work, target: "task-filter-All", title: "All task types", text: "Show both paid gigs and unpaid responsibilities."),
      .init(destination: .work, target: "task-filter-Today", title: "Due today", text: "Filter the list to tasks due today."),
      .init(destination: .work, target: "task-filter-This week", title: "This week's tasks", text: "Plan ahead by looking at tasks due this week."),
      .init(destination: .work, target: "task-filter-Responsibilities", title: "Responsibilities", text: "These are unpaid contributions to your household. Start and finish them just like tasks."),
      .init(destination: .work, target: "task-filter-Gigs", title: "Paid gigs", text: "Gigs have a reward. Submit your work when it is finished; a parent approves it before payday."),
      .init(destination: .payday, target: "payday-summary", title: "Your upcoming payday", text: "See the date, approved earnings and earnings still awaiting a parent's review."),
      .init(destination: .payday, target: "heading-By child", title: "Payday breakdown", text: "Each child's approved earnings use their own Spend, Save and Give percentages."),
      .init(destination: .home, target: "shop-entry", title: "Shopping center", text: "Search for items, save wishes, request purchases, and propose a savings goal. Parents handle actual store checkout.")
    ]
    let details: [Self] = parent ? [
      .init(destination: .home, target: "heading-Needs your review", title: "Task approvals", text: "Submitted tasks appear here. Open one to approve it or ask for a redo with a helpful note."),
      .init(destination: .home, target: "heading-This week", title: "Recent family activity", text: "Keep up with money recorded for your family. This history is a learning ledger, not a bank account."),
      .init(destination: .home, target: "add-responsibility", title: "Add a responsibility", text: "Open the task form with an unpaid responsibility selected. Enter the name, instructions, child and due date."),
      .init(destination: .work, target: "add-task", title: "Add a paid gig", text: "Choose a task type, name, instructions, reward, child and due date. Save only when the details are ready."),
      .init(destination: .work, target: "task-presets", title: "Editable presets", text: "Select a ready-made idea to open its filled-in form. Change anything before adding it. Done hides the presets; Show presets brings them back."),
      .init(destination: .payday, target: "review-payday", title: "Review and confirm payday", text: "Check the split and earnings before confirming. This button is unavailable when there is nothing approved to pay."),
      .init(destination: .family, target: "add-child", title: "Add Child", text: "Create another profile with its own name, age range, passcode and money split."),
      .init(destination: .family, target: "edit-child", title: "Edit a child", text: "Change this child's details and split without changing a sibling's settings."),
      .init(destination: .family, target: "manage-jars", title: "Manage jars and goals", text: "Open this child's balances, transaction history and savings goals. Parents can record outside purchases and adjustments."),
      .init(destination: .family, target: "child-passcode", title: "Change a child's passcode", text: "Use this control to reset this profile's passcode. Passcodes keep profiles separate on a shared device."),
      .init(destination: .family, target: "remove-child", title: "Remove a child", text: "Removal asks for confirmation and checks unsettled work and balances. Historical records are preserved."),
      .init(destination: .settings, target: "settings-Family & locale", title: "Family and locale", text: "Check your family name, currency, locale and timezone."),
      .init(destination: .settings, target: "schedule-frequency", title: "Payday frequency", text: "Choose Weekly, Every two weeks, Twice monthly, Monthly or Custom. Custom shows Every [number] days."),
      .init(destination: .settings, target: "schedule-date", title: "Next payday date", text: "Choose when the next payday should happen. The repeat interval starts from this scheduled date."),
      .init(destination: .settings, target: "schedule-save", title: "Save your schedule", text: "Apply the date and frequency together. Custom intervals must be a whole number from 1 to 365 days."),
      .init(destination: .settings, target: "settings-Notifications", title: "Notification preferences", text: "Find notification settings here. Email delivery requires a separately configured sending service."),
      .init(destination: .settings, target: "settings-Accessibility", title: "Accessibility", text: "Find walkthrough replay and information about keyboard navigation, reduced motion and VoiceOver."),
      .init(destination: .settings, target: "settings-Privacy & data", title: "Privacy and family data", text: "Export a family backup here. Account deletion and demo reset are separate actions; this tour does not run them.")
    ] : [
      .init(destination: .jars, target: "jar-spend", title: "Spend", text: "This balance is available for parent-approved purchases. Requests do not deduct money until approved."),
      .init(destination: .jars, target: "jar-save", title: "Save", text: "Savings are for your goals. Changing a featured goal does not move money already saved."),
      .init(destination: .jars, target: "jar-give", title: "Give", text: "Set aside money for generosity and gifts."),
      .init(destination: .jars, target: "add-goal", title: "Propose a savings goal", text: "Enter a title, icon, target amount and optional date. Your parent reviews the idea before it becomes active."),
      .init(destination: .jars, target: "featured-goals", title: "Choose a featured goal or remove one", text: "Make featured chooses which approved goal appears on Home and receives future Save allocations. Remove goal archives it after confirmation without taking away savings."),
      .init(destination: .jars, target: "history-search", title: "Search your history", text: "Search transaction descriptions to find a purchase, payday or other entry."),
      .init(destination: .jars, target: "heading-Jar history", title: "Filter and inspect transactions", text: "Use the category buttons to narrow the list. Open an entry for its date, jar, amount and details."),
      .init(destination: .profile, target: "propose-gig", title: "Suggest a gig", text: "Send your grown-up a useful job idea and an optional note. Your grown-up decides whether to add it and what it pays."),
      .init(destination: .profile, target: "heading-How your jars fill up", title: "Your personal split", text: "See the percentages your parent has chosen for Spend, Save and Give."),
      .init(destination: .profile, target: "heading-Keeping you safe", title: "Your privacy", text: "You do not need an email to use a child profile. Proof images stay private to your family.")
    ]
    return [common[0], common[1], common[2], common[9], common[11]]
      + (parent ? [details[4], details[6]] : [details[3], details[4]]) + [
      .init(destination: .settings, target: parent ? "schedule-frequency" : "tour-replay", title: "Your settings", text: parent ? "Set your payday schedule here, including a custom number of days. Save your changes when ready." : "Find your profile controls and walkthrough replay here."),
      .init(destination: .settings, target: "tour-replay", title: "Replay this walkthrough", text: "Take a tour in Settings starts this again whenever you need it. Skip tour leaves your family data unchanged."),
      .init(destination: .settings, target: "lock-profiles", title: "Lock profiles when finished", text: "Use Lock profiles on a shared device. It locks profiles without signing out of the family account.")
    ]
  }
}
struct CrewTourOverlay: View {
  let step: CrewTourStep
  let index: Int
  let count: Int
  let rect: CGRect?
  let back: () -> Void
  let next: () -> Void
  let skip: () -> Void
  @AccessibilityFocusState private var focused: Bool
  @State private var cardSize = CGSize(width: 440, height: 270)
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var highlightRect: CGRect?
  private var movement: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.42) }
  private func position(in size: CGSize) -> CGPoint {
    let w = min(440, size.width - 32), h = cardSize.height, gap: CGFloat = 22
    let r = highlightRect ?? rect ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
    var x = r.midX, y = r.maxY + gap + h / 2
    if r.maxX + gap + w <= size.width - 16 { x = r.maxX + gap + w / 2; y = r.midY }
    else if r.minX - gap - w >= 16 { x = r.minX - gap - w / 2; y = r.midY }
    else if y + h / 2 > size.height - 16 { y = r.minY - gap - h / 2 }
    return CGPoint(x: max(w / 2 + 16, min(size.width - w / 2 - 16, x)),
      y: max(h / 2 + 16, min(size.height - h / 2 - 16, y)))
  }
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomTrailing) {
        Color.black.opacity(0.5).ignoresSafeArea()
        if let rect = highlightRect {
          RoundedRectangle(cornerRadius: 10).fill(.white)
            .frame(width: rect.width + 12, height: rect.height + 12)
            .position(x: rect.midX, y: rect.midY).blendMode(.destinationOut)
        }
      }.compositingGroup().allowsHitTesting(true).animation(movement, value: highlightRect)
      if let rect = highlightRect {
        RoundedRectangle(cornerRadius: 10).stroke(Color.evergreen, lineWidth: 3)
          .frame(width: rect.width + 12, height: rect.height + 12)
          .position(x: rect.midX, y: rect.midY).allowsHitTesting(false)
          .animation(movement, value: highlightRect)
      }
      VStack(alignment: .leading, spacing: 14) {
        Text("INTERACTIVE WALKTHROUGH · \(index + 1) OF \(count)")
          .font(.caption.bold()).foregroundStyle(Color.evergreen)
        Text(step.title).font(.title2.bold()).accessibilityFocused($focused)
        Text(step.text).fixedSize(horizontal: false, vertical: true)
        HStack {
          Button("Skip tour", action: skip).keyboardShortcut(.cancelAction)
          Spacer()
          Button("Back", action: back).disabled(index == 0)
          Button(index == count - 1 ? "Done!" : "Next", action: next)
            .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
        }
      }.padding(24).frame(width: min(440, proxy.size.width - 32))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
        .background(Color.oat, in: RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 20).position(position(in: proxy.size))
        .animation(movement, value: highlightRect)
        .animation(movement, value: cardSize)
        .task(id: index) {
          try? await Task.sleep(for: .milliseconds(150))
          guard !Task.isCancelled else { return }
          NotificationCenter.default.post(name: .crewTourTarget, object: step.target)
        }
        .onAppear { focused = true }.onChange(of: index) { _, _ in focused = true }
    }.onChange(of: rect, initial: true) { _, value in
      if let value { highlightRect = value }
    }.foregroundStyle(Color.ink).preferredColorScheme(.light).accessibilityAddTraits(.isModal)
  }
}
