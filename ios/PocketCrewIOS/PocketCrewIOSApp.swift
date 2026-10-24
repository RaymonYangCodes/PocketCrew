import SwiftUI

@main
struct PocketCrewIOSApp: App {
  @StateObject private var store = AppStore()
  @StateObject private var cloud = CloudSessionStore()
  @AppStorage("pocketcrew.didEnter") private var didEnter = false

  var body: some Scene {
    WindowGroup {
      rootView
        .environmentObject(store)
        .environmentObject(cloud)
        .preferredColorScheme(.light)
        .task {
          cloud.bind(to: store)
          await cloud.restoreSession()
        }
        .onOpenURL { url in Task { await cloud.handle(url: url) } }
    }
  }

  @ViewBuilder private var rootView: some View {
    if cloud.usingDemo || (!cloud.isConfigured && didEnter) {
      if didEnter { MobileRootView() } else { MobileWelcomeView(didEnter: $didEnter) }
    } else {
      switch cloud.authPhase {
      case .signedIn:
        if cloud.requiresPasswordUpdate {
          PasswordUpdateView()
        } else {
          switch cloud.familyPhase {
          case .ready:
            if store.profilePasscodesReady { MobileRootView() } else { DevicePasscodeSetupView() }
          case .needsFamily:
            CloudFamilySetupView()
          default:
            CloudLoadingView()
          }
        }
      default:
        MobileWelcomeView(didEnter: $didEnter)
      }
    }
  }
}
