import AppKit
import SwiftUI

struct FamilyView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @State private var editChild: ChildProfile?
  @State private var moneyChild: ChildProfile?
  @State private var addChild = false
  @State private var invite = false
  @State private var gigProposal: WorkItem?
  @State private var passcodeTarget: ProfileAccessTarget?
  @State private var removeChild: ChildProfile?
  @State private var goalToComplete: SavingsGoal?

  private var proposedGoals: [SavingsGoal] { store.state.goals.filter { $0.status == .proposed } }
  private var proposedGigs: [WorkItem] {
    store.state.workItems.filter { $0.lifecycleStatus == "proposed" }
  }
  var body: some View {
    TourScrollView {
      VStack(alignment: .leading, spacing: 26) {
        HStack(alignment: .bottom) {
          PageHeader(
            eyebrow: "Your household", title: "Family",
            subtitle: "Profiles, jar rules, invitations, and child ideas—all in one place.")
          Spacer()
          if cloud.familyId != nil {
            Button {
              invite = true
            } label: {
              Label("Invite co-parent", systemImage: "envelope.fill")
            }.buttonStyle(SecondaryButtonStyle())
          }
          Button {
            addChild = true
          } label: {
            Label(AppLanguage.text("Add child"), systemImage: "person.badge.plus")
          }.buttonStyle(PrimaryButtonStyle()).walkthroughTarget("add-child")
        }
        SectionHeading(title: "Crew members")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16)], spacing: 16) {
          guardianCard
          ForEach(store.state.children) { child in childCard(child) }
        }
        if !proposedGoals.isEmpty || !proposedGigs.isEmpty {
          SectionHeading(title: "Ideas to review")
          PocketPanel {
            VStack(spacing: 0) {
              ForEach(proposedGoals) { goal in
                HStack {
                  SavingsGoalArt(goal: goal, size: 40)
                  VStack(alignment: .leading) {
                    Text(goal.title).fontWeight(.bold)
                    Text(
                      "Goal idea from \(store.child(goal.childId)?.name ?? "your child") · \(goal.targetCents.currency())"
                    ).font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer()
                  Button(AppLanguage.text("Approve")) {
                    do { try store.approveGoal(goal.id) } catch { store.show(error: error) }
                  }.buttonStyle(SecondaryButtonStyle())
                }.padding(.vertical, 10)
              }
              ForEach(proposedGigs) { gig in
                HStack {
                  Image(systemName: "lightbulb.fill").foregroundStyle(Color.sunny)
                  VStack(alignment: .leading) {
                    Text(gig.title).fontWeight(.bold)
                    Text("Gig idea from \(store.child(gig.createdBy)?.name ?? "your child")").font(
                      .caption
                    ).foregroundStyle(.secondary)
                  }
                  Spacer()
                  Button("Set reward") { gigProposal = gig }.buttonStyle(SecondaryButtonStyle())
                }.padding(.vertical, 10)
              }
            }
          }
        }
        SectionHeading(title: "Complete a savings goal")
        ForEach(store.state.goals.filter { $0.status == .active }) { goal in
          PocketPanel {
            HStack {
              SavingsGoalArt(goal: goal, size: 40)
              VStack(alignment: .leading) {
                Text(goal.title).fontWeight(.bold)
                Text("\(store.child(goal.childId)?.name ?? "Child") · \(goal.targetCents.currency()) from Spend")
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Button(AppLanguage.text("Complete goal")) { goalToComplete = goal }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(store.balance(.spend, childId: goal.childId) < goal.targetCents)
            }
          }
        }
        SectionHeading(title: "Family roles")
        PocketPanel {
          VStack(spacing: 0) {
            ForEach(store.state.members) { member in
              HStack {
                Image(
                  systemName: member.role == .guardian
                    ? "person.badge.key.fill" : "person.crop.circle.fill"
                ).foregroundStyle(member.role == .guardian ? Color.evergreen : Color.sky).frame(
                  width: 32)
                VStack(alignment: .leading) {
                  Text(memberName(member)).fontWeight(.bold)
                  Text(member.role == .guardian ? "Parent / guardian" : "Child profile").font(
                    .caption
                  ).foregroundStyle(.secondary)
                }
                Spacer()
                Text(member.inviteState == "pending" ? "Invite pending" : "Active").font(
                  .caption.weight(.bold)
                ).foregroundStyle(member.inviteState == "pending" ? Color.coral : Color.evergreen)
                  .padding(.horizontal, 10).padding(.vertical, 5).background(
                    (member.inviteState == "pending" ? Color.coral : Color.evergreen).opacity(0.1),
                    in: Capsule())
              }.padding(.vertical, 10)
            }
          }
        }
      }.padding(32).frame(maxWidth: 1150, alignment: .leading)
    }
    .sheet(item: $editChild) { child in
      if let split = store.split(for: child.id) {
        EditChildSheet(child: child, split: split)
      }
    }
    .sheet(item: $moneyChild) { child in
      TransactionSheet(initialCategory: .save).onAppear { store.selectChild(child.id) }
    }
    .sheet(isPresented: $addChild) { AddChildSheet() }
    .sheet(item: $removeChild) { RemoveChildSheet(child: $0) }
    .alert("Complete this goal?", isPresented: Binding(get: { goalToComplete != nil }, set: { if !$0 { goalToComplete = nil } })) {
      Button(AppLanguage.text("Cancel"), role: .cancel) { goalToComplete = nil }
      Button(AppLanguage.text("Confirm completion")) {
        if let goal = goalToComplete {
          do { try store.completeGoal(goal.id) } catch { store.show(error: error) }
        }
        goalToComplete = nil
      }
    } message: {
      Text("Deduct \(goalToComplete?.targetCents.currency() ?? "the target amount") from Spend and move this goal to Wins. This records the reward in PocketCrew; it does not buy anything from a store.")
    }
    .sheet(isPresented: $invite) { InviteSheet() }
    .sheet(item: $gigProposal) { GigProposalApprovalSheet(gig: $0) }
    .sheet(item: $passcodeTarget) { ChangePasscodeSheet(target: $0) }
  }
  private var guardianCard: some View {
    PocketPanel {
      HStack(spacing: 13) {
        ZStack {
          Circle().fill(Color.evergreen)
          Text(String(store.guardianDisplayName.prefix(1))).font(
            .title2.weight(.black)
          ).foregroundStyle(.white)
        }.frame(width: 52, height: 52)
        VStack(alignment: .leading) {
          Text(store.guardianDisplayName).font(.title3.weight(.black))
          Text("Current parent / guardian").foregroundStyle(.secondary)
        }
        Spacer()
        Button("Change passcode") { passcodeTarget = .parent }.buttonStyle(SecondaryButtonStyle())
        Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.evergreen)
      }
    }
  }
  private func childCard(_ child: ChildProfile) -> some View {
    PocketPanel {
      VStack(alignment: .leading, spacing: 15) {
        HStack {
          AvatarView(child: child, size: 52)
          VStack(alignment: .leading) {
            Text(child.name).font(.title3.weight(.black))
            Text("Age \(child.ageRange) · Child").foregroundStyle(.secondary)
          }
          Spacer()
          Text(store.pending(childId: child.id).currency()).font(.headline.weight(.black))
            .foregroundStyle(Color.evergreen)
        }
        if let split = store.split(for: child.id) {
          HStack {
            Text("Spend \(split.spendPercent)%")
            Spacer()
            Text("Save \(split.savePercent)%")
            Spacer()
            Text("Give \(split.givePercent)%")
          }.font(.caption.weight(.bold)).foregroundStyle(.secondary)
        }
        HStack {
          Button(AppLanguage.text("Edit child")) { editChild = child }.buttonStyle(SecondaryButtonStyle()).walkthroughTarget("edit-child-" + child.id.uuidString)
          Button("Manage jars") { moneyChild = child }.buttonStyle(SecondaryButtonStyle()).walkthroughTarget("manage-jars-" + child.id.uuidString)
          Button("Change passcode") { passcodeTarget = .child(child.id) }.buttonStyle(
            SecondaryButtonStyle()).walkthroughTarget("child-passcode-" + child.id.uuidString)
          Spacer()
        }
        Button(AppLanguage.text("Remove child"), role: .destructive) { removeChild = child }.walkthroughTarget("remove-child-" + child.id.uuidString)
      }
    }
  }
  private func memberName(_ member: FamilyMember) -> String {
    if let childId = member.childId { return store.child(childId)?.name ?? "Child" }
    if let userId = member.userId {
      return store.state.users.first(where: { $0.id == userId })?.displayName ?? "Guardian"
    }
    return "Member"
  }
}

struct RemoveChildSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let child: ChildProfile
  @State private var passcode = ""
  @State private var message = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Remove \(child.name)?").font(.title2.bold())
      Text("This removes their profile from your family. Historical records are preserved in your family backup. Settle their balances, pending earnings, open work and cart first. At least one child must remain.")
      SecureField(AppLanguage.text("Parent passcode"), text: $passcode)
      if !message.isEmpty { Text(message).foregroundStyle(.red) }
      HStack {
        Button(AppLanguage.text("Cancel")) { dismiss() }
        Spacer()
        Button(AppLanguage.text("Remove child"), role: .destructive) {
          do { try store.removeChild(child.id, parentPasscode: passcode); dismiss() }
          catch { message = error.localizedDescription }
        }.disabled(passcode.isEmpty)
      }
    }.padding(28).frame(width: 440)
  }
}

struct ChangePasscodeSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let target: ProfileAccessTarget
  @State private var currentParentPasscode = ""
  @State private var newPasscode = ""
  @State private var confirmation = ""
  @State private var error = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: "key.fill").font(.system(size: 38)).foregroundStyle(Color.evergreen)
      Text("Change \(targetName)’s passcode").font(.largeTitle.weight(.black)).fontDesign(.rounded)
      Text("Use a code that other children in the household won’t guess.").foregroundStyle(
        .secondary)
      SecureField("Current parent passcode", text: $currentParentPasscode).textFieldStyle(
        .roundedBorder)
      SecureField("New four-digit passcode", text: $newPasscode).textFieldStyle(.roundedBorder)
        .onChange(of: newPasscode) { _, value in
          newPasscode = String(value.filter(\.isNumber).prefix(4))
        }
      SecureField("Confirm new passcode", text: $confirmation).textFieldStyle(.roundedBorder)
        .onChange(of: confirmation) { _, value in
          confirmation = String(value.filter(\.isNumber).prefix(4))
        }
      if !error.isEmpty {
        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
      }
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button("Update passcode") { save() }.buttonStyle(PrimaryButtonStyle()).disabled(
          !newPasscode.isFourDigitPasscode || newPasscode != confirmation)
      }
    }.padding(28).frame(width: 540, height: 470).background(Color.oat)
  }

  private var targetName: String {
    switch target {
    case .parent: return store.guardianDisplayName
    case .child(let childId): return store.child(childId)?.name ?? "Child"
    }
  }

  private func save() {
    guard newPasscode == confirmation else {
      error = "The new passcodes don’t match."
      return
    }
    do {
      try store.updatePasscode(
        target: target, currentParentPasscode: currentParentPasscode, newPasscode: newPasscode)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct SplitEditorSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let child: ChildProfile
  @State private var spend = 0.0
  @State private var save = 0.0
  @State private var give = 0.0
  @State private var error = ""
  private var total: Int { Int(spend + save + give) }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        AvatarView(child: child, size: 56)
        VStack(alignment: .leading) {
          Text("\(child.name)’s jar split").font(.largeTitle.weight(.black)).fontDesign(.rounded)
          Text("Payday cents are rounded deterministically; any remainder goes to Spend.")
            .foregroundStyle(.secondary)
        }
      }
      VStack(spacing: 16) {
        splitRow(.spend, $spend)
        splitRow(.save, $save)
        splitRow(.give, $give)
      }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
      HStack {
        Text("Total").font(.headline)
        Spacer()
        Text("\(total)%").font(.title2.weight(.black)).foregroundStyle(
          total == 100 ? Color.evergreen : Color.coral)
      }
      if total != 100 {
        Label(
          "Adjust the split until Spend + Save + Give equals 100%.",
          systemImage: "exclamationmark.circle.fill"
        ).foregroundStyle(Color.coral)
      }
      if !error.isEmpty { Text(error).foregroundStyle(Color.coral) }
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button("Save split") {
          do {
            try store.updateSplit(
              childId: child.id, spend: Int(spend), save: Int(save), give: Int(give))
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(PrimaryButtonStyle()).disabled(total != 100)
      }
    }.padding(28).frame(width: 610, height: 510).background(Color.oat).onAppear {
      if let rule = store.split(for: child.id) {
        spend = Double(rule.spendPercent)
        save = Double(rule.savePercent)
        give = Double(rule.givePercent)
      }
    }
  }
  private func splitRow(_ kind: JarKind, _ value: Binding<Double>) -> some View {
    HStack(spacing: 12) {
      JarIcon(kind: kind, size: 38)
      Text(kind.title).fontWeight(.bold).frame(width: 55, alignment: .leading)
      Slider(value: value, in: 0...100, step: 1)
      TextField("Percent", value: value, format: .number.precision(.fractionLength(0)))
        .textFieldStyle(.roundedBorder).frame(width: 65)
      Text("%")
    }
  }
}

struct InviteSheet: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var email = ""
  @State private var error = ""
  @State private var working = false
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: "envelope.badge.fill").font(.system(size: 38)).foregroundStyle(
        Color.evergreen)
      Text("Invite a co-parent").font(.largeTitle.weight(.black)).fontDesign(.rounded)
      Text(
        "PocketCrew will email a one-time, expiring invitation. The recipient signs in with this email before joining your family."
      ).foregroundStyle(.secondary)
      TextField("Display name", text: $name).textFieldStyle(.roundedBorder)
      TextField(AppLanguage.text("Email"), text: $email).textFieldStyle(.roundedBorder)
      if !error.isEmpty { Text(error).foregroundStyle(Color.coral) }
      Spacer()
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button("Send invitation") { send() }.buttonStyle(PrimaryButtonStyle()).disabled(
          !email.contains("@") || working || cloud.familyId == nil)
      }
    }.padding(28).frame(width: 520, height: 430).background(Color.oat)
  }

  private func send() {
    working = true
    error = ""
    Task {
      do {
        try await cloud.inviteGuardian(email: email)
        try store.inviteCoParent(name: name, email: email)
        dismiss()
      } catch { self.error = error.localizedDescription }
      working = false
    }
  }
}

struct GigProposalApprovalSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let gig: WorkItem
  @State private var reward = ""
  @State private var due = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Set up this gig").font(.largeTitle.weight(.black)).fontDesign(.rounded)
      Text(gig.title).font(.title2.weight(.bold))
      if !gig.instructions.isEmpty { Text(gig.instructions).foregroundStyle(.secondary) }
      Form {
        TextField("Agreed reward", text: $reward)
        DatePicker("Due", selection: $due)
      }.formStyle(.grouped)
      if !error.isEmpty { Text(error).foregroundStyle(Color.coral) }
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button("Approve & assign") {
          let cents = Int(((Double(reward) ?? 0) * 100).rounded())
          do {
            try store.approveGigProposal(gig.id, reward: cents, dueAt: due)
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(PrimaryButtonStyle())
      }
    }.padding(28).frame(width: 520, height: 430).background(Color.oat)
  }
}

struct SettingsView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @Binding var didEnter: Bool
  @State private var frequency: PaydayFrequency = .weekly
  @State private var customDays = "7"
  @State private var payday = Date()
  @State private var reminders = true
  @State private var approvals = true
  @State private var weeklySummary = true
  @State private var deleteSheet = false
  @State private var deleteCloudSheet = false
  @State private var replaceWithCloudConfirmation = false
  @State private var error = ""
  var body: some View {
    TourScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PageHeader(
          eyebrow: "Family controls", title: "Settings",
          subtitle: "Schedules, privacy, accessibility, and your family data.")
        LanguagePicker()
        settingsSection("Family & locale", icon: "globe.americas.fill") {
          LabeledContent("Family name", value: store.state.family.name)
          LabeledContent("Currency", value: "USD — US Dollar")
          LabeledContent("Locale", value: store.state.family.locale)
          LabeledContent("Timezone", value: store.state.family.timezone)
        }
        if let user = cloud.signedInUser {
          settingsSection("Cloud account", icon: "person.crop.circle.badge.checkmark") {
            LabeledContent("Signed in", value: user.email)
            CloudSyncBadge()
            HStack {
              Button("Reload family") {
                if cloud.hasUnsyncedChanges {
                  replaceWithCloudConfirmation = true
                } else {
                  Task { await cloud.reloadFamily() }
                }
              }.buttonStyle(SecondaryButtonStyle())
              Spacer()
              Button(AppLanguage.text("Sign Out"), role: .destructive) { Task { await cloud.signOut() } }.foregroundStyle(.red)
            }
          }
        } else if cloud.usingDemo && cloud.isConfigured {
          settingsSection("Real family account", icon: "person.crop.circle.badge.plus") {
            Text("Ready to move beyond the demo? Sign in or create a private family account.")
              .foregroundStyle(.secondary)
            Button("Sign in to a real family") {
              store.lock()
              cloud.leaveDemo()
              didEnter = false
            }.buttonStyle(PrimaryButtonStyle())
          }
        }
        settingsSection("Payday schedule", icon: "calendar.badge.clock") {
          Picker("Frequency", selection: $frequency) {
            ForEach(PaydayFrequency.allCases) { Text($0.title).tag($0) }
          }.walkthroughTarget("schedule-frequency")
          if frequency == .custom {
            HStack {
              Text("Every")
              TextField("Days", text: $customDays).textFieldStyle(.roundedBorder).frame(width: 70)
                .accessibilityLabel("Number of days between paydays")
              Text("days")
            }
            Text("Enter a whole number from 1 to 365.").font(.caption).foregroundStyle(.secondary)
          }
          DatePicker("Next payday", selection: $payday).walkthroughTarget("schedule-date")
          HStack {
            Spacer()
            Button("Save schedule") {
              do { try store.updateSchedule(frequency: frequency, date: payday, customDays: Int(customDays)) } catch {
                store.show(error: error)
              }
            }.buttonStyle(PrimaryButtonStyle()).walkthroughTarget("schedule-save")
          }
        }
        settingsSection("What’s new", icon: "bell.badge.fill") {
          Toggle("Work submitted for review", isOn: $approvals)
          Toggle("Payday reminders", isOn: $reminders)
          Toggle("Weekly family summary", isOn: $weeklySummary)
        }
        settingsSection("Accessibility", icon: "accessibility.fill") {
          Button(AppLanguage.text("Take a tour")) {
            NotificationCenter.default.post(name: .replayCrewWalkthrough, object: nil)
          }.buttonStyle(SecondaryButtonStyle()).walkthroughTarget("tour-replay")
          LabeledContent("Reduced motion", value: "Follows macOS setting")
          LabeledContent("Keyboard navigation", value: "Supported")
          Text(
            "PocketCrew pairs every color with a label or icon and uses native VoiceOver semantics."
          ).font(.caption).foregroundStyle(.secondary)
        }
        settingsSection("Privacy & data", icon: "lock.shield.fill") {
          Text(
            cloud.signedInUser == nil
              ? "Proof images stay on this device in demo mode. Financial records are append-only, and sensitive actions require the parent PIN."
              : "Proof images use private family storage and short-lived previews. Financial records are append-only, and sensitive actions require the parent PIN."
          ).foregroundStyle(.secondary)
          HStack {
            Button {
              exportData()
            } label: {
              Label("Export family data", systemImage: "square.and.arrow.up")
            }.buttonStyle(SecondaryButtonStyle())
            if cloud.signedInUser == nil {
              Button("Reset demo") {
                do { try store.resetDemo() } catch { store.show(error: error) }
              }.buttonStyle(SecondaryButtonStyle())
            }
            Spacer()
            if cloud.signedInUser == nil {
              Button("Delete family data", role: .destructive) { deleteSheet = true }
            } else {
              Button("Delete cloud account", role: .destructive) { deleteCloudSheet = true }
            }
          }
        }
        Text(
          "PocketCrew is a financial-learning ledger, not a bank. Funds are not held, insured, or transferred by this app."
        ).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 8)
      }.padding(32).frame(maxWidth: 950, alignment: .leading)
    }.onAppear {
      frequency = store.state.schedule.frequency
      customDays = String(store.state.schedule.customDays ?? 7)
      payday = store.state.schedule.nextPaydayAt
    }.sheet(isPresented: $deleteSheet) { DeleteDataSheet { didEnter = false } }
      .sheet(isPresented: $deleteCloudSheet) { CloudAccountDeletionView() }
      .confirmationDialog(
        "Replace this device’s unsaved changes?", isPresented: $replaceWithCloudConfirmation,
        titleVisibility: .visible
      ) {
        Button("Replace with cloud copy", role: .destructive) {
          Task { await cloud.discardLocalChangesAndReload() }
        }
        Button("Keep local changes", role: .cancel) {}
      } message: {
        Text("Use this only when retrying sync does not work. The latest saved family copy wins.")
      }
  }
  private func settingsSection<Content: View>(
    _ title: String, icon: String, @ViewBuilder content: () -> Content
  ) -> some View {
    PocketPanel {
      VStack(alignment: .leading, spacing: 16) {
        Label(title, systemImage: icon).font(.title2.weight(.black)).fontDesign(.rounded)
          .foregroundStyle(Color.ink).walkthroughTarget("settings-" + title)
        Divider()
        content()
      }
    }
  }
  private func exportData() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      "PocketCrew-\(store.state.family.name.replacingOccurrences(of: " ", with: "-"))-export.json"
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let url = panel.url {
      do {
        try LocalJSONRepository.encoder.encode(store.state).write(to: url, options: .atomic)
        store.toast = ToastMessage(text: "Family data exported", isError: false)
      } catch { store.show(error: error) }
    }
  }
}

struct ChildSettingsView: View {
  @EnvironmentObject private var store: AppStore
  var body: some View {
    TourScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PageHeader(eyebrow: "Your preferences", title: "Settings", subtitle: "Learn your way around PocketCrew.")
        LanguagePicker()
        PocketPanel {
          VStack(alignment: .leading, spacing: 14) {
            Text(AppLanguage.text("Learn PocketCrew")).font(.title2.bold())
            Button(AppLanguage.text("Take a tour")) {
              NotificationCenter.default.post(name: .replayCrewWalkthrough, object: nil)
            }.buttonStyle(SecondaryButtonStyle()).walkthroughTarget("tour-replay")
            Text("Replay the interactive walkthrough whenever you like.")
          }
        }
        Button(AppLanguage.text("Lock profiles")) { store.lock() }.buttonStyle(SecondaryButtonStyle())
      }.padding(32)
    }
  }
}

struct DeleteDataSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let completed: () -> Void
  @State private var phrase = ""
  @State private var pin = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: "trash.circle.fill").font(.system(size: 40)).foregroundStyle(Color.coral)
      Text("Delete family data?").font(.largeTitle.weight(.black)).fontDesign(.rounded)
      Text(
        "This removes the on-device family ledger. Export first if you want a copy. Type DELETE and enter the parent PIN."
      ).foregroundStyle(.secondary)
      TextField("Type DELETE", text: $phrase).textFieldStyle(.roundedBorder)
      SecureField(AppLanguage.text("Parent passcode"), text: $pin).textFieldStyle(.roundedBorder)
      if !error.isEmpty { Text(error).foregroundStyle(Color.coral) }
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button("Delete data", role: .destructive) {
          if !store.verifyParentPasscode(pin) {
            error = "The parent passcode didn’t match."
          } else {
            do {
              try store.deleteLocalData()
              dismiss()
              completed()
            } catch { self.error = error.localizedDescription }
          }
        }.disabled(phrase != "DELETE")
      }
    }.padding(28).frame(width: 520, height: 430).background(Color.oat)
  }
}
