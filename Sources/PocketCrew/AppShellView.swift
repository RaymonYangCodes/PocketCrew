import SwiftUI

struct AppShellView: View {
  @EnvironmentObject private var store: AppStore
  @AppStorage("pocketcrew.didEnter") private var didEnter = true
  @State private var toastTask: Task<Void, Never>?
  @State private var accessTarget: ProfileAccessTarget?
  @State private var tourIndex: Int?
  @State private var shopping = false
  private var tourSteps: [CrewTourStep] {
    CrewTourStep.steps(parent: store.role == .parent).map { step in
      if ["edit-child", "manage-jars", "child-passcode", "remove-child"].contains(step.target), let child = store.state.children.first {
        return CrewTourStep(destination: step.destination, target: step.target + "-" + child.id.uuidString, title: step.title, text: step.text)
      }
      return step
    }
  }
  private var tourKey: String { "pocketcrew.walkthrough.v1.\(store.state.family.id).\(store.role == .parent ? "parent" : store.selectedChildId.uuidString)" }
  private func startTour() { tourIndex = 0; store.destination = tourSteps[0].destination }
  private func finishTour() { UserDefaults.standard.set(true, forKey: tourKey); tourIndex = nil }

  var body: some View {
    Group {
      if store.sessionUnlocked {
        unlockedShell
      } else {
        ProfileLockView()
      }
    }
    .sheet(item: $accessTarget) { target in
      ProfilePasscodeSheet(target: target)
    }
    .tint(Color.evergreen)
    .onReceive(NotificationCenter.default.publisher(for: .replayCrewWalkthrough)) { _ in
      if store.sessionUnlocked { startTour() }
    }
    .onChange(of: store.sessionUnlocked) { _, unlocked in
      if !unlocked { tourIndex = nil }
    }
    .onChange(of: tourKey) { _, _ in tourIndex = nil }
  }

  private var unlockedShell: some View {
    NavigationSplitView {
      VStack(spacing: 0) {
        brand.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 16)
        roleSwitcher.walkthroughTarget("switch-profile").padding(.horizontal, 14).padding(.bottom, 12)
        List(store.destinations, selection: Binding(get: { store.destination.section }, set: { store.destination = $0 })) { destination in
          Label(AppLanguage.text(destination == .jars ? (store.role == .child ? "My Jars" : "Family Jars") : destination == .work && store.role == .child ? "My Tasks" : destination.title), systemImage: destination.icon).font(.body.weight(.semibold)).tag(
            destination).walkthroughTarget(destination.rawValue)
        }.scrollContentBackground(.hidden).listStyle(.sidebar)
        VStack(alignment: .leading, spacing: 8) {
          Button {
            store.lock()
          } label: {
            Label(AppLanguage.text("Lock profiles"), systemImage: "lock.fill").font(.caption.weight(.bold))
          }.buttonStyle(.plain).foregroundStyle(Color.evergreen).walkthroughTarget("lock-profiles")
          Text("PocketCrew keeps track. It does not hold or send real money.").font(.caption2).foregroundStyle(.secondary)
        }.padding(18)
      }.background(Color.oat)
        .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 285)
    } detail: {
      ZStack(alignment: .bottom) {
        Color.oat.ignoresSafeArea()
        destinationView
        if let toast = store.toast {
          ToastOverlay(message: toast).onAppear { scheduleToastDismiss(toast) }
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .sheet(isPresented: $shopping) { ShoppingCenterView() }
    .disabled(tourIndex != nil)
    .accessibilityHidden(tourIndex != nil)
    .overlayPreferenceValue(WalkthroughAnchors.self) { anchors in
      GeometryReader { proxy in
        if let index = tourIndex {
          CrewTourOverlay(step: tourSteps[index], index: index, count: tourSteps.count,
            rect: anchors[tourSteps[index].target].map { proxy[$0] },
            back: { if index > 0 { tourIndex = index - 1; store.destination = tourSteps[index - 1].destination } },
            next: { if index + 1 < tourSteps.count { tourIndex = index + 1; store.destination = tourSteps[index + 1].destination } else { finishTour() } },
            skip: finishTour)
        }
      }
    }
    .onAppear { if !UserDefaults.standard.bool(forKey: tourKey) { startTour() } }
  }

  private var brand: some View {
    HStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 12).fill(Color.evergreen)
        Text("PC").font(.subheadline.weight(.black)).foregroundStyle(.white)
      }.frame(width: 38, height: 38)
      VStack(alignment: .leading, spacing: 0) {
        Text("PocketCrew").font(.title3.weight(.black)).fontDesign(.rounded)
        Text(store.state.family.name).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
    }
  }
  private var roleSwitcher: some View {
    Menu {
      Button {
        accessTarget = .parent
      } label: {
        Label(
          store.guardianDisplayName, systemImage: "person.badge.key.fill")
      }
      Divider()
      ForEach(store.state.children) { child in
        Button {
          if store.role == .parent && store.sessionUnlocked {
            do { try store.viewChildAsParent(child.id) } catch { store.show(error: error) }
          } else { accessTarget = .child(child.id) }
        } label: {
          Label(child.name, systemImage: child.avatarSymbol)
        }
      }
    } label: {
      HStack {
        Image(
          systemName: store.role == .parent
            ? "person.badge.key.fill" : store.selectedChild.avatarSymbol
        )
        .foregroundStyle(Color.evergreen)
        VStack(alignment: .leading, spacing: 1) {
          Text(AppLanguage.text("VIEW AS")).font(.caption2.weight(.black)).tracking(0.8).foregroundStyle(.secondary)
          Text(
            store.role == .parent
              ? store.guardianDisplayName : store.selectedChild.name
          )
          .font(.subheadline.weight(.bold))
        }
        Spacer()
        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
      }.padding(10).background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }.menuStyle(.borderlessButton).accessibilityLabel("Switch profile with a passcode")
  }
  private var childSwitcher: some View {
    Menu {
      ForEach(store.state.children) { child in
        Button {
          store.selectChild(child.id)
        } label: {
          Label(child.name, systemImage: child.avatarSymbol)
        }
      }
    } label: {
      HStack {
        AvatarView(child: store.selectedChild, size: 34)
        VStack(alignment: .leading, spacing: 1) {
          Text("Viewing").font(.caption2).foregroundStyle(.secondary)
          Text(store.selectedChild.name).font(.subheadline.weight(.bold))
        }
        Spacer()
        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
      }.padding(8).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
    }.menuStyle(.borderlessButton).accessibilityLabel("Select child profile")
  }

  private var destinationView: some View {
    VStack(spacing: 0) {
      if store.destination.section == .jars || store.destination.section == .settings {
        HStack(spacing: 10) {
          if store.destination.section == .jars {
            sectionButton("Jars & goals", destination: .jars)
            sectionButton("Payday", destination: .payday)
            Button(AppLanguage.text("Shop")) { shopping = true }.buttonStyle(SecondaryButtonStyle())
          } else {
            sectionButton("Settings", destination: .settings)
            if store.role == .parent { sectionButton("Family", destination: .family) }
            else { sectionButton("Profile", destination: .profile) }
          }
          Spacer()
        }.padding(.horizontal, 32).padding(.vertical, 14)
        Divider()
      }
      pageContent
    }
  }
  private func sectionButton(_ title: String, destination: AppDestination) -> some View {
    Button(AppLanguage.text(title)) { store.destination = destination }
      .buttonStyle(FilterPill(active: store.destination == destination))
      .walkthroughTarget(destination == .jars || destination == .settings ? "section-" + destination.rawValue : destination.rawValue)
  }
  @ViewBuilder private var pageContent: some View {
    switch (store.role, store.destination) {
    case (.parent, .home): ParentHomeView()
    case (.child, .home): ChildHomeView()
    case (_, .work): WorkHubView()
    case (_, .payday): PaydayView()
    case (_, .jars): JarsView()
    case (_, .family): FamilyView()
    case (.parent, .settings): SettingsView(didEnter: $didEnter)
    case (.child, .settings): ChildSettingsView()
    case (_, .profile): ProfileView()
    }
  }
  private func scheduleToastDismiss(_ toast: ToastMessage) {
    toastTask?.cancel()
    toastTask = Task {
      try? await Task.sleep(for: .seconds(3.5))
      if !Task.isCancelled, store.toast?.id == toast.id { store.toast = nil }
    }
  }
}

struct ProfileLockView: View {
  @EnvironmentObject private var store: AppStore
  @State private var accessTarget: ProfileAccessTarget?

  var body: some View {
    ZStack {
      Color.oat.ignoresSafeArea()
      Circle().fill(Color.sunny.opacity(0.35)).frame(width: 420).offset(x: 480, y: -300)
      VStack(spacing: 26) {
        VStack(spacing: 8) {
          ZStack {
            RoundedRectangle(cornerRadius: 17).fill(Color.evergreen)
            Text("PC").font(.title3.weight(.black)).foregroundStyle(.white)
          }.frame(width: 54, height: 54)
          Text("Who’s using PocketCrew?").font(.system(size: 34, weight: .black, design: .rounded))
          Text("Each profile has its own private four-digit passcode.").foregroundStyle(.secondary)
        }
        HStack(spacing: 16) {
          profileCard(
            name: store.guardianDisplayName, subtitle: "Parent / guardian",
            symbol: "person.badge.key.fill", color: .evergreen, target: .parent)
          ForEach(store.state.children) { child in
            profileCard(
              name: child.name, subtitle: "Child profile", symbol: child.avatarSymbol,
              color: Color(hex: child.avatarHex), target: .child(child.id))
          }
        }.frame(maxWidth: 820)
        if store.state.family.id == DemoData.familyId {
          Text("Demo codes · Parent 2468 · Jordan 1212 · Riley 0808")
            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
        }
        Label(
          "Profiles lock whenever you switch or choose Lock profiles.",
          systemImage: "lock.shield.fill"
        )
        .font(.caption).foregroundStyle(.secondary)
      }.padding(40)
    }
    .sheet(item: $accessTarget) { target in ProfilePasscodeSheet(target: target) }
  }

  private func profileCard(
    name: String, subtitle: String, symbol: String, color: Color, target: ProfileAccessTarget
  ) -> some View {
    Button {
      accessTarget = target
    } label: {
      VStack(spacing: 14) {
        Image(systemName: symbol).font(.system(size: 28, weight: .bold)).foregroundStyle(Color.ink)
          .frame(width: 66, height: 66).background(color.opacity(0.72), in: Circle())
        VStack(spacing: 3) {
          Text(name).font(.title3.weight(.black)).foregroundStyle(Color.ink)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Label("Enter passcode", systemImage: "lock.fill").font(.caption.weight(.bold))
          .foregroundStyle(Color.evergreen)
      }.padding(22).frame(width: 190, height: 210)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.black.opacity(0.05)))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }.buttonStyle(.plain)
  }
}

struct ProfilePasscodeSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let target: ProfileAccessTarget
  @State private var passcode = ""
  @State private var error = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "lock.circle.fill").font(.system(size: 48)).foregroundStyle(Color.evergreen)
      VStack(spacing: 5) {
        Text("View as \(targetName)").font(.largeTitle.weight(.black)).fontDesign(.rounded)
        Text("Enter \(targetName)’s four-digit passcode.").foregroundStyle(.secondary)
      }
      SecureField("Passcode", text: $passcode).textFieldStyle(.roundedBorder).font(
        .title2.monospaced()
      )
      .multilineTextAlignment(.center).frame(width: 220).focused($focused)
      .onChange(of: passcode) { _, value in
        passcode = String(value.filter(\.isNumber).prefix(4))
        if passcode.count == 4 { authenticate() }
      }
      if let hint = store.demoPasscodeHint(for: target) {
        Text("Demo passcode: \(hint)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
      }
      if !error.isEmpty {
        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
      }
      HStack {
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button("Unlock") { authenticate() }.buttonStyle(PrimaryButtonStyle())
          .disabled(passcode.count != 4)
      }
    }.padding(32).frame(width: 430, height: 390).background(Color.oat)
      .onAppear { focused = true }
  }

  private var targetName: String {
    switch target {
    case .parent: return store.guardianDisplayName
    case .child(let childId): return store.child(childId)?.name ?? "Child"
    }
  }

  private func authenticate() {
    guard passcode.count == 4 else { return }
    do {
      try store.unlock(target, passcode: passcode)
      dismiss()
    } catch {
      self.error = error.localizedDescription
      passcode = ""
      focused = true
    }
  }
}
