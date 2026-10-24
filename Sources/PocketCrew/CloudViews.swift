import SwiftUI

enum CloudAuthMode: String, Identifiable {
  case signIn
  case signUp
  var id: String { rawValue }
}

struct CloudAuthView: View {
  @EnvironmentObject private var cloud: CloudSessionStore
  @Environment(\.dismiss) private var dismiss
  let initialMode: CloudAuthMode
  @State private var mode: CloudAuthMode
  @State private var displayName = ""
  @State private var email = ""
  @State private var password = ""

  init(initialMode: CloudAuthMode) {
    self.initialMode = initialMode
    _mode = State(initialValue: initialMode)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(mode == .signIn ? "Welcome back" : "Create your guardian account")
              .font(.largeTitle.weight(.black)).fontDesign(.rounded)
            Text("Your email identifies you—not your children.").foregroundStyle(.secondary)
          }
          Spacer()
          Button(AppLanguage.text("Close")) { dismiss() }.buttonStyle(.plain)
        }
        Picker("Account action", selection: $mode) {
          Text(AppLanguage.text("Sign in")).tag(CloudAuthMode.signIn)
          Text("Create account").tag(CloudAuthMode.signUp)
        }.pickerStyle(.segmented)
        if !cloud.isConfigured {
          Label(
            "Cloud sign-in is not configured in this build. Add the Supabase URL and publishable key, or keep using the demo.",
            systemImage: "wrench.and.screwdriver.fill"
          ).font(.callout).foregroundStyle(Color.ink).padding(14).background(
            Color.sunny.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        }
        VStack(spacing: 12) {
          if mode == .signUp {
            TextField("Your display name", text: $displayName).textFieldStyle(.roundedBorder)
          }
          TextField(AppLanguage.text("Email"), text: $email).textFieldStyle(.roundedBorder)
          SecureField(AppLanguage.text("Password"), text: $password).textFieldStyle(.roundedBorder)
          if mode == .signUp {
            Text("Use at least 8 characters.").font(.caption).foregroundStyle(.secondary).frame(
              maxWidth: .infinity, alignment: .leading)
          }
        }
        if let notice = cloud.notice {
          Text(notice).font(.callout).foregroundStyle(Color.coral).frame(
            maxWidth: .infinity, alignment: .leading)
        }
        Button(mode == .signIn ? "Sign in with email" : "Create account") {
          Task {
            if mode == .signIn {
              await cloud.signIn(email: email, password: password)
            } else {
              await cloud.signUp(displayName: displayName, email: email, password: password)
            }
          }
        }.buttonStyle(PrimaryButtonStyle()).disabled(!emailIsValid || !passwordIsValid || isWorking)
          .frame(maxWidth: .infinity)
        HStack {
          Rectangle().fill(.black.opacity(0.1)).frame(height: 1)
          Text("OR").font(.caption.bold()).foregroundStyle(.secondary)
          Rectangle().fill(.black.opacity(0.1)).frame(height: 1)
        }
        Button {
          Task { await cloud.signInWithGoogle() }
        } label: {
          HStack {
            Text("G").font(.headline.weight(.black)).foregroundStyle(Color(hex: "4285F4"))
              .frame(width: 28, height: 28).background(.white, in: Circle())
            Text(AppLanguage.text("Continue with Google"))
          }.frame(maxWidth: .infinity)
        }.buttonStyle(SecondaryButtonStyle()).disabled(!cloud.isConfigured || isWorking)
        if mode == .signIn {
          Button("Forgot password?") {
            Task { await cloud.sendPasswordReset(email: email) }
          }.buttonStyle(.plain).font(.callout.weight(.bold)).foregroundStyle(Color.evergreen)
            .disabled(!emailIsValid || isWorking)
        }
        if isWorking { ProgressView("Connecting securely…") }
        #if os(macOS)
        Text("This Mac remembers your sign-in until you choose Sign Out, without using Keychain. Sign-in tokens are stored unencrypted in a file restricted to your Mac user account. Profile passcodes still protect the app’s views; use your Mac screen lock too.")
          .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        #endif
        Text(
          "Authentication is handled by Supabase. PocketCrew never receives your Google password."
        ).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      }.padding(28).frame(maxWidth: 520)
    }.background(Color.oat).onChange(of: cloud.authPhase) { _, phase in
      if case .signedIn = phase { dismiss() }
    }
  }

  private var emailIsValid: Bool { email.contains("@") && email.contains(".") }
  private var passwordIsValid: Bool {
    password.count >= 8
      && (mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty)
  }
  private var isWorking: Bool { cloud.authPhase == .working }
}

struct CloudFamilySetupView: View {
  @EnvironmentObject private var cloud: CloudSessionStore
  @EnvironmentObject private var store: AppStore
  @State private var mode = 0
  @State private var familyName = "Our Family"
  @State private var parentName = ""
  @State private var parentPasscode = ""
  @State private var children = [ChildSetupDraft.blank()]
  @State private var currency = "USD"
  @State private var frequency: PaydayFrequency = .weekly
  @State private var inviteToken = ""
  @State private var error = ""
  @State private var working = false

  var body: some View {
    ZStack {
      Color.oat.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header
          Picker("Family setup", selection: $mode) {
            Text(AppLanguage.text("Create a family")).tag(0)
            Text("Join with invite").tag(1)
          }.pickerStyle(.segmented)
          if mode == 0 { createForm } else { joinForm }
          if !error.isEmpty {
            Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
          } else if let notice = cloud.notice {
            Label(notice, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
          }
          if working { ProgressView("Securing your family…") }
        }.padding(28).frame(maxWidth: 760)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Your real family space").font(.largeTitle.weight(.black)).fontDesign(.rounded)
        Text("Signed in as \(cloud.signedInUser?.email ?? "guardian")")
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(AppLanguage.text("Sign Out"), role: .destructive) { Task { await cloud.signOut() } }.buttonStyle(.plain).foregroundStyle(
        Color.red)
    }
  }

  private var createForm: some View {
    PocketPanel {
      VStack(alignment: .leading, spacing: 14) {
        Text("Start a household").font(.title2.weight(.black))
        TextField(AppLanguage.text("Family name"), text: $familyName).textFieldStyle(.roundedBorder)
        TextField("Your display name", text: $parentName).textFieldStyle(.roundedBorder)
        SecureField("Parent profile passcode", text: $parentPasscode).textFieldStyle(.roundedBorder)
          .onChange(of: parentPasscode) { _, value in
            parentPasscode = String(value.filter(\.isNumber).prefix(4))
          }
        HStack {
          Picker("Currency", selection: $currency) {
            ForEach(["USD", "CAD", "GBP", "EUR"], id: \.self) { Text($0) }
          }
          Picker("Payday", selection: $frequency) {
            ForEach(PaydayFrequency.allCases.filter { $0 != .custom }) { Text($0.title).tag($0) }
          }
        }
        Divider()
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Children").font(.headline)
            Text("Each child gets independent profile, passcode, avatar, and jar settings.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            children.append(.blank(position: children.count))
          } label: {
            Label(AppLanguage.text("Add Child"), systemImage: "person.badge.plus")
          }.buttonStyle(SecondaryButtonStyle())
        }
        ForEach($children) { $child in
          ChildSettingsEditor(
            child: $child, title: childTitle(child), canRemove: children.count > 1,
            onRemove: { removeChild(child.id) })
        }
        if !passcodesAreUnique {
          Label(
            "The parent and every child must use different passcodes.",
            systemImage: "exclamationmark.shield.fill"
          ).font(.caption).foregroundStyle(Color.coral)
        }
        HStack {
          Button {
            children.append(.blank(position: children.count))
          } label: {
            Label(AppLanguage.text("Add Child"), systemImage: "person.badge.plus")
          }.buttonStyle(SecondaryButtonStyle())
          Spacer()
          Button("Create secure family") { createFamily() }.buttonStyle(PrimaryButtonStyle())
            .disabled(!createIsValid || working)
        }
      }
    }
  }

  private var joinForm: some View {
    PocketPanel {
      VStack(alignment: .leading, spacing: 14) {
        Text("Join a co-parent’s family").font(.title2.weight(.black))
        Text(
          "Open the invitation link from your email, or paste its one-time token here. You must sign in with the invited email address."
        ).foregroundStyle(.secondary)
        TextField("Invitation token", text: $inviteToken).textFieldStyle(.roundedBorder)
        Button("Accept invitation") { acceptInvite() }.buttonStyle(PrimaryButtonStyle()).disabled(
          inviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
      }
    }
  }

  private var createIsValid: Bool {
    !familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !parentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && parentPasscode.isFourDigitPasscode && !children.isEmpty
      && children.allSatisfy(\.isComplete) && passcodesAreUnique
  }
  private var passcodesAreUnique: Bool {
    let values = [parentPasscode] + children.map(\.passcode)
    return Set(values.filter({ !$0.isEmpty })).count == values.filter({ !$0.isEmpty }).count
  }
  private func childTitle(_ child: ChildSetupDraft) -> String {
    let name = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      let position = (children.firstIndex(where: { $0.id == child.id }) ?? 0) + 1
      return position == 1 ? "First child" : "Child \(position)"
    }
    return name
  }
  private func removeChild(_ id: UUID) {
    guard children.count > 1 else { return }
    children.removeAll(where: { $0.id == id })
  }
  private func createFamily() {
    working = true
    error = ""
    do {
      try store.createFamily(
        familyName: familyName, parentName: parentName, children: children, currency: currency,
        frequency: frequency, parentPasscode: parentPasscode)
      Task {
        do { try await cloud.createFamily(using: store.state) } catch {
          self.error = error.localizedDescription
        }
        working = false
      }
    } catch {
      self.error = error.localizedDescription
      working = false
    }
  }
  private func acceptInvite() {
    working = true
    error = ""
    Task {
      do {
        try await cloud.acceptInvite(token: inviteToken.trimmingCharacters(in: .whitespaces))
      } catch { self.error = error.localizedDescription }
      working = false
    }
  }
}

struct PasswordUpdateView: View {
  @EnvironmentObject private var cloud: CloudSessionStore
  @State private var password = ""
  @State private var confirmation = ""
  @State private var working = false

  var body: some View {
    ZStack {
      Color.oat.ignoresSafeArea()
      PocketPanel {
        VStack(alignment: .leading, spacing: 16) {
          Image(systemName: "key.fill").font(.system(size: 42)).foregroundStyle(Color.evergreen)
          Text("Choose a new password").font(.largeTitle.weight(.black)).fontDesign(.rounded)
          Text("Finish the recovery link by setting a new guardian account password.")
            .foregroundStyle(.secondary)
          SecureField("New password", text: $password).textFieldStyle(.roundedBorder)
          SecureField("Confirm new password", text: $confirmation).textFieldStyle(.roundedBorder)
          if let notice = cloud.notice {
            Text(notice).font(.callout).foregroundStyle(Color.coral)
          }
          Button("Update password") {
            working = true
            Task {
              _ = await cloud.updateRecoveredPassword(password)
              working = false
            }
          }.buttonStyle(PrimaryButtonStyle()).disabled(
            password.count < 8 || password != confirmation || working)
          if working { ProgressView("Updating securely…") }
          Button("Cancel and sign out", role: .destructive) { Task { await cloud.signOut() } }
        }.frame(maxWidth: 480)
      }.padding(28)
    }
  }
}

struct DevicePasscodeSetupView: View {
  @EnvironmentObject private var store: AppStore
  @State private var parentCode = ""
  @State private var childCodes: [UUID: String] = [:]
  @State private var error = ""

  var body: some View {
    ZStack {
      Color.oat.ignoresSafeArea()
      PocketPanel {
        VStack(alignment: .leading, spacing: 16) {
          Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(
            Color.evergreen)
          Text("Protect profiles on this device").font(.largeTitle.weight(.black)).fontDesign(
            .rounded)
          Text(
            "Choose a local PIN for the parent view and each child. These PINs keep siblings out of one another’s profile."
          ).foregroundStyle(.secondary)
          SecureField("Parent 4-digit PIN", text: $parentCode).textFieldStyle(.roundedBorder)
            .onChange(of: parentCode) { _, value in
              parentCode = String(value.filter(\.isNumber).prefix(4))
            }
          ForEach(store.state.children) { child in
            SecureField("\(child.name)’s 4-digit PIN", text: childBinding(child.id))
              .textFieldStyle(.roundedBorder).onChange(of: childCodes[child.id] ?? "") { _, value in
                childCodes[child.id] = String(value.filter(\.isNumber).prefix(4))
              }
          }
          if !error.isEmpty { Text(error).foregroundStyle(Color.coral) }
          Button("Secure this device") {
            do {
              try store.configureDevicePasscodes(parent: parentCode, children: childCodes)
            } catch {
              self.error = error.localizedDescription
            }
          }.buttonStyle(PrimaryButtonStyle()).disabled(!isValid)
        }.frame(maxWidth: 520)
      }.padding(28)
    }
  }

  private var isValid: Bool {
    parentCode.isFourDigitPasscode
      && store.state.children.allSatisfy({ childCodes[$0.id]?.isFourDigitPasscode == true })
  }
  private func childBinding(_ id: UUID) -> Binding<String> {
    Binding(get: { childCodes[id] ?? "" }, set: { childCodes[id] = $0 })
  }
}

struct CloudLoadingView: View {
  @EnvironmentObject private var cloud: CloudSessionStore
  var body: some View {
    ZStack {
      Color.oat.ignoresSafeArea()
      VStack(spacing: 15) {
        ProgressView().controlSize(.large)
        Text("Opening your family…").font(.title2.weight(.black)).fontDesign(.rounded)
        if case .failed(let message) = cloud.familyPhase {
          Text(message).foregroundStyle(Color.coral).multilineTextAlignment(.center)
          Button(AppLanguage.text("Try again")) { Task { await cloud.reloadFamily() } }.buttonStyle(
            PrimaryButtonStyle())
        }
      }.padding(28)
    }
  }
}

struct CloudSyncBadge: View {
  @EnvironmentObject private var cloud: CloudSessionStore
  var body: some View {
    switch cloud.syncState {
    case .localOnly:
      Label("On this device", systemImage: "internaldrive.fill")
    case .saving:
      Label("Saving…", systemImage: "arrow.triangle.2.circlepath.icloud")
    case .saved:
      Label("Saved to family", systemImage: "checkmark.icloud.fill")
    case .failed:
      Button {
        cloud.retrySync()
      } label: {
        Label("Sync needs attention", systemImage: "exclamationmark.icloud.fill")
      }
    }
  }
}

struct CloudProofPreview: View {
  @EnvironmentObject private var cloud: CloudSessionStore
  let path: String
  @State private var signedURL: URL?
  @State private var failed = false

  var body: some View {
    Group {
      if let signedURL {
        AsyncImage(url: signedURL) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFit()
          case .failure:
            Label("Proof preview unavailable", systemImage: "photo.badge.exclamationmark")
              .foregroundStyle(.secondary)
          default:
            ProgressView("Loading private proof…")
          }
        }
      } else if failed {
        Label("Proof preview unavailable", systemImage: "photo.badge.exclamationmark")
          .foregroundStyle(.secondary)
      } else {
        ProgressView("Opening private proof…")
      }
    }
    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 260)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .task(id: path) {
      signedURL = await cloud.signedProofURL(for: path)
      failed = signedURL == nil
    }
  }
}

struct CloudAccountDeletionView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @Environment(\.dismiss) private var dismiss
  @State private var phrase = ""
  @State private var parentPIN = ""
  @State private var error = ""
  @State private var working = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("Delete your guardian account?", systemImage: "trash.circle.fill")
            .font(.title2.weight(.black)).foregroundStyle(Color.coral)
          Text(
            "If you are the only guardian, the cloud family and its private proof images are deleted. If another guardian remains, ownership transfers to them. This cannot be undone."
          ).foregroundStyle(.secondary)
        }
        Section("Confirm") {
          TextField("Type DELETE", text: $phrase)
          SecureField("Current parent PIN", text: $parentPIN)
            .onChange(of: parentPIN) { _, value in
              parentPIN = String(value.filter(\.isNumber).prefix(4))
            }
        }
        if !error.isEmpty { Text(error).foregroundStyle(Color.coral) }
        if working { ProgressView("Deleting cloud account…") }
        Section {
          Button("Permanently delete account", role: .destructive) { deleteAccount() }
            .disabled(phrase != "DELETE" || !parentPIN.isFourDigitPasscode || working)
        }
      }
      .navigationTitle("Delete cloud account")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(AppLanguage.text("Cancel")) { dismiss() } }
      }
    }
    #if os(macOS)
      .frame(width: 560, height: 500)
    #endif
  }

  private func deleteAccount() {
    guard store.verifyParentPasscode(parentPIN) else {
      error = "The parent PIN didn’t match."
      parentPIN = ""
      return
    }
    working = true
    error = ""
    Task {
      if await cloud.deleteAccount() {
        dismiss()
      } else {
        error = cloud.notice ?? "The account could not be deleted."
      }
      working = false
    }
  }
}
