import SwiftUI

@main
struct PocketCrewApp: App {
  @StateObject private var store = AppStore()
  @StateObject private var cloud = CloudSessionStore()
  @AppStorage("pocketcrew.didEnter") private var didEnter = false
  @AppStorage(AppLanguage.key) private var language = "en"

  var body: some Scene {
    WindowGroup(id: "main") {
      VStack(spacing: 0) { rootView.id(language) }
        .environment(\.locale, Locale(identifier: language))
        .environmentObject(store)
        .environmentObject(cloud)
        .preferredColorScheme(.light)
        .frame(minWidth: 760, minHeight: 600)
        .task {
          cloud.bind(to: store)
          await cloud.restoreSession()
        }
        .onOpenURL { url in Task { await cloud.handle(url: url) } }
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1260, height: 820)
    .commands { CommandGroup(replacing: .newItem) {} }

  }

  @ViewBuilder private var rootView: some View {
    if cloud.usingDemo || (!cloud.isConfigured && didEnter) {
      if didEnter { AppShellView() } else { WelcomeView(didEnter: $didEnter) }
    } else {
      switch cloud.authPhase {
      case .signedIn:
        if cloud.requiresPasswordUpdate {
          PasswordUpdateView()
        } else {
          switch cloud.familyPhase {
          case .ready:
            if store.profilePasscodesReady { AppShellView() } else { DevicePasscodeSetupView() }
          case .needsFamily:
            CloudFamilySetupView()
          default:
            CloudLoadingView()
          }
        }
      default:
        WelcomeView(didEnter: $didEnter)
      }
    }
  }
}
