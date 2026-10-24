import PhotosUI
import SwiftUI

struct MobileWorkView: View {
  @EnvironmentObject private var store: AppStore
  @State private var segment = 0
  @State private var creating = false
  @State private var selectedPreset: WorkPreset?
  @State private var showPresets = false
  @State private var loadedPresetPreference = false

  private var assignments: [WorkAssignment] {
    store.state.assignments.filter { assignment in
      guard store.item(for: assignment)?.lifecycleStatus == "active" else { return false }
      if segment == 1 {
        return assignment.status == .available && store.item(for: assignment)?.type == .gig
      }
      if segment == 2 {
        return [.approved, .paid, .rejected].contains(assignment.status)
          && (store.role == .parent || assignment.childId == store.selectedChildId)
      }
      return store.role == .parent
        ? ![.available, .approved, .paid, .rejected].contains(assignment.status)
        : assignment.childId == store.selectedChildId
          && ![.approved, .paid, .rejected].contains(assignment.status)
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          VStack(alignment: .leading) {
            Text("Work").font(.largeTitle.bold()).fontDesign(.rounded)
            Text(
              store.role == .parent
                ? "Assign, review, and encourage." : "Pick what’s next and send it for review."
            ).foregroundStyle(.secondary)
          }
          Spacer()
          if store.role == .parent {
            Button {
              creating = true
            } label: {
              Image(systemName: "plus").font(.headline)
            }.buttonStyle(.borderedProminent).accessibilityLabel("Add work")
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
            MobileCard {
              VStack(alignment: .leading, spacing: 10) {
                Label("Work presets are always available", systemImage: "wand.and.stars")
                  .font(.headline).foregroundStyle(Color.evergreen)
                Text("Reopen editable gig and responsibility ideas whenever you need one.")
                  .font(.subheadline).foregroundStyle(.secondary)
                Button("Show presets") { showPresets = true }.buttonStyle(.bordered)
              }
            }
          }
        }
        Picker("Work list", selection: $segment) {
          Text("My work").tag(0)
          Text("Available gigs").tag(1)
          Text("Completed").tag(2)
        }.pickerStyle(.segmented)
        if assignments.isEmpty {
          MobileCard {
            ContentUnavailableView(
              "Nothing here yet", systemImage: "checkmark.circle",
              description: Text("New work appears here when it’s added or assigned."))
          }
        }
        ForEach(assignments) { assignment in MobileWorkRow(assignment: assignment) }
      }.padding(16)
    }.background(Color.oat).sheet(isPresented: $creating) { MobileCreateWorkSheet() }
      .sheet(item: $selectedPreset) { MobileCreateWorkSheet(preset: $0) }
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

struct MobileWorkRow: View {
  @EnvironmentObject private var store: AppStore
  let assignment: WorkAssignment
  @State private var details = false
  private var item: WorkItem? { store.item(for: assignment) }
  var body: some View {
    MobileCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          TypeBadge(type: item?.type ?? .responsibility)
          Spacer()
          StatusBadge(status: assignment.status)
        }
        Text(item?.title ?? "Work item").font(.headline)
        Text(item?.instructions ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        if store.state.children.count > 1 {
          if let child = store.child(assignment.childId) {
            Label(child.name, systemImage: child.avatarSymbol).font(.caption.weight(.bold))
              .foregroundStyle(.secondary)
          } else {
            Label("Open to any child", systemImage: "person.2.fill").font(.caption.weight(.bold))
              .foregroundStyle(.secondary)
          }
        }
        HStack {
          Label(assignment.dueAt.shortDate, systemImage: "calendar").font(.caption)
          Spacer()
          if item?.type == .gig {
            Text(assignment.rewardSnapshotCents.currency()).font(.headline).foregroundStyle(
              Color.evergreen)
          }
        }
        Button(actionTitle) { action() }.buttonStyle(.borderedProminent).frame(
          maxWidth: .infinity, alignment: .trailing)
      }
    }.sheet(isPresented: $details) {
      if store.role == .parent, assignment.status == .awaitingApproval,
        let submission = store.submission(for: assignment.id)
      {
        MobileReviewSheet(assignment: assignment, submission: submission)
      } else {
        MobileWorkDetailSheet(assignment: assignment)
      }
    }
  }
  private var actionTitle: String {
    if store.role == .parent {
      return assignment.status == .awaitingApproval ? "Review" : "Details"
    }
    switch assignment.status {
    case .available: return "Claim"
    case .assigned: return "Start"
    case .inProgress, .redoRequested: return "Finish & submit"
    default: return "Details"
    }
  }
  private func action() {
    if store.role == .child && [.available, .assigned].contains(assignment.status) {
      do { try store.start(assignment.id) } catch { store.show(error: error) }
    }
    details = true
  }
}

struct MobileWorkDetailSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let assignment: WorkAssignment
  @State private var note = ""
  @State private var photoItem: PhotosPickerItem?
  @State private var proof: ProofImage?
  @State private var error = ""
  private var item: WorkItem? { store.item(for: assignment) }
  private var live: WorkAssignment {
    store.state.assignments.first(where: { $0.id == assignment.id }) ?? assignment
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(item?.instructions ?? "")
          if item?.type == .gig {
            LabeledContent("Reward", value: assignment.rewardSnapshotCents.currency())
          }
          LabeledContent("Due", value: assignment.dueAt.friendlyDate)
        }
        if let steps = item?.checklist, !steps.isEmpty {
          Section("Checklist") {
            ForEach(steps, id: \.self) { step in
              Button {
                do { try store.toggleStep(step, assignmentId: assignment.id) } catch {
                  store.show(error: error)
                }
              } label: {
                Label(
                  step,
                  systemImage: live.checklistDone.contains(step)
                    ? "checkmark.circle.fill" : "circle")
              }.foregroundStyle(Color.ink)
            }
          }
        }
        if store.role == .child && [.inProgress, .redoRequested, .assigned].contains(live.status) {
          if live.status == .redoRequested, let submission = store.submission(for: assignment.id),
            let decision = store.state.decisions.last(where: { $0.submissionId == submission.id })
          {
            Section("Redo note") { Text(decision.reason ?? "Please take another look.") }
          }
          Section("Submission") {
            TextField("Optional note", text: $note, axis: .vertical)
            PhotosPicker(selection: $photoItem, matching: .images) {
              Label(proof?.fileName ?? "Add proof image", systemImage: "photo")
            }
            .onChange(of: photoItem) { _, item in
              Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                  data.count <= 8_000_000
                {
                  proof = ProofImage(fileName: "proof-image.jpg", bookmarkData: data)
                } else if item != nil {
                  error = "Choose an image under 8 MB."
                }
              }
            }
          }
          if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
          Section {
            Button("Submit for review") { submit() }.disabled(
              item?.proofRequired == true && proof == nil)
          }
        } else if let submission = store.submission(for: assignment.id) {
          Section("Submission") {
            Text(submission.note.isEmpty ? "No note added" : submission.note)
            if let proof = submission.proofImage {
              Label(proof.fileName, systemImage: "photo.fill")
            }
          }
        }
      }.navigationTitle(item?.title ?? "Work").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
      }
    }
  }
  private func submit() {
    do {
      try store.submit(assignment.id, note: note, proof: proof)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct MobileReviewSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  let assignment: WorkAssignment
  let submission: WorkSubmission
  @State private var reason = ""
  @State private var showingReason: DecisionKind?
  @State private var error = ""
  var body: some View {
    NavigationStack {
      Form {
        Section("Submitted by") {
          LabeledContent(
            store.child(submission.childId)?.name ?? "Child",
            value: submission.submittedAt.formatted(date: .abbreviated, time: .shortened))
        }
        Section("Child’s note") {
          Text(submission.note.isEmpty ? "No note added" : submission.note)
          if let proof = submission.proofImage { Label(proof.fileName, systemImage: "photo.fill") }
          if let path = submission.proofImage?.storagePath { CloudProofPreview(path: path) }
        }
        if store.item(for: assignment)?.type == .gig {
          Section {
            LabeledContent("Agreed reward", value: assignment.rewardSnapshotCents.currency())
          }
        } else {
          Section { Text("Approving this responsibility adds no money.") }
        }
        if let decision = showingReason {
          Section(decision == .redoRequested ? "What needs another try?" : "Reason") {
            TextField("Be kind and specific", text: $reason, axis: .vertical)
            Button(
              decision == .redoRequested ? "Send redo request" : "Record rejection",
              role: decision == .rejected ? .destructive : nil
            ) { decide(decision) }.disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        } else {
          Section {
            Button("Approve") { approve() }
            Button("Request redo") { showingReason = .redoRequested }
            Button("Reject", role: .destructive) { showingReason = .rejected }
          }
        }
        if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
      }.navigationTitle(store.item(for: assignment)?.title ?? "Review").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
      }
    }
  }
  private func approve() {
    do {
      try store.approve(submission.id)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
  private func decide(_ value: DecisionKind) {
    do {
      try store.decide(submission.id, decision: value, reason: reason)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct MobileCreateWorkSheet: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var type: WorkType = .gig
  @State private var title = ""
  @State private var instructions = ""
  @State private var category = "Home"
  @State private var childId: UUID?
  @State private var recurrence: Recurrence = .once
  @State private var reward = ""
  @State private var due = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
  @State private var duration = 20
  @State private var proof = false
  @State private var claimable = true
  @State private var checklist = ""
  @State private var error = ""
  private let presetTitle: String?

  init(preset: WorkPreset? = nil) {
    presetTitle = preset?.title
    _type = State(initialValue: preset?.type ?? .gig)
    _title = State(initialValue: preset?.title ?? "")
    _instructions = State(initialValue: preset?.instructions ?? "")
    _category = State(initialValue: preset?.category ?? "Home")
    _recurrence = State(initialValue: preset?.recurrence ?? .once)
    _reward = State(
      initialValue: preset.map { String(format: "%.2f", Double($0.rewardCents) / 100) } ?? "")
    _duration = State(initialValue: preset?.estimatedMinutes ?? 20)
    _proof = State(initialValue: preset?.proofRequired ?? false)
    _claimable = State(initialValue: preset?.claimable ?? true)
    _checklist = State(initialValue: preset?.checklist.joined(separator: ", ") ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Picker("Type", selection: $type) { ForEach(WorkType.allCases) { Text($0.title).tag($0) } }
        Section("Work") {
          TextField("Title", text: $title)
          TextField("Instructions", text: $instructions, axis: .vertical)
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
          DatePicker("Due", selection: $due)
          Stepper("About \(duration) minutes", value: $duration, in: 5...180, step: 5)
        }
        Section("Details") {
          if type == .gig {
            TextField("Reward", text: $reward).pocketCrewDecimalKeyboard()
            Toggle("Children may claim this gig", isOn: $claimable)
          }
          Toggle("Require proof image", isOn: $proof)
          TextField("Checklist steps, separated by commas", text: $checklist, axis: .vertical)
        }
        if !error.isEmpty { Text(error).foregroundStyle(.red) }
      }.navigationTitle(presetTitle == nil ? "Add work" : "Customize preset").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") { save() }.disabled(title.isEmpty)
        }
      }
    }
  }
  private func save() {
    let resolvedChildId = type == .responsibility && childId == nil ? store.selectedChildId : childId
    do {
      try store.createWork(
        type: type, title: title, instructions: instructions, category: category,
        childId: resolvedChildId,
        recurrence: recurrence, dueAt: due, minutes: duration,
        reward: Int(((Double(reward) ?? 0) * 100).rounded()), proof: proof,
        claimable: type == .gig && claimable,
        checklist: checklist.split(separator: ",").map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
