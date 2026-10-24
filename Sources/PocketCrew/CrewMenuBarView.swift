import AppKit
import SwiftUI

/// Uses the same unlocked session and store as the main app. Never creates a second ledger.
struct CrewMenuBarView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.openWindow) private var openWindow
  let available: Bool
  @State private var selected: WorkAssignment?
  @State private var profileName = ""
  @State private var passcode = ""
  @State private var loginError = ""

  private var canRead: Bool { available && store.sessionUnlocked }
  private var work: [WorkAssignment] {
    guard canRead else { return [] }
    return store.state.assignments.filter { assignment in
      guard store.item(for: assignment)?.lifecycleStatus == "active" else { return false }
      if store.role == .parent { return assignment.status == .awaitingApproval }
      return assignment.childId == store.selectedChildId
        && [.assigned, .inProgress, .redoRequested].contains(assignment.status)
    }.sorted { $0.dueAt < $1.dueAt }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("PocketCrew", systemImage: "checkmark.circle.fill")
        .font(.title3.bold()).foregroundStyle(Color.evergreen)
      if canRead {
        Text(store.role == .parent ? "Check on your crew" : "Your next small win")
          .font(.headline)
        if store.role == .parent {
          ForEach(store.state.children.filter { $0.status == "active" }) { child in
            HStack {
              Text(child.name)
              Spacer()
              Text(store.pending(childId: child.id).currency(code: store.state.family.currency,
                locale: store.state.family.locale) + " pending")
                .foregroundStyle(.secondary)
            }
          }
          Text("\(work.count) waiting for review").font(.subheadline)
        } else {
          Text(store.selectedChild.name).foregroundStyle(.secondary)
        }
        if work.isEmpty {
          Text(store.role == .parent ? "All caught up with reviews." : "Nothing to finish right now. Find more gigs in Tasks.")
            .font(.subheadline).foregroundStyle(.secondary)
        } else {
          ScrollView {
            VStack(spacing: 8) {
              ForEach(work) { assignment in
                Button { selected = assignment } label: {
                  HStack {
                    VStack(alignment: .leading, spacing: 3) {
                      Text(store.item(for: assignment)?.title ?? "Work").fontWeight(.semibold)
                      if store.role == .parent, store.state.children.count > 1,
                        let id = assignment.childId, let child = store.child(id) {
                        Text(child.name).font(.caption)
                      }
                      Text(store.role == .parent ? "Review work" : "Open & complete")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                  }.frame(maxWidth: .infinity, minHeight: 44).padding(8)
                }.buttonStyle(.plain)
                  .background(.white, in: RoundedRectangle(cornerRadius: 12))
              }
            }
          }.frame(maxHeight: 280)
        }
        Button("Open all tasks") { showApp(.work) }
        Button(AppLanguage.text("Lock profiles"), systemImage: "lock") { selected = nil; store.lock() }
      } else if available {
        Text("Unlock your profile here").font(.headline)
        Text("Use your profile name—not your email. Capital letters don’t matter.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 6) {
          Text("Profile name").font(.caption.bold())
          TextField("Your name, or Parent", text: $profileName)
            .textFieldStyle(.roundedBorder).accessibilityLabel("Profile name")
          Text("Passcode").font(.caption.bold())
          SecureField("Profile passcode", text: $passcode)
            .textFieldStyle(.roundedBorder).accessibilityLabel("Profile passcode")
            .onSubmit { unlockHere() }
        }
        if !loginError.isEmpty {
          Text(loginError).font(.caption).foregroundStyle(Color.red)
            .fixedSize(horizontal: false, vertical: true)
        }
        Button("Unlock") { unlockHere() }.buttonStyle(PrimaryButtonStyle())
          .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || passcode.isEmpty)
      } else {
        Text("Sign in or set up your family once in PocketCrew. After that, you can unlock here with your profile name and passcode.")
          .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Button("Sign in or set up family") { showApp(.home) }
      }
    }
    .padding(18).frame(width: 340).background(Color.oat).tint(Color.evergreen)
    .foregroundStyle(Color.ink).preferredColorScheme(.light)
    .sheet(item: $selected) { assignment in
      if canRead {
        if store.role == .parent, assignment.status == .awaitingApproval,
          let submission = store.submission(for: assignment.id) {
          ReviewSheet(assignment: assignment, submission: submission)
        } else if assignment.childId == store.selectedChildId {
          WorkDetailSheet(assignment: assignment)
        }
      }
    }
    .onChange(of: store.sessionUnlocked) { _, unlocked in
      passcode = ""; loginError = ""
      if !unlocked { selected = nil }
    }
    .onChange(of: store.selectedChildId) { _, _ in selected = nil }
    .onChange(of: store.role) { _, _ in selected = nil }
    .onChange(of: available) { _, _ in selected = nil; passcode = ""; loginError = "" }
    .onDisappear { passcode = "" }
  }

  private func unlockHere() {
    guard available else { return }
    do {
      try store.unlock(profileName: profileName, passcode: passcode)
      passcode = ""; loginError = ""
    } catch { passcode = ""; loginError = error.localizedDescription }
  }

  private func showApp(_ destination: AppDestination) {
    store.destination = destination
    openWindow(id: "main")
    NSApp.activate(ignoringOtherApps: true)
  }
}
