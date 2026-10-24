import SwiftUI

struct MobileWelcomeView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var cloud: CloudSessionStore
  @Binding var didEnter: Bool
  @State private var authMode: CloudAuthMode?

  var body: some View {
    ZStack {
      Color.oat.ignoresSafeArea()
      Circle().fill(Color.sunny.opacity(0.32)).frame(width: 340).offset(x: 170, y: -330)
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Spacer(minLength: 42)
          HStack(spacing: 11) {
            ZStack {
              RoundedRectangle(cornerRadius: 15).fill(Color.evergreen)
              Text("PC").font(.headline.bold()).foregroundStyle(.white)
            }.frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 1) {
              Text("PocketCrew").font(.title2.bold()).fontDesign(.rounded)
              Text("Earn it. Split it. Grow it.").font(.caption.bold()).foregroundStyle(
                Color.evergreen)
            }
          }
          VStack(alignment: .leading, spacing: 12) {
            Text("A little economy for your favorite crew.").font(
              .system(size: 43, weight: .black, design: .rounded)
            ).tracking(-1.2)
            Text(
              "Kids contribute, earn, and build money confidence. Parents keep every step clear and safe."
            ).font(.title3).foregroundStyle(.secondary).lineSpacing(3)
          }
          MobileCard {
            VStack(alignment: .leading, spacing: 14) {
              Label("WORK → REVIEW → PAYDAY → JARS", systemImage: "sparkles")
                .font(.caption.bold()).foregroundStyle(Color.evergreen)
              HStack {
                jar(.spend, "50%")
                jar(.save, "40%")
                jar(.give, "10%")
              }
            }
          }
          VStack(spacing: 11) {
            Button {
              cloud.enterDemo()
              try? store.resetDemo()
              didEnter = true
            } label: {
              Label("Try the Parker demo family", systemImage: "play.fill").frame(
                maxWidth: .infinity)
            }.buttonStyle(PrimaryButtonStyle())
            Button("Create a family") { authMode = .signUp }.buttonStyle(SecondaryButtonStyle())
              .frame(maxWidth: .infinity)
            Button("Sign in") { authMode = .signIn }.fontWeight(.bold).foregroundStyle(
              Color.evergreen
            )
            .frame(minHeight: 44)
            Button {
              Task { await cloud.signInWithGoogle() }
            } label: {
              Label("Continue with Google", systemImage: "person.crop.circle.badge.checkmark")
                .frame(maxWidth: .infinity)
            }.buttonStyle(SecondaryButtonStyle())
          }
          if let notice = cloud.notice {
            Text(notice).font(.caption).foregroundStyle(Color.coral).multilineTextAlignment(.center)
              .frame(maxWidth: .infinity)
          }
          Text(
            "PocketCrew is a family learning ledger—not a bank. It does not hold, insure, or transfer funds."
          ).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }.padding(22)
      }
    }
    .sheet(item: $authMode) { mode in
      CloudAuthView(initialMode: mode).environmentObject(cloud)
    }
  }

  private func jar(_ kind: JarKind, _ percent: String) -> some View {
    VStack(spacing: 5) {
      JarIcon(kind: kind, size: 42)
      Text(kind.title).font(.caption.bold())
      Text(percent).font(.caption2).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity)
  }
}

struct MobileLocalSignIn: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var didEnter: Bool
  @State private var email = ""

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Parent email", text: $email).pocketCrewEmailInput()
        } footer: {
          Text(
            "Cloud accounts are not connected in this local build. Continue to the on-device family after entering an email."
          )
        }
      }.navigationTitle("Welcome back").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Continue") {
            didEnter = true
            dismiss()
          }.disabled(!email.contains("@"))
        }
      }
    }.presentationDetents([.medium])
  }
}

struct MobileOnboardingView: View {
  @EnvironmentObject private var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @Binding var didEnter: Bool
  @State private var step = 0
  @State private var familyName = "Our Family"
  @State private var parentName = ""
  @State private var parentPasscode = ""
  @State private var frequency: PaydayFrequency = .weekly
  @State private var currency = "USD"
  @State private var children = [ChildSetupDraft.blank()]
  @State private var error = ""

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        progress
        if step == 0 { familyStep } else if step == 1 { childStep } else { previewStep }
        Divider()
        HStack {
          if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.bordered) }
          Spacer()
          Button(step == 2 ? "Open PocketCrew" : "Continue") {
            if step < 2 { step += 1 } else { finish() }
          }.buttonStyle(.borderedProminent).disabled(!stepIsValid)
        }.padding()
      }.background(Color.oat).navigationTitle("Set up your crew").pocketCrewInlineTitle().toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
      }
    }
  }

  private var progress: some View {
    HStack(spacing: 8) {
      ForEach(0..<3, id: \.self) { index in
        Capsule().fill(index <= step ? Color.evergreen : Color.ink.opacity(0.12)).frame(height: 7)
          .accessibilityLabel("Step \(index + 1)")
      }
    }.padding(.horizontal).padding(.vertical, 12)
  }

  private var familyStep: some View {
    Form {
      Section("Family") {
        TextField("Family name", text: $familyName)
        TextField("Your display name", text: $parentName)
        SecureField("Choose a 4-digit parent passcode", text: $parentPasscode)
          .pocketCrewNumericKeyboard().onChange(of: parentPasscode) { _, value in
            parentPasscode = String(value.filter(\.isNumber).prefix(4))
          }
      }
      Section("Payday") {
        Picker("Schedule", selection: $frequency) {
          ForEach(PaydayFrequency.allCases) { Text($0.title).tag($0) }
        }
        Picker("Currency", selection: $currency) {
          ForEach(["USD", "CAD", "GBP", "EUR"], id: \.self) { Text($0) }
        }
        LabeledContent("Timezone", value: TimeZone.current.identifier)
      }
    }.scrollContentBackground(.hidden)
  }

  private var childStep: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Children").font(.title2.bold())
            Text("Give every child their own settings.").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            children.append(.blank(position: children.count))
          } label: {
            Label("Add Child", systemImage: "person.badge.plus")
          }.buttonStyle(.borderedProminent)
        }
        ForEach($children) { $child in
          ChildSettingsEditor(
            child: $child, title: childTitle(child), canRemove: children.count > 1,
            onRemove: { removeChild(child.id) })
        }
        if !passcodesAreUnique {
          Label("Every profile needs a different passcode.", systemImage: "exclamationmark.shield.fill")
            .foregroundStyle(Color.coral)
        }
        Button {
          children.append(.blank(position: children.count))
        } label: {
          Label("Add Child", systemImage: "person.badge.plus")
        }.buttonStyle(.bordered)
      }.padding(16)
    }
  }

  private var previewStep: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Small steps, real lessons").font(.largeTitle.bold()).fontDesign(.rounded)
        previewRow("1", "Do the work", "Responsibilities build habits. Gigs earn money.", .sky)
        previewRow("2", "You review", "Approve, request a redo, or leave a kind note.", .sunny)
        previewRow(
          "3", "Fill the jars", "Payday splits approved earnings into Spend, Save, and Give.",
          .coral)
        if !error.isEmpty {
          Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
      }.padding()
    }
  }

  private var stepIsValid: Bool {
    switch step {
    case 0: !familyName.isEmpty && !parentName.isEmpty && parentPasscode.isFourDigitPasscode
    case 1: !children.isEmpty && children.allSatisfy(\.isComplete) && passcodesAreUnique
    default: true
    }
  }
  private func previewRow(_ number: String, _ title: String, _ detail: String, _ color: Color)
    -> some View
  {
    MobileCard {
      HStack(alignment: .top, spacing: 13) {
        Text(number).font(.headline.bold()).frame(width: 36, height: 36).background(
          color, in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.headline)
          Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
      }
    }
  }
  private func finish() {
    do {
      try store.createFamily(
        familyName: familyName, parentName: parentName, children: children, currency: currency,
        frequency: frequency, parentPasscode: parentPasscode)
      store.lock()
      didEnter = true
      dismiss()
    } catch { self.error = error.localizedDescription }
  }

  private var passcodesAreUnique: Bool {
    let values = [parentPasscode] + children.map(\.passcode)
    return Set(values.filter({ !$0.isEmpty })).count == values.filter({ !$0.isEmpty }).count
  }
  private func childTitle(_ child: ChildSetupDraft) -> String {
    let name = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty { return name }
    return "Child \((children.firstIndex(where: { $0.id == child.id }) ?? 0) + 1)"
  }
  private func removeChild(_ id: UUID) {
    guard children.count > 1 else { return }
    children.removeAll(where: { $0.id == id })
  }
}
