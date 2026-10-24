import SwiftUI

struct MobileFamilyView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @State private var editingChild: ChildProfile?
  @State private var passcodeTarget: ProfileAccessTarget?
  @State private var inviting = false
  @State private var addingChild = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text("Family").font(.largeTitle.bold()).fontDesign(.rounded)
          Spacer()
          if cloud.familyId != nil {
            Button {
              inviting = true
            } label: {
              Image(systemName: "envelope.badge.fill")
            }
            .buttonStyle(.bordered).accessibilityLabel("Invite co-parent")
          }
        }
        Button {
          addingChild = true
        } label: {
          Label("Add Child", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent)
        MobileCard {
          HStack {
            Image(systemName: "person.badge.key.fill").font(.title).foregroundStyle(Color.evergreen)
            VStack(alignment: .leading) {
              Text(store.guardianDisplayName).font(.headline)
              Text("Parent / guardian").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("PIN") { passcodeTarget = .parent }.buttonStyle(.bordered)
          }
        }
        ForEach(store.state.children) { child in
          MobileCard {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                AvatarView(child: child)
                VStack(alignment: .leading) {
                  Text(child.name).font(.headline)
                  Text("Age \(child.ageRange)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.pending(childId: child.id).currency()).bold().foregroundStyle(
                  Color.evergreen)
              }
              if let split = store.split(for: child.id) {
                Text(
                  "Spend \(split.spendPercent)% · Save \(split.savePercent)% · Give \(split.givePercent)%"
                ).font(.caption.bold())
              }
              HStack {
                Button("Edit child") { editingChild = child }.buttonStyle(.bordered)
                Button("Change PIN") { passcodeTarget = .child(child.id) }.buttonStyle(.bordered)
              }
            }
          }
        }
      }.padding(16)
    }.background(Color.oat).sheet(isPresented: $addingChild) { MobileAddChildSheet() }.sheet(
      item: $editingChild
    ) { child in
      if let split = store.split(for: child.id) {
        MobileEditChildSheet(child: child, split: split)
      }
    }.sheet(item: $passcodeTarget) { MobileChangePasscode(target: $0) }.sheet(
      isPresented: $inviting
    ) { MobileInviteSheet() }
  }
}

struct MobileAddChildSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var child = ChildSetupDraft.blank()
  @State private var error = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Each child has a separate passcode, avatar, and payday split.")
            .foregroundStyle(.secondary)
          ChildSettingsEditor(child: $child, title: "New child")
          if !error.isEmpty {
            Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
          }
        }.padding(16)
      }.background(Color.oat).navigationTitle("Add Child").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") { save() }.disabled(!child.isComplete)
        }
      }
    }
  }

  private func save() {
    do {
      try store.addChild(child)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct MobileEditChildSheet: View {
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
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("These changes affect only this child and preserve their balances and history.")
            .foregroundStyle(.secondary)
          ChildSettingsEditor(child: $draft, title: draft.name, showsPasscode: false)
          if !error.isEmpty {
            Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
          }
        }.padding(16)
      }.background(Color.oat).navigationTitle("Edit child").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }.disabled(!isValid)
        }
      }
    }
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

struct MobileInviteSheet: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var email = ""
  @State private var error = ""
  @State private var working = false
  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Display name", text: $name)
          TextField("Email", text: $email).pocketCrewEmailInput()
        } footer: {
          Text("The invitation expires and only the invited email address can accept it.")
        }
        if !error.isEmpty { Text(error).foregroundStyle(.red) }
        if working { ProgressView("Sending…") }
      }.navigationTitle("Invite co-parent").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Send") { send() }.disabled(!email.contains("@") || working)
        }
      }
    }
  }
  private func send() {
    working = true
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

struct MobileSplitEditor: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let child: ChildProfile
  @State private var spend = 50.0
  @State private var save = 40.0
  @State private var give = 10.0
  @State private var error = ""
  var total: Int { Int(spend + save + give) }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          slider("Spend", $spend)
          slider("Save", $save)
          slider("Give", $give)
        }
        Section {
          LabeledContent("Total", value: "\(total)%")
          if total != 100 { Text("The split must total 100%.").foregroundStyle(.red) }
        }
        if !error.isEmpty { Text(error).foregroundStyle(.red) }
      }.navigationTitle("\(child.name)’s split").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            do {
              try store.updateSplit(
                childId: child.id, spend: Int(spend), save: Int(save), give: Int(give))
              dismiss()
            } catch { self.error = error.localizedDescription }
          }.disabled(total != 100)
        }
      }.onAppear {
        if let rule = store.split(for: child.id) {
          spend = Double(rule.spendPercent)
          save = Double(rule.savePercent)
          give = Double(rule.givePercent)
        }
      }
    }
  }
  private func slider(_ name: String, _ value: Binding<Double>) -> some View {
    VStack(alignment: .leading) {
      HStack {
        Text(name)
        Spacer()
        Text("\(Int(value.wrappedValue))%")
      }
      Slider(value: value, in: 0...100, step: 1)
    }
  }
}

struct MobileChangePasscode: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let target: ProfileAccessTarget
  @State private var current = ""
  @State private var new = ""
  @State private var confirm = ""
  @State private var error = ""
  var body: some View {
    NavigationStack {
      Form {
        SecureField("Current parent passcode", text: $current).pocketCrewNumericKeyboard()
        SecureField("New four-digit passcode", text: $new).pocketCrewNumericKeyboard().onChange(
          of: new
        ) { _, value in new = String(value.filter(\.isNumber).prefix(4)) }
        SecureField("Confirm passcode", text: $confirm).pocketCrewNumericKeyboard().onChange(
          of: confirm
        ) { _, value in confirm = String(value.filter(\.isNumber).prefix(4)) }
        if !error.isEmpty { Text(error).foregroundStyle(.red) }
      }.navigationTitle("Change passcode").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }.disabled(!new.isFourDigitPasscode || new != confirm)
        }
      }
    }
  }
  private func save() {
    do {
      try store.updatePasscode(target: target, currentParentPasscode: current, newPasscode: new)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct MobileSettingsView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @AppStorage("pocketcrew.didEnter") private var didEnter = true
  @State private var frequency: PaydayFrequency = .weekly
  @State private var date = Date()
  @State private var deleteCloudSheet = false
  @State private var replaceWithCloudConfirmation = false
  var body: some View {
    Form {
      if let user = cloud.signedInUser {
        Section("Cloud account") {
          LabeledContent("Signed in", value: user.email)
          CloudSyncBadge()
          Button("Reload family") {
            if cloud.hasUnsyncedChanges {
              replaceWithCloudConfirmation = true
            } else {
              Task { await cloud.reloadFamily() }
            }
          }
          Button("Sign out", role: .destructive) { Task { await cloud.signOut() } }
          Button("Delete cloud account", role: .destructive) { deleteCloudSheet = true }
        }
      } else if cloud.usingDemo && cloud.isConfigured {
        Section("Real family account") {
          Text("Sign in or create a private family when you’re ready to leave the demo.")
          Button("Sign in to a real family") {
            store.lock()
            cloud.leaveDemo()
            didEnter = false
          }
        }
      }
      Section("Payday schedule") {
        Picker("Frequency", selection: $frequency) {
          ForEach(PaydayFrequency.allCases) { Text($0.title).tag($0) }
        }
        DatePicker("Next payday", selection: $date, displayedComponents: .date)
        Button("Save schedule") {
          do { try store.updateSchedule(frequency: frequency, date: date) } catch {
            store.show(error: error)
          }
        }
      }
      Section("Privacy") {
        Label(
          cloud.signedInUser == nil ? "Local proof images" : "Private family proof storage",
          systemImage: "photo.badge.shield.checkmark.fill")
        Label("Append-only financial history", systemImage: "lock.doc.fill")
        Text("PocketCrew does not hold, insure, or transfer funds.").font(.caption).foregroundStyle(
          .secondary)
      }
      if cloud.signedInUser == nil {
        Section("Demo") {
          Button("Reset Parker family", role: .destructive) {
            do { try store.resetDemo() } catch { store.show(error: error) }
          }
        }
      }
    }.navigationTitle("Settings").onAppear {
      frequency = store.state.schedule.frequency
      date = store.state.schedule.nextPaydayAt
    }.sheet(isPresented: $deleteCloudSheet) { CloudAccountDeletionView() }
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
}
