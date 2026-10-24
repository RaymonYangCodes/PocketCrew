import SwiftUI

struct MobileRootView: View {
  @EnvironmentObject private var store: AppStore

  var body: some View {
    Group {
      if store.sessionUnlocked {
        MobileTabShell()
      } else {
        MobileProfileLockView()
      }
    }
    .tint(Color.evergreen)
  }
}

struct MobileProfileLockView: View {
  @EnvironmentObject private var store: AppStore
  @State private var target: ProfileAccessTarget?

  var body: some View {
    ZStack {
      Color.oat.ignoresSafeArea()
      Circle().fill(Color.sunny.opacity(0.28)).frame(width: 330).offset(x: 170, y: -340)
      ScrollView {
        VStack(spacing: 24) {
          Spacer(minLength: 36)
          ZStack {
            RoundedRectangle(cornerRadius: 18).fill(Color.evergreen)
            Text("PC").font(.title2.bold()).foregroundStyle(.white)
          }.frame(width: 58, height: 58)
          VStack(spacing: 6) {
            Text("Who’s using PocketCrew?").font(.largeTitle.bold()).fontDesign(.rounded)
              .multilineTextAlignment(.center)
            Text("Every profile has its own passcode.").foregroundStyle(.secondary)
          }
          VStack(spacing: 12) {
            profileButton(
              store.guardianDisplayName, "Parent / guardian",
              "person.badge.key.fill", .evergreen, .parent)
            ForEach(store.state.children) { child in
              profileButton(
                child.name, "Child profile", child.avatarSymbol, Color(hex: child.avatarHex),
                .child(child.id))
            }
          }
          if store.state.family.id == DemoData.familyId {
            Text("Demo · Parent 2468 · Jordan 1212 · Riley 0808")
              .font(.caption.bold()).foregroundStyle(.secondary).multilineTextAlignment(.center)
          }
          Text("PocketCrew is a learning ledger. It does not hold or transfer funds.")
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(22)
      }
    }
    .sheet(item: $target) { MobilePasscodeView(target: $0) }
  }

  private func profileButton(
    _ name: String, _ subtitle: String, _ symbol: String, _ color: Color,
    _ accessTarget: ProfileAccessTarget
  ) -> some View {
    Button {
      target = accessTarget
    } label: {
      HStack(spacing: 14) {
        Image(systemName: symbol).font(.title2.bold()).foregroundStyle(Color.ink)
          .frame(width: 54, height: 54).background(color.opacity(0.72), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(name).font(.headline).foregroundStyle(Color.ink)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "lock.fill").foregroundStyle(Color.evergreen)
      }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.05)))
    }.buttonStyle(.plain)
  }
}

struct MobilePasscodeView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let target: ProfileAccessTarget
  @State private var passcode = ""
  @State private var error = ""
  @FocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        Spacer()
        Image(systemName: "lock.circle.fill").font(.system(size: 60)).foregroundStyle(
          Color.evergreen)
        Text("View as \(targetName)").font(.largeTitle.bold()).fontDesign(.rounded)
        SecureField("Four-digit passcode", text: $passcode).pocketCrewNumericKeyboard()
          .textContentType(.password).font(.title2.monospaced()).multilineTextAlignment(.center)
          .padding().background(.white, in: RoundedRectangle(cornerRadius: 14)).focused($focused)
          .onChange(of: passcode) { _, value in
            passcode = String(value.filter(\.isNumber).prefix(4))
            if passcode.count == 4 { authenticate() }
          }
        if let hint = store.demoPasscodeHint(for: target) {
          Text("Demo passcode: \(hint)").font(.caption.bold()).foregroundStyle(.secondary)
        }
        if !error.isEmpty {
          Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
        }
        Button("Unlock") { authenticate() }.buttonStyle(PrimaryButtonStyle())
          .disabled(passcode.count != 4)
        Spacer()
      }.padding(24).background(Color.oat).navigationTitle("Passcode").pocketCrewInlineTitle()
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }.presentationDetents([.medium]).onAppear { focused = true }
  }

  private var targetName: String {
    switch target {
    case .parent: return store.guardianDisplayName
    case .child(let id): return store.child(id)?.name ?? "Child"
    }
  }
  private func authenticate() {
    do {
      try store.unlock(target, passcode: passcode)
      dismiss()
    } catch {
      self.error = error.localizedDescription
      passcode = ""
    }
  }
}

struct MobileTabShell: View {
  @EnvironmentObject private var store: AppStore
  @State private var switchTarget: ProfileAccessTarget?

  var body: some View {
    TabView(selection: $store.destination) {
      mobileTab(.home) { MobileHomeView() }
      mobileTab(.work) { MobileWorkView() }
      mobileTab(.payday) { MobilePaydayView() }
      if store.role == .parent {
        mobileTab(.family) { MobileFamilyView() }
        mobileTab(.settings) { MobileSettingsView() }
      } else {
        mobileTab(.jars) { MobileJarsView() }
        mobileTab(.profile) { MobileProfileView() }
      }
    }
    .sheet(item: $switchTarget) { MobilePasscodeView(target: $0) }
    .onChange(of: store.role) { _, _ in store.destination = .home }
  }

  private func mobileTab<Content: View>(
    _ destination: AppDestination, @ViewBuilder content: () -> Content
  )
    -> some View
  {
    NavigationStack {
      content().toolbar {
        ToolbarItem(placement: .navigation) { Text("PocketCrew").font(.headline.bold()) }
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button {
              switchTarget = .parent
            } label: {
              Label("Parent", systemImage: "person.badge.key.fill")
            }
            ForEach(store.state.children) { child in
              Button {
                switchTarget = .child(child.id)
              } label: {
                Label(child.name, systemImage: child.avatarSymbol)
              }
            }
            Divider()
            Button {
              store.lock()
            } label: {
              Label("Lock profiles", systemImage: "lock.fill")
            }
          } label: {
            Image(
              systemName: store.role == .parent
                ? "person.badge.key.fill" : store.selectedChild.avatarSymbol)
          }.accessibilityLabel("Switch profile")
        }
      }
    }
    .tabItem { Label(destination.title, systemImage: destination.icon) }.tag(destination)
  }
}

struct MobileCard<Content: View>: View {
  @ViewBuilder let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white, in: RoundedRectangle(cornerRadius: 20))
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(.black.opacity(0.05)))
  }
}

extension View {
  @ViewBuilder func pocketCrewNumericKeyboard() -> some View {
    #if os(iOS)
      keyboardType(.numberPad)
    #else
      self
    #endif
  }

  @ViewBuilder func pocketCrewDecimalKeyboard() -> some View {
    #if os(iOS)
      keyboardType(.decimalPad)
    #else
      self
    #endif
  }

  @ViewBuilder func pocketCrewEmailInput() -> some View {
    #if os(iOS)
      keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
    #else
      self
    #endif
  }

  @ViewBuilder func pocketCrewInlineTitle() -> some View {
    #if os(iOS)
      navigationBarTitleDisplayMode(.inline)
    #else
      self
    #endif
  }
}
