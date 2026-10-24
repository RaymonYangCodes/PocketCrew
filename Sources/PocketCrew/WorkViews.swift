import AppKit
import SwiftUI

private enum WorkSegment: String, CaseIterable, Identifiable {
  case mine = "To do"
  case available = "Available gigs"
  case completed = "Completed"
  var id: String { rawValue }
}
private enum WorkFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case today = "Today"
  case week = "This week"
  case responsibilities = "Responsibilities"
  case gigs = "Gigs"
  var id: String { rawValue }
}

struct WorkHubView: View {
  @EnvironmentObject private var store: AppStore
  @State private var segment: WorkSegment = .mine
  @State private var filter: WorkFilter = .all
  @State private var createSheet = false
  @State private var proposeGigSheet = false
  @State private var selectedPreset: WorkPreset?
  @State private var selectedAssignment: WorkAssignment?
  @State private var showPresets = false
  @State private var loadedPresetPreference = false

  private var assignments: [WorkAssignment] {
    store.state.assignments.filter { assignment in
      guard let item = store.item(for: assignment), item.lifecycleStatus == "active" else {
        return false
      }
      let roleMatch: Bool
      switch segment {
      case .mine:
        roleMatch =
          store.role == .parent
          ? ![.available, .approved, .paid, .rejected].contains(assignment.status)
          : assignment.childId == store.selectedChildId
            && ![.approved, .paid, .rejected].contains(assignment.status)
      case .available:
        roleMatch =
          item.type == .gig && assignment.childId == nil && assignment.status == .available
      case .completed:
        roleMatch =
          [.approved, .paid, .rejected].contains(assignment.status)
          && (store.role == .parent || assignment.childId == store.selectedChildId)
      }
      guard roleMatch else { return false }
      switch filter {
      case .all: return true
      case .today: return Calendar.current.isDateInToday(assignment.dueAt)
      case .week:
        return assignment.dueAt < Calendar.current.date(byAdding: .day, value: 7, to: Date())!
      case .responsibilities: return item.type == .responsibility
      case .gigs: return item.type == .gig
      }
    }.sorted { $0.dueAt < $1.dueAt }
  }

  var body: some View {
    TourScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .bottom) {
          PageHeader(
            eyebrow: store.role == .parent ? "Family tasks" : "Your tasks", title: store.role == .child ? "My Tasks" : "Tasks",
            subtitle: store.role == .parent
              ? "Add tasks and review completed work."
              : "Choose a task, finish it, and send it for review.")
          Spacer()
          if store.role == .parent {
            Button {
              createSheet = true
            } label: {
              Label(AppLanguage.text("Add task"), systemImage: "plus")
            }.buttonStyle(PrimaryButtonStyle()).walkthroughTarget("add-task")
          } else {
            Button { proposeGigSheet = true } label: {
              Label(AppLanguage.text("Suggest a gig"), systemImage: "lightbulb.fill")
            }.buttonStyle(PrimaryButtonStyle())
          }
        }
        if store.role == .parent {
          if showPresets {
            WorkPresetLibrary(
              choose: { selectedPreset = $0 },
              done: {
                do {
                  try store.dismissWorkPresets()
                  showPresets = false
                } catch { store.show(error: error) }
              })
          } else {
            PocketPanel(padding: 14) {
              HStack(spacing: 12) {
                Image(systemName: "wand.and.stars").foregroundStyle(Color.evergreen)
                Text("Need an idea? Pick a task and make it your own.")
                  .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button(AppLanguage.text("Get ideas")) { showPresets = true }.buttonStyle(SecondaryButtonStyle()).walkthroughTarget("task-presets")
              }
            }
          }
        }
        Picker("Work view", selection: $segment) {
          ForEach(WorkSegment.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).frame(maxWidth: 620).walkthroughTarget("task-segments")
        HStack(spacing: 8) {
          ForEach(WorkFilter.allCases) { value in
            Button(value.rawValue) { filter = value }.buttonStyle(.plain).font(
              .caption.weight(.bold)
            ).padding(.horizontal, 13).frame(minHeight: 34).foregroundStyle(
              filter == value ? Color.white : Color.ink.opacity(0.68)
            ).background(filter == value ? Color.evergreen : Color.white, in: Capsule()).overlay(
              Capsule().stroke(Color.ink.opacity(filter == value ? 0 : 0.08))).walkthroughTarget("task-filter-" + value.rawValue)
          }
        }
        if assignments.isEmpty {
          PocketPanel {
            EmptyState(
              icon: "checkmark.circle",
              title: segment == .completed ? "No finished work yet" : "This list is clear",
              message: segment == .available
                ? "New open gigs will show up here when a parent adds them."
                : "Enjoy the breathing room. Work appears here when it’s assigned or claimed.")
          }
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
            ForEach(assignments) { assignment in
              WorkCardView(assignment: assignment) { selectedAssignment = assignment }
            }
          }
        }
      }.padding(32).frame(maxWidth: 1200, alignment: .leading)
    }
    .sheet(isPresented: $createSheet) { CreateWorkSheet() }
    .sheet(isPresented: $proposeGigSheet) { GigProposalSheet() }
    .sheet(item: $selectedPreset) { CreateWorkSheet(preset: $0) }
    .sheet(item: $selectedAssignment) { assignment in
      if store.role == .parent, let submission = store.submission(for: assignment.id),
        assignment.status == .awaitingApproval
      {
        ReviewSheet(assignment: assignment, submission: submission)
      } else {
        WorkDetailSheet(assignment: assignment)
      }
    }
    .onAppear {
      guard !loadedPresetPreference else { return }
      loadedPresetPreference = true
      showPresets = store.state.family.workPresetsDismissed != true
    }
    .onChange(of: store.state.family.workPresetsDismissed) { _, dismissed in
      if dismissed == true { showPresets = false }
    }
  }
}

struct WorkCardView: View {
  @EnvironmentObject private var store: AppStore
  let assignment: WorkAssignment
  var open: () -> Void
  private var item: WorkItem? { store.item(for: assignment) }

  var body: some View {
    if let item {
      PocketPanel {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top) {
            TypeBadge(type: item.type)
            Spacer()
            StatusBadge(status: assignment.status)
          }
          VStack(alignment: .leading, spacing: 5) {
            Text(item.title).font(.title3.weight(.black)).fontDesign(.rounded)
            Text(item.instructions).font(.subheadline).foregroundStyle(Color.ink.opacity(0.62))
              .lineLimit(2)
          }
          HStack(spacing: 14) {
            Label(assignment.dueAt.shortDate, systemImage: "calendar")
            Label(item.recurrence.title, systemImage: "arrow.triangle.2.circlepath")
            if let minutes = assignment.estimatedMinutes {
              Label("~\(minutes)m", systemImage: "clock")
            }
          }.font(.caption).foregroundStyle(.secondary)
          HStack {
            if store.state.children.count > 1 {
              if let child = store.child(assignment.childId) {
                HStack(spacing: 6) {
                  AvatarView(child: child, size: 26)
                  Text(child.name).font(.caption.weight(.bold))
                }
              } else {
                Label("Open to any child", systemImage: "person.2").font(.caption.weight(.bold))
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            if item.type == .gig {
              Text(
                assignment.rewardSnapshotCents.currency(
                  code: store.state.family.currency, locale: store.state.family.locale)
              ).font(.title3.weight(.black)).foregroundStyle(Color.evergreen)
            }
          }
          Divider()
          HStack {
            Button(nextActionTitle) { performAction() }.buttonStyle(
              assignment.status == .available || assignment.status == .assigned
                || assignment.status == .inProgress || assignment.status == .redoRequested
                ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
            Spacer()
            if store.role == .parent {
              Menu {
                Button(item.lifecycleStatus == "paused" ? "Resume" : "Pause") {
                  tryAction {
                    try store.setWorkLifecycle(
                      item.id, status: item.lifecycleStatus == "paused" ? "active" : "paused")
                  }
                }
                Divider()
                Button("Delete", role: .destructive) {
                  tryAction { try store.setWorkLifecycle(item.id, status: "deleted") }
                }
              } label: {
                Image(systemName: "ellipsis").frame(width: 34, height: 34)
              }.menuStyle(.borderlessButton)
            }
          }
        }
      }
    }
  }
  private var nextActionTitle: String {
    if store.role == .parent {
      return assignment.status == .awaitingApproval ? "Review submission" : "Open details"
    }
    switch assignment.status {
    case .available: return "Claim gig"
    case .assigned: return "Start"
    case .inProgress, .redoRequested: return "Finish & submit"
    case .awaitingApproval: return "View submission"
    default: return "View details"
    }
  }
  private func performAction() {
    if store.role == .child && (assignment.status == .available || assignment.status == .assigned) {
      do {
        try store.start(assignment.id)
        open()
      } catch { store.show(error: error) }
    } else {
      open()
    }
  }
  private func tryAction(_ action: () throws -> Void) {
    do { try action() } catch { store.show(error: error) }
  }
}

struct AnyButtonStyle: ButtonStyle {
  private let bodyBuilder: (Configuration) -> AnyView
  init<S: ButtonStyle>(_ style: S) { bodyBuilder = { AnyView(style.makeBody(configuration: $0)) } }
  func makeBody(configuration: Configuration) -> some View { bodyBuilder(configuration) }
}

struct CreateWorkSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var type: WorkType = .gig
  @State private var title = ""
  @State private var instructions = ""
  @State private var category = "Home"
  @State private var childId: UUID?
  @State private var recurrence: Recurrence = .once
  @State private var dueAt = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
  @State private var duration = 20
  @State private var reward = ""
  @State private var proofRequired = false
  @State private var claimable = true
  @State private var checklist = ""
  @State private var error = ""
  private let presetTitle: String?

  init(initialType: WorkType = .gig, preset: WorkPreset? = nil) {
    let resolvedType = preset?.type ?? initialType
    presetTitle = preset?.title
    _type = State(initialValue: resolvedType)
    _title = State(initialValue: preset?.title ?? "")
    _instructions = State(initialValue: preset?.instructions ?? "")
    _category = State(initialValue: preset?.category ?? "Home")
    _recurrence = State(initialValue: preset?.recurrence ?? .once)
    _duration = State(initialValue: preset?.estimatedMinutes ?? 20)
    _reward = State(
      initialValue: preset.map { String(format: "%.2f", Double($0.rewardCents) / 100) } ?? "")
    _proofRequired = State(initialValue: preset?.proofRequired ?? false)
    _claimable = State(initialValue: preset?.claimable ?? true)
    _checklist = State(initialValue: preset?.checklist.joined(separator: ", ") ?? "")
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading) {
          Text(presetTitle == nil ? "Add work" : "Customize this preset")
            .font(.largeTitle.weight(.black)).fontDesign(.rounded)
          Text(
            presetTitle == nil
              ? "Responsibilities build habits. Gigs create optional earning opportunities."
              : "Everything is prefilled, and you can change any detail before adding it."
          )
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }.buttonStyle(.plain)
      }
      .padding(28)
      Form {
        Picker("Type", selection: $type) { ForEach(WorkType.allCases) { Text($0.title).tag($0) } }
          .pickerStyle(.segmented)
        Section("The work") {
          TextField("Title", text: $title)
          TextField("Instructions", text: $instructions, axis: .vertical).lineLimit(2...4)
          TextField("Category", text: $category)
          Picker("Assigned to", selection: $childId) {
            Text("Open to any child").tag(UUID?.none)
            ForEach(store.state.children) { Text($0.name).tag(Optional($0.id)) }
          }
        }
        Section("Timing") {
          Picker("Schedule", selection: $recurrence) {
            ForEach(Recurrence.allCases) { Text($0.title).tag($0) }
          }
          DatePicker("Due", selection: $dueAt)
          Stepper("About \(duration) minutes", value: $duration, in: 5...180, step: 5)
        }
        Section("Details") {
          if type == .gig {
            TextField("Reward (for example 10.00)", text: $reward)
            Toggle("Children may claim this gig", isOn: $claimable)
          }
          Toggle("Require a proof image", isOn: $proofRequired)
          TextField("Checklist steps, separated by commas", text: $checklist)
        }
        if !error.isEmpty {
          Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.coral)
        }
      }.formStyle(.grouped)
      Divider()
      HStack {
        Spacer()
        Button(AppLanguage.text("Cancel")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
        Button("Add \(type == .gig ? "gig" : "responsibility")") { save() }.buttonStyle(
          PrimaryButtonStyle())
      }.padding(22)
    }.frame(width: 640, height: 720).background(Color.oat)
  }
  private func save() {
    let cents = Int(((Double(reward) ?? 0) * 100).rounded())
    let resolvedChildId = type == .responsibility && childId == nil ? store.selectedChildId : childId
    do {
      try store.createWork(
        type: type, title: title, instructions: instructions, category: category,
        childId: resolvedChildId,
        recurrence: recurrence, dueAt: dueAt, minutes: duration, reward: cents,
        proof: proofRequired, claimable: type == .gig && claimable,
        checklist: checklist.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty })
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct WorkDetailSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let assignment: WorkAssignment
  @State private var note = ""
  @State private var proof: ProofImage?
  @State private var error = ""
  private var item: WorkItem? { store.item(for: assignment) }
  private var liveAssignment: WorkAssignment {
    store.state.assignments.first(where: { $0.id == assignment.id }) ?? assignment
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          if let item {
            TypeBadge(type: item.type)
            Text(item.title).font(.largeTitle.weight(.black)).fontDesign(.rounded)
          }
        }
        Spacer()
        StatusBadge(status: liveAssignment.status)
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }.buttonStyle(.plain)
      }
      if let item {
        Text(item.instructions).font(.title3).foregroundStyle(.secondary)
        HStack {
          Label(liveAssignment.dueAt.friendlyDate, systemImage: "calendar")
          if item.type == .gig {
            Spacer()
            Text(liveAssignment.rewardSnapshotCents.currency()).font(.title2.weight(.black))
              .foregroundStyle(Color.evergreen)
          }
        }
        if !item.checklist.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text("CHECKLIST").font(.caption.weight(.black)).tracking(1.2).foregroundStyle(
              Color.evergreen)
            ForEach(item.checklist, id: \.self) { step in
              Button {
                tryAction { try store.toggleStep(step, assignmentId: assignment.id) }
              } label: {
                HStack {
                  Image(
                    systemName: liveAssignment.checklistDone.contains(step)
                      ? "checkmark.circle.fill" : "circle"
                  ).foregroundStyle(
                    liveAssignment.checklistDone.contains(step) ? Color.evergreen : Color.secondary)
                  Text(step).strikethrough(liveAssignment.checklistDone.contains(step))
                  Spacer()
                }.contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
        if store.role == .child && [.available, .assigned].contains(liveAssignment.status) {
          Button(liveAssignment.status == .available ? "Claim gig" : "Start task") {
            tryAction { try store.start(assignment.id) }
          }.buttonStyle(PrimaryButtonStyle())
        }
        if store.role == .child
          && [.inProgress, .redoRequested].contains(liveAssignment.status)
        {
          if liveAssignment.status == .redoRequested,
            let submission = store.submission(for: assignment.id),
            let decision = store.state.decisions.last(where: { $0.submissionId == submission.id })
          {
            Label(
              decision.reason ?? "Please take another look.",
              systemImage: "arrow.clockwise.circle.fill"
            ).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
              Color.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
          }
          TextField("Add a note for your grown-up (optional)", text: $note, axis: .vertical)
            .lineLimit(2...4).textFieldStyle(.roundedBorder)
          HStack {
            Button {
              chooseProof()
            } label: {
              Label(proof == nil ? "Add proof image" : proof!.fileName, systemImage: "photo")
            }.buttonStyle(SecondaryButtonStyle())
            Spacer()
            Button(AppLanguage.text("Send to my grown-up")) { submit() }.buttonStyle(PrimaryButtonStyle())
          }
        } else if let submission = store.submission(for: assignment.id) {
          PocketPanel(padding: 15) {
            VStack(alignment: .leading, spacing: 6) {
              Text("YOUR SUBMISSION").font(.caption.weight(.black)).tracking(1)
              Text(submission.note.isEmpty ? "No note added" : submission.note)
              if let proof = submission.proofImage {
                Label(proof.fileName, systemImage: "photo.fill").font(.caption).foregroundStyle(
                  .secondary)
              }
            }
          }
        }
        if !error.isEmpty {
          Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.coral)
        }
      }
    }.padding(28).frame(width: 610, height: 650, alignment: .topLeading).background(Color.oat)
  }
  private func chooseProof() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .heic]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      if let data = try? Data(contentsOf: url), data.count <= 8_000_000 {
        proof = ProofImage(fileName: url.lastPathComponent, bookmarkData: data)
      } else {
        error = "Choose an image under 8 MB."
      }
    }
  }
  private func submit() {
    do {
      try store.submit(assignment.id, note: note, proof: proof)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
  private func tryAction(_ action: () throws -> Void) {
    do { try action() } catch { self.error = error.localizedDescription }
  }
}

struct ReviewSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let assignment: WorkAssignment
  let submission: WorkSubmission
  @State private var decision: DecisionKind?
  @State private var reason = ""
  @State private var error = ""
  private var item: WorkItem? { store.item(for: assignment) }
  private var child: ChildProfile? { store.child(submission.childId) }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("READY FOR REVIEW").font(.caption.weight(.black)).tracking(1.3).foregroundStyle(
            Color.evergreen)
          Text(item?.title ?? "Submission").font(.largeTitle.weight(.black)).fontDesign(.rounded)
        }
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }.buttonStyle(.plain)
      }
      HStack {
        if let child {
          AvatarView(child: child)
          Text(child.name).font(.headline)
        }
        Spacer()
        Text("Submitted \(submission.submittedAt.formatted(.relative(presentation: .named)))").font(
          .caption
        ).foregroundStyle(.secondary)
      }
      PocketPanel {
        VStack(alignment: .leading, spacing: 10) {
          Label("Child’s note", systemImage: "quote.bubble.fill").font(.caption.weight(.black))
            .foregroundStyle(Color.evergreen)
          Text(submission.note.isEmpty ? "No note added." : submission.note).font(.title3)
          if let proof = submission.proofImage {
            Label("Proof attached: \(proof.fileName)", systemImage: "photo.fill").foregroundStyle(
              .secondary)
            if let path = proof.storagePath { CloudProofPreview(path: path) }
          }
        }
      }
      if let item {
        HStack {
          Label(item.type.title, systemImage: item.type == .gig ? "sparkles" : "house.fill")
          Spacer()
          if item.type == .gig {
            Text("Reward \(assignment.rewardSnapshotCents.currency())").font(.title3.weight(.black))
              .foregroundStyle(Color.evergreen)
          } else {
            Text("Completes with $0.00").foregroundStyle(.secondary)
          }
        }
      }
      if let decision, decision != .approved {
        VStack(alignment: .leading, spacing: 7) {
          Text(decision == .redoRequested ? "What needs another try?" : "Why isn’t this approved?")
            .font(.headline)
          TextField("Be kind and specific", text: $reason, axis: .vertical).lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
          Button(
            decision == .redoRequested ? "Send redo request" : "Record rejection",
            role: decision == .rejected ? .destructive : nil
          ) { submitDecision(decision) }.buttonStyle(PrimaryButtonStyle()).disabled(
            reason.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      } else {
        HStack {
          Button(AppLanguage.text("Not this time")) { decision = .rejected }.buttonStyle(SecondaryButtonStyle())
          Button("Ask to try again") { decision = .redoRequested }.buttonStyle(SecondaryButtonStyle())
          Spacer()
          Button {
            submitDecision(.approved)
          } label: {
            Label(AppLanguage.text("Approve"), systemImage: "checkmark")
          }.buttonStyle(PrimaryButtonStyle())
        }
      }
      if !error.isEmpty {
        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.coral)
      }
    }.padding(28).frame(width: 620, height: 590, alignment: .topLeading).background(Color.oat)
  }
  private func submitDecision(_ value: DecisionKind) {
    do {
      if value == .approved {
        try store.approve(submission.id)
      } else {
        try store.decide(submission.id, decision: value, reason: reason)
      }
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
